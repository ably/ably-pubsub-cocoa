import _AblyPluginSupportPrivate
@testable import AblyLiveObjects
@testable import AblyLiveObjectsTesting
import AblyPubSubDevice
import Foundation
import Testing

/// Tests for the OM3 message-size calculation and the RTO15d publish-size gate.
///
/// These vectors mirror ably-java's ObjectMessage size tests so the RTO15d size gate's accept/reject
/// decisions stay aligned across SDKs (the byte-length semantics the OM3 "length" wording leaves
/// underspecified). The size algorithm is implemented on the `ProtocolTypes` (non-wire)
/// `OutboundObjectMessage` — see the explanatory comment in `ObjectMessage.swift` — so the tests
/// exercise it there.
struct WireObjectMessageSizeTests {
    // MARK: - OM3 composite size

    // A message exercising every size-contributing field, whose expected size is
    // clientId(11) + operation(54) + object(46) + extras(26) = 137 bytes.
    // @spec OM3
    // @spec OOP4
    // @spec OST3
    @Test
    func compositeMessageSize() {
        let objectMessage = ProtocolTypes.OutboundObjectMessage(
            id: "msg_12345", // Not counted in size calculation
            clientId: "test-client", // OM3f: 11 bytes (UTF-8)
            connectionId: "conn_98765", // Not counted
            // OM3d: JSON serialization length -> 26 bytes ({"count":42,"meta":"data"})
            extras: [
                "meta": "data",
                "count": 42,
            ],
            timestamp: Date(timeIntervalSince1970: 1_699_123_456.789), // Not counted
            operation: .init(
                action: .known(.mapCreate),
                objectId: "obj_54321", // Not counted in operation size
                // mapSet contributes 6 (key) + 6 (string value) = 12
                mapSet: .init(
                    key: "mapKey", // 6 bytes
                    value: .init(
                        objectId: "ref_obj", // Not counted (string takes precedence in OD3)
                        string: "sample", // 6 bytes
                    ),
                ),
                // counterInc contributes 8
                counterInc: WireCounterInc(number: NSNumber(value: 10.0)),
                // mapCreateWithObjectId.derivedFrom contributes 26 (via OOP4h2)
                mapCreateWithObjectId: .init(
                    initialValue: "{}", // Not counted in derivedFrom size
                    nonce: "dummy-nonce", // Not counted in derivedFrom size
                    derivedFrom: .init(
                        semantics: .known(.lww), // Not counted
                        entries: [
                            // 6 (key) + 6 (string) = 12
                            "entry1": .init(
                                tombstone: false, // Not counted
                                timeserial: "ts_123", // Not counted
                                data: .init(string: "value1"),
                            ),
                            // 6 (key) + 8 (number) = 14
                            "entry2": .init(data: .init(number: NSNumber(value: 42.0))),
                        ],
                    ),
                ),
                // counterCreateWithObjectId.derivedFrom contributes 8 (via OOP4k2)
                counterCreateWithObjectId: .init(
                    initialValue: "{}", // Not counted
                    nonce: "dummy-nonce", // Not counted
                    derivedFrom: WireCounterCreate(count: NSNumber(value: 100.0)),
                ),
            ),
            object: .init(
                objectId: "state_obj", // Not counted in state size
                siteTimeserials: ["site1": "serial1"], // Not counted
                tombstone: false, // Not counted
                // createOp contributes 9 (key) + 11 (string) = 20
                createOp: .init(
                    action: .known(.mapSet),
                    objectId: "create_obj",
                    mapSet: .init(
                        key: "createKey", // 9 bytes
                        value: .init(string: "createValue"), // 11 bytes
                    ),
                ),
                // map contributes 8 (key length) + 10 (string) = 18
                map: .init(
                    semantics: .known(.lww),
                    entries: [
                        "stateKey": .init(data: .init(string: "stateValue")),
                    ],
                ),
                // counter contributes 8
                counter: WireObjectsCounter(count: NSNumber(value: 50.0)),
            ),
            serial: "serial_123", // Not counted
            siteCode: "site_abc", // Not counted
        )

        #expect(objectMessage.size == 137)
    }

    // Confirms OD3e measures strings in UTF-8 bytes: 你 -> 3 bytes, 😊 -> 4 bytes.
    // @spec OD3e
    @Test
    func unicodeStringSize() {
        let objectMessage = ProtocolTypes.OutboundObjectMessage(
            operation: .init(
                action: .known(.mapSet),
                objectId: "",
                mapSet: .init(
                    key: "",
                    value: .init(string: "你😊"),
                ),
            ),
        )

        #expect(objectMessage.size == 7)
    }

    // MARK: - OD3 leaf branches

