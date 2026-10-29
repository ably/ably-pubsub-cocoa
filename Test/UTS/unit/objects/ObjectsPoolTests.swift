// Derived from the UTS spec `objects/unit/objects_pool.md`.
//
// These ports drive the ObjectsPool sync state machine directly. In cocoa the pool's
// INITIALIZED -> SYNCING -> SYNCED state machine, its buffered-operation queue (RTO7), and the
// RTO7b `appliedOnAckSerials` set live one layer up on `InternalDefaultRealtimeObjects` (the spec's
// `RealtimeObject`), which *owns* the `ObjectsPool`; the pool value type itself is just the
// `Dict<String, LiveObject>`. So the spec's `pool.processAttached` / `pool.processObjectSync` /
// `pool.processObjectMessage` / `pool.syncState` map onto
// `InternalDefaultRealtimeObjects.nosync_onChannelAttached` /
// `.nosync_handleObjectSyncProtocolMessage` / `.nosync_handleObjectProtocolMessage` and
// `testsOnly_syncState` (see the shape-deviation note S-1 in deviations.md).
//
// Infra-driving stand-ins (NOT deviations): the unit tier has no channel/connection/transport, so
// there is no ATTACHED / OBJECT_SYNC / OBJECT PROTOCOL frame — the state machine is driven through
// the internal `nosync_*` entry points and the pool is seeded directly (`testsOnly_setPoolEntry` /
// direct node construction). `appliedOnAckSerials` has no direct setter, so it is seeded through the
// sanctioned RTO9a2a4 entry point (`testsOnly_applyObjectMessages(_:source:.local)`), exactly how a
// serial actually enters that set in production. Every serial/siteCode comes from `StandardTestPool`
// or the spec's own literal values.
//
// Deviations from the UTS spec (recorded in deviations.md):
// - (D-1) RTO7-RTO8: the spec asserts an OBJECT message received in INITIALIZED is buffered (RTO8a
//   "buffer if not SYNCED"). cocoa buffers iff SYNCING and applies immediately in INITIALIZED — a
//   documented equivalence (operations only arrive after ATTACHED in production). The port asserts
//   cocoa's actual behaviour and keeps the spec ASSERT as a comment.

import _AblyPluginSupportPrivate
import AblyPubSubDevice
@testable import AblyLiveObjects
@testable import AblyLiveObjectsTesting
import Foundation
import Testing

struct ObjectsPoolTests {
    // MARK: - Helpers

    /// The spec's standard object `siteTimeserials: { "aaa": "t:0" }` baseline.
    private static let poolSiteTimeserials = ["aaa": StandardTestPool.poolSerial]

    private static func makeRealtimeObjects(internalQueue: DispatchQueue) -> InternalDefaultRealtimeObjects {
        InternalDefaultRealtimeObjects(
            logger: TestLogger(),
            internalQueue: internalQueue,
            userCallbackQueue: .main,
            clock: MockSimpleClock(),
            channelName: "test-channel",
        )
    }

    /// `pool.processAttached(ProtocolMessage(action: ATTACHED, flags: hasObjects ? HAS_OBJECTS : 0))`.
    private static func attach(_ realtimeObjects: InternalDefaultRealtimeObjects, hasObjects: Bool, on internalQueue: DispatchQueue) {
        internalQueue.ably_syncNoDeadlock {
            realtimeObjects.nosync_onChannelAttached(hasObjects: hasObjects)
        }
    }

    /// `pool.processObjectSync(build_object_sync_message(channel, channelSerial, objectMessages))`.
    private static func processObjectSync(_ realtimeObjects: InternalDefaultRealtimeObjects, _ messages: [ProtocolTypes.InboundObjectMessage], channelSerial: String?, on internalQueue: DispatchQueue) {
        internalQueue.ably_syncNoDeadlock {
            realtimeObjects.nosync_handleObjectSyncProtocolMessage(objectMessages: messages, protocolMessageChannelSerial: channelSerial)
        }
    }

    /// `pool.processObjectSync(...)` convenience wrapping bare `ObjectState`s (the `build_object_state`
    /// form) into `build_object_message_with_state` messages.
    private static func processObjectSync(_ realtimeObjects: InternalDefaultRealtimeObjects, states: [ProtocolTypes.ObjectState], channelSerial: String?, on internalQueue: DispatchQueue) {
        processObjectSync(realtimeObjects, states.map { TestFactories.inboundObjectMessage(object: $0) }, channelSerial: channelSerial, on: internalQueue)
    }

    /// `pool.processObjectMessage(build_object_message(channel, objectMessages))`.
    private static func processObjectMessage(_ realtimeObjects: InternalDefaultRealtimeObjects, _ messages: [ProtocolTypes.InboundObjectMessage], on internalQueue: DispatchQueue) {
        internalQueue.ably_syncNoDeadlock {
            realtimeObjects.nosync_handleObjectProtocolMessage(objectMessages: messages)
        }
    }

    private static func counter(_ realtimeObjects: InternalDefaultRealtimeObjects, _ objectID: String) -> InternalDefaultLiveCounter? {
        realtimeObjects.testsOnly_objectsPool.entries[objectID]?.counterValue
    }

    private static func map(_ realtimeObjects: InternalDefaultRealtimeObjects, _ objectID: String) -> InternalDefaultLiveMap? {
        realtimeObjects.testsOnly_objectsPool.entries[objectID]?.mapValue
    }

    /// An empty root `ObjectState` with the standard `{ map: {LWW, {}}, createOp: {mapCreate: {LWW, {}}} }` shape.
    private static func emptyRootState(siteTimeserials: [String: String]? = nil) -> ProtocolTypes.ObjectState {
        TestFactories.mapObjectState(
            objectId: "root",
            siteTimeserials: siteTimeserials ?? poolSiteTimeserials,
            createOp: TestFactories.mapCreateOperation(objectId: "root", entries: [:]),
            entries: [:],
        )
    }

    // MARK: - RTO3

    // UTS: objects/unit/RTO3/pool-init-root-0
    @Test
    func poolInitialisesWithRootInternalLiveMap() throws {
        // Setup
        let internalQueue = ObjectsUTS.createInternalQueue()
        let pool = ObjectsUTS.freshPool(internalQueue: internalQueue) // pool = ObjectsPool()

        // Assertions
        let root = try #require(pool.entries["root"]) // RTO3b: "root" IN pool
        let rootMap = try #require(root.mapValue) // RTO3a/RTO3b: pool["root"] IS InternalLiveMap
        #expect(rootMap.testsOnly_data.isEmpty) // RTO3b1: pool["root"].data == {}
        #expect(rootMap.testsOnly_objectID == "root") // RTO3b1: pool["root"].objectId == "root"
    }

