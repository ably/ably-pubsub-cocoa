import _AblyPluginSupportPrivate
@testable import AblyLiveObjects
@testable import AblyLiveObjectsTesting
import AblyPubSubDevice
import Foundation
import Testing

/// Tests for the Phase 4 (part 2) path-subscription layer: ``PathObjectSubscriptionRegister``, its
/// depth-windowed coverage ranking (RTO24), and the `notifyPathSubscriptions` fan-out wired into the
/// inbound-operation apply path (RTLO4b4c3b -> RTO24b).
///
/// Unlike the part-1 resolution/read tests (which drive a lightweight `SeededRealtimeObjects`
/// double), these must drive the **real** ``InternalDefaultRealtimeObjects``, since path dispatch is
/// owned by the engine's apply path. Objects are seeded into the engine's owned pool via
/// `testsOnly_setPoolEntry`, the parent-reference graph via each object's `testsOnly_setParentReferences`,
/// and updates are driven via `testsOnly_applyObjectMessages` (the gated RTO9 apply path).
///
/// Subscriber callbacks are emitted on the engine's `userCallbackQueue` (off any mutex — issue #120).
/// Each test drains that serial queue with a `sync {}` barrier before asserting.
struct PathObjectSubscriptionTests {
    private static let channelName = "test-channel"

    // MARK: - Fixture

    private struct Fixture {
        let engine: InternalDefaultRealtimeObjects
        let coreSDK: MockCoreSDK
        let internalQueue: DispatchQueue
        let userCallbackQueue: DispatchQueue
    }

    /// Thread-safe collector for the events delivered to a path subscription.
    private final class EventCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var storedEvents: [PathObjectSubscriptionEvent] = []

        func record(_ event: PathObjectSubscriptionEvent) {
            lock.withLock { storedEvents.append(event) }
        }

        var events: [PathObjectSubscriptionEvent] {
            lock.withLock { storedEvents }
        }

