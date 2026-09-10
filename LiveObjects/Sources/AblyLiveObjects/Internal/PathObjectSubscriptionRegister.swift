import Ably
import Foundation

/// Registry for ``PathObject`` subscriptions and path-event dispatch. One per ``RealtimeObject``
/// (owned by ``InternalDefaultRealtimeObjects``).
///
/// ## Concurrency
///
/// The register is **queue-confined**: every entry point (`nosync_subscribe`, `nosync_unsubscribe`,
/// `nosync_notifyPathEvent`, `nosync_dispose`) runs on the objects engine's internal serial queue,
/// enforced by `dispatchPrecondition`. Subscriptions are registered from public callers via a hop
/// onto that queue (see ``DefaultPathObject/subscribe(options:listener:)``); dispatch already runs on
/// it (path notification happens inside the inbound-message apply path). There is **no lock**: the
/// mutable `subscriptions` map is plain queue-confined state.
///
/// Listener callbacks are emitted on `userCallbackQueue`, never while holding any mutex — the
/// off-lock dispatch convention that avoids re-entrancy when a callback calls back into the SDK
/// (https://github.com/ably/ably-liveobjects-swift-plugin/issues/120), matching
/// ``SubscriptionStorage``'s off-lock `async` dispatch.
///
/// ## Why not ``SubscriptionStorage``
///
/// `SubscriptionStorage` broadcasts the *same* update to every subscriber of an event name. Path
/// dispatch is per-subscription: each registration resolves its *own* covered path from the
/// candidate list (RTO24b2b, depth-windowed coverage RTO24c1), so a uniform broadcast cannot express
/// it, so an `EventEmitter`-style per-listener `apply` is used rather than reusing the
/// LiveMap/LiveCounter change coordinators verbatim. (Deviation candidate.)
///
/// Spec: `RTO24`, `RTO24a`, `RTPO19`.
internal final class PathObjectSubscriptionRegister: @unchecked Sendable {
    /// Constructs the ``PathObject`` carried by a path event, for a given segment list. Supplied by the
    /// subscribing ``DefaultPathObject`` so the register need not itself hold the channel object / core
    /// SDK. Returns `nil` when its captured context has been released, in which case the subscription is
    /// effectively dead and the event is dropped.
    internal typealias PathObjectFactory = @Sendable (_ segments: [String]) -> (any PathObject)?

    /// A single registration: the EventEmitter-`Listener` analogue plus its coverage state.
    private struct PathSubscription {
        /// The subscription's stored path, as segments (copied at subscribe time). RTPO19f.
        internal let segments: [String]
        /// The RTPO19c1 depth window; `nil` means infinite depth.
        internal let depth: Int?
        internal let listener: PathObjectSubscriptionCallback
        internal let makePathObject: PathObjectFactory
    }

    private let internalQueue: DispatchQueue
    private let userCallbackQueue: DispatchQueue

    /// Queue-confined registrations, keyed by an identity token used for deregistration. Identity
    /// keying (rather than value equality) ensures `nosync_unsubscribe` removes exactly the intended
    /// registration.
    private nonisolated(unsafe) var subscriptions: [UUID: PathSubscription] = [:]

    internal init(internalQueue: DispatchQueue, userCallbackQueue: DispatchQueue) {
        self.internalQueue = internalQueue
        self.userCallbackQueue = userCallbackQueue
    }

    /// Queue-synchronised entry point for public (off-queue) callers: hops onto the internal queue and
    /// delegates to ``nosync_subscribe(segments:depth:listener:makePathObject:)``. Mirrors the
    /// self-synchronising deregistration hop the returned ``Subscription`` already performs, so callers
    /// need not manage the queue boundary themselves. Spec: RTPO19f.
    internal func subscribe(
        segments: [String],
        depth: Int?,
        listener: @escaping PathObjectSubscriptionCallback,
        makePathObject: @escaping PathObjectFactory,
    ) -> any Subscription {
        internalQueue.ably_syncNoDeadlock {
            nosync_subscribe(segments: segments, depth: depth, listener: listener, makePathObject: makePathObject)
        }
    }