    // MARK: - RTO4a

    // UTS: objects/unit/RTO4/attached-has-objects-syncing-0
    @Test
    func attachedWithHasObjectsFlagStartsSyncing() {
        // Setup
        let internalQueue = ObjectsUTS.createInternalQueue()
        let realtimeObjects = Self.makeRealtimeObjects(internalQueue: internalQueue)

        // Test Steps — ATTACHED with HAS_OBJECTS (RTO4a)
        Self.attach(realtimeObjects, hasObjects: true, on: internalQueue)

        // Assertions
        #expect(realtimeObjects.testsOnly_syncState == .syncing) // RTO4c
    }

    // MARK: - RTO4b

    // UTS: objects/unit/RTO4b/attached-no-objects-synced-0
    @available(iOS 17.0.0, tvOS 17.0.0, *)
    @Test
    func attachedWithoutHasObjectsClearsPoolAndGoesToSynced() async throws {
        // Setup
        let internalQueue = ObjectsUTS.createInternalQueue()
        let realtimeObjects = Self.makeRealtimeObjects(internalQueue: internalQueue)
        let coreSDK = MockCoreSDK(channelState: .attached, internalQueue: internalQueue)

        // pool["counter:abc@1000"] = InternalLiveCounter(...)
        realtimeObjects.testsOnly_setPoolEntry(.counter(ObjectsUTS.makeCounter(objectID: "counter:abc@1000", internalQueue: internalQueue)), forObjectID: "counter:abc@1000")
        // pool["root"].data = { "name": { data: { string: "Alice" }, timeserial: "01", tombstone: false } }
        let root = ObjectsUTS.makeMap(objectID: "root", data: ["name": ObjectsUTS.mapEntry(data: ProtocolTypes.ObjectData(string: "Alice"), timeserial: "01")], internalQueue: internalQueue)
        realtimeObjects.testsOnly_setPoolEntry(.map(root), forObjectID: "root")

        // Test Steps
        let updates = Subscriber<DefaultLiveMapUpdate, SubscribeResponse>(callbackQueue: .main)
        try root.subscribe(listener: updates.createListener(), coreSDK: coreSDK) // pool["root"].subscribe(...)
        Self.attach(realtimeObjects, hasObjects: false, on: internalQueue) // ATTACHED, flags: 0

        // Assertions
        #expect(realtimeObjects.testsOnly_syncState == .synced)
        #expect(Self.counter(realtimeObjects, "counter:abc@1000") == nil) // RTO4b1: "counter:abc@1000" NOT IN pool
        #expect(Self.map(realtimeObjects, "root") != nil) // "root" IN pool
        #expect(try #require(Self.map(realtimeObjects, "root")).testsOnly_data.isEmpty) // RTO4b2: pool["root"].data == {}

        let invocations = await updates.getInvocations()
        #expect(invocations.count >= 1) // updates.length >= 1
        let firstUpdate = try #require(invocations.first?.0)
        #expect(firstUpdate.update == ["name": .removed]) // RTO4b2a: updates[0].update == { "name": "removed" }
        #expect(firstUpdate.objectMessage == nil) // RTO4b2a: updates[0].objectMessage IS null (sync-originated)
    }

    // UTS: objects/unit/RTO4b2a/reset-of-empty-root-emits-no-update-0
    @available(iOS 17.0.0, tvOS 17.0.0, *)
    @Test
    func attachedWithoutHasObjectsOnEmptyRootEmitsNoUpdate() async throws {
        // Setup
        let internalQueue = ObjectsUTS.createInternalQueue()
        let realtimeObjects = Self.makeRealtimeObjects(internalQueue: internalQueue)
        let coreSDK = MockCoreSDK(channelState: .attached, internalQueue: internalQueue)

        // pool["counter:abc@1000"] = InternalLiveCounter(...); root is already empty (RTLM4c zero-value)
        realtimeObjects.testsOnly_setPoolEntry(.counter(ObjectsUTS.makeCounter(objectID: "counter:abc@1000", internalQueue: internalQueue)), forObjectID: "counter:abc@1000")

        // Test Steps
        let updates = Subscriber<DefaultLiveMapUpdate, SubscribeResponse>(callbackQueue: .main)
        try realtimeObjects.testsOnly_objectsPool.root.subscribe(listener: updates.createListener(), coreSDK: coreSDK)
        Self.attach(realtimeObjects, hasObjects: false, on: internalQueue) // ATTACHED, flags: 0

        // Assertions
        #expect(realtimeObjects.testsOnly_syncState == .synced)
        #expect(Self.counter(realtimeObjects, "counter:abc@1000") == nil) // RTO4b1: non-root objects still removed
        #expect(Self.map(realtimeObjects, "root") != nil) // "root" IN pool
        #expect(try #require(Self.map(realtimeObjects, "root")).testsOnly_data.isEmpty) // pool["root"].data == {}
        // RTO4b2a: no keys were removed, so the empty update collapses to a no-op and is not delivered
        #expect(await updates.getInvocations().isEmpty) // updates.length == 0

        // Liveness control: a reset that DOES remove a key still emits, proving the wiring is live.
        let control = Subscriber<DefaultLiveMapUpdate, SubscribeResponse>(callbackQueue: .main)
        let realtimeObjects2 = Self.makeRealtimeObjects(internalQueue: internalQueue)
        let root2 = ObjectsUTS.makeMap(objectID: "root", data: ["name": ObjectsUTS.mapEntry(data: ProtocolTypes.ObjectData(string: "Alice"), timeserial: "01")], internalQueue: internalQueue)
        realtimeObjects2.testsOnly_setPoolEntry(.map(root2), forObjectID: "root")
        try root2.subscribe(listener: control.createListener(), coreSDK: coreSDK)
        Self.attach(realtimeObjects2, hasObjects: false, on: internalQueue)
        let controlInvocations = await control.getInvocations()
        #expect(controlInvocations.count >= 1) // control.length >= 1
        #expect(try #require(controlInvocations.first?.0).update == ["name": .removed]) // control[0].update == { "name": "removed" }
    }

    // MARK: - RTO5

