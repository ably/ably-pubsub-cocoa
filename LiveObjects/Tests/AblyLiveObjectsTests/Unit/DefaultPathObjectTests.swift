import _AblyPluginSupportPrivate
@testable import AblyLiveObjects
@testable import AblyLiveObjectsTesting
import AblyPubSubDevice
import Foundation
import Testing

/// Tests for the Phase 4 (part 1) path layer: ``PathSegments``, ``DefaultPathObject`` and its typed
/// subclasses, the ``ChannelConfigGuards`` state checks, and the extended error model. Path
/// *subscriptions* (RTPO19/RTO24) are part 2 and are not exercised here (they still trap).
///
/// Everything is driven through a seeded ``ObjectsPool`` and a local ``SeededRealtimeObjects`` double
/// so path resolution walks root -> children exactly as production does.
struct DefaultPathObjectTests {
    // MARK: - Construction helpers

    private static func makeMap(objectID: String, data: [String: InternalObjectsMapEntry] = [:], internalQueue: DispatchQueue) -> InternalDefaultLiveMap {
        InternalDefaultLiveMap(testsOnly_data: data, objectID: objectID, logger: TestLogger(), internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
    }

    private static func makeCounter(objectID: String, data: Double, internalQueue: DispatchQueue) -> InternalDefaultLiveCounter {
        InternalDefaultLiveCounter(testsOnly_data: data, objectID: objectID, logger: TestLogger(), internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
    }

    /// Builds a seeded pool whose root map has:
    /// - `s` -> string "hi"
    /// - `n` -> number 5
    /// - `cnt` -> counter (value 42)
    /// - `m` -> nested map with entry `deep` -> string "leaf"
    ///
    /// Returns the realtime-objects double, the shared queue and a core SDK in the requested state.
    private static func makeFixture(channelState: _AblyPluginSupportPrivate.RealtimeChannelState = .attached) -> (realtimeObjects: SeededRealtimeObjects, coreSDK: MockCoreSDK, internalQueue: DispatchQueue) {
        let internalQueue = TestFactories.createInternalQueue()
        let coreSDK = MockCoreSDK(channelState: channelState, internalQueue: internalQueue)

        let nestedMap = makeMap(
            objectID: "map:child@0",
            data: ["deep": TestFactories.internalMapEntry(data: ProtocolTypes.ObjectData(string: "leaf"))],
            internalQueue: internalQueue,
        )
        let counter = makeCounter(objectID: "counter:c@0", data: 42, internalQueue: internalQueue)
        let root = makeMap(
            objectID: ObjectsPool.rootKey,
            data: [
                "s": TestFactories.internalMapEntry(data: ProtocolTypes.ObjectData(string: "hi")),
                "n": TestFactories.internalMapEntry(data: ProtocolTypes.ObjectData(number: NSNumber(value: 5))),
                "cnt": TestFactories.internalMapEntry(data: ProtocolTypes.ObjectData(objectId: "counter:c@0")),
                "m": TestFactories.internalMapEntry(data: ProtocolTypes.ObjectData(objectId: "map:child@0")),
            ],
            internalQueue: internalQueue,
        )

        var pool = ObjectsPool(
            logger: TestLogger(),
            internalQueue: internalQueue,
            userCallbackQueue: .main,
            clock: MockSimpleClock(),
            testsOnly_otherEntries: [
                "counter:c@0": .counter(counter),
                "map:child@0": .map(nestedMap),
            ],
        )
        // Replace the auto-created empty root with our seeded root map.
        pool.testsOnly_setEntry(.map(root), forObjectID: ObjectsPool.rootKey)

        return (SeededRealtimeObjects(pool: pool, internalQueue: internalQueue), coreSDK, internalQueue)
    }

    private static func rootPathObject(_ fixture: (realtimeObjects: SeededRealtimeObjects, coreSDK: MockCoreSDK, internalQueue: DispatchQueue)) -> DefaultLiveMapPathObject {
        DefaultLiveMapPathObject(channelObject: fixture.realtimeObjects, coreSDK: fixture.coreSDK, internalQueue: fixture.internalQueue, segments: [])
    }

    // MARK: - PathSegments escaping (RTPO4, RTPO6)

    // @spec RTPO4b - dots inside a segment are escaped on render; @spec RTPO6b - parsing honours the escape
    @Test
    func pathSegmentsEscaping() {
        // Empty segment list renders to the empty (root) path: zero segments (RTPO4c).
        #expect(PathSegments.join([]).isEmpty)

        // RTPO4b: a dot inside a segment is escaped when rendered.
        #expect(PathSegments.join(["a.b", "c"]) == #"a\.b.c"#)
        // RTPO6b: parsing honours the escaped dot.
        #expect(PathSegments.parse(#"a\.b.c"#) == ["a.b", "c"])

        // A backslash inside a segment renders as-is (only dots are escaped, ably-js `_escapePath`
        // parity) — the stored segment is never re-parsed, so no ambiguity arises.
        #expect(PathSegments.join([#"a\"#, "b"]) == #"a\.b"#)

        // User sub-path parsing: "" is one empty segment (ably-js `at("")` parity).
        #expect(PathSegments.parse("") == [""])
        #expect(PathSegments.parse("x.y") == ["x", "y"])
    }

    // MARK: - Resolution & type discrimination (RTPO3, RTTS4)

    // @spec RTTS4a - exists reflects resolution; @spec RTTS4b - type discriminates the resolved value
    @Test
    func resolvesRootAndNestedValues() throws {
        let fixture = Self.makeFixture()
        let root = Self.rootPathObject(fixture)

        // Root (empty path) is always the root map.
        #expect(try root.exists())
        #expect(try root.type() == .liveMap)

        // Nested primitive, number, counter and map.
        #expect(try root.get(key: "s").type() == .string)
        #expect(try root.get(key: "n").type() == .number)
        #expect(try root.get(key: "cnt").type() == .liveCounter)
        #expect(try root.get(key: "m").type() == .liveMap)
        // Deep navigation via at().
        #expect(try root.at(path: "m.deep").type() == .string)
        #expect(try root.at(path: "m.deep").exists())
    }

    // @spec RTPO3c1 - an unresolved path degrades to nil/false for all reads
    @Test
    func unresolvedPathDegradesGracefully() throws {
        let fixture = Self.makeFixture()
        let root = Self.rootPathObject(fixture)

        let missing = root.get(key: "nope")
        #expect(try !missing.exists()) // RTTS4a
        #expect(try missing.type() == nil) // RTTS4b3
        #expect(try missing.instance() == nil) // RTPO8e
        #expect(try missing.compactJson() == nil) // RTPO3c1
        #expect(try missing.asPrimitive().value() == nil)
        #expect(try missing.asLiveCounter().value() == nil)
        // A path that tries to navigate through a primitive mid-path is also unresolved (RTPO3a1).
        #expect(try !root.at(path: "s.child").exists())
    }

    // MARK: - Navigation (RTPO5, RTPO6)

    // @spec RTPO5c - get appends an escaped key; @spec RTPO6c - at appends a parsed sub-path
    @Test
    func navigationBuildsStoredPath() {
        let fixture = Self.makeFixture()
        let root = Self.rootPathObject(fixture)

        #expect(root.get(key: "a").path == "a")
        #expect(root.get(key: "a.b").path == #"a\.b"#) // dot in key is escaped on render (RTPO4b)
        // A backslash in a key is stored verbatim in the segment and rendered as-is (only dots are
        // escaped, ably-js parity); the raw key survives navigation unambiguously.
        #expect(root.get(key: #"a\"#).path == #"a\"#)
        #expect(root.at(path: "x.y").path == "x.y")
        #expect(root.get(key: "a").asLiveMap().at(path: "b.c").path == "a.b.c")
    }

    // MARK: - Casts (RTTS5)

    // @spec RTTS5a - casts are pure type refinements that preserve the path and never resolve
    @Test
    func castsPreservePathWithoutResolving() {
        let fixture = Self.makeFixture()
        let node = Self.rootPathObject(fixture).get(key: "cnt")

        #expect(node.asLiveMap().path == "cnt")
        #expect(node.asLiveCounter().path == "cnt")
        #expect(node.asPrimitive().path == "cnt")
    }

    // MARK: - compactJson (RTPO14) & instance (RTPO8)

    // @spec RTPO14b - compactJson recursively compacts maps, counters and primitives
    @Test
    func compactJsonPerType() throws {
        let fixture = Self.makeFixture()
        let root = Self.rootPathObject(fixture)

        #expect(try root.get(key: "s").compactJson() == .string("hi"))
        #expect(try root.get(key: "cnt").compactJson() == .number(42)) // RTPO13d
        #expect(try root.get(key: "m").compactJson() == .object(["deep": .string("leaf")])) // RTPO13c2
    }

    // @spec RTPO8c - instance wraps a live object; @spec RTPO8f - instance wraps a primitive
    @Test
    func instanceWrapsResolvedValue() throws {
        let fixture = Self.makeFixture()
        let root = Self.rootPathObject(fixture)

        guard case .liveCounter = try #require(try root.get(key: "cnt").instance()) else {
            Issue.record("Expected .liveCounter instance")
            return
        }
        guard case .liveMap = try #require(try root.get(key: "m").instance()) else {
            Issue.record("Expected .liveMap instance")
            return
        }
        // RTPO8f: a primitive resolves to a primitive Instance (not nil).
        guard case let .primitive(primitive) = try #require(try root.get(key: "s").instance()) else {
            Issue.record("Expected .primitive instance")
            return
        }
        #expect(try primitive.value == .string("hi"))
    }

    // MARK: - Map reads (RTPO9, RTPO10, RTPO11, RTPO12)

    // @spec RTPO10 - keys; @spec RTPO12 - size; @spec RTPO9 - entries; @spec RTPO11 - values
    @Test
    func mapReads() throws {
        let fixture = Self.makeFixture()
        let root = Self.rootPathObject(fixture)

        #expect(try Set(root.keys()) == ["s", "n", "cnt", "m"])
        #expect(try root.size() == 4)
        #expect(try root.entries().count == 4)
        #expect(try root.values().count == 4)
        // entries()/values() yield child path objects addressed as if by get().
        let entriesByKey = try Dictionary(uniqueKeysWithValues: root.entries().map { ($0.key, $0.value) })
        #expect(entriesByKey["s"]?.path == "s")

        // A map read on a non-map path degrades: nil size, empty collections (RTPO12d/RTPO10d).
        let counterPath = root.get(key: "cnt").asLiveMap()
        #expect(try counterPath.size() == nil)
        #expect(try counterPath.keys().isEmpty)
    }

    // MARK: - Counter read (RTTS6b)

    // @spec RTTS6b - a counter path resolves to its value; a non-counter path yields nil
    @Test
    func counterValue() throws {
        let fixture = Self.makeFixture()
        let root = Self.rootPathObject(fixture)

        #expect(try root.get(key: "cnt").asLiveCounter().value() == 42)
        // Wrong type via the counter cast degrades to nil on read.
        #expect(try root.get(key: "s").asLiveCounter().value() == nil)
    }

    // MARK: - Primitive reads (RTTS6b) and the per-case convenience accessors

    /// A root map holding one entry per ``Primitive`` case, keyed by the case name. Separate from
    /// ``makeFixture()`` so that the entry count the map-read tests assert on stays fixed.
    private static func makePrimitivesRootPathObject() -> DefaultLiveMapPathObject {
        let internalQueue = TestFactories.createInternalQueue()
        let coreSDK = MockCoreSDK(channelState: .attached, internalQueue: internalQueue)

        let root = makeMap(
            objectID: ObjectsPool.rootKey,
            data: [
                "string": TestFactories.internalMapEntry(data: ProtocolTypes.ObjectData(string: "hi")),
                "number": TestFactories.internalMapEntry(data: ProtocolTypes.ObjectData(number: NSNumber(value: 5))),
                "bool": TestFactories.internalMapEntry(data: ProtocolTypes.ObjectData(boolean: true)),
                "data": TestFactories.internalMapEntry(data: ProtocolTypes.ObjectData(bytes: Data([1, 2, 3]))),
                "jsonArray": TestFactories.internalMapEntry(data: ProtocolTypes.ObjectData(json: ["a"])),
                "jsonObject": TestFactories.internalMapEntry(data: ProtocolTypes.ObjectData(json: ["k": "v"])),
            ],
            internalQueue: internalQueue,
        )

        var pool = ObjectsPool(logger: TestLogger(), internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
        pool.testsOnly_setEntry(.map(root), forObjectID: ObjectsPool.rootKey)

        return DefaultLiveMapPathObject(
            channelObject: SeededRealtimeObjects(pool: pool, internalQueue: internalQueue),
            coreSDK: coreSDK,
            internalQueue: internalQueue,
            segments: [],
        )
    }

    @Test
    func primitiveConvenienceAccessors() throws {
        let root = Self.makePrimitivesRootPathObject()

        #expect(try root.get(key: "string").asPrimitive().stringValue() == "hi")
        #expect(try root.get(key: "number").asPrimitive().numberValue() == 5)
        #expect(try root.get(key: "bool").asPrimitive().boolValue() == true)
        #expect(try root.get(key: "data").asPrimitive().dataValue() == Data([1, 2, 3]))
        #expect(try root.get(key: "jsonArray").asPrimitive().jsonArrayValue() == ["a"])
        #expect(try root.get(key: "jsonObject").asPrimitive().jsonObjectValue() == ["k": "v"])

        // An accessor for a case other than the one that resolved yields nil, as does any accessor on
        // a path that does not resolve to a primitive at all.
        #expect(try root.get(key: "string").asPrimitive().numberValue() == nil)
        #expect(try root.get(key: "nope").asPrimitive().stringValue() == nil)
    }

    // MARK: - Writes via the publish path (RTPO15, RTPO17)

    // @spec RTPO15d - set publishes a MAP_SET operation for the resolved map
    @Test
    func mapSetPublishesMapSet() async throws {
        let fixture = Self.makeFixture()
        let root = Self.rootPathObject(fixture)

        // Set on the root map (empty path always resolves).
        try await root.set(key: "greeting", value: .primitive(.string("hi")))

        let messages = try #require(fixture.realtimeObjects.capturedMessages)
        #expect(messages.count == 1)
        #expect(messages[0].operation?.action == .known(.mapSet))
        #expect(messages[0].operation?.objectId == ObjectsPool.rootKey)
        #expect(messages[0].operation?.mapSet?.key == "greeting")
    }

    // @spec RTPO17d - increment publishes a COUNTER_INC operation for the resolved counter
    @Test
    func counterIncrementPublishesCounterInc() async throws {
        let fixture = Self.makeFixture()
        let root = Self.rootPathObject(fixture)

        try await root.get(key: "cnt").asLiveCounter().increment(amount: 3)

        let messages = try #require(fixture.realtimeObjects.capturedMessages)
        #expect(messages.count == 1)
        #expect(messages[0].operation?.action == .known(.counterInc))
        #expect(messages[0].operation?.objectId == "counter:c@0")
        #expect(messages[0].operation?.counterInc?.number == NSNumber(value: 3))
    }

    // MARK: - Write error model (92005, 92007)

    // @spec RTPO17e - a write through a mismatched-type cast throws 92007
    @Test
    func writeThroughWrongTypeCastThrows92007() async throws {
        let fixture = Self.makeFixture()
        let root = Self.rootPathObject(fixture)

        // "cnt" resolves to a counter; incrementing through the counter cast is fine, but setting a
        // key via the map cast must fail with a type mismatch.
        await #expect { () async throws in
            try await root.get(key: "cnt").asLiveMap().set(key: "k", value: .primitive(.string("v")))
        } throws: { error in
            (error as? ErrorInfo)?.code == 92007
        }
    }

    // MARK: - Channel-config guards (RTO25, RTO26)

    // @spec RTO25 - a read on a DETACHED channel throws (implementable state-check portion of the guard)
    @Test
    func readOnDetachedChannelThrows() throws {
        let fixture = Self.makeFixture(channelState: .detached)
        let root = Self.rootPathObject(fixture)

        #expect(throws: ErrorInfo.self) {
            _ = try root.exists()
        }
        #expect(throws: ErrorInfo.self) {
            _ = try root.get(key: "s").type()
        }

        // The convenience accessors delegate to `value()`, so they must propagate the same error.
        #expect(throws: ErrorInfo.self) {
            _ = try root.get(key: "s").asPrimitive().stringValue()
        }
    }

    // @spec RTO26 - a write on a SUSPENDED channel throws (implementable state-check portion of the guard)
    @Test
    func writeOnSuspendedChannelThrows() async throws {
        let fixture = Self.makeFixture(channelState: .suspended)
        let root = Self.rootPathObject(fixture)

        await #expect(throws: ErrorInfo.self) {
            try await root.set(key: "k", value: .primitive(.string("v")))
        }
    }

    // MARK: - Channel-mode guards (RTO2a2 / RTO2b2)

    // @spec RTO2a2 - a read on a channel without the `object_subscribe` mode throws 40024
    @Test
    func readWithoutObjectSubscribeModeThrows() throws {
        let fixture = Self.makeFixture()
        // Channel configured only with object_publish — missing object_subscribe.
        fixture.coreSDK.setObjectChannelModes([.objectPublish])
        let root = Self.rootPathObject(fixture)

        let error = try #require(throws: ErrorInfo.self) {
            _ = try root.exists()
        }
        #expect(error.code == 40024)
        #expect(error.statusCode == 400)
        #expect(error.message == "\"object_subscribe\" channel mode must be set for this operation")
    }

    // @spec RTO2b2 - a write on a channel without the `object_publish` mode throws 40024
    @Test
    func writeWithoutObjectPublishModeThrows() async throws {
        let fixture = Self.makeFixture()
        // Channel configured only with object_subscribe — missing object_publish.
        fixture.coreSDK.setObjectChannelModes([.objectSubscribe])
        let root = Self.rootPathObject(fixture)

        let error = try await #require(throws: ErrorInfo.self) {
            try await root.set(key: "k", value: .primitive(.string("v")))
        }
        #expect(error.code == 40024)
        #expect(error.message == "\"object_publish\" channel mode must be set for this operation")
    }

    // @spec RTO2a2 - when no modes are configured at all, the access guard also throws 40024
    @Test
    func readWithNoModesThrows() throws {
        let fixture = Self.makeFixture()
        fixture.coreSDK.setObjectChannelModes([])
        let root = Self.rootPathObject(fixture)

        let error = try #require(throws: ErrorInfo.self) {
            _ = try root.get(key: "s").type()
        }
        #expect(error.code == 40024)
    }

    // @spec RTO2a2 - the get() mode guard (throwIfMissingObjectSubscribeMode) throws 40024 when the
    // `object_subscribe` mode is absent, and passes when present (no channel-state check).
    @Test
    func objectSubscribeModeGuardForGet() throws {
        let internalQueue = TestFactories.createInternalQueue()

        // Present (even on a DETACHED channel — get() delegates state handling to ensure-active).
        let withMode = MockCoreSDK(channelState: .detached, objectChannelModes: [.objectSubscribe], internalQueue: internalQueue)
        #expect(throws: Never.self) {
            try ChannelConfigGuards.throwIfMissingObjectSubscribeMode(coreSDK: withMode, internalQueue: internalQueue)
        }

        // Absent: throws 40024.
        let withoutMode = MockCoreSDK(channelState: .attached, objectChannelModes: [.objectPublish], internalQueue: internalQueue)
        let error = try #require(throws: ErrorInfo.self) {
            try ChannelConfigGuards.throwIfMissingObjectSubscribeMode(coreSDK: withoutMode, internalQueue: internalQueue)
        }
        #expect(error.code == 40024)
    }

    // MARK: - echoMessages write guard (RTO26c)

    // @spec RTO26 - a write with the `echoMessages` option disabled throws 40000
    @Test
    func writeWithEchoMessagesDisabledThrows() async throws {
        let fixture = Self.makeFixture()
        fixture.coreSDK.setEchoMessages(false)
        let root = Self.rootPathObject(fixture)

        let error = try await #require(throws: ErrorInfo.self) {
            try await root.set(key: "k", value: .primitive(.string("v")))
        }
        #expect(error.code == 40000)
        #expect(error.statusCode == 400)
        #expect(error.message == "\"echoMessages\" client option must be enabled for this operation")
    }

    // The write guard checks echoMessages before channel state: with
    // echo disabled AND the channel SUSPENDED, the echoMessages error (40000) is the one surfaced.
    // @spec RTO26
    @Test
    func writeGuardChecksEchoMessagesBeforeChannelState() async throws {
        let fixture = Self.makeFixture(channelState: .suspended)
        fixture.coreSDK.setEchoMessages(false)
        let root = Self.rootPathObject(fixture)

        let error = try await #require(throws: ErrorInfo.self) {
            try await root.set(key: "k", value: .primitive(.string("v")))
        }
        #expect(error.code == 40000)
    }

    // MARK: - throwIfUnpublishableState connection guard (RTO15b / RTL6c)

    // @spec RTO26 - an inactive connection surfaces the connection's state error; the channel-state
    // portion is checked only when the connection is active.
    @Test
    func unpublishableStateGuardSurfacesConnectionError() throws {
        let internalQueue = TestFactories.createInternalQueue()

        // Active connection, usable channel: passes.
        let active = MockCoreSDK(channelState: .attached, internalQueue: internalQueue)
        #expect(throws: Never.self) {
            try ChannelConfigGuards.throwIfUnpublishableState(coreSDK: active, internalQueue: internalQueue)
        }

        // Inactive connection: the connection's own error is surfaced (before the channel-state check).
        let connectionError = ErrorInfo.create(withCode: 80002, status: 400, message: "Connection is suspended")
        let inactive = MockCoreSDK(channelState: .attached, connectionStateError: connectionError, internalQueue: internalQueue)
        let error = try #require(throws: ErrorInfo.self) {
            try ChannelConfigGuards.throwIfUnpublishableState(coreSDK: inactive, internalQueue: internalQueue)
        }
        #expect(error.code == 80002)

        // Active connection but FAILED channel: the channel-state check fires.
        let failedChannel = MockCoreSDK(channelState: .failed, internalQueue: internalQueue)
        #expect(throws: ErrorInfo.self) {
            try ChannelConfigGuards.throwIfUnpublishableState(coreSDK: failedChannel, internalQueue: internalQueue)
        }
    }

    // MARK: - Depth validation helper (RTPO19c1a)

    // @spec RTPO19c1a - depth <= 0 is rejected with 40003; the check lives in ChannelConfigGuards for part 2
    @Test
    func subscriptionDepthValidation() throws {
        // Valid: nil (unbounded) and any positive integer.
        #expect(throws: Never.self) {
            try ChannelConfigGuards.validateSubscriptionDepth(nil)
        }
        #expect(throws: Never.self) {
            try ChannelConfigGuards.validateSubscriptionDepth(3)
        }
        for invalid in [0, -1] {
            #expect { try ChannelConfigGuards.validateSubscriptionDepth(invalid) } throws: { error in
                (error as? ErrorInfo)?.code == 40003
            }
        }
    }

    // MARK: - Error model numeric codes

    // @spec RTPO3c2 - the path-API error codes are surfaced as their raw integers
    @Test
    func errorModelNumericCodes() {
        #expect(LiveObjectsError.pathNotResolved(path: "x").numericCode == 92005)
        #expect(LiveObjectsError.pathTypeMismatch(operationDescription: "x").numericCode == 92007)
        #expect(LiveObjectsError.channelModeRequired(mode: "object_subscribe").numericCode == 40024)
        #expect(LiveObjectsError.pluginUnavailable.numericCode == 40019)
        #expect(LiveObjectsError.invalidInput(message: "x").numericCode == 40003)
        // All are 400-class client errors.
        #expect(LiveObjectsError.pathNotResolved(path: "x").statusCode == 400)
    }
}

