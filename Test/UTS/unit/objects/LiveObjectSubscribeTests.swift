// Derived from the UTS spec `objects/unit/live_object_subscribe.md`.
//
// Drives `Instance#subscribe` (RTINS16 -> RTLO4b) against the **real** `InternalDefaultRealtimeObjects`
// engine: instance-subscribe delivery is owned by the engine's apply path (a node emits to its own
// subscribers, RTLO4b4c3a) and the enriched `InstanceSubscriptionEvent.message` is the public
// `ObjectMessage` the engine derives from the inbound frame (`toPublicObjectMessage`, PAOM3). The
// standard graph is seeded straight into the engine's owned pool (`testsOnly_setPoolEntry` +
// `testsOnly_setParentReferences`) — the unit stand-in for `setup_synced_channel`, which has no
// channel/connection here — and inbound OBJECT frames are replayed via `testsOnly_applyObjectMessages`
// (the stand-in for `mock_ws.send_to_client`). Instances are obtained through the production seam
// `root.get(key:).instance()`; subscriber callbacks run on the engine's `userCallbackQueue`, drained
// with a `sync {}` barrier before asserting (the `poll_until(updates.length >= …)` stand-in — never a
// sleep). Nodes/pool are seeded at `POOL_SERIAL` so the spec's remote serials win LWW. These are
// infra-driving stand-ins, NOT deviations.
//
// Deviations from the UTS spec (see Test/UTS/deviations.md):
// - (D-1) RTLO4b4c1 noop shape: the spec models the noop increment as `counterInc: {}` (present but
//   number-less); cocoa's `WireCounterInc.number` is non-optional, so the same RTLC9h noop branch is
//   reached with an absent `counterInc` (`ObjectsUTS.counterIncNoopMessage`).
//
// Adaptations that are NOT deviations (unit-fixture shape, per objects-mapping §5/§13):
// - The spec's `Instance` is polymorphic; here it is the `Instance` enum, so `instance.subscribe(...)`
//   is reached by unwrapping to the `.liveCounter` / `.liveMap` payload (which carries `subscribe`).
// - `subscribe-no-side-effects-0` observes `channel.state`; the unit fixture has only the fixed
//   `CoreSDK` channel state, so the observable subset is that subscribe neither throws nor changes it.

import _AblyPluginSupportPrivate
import AblyPubSubDevice
@testable import AblyLiveObjects
@testable import AblyLiveObjectsTesting
import Foundation
import Testing

struct LiveObjectSubscribeTests {
    private static let channelName = "test"

    // MARK: - Fixture

    private struct Fixture {
        let engine: InternalDefaultRealtimeObjects
        let coreSDK: ObjectsUTSCoreSDK
        let internalQueue: DispatchQueue
        let userCallbackQueue: DispatchQueue
    }

    /// The unit stand-in for `{ client, channel, root, mock_ws } = AWAIT setup_synced_channel("test")`:
    /// a real engine over a fresh internal/user-callback queue pair (no channel/connection).
    private static func makeFixture() -> Fixture {
        let internalQueue = ObjectsUTS.createInternalQueue()
        let userCallbackQueue = DispatchQueue(label: "LiveObjectSubscribeTests.userCallback")
        // Same channel name as the engine: the instance wrapper projects the delivered public message
        // per PAOM3 at delivery using this coreSDK's channel name (PAOM2e).
        let coreSDK = ObjectsUTSCoreSDK(channelState: .attached, channelName: channelName)
        let engine = InternalDefaultRealtimeObjects(
            logger: TestLogger(),
            internalQueue: internalQueue,
            userCallbackQueue: userCallbackQueue,
            clock: MockSimpleClock(),
            channelName: channelName,
        )
        return Fixture(engine: engine, coreSDK: coreSDK, internalQueue: internalQueue, userCallbackQueue: userCallbackQueue)
    }

    private static func rootPath(_ f: Fixture) -> DefaultLiveMapPathObject {
        DefaultLiveMapPathObject(channelObject: f.engine, coreSDK: f.coreSDK, internalQueue: f.internalQueue, segments: [])
    }

    private static func makeCounter(objectID: String, data: Double = 0, _ f: Fixture) -> InternalDefaultLiveCounter {
        InternalDefaultLiveCounter(testsOnly_data: data, objectID: objectID, logger: TestLogger(), internalQueue: f.internalQueue, userCallbackQueue: f.userCallbackQueue, clock: MockSimpleClock())
    }