    // UTS: objects/unit/RTO5/sync-complete-sequence-0
    @Test
    func objectSyncCompleteSequence() throws {
        // Setup
        let internalQueue = ObjectsUTS.createInternalQueue()
        let realtimeObjects = Self.makeRealtimeObjects(internalQueue: internalQueue)
        Self.attach(realtimeObjects, hasObjects: true, on: internalQueue)

        // Test Steps
        let rootState = TestFactories.mapObjectState(
            objectId: "root",
            siteTimeserials: Self.poolSiteTimeserials,
            createOp: TestFactories.mapCreateOperation(objectId: "root", entries: [:]),
            entries: ["name": TestFactories.mapEntry(timeserial: StandardTestPool.poolSerial, data: ProtocolTypes.ObjectData(string: "Alice"))],
        )
        let counterState = TestFactories.counterObjectState(
            objectId: "counter:abc@1000",
            siteTimeserials: Self.poolSiteTimeserials,
            createOp: TestFactories.counterCreateOperation(objectId: "counter:abc@1000", count: 42),
            count: 0,
        )
        Self.processObjectSync(realtimeObjects, states: [rootState, counterState], channelSerial: "sync1:", on: internalQueue) // RTO5a4: cursor empty -> complete

        // Assertions
        #expect(realtimeObjects.testsOnly_syncState == .synced) // RTO5c8
        #expect(Self.map(realtimeObjects, "root") != nil) // "root" IN pool
        #expect(Self.counter(realtimeObjects, "counter:abc@1000") != nil) // "counter:abc@1000" IN pool
        #expect(try #require(Self.map(realtimeObjects, "root")).testsOnly_data["name"]?.data?.string == "Alice") // pool["root"].data["name"].data == { string: "Alice" }
        #expect(try #require(Self.counter(realtimeObjects, "counter:abc@1000")).testsOnly_data == 42) // pool["counter:abc@1000"].data == 42
    }

    // UTS: objects/unit/RTO5a2/new-sequence-discards-old-0
    @Test
    func newSyncSequenceDiscardsPrevious() {
        // Setup
        let internalQueue = ObjectsUTS.createInternalQueue()
        let realtimeObjects = Self.makeRealtimeObjects(internalQueue: internalQueue)
        Self.attach(realtimeObjects, hasObjects: true, on: internalQueue)
        Self.processObjectSync(realtimeObjects, states: [
            TestFactories.counterObjectState(objectId: "counter:old@1000", siteTimeserials: Self.poolSiteTimeserials, count: 10),
        ], channelSerial: "seq1:more", on: internalQueue)

        // Test Steps — new sequence id starts fresh sync (RTO5a2)
        Self.processObjectSync(realtimeObjects, states: [
            Self.emptyRootState(),
            TestFactories.counterObjectState(objectId: "counter:new@1000", siteTimeserials: Self.poolSiteTimeserials, count: 99),
        ], channelSerial: "seq2:", on: internalQueue)

        // Assertions
        #expect(realtimeObjects.testsOnly_syncState == .synced)
        #expect(Self.counter(realtimeObjects, "counter:old@1000") == nil) // RTO5a2a: SyncObjectsPool cleared
        #expect(Self.counter(realtimeObjects, "counter:new@1000") != nil)
    }

    // UTS: objects/unit/RTO5a5/absent-channel-serial-0
    @Test
    func objectSyncWithNoChannelSerialIsSingleMessageSync() {
        // Setup
        let internalQueue = ObjectsUTS.createInternalQueue()
        let realtimeObjects = Self.makeRealtimeObjects(internalQueue: internalQueue)
        Self.attach(realtimeObjects, hasObjects: true, on: internalQueue)

        // Test Steps — no channelSerial: the whole sync is contained in this one message (RTO5a5)
        Self.processObjectSync(realtimeObjects, states: [
            TestFactories.counterObjectState(objectId: "counter:new@1000", siteTimeserials: Self.poolSiteTimeserials, count: 99),
        ], channelSerial: nil, on: internalQueue)

        // Assertions
        #expect(realtimeObjects.testsOnly_syncState == .synced)
        #expect(Self.counter(realtimeObjects, "counter:new@1000") != nil)
    }

    // UTS: objects/unit/RTO5a6/malformed-channel-serial-treated-as-absent-0
    @Test
    func malformedChannelSerialTreatedAsAbsent() {
        // Setup
        let internalQueue = ObjectsUTS.createInternalQueue()
        let realtimeObjects = Self.makeRealtimeObjects(internalQueue: internalQueue)
        Self.attach(realtimeObjects, hasObjects: true, on: internalQueue)

        // Test Steps — "malformedserialnocolon" has no ':' separator (RTO5a1), so RTO5a6 handles it as
        // if the channelSerial were absent (RTO5a5).
        Self.processObjectSync(realtimeObjects, states: [
            TestFactories.counterObjectState(objectId: "counter:new@1000", siteTimeserials: Self.poolSiteTimeserials, count: 99),
        ], channelSerial: "malformedserialnocolon", on: internalQueue)

        // Assertions — treated as absent (RTO5a5): the message was applied and the sync ended.
        #expect(realtimeObjects.testsOnly_syncState == .synced)
        #expect(Self.counter(realtimeObjects, "counter:new@1000") != nil)
    }

    // UTS: objects/unit/RTO5f2a/partial-map-merge-0
    @Test
    func partialObjectStateMergeForMaps() throws {
        // Setup
        let internalQueue = ObjectsUTS.createInternalQueue()
        let realtimeObjects = Self.makeRealtimeObjects(internalQueue: internalQueue)
        Self.attach(realtimeObjects, hasObjects: true, on: internalQueue)

        // Test Steps — two messages of the same sequence, each carrying a partial root state (RTO5f2)
        Self.processObjectSync(realtimeObjects, states: [
            TestFactories.mapObjectState(objectId: "root", siteTimeserials: Self.poolSiteTimeserials, entries: ["name": TestFactories.mapEntry(timeserial: StandardTestPool.poolSerial, data: ProtocolTypes.ObjectData(string: "Alice"))]),
        ], channelSerial: "sync1:more", on: internalQueue)
        Self.processObjectSync(realtimeObjects, states: [
            TestFactories.mapObjectState(objectId: "root", siteTimeserials: Self.poolSiteTimeserials, createOp: TestFactories.mapCreateOperation(objectId: "root", entries: [:]), entries: ["age": TestFactories.mapEntry(timeserial: StandardTestPool.poolSerial, data: ProtocolTypes.ObjectData(number: NSNumber(value: 30)))]),
        ], channelSerial: "sync1:", on: internalQueue)

        // Assertions — RTO5f2a2: entries from both messages are merged
        let root = try #require(Self.map(realtimeObjects, "root"))
        #expect(root.testsOnly_data["name"]?.data?.string == "Alice") // pool["root"].data["name"].data == { string: "Alice" }
        #expect(root.testsOnly_data["age"]?.data?.number?.intValue == 30) // pool["root"].data["age"].data == { number: 30 }
    }