    /// Registers a subscription for `segments` with the given depth window, returning a
    /// ``Subscription`` whose `unsubscribe()` deregisters it. Spec: RTPO19f.
    internal func nosync_subscribe(
        segments: [String],
        depth: Int?,
        listener: @escaping PathObjectSubscriptionCallback,
        makePathObject: @escaping PathObjectFactory,
    ) -> any Subscription {
        dispatchPrecondition(condition: .onQueue(internalQueue))
        let id = UUID()
        subscriptions[id] = .init(segments: segments, depth: depth, listener: listener, makePathObject: makePathObject)
        let internalQueue = internalQueue
        return ClosureSubscription { [weak self] in
            // SUB2a/SUB2b: hop onto the internal queue to deregister; idempotent (a missing id is a
            // no-op), and a no-op if the register has already been released.
            internalQueue.ably_syncNoDeadlock {
                self?.nosync_unsubscribe(id: id)
            }
        }
    }

    /// Deregisters the subscription with the given identity token. Idempotent. Spec: SUB2a/SUB2b (the
    /// returned `Subscription`'s unsubscribe contract); reverses the RTPO19f registration.
    internal func nosync_unsubscribe(id: UUID) {
        dispatchPrecondition(condition: .onQueue(internalQueue))
        subscriptions.removeValue(forKey: id)
    }

    /// Dispatches one path event: each subscription covering any candidate path is notified at most
    /// once, at the first (most-preferred) covered candidate; subscriptions covering none are
    /// skipped. The listener receives a ``PathObjectSubscriptionEvent`` whose `object` points at the
    /// chosen candidate path (RTO24b2b1 / RTPO19e1) and whose `message` is the source object message
    /// (RTO24b2b2 / RTPO19e2). Callbacks are emitted on `userCallbackQueue`, off any mutex.
    ///
    /// Spec: RTO24b2b, RTO24c1.
    internal func nosync_notifyPathEvent(candidatePaths: [[String]], message: ObjectMessage?) {
        dispatchPrecondition(condition: .onQueue(internalQueue))
        for subscription in subscriptions.values {
            // RTO24b2b: first (most-preferred) covered candidate, or skip this subscription.
            guard let chosen = candidatePaths.first(where: { Self.covers(subscription, eventPath: $0) }) else {
                continue
            }
            // The captured context may have been released; drop the event if so (dead subscription).
            guard let object = subscription.makePathObject(chosen) else {
                continue
            }
            let event = PathObjectSubscriptionEvent(object: object, message: message)
            let listener = subscription.listener
            userCallbackQueue.async {
                listener(event)
            }
        }
    }

    /// Drops all subscriptions. Called when the owning ``RealtimeObject`` is disposed.
    internal func nosync_dispose() {
        dispatchPrecondition(condition: .onQueue(internalQueue))
        subscriptions.removeAll()
    }

    /// A subscription covers `eventPath` iff its stored path is a prefix of it (exact match included)
    /// and the relative depth is within the subscription's depth window. Spec: RTO24c1.
    private static func covers(_ subscription: PathSubscription, eventPath: [String]) -> Bool {
        let subPath = subscription.segments
        if subPath.count > eventPath.count {
            return false
        }
        for i in subPath.indices where eventPath[i] != subPath[i] {
            return false
        }
        guard let depth = subscription.depth else {
            return true // nil = infinite depth
        }
        return eventPath.count - subPath.count + 1 <= depth
    }
}

/// A ``Subscription`` whose `unsubscribe()` runs a closure. Calling
/// `unsubscribe()` more than once simply re-runs the closure, whose effect is idempotent. Spec:
/// `SUB2a`, `SUB2b`.
private final class ClosureSubscription: Subscription {
    private let action: @Sendable () -> Void

    internal init(action: @escaping @Sendable () -> Void) {
        self.action = action
    }

    internal func unsubscribe() {
        action()
    }
}