    private static func makeMap(objectID: String, data: [String: InternalObjectsMapEntry] = [:], _ f: Fixture) -> InternalDefaultLiveMap {
        InternalDefaultLiveMap(testsOnly_data: data, objectID: objectID, logger: TestLogger(), internalQueue: f.internalQueue, userCallbackQueue: f.userCallbackQueue, clock: MockSimpleClock())
    }

    /// Seeds the standard test graph (root + score/nested counters + profile/prefs maps) into the
    /// engine's owned pool, with the standard parentReferences so path resolution reaches every node.
    /// Entries are seeded at `POOL_SERIAL` ("t:0") so the spec's remote serials win per-object/per-entry
    /// LWW (RTLM9e). This is the direct-seeding stand-in for the spec's synced standard pool.
    private static func seedStandardGraph(_ f: Fixture) {
        let score = makeCounter(objectID: "counter:score@1000", data: 100, f)
        let nested = makeCounter(objectID: "counter:nested@1000", data: 5, f)
        let prefs = makeMap(objectID: "map:prefs@1000", data: ["theme": ObjectsUTS.mapEntry(data: ProtocolTypes.ObjectData(string: "dark"))], f)
        let profile = makeMap(
            objectID: "map:profile@1000",
            data: [
                "email": ObjectsUTS.mapEntry(data: ProtocolTypes.ObjectData(string: "alice@example.com")),
                "nested_counter": ObjectsUTS.mapEntry(data: ProtocolTypes.ObjectData(objectId: "counter:nested@1000")),
                "prefs": ObjectsUTS.mapEntry(data: ProtocolTypes.ObjectData(objectId: "map:prefs@1000")),
            ],
            f,
        )
        let root = makeMap(
            objectID: ObjectsPool.rootKey,
            data: [
                "name": ObjectsUTS.mapEntry(data: ProtocolTypes.ObjectData(string: "Alice")),
                "score": ObjectsUTS.mapEntry(data: ProtocolTypes.ObjectData(objectId: "counter:score@1000")),
                "profile": ObjectsUTS.mapEntry(data: ProtocolTypes.ObjectData(objectId: "map:profile@1000")),
            ],
            f,
        )
        f.engine.testsOnly_setPoolEntry(.counter(score), forObjectID: "counter:score@1000")
        f.engine.testsOnly_setPoolEntry(.counter(nested), forObjectID: "counter:nested@1000")
        f.engine.testsOnly_setPoolEntry(.map(prefs), forObjectID: "map:prefs@1000")
        f.engine.testsOnly_setPoolEntry(.map(profile), forObjectID: "map:profile@1000")
        f.engine.testsOnly_setPoolEntry(.map(root), forObjectID: ObjectsPool.rootKey)
        score.testsOnly_setParentReferences([ObjectsPool.rootKey: ["score"]])
        profile.testsOnly_setParentReferences([ObjectsPool.rootKey: ["profile"]])
        nested.testsOnly_setParentReferences(["map:profile@1000": ["nested_counter"]])
        prefs.testsOnly_setParentReferences(["map:profile@1000": ["prefs"]])
    }

    /// The `mock_ws.send_to_client` stand-in: replay inbound OBJECT frames through the engine's apply
    /// path, then drain the engine's `userCallbackQueue` (the `poll_until` stand-in — never a sleep).
    private static func applyAndDrain(_ messages: [ProtocolTypes.InboundObjectMessage], _ f: Fixture) {
        f.engine.testsOnly_applyObjectMessages(messages, source: .channel)
        f.userCallbackQueue.sync {}
    }

    /// `root.get(key).instance()` unwrapped to its `.liveCounter` payload (RTINS16 wrapping).
    private static func counterInstance(_ f: Fixture, key: String) throws -> any LiveCounterInstance {
        let instance = try #require(try Self.rootPath(f).get(key: key).instance())
        guard case let .liveCounter(counterInstance) = instance else {
            Issue.record("expected a .liveCounter instance at root.get(\"\(key)\")")
            throw CancellationError()
        }
        return counterInstance
    }