    // UTS: objects/unit/RTO5c2/remove-absent-objects-0
    @Test
    func syncCompletionRemovesObjectsNotInSync() {
        // Setup
        let internalQueue = ObjectsUTS.createInternalQueue()
        let realtimeObjects = Self.makeRealtimeObjects(internalQueue: internalQueue)
        // pool["counter:old@1000"] = InternalLiveCounter(...); .data = 99
        realtimeObjects.testsOnly_setPoolEntry(.counter(ObjectsUTS.makeCounter(objectID: "counter:old@1000", data: 99, internalQueue: internalQueue)), forObjectID: "counter:old@1000")
        Self.attach(realtimeObjects, hasObjects: true, on: internalQueue)

        // Test Steps — sync with only root
        Self.processObjectSync(realtimeObjects, states: [Self.emptyRootState()], channelSerial: "sync1:", on: internalQueue)

        // Assertions
        #expect(Self.counter(realtimeObjects, "counter:old@1000") == nil) // RTO5c2: removed (not received during sync)
        #expect(Self.map(realtimeObjects, "root") != nil) // RTO5c2a: root must not be removed
    }

    // UTS: objects/unit/RTO5c9/clear-applied-on-ack-serials-0
    @Test
    func syncCompletionClearsAppliedOnAckSerials() {
        // Setup
        let internalQueue = ObjectsUTS.createInternalQueue()
        let realtimeObjects = Self.makeRealtimeObjects(internalQueue: internalQueue)

        // realtime_object.appliedOnAckSerials = {"serial-1", "serial-2"}. cocoa has no direct setter,
        // so seed via the sanctioned RTO9a2a4 LOCAL-apply entry point (how a serial actually enters
        // the set) — on throwaway counters whose data is irrelevant to this test.
        realtimeObjects.testsOnly_applyObjectMessages([
            ObjectsUTS.counterIncMessage(objectId: "counter:seed1@1000", number: 1, serial: "serial-1", siteCode: StandardTestPool.siteCode),
            ObjectsUTS.counterIncMessage(objectId: "counter:seed2@1000", number: 1, serial: "serial-2", siteCode: StandardTestPool.siteCode),
        ], source: .local)
        #expect(realtimeObjects.testsOnly_appliedOnAckSerials == ["serial-1", "serial-2"])

        Self.attach(realtimeObjects, hasObjects: true, on: internalQueue)

        // Test Steps
        Self.processObjectSync(realtimeObjects, states: [Self.emptyRootState()], channelSerial: "sync1:", on: internalQueue)

        // Assertions — RTO5c9: appliedOnAckSerials cleared after sync
        #expect(realtimeObjects.testsOnly_appliedOnAckSerials.isEmpty) // realtime_object.appliedOnAckSerials == {}
    }

    // MARK: - RTO7 / RTO8

    // UTS: objects/unit/RTO8a/buffer-during-syncing-0
    @Test
    func objectMessagesBufferedDuringSyncing() {
        // Setup
        let internalQueue = ObjectsUTS.createInternalQueue()
        let realtimeObjects = Self.makeRealtimeObjects(internalQueue: internalQueue)
        Self.attach(realtimeObjects, hasObjects: true, on: internalQueue)

        // Test Steps
        Self.processObjectMessage(realtimeObjects, [
            ObjectsUTS.counterIncMessage(objectId: "counter:abc@1000", number: 5, serial: "01", siteCode: "site1"),
        ], on: internalQueue)

        // Assertions
        #expect(realtimeObjects.testsOnly_syncState == .syncing)
        #expect(realtimeObjects.testsOnly_bufferedObjectOperationsCount == 1) // RTO8a / RTO7a
        #expect(Self.counter(realtimeObjects, "counter:abc@1000") == nil) // buffered, not applied
    }

    // UTS: objects/unit/RTO5c6/apply-buffered-on-sync-0
    @Test
    func bufferedOperationsAppliedOnSyncCompletion() throws {
        // Setup
        let internalQueue = ObjectsUTS.createInternalQueue()
        let realtimeObjects = Self.makeRealtimeObjects(internalQueue: internalQueue)
        Self.attach(realtimeObjects, hasObjects: true, on: internalQueue)
        Self.processObjectMessage(realtimeObjects, [
            ObjectsUTS.counterIncMessage(objectId: "counter:abc@1000", number: 10, serial: "02", siteCode: "site1"),
        ], on: internalQueue)

        // Test Steps
        Self.processObjectSync(realtimeObjects, states: [
            Self.emptyRootState(),
            TestFactories.counterObjectState(objectId: "counter:abc@1000", siteTimeserials: Self.poolSiteTimeserials, createOp: TestFactories.counterCreateOperation(objectId: "counter:abc@1000", count: 100), count: 0),
        ], channelSerial: "sync1:", on: internalQueue)

        // Assertions — RTO5c6: buffered op (10) applied on top of synced createOp value (100)
        #expect(try #require(Self.counter(realtimeObjects, "counter:abc@1000")).testsOnly_data == 110) // pool["counter:abc@1000"].data == 110
        // bufferedObjectOperations.length == 0 — cocoa leaves SYNCED, so no buffer exists (nil, not 0).
        #expect(realtimeObjects.testsOnly_bufferedObjectOperationsCount == nil)
    }

    // MARK: - RTO9

    // UTS: objects/unit/RTO9a1/null-operation-warning-0
    @Test
    func nullOperationIsDiscardedWithWarning() {
        // Setup
        let internalQueue = ObjectsUTS.createInternalQueue()
        let realtimeObjects = Self.makeRealtimeObjects(internalQueue: internalQueue)
        Self.attach(realtimeObjects, hasObjects: false, on: internalQueue) // pool.syncState = SYNCED

        // Test Steps — ObjectMessage with operation: null (RTO9a1)
        Self.processObjectMessage(realtimeObjects, [
            TestFactories.inboundObjectMessage(operation: nil, serial: "01", siteCode: "site1"),
        ], on: internalQueue)

        // Assertions — discarded: no object created, only root remains
        #expect(realtimeObjects.testsOnly_objectsPool.entries.count == 1) // pool.keys().length == 1
    }

