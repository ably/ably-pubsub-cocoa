import Foundation
import AblyPubSubDevice
import AblyPubSubDevice.Private

/// A deterministic `ARTTimeProvider` for UTS unit tests.
///
/// Both the wall clock and the continuous clock start at a fixed origin and only ever move when the test calls
/// `advanceTime(byMilliseconds:)` — nothing fires on its own, so tests are fully in control
/// (the UTS `enable_fake_timers()` / `ADVANCE_TIME(ms)` primitives).
///
/// Every block scheduled through the SDK's `scheduleAfter:queue:block:` is recorded here, which
/// means this provider doubles as the timer-leak safety net the UTS derived-tests guide asks for:
/// `cancelAllScheduled()` in teardown cancels every surviving timer, including ones the SDK may
/// have orphaned and which are no longer reachable through its public API.
final class MockTimeProvider: NSObject, TimeProvider, @unchecked Sendable {
    /// A point on / duration of the continuous clock, in the same units as `clock_gettime_nsec_np`.
    private typealias Nanoseconds = UInt64

    private let lock = NSLock()

    /// Wall-clock origin (ms since the Unix epoch): a fixed, arbitrary point by default,
    /// overridable per test for wall-clock-sensitive specs (java's `FakeClock(initialTimeMs)`).
    private var wallClockMilliseconds: Double

    init(initialWallClockMilliseconds: Double = 1_600_000_000_000) {
        wallClockMilliseconds = initialWallClockMilliseconds
        super.init()
    }

    /// Continuous-clock origin.
    private var continuousNanoseconds: Nanoseconds = 1_000_000_000

    private final class ScheduledBlock: @unchecked Sendable {
        let fireAtNanoseconds: Nanoseconds
        let queue: DispatchQueue
        let block: @Sendable () -> Void
        var isCancelled = false

        init(fireAtNanoseconds: Nanoseconds, queue: DispatchQueue, block: @escaping @Sendable () -> Void) {
            self.fireAtNanoseconds = fireAtNanoseconds
            self.queue = queue
            self.block = block
        }
    }

    /// A cancellable handle returned to the SDK for a scheduled block.
    private final class Handle: NSObject, SchedulerHandle {
        private let owner: MockTimeProvider
        fileprivate let scheduled: ScheduledBlock

        init(owner: MockTimeProvider, scheduled: ScheduledBlock) {
            self.owner = owner
            self.scheduled = scheduled
        }

        func cancel() {
            owner.cancel(scheduled)
        }
    }

    /// The fake clock's own continuous-clock instant. The system instant
    /// (`ARTSystemContinuousClockInstant`) is private to `ARTSystemTimeProvider`, so the fake
    /// provider supplies its own value type conforming to the boundary protocol.
    private final class Instant: NSObject, ContinuousClockInstant, @unchecked Sendable {
        let nanoseconds: UInt64
        init(nanoseconds: UInt64) { self.nanoseconds = nanoseconds }

        func isAfter(_ other: ContinuousClockInstant) -> Bool {
            guard let other = other as? Instant else { return false }
            return nanoseconds > other.nanoseconds
        }

        func addingDuration(_ duration: TimeInterval) -> ContinuousClockInstant {
            Instant(nanoseconds: nanoseconds + UInt64(max(0, duration) * 1_000_000_000))
        }
    }

    private var scheduledBlocks: [ScheduledBlock] = []

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    /// Count of pending (not-yet-fired, not-cancelled) blocks. Caller must hold the lock.
    private var pendingCount: Int {
        scheduledBlocks.filter { !$0.isCancelled }.count
    }

    // MARK: ARTTimeProvider

    func wallClockNow() -> Date {
        withLock { Date(timeIntervalSince1970: wallClockMilliseconds / 1000.0) }
    }

    func continuousClockNow() -> ContinuousClockInstant {
        withLock { Instant(nanoseconds: continuousNanoseconds) }
    }

    func schedule(after delay: TimeInterval, queue: DispatchQueue, block: @escaping @Sendable () -> Void) -> SchedulerHandle {
        withLock {
            rememberQueue(queue)
            let fireAt = continuousNanoseconds + Nanoseconds(max(0, delay) * 1_000_000_000)
            let scheduled = ScheduledBlock(fireAtNanoseconds: fireAt, queue: queue, block: block)
            scheduledBlocks.append(scheduled)
            return Handle(owner: self, scheduled: scheduled)
        }
    }