    // @spec OD3e
    @Test
    func objectDataStringSize() {
        #expect(ProtocolTypes.ObjectData(string: "hello").size == 5)
        // UTF-8 byte length, not character count
        #expect(ProtocolTypes.ObjectData(string: "你").size == 3)
    }

    // @spec OD3d
    @Test
    func objectDataNumberSize() {
        #expect(ProtocolTypes.ObjectData(number: NSNumber(value: 3.14)).size == 8)
    }

    // @spec OD3b
    @Test
    func objectDataBooleanSize() {
        #expect(ProtocolTypes.ObjectData(boolean: true).size == 1)
        #expect(ProtocolTypes.ObjectData(boolean: false).size == 1)
    }

    // @spec OD3c
    @Test
    func objectDataBytesSize() {
        // Size is the actual binary length, regardless of base64 representation.
        let bytes = Data([0x01, 0x02, 0x03, 0x04, 0x05])
        #expect(ProtocolTypes.ObjectData(bytes: bytes).size == 5)
    }

    // @spec OD3g
    @Test
    func objectDataJSONSize() {
        // {"k":"v"} is 9 bytes.
        #expect(ProtocolTypes.ObjectData(json: .object(["k": "v"])).size == 9)
    }

    // @spec OD3f
    @Test
    func objectDataEmptyIsZero() {
        #expect(ProtocolTypes.ObjectData().size == 0)
        // objectId does not contribute to the size (it is not one of the OD3 leaves).
        #expect(ProtocolTypes.ObjectData(objectId: "obj:1@2").size == 0)
    }

    // MARK: - OCN3 counter

    // @spec OCN3a
    // @spec OCN3b
    @Test
    func objectsCounterSize() {
        #expect(WireObjectsCounter(count: NSNumber(value: 42.0)).size == 8)
        #expect(WireObjectsCounter(count: nil).size == 0)
    }

    // MARK: - OM3d extras

    // @spec OM3d
    @Test
    func extrasSizeIsJSONStringLength() {
        let objectMessage = ProtocolTypes.OutboundObjectMessage(
            extras: [
                "meta": "data",
                "count": 42,
            ],
        )
        // {"count":42,"meta":"data"} is 26 bytes/UTF-16 code units.
        #expect(objectMessage.size == 26)
    }

    // MARK: - String measurement convention (UTF-8 for strings/keys; UTF-16 string length for extras)

    // OM3f measures clientId as its UTF-8 byte length, not its UTF-16 code-unit count.
    // @spec OM3f
    @Test
    func clientIdIsUTF8ByteLength() {
        // 你 -> 3 UTF-8 bytes, 😊 -> 4 UTF-8 bytes (7 total), versus 3 UTF-16 code units.
        let objectMessage = ProtocolTypes.OutboundObjectMessage(clientId: "你😊")
        #expect(objectMessage.size == 7)
    }

    // MST3c measures the MapSet key as its UTF-8 byte length.
    // @spec MST3c
    @Test
    func mapSetKeyIsUTF8ByteLength() {
        // 你 -> 3 UTF-8 bytes (key); string value "v" -> 1 byte.
        let mapSet = ProtocolTypes.MapSet(key: "你", value: .init(string: "v"))
        #expect(mapSet.size == 4)
    }

    // OMP4a1 measures map-state entry keys as their UTF-8 byte length (changed from UTF-16 for
    // key-consistency with the MapCreate/MapSet/MapRemove operation keys).
    // @spec OMP4a1
    @Test
    func objectsMapEntryKeyIsUTF8ByteLength() {
        // 你😊 -> 7 UTF-8 bytes (key), versus 3 UTF-16 code units; entry data string "v" -> 1 byte.
        let map = ProtocolTypes.ObjectsMap(
            semantics: .known(.lww),
            entries: [
                "你😊": .init(data: .init(string: "v")),
            ],
        )
        #expect(map.size == 8)
    }

    // OM3d measures extras as the UTF-16 string length of its JSON representation (the docs'
    // verbatim "string length of its JSON representation"), not its UTF-8 byte length.
    // @spec OM3d
    @Test
    func extrasIsUTF16StringLengthOfJSON() {
        let objectMessage = ProtocolTypes.OutboundObjectMessage(
            extras: [
                "k": "你",
            ],
        )
        // The JSON representation {"k":"你"} is 9 UTF-16 code units (你 is one), versus 11 UTF-8 bytes.
        #expect(objectMessage.size == 9)
    }

    // MARK: - RTO15d publish-size gate

    private static func createRealtimeObjects(internalQueue: DispatchQueue) -> InternalDefaultRealtimeObjects {
        InternalDefaultRealtimeObjects(
            logger: TestLogger(),
            internalQueue: internalQueue,
            userCallbackQueue: .main,
            clock: MockSimpleClock(),
            channelName: "test-channel",
        )
    }