    // UTS: objects/unit/RTO9a3/dedup-applied-on-ack-0
    @Test
    func appliedOnAckSerialsDeduplication() throws {
        // Setup
        let internalQueue = ObjectsUTS.createInternalQueue()
        let realtimeObjects = Self.makeRealtimeObjects(internalQueue: internalQueue)
        Self.attach(realtimeObjects, hasObjects: false, on: internalQueue) // pool.syncState = SYNCED

        // pool["counter:abc@1000"] = InternalLiveCounter(...); .data = 10
        realtimeObjects.testsOnly_setPoolEntry(.counter(ObjectsUTS.makeCounter(objectID: "counter:abc@1000", data: 10, internalQueue: internalQueue)), forObjectID: "counter:abc@1000")
        // realtime_object.appliedOnAckSerials = {"echo-serial-1"} — seeded via the RTO9a2a4 LOCAL-apply
        // entry point on a throwaway object, so counter:abc@1000's data stays exactly 10.
        realtimeObjects.testsOnly_applyObjectMessages([
            ObjectsUTS.counterIncMessage(objectId: "counter:seed@1000", number: 1, serial: "echo-serial-1", siteCode: "site1"),
        ], source: .local)
        #expect(realtimeObjects.testsOnly_appliedOnAckSerials.contains("echo-serial-1"))

        // Test Steps — a channel-sourced COUNTER_INC whose serial is already in appliedOnAckSerials
        Self.processObjectMessage(realtimeObjects, [
            ObjectsUTS.counterIncMessage(objectId: "counter:abc@1000", number: 5, serial: "echo-serial-1", siteCode: "site1"),
        ], on: internalQueue)

        // Assertions — RTO9a3: discarded and removed from the set
        #expect(try #require(Self.counter(realtimeObjects, "counter:abc@1000")).testsOnly_data == 10) // pool["counter:abc@1000"].data == 10
        #expect(!realtimeObjects.testsOnly_appliedOnAckSerials.contains("echo-serial-1")) // "echo-serial-1" NOT IN appliedOnAckSerials
    }

    // UTS: objects/unit/RTO9a2a4/local-source-adds-serial-0
    @Test
    func localSourceAddsSerialToAppliedOnAckSerials() throws {
        // Setup
        let internalQueue = ObjectsUTS.createInternalQueue()
        let realtimeObjects = Self.makeRealtimeObjects(internalQueue: internalQueue)
        Self.attach(realtimeObjects, hasObjects: false, on: internalQueue) // pool.syncState = SYNCED
        _ = realtimeObjects.testsOnly_createZeroValueLiveObject(forObjectID: "counter:abc@1000") // pool["counter:abc@1000"] = InternalLiveCounter(...)

        // Test Steps — pool.applyObjectMessages([...], source: LOCAL)
        realtimeObjects.testsOnly_applyObjectMessages([
            ObjectsUTS.counterIncMessage(objectId: "counter:abc@1000", number: 5, serial: "local-serial-1", siteCode: StandardTestPool.siteCode),
        ], source: .local)

        // Assertions — RTO9a2a4
        #expect(realtimeObjects.testsOnly_appliedOnAckSerials.contains("local-serial-1")) // "local-serial-1" IN appliedOnAckSerials
        #expect(try #require(Self.counter(realtimeObjects, "counter:abc@1000")).testsOnly_data == 5) // pool["counter:abc@1000"].data == 5
    }

    // UTS: objects/unit/RTO9a2b/unsupported-action-warning-0
    @Test
    func unsupportedActionIsDiscardedWithWarning() {
        // Setup
        let internalQueue = ObjectsUTS.createInternalQueue()
        let realtimeObjects = Self.makeRealtimeObjects(internalQueue: internalQueue)
        Self.attach(realtimeObjects, hasObjects: false, on: internalQueue) // pool.syncState = SYNCED

        // Test Steps — operation with an UNKNOWN_ACTION (RTO9a2b)
        Self.processObjectMessage(realtimeObjects, [
            TestFactories.inboundObjectMessage(
                operation: TestFactories.objectOperation(action: .unknown(999), objectId: "counter:abc@1000"), // UNKNOWN_ACTION (RTO9a2b): an unrecognised action raw value
                serial: "01",
                siteCode: "site1",
            ),
        ], on: internalQueue)

        // Assertions — discarded: no object created, only root remains
        #expect(realtimeObjects.testsOnly_objectsPool.entries.count == 1) // pool.keys().length == 1
    }

    // MARK: - RTO6

    // UTS: objects/unit/RTO6/zero-value-from-prefix-0
    @Test
    func zeroValueObjectCreationFromObjectIdPrefix() throws {
        // Setup
        let internalQueue = ObjectsUTS.createInternalQueue()
        let realtimeObjects = Self.makeRealtimeObjects(internalQueue: internalQueue)
        Self.attach(realtimeObjects, hasObjects: false, on: internalQueue) // pool.syncState = SYNCED

        // Test Steps
        Self.processObjectMessage(realtimeObjects, [
            ObjectsUTS.counterIncMessage(objectId: "counter:new@2000", number: 5, serial: "01", siteCode: "site1"),
        ], on: internalQueue)
        Self.processObjectMessage(realtimeObjects, [
            TestFactories.mapSetOperationMessage(objectId: "map:new@2000", key: "key", value: "val", serial: "01", siteCode: "site1"),
        ], on: internalQueue)

        // Assertions
        let newCounter = try #require(Self.counter(realtimeObjects, "counter:new@2000")) // RTO6b3: "counter" prefix -> InternalLiveCounter
        #expect(newCounter.testsOnly_data == 5) // pool["counter:new@2000"].data == 5

        let newMap = try #require(Self.map(realtimeObjects, "map:new@2000")) // RTO6b2: "map" prefix -> InternalLiveMap
        #expect(newMap.testsOnly_data["key"]?.data?.string == "val") // pool["map:new@2000"].data["key"].data == { string: "val" }
    }

    // MARK: - RTO5d / RTO5f3 / RTO5e

    // UTS: objects/unit/RTO5d/null-object-skipped-0
    @Test
    func objectSyncWithNullObjectFieldIsSkipped() {
        // Setup
        let internalQueue = ObjectsUTS.createInternalQueue()
        let realtimeObjects = Self.makeRealtimeObjects(internalQueue: internalQueue)
        Self.attach(realtimeObjects, hasObjects: true, on: internalQueue)

        // Test Steps — one message has object: null (RTO5d, skipped), plus a valid root
        Self.processObjectSync(realtimeObjects, [
            TestFactories.inboundObjectMessage(object: nil), // ObjectMessage(object: null)
            TestFactories.inboundObjectMessage(object: Self.emptyRootState()),
        ], channelSerial: "sync1:", on: internalQueue)

        // Assertions
        #expect(realtimeObjects.testsOnly_syncState == .synced)
    }

    // UTS: objects/unit/RTO5f3/unsupported-type-skipped-0
    @Test
    func objectSyncWithUnsupportedObjectTypeIsSkipped() {
        // Setup
        let internalQueue = ObjectsUTS.createInternalQueue()
        let realtimeObjects = Self.makeRealtimeObjects(internalQueue: internalQueue)
        Self.attach(realtimeObjects, hasObjects: true, on: internalQueue)

        // Test Steps — the second object has neither map nor counter (RTO5f3, skipped)
        Self.processObjectSync(realtimeObjects, states: [
            Self.emptyRootState(),
            TestFactories.objectState(objectId: "unknown:xyz@1000", siteTimeserials: [:], map: nil, counter: nil),
        ], channelSerial: "sync1:", on: internalQueue)

        // Assertions
        #expect(realtimeObjects.testsOnly_syncState == .synced)
        #expect(realtimeObjects.testsOnly_objectsPool.entries["unknown:xyz@1000"] == nil) // "unknown:xyz@1000" NOT IN pool
    }

