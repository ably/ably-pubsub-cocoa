// Derived from the UTS spec `objects/unit/realtime_object.md`.
//
// A MIXED spec. These ports drive the **real** `InternalDefaultRealtimeObjects` engine behind the
// public `PublicDefaultRealtimeObject` entry point (`channel.object`), over a fresh internal/
// user-callback queue pair and a `MockCoreSDK` — there is no channel/connection here. The spec's
// mock-WebSocket transport (`setup_synced_channel`, `MockWebSocket`, `channel.attach()`/`.detach()`,
// `build_object_sync_message`/`build_ack_message`) has no unit-tier counterpart, so:
//   - "synced channel" is stood in by driving the engine's own channel-state / OBJECT_SYNC handlers
//     directly (`nosync_onChannelAttached`, `nosync_handleObjectSyncProtocolMessage`) and seeding the
//     standard graph straight into the engine's owned pool (`testsOnly_setPoolEntry` +
//     `testsOnly_setParentReferences`, the LiveObjectSubscribeTests seeding idiom);
//   - inbound OBJECT frames (`mock_ws.send_to_client`) are replayed via
//     `testsOnly_applyObjectMessages` (off-queue) / `nosync_handleObjectProtocolMessage` (on-queue);
//   - a server ACK (`build_ack_message`) is stood in by a `MockCoreSDK` publish handler returning a
//     canned `PublishResult` — the apply-on-ACK pipeline (RTO20) then runs for real;
//   - `channel.object.processChannelState(state)` is the engine's `nosync_onChannelStateChanged`;
//   - fake timers + `ADVANCE_TIME` are stood in by advancing the engine's `MockSimpleClock` and
//     calling `performGarbageCollection()` directly.
// These are infra-driving stand-ins, NOT deviations.
//
// This suite uses `MockCoreSDK` (the shared configurable double the native `PublicRealtimeObjectTests`
// uses) rather than `ObjectsUTSCoreSDK`, because the ported cases must vary the channel state, the
// object channel modes (RTO2a2 / RTO23a / RTO25a / RTO26a → 40024) and `echoMessages` (RTO26c →
// 40000) per case — configuration `ObjectsUTSCoreSDK` fixes. This is an infra choice, not a deviation.
//
// Adaptations that are NOT deviations (per objects-mapping §9/§13):
// - Sync-state events (RTO18): `object.on(event:)` takes the `ObjectsEvent` enum (`.syncing`/
//   `.synced`) and a no-argument `@Sendable` callback, returns `any StatusSubscription`, and
//   deregistration is per-subscription `off()` (there is no `off(listener)`/`offAll`).
// - The spec's PM-level assertions on the OBJECT publish (`msg.action == OBJECT`, `msg.channel`) have
//   no OutboundObjectMessage counterpart — the unit tier captures at the `publishAndApply` seam, not a
//   PROTOCOL frame — so they are kept as comments and the ObjectMessage-level assertions are emitted.

import _AblyPluginSupportPrivate
import AblyPubSubDevice
@testable import AblyLiveObjects
@testable import AblyLiveObjectsTesting
import Foundation
import Testing

struct RealtimeObjectTests {
    private typealias ChannelState = _AblyPluginSupportPrivate.RealtimeChannelState
    private typealias ChannelMode = _AblyPluginSupportPrivate.ChannelMode

    private static let channelName = "test"
    private static let baseTime = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Fixture

    private struct Fixture {
        let engine: InternalDefaultRealtimeObjects
        let coreSDK: MockCoreSDK
        let object: PublicDefaultRealtimeObject
        let internalQueue: DispatchQueue
        let userCallbackQueue: DispatchQueue
        let clock: MockSimpleClock
        let published: ObjectsUTSPublished
    }