    // Two messages of 60 KiB + 5 KiB = 66560 bytes exceed the 64 KiB (65536-byte) default limit, so
    // the publish is rejected with a 40009 error before reaching the core SDK.
    // @spec RTO15d
    @Test
    func publishRejectsMessagesExceedingMaxSize() async throws {
        let internalQueue = TestFactories.createInternalQueue()
        let realtimeObjects = Self.createRealtimeObjects(internalQueue: internalQueue)
        let coreSDK = MockCoreSDK(channelState: .attached, internalQueue: internalQueue)

        // The publish must be rejected before the core SDK is consulted; if the gate fails to fire,
        // the mock's unconfigured `nosync_publish` would trap instead of returning an error.
        let message1 = ProtocolTypes.OutboundObjectMessage(clientId: String(repeating: "a", count: 60 * 1024))
        #expect(message1.size == 60 * 1024)
        let message2 = ProtocolTypes.OutboundObjectMessage(clientId: String(repeating: "b", count: 5 * 1024))
        #expect(message2.size == 5 * 1024)

        let error = try await #require(throws: ARTErrorInfo.self) {
            try await realtimeObjects.testsOnly_publish(objectMessages: [message1, message2], coreSDK: coreSDK)
        }

        #expect(error.code == 40009)
        #expect(error.statusCode == 400)
        #expect(error.message == "ObjectMessages size 66560 exceeds maximum allowed size of 65536 bytes")
    }

    // A publish whose total size is within the limit is handed to the core SDK and succeeds.
    // @spec RTO15d
    @Test
    func publishAcceptsMessagesWithinMaxSize() async throws {
        let internalQueue = TestFactories.createInternalQueue()
        let realtimeObjects = Self.createRealtimeObjects(internalQueue: internalQueue)
        let coreSDK = MockCoreSDK(channelState: .attached, internalQueue: internalQueue)
        coreSDK.setPublishHandler { messages in
            PublishResult(serials: messages.map { _ in "serial" })
        }

        // Well within the 65536-byte limit.
        let message = ProtocolTypes.OutboundObjectMessage(clientId: String(repeating: "a", count: 1024))

        try await realtimeObjects.testsOnly_publish(objectMessages: [message], coreSDK: coreSDK)
    }

    // RTO15d: the gate reads the connection's negotiated `maxMessageSize` (from the latest
    // CONNECTED ProtocolMessage's connectionDetails, via `CoreSDK.nosync_maxMessageSize`). A message
    // within the 65536 default but above the smaller negotiated limit is rejected against that limit.
    // @spec RTO15d
    @Test
    func publishUsesConnectionMaxMessageSize() async throws {
        let internalQueue = TestFactories.createInternalQueue()
        let realtimeObjects = Self.createRealtimeObjects(internalQueue: internalQueue)
        // Negotiated limit of 2 KiB, well below the 65536 default.
        let coreSDK = MockCoreSDK(channelState: .attached, maxMessageSize: 2 * 1024, internalQueue: internalQueue)

        // 3 KiB: within the default fallback but over the negotiated 2 KiB limit.
        let message = ProtocolTypes.OutboundObjectMessage(clientId: String(repeating: "a", count: 3 * 1024))
        #expect(message.size == 3 * 1024)

        let error = try await #require(throws: ARTErrorInfo.self) {
            try await realtimeObjects.testsOnly_publish(objectMessages: [message], coreSDK: coreSDK)
        }

        #expect(error.code == 40009)
        #expect(error.statusCode == 400)
        #expect(error.message == "ObjectMessages size 3072 exceeds maximum allowed size of 2048 bytes")
    }

    // RTO15d: when the core SDK exposes no negotiated `maxMessageSize` (nil — no connection
    // details, or the server sent no limit), the gate falls back to the 65536 Ably default, so a
    // message that fits the default is accepted.
    // @spec RTO15d
    @Test
    func publishFallsBackToDefaultMaxMessageSizeWhenUnset() async throws {
        let internalQueue = TestFactories.createInternalQueue()
        let realtimeObjects = Self.createRealtimeObjects(internalQueue: internalQueue)
        // nil maxMessageSize → fall back to the 65536 default.
        let coreSDK = MockCoreSDK(channelState: .attached, maxMessageSize: nil, internalQueue: internalQueue)
        coreSDK.setPublishHandler { messages in
            PublishResult(serials: messages.map { _ in "serial" })
        }

        // 60 KiB: over any smaller negotiated limit but within the 65536 default.
        let message = ProtocolTypes.OutboundObjectMessage(clientId: String(repeating: "a", count: 60 * 1024))

        try await realtimeObjects.testsOnly_publish(objectMessages: [message], coreSDK: coreSDK)
    }
}
