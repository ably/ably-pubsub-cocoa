import Testing
import Foundation
import Ably
import AblyLiveObjects

/// Objects sync (RTO4, RTO5, RTO17)
/// Derived from ably/specification `uts/objects/integration/objects_sync_test.md`
///
/// Direct-sandbox integration test against the Ably Sandbox (`sandbox.realtime.ably-nonprod.net`,
/// via SandboxApp.sandboxHost) — no proxy, no fault injection. Provisions a throwaway SandboxApp
/// and connects real clients straight to the sandbox.
///
/// Verifies the sync sequence against the real server: attach with HAS_OBJECTS, receive
/// OBJECT_SYNC, reach SYNCED state. Also tests re-attach behaviour where the client detaches and
/// re-attaches to verify the pool is re-synced.
@Suite(.serialized)
final class ObjectsSyncTests: IntegrationTestCase {

    // UTS: objects/integration/RTO4-RTO5/attach-sync-get-0
    @Test(arguments: [false, true]) // useBinaryProtocol: false = JSON, true = msgpack
    func test_RTO4_RTO5_attach_triggers_sync_get_resolves_after_SYNCED(useBinaryProtocol: Bool) async throws {
        // The spec's BEFORE/AFTER ALL sandbox app provisioning is owned by the withSandboxApp scope.
        try await withSandboxApp { app in
            // Setup
            let channelName = "objects-sync-\(UUID().uuidString)"

            let options = objectsClientOptions(key: app.defaultKey, useBinaryProtocol: useBinaryProtocol)
            try await withRealtimeClient(options) { client in
                client.connect()
                guard await awaitState(client, .connected, timeout: 15) else { return }

                let channel = objectsChannel(client, channelName)

                // Test Steps
                let root = try await channel.object.get()

                // Assertions
                // ASSERT root IS PathObject
                // (no runtime assertion: satisfied by get()'s return type, `any LiveMapPathObject`)
                #expect(root.path == "")

                // Teardown (spec: client.close()) — handled by the withRealtimeClient scope.
            }
        }
    }

    // UTS: objects/integration/RTO5-RTO17/two-clients-sync-0
    @Test(arguments: [false, true]) // useBinaryProtocol: false = JSON, true = msgpack
    func test_RTO5_RTO17_two_clients_sync_same_channel_with_pre_existing_data(useBinaryProtocol: Bool) async throws {
        try await withSandboxApp { app in
            // Setup
            let channelName = "objects-two-sync-\(UUID().uuidString)"

            let optionsA = objectsClientOptions(key: app.defaultKey, useBinaryProtocol: useBinaryProtocol)
            let optionsB = objectsClientOptions(key: app.defaultKey, useBinaryProtocol: useBinaryProtocol)

            try await withRealtimeClient(optionsA) { clientA in
                try await withRealtimeClient(optionsB) { clientB in
                    clientA.connect()
                    guard await awaitState(clientA, .connected, timeout: 15) else { return }

                    clientB.connect()
                    guard await awaitState(clientB, .connected, timeout: 15) else { return }

                    let channelA = objectsChannel(clientA, channelName)
                    let channelB = objectsChannel(clientB, channelName)

                    // Test Steps
                    // Client A creates data
                    let rootA = try await channelA.object.get()
                    try await rootA.set(key: "key1", value: "value1")

                    // Client B attaches and syncs — should see the data
                    let rootB = try await channelB.object.get()
                    guard await pollUntil("rootB.key1 == \"value1\"", timeout: 10, {
                        stringValue(at: rootB.get(key: "key1")) == "value1"
                    }) else { return }

                    // Assertions
                    #expect(stringValue(at: rootB.get(key: "key1")) == "value1")

                    // Teardown (spec: client_a.close() / client_b.close()) — handled by the
                    // withRealtimeClient scopes.
                }
            }
        }
    }

    // UTS: objects/integration/RTO17/reattach-resyncs-0
    @Test(arguments: [false, true]) // useBinaryProtocol: false = JSON, true = msgpack
    func test_RTO17_reattach_resyncs_object_pool(useBinaryProtocol: Bool) async throws {
        try await withSandboxApp { app in
            // Setup
            let channelName = "objects-reattach-\(UUID().uuidString)"

            let options = objectsClientOptions(key: app.defaultKey, useBinaryProtocol: useBinaryProtocol)
            try await withRealtimeClient(options) { client in
                client.connect()
                guard await awaitState(client, .connected, timeout: 15) else { return }

                let channel = objectsChannel(client, channelName)
                var root = try await channel.object.get()

                // Test Steps
                // Set some data
                try await root.set(key: "before_detach", value: "hello")
                #expect(stringValue(at: root.get(key: "before_detach")) == "hello")

                // Detach and re-attach
                await awaitDetach(channel)
                await awaitAttach(channel)

                // Re-sync should restore data
                root = try await channel.object.get()
                let reSyncedRoot = root
                guard await pollUntil("root.before_detach == \"hello\" after re-attach", timeout: 10, {
                    stringValue(at: reSyncedRoot.get(key: "before_detach")) == "hello"
                }) else { return }

                // Assertions
                #expect(stringValue(at: root.get(key: "before_detach")) == "hello")

                // Teardown (spec: client.close()) — handled by the withRealtimeClient scope.
            }
        }
    }

    // UTS: objects/integration/RTO4/attach-subscribe-only-0
    @Test(arguments: [false, true]) // useBinaryProtocol: false = JSON, true = msgpack
    func test_RTO4_attach_without_OBJECT_PUBLISH_still_resolves_get_with_empty_pool(useBinaryProtocol: Bool) async throws {
        try await withSandboxApp { app in
            // Setup
            let channelName = "objects-subscribe-only-\(UUID().uuidString)"

            let options = objectsClientOptions(key: app.defaultKey, useBinaryProtocol: useBinaryProtocol)
            try await withRealtimeClient(options) { client in
                client.connect()
                guard await awaitState(client, .connected, timeout: 15) else { return }

                let channel = objectsChannel(client, channelName, modes: [.objectSubscribe])

                // Test Steps
                let root = try await channel.object.get()

                // Assertions
                // ASSERT root IS PathObject
                // (no runtime assertion: satisfied by get()'s return type, `any LiveMapPathObject`)
                #expect(try root.size() == 0)

                // Teardown (spec: client.close()) — handled by the withRealtimeClient scope.
            }
        }
    }
}

extension ObjectsSyncTests {
    /// Awaits the channel detach acknowledgement (the spec's `AWAIT channel.detach()`), recording
    /// an issue on error.
    private func awaitDetach(_ channel: ARTRealtimeChannel,
                             sourceLocation: SourceLocation = #_sourceLocation) async {
        let failure: String? = await withCheckedContinuation { continuation in
            channel.detach { error in
                continuation.resume(returning: error.map { "\($0)" })
            }
        }

        if let failure {
            Issue.record("detach() failed: \(failure)", sourceLocation: sourceLocation)
        }
    }

    /// Awaits the channel attach acknowledgement (the spec's `AWAIT channel.attach()`), recording
    /// an issue on error.
    private func awaitAttach(_ channel: ARTRealtimeChannel,
                             sourceLocation: SourceLocation = #_sourceLocation) async {
        let failure: String? = await withCheckedContinuation { continuation in
            channel.attach { error in
                continuation.resume(returning: error.map { "\($0)" })
            }
        }

        if let failure {
            Issue.record("attach() failed: \(failure)", sourceLocation: sourceLocation)
        }
    }
}
