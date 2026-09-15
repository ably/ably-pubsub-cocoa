// Derived from the UTS spec `objects/unit/internal_live_counter_api.md`.
//
// Drives `InternalLiveCounter`'s public-facing API — value reads, `increment`/`decrement` writes, and
// the emitted update event — through the path/instance layer (`RTPO*`/`RTINS*` delegate to `RTLC*`).
// The spec's `setup_synced_channel` mock-WebSocket fixture has no unit-tier counterpart: the standard
// pool is seeded straight into an `ObjectsPool` (`ObjectsUTS.standardPool`) behind an
// `ObjectsUTSSeededRealtimeObjects`, and the spec's `root` is a `DefaultLiveMapPathObject` over it. The
// seeded double captures each published message (`capturedMessages`, the spec's
// `captured_messages[0].state[0]` → `capturedMessages[0].operation`) AND asynchronously applies the
// operation back onto the pool entry (the RTO20 ACK echo), so the post-apply value reads
// (`value() == 150` / `== 85`) are directly portable.
//
// Deviations from the UTS spec:
// - (D-1) RTLC12e1's non-numeric table rows (`null`, `"10"`, `true`, `[1,2]`, `{n:1}`) are
//   compile-time-unrepresentable because cocoa's `increment(amount:)` takes a `Double` (objects-mapping
//   §6). Only the expressible non-finite doubles (`NaN`, `Infinity`, `-Infinity`) are ported as runtime
//   40003 assertions. `null` ≡ omitted here (nullish default), so per the spec's own note the default is
//   pinned directly via the no-argument `increment()` (increments by 1).
//
// Prose-only sections with no Test ID get no test method:
// - RTLC5a/RTLC5b (access-API preconditions) are replaced by RTO25 and live in
//   `objects/unit/realtime_object.md`.
// - RTLC12b/RTLC12c/RTLC12d (write-API preconditions) are replaced by RTO26 and live in
//   `objects/unit/realtime_object.md`.

import AblyPubSubDevice
@testable import AblyLiveObjects
import Foundation
import Testing

struct InternalLiveCounterApiTests {
    // MARK: - Fixture

    private typealias Fixture = (
        root: DefaultLiveMapPathObject,
        realtimeObjects: ObjectsUTSSeededRealtimeObjects,
        internalQueue: DispatchQueue
    )

    /// The unit stand-in for `setup_synced_channel("test")`: seeds the standard pool directly and wraps
    /// it in a `DefaultLiveMapPathObject` root (`root.get("score")` resolves to `counter:score@1000`,
    /// value 100).
    private static func makeFixture() -> Fixture {
        let internalQueue = ObjectsUTS.createInternalQueue()
        let pool = ObjectsUTS.standardPool(internalQueue: internalQueue)
        let realtimeObjects = ObjectsUTSSeededRealtimeObjects(pool: pool, internalQueue: internalQueue)
        let coreSDK = ObjectsUTSCoreSDK()
        let root = DefaultLiveMapPathObject(channelObject: realtimeObjects, coreSDK: coreSDK, internalQueue: internalQueue, segments: [])
        return (root, realtimeObjects, internalQueue)
    }

    // MARK: - RTLC5: value() returns current counter data

    // UTS: objects/unit/RTLC5/value-returns-data-0
    @Test
    func valueReturnsCurrentCounterData() throws {
        // Setup
        let root = Self.makeFixture().root

        // Assertions
        let counter = root.get(key: "score")
        #expect(try counter.asLiveCounter().value() == 100) // RTLC5c
    }

    // MARK: - RTLC12: increment sends v6 COUNTER_INC message

    // UTS: objects/unit/RTLC12/increment-sends-counter-inc-0
    @Test
    func incrementSendsCounterIncMessage() async throws {
        // Setup
        let fixture = Self.makeFixture()

        // Test Steps
        try await fixture.root.get(key: "score").asLiveCounter().increment(amount: 25)

        // Assertions
        let messages = try #require(fixture.realtimeObjects.capturedMessages)
        #expect(messages.count == 1) // RTLC12g (published via publishAndApply)
        let op = try #require(messages[0].operation)
        #expect(op.action == .known(.counterInc)) // RTLC12e2
        #expect(op.objectId == "counter:score@1000") // RTLC12e3
        #expect(op.counterInc?.number == NSNumber(value: 25)) // RTLC12e5
    }

    // MARK: - RTLC12: increment applies locally after ACK

    // UTS: objects/unit/RTLC12/increment-applies-locally-0
    @Test
    func incrementAppliesLocallyAfterAck() async throws {
        // Setup
        let fixture = Self.makeFixture()

        // Test Steps
        try await fixture.root.get(key: "score").asLiveCounter().increment(amount: 50)

        // Assertions
        // Via publishAndApply, the value reflects the change after the awaited write (100 + 50).
        #expect(try fixture.root.get(key: "score").asLiveCounter().value() == 150)
    }

    // MARK: - RTLC12e1: increment with non-number throws

