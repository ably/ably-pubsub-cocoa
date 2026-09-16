import _AblyPluginSupportPrivate
@testable import AblyLiveObjects
@testable import AblyLiveObjectsTesting
import AblyPubSubDevice
import Testing

@Suite(.tags(.integration), .serialized)
struct AblyLiveObjectsTests {
    @Test
    func objectsProperty() async throws {
        // Given

        let clientOptions = ARTClientOptions(key: "foo:bar")
        clientOptions.plugins = [.liveObjects: AblyLiveObjects.Plugin.self]
        // Don't need to connect
        clientOptions.autoConnect = false

        let realtime = ARTRealtimeClient(options: clientOptions)

        let channel = realtime.channels.get("someChannel")

        // Then

        // Check that the `channel.object` property works and gives the internal type we expect
        #expect(channel.object is PublicDefaultRealtimeObject)
    }

    /// A basic test of the core interactions between this plugin and ably-cocoa.
    @Test(arguments: [true, false])
    func plumbingSmokeTest(useBinaryProtocol: Bool) async throws {
        let clientOptions = try await Sandbox.clientOptions()
        clientOptions.plugins = [.liveObjects: AblyLiveObjects.Plugin.self]
        clientOptions.useBinaryProtocol = useBinaryProtocol

        let realtime = ARTRealtimeClient(options: clientOptions)
        defer { realtime.close() }

        // 1. Create a Map on a channel using the REST API.
        // https://ably.com/docs/api/liveobjects-rest

        let channelName = UUID().uuidString

        // swiftlint:disable:next force_cast
        let restClientOptions = clientOptions.copy() as! ARTClientOptions
        // TODO: Understand why the LiveObjects REST API is failing when I try to use MessagePack (asked in https://ably-real-time.slack.com/archives/CURL4U2FP/p1749739112276359); for now am just using a separate client that always uses JSON.
        restClientOptions.useBinaryProtocol = false
        let rest = ARTHttpClient(options: restClientOptions)

        let currentAblyTimestamp = UInt64(Date().timeIntervalSince1970) * MSEC_PER_SEC

        let mapCreateResponse = try await rest.requestAsync(
            "POST",
            path: "/channels/\(channelName)/objects",
            params: nil,
            body: [
                "operation": "MAP_CREATE",
                "data": [
                    "title": [
                        "string": "LiveObjects is awesome",
                    ],
                    "createdAt": [
                        "number": currentAblyTimestamp,
                    ],
                    "isPublished": [
                        "boolean": true,
                    ],
                ],
            ],
            headers: nil,
        )

        try #require(mapCreateResponse.statusCode == 201)
        let restCreatedMapObjectID = try #require((mapCreateResponse.items.first?["objectIds"] as? [String])?.first)

        // 2. Attach to the channel on which we just created the Map.
        let channelOptions = ARTRealtimeChannelOptions()
        channelOptions.modes = [.objectPublish, .objectSubscribe]
        let channel = realtime.channels.get(channelName, options: channelOptions)
        try await channel.attachAsync()

        // Go through the real public proxy plumbing (rather than a test-only reimplementation of it)
        // to reach the internal objects and a `CoreSDK` for publishing.
        let object = channel.testsOnly_nonTypeErasedObject
        let objects = object.testsOnly_proxied
        let coreSDK = object.testsOnly_coreSDK

        // 3. Check that ably-cocoa called our onChannelAttached and passed the HAS_OBJECTS flag.
        #expect(objects.testsOnly_onChannelAttachedHasObjects == true)

        // 4. Check that ably-cocoa used us to decode the ObjectMessages in the OBJECT_SYNC, and then called our handleObjectSyncProtocolMessage with these ObjectMessages; we expect the OBJECT_SYNC to contain the root object and the map that we created in the REST call above.
        let objectSyncObjectMessages = try #require(await objects.testsOnly_receivedObjectSyncProtocolMessages.first { _ in true })
        #expect(Set(objectSyncObjectMessages.map(\.object?.objectId)) == ["root", restCreatedMapObjectID])

        // 5. Now, send an OBJECT ProtocolMessage that creates a new Map. This confirms that Ably is using us to encode this ProtocolMessage's contained ObjectMessages.

        let initialValueJSON = #"{"mapCreate":{"semantics":0}}"#
        let realtimeCreatedMapObjectID = ObjectCreationHelpers.testsOnly_createObjectID(
            type: "map",
            initialValue: initialValueJSON,
            nonce: "1",
            timestamp: Date(timeIntervalSince1970: Double(currentAblyTimestamp) / 1000),
        )

        try await objects.testsOnly_publish(objectMessages: [
            ProtocolTypes.OutboundObjectMessage(
                operation: .init(
                    action: .known(.mapCreate),
                    objectId: realtimeCreatedMapObjectID,
                    mapCreate: .init(semantics: .known(.lww), entries: nil),
                    mapCreateWithObjectId: .init(initialValue: initialValueJSON, nonce: "1"),
                ),
            ),
        ], coreSDK: coreSDK)

        // 6. Check that ably-cocoa used us to decode the ObjectMessages in the OBJECT triggered by this map creation, and then called our handleObjectProtocolMessage with these ObjectMessages; we expect the OBJECT to contain the map create operation that we just performed.
        let objectObjectMessages = try #require(await objects.testsOnly_receivedObjectProtocolMessages.first { _ in true })
        try #require(objectObjectMessages.count == 1)
        let receivedMapCreateObjectMessage = objectObjectMessages[0]
        #expect(receivedMapCreateObjectMessage.operation?.objectId == realtimeCreatedMapObjectID)
        #expect(receivedMapCreateObjectMessage.operation?.action == .known(.mapCreate))

        // 7. Now, send an invalid OBJECT ProtocolMessage to check that ably-cocoa correctly reports on its NACK.
        let invalidObjectThrownError = try await #require(throws: ARTErrorInfo.self) {
            try await objects.testsOnly_publish(objectMessages: [
                .init(),
            ], coreSDK: coreSDK)
        }

        // (These are just based on what I observed in the NACK)
        #expect(invalidObjectThrownError.code == 92000)
        #expect(invalidObjectThrownError.message == "invalid object message: object operation required")
    }
}
