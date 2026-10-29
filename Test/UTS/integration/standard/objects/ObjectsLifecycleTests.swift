import Testing
import Foundation
import AblyPubSubDevice
import AblyLiveObjects

/// Objects lifecycle (RTO23, RTPO15, RTPO17)
/// Derived from ably/specification `uts/objects/integration/objects_lifecycle_test.md`
///
/// Direct-sandbox integration test against the Ably Sandbox (`sandbox.realtime.ably-nonprod.net`,
/// via SandboxApp.sandboxHost) — no proxy, no fault injection. Provisions a throwaway SandboxApp
/// and connects real clients straight to the sandbox.
///
/// End-to-end lifecycle: connect, sync, create objects via PathObject, mutate, and verify
/// propagation to a second client. Complements unit tests by verifying real server sync, mutation
/// delivery, and object creation.
@Suite(.serialized)
final class ObjectsLifecycleTests: IntegrationTestCase {

    // UTS: objects/integration/RTO23-RTPO15/set-primitive-propagates-0
    @Test(arguments: [false, true]) // useBinaryProtocol: false = JSON, true = msgpack
    func RTO23_RTPO15_set_primitive_via_PathObject_second_client_reads_it(useBinaryProtocol: Bool) async throws {
        // The spec's BEFORE/AFTER ALL sandbox app provisioning is owned by the withSandboxApp scope.
        try await withSandboxApp { app in
            // Setup
            let channelName = "objects-lifecycle-\(UUID().uuidString)"

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

                    let rootA = try await channelA.object.get()
                    let rootB = try await channelB.object.get()

                    // Test Steps
                    // Client A sets a value
                    try await rootA.set(key: "greeting", value: "hello")

                    // Client B subscribes and waits for the update
                    let eventsB = Captured<PathObjectSubscriptionEvent>()
                    try rootB.subscribe { event in eventsB.append(event) }
                    guard await pollUntil("rootB.greeting == \"hello\"", timeout: 10, {
                        stringValue(at: rootB.get(key: "greeting")) == "hello"
                    }) else { return }

                    // Assertions
                    #expect(stringValue(at: rootB.get(key: "greeting")) == "hello")

                    // Teardown (spec: client_a.close() / client_b.close()) — handled by the
                    // withRealtimeClient scopes.
                }
            }
        }
    }

    // UTS: objects/integration/RTPO15/set-counter-value-type-0
    @Test(arguments: [false, true]) // useBinaryProtocol: false = JSON, true = msgpack
    func RTPO15_set_with_LiveCounter_second_client_reads_counter(useBinaryProtocol: Bool) async throws {
        try await withSandboxApp { app in
            // Setup
            let channelName = "objects-counter-create-\(UUID().uuidString)"

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

                    let rootA = try await channelA.object.get()
                    let rootB = try await channelB.object.get()

                    // Test Steps
                    try await rootA.set(key: "my_counter", value: .liveCounter(.create(initialCount: 42)))
                    guard await pollUntil("rootB.my_counter == 42", timeout: 10, {
                        counterValue(at: rootB.get(key: "my_counter")) == 42
                    }) else { return }

                    // Assertions
                    #expect(counterValue(at: rootB.get(key: "my_counter")) == 42)
                    #expect(try rootB.get(key: "my_counter").instance() != nil)

                    // Teardown — handled by the withRealtimeClient scopes.
                }
            }
        }
    }

    // UTS: objects/integration/RTPO17/increment-propagates-0
    @Test(arguments: [false, true]) // useBinaryProtocol: false = JSON, true = msgpack
    func RTPO17_increment_counter_second_client_sees_updated_value(useBinaryProtocol: Bool) async throws {
        try await withSandboxApp { app in
            // Setup
            let channelName = "objects-increment-\(UUID().uuidString)"

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

                    let rootA = try await channelA.object.get()
                    let rootB = try await channelB.object.get()

                    // Test Steps
                    // Create a counter first
                    try await rootA.set(key: "hits", value: .liveCounter(.create(initialCount: 0)))
                    guard await pollUntil("rootB.hits == 0", timeout: 10, {
                        counterValue(at: rootB.get(key: "hits")) == 0
                    }) else { return }

                    // Increment it
                    try await rootA.get(key: "hits").asLiveCounter().increment(amount: 10)
                    guard await pollUntil("rootB.hits == 10", timeout: 10, {
                        counterValue(at: rootB.get(key: "hits")) == 10
                    }) else { return }

                    // Assertions
                    #expect(counterValue(at: rootA.get(key: "hits")) == 10)
                    #expect(counterValue(at: rootB.get(key: "hits")) == 10)

                    // Teardown — handled by the withRealtimeClient scopes.
                }
            }
        }
    }

    // UTS: objects/integration/RTPO15/set-map-value-type-0
    @Test(arguments: [false, true]) // useBinaryProtocol: false = JSON, true = msgpack
    func RTPO15_set_with_LiveMap_second_client_reads_nested_map(useBinaryProtocol: Bool) async throws {
        try await withSandboxApp { app in
            // Setup
            let channelName = "objects-map-create-\(UUID().uuidString)"

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

                    let rootA = try await channelA.object.get()
                    let rootB = try await channelB.object.get()

                    // Test Steps
                    try await rootA.set(key: "settings", value: .liveMap(.create(entries: [
                        "theme": "dark",
                        "fontSize": 14,
                    ])))
                    guard await pollUntil("rootB.settings.theme == \"dark\"", timeout: 10, {
                        stringValue(at: rootB.get(key: "settings").asLiveMap().get(key: "theme")) == "dark"
                    }) else { return }

                    // Assertions
                    #expect(stringValue(at: rootB.get(key: "settings").asLiveMap().get(key: "theme")) == "dark")
                    #expect(numberValue(at: rootB.get(key: "settings").asLiveMap().get(key: "fontSize")) == 14)

                    // Teardown — handled by the withRealtimeClient scopes.
                }
            }
        }
    }

    // UTS: objects/integration/RTO23/get-returns-path-object-0
    @Test(arguments: [false, true]) // useBinaryProtocol: false = JSON, true = msgpack
    func RTO23_get_waits_for_sync_and_returns_PathObject(useBinaryProtocol: Bool) async throws {
        try await withSandboxApp { app in
            // Setup
            let channelName = "objects-get-root-\(UUID().uuidString)"

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
                #expect(try root.size() == 0)

                // Teardown (spec: client.close()) — handled by the withRealtimeClient scope.
            }
        }
    }

    // UTS: objects/integration/RTPO15/rest-provisioned-data-sync-0
    @Test(arguments: [false, true]) // useBinaryProtocol: false = JSON, true = msgpack
    func RTPO15_client_syncs_pre_existing_data_provisioned_via_REST(useBinaryProtocol: Bool) async throws {
        try await withSandboxApp { app in
            // Setup
            let channelName = "objects-rest-provision-\(UUID().uuidString)"

            // Provision data via REST before any realtime client connects
            try await provisionObjectsViaRest(apiKey: app.defaultKey, channelName: channelName, operations: [
                mapSetOp(key: "provisioned", value: valueString("from_rest"), objectId: "root"),
            ])

            // Test Steps
            let options = objectsClientOptions(key: app.defaultKey, useBinaryProtocol: useBinaryProtocol)
            try await withRealtimeClient(options) { client in
                client.connect()
                guard await awaitState(client, .connected, timeout: 15) else { return }

                let channel = objectsChannel(client, channelName)
                let root = try await channel.object.get()

                // Assertions
                #expect(stringValue(at: root.get(key: "provisioned")) == "from_rest")

                // Teardown (spec: client.close()) — handled by the withRealtimeClient scope.
            }
        }
    }
}