    // UTS: objects/unit/RTO5e/object-sync-transitions-syncing-0
    @Test
    func objectSyncTransitionsToSyncing() {
        // Setup
        let internalQueue = ObjectsUTS.createInternalQueue()
        let realtimeObjects = Self.makeRealtimeObjects(internalQueue: internalQueue)

        // Test Steps — OBJECT_SYNC received while not already SYNCING (RTO5e); "sync1:more" keeps the
        // sequence in flight so we can observe the SYNCING transition.
        Self.processObjectSync(realtimeObjects, states: [
            TestFactories.mapObjectState(objectId: "root", siteTimeserials: Self.poolSiteTimeserials, entries: [:]),
        ], channelSerial: "sync1:more", on: internalQueue)

        // Assertions
        #expect(realtimeObjects.testsOnly_syncState == .syncing)
    }

    // MARK: - RTO5c7

    // UTS: objects/unit/RTO5c7/sync-emits-updates-0
    @available(iOS 17.0.0, tvOS 17.0.0, *)
    @Test
    func syncCompletionEmitsUpdatesForExistingObjects() async throws {
        // Setup
        let internalQueue = ObjectsUTS.createInternalQueue()
        let realtimeObjects = Self.makeRealtimeObjects(internalQueue: internalQueue)
        let coreSDK = MockCoreSDK(channelState: .attached, internalQueue: internalQueue)

        // pool["root"].data = { "name": { string: "Old", timeserial: "01" } }
        let root = ObjectsUTS.makeMap(objectID: "root", data: ["name": ObjectsUTS.mapEntry(data: ProtocolTypes.ObjectData(string: "Old"), timeserial: "01")], internalQueue: internalQueue)
        realtimeObjects.testsOnly_setPoolEntry(.map(root), forObjectID: "root")

        let updates = Subscriber<DefaultLiveMapUpdate, SubscribeResponse>(callbackQueue: .main)
        try root.subscribe(listener: updates.createListener(), coreSDK: coreSDK) // pool["root"].subscribe(...)
        Self.attach(realtimeObjects, hasObjects: true, on: internalQueue)

        // Test Steps — sync re-states root's "name" as "New"
        Self.processObjectSync(realtimeObjects, states: [
            TestFactories.mapObjectState(objectId: "root", siteTimeserials: Self.poolSiteTimeserials, createOp: TestFactories.mapCreateOperation(objectId: "root", entries: [:]), entries: ["name": TestFactories.mapEntry(timeserial: StandardTestPool.poolSerial, data: ProtocolTypes.ObjectData(string: "New"))]),
        ], channelSerial: "sync1:", on: internalQueue)

        // Assertions — RTO5c7: the stored LiveObjectUpdate is emitted
        let invocations = await updates.getInvocations()
        #expect(invocations.count >= 1) // updates.length >= 1
        let firstUpdate = try #require(invocations.first?.0)
        #expect(firstUpdate.update["name"] == .updated) // "name" IN updates[0].update; updates[0].update["name"] == "updated"
    }

    // MARK: - RTO5f2b

    // UTS: objects/unit/RTO5f2b/partial-counter-error-0
    @Test
    func partialCounterStateLogsError() throws {
        // Setup
        let internalQueue = ObjectsUTS.createInternalQueue()
        let realtimeObjects = Self.makeRealtimeObjects(internalQueue: internalQueue)
        Self.attach(realtimeObjects, hasObjects: true, on: internalQueue)

        // Test Steps — two partial counter states for the same object in one sequence. RTO5f2b: a
        // partial counter merge logs an error and is skipped, so the first value (10) survives.
        Self.processObjectSync(realtimeObjects, states: [
            TestFactories.counterObjectState(objectId: "counter:abc@1000", siteTimeserials: Self.poolSiteTimeserials, count: 10),
        ], channelSerial: "sync1:more", on: internalQueue)
        Self.processObjectSync(realtimeObjects, states: [
            Self.emptyRootState(),
            TestFactories.counterObjectState(objectId: "counter:abc@1000", siteTimeserials: Self.poolSiteTimeserials, count: 5),
        ], channelSerial: "sync1:", on: internalQueue)

        // Assertions
        #expect(try #require(Self.counter(realtimeObjects, "counter:abc@1000")).testsOnly_data == 10) // pool["counter:abc@1000"].data == 10
    }

    // MARK: - RTO4d

    // UTS: objects/unit/RTO4d/attached-clears-buffer-0
    @Test
    func attachedClearsBufferedOperations() {
        // Setup
        let internalQueue = ObjectsUTS.createInternalQueue()
        let realtimeObjects = Self.makeRealtimeObjects(internalQueue: internalQueue)
        Self.attach(realtimeObjects, hasObjects: true, on: internalQueue)
        Self.processObjectMessage(realtimeObjects, [
            ObjectsUTS.counterIncMessage(objectId: "counter:abc@1000", number: 5, serial: "01", siteCode: "site1"),
        ], on: internalQueue)
        #expect(realtimeObjects.testsOnly_bufferedObjectOperationsCount == 1)

        // Test Steps — a fresh ATTACHED (HAS_OBJECTS) during SYNCING (RTO4d)
        Self.attach(realtimeObjects, hasObjects: true, on: internalQueue)

        // Assertions
        #expect(realtimeObjects.testsOnly_bufferedObjectOperationsCount == 0) // RTO4d
    }

    // MARK: - RTO4 / RTO5

    // UTS: objects/unit/RTO4-RTO5/attached-during-syncing-resets-0
    @Test
    func attachedDuringSyncingResetsSync() {
        // Setup
        let internalQueue = ObjectsUTS.createInternalQueue()
        let realtimeObjects = Self.makeRealtimeObjects(internalQueue: internalQueue)
        Self.attach(realtimeObjects, hasObjects: true, on: internalQueue)
        Self.processObjectSync(realtimeObjects, states: [
            TestFactories.counterObjectState(objectId: "counter:old@1000", siteTimeserials: Self.poolSiteTimeserials, count: 10),
        ], channelSerial: "sync1:more", on: internalQueue)
        #expect(realtimeObjects.testsOnly_syncState == .syncing)

        // Test Steps — a new ATTACHED during SYNCING, then a fresh sync sequence
        Self.attach(realtimeObjects, hasObjects: true, on: internalQueue)
        Self.processObjectSync(realtimeObjects, states: [
            Self.emptyRootState(),
            TestFactories.counterObjectState(objectId: "counter:new@1000", siteTimeserials: Self.poolSiteTimeserials, count: 99),
        ], channelSerial: "sync2:", on: internalQueue)

        // Assertions
        #expect(realtimeObjects.testsOnly_syncState == .synced)
        #expect(Self.counter(realtimeObjects, "counter:old@1000") == nil) // interrupted sequence discarded
        #expect(Self.counter(realtimeObjects, "counter:new@1000") != nil)
    }