    // MARK: Test control

    /// Every distinct queue the SDK has scheduled a timer on. `advanceTime` barriers these to let
    /// SDK work settle around firing timers. We remember them (rather than reading the queues of the
    /// currently-pending blocks) because there are moments when no block is pending — at the leading
    /// drain before a queued handler has scheduled its timer, and between firing a timer and its
    /// cascade scheduling the next one — yet we still need to barrier the SDK's queue. The SDK only
    /// schedules timers on its internal queue, so that queue is remembered the first time any timer
    /// is scheduled (during connect for example); the callback queue isn't drained here, which is fine
    /// since the tests observe state through the internal queue, not via listener callbacks.
    private var knownQueues: [ObjectIdentifier: DispatchQueue] = [:]

    /// Caller must hold `lock`. Keyed by identity, so re-registering a queue is a no-op.
    private func rememberQueue(_ queue: DispatchQueue) {
        knownQueues[ObjectIdentifier(queue)] = queue
    }

    /// Advances both clocks by `milliseconds` and runs the SDK to quiescence:
    ///
    /// 1. Drains first, so any already-queued work (e.g. an unexpected disconnect transitioning to
    ///    DISCONNECTED) finishes *registering its timer* before the clock moves past it.
    /// 2. Advances both clocks.
    /// 3. Fires every now-due block and drains the cascade it triggers, repeating while the cascade
    ///    schedules further blocks that are themselves already due (e.g. a zero-delay reschedule).
    ///
    /// After it returns, the SDK has fully reacted to the elapsed time: state has settled and the
    /// next timer (if any) is registered. Chained retries that are scheduled *relative to the new
    /// time* remain in the future and need a subsequent `advanceTime` — matching real elapsed time.
    func advanceTime(byMilliseconds milliseconds: Double) {
        drainAllQueues()

        let target = withLock { () -> Nanoseconds in
            continuousNanoseconds = continuousNanoseconds + Nanoseconds(max(0, milliseconds) * 1_000_000)
            wallClockMilliseconds += milliseconds
            return continuousNanoseconds
        }

        while fireBlocksDue(upTo: target) {
            drainAllQueues()
        }
    }

    /// Dispatches every not-yet-fired, not-cancelled block whose fire time is `<= target` onto its
    /// target queue (in fire-time order). Returns `true` if it dispatched anything.
    private func fireBlocksDue(upTo target: Nanoseconds) -> Bool {
        let due = withLock { () -> [ScheduledBlock] in
            let due = scheduledBlocks
                .filter { !$0.isCancelled && $0.fireAtNanoseconds <= target }
                .sorted { $0.fireAtNanoseconds < $1.fireAtNanoseconds }
            scheduledBlocks.removeAll { scheduled in due.contains { $0 === scheduled } }
            return due
        }
        for scheduled in due {
            scheduled.queue.async(execute: scheduled.block)
        }
        return !due.isEmpty
    }

    /// Settles the SDK's queues until a pass no longer changes the number of scheduled timers —
    /// i.e. the work has stopped scheduling (or cancelling) timers and has quiesced. Each pass takes
    /// the lock once (snapshotting both the queues to barrier and the pending count together).
    private func drainAllQueues(maxPasses: Int = 100) {
        var previousCount = -1
        for _ in 0..<maxPasses {
            let (queues, count) = withLock { (Array(knownQueues.values), pendingCount) }
            if count == previousCount {
                return
            }
            previousCount = count
            for queue in queues {
                queue.sync {}
            }
        }
    }

    /// Number of blocks currently scheduled (not yet fired, not cancelled) — useful for asserting
    /// retry state (the counterpart of ably-java's `FakeClock.pendingTaskCount`; cocoa timers have
    /// no names, so this is a single overall count).
    var pendingScheduledCount: Int {
        withLock { pendingCount }
    }

    /// Cancels every scheduled block. Used in teardown as the timer-leak safety net.
    func cancelAllScheduled() {
        withLock { scheduledBlocks.removeAll() }
    }

    private func cancel(_ scheduled: ScheduledBlock) {
        withLock {
            scheduled.isCancelled = true
            scheduledBlocks.removeAll { $0 === scheduled }
        }
    }
}