    /// `root.get(key).instance()` (or root itself when `key` is nil) unwrapped to its `.liveMap` payload.
    private static func mapInstance(_ f: Fixture, key: String?) throws -> any LiveMapInstance {
        let pathObject: any PathObject = key.map { Self.rootPath(f).get(key: $0) } ?? Self.rootPath(f)
        let instance = try #require(try pathObject.instance())
        guard case let .liveMap(mapInstance) = instance else {
            Issue.record("expected a .liveMap instance")
            throw CancellationError()
        }
        return mapInstance
    }

    // MARK: - RTLO4b: subscribe registers a listener for data updates

    // UTS: objects/unit/RTLO4b/subscribe-receives-updates-0
    @Test
    func subscribeReceivesUpdates() throws {
        // Setup
        let f = Self.makeFixture()
        Self.seedStandardGraph(f)
        let updates = ObjectsUTSInstanceEventCollector()
        let instance = try Self.counterInstance(f, key: "score")
        let sub = try instance.subscribe(listener: updates.listener)

        // Test Steps
        Self.applyAndDrain([ObjectsUTS.counterIncMessage(objectId: "counter:score@1000", number: 7, serial: "99", siteCode: "remote")], f)

        // Assertions
        // ASSERT sub IS Subscription — guaranteed by the static return type `any Subscription`.
        _ = sub
        #expect(updates.events.count == 1) // ASSERT updates.length == 1
    }

    // MARK: - RTLO4b7: subscribe returns a Subscription with an unsubscribe method

    // UTS: objects/unit/RTLO4b7/subscribe-returns-subscription-0
    @Test
    func subscribeReturnsSubscription() throws {
        // Setup
        let f = Self.makeFixture()
        Self.seedStandardGraph(f)
        let instance = try Self.counterInstance(f, key: "score")

        // Test Steps
        let sub = try instance.subscribe { _ in }

        // Assertions
        // ASSERT sub IS Subscription — the static type is `any Subscription`.
        // ASSERT sub.unsubscribe IS Function — `unsubscribe()` is a member of `Subscription`; call it.
        sub.unsubscribe()
    }

    // MARK: - RTLO4b7: Subscription#unsubscribe stops delivery

    // UTS: objects/unit/RTLO4b7/subscription-unsubscribe-stops-delivery-0
    @Test
    func subscriptionUnsubscribeStopsDelivery() throws {
        // Setup
        let f = Self.makeFixture()
        Self.seedStandardGraph(f)
        let updates = ObjectsUTSInstanceEventCollector()
        let control = ObjectsUTSInstanceEventCollector()
        let instance = try Self.counterInstance(f, key: "score")
        let sub = try instance.subscribe(listener: updates.listener)

        // Test Steps
        Self.applyAndDrain([ObjectsUTS.counterIncMessage(objectId: "counter:score@1000", number: 5, serial: "01", siteCode: "remote")], f)
        #expect(updates.events.count == 1) // poll_until(updates.length >= 1)

        sub.unsubscribe()

        // Per the Negative-assertion quiescence pattern: subscribe a control listener that WILL fire on
        // the same dispatch as the message under test, then AWAIT it before asserting `updates` is
        // unchanged.
        let controlSub = try instance.subscribe(listener: control.listener)
        defer { controlSub.unsubscribe() }
        Self.applyAndDrain([ObjectsUTS.counterIncMessage(objectId: "counter:score@1000", number: 10, serial: "02", siteCode: "remote")], f)
        #expect(control.events.count >= 1) // poll_until(control.length >= 1)

        // Assertions
        // Control delivered, so the unsubscribed listener would also have run had it still been registered.
        #expect(updates.events.count == 1) // ASSERT updates.length == 1
    }

    // MARK: - RTLO4b7: Subscription#unsubscribe is idempotent

    // UTS: objects/unit/RTLO4b7/subscription-unsubscribe-idempotent-0
    @Test
    func subscriptionUnsubscribeIsIdempotent() throws {
        // Setup
        let f = Self.makeFixture()
        Self.seedStandardGraph(f)
        let instance = try Self.counterInstance(f, key: "score")
        let sub = try instance.subscribe { _ in }

        // Test Steps
        sub.unsubscribe()
        sub.unsubscribe()

        // Assertions
        // No error thrown — both calls complete without error.
    }

    // MARK: - RTLO4b4c1: noop update does not trigger the listener