    // UTS: objects/unit/RTO5-RTO7/new-sync-keeps-buffer-0
    @Test
    func newObjectSyncSequenceDoesNotClearBuffer() throws {
        // Setup
        let internalQueue = ObjectsUTS.createInternalQueue()
        let realtimeObjects = Self.makeRealtimeObjects(internalQueue: internalQueue)
        Self.attach(realtimeObjects, hasObjects: true, on: internalQueue)
        Self.processObjectMessage(realtimeObjects, [
            ObjectsUTS.counterIncMessage(objectId: "counter:abc@1000", number: 5, serial: "01", siteCode: "site1"),
        ], on: internalQueue)
        #expect(realtimeObjects.testsOnly_bufferedObjectOperationsCount == 1)

        // Test Steps — a new OBJECT_SYNC sequence (RTO5a2) discards only the SyncObjectsPool; the
        // buffered OBJECT operation is retained and applied after completion.
        Self.processObjectSync(realtimeObjects, states: [
            Self.emptyRootState(),
            TestFactories.counterObjectState(objectId: "counter:abc@1000", siteTimeserials: Self.poolSiteTimeserials, createOp: TestFactories.counterCreateOperation(objectId: "counter:abc@1000", count: 100), count: 0),
        ], channelSerial: "seq2:", on: internalQueue)

        // Assertions — synced createOp value (100) + retained buffered inc (5)
        #expect(realtimeObjects.testsOnly_syncState == .synced)
        #expect(try #require(Self.counter(realtimeObjects, "counter:abc@1000")).testsOnly_data == 105) // pool["counter:abc@1000"].data == 105
    }

    // UTS: objects/unit/RTO7-RTO8/buffer-without-attached-0
    @Test
    func objectMessagesBufferedEvenWithoutPrecedingAttached() throws {
        // Setup
        let internalQueue = ObjectsUTS.createInternalQueue()
        let realtimeObjects = Self.makeRealtimeObjects(internalQueue: internalQueue)
        #expect(realtimeObjects.testsOnly_syncState == .initialized)

        // Test Steps
        Self.processObjectMessage(realtimeObjects, [
            ObjectsUTS.counterIncMessage(objectId: "counter:abc@1000", number: 5, serial: "01", siteCode: "site1"),
        ], on: internalQueue)

        // Assertions
        // Spec ASSERT: bufferedObjectOperations.length == 1 (RTO8a: INITIALIZED also buffers).
        // SDK deviation (D-1, deviations.md): cocoa buffers iff SYNCING and applies OBJECT messages
        // immediately in INITIALIZED (a documented equivalence — operations only arrive after ATTACHED
        // in production). So the injected message is applied immediately rather than buffered.
        #expect(realtimeObjects.testsOnly_bufferedObjectOperationsCount == nil) // not SYNCING -> no buffer
        #expect(try #require(Self.counter(realtimeObjects, "counter:abc@1000")).testsOnly_data == 5) // applied immediately (RTO8b path)
    }

    // MARK: - RTO5c / RTLM23

    // UTS: objects/unit/RTO5c-RTLM23/sync-clear-timeserial-hides-create-entries-0
    @Test
    func syncWithClearTimeserialHidesInitialCreateOpEntries() throws {
        // Setup
        let internalQueue = ObjectsUTS.createInternalQueue()
        let realtimeObjects = Self.makeRealtimeObjects(internalQueue: internalQueue)
        Self.attach(realtimeObjects, hasObjects: true, on: internalQueue)

        // Test Steps — root's ObjectState carries a clearTimeserial "05"; createOp entries with serials
        // <= "05" are rejected during merge (RTLM23).
        let rootState = TestFactories.objectState(
            objectId: "root",
            siteTimeserials: Self.poolSiteTimeserials,
            createOp: TestFactories.mapCreateOperation(objectId: "root", entries: [
                "old_key": TestFactories.mapEntry(timeserial: "03", data: ProtocolTypes.ObjectData(string: "old")),
                "new_key": TestFactories.mapEntry(timeserial: "07", data: ProtocolTypes.ObjectData(string: "new")),
            ]),
            map: TestFactories.objectsMap(entries: [:], clearTimeserial: "05"),
        )
        Self.processObjectSync(realtimeObjects, states: [rootState], channelSerial: "sync1:", on: internalQueue)

        // Assertions
        #expect(realtimeObjects.testsOnly_syncState == .synced)
        let root = try #require(Self.map(realtimeObjects, "root"))
        #expect(root.testsOnly_data["old_key"] == nil) // "old_key" NOT IN pool["root"].data (serial <= clearTimeserial)
        #expect(root.testsOnly_data["new_key"]?.data?.string == "new") // pool["root"].data["new_key"].data == { string: "new" }
    }

    // MARK: - RTO5c10 (parent references)