        /// The `.path` of every delivered event, sorted (delivery order across paths is unspecified).
        var sortedPaths: [String] {
            events.map(\.object.path).sorted()
        }
    }

    private static func makeFixture(channelState: _AblyPluginSupportPrivate.RealtimeChannelState = .attached) -> Fixture {
        let internalQueue = TestFactories.createInternalQueue()
        // A dedicated serial queue (not `.main`) so tests can drain it with a `sync {}` barrier.
        let userCallbackQueue = DispatchQueue(label: "PathObjectSubscriptionTests.userCallback")
        let coreSDK = MockCoreSDK(channelState: channelState, internalQueue: internalQueue)
        let engine = InternalDefaultRealtimeObjects(
            logger: TestLogger(),
            internalQueue: internalQueue,
            userCallbackQueue: userCallbackQueue,
            clock: MockSimpleClock(),
            channelName: channelName,
        )
        return Fixture(engine: engine, coreSDK: coreSDK, internalQueue: internalQueue, userCallbackQueue: userCallbackQueue)
    }

    /// A ``DefaultLiveMapPathObject`` rooted at the channel's root map (empty path), backed by the
    /// real engine.
    private static func rootPath(_ fixture: Fixture) -> DefaultLiveMapPathObject {
        DefaultLiveMapPathObject(channelObject: fixture.engine, coreSDK: fixture.coreSDK, internalQueue: fixture.internalQueue, segments: [])
    }

    private static func makeCounter(objectID: String, _ fixture: Fixture) -> InternalDefaultLiveCounter {
        InternalDefaultLiveCounter.createZeroValued(
            objectID: objectID,
            logger: TestLogger(),
            internalQueue: fixture.internalQueue,
            userCallbackQueue: fixture.userCallbackQueue,
            clock: MockSimpleClock(),
        )
    }

    private static func makeMap(objectID: String, data: [String: InternalObjectsMapEntry] = [:], _ fixture: Fixture) -> InternalDefaultLiveMap {
        InternalDefaultLiveMap(
            testsOnly_data: data,
            objectID: objectID,
            logger: TestLogger(),
            internalQueue: fixture.internalQueue,
            userCallbackQueue: fixture.userCallbackQueue,
            clock: MockSimpleClock(),
        )
    }

    /// Applies inbound operation messages through the gated engine apply path, then drains the user
    /// callback queue so any dispatched listener has run before the caller asserts.
    private static func applyAndDrain(_ messages: [ProtocolTypes.InboundObjectMessage], _ fixture: Fixture) {
        fixture.engine.testsOnly_applyObjectMessages(messages, source: .channel)
        fixture.userCallbackQueue.sync {}
    }

    /// Applies a self-contained `OBJECT_SYNC` (nil channelSerial, RTO5a5) through the engine, then
    /// drains the user callback queue so any dispatched listener has run before the caller asserts.
    private static func syncAndDrain(_ messages: [ProtocolTypes.InboundObjectMessage], _ fixture: Fixture) {
        fixture.internalQueue.ably_syncNoDeadlock {
            fixture.engine.nosync_handleObjectSyncProtocolMessage(
                objectMessages: messages,
                protocolMessageChannelSerial: nil,
            )
        }
        fixture.userCallbackQueue.sync {}
    }

    // MARK: - Basic delivery (RTPO19, RTO24b)

    // @spec RTO24b2a2 - a MAP_SET on the root notifies a subscription at the changed key's deeper path
    // @spec RTPO19e1 - the event's object points at the path where the change occurred
    // @spec RTPO19e2 - the event carries the source object message
    @Test
    func subscribeReceivesOnChangedKeyPathWithObjectAndMessage() throws {
        let fixture = Self.makeFixture()
        let collector = EventCollector()

        // Subscribe at "k"; a MAP_SET of root["k"] surfaces as the deeper candidate root-path + "k".
        let subscription = try Self.rootPath(fixture).get(key: "k").subscribe { collector.record($0) }
        defer { subscription.unsubscribe() }

        let message = TestFactories.mapSetOperationMessage(objectId: ObjectsPool.rootKey, key: "k", value: "v", serial: "ts1", siteCode: "site1")
        Self.applyAndDrain([message], fixture)

        #expect(collector.events.count == 1)
        let event = try #require(collector.events.first)
        // RTPO19e1: object at the changed path, and it resolves to the just-set value.
        #expect(event.object.path == "k")
        #expect(try event.object.type() == .string)
        // RTPO19e2: the PAOM3 public message that triggered the event.
        #expect(event.message == message.toPublicObjectMessage(channelName: Self.channelName))
    }

    // PAOM3b: the public `ObjectMessage.channel` reflects the real channel name that the
    // engine was constructed with (in production, bound from the `nameForChannel:` plugin bridge in
    // `DefaultInternalPlugin.nosync_prepare`) — no longer the former `""` placeholder.
    // @spec PAOM3b
    @Test
    func deliveredMessageChannelReflectsRealChannelName() throws {
        let fixture = Self.makeFixture()
        let collector = EventCollector()

        let subscription = try Self.rootPath(fixture).get(key: "k").subscribe { collector.record($0) }
        defer { subscription.unsubscribe() }

        let message = TestFactories.mapSetOperationMessage(objectId: ObjectsPool.rootKey, key: "k", value: "v", serial: "ts1", siteCode: "site1")
        Self.applyAndDrain([message], fixture)

        let event = try #require(collector.events.first)
        #expect(event.message?.channel == Self.channelName)
        // Guards against a regression to the empty-string placeholder.
        #expect(event.message?.channel.isEmpty == false)
    }

    // @spec RTO24b2a1 - a subscription at the updated object's own path is the most-preferred candidate
    @Test
    func subscribeOnRootReceivesObjectOwnPath() throws {
        let fixture = Self.makeFixture()
        let collector = EventCollector()

        // Subscribe at the root itself (empty path). The MAP_SET updates the root object, whose own
        // path ([]) is the most-preferred candidate, so the chosen path is the empty root path.
        let subscription = try Self.rootPath(fixture).subscribe { collector.record($0) }
        defer { subscription.unsubscribe() }

        Self.applyAndDrain([TestFactories.mapSetOperationMessage(objectId: ObjectsPool.rootKey, key: "k", value: "v", serial: "ts1", siteCode: "site1")], fixture)

        #expect(collector.events.count == 1)
        #expect(collector.events.first?.object.path.isEmpty == true)
    }

    // MARK: - Depth-window coverage (RTO24c1)

    // MARK: - Unsubscribe (SUB2)

    // @spec SUB2a - unsubscribe stops further delivery
    @Test
    func unsubscribeStopsDelivery() throws {
        let fixture = Self.makeFixture()
        let collector = EventCollector()

        let subscription = try Self.rootPath(fixture).subscribe { collector.record($0) }
        subscription.unsubscribe()
        // SUB2b: a second unsubscribe is a harmless no-op.
        subscription.unsubscribe()

        Self.applyAndDrain([TestFactories.mapSetOperationMessage(objectId: ObjectsPool.rootKey, key: "k", value: "v", serial: "ts1", siteCode: "site1")], fixture)

        #expect(collector.events.isEmpty)
    }

    // MARK: - Depth validation (RTPO19c1a)

    // A positive depth (and no options) is accepted.
    @Test
    func positiveAndNilDepthAccepted() throws {
        let fixture = Self.makeFixture()
        let root = Self.rootPath(fixture)
        // Neither should throw.
        try root.subscribe(options: .init(depth: 1)) { _ in }.unsubscribe()
        try root.subscribe(options: nil) { _ in }.unsubscribe()
    }

    // MARK: - Access-config guard (RTPO19b)

    // @specPartial RTPO19b - subscribe runs the access-API guard; the implementable subset is the
    // channel-state check (a DETACHED/FAILED channel is rejected). The object-mode / echo checks need
    // core accessors that the plugin API does not expose (see ChannelConfigGuards).
    @Test(arguments: [_AblyPluginSupportPrivate.RealtimeChannelState.detached, .failed])
    func subscribeRejectedInUnusableChannelState(state: _AblyPluginSupportPrivate.RealtimeChannelState) throws {
        let fixture = Self.makeFixture(channelState: state)

        #expect(throws: ARTErrorInfo.self) {
            _ = try Self.rootPath(fixture).subscribe { _ in }
        }
    }

    // MARK: - Tombstone behaviour (RTLO4b4c3c1)

    // @spec RTLO4b4c3c1 - a tombstone update is delivered to path subscriptions, which are NOT torn
    // down afterwards (unlike instance listeners, RTLO4b4c3c). A later update is still delivered.
    @Test
    func tombstoneIsDeliveredAndDoesNotTearDownPathSubscriptions() throws {
        let fixture = Self.makeFixture()
        let collector = EventCollector()

        // A nested counter reachable from root at "cnt".
        let counter = Self.makeCounter(objectID: "counter:c@1", fixture)
        fixture.engine.testsOnly_setPoolEntry(.counter(counter), forObjectID: "counter:c@1")
        counter.testsOnly_setParentReferences([ObjectsPool.rootKey: ["cnt"]])

        // Subscribe at the root with infinite depth so it covers both the delete and a later root set.
        let subscription = try Self.rootPath(fixture).subscribe { collector.record($0) }
        defer { subscription.unsubscribe() }

        // 1) OBJECT_DELETE tombstones the counter — a non-noop tombstone update fans out to the path sub.
        Self.applyAndDrain([TestFactories.objectDeleteOperationMessage(objectId: "counter:c@1", serial: "ts1", siteCode: "site1")], fixture)
        #expect(collector.events.count == 1)
        #expect(collector.events.first?.object.path == "cnt")

        // 2) A subsequent, unrelated update still reaches the same subscription — proving the tombstone
        // teardown (RTLO4b4c3c) did not deregister it (RTLO4b4c3c1).
        Self.applyAndDrain([TestFactories.mapSetOperationMessage(objectId: ObjectsPool.rootKey, key: "k", value: "v", serial: "ts2", siteCode: "site1")], fixture)
        #expect(collector.events.count == 2)
        #expect(collector.events.last?.object.path.isEmpty == true)
    }

    // MARK: - Multi-path (diamond) delivery via getFullPaths (RTO24b1/RTO24b2)

    // @spec RTO24b2 - one path event is dispatched per full path to the updated object
    @Test
    func diamondGraphDeliversOncePerPath() throws {
        let fixture = Self.makeFixture()
        let collector = EventCollector()

        // Diamond: root -"a"-> map:a -"x"-> counter:c, and root -"b"-> map:b -"y"-> counter:c.
        // counter:c therefore has two full paths: ["a","x"] and ["b","y"].
        let mapA = Self.makeMap(objectID: "map:a@1", fixture)
        let mapB = Self.makeMap(objectID: "map:b@1", fixture)
        let counter = Self.makeCounter(objectID: "counter:c@1", fixture)
        fixture.engine.testsOnly_setPoolEntry(.map(mapA), forObjectID: "map:a@1")
        fixture.engine.testsOnly_setPoolEntry(.map(mapB), forObjectID: "map:b@1")
        fixture.engine.testsOnly_setPoolEntry(.counter(counter), forObjectID: "counter:c@1")
        mapA.testsOnly_setParentReferences([ObjectsPool.rootKey: ["a"]])
        mapB.testsOnly_setParentReferences([ObjectsPool.rootKey: ["b"]])
        counter.testsOnly_setParentReferences(["map:a@1": ["x"], "map:b@1": ["y"]])

        // A single root subscription (infinite depth) covers both full paths, so it is notified twice
        // — once per path event (RTO24b2).
        let subscription = try Self.rootPath(fixture).subscribe { collector.record($0) }
        defer { subscription.unsubscribe() }

        Self.applyAndDrain([TestFactories.counterIncOperationMessage(objectId: "counter:c@1", number: 5, serial: "ts1", siteCode: "site1")], fixture)

        #expect(collector.events.count == 2)
        #expect(collector.sortedPaths == ["a.x", "b.y"])
    }

    // MARK: - Sync-originated updates (RTLO4b4c3b via OBJECT_SYNC; message nil per RTO4b2a)

    // @spec RTO4b2a - a sync-originated update carries no public message
    @Test
    func syncAppliedMapChangeDeliversWithNilMessage() throws {
        let fixture = Self.makeFixture()
        let collector = EventCollector()

        // Subscribe at "k"; the engine's root starts empty, so a sync stating root["k"] = "v"
        // produces an `updated` diff for "k" on the (existing) root object.
        let subscription = try Self.rootPath(fixture).get(key: "k").subscribe { collector.record($0) }
        defer { subscription.unsubscribe() }

        let (key, entry) = TestFactories.stringMapEntry(key: "k", value: "v")
        Self.syncAndDrain([TestFactories.rootObjectMessage(entries: [key: entry])], fixture)

        #expect(collector.events.count == 1)
        let event = try #require(collector.events.first)
        #expect(event.object.path == "k")
        #expect(event.message == nil) // RTO4b2a
    }

    // A counter changed by sync dispatches a path event at its own full path (RTO24b2a1), with nil
    // message. The root is re-stated with identical data so its diff collapses to noop and only the
    // counter's update dispatches.
    @Test
    func syncAppliedCounterChangeDeliversOnOwnPath() throws {
        let fixture = Self.makeFixture()
        let collector = EventCollector()

        // Seed: root -"cnt"-> counter:c (counter zero-valued). The sync re-states the same root data
        // (noop diff for root) and a new counter value of 100 (non-noop counter diff).
        let counter = Self.makeCounter(objectID: "counter:c@1", fixture)
        fixture.engine.testsOnly_setPoolEntry(.counter(counter), forObjectID: "counter:c@1")
        let rootData = ["cnt": TestFactories.internalMapEntry(data: ProtocolTypes.ObjectData(objectId: "counter:c@1"))]
        fixture.engine.testsOnly_setPoolEntry(.map(Self.makeMap(objectID: ObjectsPool.rootKey, data: rootData, fixture)), forObjectID: ObjectsPool.rootKey)

        let subscription = try Self.rootPath(fixture).get(key: "cnt").subscribe(options: .init(depth: 1)) { collector.record($0) }
        defer { subscription.unsubscribe() }

        Self.syncAndDrain(
            [
                TestFactories.rootObjectMessage(entries: ["cnt": TestFactories.mapEntry(data: ProtocolTypes.ObjectData(objectId: "counter:c@1"))]),
                TestFactories.counterObjectMessage(objectId: "counter:c@1", count: 100),
            ],
            fixture,
        )

        #expect(collector.events.count == 1)
        let event = try #require(collector.events.first)
        #expect(event.object.path == "cnt")
        #expect(event.message == nil) // RTO4b2a
    }

    // @spec RTLO4b4c1 - a sync that changes nothing (empty diff -> noop) dispatches no path events
    @Test
    func noChangeSyncEmitsNothing() throws {
        let fixture = Self.makeFixture()
        let collector = EventCollector()

        // Seed root["k"] = "v", then sync exactly the same data — the RTLM22 diff is empty, which
        // collapses to noop, so nothing is dispatched.
        let rootData = ["k": TestFactories.internalMapEntry(data: ProtocolTypes.ObjectData(string: "v"))]
        fixture.engine.testsOnly_setPoolEntry(.map(Self.makeMap(objectID: ObjectsPool.rootKey, data: rootData, fixture)), forObjectID: ObjectsPool.rootKey)

        // Root subscription with infinite depth — covers every possible candidate.
        let subscription = try Self.rootPath(fixture).subscribe { collector.record($0) }
        defer { subscription.unsubscribe() }

        let (key, entry) = TestFactories.stringMapEntry(key: "k", value: "v")
        Self.syncAndDrain([TestFactories.rootObjectMessage(entries: [key: entry])], fixture)

        #expect(collector.events.isEmpty)
    }

    // @spec RTO5c10 - the parent-reference rebuild runs before sync notifications, so a path event
    // for an object re-parented during the sync is delivered at its NEW path
    @Test
    func reParentedObjectDeliversOnNewPathAfterRebuild() throws {
        let fixture = Self.makeFixture()
        let newPathCollector = EventCollector()
        let oldPathCollector = EventCollector()

        // Seed: root -"old"-> counter:c (zero-valued). The sync moves the counter to root["new"]
        // (dropping "old") and changes its value to 100.
        let counter = Self.makeCounter(objectID: "counter:c@1", fixture)
        fixture.engine.testsOnly_setPoolEntry(.counter(counter), forObjectID: "counter:c@1")
        counter.testsOnly_setParentReferences([ObjectsPool.rootKey: ["old"]])
        let rootData = ["old": TestFactories.internalMapEntry(data: ProtocolTypes.ObjectData(objectId: "counter:c@1"))]
        fixture.engine.testsOnly_setPoolEntry(.map(Self.makeMap(objectID: ObjectsPool.rootKey, data: rootData, fixture)), forObjectID: ObjectsPool.rootKey)

        let root = Self.rootPath(fixture)
        let subNew = try root.get(key: "new").subscribe(options: .init(depth: 1)) { newPathCollector.record($0) }
        let subOld = try root.get(key: "old").subscribe(options: .init(depth: 1)) { oldPathCollector.record($0) }
        defer {
            subNew.unsubscribe()
            subOld.unsubscribe()
        }

        Self.syncAndDrain(
            [
                TestFactories.rootObjectMessage(entries: ["new": TestFactories.mapEntry(data: ProtocolTypes.ObjectData(objectId: "counter:c@1"))]),
                TestFactories.counterObjectMessage(objectId: "counter:c@1", count: 100),
            ],
            fixture,
        )

        // "new" gets two events: the root's own diff (removed "old"/updated "new" — chosen candidate
        // ["new"]) and the counter's update at its REBUILT full path ["new"] (RTO5c10 before notify).
        #expect(newPathCollector.events.count == 2)
        #expect(newPathCollector.sortedPaths == ["new", "new"])
        #expect(newPathCollector.events.allSatisfy { $0.message == nil })

        // "old" hears only the root's removal diff — the counter's update must NOT be delivered at
        // its stale pre-sync path.
        #expect(oldPathCollector.events.count == 1)
        #expect(oldPathCollector.events.first?.object.path == "old")
    }

    // The RTO4b reset path (ATTACHED without HAS_OBJECTS) also fans out to path subscriptions: the
    // root's RTO4b2a `removed` diff is dispatched with a nil message.
    @Test
    func attachedWithoutObjectsResetDeliversRemovedKeys() throws {
        let fixture = Self.makeFixture()
        let collector = EventCollector()

        // Seed root["k"] = "v" so the reset actually removes something.
        let rootData = ["k": TestFactories.internalMapEntry(data: ProtocolTypes.ObjectData(string: "v"))]
        fixture.engine.testsOnly_setPoolEntry(.map(Self.makeMap(objectID: ObjectsPool.rootKey, data: rootData, fixture)), forObjectID: ObjectsPool.rootKey)

        let subscription = try Self.rootPath(fixture).get(key: "k").subscribe { collector.record($0) }
        defer { subscription.unsubscribe() }

        fixture.internalQueue.ably_syncNoDeadlock {
            fixture.engine.nosync_onChannelAttached(hasObjects: false)
        }
        fixture.userCallbackQueue.sync {}

        #expect(collector.events.count == 1)
        let event = try #require(collector.events.first)
        #expect(event.object.path == "k")
        #expect(event.message == nil) // sync-originated (RTO4b2a)
    }
}