    // UTS: objects/unit/RTLO4b4c1/noop-no-trigger-0
    @Test
    func noopUpdateDoesNotTriggerListener() throws {
        // Setup
        let f = Self.makeFixture()
        Self.seedStandardGraph(f)
        let updates = ObjectsUTSInstanceEventCollector()
        let control = ObjectsUTSInstanceEventCollector()
        let instance = try Self.counterInstance(f, key: "score")
        let sub = try instance.subscribe(listener: updates.listener)
        defer { sub.unsubscribe() }

        // Test Steps
        Self.applyAndDrain([ObjectsUTS.counterIncMessage(objectId: "counter:score@1000", number: 5, serial: "01", siteCode: "remote")], f)
        #expect(updates.events.count == 1) // poll_until(updates.length >= 1)

        // Serial "02" passes the newness check (RTLO4a6); an increment with no `number` is the noop
        // (RTLC9h). Use a number-less COUNTER_INC so it exercises the real RTLC9h/RTLO4b4c1 noop branch
        // (a `number: 0` would EXIST per RTLC9g and produce a non-noop update with amount 0).
        Self.applyAndDrain([ObjectsUTS.counterIncNoopMessage(objectId: "counter:score@1000", serial: "02", siteCode: "remote")], f)

        // Negative-assertion quiescence: drive a follow-up "03" increment and await it via a SEPARATE
        // control listener (its own array). Because "03" is dispatched after the noop "02" on the same
        // channel, once the control fires the noop has certainly been processed. The control is kept
        // separate so it does not inflate `updates`.
        let controlSub = try instance.subscribe(listener: control.listener)
        Self.applyAndDrain([ObjectsUTS.counterIncMessage(objectId: "counter:score@1000", number: 3, serial: "03", siteCode: "remote")], f)
        #expect(control.events.count >= 1) // poll_until(control.length >= 1)
        controlSub.unsubscribe()

        // Assertions
        // The noop "02" produced no LiveObjectUpdate, so the original listener fired only for "01" and
        // "03" -> updates.length == 2. (The separate control listener only provides the quiescence
        // barrier; had the noop wrongly fired, updates.length would be 3.)
        #expect(updates.events.count == 2) // ASSERT updates.length == 2
    }

    // MARK: - RTLO4b6: subscribe has no side effects

    // UTS: objects/unit/RTLO4b6/subscribe-no-side-effects-0
    @Test
    func subscribeHasNoSideEffects() throws {
        // Setup
        let f = Self.makeFixture()
        Self.seedStandardGraph(f)
        let stateBefore = f.coreSDK.nosync_channelState
        let instance = try Self.counterInstance(f, key: "score")

        // Test Steps
        let sub = try instance.subscribe { _ in }
        defer { sub.unsubscribe() }

        // Assertions
        #expect(f.coreSDK.nosync_channelState == stateBefore) // ASSERT channel.state == state_before
    }

    // MARK: - RTLO4b: subscribe on a map instance receives a LiveMapUpdate

    // UTS: objects/unit/RTLO4b/subscribe-map-update-0
    @Test
    func subscribeOnMapReceivesUpdate() throws {
        // Setup
        let f = Self.makeFixture()
        Self.seedStandardGraph(f)
        let updates = ObjectsUTSInstanceEventCollector()
        let instance = try Self.mapInstance(f, key: nil) // root map
        let sub = try instance.subscribe(listener: updates.listener)
        defer { sub.unsubscribe() }

        // Test Steps
        Self.applyAndDrain([ObjectsUTS.mapSetMessage(objectId: ObjectsPool.rootKey, key: "name", value: ProtocolTypes.ObjectData(string: "Bob"), serial: StandardTestPool.remoteSerial(0), siteCode: "remote")], f)

        // Assertions
        #expect(updates.events.count == 1) // ASSERT updates.length == 1
    }

    // MARK: - RTLO4b4c3c: tombstone deregisters all Instance#subscribe listeners

