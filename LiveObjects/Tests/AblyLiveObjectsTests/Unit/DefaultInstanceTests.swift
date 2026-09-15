import _AblyPluginSupportPrivate
@testable import AblyLiveObjects
@testable import AblyLiveObjectsTesting
import AblyPubSubDevice
import Foundation
import Testing

/// Tests for the Phase 3 instance layer: ``DefaultLiveMapInstance``, ``DefaultLiveCounterInstance``,
/// ``DefaultPrimitiveInstance`` and the ``Instance`` construction seam. Everything is driven through
/// the existing mocks (`MockCoreSDK`, `MockRealtimeObjects`, `MockLiveMapObjectsPoolDelegate`).
///
/// Integration-tier / mock-WebSocket cases from `uts/objects/unit/instance.md` (those declaring
/// `setup_synced_channel` etc.) are out of scope for this native suite and are not ported here.
struct DefaultInstanceTests {
    // MARK: - Construction helpers

    private static func makeCounter(objectID: String = "counter:1@0", data: Double = 0, internalQueue: DispatchQueue) -> InternalDefaultLiveCounter {
        InternalDefaultLiveCounter(testsOnly_data: data, objectID: objectID, logger: TestLogger(), internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
    }

    private static func makeMap(objectID: String = "map:1@0", data: [String: InternalObjectsMapEntry] = [:], internalQueue: DispatchQueue) -> InternalDefaultLiveMap {
        InternalDefaultLiveMap(testsOnly_data: data, objectID: objectID, logger: TestLogger(), internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
    }

    // MARK: - Instance factory / construction (RTINS1, RTINS2a, RTINS3a)

    // @spec RTINS3a - the factory binds a map node and surfaces its objectId
    @Test
    func factoryProducesLiveMapInstance() throws {
        let internalQueue = TestFactories.createInternalQueue()
        let coreSDK = MockCoreSDK(channelState: .attached, internalQueue: internalQueue)
        let node = Self.makeMap(objectID: "map:abc@0", internalQueue: internalQueue)

        let instance = Instance.from(internalValue: .liveMap(node), coreSDK: coreSDK, realtimeObjects: MockRealtimeObjects(), internalQueue: internalQueue)

        guard case let .liveMap(mapInstance) = instance else {
            Issue.record("Expected .liveMap")
            return
        }
        #expect(instance.type == .liveMap)
        #expect(mapInstance.id == "map:abc@0")
    }

    // @spec RTINS3a - the factory binds a counter node and surfaces its objectId
    @Test
    func factoryProducesLiveCounterInstance() throws {
        let internalQueue = TestFactories.createInternalQueue()
        let coreSDK = MockCoreSDK(channelState: .attached, internalQueue: internalQueue)
        let node = Self.makeCounter(objectID: "counter:abc@0", internalQueue: internalQueue)

        let instance = Instance.from(internalValue: .liveCounter(node), coreSDK: coreSDK, realtimeObjects: MockRealtimeObjects(), internalQueue: internalQueue)

        guard case let .liveCounter(counterInstance) = instance else {
            Issue.record("Expected .liveCounter")
            return
        }
        #expect(instance.type == .liveCounter)
        #expect(counterInstance.id == "counter:abc@0")
    }

    // @spec RTTS8 - each primitive value type maps to the correct ValueType
    @Test(arguments: [
        (InternalLiveMapValue.string("s"), ValueType.string),
        (InternalLiveMapValue.number(1), ValueType.number),
        (InternalLiveMapValue.bool(true), ValueType.boolean),
        (InternalLiveMapValue.data(Data([1, 2])), ValueType.binary),
        (InternalLiveMapValue.jsonArray(["a"]), ValueType.jsonArray),
        (InternalLiveMapValue.jsonObject(["k": "v"]), ValueType.jsonObject),
    ])
    func factoryProducesPrimitiveInstanceWithCorrectType(value: InternalLiveMapValue, expectedType: ValueType) throws {
        let internalQueue = TestFactories.createInternalQueue()
        let coreSDK = MockCoreSDK(channelState: .attached, internalQueue: internalQueue)

        let instance = Instance.from(internalValue: value, coreSDK: coreSDK, realtimeObjects: MockRealtimeObjects(), internalQueue: internalQueue)

        guard case let .primitive(primitiveInstance) = instance else {
            Issue.record("Expected .primitive")
            return
        }
        #expect(instance.type == expectedType)
        #expect(primitiveInstance.type == expectedType)
    }

    // MARK: - LiveMapInstance reads (RTINS5, RTINS6, RTINS7, RTINS8, RTINS9)

    // @spec RTINS5c - get returns an Instance wrapping the value, or nil when absent
    @Test
    func mapGetReturnsWrappedInstanceOrNil() throws {
        let internalQueue = TestFactories.createInternalQueue()
        let coreSDK = MockCoreSDK(channelState: .attached, internalQueue: internalQueue)
        let realtimeObjects = MockRealtimeObjects(objectsPoolDelegate: MockLiveMapObjectsPoolDelegate(internalQueue: internalQueue))
        let node = Self.makeMap(data: ["k": TestFactories.internalMapEntry(data: ProtocolTypes.ObjectData(string: "hello"))], internalQueue: internalQueue)

        guard case let .liveMap(mapInstance) = Instance.from(internalValue: .liveMap(node), coreSDK: coreSDK, realtimeObjects: realtimeObjects, internalQueue: internalQueue) else {
            Issue.record("Expected .liveMap")
            return
        }

        let got = try #require(try mapInstance.get(key: "k"))
        guard case let .primitive(primitive) = got else {
            Issue.record("Expected primitive")
            return
        }
        #expect(try primitive.value == .string("hello"))
        #expect(try mapInstance.get(key: "missing") == nil)
    }

    // @spec RTINS6 - entries; @spec RTINS7 - keys; @spec RTINS8 - values; @spec RTINS9 - size
    @Test
    func mapEntriesKeysValuesSize() throws {
        let internalQueue = TestFactories.createInternalQueue()
        let coreSDK = MockCoreSDK(channelState: .attached, internalQueue: internalQueue)
        let realtimeObjects = MockRealtimeObjects(objectsPoolDelegate: MockLiveMapObjectsPoolDelegate(internalQueue: internalQueue))
        let node = Self.makeMap(
            data: [
                "a": TestFactories.internalMapEntry(data: ProtocolTypes.ObjectData(string: "x")),
                "b": TestFactories.internalMapEntry(data: ProtocolTypes.ObjectData(number: NSNumber(value: 5))),
            ],
            internalQueue: internalQueue,
        )

        guard case let .liveMap(mapInstance) = Instance.from(internalValue: .liveMap(node), coreSDK: coreSDK, realtimeObjects: realtimeObjects, internalQueue: internalQueue) else {
            Issue.record("Expected .liveMap")
            return
        }

        #expect(try mapInstance.size == 2)
        #expect(try Set(mapInstance.keys()) == ["a", "b"])
        #expect(try mapInstance.entries().count == 2)
        #expect(try mapInstance.values().count == 2)
        let entriesByKey = try Dictionary(uniqueKeysWithValues: mapInstance.entries().map { ($0.key, $0.value) })
        #expect(entriesByKey["a"]?.type == .string)
        #expect(entriesByKey["b"]?.type == .number)
    }

    // MARK: - LiveCounterInstance / PrimitiveInstance reads (RTINS4)

    // @spec RTINS4b - counter value delegates to the node
    @Test
    func counterValue() throws {
        let internalQueue = TestFactories.createInternalQueue()
        let coreSDK = MockCoreSDK(channelState: .attached, internalQueue: internalQueue)
        let node = Self.makeCounter(data: 42, internalQueue: internalQueue)

        guard case let .liveCounter(counterInstance) = Instance.from(internalValue: .liveCounter(node), coreSDK: coreSDK, realtimeObjects: MockRealtimeObjects(), internalQueue: internalQueue) else {
            Issue.record("Expected .liveCounter")
            return
        }
        #expect(try counterInstance.value == 42)
    }

    // @spec RTINS4c - a primitive returns its value directly
    @Test
    func primitiveValueAndType() throws {
        let internalQueue = TestFactories.createInternalQueue()
        let coreSDK = MockCoreSDK(channelState: .attached, internalQueue: internalQueue)

        guard case let .primitive(primitive) = Instance.from(internalValue: .string("direct"), coreSDK: coreSDK, realtimeObjects: MockRealtimeObjects(), internalQueue: internalQueue) else {
            Issue.record("Expected .primitive")
            return
        }
        #expect(try primitive.value == .string("direct"))
        #expect(primitive.type == .string)
    }

    @Test
    func primitiveConvenienceAccessors() throws {
        let internalQueue = TestFactories.createInternalQueue()
        let coreSDK = MockCoreSDK(channelState: .attached, internalQueue: internalQueue)

        func primitiveInstance(_ value: InternalLiveMapValue) throws -> any PrimitiveInstance {
            let instance = Instance.from(internalValue: value, coreSDK: coreSDK, realtimeObjects: MockRealtimeObjects(), internalQueue: internalQueue)
            let primitive: (any PrimitiveInstance)? = switch instance {
            case let .primitive(primitive):
                primitive
            case .liveMap, .liveCounter:
                nil
            }
            return try #require(primitive)
        }

        #expect(try primitiveInstance(.string("hi")).stringValue == "hi")
        #expect(try primitiveInstance(.number(5)).numberValue == 5)
        #expect(try primitiveInstance(.bool(true)).boolValue == true)
        #expect(try primitiveInstance(.data(Data([1, 2, 3]))).dataValue == Data([1, 2, 3]))
        #expect(try primitiveInstance(.jsonArray(["a"])).jsonArrayValue == ["a"])
        #expect(try primitiveInstance(.jsonObject(["k": "v"])).jsonObjectValue == ["k": "v"])

        // An accessor for a case other than the wrapped one yields nil.
        #expect(try primitiveInstance(.string("hi")).numberValue == nil)
    }

    // @spec RTO25b - a read on a DETACHED channel throws
    @Test
    func readOnDetachedChannelThrows() throws {
        let internalQueue = TestFactories.createInternalQueue()
        let coreSDK = MockCoreSDK(channelState: .detached, internalQueue: internalQueue)
        let node = Self.makeCounter(data: 1, internalQueue: internalQueue)

        guard case let .liveCounter(counterInstance) = Instance.from(internalValue: .liveCounter(node), coreSDK: coreSDK, realtimeObjects: MockRealtimeObjects(), internalQueue: internalQueue) else {
            Issue.record("Expected .liveCounter")
            return
        }
        #expect(throws: ARTErrorInfo.self) {
            _ = try counterInstance.value
        }

        guard case let .primitive(primitive) = Instance.from(internalValue: .string("x"), coreSDK: coreSDK, realtimeObjects: MockRealtimeObjects(), internalQueue: internalQueue) else {
            Issue.record("Expected .primitive")
            return
        }
        #expect(throws: ARTErrorInfo.self) {
            _ = try primitive.value
        }

        // The convenience accessors delegate to `value`, so they must propagate the same error.
        #expect(throws: ARTErrorInfo.self) {
            _ = try primitive.stringValue
        }
    }

    // MARK: - compactJson (RTINS11 -> RTPO13c / RTPO14b)

    // @spec RTPO14b1 - a primitive compacts to itself; binary is base64-encoded
    @Test
    func primitiveCompactJson() throws {
        let internalQueue = TestFactories.createInternalQueue()
        let coreSDK = MockCoreSDK(channelState: .attached, internalQueue: internalQueue)

        guard case let .primitive(stringPrimitive) = Instance.from(internalValue: .string("hi"), coreSDK: coreSDK, realtimeObjects: MockRealtimeObjects(), internalQueue: internalQueue) else {
            Issue.record("Expected .primitive")
            return
        }
        #expect(try stringPrimitive.compactJson() == .string("hi"))

        let bytes = Data([0x01, 0x02, 0x03])
        guard case let .primitive(binaryPrimitive) = Instance.from(internalValue: .data(bytes), coreSDK: coreSDK, realtimeObjects: MockRealtimeObjects(), internalQueue: internalQueue) else {
            Issue.record("Expected .primitive")
            return
        }
        #expect(try binaryPrimitive.compactJson() == .string(bytes.base64EncodedString()))
    }

    // @spec RTPO13d - a counter compacts to its numeric value
    @Test
    func counterCompactJson() throws {
        let internalQueue = TestFactories.createInternalQueue()
        let coreSDK = MockCoreSDK(channelState: .attached, internalQueue: internalQueue)
        let node = Self.makeCounter(data: 9, internalQueue: internalQueue)

        guard case let .liveCounter(counterInstance) = Instance.from(internalValue: .liveCounter(node), coreSDK: coreSDK, realtimeObjects: MockRealtimeObjects(), internalQueue: internalQueue) else {
            Issue.record("Expected .liveCounter")
            return
        }
        #expect(try counterInstance.compactJson() == .number(9))
    }

    // @spec RTPO13c2 - nested maps recurse; @spec RTPO13c3 - nested counters resolve to their value
    @Test
    func mapCompactJsonNested() throws {
        let internalQueue = TestFactories.createInternalQueue()
        let coreSDK = MockCoreSDK(channelState: .attached, internalQueue: internalQueue)
        let poolDelegate = MockLiveMapObjectsPoolDelegate(internalQueue: internalQueue)

        let nestedCounter = Self.makeCounter(objectID: "counter:c1@0", data: 7, internalQueue: internalQueue)
        let nestedMap = Self.makeMap(objectID: "map:m1@0", data: ["x": TestFactories.internalMapEntry(data: ProtocolTypes.ObjectData(string: "y"))], internalQueue: internalQueue)
        poolDelegate.objects["counter:c1@0"] = .counter(nestedCounter)
        poolDelegate.objects["map:m1@0"] = .map(nestedMap)

        let root = Self.makeMap(
            objectID: "map:root@0",
            data: [
                "str": TestFactories.internalMapEntry(data: ProtocolTypes.ObjectData(string: "hello")),
                "cnt": TestFactories.internalMapEntry(data: ProtocolTypes.ObjectData(objectId: "counter:c1@0")),
                "m": TestFactories.internalMapEntry(data: ProtocolTypes.ObjectData(objectId: "map:m1@0")),
            ],
            internalQueue: internalQueue,
        )
        let realtimeObjects = MockRealtimeObjects(objectsPoolDelegate: poolDelegate)

        guard case let .liveMap(mapInstance) = Instance.from(internalValue: .liveMap(root), coreSDK: coreSDK, realtimeObjects: realtimeObjects, internalQueue: internalQueue) else {
            Issue.record("Expected .liveMap")
            return
        }
        let expected: JSONValue = .object([
            "str": .string("hello"),
            "cnt": .number(7),
            "m": .object(["x": .string("y")]),
        ])
        #expect(try mapInstance.compactJson() == expected)
    }

    // @spec RTPO14b2 - a cyclic reference is emitted as {"objectId": <id>}
    @Test
    func mapCompactJsonCycle() throws {
        let internalQueue = TestFactories.createInternalQueue()
        let coreSDK = MockCoreSDK(channelState: .attached, internalQueue: internalQueue)
        let poolDelegate = MockLiveMapObjectsPoolDelegate(internalQueue: internalQueue)

        // An indirect cycle A -> B -> A. (A direct self-reference is not used: the internal engine's
        // `entries()` -> `nosync_isEntryTombstoned` re-enters the same map's mutex for a self-referencing
        // entry, an exclusive-access conflict — a pre-existing engine limitation, unrelated to the
        // compactJson cycle handling exercised here.)
        let mapA = Self.makeMap(objectID: "map:a@0", data: ["toB": TestFactories.internalMapEntry(data: ProtocolTypes.ObjectData(objectId: "map:b@0"))], internalQueue: internalQueue)
        let mapB = Self.makeMap(objectID: "map:b@0", data: ["toA": TestFactories.internalMapEntry(data: ProtocolTypes.ObjectData(objectId: "map:a@0"))], internalQueue: internalQueue)
        poolDelegate.objects["map:a@0"] = .map(mapA)
        poolDelegate.objects["map:b@0"] = .map(mapB)
        let realtimeObjects = MockRealtimeObjects(objectsPoolDelegate: poolDelegate)

        guard case let .liveMap(mapInstance) = Instance.from(internalValue: .liveMap(mapA), coreSDK: coreSDK, realtimeObjects: realtimeObjects, internalQueue: internalQueue) else {
            Issue.record("Expected .liveMap")
            return
        }
        // RTPO14b2: when the walk revisits A (already-visited), the reference is a single-property
        // object carrying the objectId, rather than infinitely recursing.
        let expected: JSONValue = .object(["toB": .object(["toA": .object(["objectId": .string("map:a@0")])])])
        #expect(try mapInstance.compactJson() == expected)
    }

    // MARK: - Mutations via the RTO20 publish path (RTINS12, RTINS14)

    // @spec RTINS14c - increment publishes a COUNTER_INC operation
    @Test
    func counterIncrementPublishesCounterInc() async throws {
        let internalQueue = TestFactories.createInternalQueue()
        let coreSDK = MockCoreSDK(channelState: .attached, internalQueue: internalQueue)
        let realtimeObjects = MockRealtimeObjects()
        let published = Published()
        realtimeObjects.setPublishAndApplyHandler { messages in
            published.set(messages)
            return .success(())
        }
        let node = Self.makeCounter(objectID: "counter:x@0", internalQueue: internalQueue)

        guard case let .liveCounter(counterInstance) = Instance.from(internalValue: .liveCounter(node), coreSDK: coreSDK, realtimeObjects: realtimeObjects, internalQueue: internalQueue) else {
            Issue.record("Expected .liveCounter")
            return
        }
        try await counterInstance.increment(amount: 5)

        let messages = try #require(published.get())
        #expect(messages.count == 1)
        #expect(messages[0].operation?.action == .known(.counterInc))
        #expect(messages[0].operation?.objectId == "counter:x@0")
        #expect(messages[0].operation?.counterInc?.number == NSNumber(value: 5))
    }

    // @spec RTINS12c - set publishes a MAP_SET operation
    @Test
    func mapSetPublishesMapSet() async throws {
        let internalQueue = TestFactories.createInternalQueue()
        let coreSDK = MockCoreSDK(channelState: .attached, internalQueue: internalQueue)
        let realtimeObjects = MockRealtimeObjects()
        let published = Published()
        realtimeObjects.setPublishAndApplyHandler { messages in
            published.set(messages)
            return .success(())
        }
        let node = Self.makeMap(objectID: "map:x@0", internalQueue: internalQueue)

        guard case let .liveMap(mapInstance) = Instance.from(internalValue: .liveMap(node), coreSDK: coreSDK, realtimeObjects: realtimeObjects, internalQueue: internalQueue) else {
            Issue.record("Expected .liveMap")
            return
        }
        try await mapInstance.set(key: "greeting", value: .primitive(.string("hi")))

        let messages = try #require(published.get())
        #expect(messages.count == 1)
        #expect(messages[0].operation?.action == .known(.mapSet))
        #expect(messages[0].operation?.objectId == "map:x@0")
        #expect(messages[0].operation?.mapSet?.key == "greeting")
        #expect(messages[0].operation?.mapSet?.value?.string == "hi")
    }

    // MARK: - Blueprint set publishes CREATE(s) + MAP_SET atomically (RTLM20e7g / RTLM20h1)

    /// Builds a `MockRealtimeObjects` that records the single `publishAndApply` array into `published`,
    /// and a map instance wrapping a fresh node, for the blueprint-set atomicity assertions below.
    private func makeBlueprintSetFixture(internalQueue: DispatchQueue) throws -> (mapInstance: LiveMapInstance, published: Published) {
        let coreSDK = MockCoreSDK(channelState: .attached, internalQueue: internalQueue)
        let realtimeObjects = MockRealtimeObjects()
        let published = Published()
        realtimeObjects.setPublishAndApplyHandler { messages in
            published.set(messages)
            return .success(())
        }
        let node = Self.makeMap(objectID: "map:x@0", internalQueue: internalQueue)
        guard case let .liveMap(mapInstance) = Instance.from(internalValue: .liveMap(node), coreSDK: coreSDK, realtimeObjects: realtimeObjects, internalQueue: internalQueue) else {
            throw BlueprintSetFixtureError.notALiveMap
        }
        return (mapInstance, published)
    }

    private enum BlueprintSetFixtureError: Error { case notALiveMap }

    // @spec RTLM20h1 - setting a LiveCounter blueprint publishes [COUNTER_CREATE, MAP_SET] as one array,
    // with the MAP_SET value chained to the created counter's objectId (RTLM20e7g2).
    @Test
    func mapSetCounterBlueprintPublishesCreateThenSet() async throws {
        let internalQueue = TestFactories.createInternalQueue()
        let (mapInstance, published) = try makeBlueprintSetFixture(internalQueue: internalQueue)

        try await mapInstance.set(key: "hits", value: .liveCounter(.create(initialCount: 7)))

        let messages = try #require(published.get())
        #expect(messages.count == 2)
        #expect(messages[0].operation?.action == .known(.counterCreate))
        #expect(messages[0].operation?.objectId.hasPrefix("counter:") == true)
        #expect(messages[1].operation?.action == .known(.mapSet))
        #expect(messages[1].operation?.objectId == "map:x@0")
        #expect(messages[1].operation?.mapSet?.key == "hits")
        #expect(messages[1].operation?.mapSet?.value?.objectId == messages[0].operation?.objectId)
    }

    // @spec RTLM20h1 - setting a LiveMap blueprint containing a nested LiveCounter publishes
    // [COUNTER_CREATE, MAP_CREATE, MAP_SET] in depth-first order (RTLMV4d1/RTLMV4k).
    @Test
    func mapSetMapBlueprintWithCounterPublishesDepthFirst() async throws {
        let internalQueue = TestFactories.createInternalQueue()
        let (mapInstance, published) = try makeBlueprintSetFixture(internalQueue: internalQueue)

        try await mapInstance.set(key: "stats", value: .liveMap(.create(entries: [
            "count": .liveCounter(.create(initialCount: 0)),
            "label": "test",
        ])))

        let messages = try #require(published.get())
        #expect(messages.count == 3)
        #expect(messages[0].operation?.action == .known(.counterCreate))
        #expect(messages[1].operation?.action == .known(.mapCreate))
        #expect(messages[2].operation?.action == .known(.mapSet))
        #expect(messages[2].operation?.mapSet?.key == "stats")
        // The MAP_SET references the "stats" map (the final CREATE), not the nested counter.
        #expect(messages[2].operation?.mapSet?.value?.objectId == messages[1].operation?.objectId)
    }

    // @spec RTLMV4k - a deeply nested blueprint (map -> map -> counter) creates innermost first:
    // [COUNTER_CREATE, MAP_CREATE(inner), MAP_CREATE(outer), MAP_SET], each entry chained to its child.
    @Test
    func mapSetDeeplyNestedBlueprintOrdersCreatesInnermostFirst() async throws {
        let internalQueue = TestFactories.createInternalQueue()
        let (mapInstance, published) = try makeBlueprintSetFixture(internalQueue: internalQueue)

        try await mapInstance.set(key: "deep", value: .liveMap(.create(entries: [
            "inner": .liveMap(.create(entries: [
                "leaf": .liveCounter(.create(initialCount: 3)),
            ])),
        ])))

        let messages = try #require(published.get())
        #expect(messages.count == 4)
        #expect(messages[0].operation?.action == .known(.counterCreate)) // innermost
        #expect(messages[1].operation?.action == .known(.mapCreate)) // inner map
        #expect(messages[2].operation?.action == .known(.mapCreate)) // outer "deep" map
        #expect(messages[3].operation?.action == .known(.mapSet)) // root MAP_SET last

        let counterId = try #require(messages[0].operation?.objectId)
        let innerMapId = try #require(messages[1].operation?.objectId)
        let outerMapId = try #require(messages[2].operation?.objectId)
        // inner map's "leaf" -> counter; outer map's "inner" -> inner map; MAP_SET -> outer map.
        #expect(messages[1].operation?.mapCreateWithObjectId?.derivedFrom?.entries?["leaf"]?.data?.objectId == counterId)
        #expect(messages[2].operation?.mapCreateWithObjectId?.derivedFrom?.entries?["inner"]?.data?.objectId == innerMapId)
        #expect(messages[3].operation?.mapSet?.value?.objectId == outerMapId)
    }

    // MARK: - Subscriptions (RTINS16)

    // @spec RTINS16e1 - the event carries an Instance wrapping the object
    // @spec RTINS16e2 - the event carries the PAOM3 message from the update
    @available(iOS 17.0.0, tvOS 17.0.0, *)
    @Test
    func counterSubscribeReceivesEnrichedEvent() async throws {
        let internalQueue = TestFactories.createInternalQueue()
        let coreSDK = MockCoreSDK(channelState: .attached, internalQueue: internalQueue)
        let node = Self.makeCounter(objectID: "counter:sub@0", internalQueue: internalQueue)

        guard case let .liveCounter(counterInstance) = Instance.from(internalValue: .liveCounter(node), coreSDK: coreSDK, realtimeObjects: MockRealtimeObjects(), internalQueue: internalQueue) else {
            Issue.record("Expected .liveCounter")
            return
        }

        let subscriber = Subscriber<InstanceSubscriptionEvent>(callbackQueue: .main)
        let subscription = try counterInstance.subscribe(listener: subscriber.createListener())

        let operation = TestFactories.objectOperation(action: .known(.counterInc), objectId: "counter:sub@0", counterInc: TestFactories.counterInc(number: 3))
        let sourceMessage = TestFactories.inboundObjectMessage(operation: operation, serial: "ts1", siteCode: "site1")
        var pool = ObjectsPool(logger: TestLogger(), internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
        internalQueue.ably_syncNoDeadlock {
            _ = node.nosync_apply(
                operation,
                source: .channel,
                objectMessage: sourceMessage,
                objectsPool: &pool,
            )
        }

        let invocations = await subscriber.getInvocations()
        #expect(invocations.count == 1)
        let event = try #require(invocations.first)
        // RTINS16e2: the subscriber receives the PAOM3 projection of the source message.
        #expect(event.message == sourceMessage.toPublicObjectMessage(channelName: coreSDK.channelName))
        // RTINS16e1: the wrapped object is the same counter (identity), exposing the same id.
        guard case let .liveCounter(eventCounter) = event.object else {
            Issue.record("Expected .liveCounter in event")
            return
        }
        #expect(eventCounter.id == "counter:sub@0")
        subscription.unsubscribe()
    }

    // @spec RTINS16d - a map subscription receives update events
    @available(iOS 17.0.0, tvOS 17.0.0, *)
    @Test
    func mapSubscribeReceivesEvent() async throws {
        let internalQueue = TestFactories.createInternalQueue()
        let coreSDK = MockCoreSDK(channelState: .attached, internalQueue: internalQueue)
        let realtimeObjects = MockRealtimeObjects(objectsPoolDelegate: MockLiveMapObjectsPoolDelegate(internalQueue: internalQueue))
        let node = Self.makeMap(objectID: "map:sub@0", internalQueue: internalQueue)

        guard case let .liveMap(mapInstance) = Instance.from(internalValue: .liveMap(node), coreSDK: coreSDK, realtimeObjects: realtimeObjects, internalQueue: internalQueue) else {
            Issue.record("Expected .liveMap")
            return
        }

        let subscriber = Subscriber<InstanceSubscriptionEvent>(callbackQueue: .main)
        try mapInstance.subscribe(listener: subscriber.createListener())

        var pool = ObjectsPool(logger: TestLogger(), internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
        internalQueue.ably_syncNoDeadlock {
            _ = node.nosync_apply(
                TestFactories.objectOperation(action: .known(.mapSet), objectId: "map:sub@0", mapSet: ProtocolTypes.MapSet(key: "k", value: ProtocolTypes.ObjectData(string: "v"))),
                source: .channel,
                objectMessage: TestFactories.inboundObjectMessage(serial: "ts1", siteCode: "site1"),
                objectsPool: &pool,
            )
        }

        let invocations = await subscriber.getInvocations()
        #expect(invocations.count == 1)
        guard case .liveMap = try #require(invocations.first).object else {
            Issue.record("Expected .liveMap in event")
            return
        }
    }

    /// A tiny thread-safe holder for the messages captured by a `publishAndApply` handler.
    private final class Published: @unchecked Sendable {
        private let mutex = NSLock()
        private var messages: [ProtocolTypes.OutboundObjectMessage]?
        func set(_ value: [ProtocolTypes.OutboundObjectMessage]) {
            mutex.withLock { messages = value }
        }

        func get() -> [ProtocolTypes.OutboundObjectMessage]? {
            mutex.withLock { messages }
        }
    }
}
