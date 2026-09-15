import Testing
import Foundation
import AblyPubSubDevice
import AblyLiveObjects

/// Objects GC — tombstone semantics (RTO10, RTLM19, RTLM5d2h, RTLM7)
/// Derived from ably/specification `uts/objects/integration/objects_gc_test.md`
///
/// Direct-sandbox integration test against the Ably Sandbox (`sandbox.realtime.ably-nonprod.net`,
/// via SandboxApp.sandboxHost) — no proxy, no fault injection. Provisions a throwaway SandboxApp
/// and connects real clients straight to the sandbox.
///
/// Behavioral verification of tombstone semantics end-to-end against the real server: removing a
/// map entry tombstones it (RTLM7), tombstoned entries read back as undefined/null (RTLM5d2h), and
/// the same key is recreatable — the server assigns a fresh objectId to the replacement object,
/// which is safe because tombstoned state is retained for the GC grace period (RTO10).
///
/// The timer-based GC sweep itself (RTO10a–RTO10c, RTLM19a) is verified at the **unit tier**
/// (`objects/unit/realtime_object.md`) where the clock is controllable; it is intentionally not
/// exercised here (the sweep cadence plus the default 24h grace period is not observable within
/// test timeouts, and integration tests run on wall-clock time — no `ADVANCE_TIME` in this file).
///
/// The spec's `value() == null` assertions denote its undefined/null absent value (RTLM5d2h) —
/// asserted here as the typed-view read returning `nil`.
@Suite(.serialized)
final class ObjectsGcTests: IntegrationTestCase {

    // UTS: objects/integration/RTO10/tombstoned-object-gc-recreate-0
    @Test(arguments: [false, true]) // useBinaryProtocol: false = JSON, true = msgpack
    func RTO10_tombstoned_object_is_recreatable_with_new_objectId(useBinaryProtocol: Bool) async throws {
        // The spec's BEFORE/AFTER ALL sandbox app provisioning is owned by the withSandboxApp scope.
        try await withSandboxApp { app in
            // Setup
            let channelName = "objects-gc-object-\(UUID().uuidString)"

            let options = objectsClientOptions(key: app.defaultKey, useBinaryProtocol: useBinaryProtocol)
            try await withRealtimeClient(options) { client in
                client.connect()
                guard await awaitState(client, .connected, timeout: 15) else { return }

                let channel = objectsChannel(client, channelName)
                // The spec's `WITH timeout: 15 seconds` on get() has no per-call Swift equivalent —
                // get() suspends until the sync completes; a hang surfaces as the test-runner timeout.
                let root = try await channel.object.get()

                // Test Steps
                // Create a counter
                try await root.set(key: "counter", value: .liveCounter(.create(initialCount: 42)))
                guard await pollUntil("root.counter == 42", timeout: 10, {
                    counterValue(at: root.get(key: "counter")) == 42
                }) else { return }

                let counterId = try counterInstanceId(at: root.get(key: "counter"))

                // Remove it (tombstones the entry and the object, RTLM7)
                try await root.remove(key: "counter")

                // RTLM5d2h: tombstoned entries read back as undefined/null
                guard await pollUntil("root.counter reads back as nil", timeout: 10, {
                    counterValue(at: root.get(key: "counter")) == nil
                }) else { return }

                // Create a new counter at the same key
                try await root.set(key: "counter", value: .liveCounter(.create(initialCount: 99)))
                guard await pollUntil("root.counter == 99", timeout: 10, {
                    counterValue(at: root.get(key: "counter")) == 99
                }) else { return }

                // Assertions
                #expect(counterValue(at: root.get(key: "counter")) == 99)
                #expect(try counterInstanceId(at: root.get(key: "counter")) != counterId)

                // Teardown (spec: client.close()) — handled by the withRealtimeClient scope.
            }
        }
    }

    // UTS: objects/integration/RTLM19/tombstoned-entry-gc-reset-0
    @Test(arguments: [false, true]) // useBinaryProtocol: false = JSON, true = msgpack
    func RTLM19_tombstoned_map_entry_is_re_settable(useBinaryProtocol: Bool) async throws {
        // The spec's BEFORE/AFTER ALL sandbox app provisioning is owned by the withSandboxApp scope.
        try await withSandboxApp { app in
            // Setup
            let channelName = "objects-gc-entry-\(UUID().uuidString)"

            let options = objectsClientOptions(key: app.defaultKey, useBinaryProtocol: useBinaryProtocol)
            try await withRealtimeClient(options) { client in
                client.connect()
                guard await awaitState(client, .connected, timeout: 15) else { return }

                let channel = objectsChannel(client, channelName)
                let root = try await channel.object.get()

                // Test Steps
                // Set then remove a key
                try await root.set(key: "ephemeral", value: "temporary")
                guard await pollUntil("root.ephemeral == \"temporary\"", timeout: 10, {
                    stringValue(at: root.get(key: "ephemeral")) == "temporary"
                }) else { return }

                try await root.remove(key: "ephemeral")

                // RTLM5d2h: tombstoned entries read back as undefined/null
                guard await pollUntil("root.ephemeral reads back as nil", timeout: 10, {
                    stringValue(at: root.get(key: "ephemeral")) == nil
                }) else { return }

                // Set the same key again
                try await root.set(key: "ephemeral", value: "revived")
                guard await pollUntil("root.ephemeral == \"revived\"", timeout: 10, {
                    stringValue(at: root.get(key: "ephemeral")) == "revived"
                }) else { return }

                // Assertions
                #expect(stringValue(at: root.get(key: "ephemeral")) == "revived")

                // Teardown (spec: client.close()) — handled by the withRealtimeClient scope.
            }
        }
    }
}