    /// A minimal thread-safe call counter / event log for the asynchronously-delivered callbacks.
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        func increment() { lock.withLock { n += 1 } }
        var value: Int { lock.withLock { n } }
    }

    private final class Log: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String] = []
        func append(_ s: String) { lock.withLock { items.append(s) } }
        var all: [String] { lock.withLock { items } }
    }

    private static func makeFixture(
        channelState: ChannelState = .attached,
        objectChannelModes: ChannelMode = [.objectSubscribe, .objectPublish],
        echoMessages: Bool = true,
        clock: MockSimpleClock = MockSimpleClock(currentTime: baseTime),
    ) -> Fixture {
        let internalQueue = ObjectsUTS.createInternalQueue()
        let userCallbackQueue = DispatchQueue(label: "RealtimeObjectTests.userCallback")
        let engine = InternalDefaultRealtimeObjects(
            logger: TestLogger(),
            internalQueue: internalQueue,
            userCallbackQueue: userCallbackQueue,
            clock: clock,
            channelName: channelName,
        )
        let coreSDK = MockCoreSDK(
            channelState: channelState,
            channelName: channelName,
            objectChannelModes: objectChannelModes,
            echoMessages: echoMessages,
            internalQueue: internalQueue,
        )
        let object = PublicDefaultRealtimeObject(proxied: engine, coreSDK: coreSDK, logger: TestLogger())
        return Fixture(engine: engine, coreSDK: coreSDK, object: object, internalQueue: internalQueue, userCallbackQueue: userCallbackQueue, clock: clock, published: ObjectsUTSPublished())
    }

    // MARK: - Fixture helpers

    private static func onQueue(_ f: Fixture, _ body: () -> Void) {
        f.internalQueue.ably_syncNoDeadlock { body() }
    }

    private static func drain(_ f: Fixture) {
        f.userCallbackQueue.sync {}
    }

    private static func channelState(_ f: Fixture) -> ChannelState {
        f.internalQueue.ably_syncNoDeadlock { f.coreSDK.nosync_channelState }
    }

    private static func setChannelState(_ f: Fixture, _ state: ChannelState) {
        f.internalQueue.ably_syncNoDeadlock { f.coreSDK.nosync_setChannelState(state) }
    }

    /// The unit stand-in for `AWAIT setup_synced_channel("test")`: drive the engine to `.synced`
    /// (RTO4b ATTACHED-with-HAS_OBJECTS-false, which resets the pool to a single empty root), set the
    /// connection `siteCode` (SITE_CODE) so local apply-on-ACK can run (RTO20c1), then seed the
    /// standard test graph straight into the engine's owned pool.
    private static func setupSyncedChannel(_ f: Fixture, seed: Bool = true, siteCode: Bool = true) {
        onQueue(f) {
            f.engine.nosync_onChannelAttached(hasObjects: false)
            if siteCode {
                f.engine.nosync_setSiteCode(StandardTestPool.siteCode)
            }
        }
        if seed {
            seedStandardGraph(f)
        }
    }

    private static func makeCounter(_ f: Fixture, objectID: String, data: Double) -> InternalDefaultLiveCounter {
        InternalDefaultLiveCounter(testsOnly_data: data, objectID: objectID, logger: TestLogger(), internalQueue: f.internalQueue, userCallbackQueue: f.userCallbackQueue, clock: f.clock)
    }

    private static func makeMap(_ f: Fixture, objectID: String, data: [String: InternalObjectsMapEntry]) -> InternalDefaultLiveMap {
        InternalDefaultLiveMap(testsOnly_data: data, objectID: objectID, logger: TestLogger(), internalQueue: f.internalQueue, userCallbackQueue: f.userCallbackQueue, clock: f.clock)
    }

    /// Seeds the shared standard LiveObjects tree (`objects/helpers/standard_test_pool.md`) into the
    /// engine's owned pool, at `POOL_SERIAL` so the spec's remote serials win LWW (RTLM9e), with the
    /// standard parentReferences so path-subscription fan-out (RTO24) reaches every node.
    ///
    ///     root: name="Alice", age=30, active=true, score->counter:score@1000 (100),
    ///           profile->map:profile@1000, data=json{tags:[a,b]}, avatar=bytes[1,2,3]
    ///     map:profile@1000: email="alice@example.com", nested_counter->counter:nested@1000 (5),
    ///                       prefs->map:prefs@1000
    ///     map:prefs@1000: theme="dark"
    private static func seedStandardGraph(_ f: Fixture) {
        let score = makeCounter(f, objectID: "counter:score@1000", data: 100)
        let nested = makeCounter(f, objectID: "counter:nested@1000", data: 5)
        let prefs = makeMap(f, objectID: "map:prefs@1000", data: ["theme": ObjectsUTS.mapEntry(data: ProtocolTypes.ObjectData(string: "dark"))])
        let profile = makeMap(
            f,
            objectID: "map:profile@1000",
            data: [
                "email": ObjectsUTS.mapEntry(data: ProtocolTypes.ObjectData(string: "alice@example.com")),
                "nested_counter": ObjectsUTS.mapEntry(data: ProtocolTypes.ObjectData(objectId: "counter:nested@1000")),
                "prefs": ObjectsUTS.mapEntry(data: ProtocolTypes.ObjectData(objectId: "map:prefs@1000")),
            ],
        )
        let root = makeMap(
            f,
            objectID: ObjectsPool.rootKey,
            data: [
                "name": ObjectsUTS.mapEntry(data: ProtocolTypes.ObjectData(string: "Alice")),
                "age": ObjectsUTS.mapEntry(data: ProtocolTypes.ObjectData(number: NSNumber(value: 30))),
                "active": ObjectsUTS.mapEntry(data: ProtocolTypes.ObjectData(boolean: true)),
                "score": ObjectsUTS.mapEntry(data: ProtocolTypes.ObjectData(objectId: "counter:score@1000")),
                "profile": ObjectsUTS.mapEntry(data: ProtocolTypes.ObjectData(objectId: "map:profile@1000")),
                "data": ObjectsUTS.mapEntry(data: ProtocolTypes.ObjectData(json: .object(["tags": .array([.string("a"), .string("b")])]))),
                "avatar": ObjectsUTS.mapEntry(data: ProtocolTypes.ObjectData(bytes: Data([1, 2, 3]))),
            ],
        )

        let poolSiteTimeserials = ["aaa": StandardTestPool.poolSerial]
        for object in [score, nested] {
            object.testsOnly_setSiteTimeserials(poolSiteTimeserials)
        }
        for object in [prefs, profile, root] {
            object.testsOnly_setSiteTimeserials(poolSiteTimeserials)
        }

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

    /// Installs a publish handler that captures the outbound messages into `f.published` and ACKs each
    /// with `ack_serial(0, i)` (the `build_ack_message` stand-in). This is the automatic-ACK
    /// `setup_synced_channel` transport.
    private static func installAckHandler(_ f: Fixture) {
        let published = f.published
        f.coreSDK.setPublishHandler { messages in
            published.set(messages)
            return PublishResult(serials: messages.enumerated().map { index, _ in StandardTestPool.ackSerial(msgSerial: 0, i: index) })
        }
    }

    /// An OBJECT_SYNC that re-states `counter:score@1000` at the given value under root (the standard
    /// tree the spec's `build_object_sync_message(..., STANDARD_POOL_OBJECTS)` restates), completing
    /// the sync immediately (RTO5a5). Used where a re-sync must not wipe the counter under test.
    private static func completeSyncRestatingScore(_ f: Fixture, count: Int = 100) {
        onQueue(f) {
            f.engine.nosync_handleObjectSyncProtocolMessage(
                objectMessages: [
                    TestFactories.mapObjectMessage(objectId: ObjectsPool.rootKey, entries: [
                        "score": TestFactories.objectReferenceMapEntry(key: "score", objectId: "counter:score@1000").entry,
                    ]),
                    TestFactories.counterObjectMessage(objectId: "counter:score@1000", count: count),
                ],
                protocolMessageChannelSerial: nil,
            )
        }
    }

    // MARK: - RTO23 get() returns PathObject wrapping root

    // UTS: objects/unit/RTO23/get-returns-path-object-0
    @Test
    func getReturnsPathObjectWrappingRoot() async throws {
        // Setup
        let f = Self.makeFixture()
        Self.setupSyncedChannel(f)

        // Test Steps
        let root = try await f.object.get()

        // Assertions
        // RTO23d — Returns PathObject with path set to empty list and root set to root InternalLiveMap.
        _ = root as any PathObject // ASSERT root IS PathObject — the static return type is `any LiveMapPathObject`.
        #expect(root.path.isEmpty) // ASSERT root.path == []
        #expect(try root.type() == .liveMap)
    }

    // MARK: - RTO23a get() requires OBJECT_SUBSCRIBE mode

    // UTS: objects/unit/RTO23a/get-requires-subscribe-mode-0
    @Test
    func getRequiresSubscribeMode() async throws {
        // Setup — channel granted only OBJECT_PUBLISH (RTO2).
        let f = Self.makeFixture(objectChannelModes: [.objectPublish])

        // Test Steps
        do {
            _ = try await f.object.get()
            Issue.record("expected get() to fail with 40024")
        } catch {
            // Assertions
            #expect(error.code == 40024) // ASSERT error.code == 40024
        }
    }

    // MARK: - RTO23e get() re-attaches a DETACHED channel (ensure-active-channel)

    // UTS: objects/unit/RTO23e/get-reattaches-detached-0
    @Test
    func getReattachesDetachedChannel() async throws {
        // Setup — the channel is DETACHED; get() must run ensure-active-channel (RTL33b implicit
        // attach, MockCoreSDK's default attach transitions it to ATTACHED), then wait for sync.
        let f = Self.makeFixture(channelState: .detached)

        // Test Steps
        // get() on a DETACHED channel triggers ensure-active-channel (RTL33b) -> implicit re-attach ->
        // then parks in the RTO23c sync wait; completing the sync resolves it.
        let getTask = Task { try await f.object.get() }
        _ = await f.engine.testsOnly_waitingForSyncEvents.first { _ in true }
        Self.onQueue(f) {
            f.engine.nosync_handleObjectSyncProtocolMessage(objectMessages: [], protocolMessageChannelSerial: nil)
        }
        let root = try await getTask.value

        // Assertions
        _ = root as any PathObject // ASSERT root IS PathObject
        #expect(root.path.isEmpty) // ASSERT root.path == []
        #expect(Self.channelState(f) == .attached) // ASSERT channel.state == ATTACHED
    }

    // MARK: - RTO23c get() waits for SYNCED state

    // UTS: objects/unit/RTO23c/get-waits-for-synced-0
    @Test
    func getWaitsForSynced() async throws {
        // Setup — attached but not yet synced (engine starts INITIALIZED).
        let f = Self.makeFixture()

        // Test Steps
        let getTask = Task { try await f.object.get() }
        _ = await f.engine.testsOnly_waitingForSyncEvents.first { _ in true } // poll_until(attach_sent) stand-in: get() has parked in the sync wait
        Self.onQueue(f) {
            f.engine.nosync_handleObjectSyncProtocolMessage(objectMessages: [], protocolMessageChannelSerial: nil)
        }
        let root = try await getTask.value

        // Assertions
        _ = root as any PathObject // ASSERT root IS PathObject
        #expect(root.path.isEmpty) // ASSERT root.path == []
    }

    // MARK: - RTO23c1 get() fails when channel enters DETACHED during sync wait

    // UTS: objects/unit/RTO23c1/fails-on-channel-detached-0
    @Test
    func getFailsWhenChannelDetachedDuringSyncWait() async throws {
        // Setup
        let f = Self.makeFixture()
        Self.setupSyncedChannel(f, seed: false)

        // Test Steps
        // Move the objects sync state back to SYNCING so a fresh get() must wait (RTO23c).
        Self.onQueue(f) { f.engine.nosync_onChannelAttached(hasObjects: true) }
        let getTask = Task { try await f.object.get() }
        // ASSERT get_future IS NOT complete — modelled by awaiting the RTO23c "started waiting" signal.
        _ = await f.engine.testsOnly_waitingForSyncEvents.first { _ in true }
        // A client-side detach then moves the channel to DETACHED.
        Self.onQueue(f) { f.engine.nosync_onChannelStateChanged(toState: .detached, reason: nil) }

        do {
            _ = try await getTask.value
            Issue.record("expected get() to fail with 92008")
        } catch {
            // Assertions
            let error = try #require(error as? ErrorInfo)
            #expect(error.code == 92008) // ASSERT error.code == 92008
            #expect(error.statusCode == 400) // ASSERT error.statusCode == 400
        }
    }

    // MARK: - RTO23c1 get() fails when channel enters SUSPENDED during sync wait

    // UTS: objects/unit/RTO23c1/fails-on-channel-suspended-0
    @Test
    func getFailsWhenChannelSuspendedDuringSyncWait() async throws {
        // Setup
        let f = Self.makeFixture()
        Self.setupSyncedChannel(f, seed: false)

        // Test Steps
        Self.onQueue(f) { f.engine.nosync_onChannelAttached(hasObjects: true) } // back to SYNCING
        let getTask = Task { try await f.object.get() }
        _ = await f.engine.testsOnly_waitingForSyncEvents.first { _ in true } // ASSERT get_future IS NOT complete
        // channel.object.processChannelState(SUSPENDED) — the engine's channel-state handler directly.
        Self.onQueue(f) { f.engine.nosync_onChannelStateChanged(toState: .suspended, reason: nil) }

        do {
            _ = try await getTask.value
            Issue.record("expected get() to fail with 92008")
        } catch {
            // Assertions
            let error = try #require(error as? ErrorInfo)
            #expect(error.code == 92008) // ASSERT error.code == 92008
            #expect(error.statusCode == 400) // ASSERT error.statusCode == 400
        }
    }

    // MARK: - RTO23c1 get() fails with cause when channel enters FAILED during sync wait

    // UTS: objects/unit/RTO23c1/fails-on-channel-failed-0
    @Test
    func getFailsWithCauseWhenChannelFailedDuringSyncWait() async throws {
        // Setup
        let f = Self.makeFixture()
        Self.setupSyncedChannel(f, seed: false)

        // Test Steps
        Self.onQueue(f) { f.engine.nosync_onChannelAttached(hasObjects: true) } // back to SYNCING
        let getTask = Task { try await f.object.get() }
        _ = await f.engine.testsOnly_waitingForSyncEvents.first { _ in true } // ASSERT get_future IS NOT complete
        // A channel ERROR moves the channel to FAILED and sets its errorReason (the injected error).
        let failedReason = ErrorInfo.create(withCode: 90000, status: 400, message: "Channel failed")
        Self.onQueue(f) { f.engine.nosync_onChannelStateChanged(toState: .failed, reason: failedReason) }

        do {
            _ = try await getTask.value
            Issue.record("expected get() to fail with 92008")
        } catch {
            // Assertions
            let error = try #require(error as? ErrorInfo)
            #expect(error.code == 92008) // ASSERT error.code == 92008
            #expect(error.statusCode == 400) // ASSERT error.statusCode == 400
            // RTO23c1 - cause is set to the channel's errorReason (the injected FAILED error).
            #expect(error.cause?.code == 90000) // ASSERT error.cause.code == 90000
        }
    }

    // MARK: - RTO15 publish sends OBJECT ProtocolMessage

    // UTS: objects/unit/RTO15/publish-sends-object-pm-0
    @Test
    func publishSendsObjectProtocolMessage() async throws {
        // Setup
        let f = Self.makeFixture()
        Self.installAckHandler(f)
        Self.setupSyncedChannel(f)
        let root = try await f.object.get()

        // Test Steps
        // Drive the internal publish (RTO15) through a public mutation. Only the observable wire
        // behaviour is asserted here (RTO20 apply-on-ACK is covered by the neighbouring cases).
        try await root.get(key: "score").asLiveCounter().increment(amount: 5)

        // Assertions
        // The unit tier captures at the publishAndApply seam (the OutboundObjectMessage `state` array),
        // not a PROTOCOL frame — so `msg.action == OBJECT` / `msg.channel == "test"` (PM-level) have no
        // counterpart; the ObjectMessage-level assertions below stand in.
        let messages = try #require(f.published.get())
        #expect(messages.count == 1) // ASSERT captured_messages[0].state.length == 1
        let operation = try #require(messages[0].operation)
        // RTO15e3 - the state entry is the encoded ObjectMessage for the driven mutation.
        #expect(operation.action == .known(.counterInc)) // ASSERT ...operation.action == COUNTER_INC
        #expect(operation.objectId == "counter:score@1000") // ASSERT ...operation.objectId == "counter:score@1000"
        #expect(try #require(operation.counterInc).number.intValue == 5) // ASSERT ...operation.counterInc.number == 5
    }

    // MARK: - RTO20 publishAndApply applies locally on ACK

    // UTS: objects/unit/RTO20/publish-and-apply-local-0
    @Test
    func publishAndApplyAppliesLocallyOnAck() async throws {
        // Setup
        let f = Self.makeFixture()
        Self.installAckHandler(f)
        Self.setupSyncedChannel(f)
        let root = try await f.object.get()

        // Test Steps
        try await root.get(key: "score").asLiveCounter().increment(amount: 10)

        // Assertions
        #expect(try root.get(key: "score").asLiveCounter().value() == 110) // ASSERT root.get("score").value() == 110
    }

    // MARK: - RTO20c publishAndApply logs error when siteCode missing

    // UTS: objects/unit/RTO20c/missing-site-code-0
    @Test
    func publishAndApplyLogsErrorWhenSiteCodeMissing() async throws {
        // Setup — synced but with NO siteCode set (RTO20c1), so local apply is skipped.
        let f = Self.makeFixture()
        Self.installAckHandler(f)
        Self.setupSyncedChannel(f, siteCode: false)
        let root = try await f.object.get()

        // Test Steps
        try await root.get(key: "score").asLiveCounter().increment(amount: 10)

        // Assertions
        #expect(try root.get(key: "score").asLiveCounter().value() == 100) // ASSERT root.get("score").value() == 100
    }

    // MARK: - RTO20d1 null serial in PublishResult is skipped

    // UTS: objects/unit/RTO20d1/null-serial-skipped-0
    @Test
    func nullSerialInPublishResultIsSkipped() async throws {
        // Setup — ACK conflates the serial to null (RTO20d1).
        let f = Self.makeFixture()
        f.coreSDK.setPublishHandler { _ in PublishResult(serials: [nil]) }
        Self.setupSyncedChannel(f)
        let root = try await f.object.get()

        // Test Steps
        try await root.get(key: "score").asLiveCounter().increment(amount: 10)

        // Assertions
        #expect(try root.get(key: "score").asLiveCounter().value() == 100) // ASSERT root.get("score").value() == 100
    }

    // MARK: - RTO20d4 empty synthetic list skips the RTO20e sync wait

    // UTS: objects/unit/RTO20d4/empty-synthetic-list-skips-sync-wait-0
    @Test
    func emptySyntheticListSkipsSyncWait() async throws {
        // Setup — all-null ACK (so the synthetic list is empty per RTO20d1).
        let f = Self.makeFixture()
        f.coreSDK.setPublishHandler { _ in PublishResult(serials: [nil]) }
        Self.setupSyncedChannel(f)
        let root = try await f.object.get()

        // Test Steps
        // Move the objects sync state back to SYNCING so a normal publishAndApply would park in the
        // RTO20e wait. No sync-completing message is ever sent: resolution proves the wait was skipped.
        Self.onQueue(f) { f.engine.nosync_onChannelAttached(hasObjects: true) }
        try await root.get(key: "score").asLiveCounter().increment(amount: 10)

        // Assertions
        // Resolution despite the channel never reaching SYNCED proves the RTO20e wait was skipped.
        #expect(try root.get(key: "score").asLiveCounter().value() == 100) // ASSERT root.get("score").value() == 100
    }

    // MARK: - RTO20e publishAndApply waits for SYNCED during SYNCING

    // UTS: objects/unit/RTO20e/waits-for-synced-0
    @Test
    func publishAndApplyWaitsForSyncedDuringSyncing() async throws {
        // Setup
        let f = Self.makeFixture()
        Self.installAckHandler(f)
        Self.setupSyncedChannel(f)
        let root = try await f.object.get()

        // Test Steps
        Self.onQueue(f) { f.engine.nosync_onChannelAttached(hasObjects: true) } // back to SYNCING
        let incTask = Task { try await root.get(key: "score").asLiveCounter().increment(amount: 10) }

        // Per RTO20e the write must WAIT for the sync to reach SYNCED: while still SYNCING the increment
        // must not have applied yet. The value is unchanged regardless of ACK timing (apply is deferred
        // to sync completion), so it stands in for `inc_future IS NOT complete`.
        Self.onQueue(f) {} // flush the publish/ACK hop
        #expect(try root.get(key: "score").asLiveCounter().value() == 100) // ASSERT inc not applied; value == 100

        Self.completeSyncRestatingScore(f) // build_object_sync_message(..., STANDARD_POOL_OBJECTS)
        try await incTask.value

        // Assertions
        #expect(try root.get(key: "score").asLiveCounter().value() == 110) // ASSERT root.get("score").value() == 110
    }

    // MARK: - RTO20e1 publishAndApply fails when channel enters DETACHED during sync wait

    // UTS: objects/unit/RTO20e1/fails-on-channel-detached-0
    @Test
    func publishAndApplyFailsWhenChannelDetachedDuringSyncWait() async throws {
        // The publish parks in the RTO20e wait; the channel then enters DETACHED.
        let error = try await Self.runPublishAndApplyFailingOnChannelState(.detached)

        // Assertions
        #expect(error.code == 92008) // ASSERT error.code == 92008
    }

    // MARK: - RTO20e1 publishAndApply fails when channel enters FAILED during sync wait

    // UTS: objects/unit/RTO20e1/fails-on-channel-failed-0
    @Test
    func publishAndApplyFailsWhenChannelFailedDuringSyncWait() async throws {
        // The publish parks in the RTO20e wait; the channel then enters FAILED.
        let error = try await Self.runPublishAndApplyFailingOnChannelState(.failed)

        // Assertions
        #expect(error.code == 92008) // ASSERT error.code == 92008
    }

    /// Shared orchestration for the two RTO20e1 cases: the publish parks in the RTO20e wait, then the
    /// channel enters the given state (driven from within the publish-callback handler, so the waiter
    /// is guaranteed parked before the drain — the race-free ordering the native twin uses, standing in
    /// for `ASSERT inc_future IS NOT complete`). Returns the ErrorInfo the increment fails with.
    private static func runPublishAndApplyFailingOnChannelState(_ state: ChannelState) async throws -> ErrorInfo {
        // Setup
        let f = makeFixture()
        setupSyncedChannel(f)
        let root = try await f.object.get()

        // Test Steps
        onQueue(f) { f.engine.nosync_onChannelAttached(hasObjects: true) } // back to SYNCING
        let engine = f.engine
        let internalQueue = f.internalQueue
        f.coreSDK.setPublishCallbackHandler { messages, callback in
            let result = PublishResult(serials: messages.enumerated().map { index, _ in StandardTestPool.ackSerial(msgSerial: 0, i: index) })
            internalQueue.async {
                callback(.success(result)) // parks the publishAndApply waiter (ASSERT inc_future IS NOT complete)
                internalQueue.async {
                    engine.nosync_onChannelStateChanged(toState: state, reason: nil) // then the channel state change fails it
                }
            }
        }

        do {
            try await root.get(key: "score").asLiveCounter().increment(amount: 10)
            Issue.record("expected the increment to fail with 92008")
            throw CancellationError()
        } catch let error as ErrorInfo {
            return error
        }
    }

    // MARK: - RTO17, RTO18 Sync state events

    // UTS: objects/unit/RTO17/sync-state-events-0
    @Test
    func syncStateEvents() async throws {
        // Setup — attached but not yet synced.
        let f = Self.makeFixture()
        let events = Log()
        f.object.on(event: .syncing) { events.append("SYNCING") }
        f.object.on(event: .synced) { events.append("SYNCED") }

        // Test Steps
        // RTO18b1 SYNCING (ATTACHED with HAS_OBJECTS), then RTO18b2 SYNCED (OBJECT_SYNC completion).
        Self.onQueue(f) { f.engine.nosync_onChannelAttached(hasObjects: true) }
        Self.onQueue(f) { f.engine.nosync_handleObjectSyncProtocolMessage(objectMessages: [], protocolMessageChannelSerial: nil) }
        Self.drain(f)

        // Assertions
        // RTO18e: listeners called with no arguments (the `() -> Void` callback), verified by shape.
        #expect(events.all == ["SYNCING", "SYNCED"]) // ASSERT events CONTAINS_IN_ORDER ["SYNCING", "SYNCED"]
    }

    // MARK: - RTO18d Duplicate listener registered twice fires twice

    // UTS: objects/unit/RTO18d/duplicate-listener-0
    @Test
    func duplicateListenerRegisteredTwiceFiresTwice() async throws {
        // Setup — cocoa registers each `on` call as a distinct subscription (no instance de-dup), so
        // this exercises the RTE4 reference behaviour: the same listener added twice fires twice.
        let f = Self.makeFixture()
        Self.setupSyncedChannel(f, seed: false)
        let callCount = Counter()
        let listener: @Sendable () -> Void = { callCount.increment() }
        f.object.on(event: .synced, callback: listener)
        f.object.on(event: .synced, callback: listener)

        // Test Steps
        Self.onQueue(f) { f.engine.nosync_onChannelAttached(hasObjects: true) } // ATTACHED sync2 -> SYNCING
        Self.onQueue(f) { f.engine.nosync_handleObjectSyncProtocolMessage(objectMessages: [], protocolMessageChannelSerial: nil) } // OBJECT_SYNC -> SYNCED
        Self.drain(f)

        // Assertions
        #expect(callCount.value == 2) // ASSERT call_count == 2
    }

    // MARK: - RTO19 off() deregisters listener

    // UTS: objects/unit/RTO19/off-deregisters-0
    @Test
    func offDeregistersListener() async throws {
        // Setup
        let f = Self.makeFixture()
        Self.setupSyncedChannel(f, seed: false)
        let callCount = Counter()
        let sub = f.object.on(event: .synced) { callCount.increment() }
        sub.off() // deregister before any event is emitted

        // Test Steps
        Self.onQueue(f) { f.engine.nosync_onChannelAttached(hasObjects: true) }
        Self.onQueue(f) { f.engine.nosync_handleObjectSyncProtocolMessage(objectMessages: [], protocolMessageChannelSerial: nil) }
        Self.drain(f)

        // Assertions
        #expect(callCount.value == 0) // ASSERT call_count == 0
    }

    // MARK: - RTO2 Channel mode enforcement

    // UTS: objects/unit/RTO2/mode-enforcement-0
    @Test
    func channelModeEnforcement() async throws {
        // Setup — ATTACHED state grants only OBJECT_SUBSCRIBE (RTO2a), so a write is rejected.
        let f = Self.makeFixture(objectChannelModes: [.objectSubscribe])
        Self.setupSyncedChannel(f)
        let root = try await f.object.get()

        // Test Steps
        do {
            try await root.set(key: "name", value: "Bob")
            Issue.record("expected set() to fail with 40024")
        } catch {
            // Assertions
            #expect(error.code == 40024) // ASSERT error.code == 40024
        }
    }

    // MARK: - RTO23e get() on a FAILED channel rejects with 90001 (ensure-active-channel)

    // UTS: objects/unit/RTO23e/get-rejects-failed-0
    @Test
    func getRejectsFailedChannel() async throws {
        // Setup — attach fails, putting the channel into FAILED state (RTL33c).
        let f = Self.makeFixture(channelState: .failed)

        // Test Steps
        do {
            _ = try await f.object.get()
            Issue.record("expected get() to fail with 90001")
        } catch {
            // Assertions
            #expect(error.code == 90001) // ASSERT error.code == 90001
            #expect(error.statusCode == 400) // ASSERT error.statusCode == 400
        }
    }

    // MARK: - RTO25a Access API precondition requires OBJECT_SUBSCRIBE mode

    // UTS: objects/unit/RTO25a/access-requires-subscribe-mode-0
    @Test
    func accessRequiresSubscribeMode() async throws {
        // Setup — channel granted only OBJECT_PUBLISH, so obtaining the objects API throws 40024.
        let f = Self.makeFixture(objectChannelModes: [.objectPublish])

        // Test Steps
        do {
            _ = try await f.object.get()
            Issue.record("expected get() to fail with 40024")
        } catch {
            // Assertions
            #expect(error.code == 40024) // ASSERT error.code == 40024
            #expect(error.statusCode == 400) // ASSERT error.statusCode == 400
        }
    }

    // MARK: - RTO25b Access API precondition throws on DETACHED channel

    // UTS: objects/unit/RTO25b/access-throws-detached-0
    @Test
    func accessThrowsOnDetachedChannel() async throws {
        // Setup — root obtained while ATTACHED, then the channel is detached client-side.
        let f = Self.makeFixture()
        Self.setupSyncedChannel(f)
        let root = try await f.object.get()

        // Test Steps
        Self.setChannelState(f, .detached) // AWAIT channel.detach(); AWAIT_STATE DETACHED
        do {
            _ = try root.keys()
            Issue.record("expected keys() to fail with 90001")
        } catch {
            // Assertions
            #expect(error.code == 90001) // ASSERT error.code == 90001
            #expect(error.statusCode == 400) // ASSERT error.statusCode == 400
        }
    }

    // MARK: - RTO25b Access API precondition throws on FAILED channel

    // UTS: objects/unit/RTO25b/access-throws-failed-0
    @Test
    func accessThrowsOnFailedChannel() async throws {
        // Setup
        let f = Self.makeFixture()
        Self.setupSyncedChannel(f)
        let root = try await f.object.get()

        // Test Steps
        Self.setChannelState(f, .failed) // force channel to FAILED
        do {
            _ = try root.keys()
            Issue.record("expected keys() to fail with 90001")
        } catch {
            // Assertions
            #expect(error.code == 90001) // ASSERT error.code == 90001
            #expect(error.statusCode == 400) // ASSERT error.statusCode == 400
        }
    }

    // MARK: - RTO26a Write API precondition requires OBJECT_PUBLISH mode

    // UTS: objects/unit/RTO26a/write-requires-publish-mode-0
    @Test
    func writeRequiresPublishMode() async throws {
        // Setup — channel granted only OBJECT_SUBSCRIBE (no OBJECT_PUBLISH).
        let f = Self.makeFixture(objectChannelModes: [.objectSubscribe])
        Self.setupSyncedChannel(f)
        let root = try await f.object.get()

        // Test Steps
        do {
            try await root.set(key: "name", value: "Bob")
            Issue.record("expected set() to fail with 40024")
        } catch {
            // Assertions
            #expect(error.code == 40024) // ASSERT error.code == 40024
            #expect(error.statusCode == 400) // ASSERT error.statusCode == 400
        }
    }

    // MARK: - RTO26b Write API precondition throws on DETACHED channel

    // UTS: objects/unit/RTO26b/write-throws-detached-0
    @Test
    func writeThrowsOnDetachedChannel() async throws {
        // Setup
        let f = Self.makeFixture()
        Self.setupSyncedChannel(f)
        let root = try await f.object.get()

        // Test Steps
        Self.setChannelState(f, .detached) // AWAIT channel.detach(); AWAIT_STATE DETACHED
        do {
            try await root.set(key: "name", value: "Bob")
            Issue.record("expected set() to fail with 90001")
        } catch {
            // Assertions
            #expect(error.code == 90001) // ASSERT error.code == 90001
            #expect(error.statusCode == 400) // ASSERT error.statusCode == 400
        }
    }

    // MARK: - RTO26b Write API precondition throws on FAILED channel

    // UTS: objects/unit/RTO26b/write-throws-failed-0
    @Test
    func writeThrowsOnFailedChannel() async throws {
        // Setup
        let f = Self.makeFixture()
        Self.setupSyncedChannel(f)
        let root = try await f.object.get()

        // Test Steps
        Self.setChannelState(f, .failed) // force channel to FAILED
        do {
            try await root.set(key: "name", value: "Bob")
            Issue.record("expected set() to fail with 90001")
        } catch {
            // Assertions
            #expect(error.code == 90001) // ASSERT error.code == 90001
            #expect(error.statusCode == 400) // ASSERT error.statusCode == 400
        }
    }

    // MARK: - RTO26c Write API precondition throws when echoMessages is false

    // UTS: objects/unit/RTO26c/write-throws-echo-disabled-0
    @Test
    func writeThrowsWhenEchoMessagesDisabled() async throws {
        // Setup — client configured with echoMessages: false (RTO26c).
        let f = Self.makeFixture(echoMessages: false)
        Self.setupSyncedChannel(f)
        let root = try await f.object.get()

        // Test Steps
        do {
            try await root.set(key: "name", value: "Bob")
            Issue.record("expected set() to fail with 40000")
        } catch {
            // Assertions
            #expect(error.code == 40000) // ASSERT error.code == 40000
            #expect(error.statusCode == 400) // ASSERT error.statusCode == 400
        }
    }

    // MARK: - RTO24a RealtimeObject maintains a single PathObjectSubscriptionRegister

    // UTS: objects/unit/RTO24a/single-register-instance-0
    @Test
    func singleRegisterInstanceSharedAcrossPathObjects() async throws {
        // Setup
        let f = Self.makeFixture()
        Self.setupSyncedChannel(f)
        let root = try await f.object.get()

        let eventsRoot = ObjectsUTSPathEventCollector()
        let eventsScore = ObjectsUTSPathEventCollector()
        // Subscribe via root PathObject at path [] and via a deeper PathObject at path ["score"].
        try root.subscribe(listener: eventsRoot.listener)
        let scorePath = root.get(key: "score")
        try scorePath.subscribe(listener: eventsScore.listener)

        // Test Steps
        // siteCode "remote" is absent from the pool's siteTimeserials, so the op passes the newness
        // check regardless of serial ordering; "t:1" also sorts after "t:0" for entry-level LWW.
        f.engine.testsOnly_applyObjectMessages(
            [ObjectsUTS.counterIncMessage(objectId: "counter:score@1000", number: 5, serial: StandardTestPool.remoteSerial(0), siteCode: "remote")],
            source: .channel,
        )
        Self.drain(f) // poll_until(events_score.length >= 1)

        // Assertions
        // Both subscriptions are managed by the same register and both fire.
        #expect(!eventsRoot.events.isEmpty) // ASSERT events_root.length >= 1
        #expect(!eventsScore.events.isEmpty) // ASSERT events_score.length >= 1
    }

    // MARK: - RTO24c1 Subscription coverage: prefix match with depth constraint

    // UTS: objects/unit/RTO24c1/coverage-prefix-depth-0
    @Test
    func subscriptionCoveragePrefixWithDepthConstraint() async throws {
        // Setup
        let f = Self.makeFixture()
        Self.setupSyncedChannel(f)
        let root = try await f.object.get()

        let shallowEvents = ObjectsUTSPathEventCollector()
        let deepEvents = ObjectsUTSPathEventCollector()
        // Subscribe at root with depth 1 — per RTO24c2b this covers ONLY root's own path ([]), not its
        // children (a child like ["score"] is relativeDepth 2 > 1).
        try root.subscribe(options: PathObjectSubscriptionOptions(depth: 1), listener: shallowEvents.listener)
        // Subscribe at root with no depth limit — covers everything.
        try root.subscribe(listener: deepEvents.listener)

        // Test Steps
        // Update root itself (a MAP_SET on root — candidate path [] is covered by depth 1).
        f.engine.testsOnly_applyObjectMessages(
            [ObjectsUTS.mapSetMessage(objectId: ObjectsPool.rootKey, key: "name", value: ProtocolTypes.ObjectData(string: "Bob"), serial: StandardTestPool.remoteSerial(0), siteCode: "remote")],
            source: .channel,
        )
        Self.drain(f) // poll_until(deep_events.length >= 1)

        // Update a child of root (path ["score"], relativeDepth 2) — NOT covered by depth 1.
        f.engine.testsOnly_applyObjectMessages(
            [ObjectsUTS.counterIncMessage(objectId: "counter:score@1000", number: 5, serial: StandardTestPool.remoteSerial(1), siteCode: "remote")],
            source: .channel,
        )
        Self.drain(f) // poll_until(deep_events.length >= 2) & poll_until(shallow_events.length >= 1)

        // Assertions
        // Shallow subscription (depth 1) only sees the root self-update, not the child update.
        #expect(shallowEvents.events.count == 1) // ASSERT shallow_events.length == 1
        // Deep subscription (no depth limit) sees both updates.
        #expect(deepEvents.events.count >= 2) // ASSERT deep_events.length >= 2
    }

    // MARK: - RTO10 GC removes tombstoned objects past grace period

    // UTS: objects/unit/RTO10/gc-tombstoned-objects-0
    @Test
    func gcRemovesTombstonedObjectsPastGracePeriod() async throws {
        // Setup — default grace period is the RTO10b3 24h; the tombstone is stamped "now" so only the
        // clock advance below makes it GC-eligible.
        let f = Self.makeFixture()
        Self.setupSyncedChannel(f)
        let root = try await f.object.get()

        f.engine.testsOnly_applyObjectMessages(
            [TestFactories.objectDeleteOperationMessage(objectId: "counter:score@1000", serial: "99", siteCode: "site1", serialTimestamp: f.clock.now)],
            source: .channel,
        )

        // Test Steps
        f.clock.advance(by: 86_400 + 300) // ADVANCE_TIME(86400000 + 300000) ms
        f.engine.performGarbageCollection()

        // Assertions
        #expect(try root.get(key: "score").asLiveCounter().value() == nil) // ASSERT root.get("score").value() == null
    }

    // MARK: - RTO10c1b1 GC never removes the root object

    // UTS: objects/unit/RTO10c1b1/gc-root-never-removed-0
    @Test
    func gcNeverRemovesRootObject() async throws {
        // Setup
        let f = Self.makeFixture()
        Self.setupSyncedChannel(f)
        let root = try await f.object.get()

        // Rogue OBJECT_DELETE targeting the root object: rejected per RTLO4e10 (root not tombstoned).
        f.engine.testsOnly_applyObjectMessages(
            [TestFactories.objectDeleteOperationMessage(objectId: ObjectsPool.rootKey, serial: StandardTestPool.remoteSerial(0), siteCode: "remote", serialTimestamp: f.clock.now)],
            source: .channel,
        )

        // Test Steps
        #expect(try root.get(key: "name").asPrimitive().value()?.stringValue == "Alice") // ASSERT root.get("name").value() == "Alice"

        f.clock.advance(by: 86_400 + 300) // ADVANCE_TIME(86400000 + 300000) ms
        f.engine.performGarbageCollection() // even after the grace period elapses, root must remain

        // A subsequent operation still applies to the same root object the client holds.
        f.engine.testsOnly_applyObjectMessages(
            [ObjectsUTS.mapSetMessage(objectId: ObjectsPool.rootKey, key: "name", value: ProtocolTypes.ObjectData(string: "Bob"), serial: StandardTestPool.remoteSerial(1), siteCode: "remote")],
            source: .channel,
        )

        // Assertions
        #expect(try root.get(key: "name").asPrimitive().value()?.stringValue == "Bob") // ASSERT root.get("name").value() == "Bob"
    }

    // MARK: - RTO20 Echo deduplication via appliedOnAckSerials

    // UTS: objects/unit/RTO20/echo-dedup-0
    @Test
    func echoDeduplicationViaAppliedOnAckSerials() async throws {
        // Setup
        let f = Self.makeFixture()
        Self.installAckHandler(f)
        Self.setupSyncedChannel(f)
        let root = try await f.object.get()

        // Test Steps
        try await root.get(key: "score").asLiveCounter().increment(amount: 10)
        let scoreAfterApply = try root.get(key: "score").asLiveCounter().value()

        // The echo carries the same serial as the apply-on-ACK (ack_serial(0, 0)); RTO9a3 dedups it.
        f.engine.testsOnly_applyObjectMessages(
            [ObjectsUTS.counterIncMessage(objectId: "counter:score@1000", number: 10, serial: StandardTestPool.ackSerial(msgSerial: 0, i: 0), siteCode: StandardTestPool.siteCode)],
            source: .channel,
        )
        let scoreAfterEcho = try root.get(key: "score").asLiveCounter().value()

        // Assertions
        #expect(scoreAfterApply == 110) // ASSERT score_after_apply == 110
        #expect(scoreAfterEcho == 110) // ASSERT score_after_echo == 110
    }

    // MARK: - RTO20f Apply-on-ACK does not update siteTimeserials

    // UTS: objects/unit/RTO20f/ack-no-site-timeserials-update-0
    @Test
    func applyOnAckDoesNotUpdateSiteTimeserials() async throws {
        // Setup
        let f = Self.makeFixture()
        Self.installAckHandler(f)
        Self.setupSyncedChannel(f)
        let root = try await f.object.get()

        // Test Steps
        try await root.get(key: "score").asLiveCounter().increment(amount: 10)
        #expect(try root.get(key: "score").asLiveCounter().value() == 110) // ASSERT root.get("score").value() == 110

        // Inbound COUNTER_INC from SITE_CODE with serial below_ack_serial(9) ("t:0:9"): NOT the
        // apply-on-ACK serial (so RTO9a3 does not discard it) yet sorts below "t:1:0". It applies iff
        // LOCAL correctly left siteTimeserials untouched (RTLC7c), reaching 120.
        f.engine.testsOnly_applyObjectMessages(
            [ObjectsUTS.counterIncMessage(objectId: "counter:score@1000", number: 10, serial: StandardTestPool.belowAckSerial(9), siteCode: StandardTestPool.siteCode)],
            source: .channel,
        )
        Self.drain(f) // poll_until(root.get("score").value() == 120)

        // Assertions
        #expect(try root.get(key: "score").asLiveCounter().value() == 120) // ASSERT root.get("score").value() == 120
    }

    // MARK: - RTO20 ACK after echo does not double-apply

    // UTS: objects/unit/RTO20/ack-after-echo-no-double-apply-0
    @Test
    func ackAfterEchoDoesNotDoubleApply() async throws {
        // Setup — `setup_synced_channel_no_ack`: the ACK is not automatic; the publish-callback handler
        // delivers the echo BEFORE the ACK, in a controlled internal-queue ordering.
        let f = Self.makeFixture()
        Self.setupSyncedChannel(f)
        let root = try await f.object.get()

        let engine = f.engine
        let internalQueue = f.internalQueue
        f.coreSDK.setPublishCallbackHandler { messages, callback in
            let result = PublishResult(serials: messages.enumerated().map { index, _ in StandardTestPool.ackSerial(msgSerial: 0, i: index) })
            internalQueue.async {
                // Send the echo BEFORE the ACK (source channel) -> counter reaches 110.
                engine.nosync_handleObjectProtocolMessage(objectMessages: [
                    ObjectsUTS.counterIncMessage(objectId: "counter:score@1000", number: 10, serial: StandardTestPool.ackSerial(msgSerial: 0, i: 0), siteCode: StandardTestPool.siteCode),
                ])
                // Now the ACK: the apply-on-ACK finds the serial already applied and does not double-apply.
                callback(.success(result))
            }
        }

        // Test Steps
        try await root.get(key: "score").asLiveCounter().increment(amount: 10)

        // Assertions
        #expect(try root.get(key: "score").asLiveCounter().value() == 110) // ASSERT root.get("score").value() == 110
    }

    // MARK: - RTO5c9, RTO20 appliedOnAckSerials cleared on re-sync

    // UTS: objects/unit/RTO5c9-RTO20/ack-serials-cleared-on-resync-0
    @Test
    func ackSerialsClearedOnResync() async throws {
        // Setup
        let f = Self.makeFixture()
        Self.installAckHandler(f)
        Self.setupSyncedChannel(f)
        let root = try await f.object.get()

        // Test Steps
        try await root.get(key: "score").asLiveCounter().increment(amount: 10)
        #expect(try root.get(key: "score").asLiveCounter().value() == 110) // ASSERT root.get("score").value() == 110

        // Trigger re-sync — appliedOnAckSerials should be cleared per RTO5c9 (restating the counter
        // at 100 via the standard-pool OBJECT_SYNC).
        Self.onQueue(f) { f.engine.nosync_onChannelAttached(hasObjects: true) }
        Self.completeSyncRestatingScore(f, count: 100)
        #expect(try root.get(key: "score").asLiveCounter().value() == 100) // ASSERT root.get("score").value() == 100

        // Replay the same serial (ack_serial(0, 0)) used for apply-on-ACK. If appliedOnAckSerials was
        // cleared, this applies normally; if not, RTO9a3 dedup would reject it and score stays 100.
        f.engine.testsOnly_applyObjectMessages(
            [ObjectsUTS.counterIncMessage(objectId: "counter:score@1000", number: 10, serial: StandardTestPool.ackSerial(msgSerial: 0, i: 0), siteCode: StandardTestPool.siteCode)],
            source: .channel,
        )
        Self.drain(f) // poll_until(root.get("score").value() == 110)

        // Assertions
        #expect(try root.get(key: "score").asLiveCounter().value() == 110) // ASSERT root.get("score").value() == 110
    }

    // MARK: - RTO20 Subscription fires on apply-on-ACK

    // UTS: objects/unit/RTO20/subscription-fires-on-ack-apply-0
    @Test
    func subscriptionFiresOnAckApply() async throws {
        // Setup
        let f = Self.makeFixture()
        Self.installAckHandler(f)
        Self.setupSyncedChannel(f)
        let root = try await f.object.get()
        let events = ObjectsUTSPathEventCollector()
        try root.get(key: "score").subscribe(listener: events.listener)

        // Test Steps
        try await root.get(key: "score").asLiveCounter().increment(amount: 10)
        Self.drain(f)

        // Assertions
        #expect(!events.events.isEmpty) // ASSERT events.length >= 1
        #expect(try root.get(key: "score").asLiveCounter().value() == 110) // ASSERT root.get("score").value() == 110
    }

    // MARK: - RTO23 get() implicitly attaches channel

    // UTS: objects/unit/RTO23/get-implicit-attach-0
    @Test
    func getImplicitlyAttachesChannel() async throws {
        // Setup — the channel is INITIALIZED; get() must trigger the implicit attach (RTL33b).
        let f = Self.makeFixture(channelState: .initialized)

        // Test Steps
        #expect(Self.channelState(f) == .initialized) // ASSERT channel.state == INITIALIZED
        let getTask = Task { try await f.object.get() }
        _ = await f.engine.testsOnly_waitingForSyncEvents.first { _ in true }
        Self.onQueue(f) { f.engine.nosync_handleObjectSyncProtocolMessage(objectMessages: [], protocolMessageChannelSerial: nil) }
        let root = try await getTask.value

        // Assertions
        _ = root as any PathObject // ASSERT root IS PathObject
        #expect(root.path.isEmpty) // ASSERT root.path == []
        #expect(Self.channelState(f) == .attached) // ASSERT channel.state == ATTACHED
    }

    // MARK: - RTO23d get() resolves immediately when already SYNCED

    // UTS: objects/unit/RTO23d/get-resolves-immediately-synced-0
    @Test
    func getResolvesImmediatelyWhenSynced() async throws {
        // Setup
        let f = Self.makeFixture()
        Self.setupSyncedChannel(f)

        // Test Steps
        let root2 = try await f.object.get()

        // Assertions
        _ = root2 as any PathObject // ASSERT root2 IS PathObject
        #expect(root2.path.isEmpty) // ASSERT root2.path == []
    }

    // MARK: - RTO10b1 GC grace period from ConnectionDetails

    // UTS: objects/unit/RTO10b1/gc-grace-period-source-0
    @Test
    func gcGracePeriodFromConnectionDetails() async throws {
        // Setup — the server-provided grace period is 5000ms (vs the 24h default). Applied via the
        // CONNECTED handler stand-in `nosync_setGarbageCollectionGracePeriod` (seconds).
        let f = Self.makeFixture()
        Self.setupSyncedChannel(f)
        let root = try await f.object.get()
        Self.onQueue(f) { f.engine.nosync_setGarbageCollectionGracePeriod(5) } // 5000ms

        // Tombstone stamped "now": after a 6s advance it is eligible under the 5s server-provided grace
        // but NOT under the 24h default, so this fails if the connection value is ignored.
        f.engine.testsOnly_applyObjectMessages(
            [TestFactories.objectDeleteOperationMessage(objectId: "counter:score@1000", serial: "99", siteCode: "site1", serialTimestamp: f.clock.now)],
            source: .channel,
        )

        // Test Steps
        f.clock.advance(by: 5 + 1) // ADVANCE_TIME(5000 + 1000) ms
        f.engine.performGarbageCollection()

        // Assertions
        #expect(try root.get(key: "score").asLiveCounter().value() == nil) // ASSERT root.get("score").value() == null
    }

    // MARK: - RTO17, RTO18 Sync event sequences for all state transitions

    // UTS: objects/unit/RTO17-RTO18/sync-event-sequences-0
    @Test
    func syncEventSequencesForAllTransitions() async throws {
        // "initial attach": a genuine FIRST attach, observed on a fresh non-synced channel with the
        // listeners registered BEFORE the attach. ATTACHED(HAS_OBJECTS) -> SYNCING, OBJECT_SYNC -> SYNCED.
        do {
            let f = Self.makeFixture()
            let events = Log()
            f.object.on(event: .syncing) { events.append("SYNCING") }
            f.object.on(event: .synced) { events.append("SYNCED") }
            Self.onQueue(f) { f.engine.nosync_onChannelAttached(hasObjects: true) }
            Self.onQueue(f) { f.engine.nosync_handleObjectSyncProtocolMessage(objectMessages: [], protocolMessageChannelSerial: nil) }
            Self.drain(f)
            #expect(events.all == ["SYNCING", "SYNCED"]) // ASSERT events == ["SYNCING", "SYNCED"]
        }

        // "re-sync on new ATTACHED": from SYNCED, a new ATTACHED(HAS_OBJECTS) + OBJECT_SYNC re-syncs.
        do {
            let f = Self.makeFixture()
            Self.setupSyncedChannel(f, seed: false)
            let events = Log()
            f.object.on(event: .syncing) { events.append("SYNCING") }
            f.object.on(event: .synced) { events.append("SYNCED") }
            Self.onQueue(f) { f.engine.nosync_onChannelAttached(hasObjects: true) }
            Self.onQueue(f) { f.engine.nosync_handleObjectSyncProtocolMessage(objectMessages: [], protocolMessageChannelSerial: nil) }
            Self.drain(f)
            #expect(events.all == ["SYNCING", "SYNCED"]) // ASSERT events == ["SYNCING", "SYNCED"]
        }

        // "ATTACHED without HAS_OBJECTS": RTO4c transitions SYNCED -> SYNCING, then RTO4b4 completes the
        // sync immediately -> SYNCED.
        do {
            let f = Self.makeFixture()
            Self.setupSyncedChannel(f, seed: false)
            let events = Log()
            f.object.on(event: .syncing) { events.append("SYNCING") }
            f.object.on(event: .synced) { events.append("SYNCED") }
            Self.onQueue(f) { f.engine.nosync_onChannelAttached(hasObjects: false) }
            Self.drain(f)
            #expect(events.all == ["SYNCING", "SYNCED"]) // ASSERT events == ["SYNCING", "SYNCED"]
        }
    }

    // MARK: - RTO27 Objects data lifecycle on channel state transitions

    // UTS: objects/unit/RTO27/channel-state-data-lifecycle-0
    @Test
    func channelStateDataLifecycle() async throws {
        // RTO27a - DETACHED / FAILED clears data without emitting update events.
        for state in [ChannelState.detached, .failed] {
            let f = Self.makeFixture()
            Self.setupSyncedChannel(f)
            let root = try await f.object.get()

            // sanity: STANDARD_POOL_OBJECTS materialised — root map, a counter, and a NESTED map.
            let poolBefore = f.engine.testsOnly_objectsPool
            #expect(try #require(poolBefore.entries[ObjectsPool.rootKey]?.mapValue).testsOnly_data["name"] != nil) // ASSERT "name" IN pool["root"].data
            #expect(try #require(poolBefore.entries["counter:score@1000"]?.counterValue).testsOnly_data == 100) // ASSERT pool["counter:score@1000"].value == 100
            #expect(try #require(poolBefore.entries["map:profile@1000"]?.mapValue).testsOnly_data["email"] != nil) // ASSERT "email" IN pool["map:profile@1000"].data

            // RTO27a1: no update events must be emitted during the clear (subscribe to root's instance).
            let updates = ObjectsUTSInstanceEventCollector()
            let rootInstance = try #require(try root.instance())
            guard case let .liveMap(rootMap) = rootInstance else {
                Issue.record("expected root to resolve to a .liveMap instance")
                return
            }
            let sub = try rootMap.subscribe(listener: updates.listener)
            defer { sub.unsubscribe() }

            // channel.object.processChannelState(state) — the engine's channel-state handler.
            Self.onQueue(f) { f.engine.nosync_onChannelStateChanged(toState: state, reason: nil) }
            Self.drain(f)

            // RTO27a1: EVERY object's data is cleared; the objects themselves remain in the pool.
            let poolAfter = f.engine.testsOnly_objectsPool
            #expect(try #require(poolAfter.entries[ObjectsPool.rootKey]?.mapValue).testsOnly_data.isEmpty) // ASSERT pool["root"].data == {}
            #expect(poolAfter.entries["counter:score@1000"] != nil) // ASSERT "counter:score@1000" IN pool
            #expect(try #require(poolAfter.entries["counter:score@1000"]?.counterValue).testsOnly_data == 0) // ASSERT pool["counter:score@1000"].value == 0
            #expect(poolAfter.entries["map:profile@1000"] != nil) // ASSERT "map:profile@1000" IN pool
            #expect(try #require(poolAfter.entries["map:profile@1000"]?.mapValue).testsOnly_data.isEmpty) // ASSERT pool["map:profile@1000"].data == {}
            #expect(updates.events.isEmpty) // ASSERT updates.length == 0
        }

        // RTO27b - SUSPENDED retains data.
        do {
            let f = Self.makeFixture()
            Self.setupSyncedChannel(f)
            _ = try await f.object.get()

            Self.onQueue(f) { f.engine.nosync_onChannelStateChanged(toState: .suspended, reason: nil) } // RTO27b: no-op for objects data

            // RTO27b: data retained unchanged — root, the counter, and the nested map.
            let pool = f.engine.testsOnly_objectsPool
            #expect(try #require(pool.entries[ObjectsPool.rootKey]?.mapValue).testsOnly_data["name"] != nil) // ASSERT "name" IN pool["root"].data
            #expect(try #require(pool.entries["counter:score@1000"]?.counterValue).testsOnly_data == 100) // ASSERT pool["counter:score@1000"].value == 100
            #expect(try #require(pool.entries["map:profile@1000"]?.mapValue).testsOnly_data["email"] != nil) // ASSERT "email" IN pool["map:profile@1000"].data
        }
    }
}