    // UTS: objects/unit/RTLO4b4c3c/tombstone-deregisters-listeners-0
    @Test
    func tombstoneDeregistersAllListeners() throws {
        // Setup
        let f = Self.makeFixture()
        Self.seedStandardGraph(f)
        let updatesA = ObjectsUTSInstanceEventCollector()
        let updatesB = ObjectsUTSInstanceEventCollector()
        let control = ObjectsUTSInstanceEventCollector()
        let instance = try Self.counterInstance(f, key: "score")
        let subA = try instance.subscribe(listener: updatesA.listener)
        let subB = try instance.subscribe(listener: updatesB.listener)
        defer { subA.unsubscribe(); subB.unsubscribe() }

        // Test Steps
        // Send an OBJECT_DELETE which causes a tombstone.
        Self.applyAndDrain([ObjectsUTS.objectDeleteMessage(objectId: "counter:score@1000", serial: "50", siteCode: "remote")], f)

        // Both listeners should have received the tombstone update.
        #expect(updatesA.events.count == 1)
        #expect(updatesA.events.first?.message?.operation.action == .objectDelete)
        #expect(updatesB.events.count == 1)
        #expect(updatesB.events.first?.message?.operation.action == .objectDelete)

        // QUIESCENCE: a tombstoned object ignores further operations (RTLC7e), so neither the
        // deregistered listeners nor a fresh listener on counter:score@1000 would ever fire — use a
        // SEPARATE LIVE object: subscribe a control listener to map:profile@1000 and drive an
        // observable update on it AFTER the message under test. Messages are processed in order, so once
        // the control fires, "51" has also been processed.
        let controlInstance = try Self.mapInstance(f, key: "profile")
        let controlSub = try controlInstance.subscribe(listener: control.listener)
        defer { controlSub.unsubscribe() }
        Self.applyAndDrain([ObjectsUTS.counterIncMessage(objectId: "counter:score@1000", number: 3, serial: "51", siteCode: "remote")], f)
        Self.applyAndDrain([ObjectsUTS.mapSetMessage(objectId: "map:profile@1000", key: "quiescence_probe", value: ProtocolTypes.ObjectData(string: "x"), serial: "52", siteCode: "remote")], f)
        #expect(control.events.count >= 1) // poll_until(control.length >= 1)

        // Assertions
        // Control delivered, so any still-registered original listener would also have run.
        #expect(updatesA.events.count == 1) // ASSERT updates_a.length == 1
        #expect(updatesB.events.count == 1) // ASSERT updates_b.length == 1
    }

    // MARK: - RTLO4b4c3c: tombstone on an already-zero counter still fires then deregisters

    // UTS: objects/unit/RTLO4b4c3c/tombstone-zero-value-counter-tears-down-0
    @Test
    func tombstoneOnZeroValueCounterTearsDown() throws {
        // Setup
        let f = Self.makeFixture()
        Self.seedStandardGraph(f)
        let updatesA = ObjectsUTSInstanceEventCollector()
        let updatesB = ObjectsUTSInstanceEventCollector()
        let control = ObjectsUTSInstanceEventCollector()
        let instance = try Self.counterInstance(f, key: "score")

        // Drive the counter (100 in the standard pool) down to 0 BEFORE registering the listeners under
        // test, so they observe only the tombstone. poll_until(value() == 0) is the quiescence barrier
        // that the increment has been applied before we subscribe, so the "-100" update is not seen by
        // them. (applyAndDrain is synchronous, so the increment is fully applied before we subscribe.)
        Self.applyAndDrain([ObjectsUTS.counterIncMessage(objectId: "counter:score@1000", number: -100, serial: "40", siteCode: "remote")], f)
        #expect(try Self.rootPath(f).get(key: "score").asLiveCounter().value() == 0) // poll_until(root.get("score").value() == 0)

        let subA = try instance.subscribe(listener: updatesA.listener)
        let subB = try instance.subscribe(listener: updatesB.listener)
        defer { subA.unsubscribe(); subB.unsubscribe() }

        // Test Steps
        // OBJECT_DELETE tombstones the already-zero counter (zero-delta diff, RTLC14c -> NOT a no-op).
        Self.applyAndDrain([ObjectsUTS.objectDeleteMessage(objectId: "counter:score@1000", serial: "50", siteCode: "remote")], f)

        // Both listeners received the tombstone update even though the counter data did not change (0 -> 0).
        #expect(updatesA.events.count == 1)
        #expect(updatesA.events.first?.message?.operation.action == .objectDelete)
        #expect(updatesB.events.count == 1)
        #expect(updatesB.events.first?.message?.operation.action == .objectDelete)

        // Prove deregistration. As in the populated teardown case, a tombstoned object ignores further
        // ops (RTLC7e), so neither the deregistered listeners nor a fresh listener on counter:score@1000
        // could ever fire — use a SEPARATE LIVE object (map:profile@1000) as the quiescence barrier.
        // Messages are processed in order, so once the control fires, the follow-up "51" has also been
        // processed.
        let controlInstance = try Self.mapInstance(f, key: "profile")
        let controlSub = try controlInstance.subscribe(listener: control.listener)
        defer { controlSub.unsubscribe() }
        Self.applyAndDrain([ObjectsUTS.counterIncMessage(objectId: "counter:score@1000", number: 3, serial: "51", siteCode: "remote")], f)
        Self.applyAndDrain([ObjectsUTS.mapSetMessage(objectId: "map:profile@1000", key: "quiescence_probe", value: ProtocolTypes.ObjectData(string: "x"), serial: "52", siteCode: "remote")], f)
        #expect(control.events.count >= 1) // poll_until(control.length >= 1)

        // Assertions
        // Control delivered, so any still-registered original listener would also have run: the
        // tombstone deregistered them per RTLO4b4c3c.
        #expect(updatesA.events.count == 1) // ASSERT updates_a.length == 1
        #expect(updatesB.events.count == 1) // ASSERT updates_b.length == 1
    }