    // UTS: objects/unit/RTO5c10/sync-rebuilds-parent-refs-0
    @Test
    func syncCompletionRebuildsParentReferences() throws {
        // Setup
        let internalQueue = ObjectsUTS.createInternalQueue()
        let realtimeObjects = Self.makeRealtimeObjects(internalQueue: internalQueue)
        Self.attach(realtimeObjects, hasObjects: true, on: internalQueue)

        // Test Steps
        Self.processObjectSync(realtimeObjects, states: [
            TestFactories.mapObjectState(objectId: "root", siteTimeserials: Self.poolSiteTimeserials, createOp: TestFactories.mapCreateOperation(objectId: "root", entries: [:]), entries: [
                "score": TestFactories.mapEntry(timeserial: StandardTestPool.poolSerial, data: ProtocolTypes.ObjectData(objectId: "counter:score@1000")),
                "profile": TestFactories.mapEntry(timeserial: StandardTestPool.poolSerial, data: ProtocolTypes.ObjectData(objectId: "map:profile@1000")),
                "name": TestFactories.mapEntry(timeserial: StandardTestPool.poolSerial, data: ProtocolTypes.ObjectData(string: "Alice")),
            ]),
            TestFactories.counterObjectState(objectId: "counter:score@1000", siteTimeserials: Self.poolSiteTimeserials, createOp: TestFactories.counterCreateOperation(objectId: "counter:score@1000", count: 100), count: 0),
            TestFactories.mapObjectState(objectId: "map:profile@1000", siteTimeserials: Self.poolSiteTimeserials, createOp: TestFactories.mapCreateOperation(objectId: "map:profile@1000", entries: [:]), entries: [
                "nested_counter": TestFactories.mapEntry(timeserial: StandardTestPool.poolSerial, data: ProtocolTypes.ObjectData(objectId: "counter:nested@1000")),
            ]),
            TestFactories.counterObjectState(objectId: "counter:nested@1000", siteTimeserials: Self.poolSiteTimeserials, createOp: TestFactories.counterCreateOperation(objectId: "counter:nested@1000", count: 5), count: 0),
        ], channelSerial: "sync1:", on: internalQueue)

        // Assertions — RTO5c10
        #expect(try #require(Self.map(realtimeObjects, "root")).testsOnly_parentReferences == [:]) // root not referenced by any parent
        #expect(try #require(Self.counter(realtimeObjects, "counter:score@1000")).testsOnly_parentReferences == ["root": ["score"]])
        #expect(try #require(Self.map(realtimeObjects, "map:profile@1000")).testsOnly_parentReferences == ["root": ["profile"]])
        #expect(try #require(Self.counter(realtimeObjects, "counter:nested@1000")).testsOnly_parentReferences == ["map:profile@1000": ["nested_counter"]])
    }

    // UTS: objects/unit/RTO5c10/resync-rebuilds-parent-refs-0
    @Test
    func resyncRebuildsParentReferencesWithNewTreeStructure() throws {
        // Setup — first sync: counter:abc@1000 is a child of root
        let internalQueue = ObjectsUTS.createInternalQueue()
        let realtimeObjects = Self.makeRealtimeObjects(internalQueue: internalQueue)
        Self.attach(realtimeObjects, hasObjects: true, on: internalQueue)
        Self.processObjectSync(realtimeObjects, states: [
            TestFactories.mapObjectState(objectId: "root", siteTimeserials: Self.poolSiteTimeserials, createOp: TestFactories.mapCreateOperation(objectId: "root", entries: [:]), entries: [
                "counter_key": TestFactories.mapEntry(timeserial: StandardTestPool.poolSerial, data: ProtocolTypes.ObjectData(objectId: "counter:abc@1000")),
            ]),
            TestFactories.counterObjectState(objectId: "counter:abc@1000", siteTimeserials: Self.poolSiteTimeserials, createOp: TestFactories.counterCreateOperation(objectId: "counter:abc@1000", count: 10), count: 0),
        ], channelSerial: "sync1:", on: internalQueue)
        #expect(try #require(Self.counter(realtimeObjects, "counter:abc@1000")).testsOnly_parentReferences == ["root": ["counter_key"]])

        // Test Steps — second sync: counter:abc@1000 is now a child of map:wrapper@1000, not root
        let secondSerial = StandardTestPool.remoteSerial(0) // "t:1"
        Self.attach(realtimeObjects, hasObjects: true, on: internalQueue)
        Self.processObjectSync(realtimeObjects, states: [
            TestFactories.mapObjectState(objectId: "root", siteTimeserials: ["aaa": secondSerial], createOp: TestFactories.mapCreateOperation(objectId: "root", entries: [:]), entries: [
                "wrapper": TestFactories.mapEntry(timeserial: secondSerial, data: ProtocolTypes.ObjectData(objectId: "map:wrapper@1000")),
            ]),
            TestFactories.mapObjectState(objectId: "map:wrapper@1000", siteTimeserials: ["aaa": secondSerial], createOp: TestFactories.mapCreateOperation(objectId: "map:wrapper@1000", entries: [:]), entries: [
                "moved_counter": TestFactories.mapEntry(timeserial: secondSerial, data: ProtocolTypes.ObjectData(objectId: "counter:abc@1000")),
            ]),
            TestFactories.counterObjectState(objectId: "counter:abc@1000", siteTimeserials: ["aaa": secondSerial], createOp: TestFactories.counterCreateOperation(objectId: "counter:abc@1000", count: 20), count: 0),
        ], channelSerial: "sync2:", on: internalQueue)

        // Assertions
        #expect(realtimeObjects.testsOnly_syncState == .synced)
        #expect(try #require(Self.map(realtimeObjects, "root")).testsOnly_parentReferences == [:]) // root not referenced by any parent
        #expect(try #require(Self.map(realtimeObjects, "map:wrapper@1000")).testsOnly_parentReferences == ["root": ["wrapper"]])
        #expect(try #require(Self.counter(realtimeObjects, "counter:abc@1000")).testsOnly_parentReferences == ["map:wrapper@1000": ["moved_counter"]]) // moved, no longer under root
    }

    // UTS: objects/unit/RTO5c10/empty-sync-parent-refs-0
    @Test
    func emptySyncLeavesRootWithEmptyParentReferences() throws {
        // Setup — a normal sync to populate parentReferences
        let internalQueue = ObjectsUTS.createInternalQueue()
        let realtimeObjects = Self.makeRealtimeObjects(internalQueue: internalQueue)
        Self.attach(realtimeObjects, hasObjects: true, on: internalQueue)
        Self.processObjectSync(realtimeObjects, states: [
            TestFactories.mapObjectState(objectId: "root", siteTimeserials: Self.poolSiteTimeserials, createOp: TestFactories.mapCreateOperation(objectId: "root", entries: [:]), entries: [
                "child": TestFactories.mapEntry(timeserial: StandardTestPool.poolSerial, data: ProtocolTypes.ObjectData(objectId: "counter:child@1000")),
            ]),
            TestFactories.counterObjectState(objectId: "counter:child@1000", siteTimeserials: Self.poolSiteTimeserials, createOp: TestFactories.counterCreateOperation(objectId: "counter:child@1000", count: 1), count: 0),
        ], channelSerial: "sync1:", on: internalQueue)
        #expect(try #require(Self.counter(realtimeObjects, "counter:child@1000")).testsOnly_parentReferences == ["root": ["child"]])

        // Test Steps — empty sync: ATTACHED without HAS_OBJECTS (RTO4b)
        Self.attach(realtimeObjects, hasObjects: false, on: internalQueue)

        // Assertions
        #expect(realtimeObjects.testsOnly_syncState == .synced)
        #expect(Self.counter(realtimeObjects, "counter:child@1000") == nil) // RTO4b1: removed from pool
        let root = try #require(Self.map(realtimeObjects, "root"))
        #expect(root.testsOnly_data.isEmpty) // pool["root"].data == {}
        #expect(root.testsOnly_parentReferences == [:]) // RTO5c10a: reset to empty
    }
}