// MARK: - Local test double

/// A realtime-objects double that exposes a pre-seeded ``ObjectsPool`` for path resolution and
/// captures the messages published by the write path. Mirrors `MockRealtimeObjects` but with an
/// injectable full pool (so the root can carry seeded entries).
private final class SeededRealtimeObjects: InternalRealtimeObjectsProtocol {
    private let poolMutex: DispatchQueueMutex<ObjectsPool>
    private let mutex = NSLock()
    private nonisolated(unsafe) var _captured: [ProtocolTypes.OutboundObjectMessage]?
    private let _pathObjectSubscriptionRegister: PathObjectSubscriptionRegister

    init(pool: ObjectsPool, internalQueue: DispatchQueue) {
        poolMutex = DispatchQueueMutex(dispatchQueue: internalQueue, initialValue: pool)
        _pathObjectSubscriptionRegister = PathObjectSubscriptionRegister(internalQueue: internalQueue, userCallbackQueue: .main)
    }

    var nosync_objectsPool: ObjectsPool {
        poolMutex.withoutSync { $0 }
    }

    var pathObjectSubscriptionRegister: PathObjectSubscriptionRegister {
        _pathObjectSubscriptionRegister
    }

    var capturedMessages: [ProtocolTypes.OutboundObjectMessage]? {
        mutex.withLock { _captured }
    }

    func nosync_publishAndApply(
        objectMessages: [ProtocolTypes.OutboundObjectMessage],
        coreSDK: CoreSDK,
        callback: @escaping @Sendable (Result<Void, ErrorInfo>) -> Void,
    ) {
        mutex.withLock { _captured = objectMessages }
        callback(.success(()))
    }
}