    // UTS: objects/unit/RTLC12e1/increment-non-number-0
    @Test
    func incrementWithNonNumberThrows() async throws {
        // Setup
        let fixture = Self.makeFixture()

        // Test Steps
        // Spec: `AWAIT root.get("score").increment("not_a_number") FAILS WITH error`.
        // A string amount is compile-time-unrepresentable (increment(amount: Double), D-1); the
        // expressible "not finite" case is a non-finite double, which reaches the same RTLC12e1 check.
        do {
            try await fixture.root.get(key: "score").asLiveCounter().increment(amount: .nan)
            Issue.record("expected increment(NaN) to throw 40003")
        } catch {
            // Assertions — typed throws: `error` is already an ARTErrorInfo.
            #expect(error.code == 40003)
        }
    }

    // MARK: - RTLC13: decrement delegates to increment with negated amount

    // UTS: objects/unit/RTLC13/decrement-negates-0
    @Test
    func decrementNegatesAmount() async throws {
        // Setup
        let fixture = Self.makeFixture()

        // Test Steps
        try await fixture.root.get(key: "score").asLiveCounter().decrement(amount: 15)

        // Assertions
        let messages = try #require(fixture.realtimeObjects.capturedMessages)
        #expect(messages[0].operation?.counterInc?.number == NSNumber(value: -15)) // RTLC13b
        // Via publishAndApply, the value reflects the negated change (100 - 15).
        #expect(try fixture.root.get(key: "score").asLiveCounter().value() == 85)
    }

    // MARK: - RTLC11: LiveCounterUpdate emitted on increment

    // UTS: objects/unit/RTLC11/counter-update-on-inc-0
    @Test
    func counterUpdateEmittedOnIncrement() async throws {
        // Setup
        let fixture = Self.makeFixture()

        // updates = []; instance = root.get("score").instance(); instance.subscribe(...)
        guard case let .liveCounter(counter) = try fixture.root.get(key: "score").instance() else {
            Issue.record("expected a counter instance at root.get(\"score\")")
            return
        }
        let collector = ObjectsUTSEventCollector()
        try counter.subscribe(listener: collector.listener)

        // Test Steps
        // Spec: `mock_ws.send_to_client(build_object_message("test", [build_counter_inc(...7, "99",
        // "remote-site")]))`. The unit stand-in for `send_to_client` applies the inbound COUNTER_INC
        // directly to the internal node the instance wraps (the spec's literal remote serial/siteCode).
        let objectMessage = ObjectsUTS.counterIncMessage(objectId: "counter:score@1000", number: 7, serial: "99", siteCode: "remote-site")
        let operation = try #require(objectMessage.operation)
        fixture.internalQueue.ably_syncNoDeadlock {
            // Pool access is queue-confined (the seeded double's mutex asserts on-queue).
            var pool = fixture.realtimeObjects.nosync_objectsPool
            guard case let .counter(node) = pool.entries["counter:score@1000"] else {
                Issue.record("expected counter node in the seeded pool")
                return
            }
            _ = node.nosync_apply(operation, source: .channel, objectMessage: objectMessage, objectsPool: &pool)
        }

        // poll_until(updates.length >= 1): drain the callback queue (never sleep).
        let updates = await collector.events()

        // Assertions
        #expect(updates.count >= 1)
        let event = try #require(updates.first)
        #expect(event.message?.operation.counterInc?.number == 7) // RTLC11b1
    }

    // MARK: - RTLC12e1: Table-driven invalid increment amounts

    // UTS: objects/unit/RTLC12e1/increment-invalid-amounts-table-0
    @Test
    func incrementInvalidAmountsTable() async throws {
        // The spec's invalid_amounts table:
        //   { value: null,        label: "null" }        # language-applicability: null ≡ omitted here
        //   { value: NaN,         label: "NaN" }
        //   { value: Infinity,    label: "Infinity" }
        //   { value: -Infinity,   label: "-Infinity" }
        //   { value: "10",        label: "string" }      # unrepresentable: increment(amount: Double)
        //   { value: true,        label: "boolean" }     # unrepresentable
        //   { value: [1, 2],      label: "array" }       # unrepresentable
        //   { value: { n: 1 },    label: "object" }      # unrepresentable
        // Only the non-finite doubles are expressible (D-1); each throws 40003.
        let invalidAmounts: [(value: Double, label: String)] = [
            (.nan, "NaN"),
            (.infinity, "Infinity"),
            (-.infinity, "-Infinity"),
        ]

        // Test Steps
        for scenario in invalidAmounts {
            let fixture = Self.makeFixture()
            do {
                try await fixture.root.get(key: "score").asLiveCounter().increment(amount: scenario.value)
                Issue.record("expected increment(\(scenario.label)) to throw 40003")
            } catch {
                // Assertions
                #expect(error.code == 40003)
            }
        }

        // The `null` row is not applicable (null ≡ omitted): pin the default directly so a later
        // signature/coalescing change surfaces as a conscious decision — `increment()` succeeds and
        // increments by the default of 1 (100 + 1).
        let fixture = Self.makeFixture()
        try await fixture.root.get(key: "score").asLiveCounter().increment()
        #expect(try fixture.root.get(key: "score").asLiveCounter().value() == 101)
    }
}