    // MARK: - RTLO4b4d: the event carries the source public ObjectMessage

    // UTS: objects/unit/RTLO4b4d/update-has-object-message-0
    @Test
    func updateCarriesSourceObjectMessage() throws {
        // Setup
        let f = Self.makeFixture()
        Self.seedStandardGraph(f)
        let updates = ObjectsUTSInstanceEventCollector()
        let instance = try Self.counterInstance(f, key: "score")
        let sub = try instance.subscribe(listener: updates.listener)
        defer { sub.unsubscribe() }

        // Test Steps
        Self.applyAndDrain([ObjectsUTS.counterIncMessage(objectId: "counter:score@1000", number: 7, serial: "99", siteCode: "remote")], f)

        // Assertions
        #expect(updates.events.count == 1) // ASSERT updates.length == 1
        let message = try #require(updates.events.first?.message) // ASSERT updates[0].message IS NOT null
        #expect(message.serial == "99") // ASSERT updates[0].message.serial == "99"
        #expect(message.siteCode == "remote") // ASSERT updates[0].message.siteCode == "remote"
        #expect(message.operation.action == .counterInc) // ASSERT updates[0].message.operation.action == "COUNTER_INC"
        #expect(message.operation.objectId == "counter:score@1000") // ASSERT updates[0].message.operation.objectId == "counter:score@1000"
    }

    // MARK: - RTLO4b4e: tombstone update identified by OBJECT_DELETE action

    // UTS: objects/unit/RTLO4b4e/tombstone-flag-true-0
    @Test
    func tombstoneUpdateIdentifiedByObjectDeleteAction() throws {
        // Setup
        let f = Self.makeFixture()
        Self.seedStandardGraph(f)
        let updates = ObjectsUTSInstanceEventCollector()
        let instance = try Self.counterInstance(f, key: "score")
        let sub = try instance.subscribe(listener: updates.listener)
        defer { sub.unsubscribe() }

        // Test Steps
        Self.applyAndDrain([ObjectsUTS.objectDeleteMessage(objectId: "counter:score@1000", serial: "50", siteCode: "remote")], f)

        // Assertions
        #expect(updates.events.count == 1) // ASSERT updates.length == 1
        #expect(updates.events.first?.message?.operation.action == .objectDelete) // ASSERT updates[0].message.operation.action == "OBJECT_DELETE"
    }

    // MARK: - RTLO4b4e: normal update carries a non-tombstone action

    // UTS: objects/unit/RTLO4b4e/tombstone-flag-false-0
    @Test
    func normalUpdateCarriesNonTombstoneAction() throws {
        // Setup
        let f = Self.makeFixture()
        Self.seedStandardGraph(f)
        let updates = ObjectsUTSInstanceEventCollector()
        let instance = try Self.counterInstance(f, key: "score")
        let sub = try instance.subscribe(listener: updates.listener)
        defer { sub.unsubscribe() }

        // Test Steps
        Self.applyAndDrain([ObjectsUTS.counterIncMessage(objectId: "counter:score@1000", number: 7, serial: "99", siteCode: "remote")], f)

        // Assertions
        #expect(updates.events.count == 1) // ASSERT updates.length == 1
        #expect(updates.events.first?.message?.operation.action == .counterInc) // ASSERT updates[0].message.operation.action == "COUNTER_INC"
    }
}
