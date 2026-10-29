import AblyPubSubDeviceSwift
import AblyTesting
import Foundation
import Testing

@Suite(.serialized)
struct AsyncAPITests {
    private func makeClient(clientId: String? = nil) async throws -> PubSubClient {
        let options = try await Sandbox.clientOptions()
        options.clientId = clientId
        return PubSubDevice.createClient(options: options)
    }

    @Test
    func channelAndConnectionOperations() async throws {
        let client = try await makeClient()
        defer { client.close() }
        let channel = client.channels.get("async-\(UUID().uuidString)")

        try await channel.attach()
        #expect(channel.state == .attached)

        let options = RealtimeChannelOptions()
        options.params = ["rewind": "1"]
        try await channel.setOptions(options)

        let publishResult = try #require(try await channel.publish("greeting", data: "hello"))
        #expect(publishResult.serials.count == 1)

        let batchResult = try #require(try await channel.publish([Message(name: "first", data: "one"), Message(name: "second", data: "two")]))
        #expect(batchResult.serials.count == 2)

        try await client.connection.ping()

        try await channel.detach()
        #expect(channel.state == .detached)
    }

    @Test
    func presenceOperations() async throws {
        let client = try await makeClient(clientId: "async-tester")
        defer { client.close() }
        let presence = client.channels.get("async-\(UUID().uuidString)").presence

        try await presence.enter("present")
        try await presence.update("still present")
        try await presence.leave(nil)
    }

    @Test
    func presenceOnBehalfOfClients() async throws {
        // Only a client without a client ID of its own can enter on behalf of others.
        let client = try await makeClient()
        defer { client.close() }
        let presence = client.channels.get("async-\(UUID().uuidString)").presence

        try await presence.enterClient("other-client", data: "present")
        try await presence.updateClient("other-client", data: "still present")
        try await presence.leaveClient("other-client", data: nil)
    }

    @Test
    func throwsErrorInfo() async throws {
        let options = ClientOptions(key: "fake.key:secret")
        options.endpoint = SandboxEnvironment.nonprodEndpoint
        let client = PubSubDevice.createClient(options: options)
        defer { client.close() }

        let error = await #expect(throws: ErrorInfo.self) {
            try await client.channels.get("async-\(UUID().uuidString)").attach()
        }
        #expect(error?.code == 40101)
    }

    /// Calling these functions from a main-actor-isolated context must compile in the Swift 6 language mode, with no `Sendable` diagnostics for the SDK object they are called on or the data passed to them.
    @MainActor
    @Test
    func callableFromMainActor() async throws {
        let client = try await makeClient(clientId: "main-actor-tester")
        defer { client.close() }
        let channel = client.channels.get("async-\(UUID().uuidString)")
        // Neither the protocol existential nor the dictionary is `Sendable`.
        let channelProtocol: any RealtimeChannelProtocol = channel
        let data: [String: Any] = ["key": "value"]

        try await channelProtocol.attach()
        try await channelProtocol.publish("dictionary", data: data)
        try await channel.presence.enter(data)
        try await channelProtocol.detach()
    }
}
