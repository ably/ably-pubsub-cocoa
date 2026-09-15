// Proxy tests spawn a local uts-proxy process — macOS-only.
#if os(macOS)

import Testing
import Foundation
import AblyPubSubDevice
import AblyLiveObjects

/// Objects fault handling (RTO5a2, RTO7, RTO8, RTO17, RTO20e, RTO20e1)
/// Derived from ably/specification `uts/objects/integration/proxy/objects_faults.md`
///
/// Proxy integration test against Ably Sandbox endpoint.
///
/// Uses the programmable uts-proxy to inject transport-level faults while the
/// SDK communicates with the real Ably backend. See
/// `uts/docs/proxy.md` for proxy infrastructure details.
///
/// Corresponding unit tests:
/// - `objects/unit/objects_pool.md` — RTO5a2 (new sync discards old), RTO7/RTO8 (buffering during
///   SYNCING)
/// - `objects/unit/realtime_object.md` — RTO17 (sync state events), RTO20e (publishAndApply waits
///   for SYNCED), RTO20e1 (in-flight operation fails with 92008 when the channel leaves the
///   attached state during the sync wait)
///
/// Needs outbound network (the uts-proxy binary on first run, then the Ably sandbox):
///
/// ```bash
/// swift test --filter UTS.ObjectsFaultsTests
/// ```
@Suite(.serialized)
final class ObjectsFaultsTests: ProxyTestCase {

    // UTS: objects/proxy/RTO5a2-RTO17/sync-interrupted-reconnect-0
    @Test
    func RTO5a2_RTO17_sync_interrupted_by_disconnect_resyncs_on_reconnect() async throws {
        // Setup
        // (The spec's BEFORE/AFTER ALL sandbox app provisioning, the session teardown, and the
        // common client-close cleanup are owned by the withProxySession/withRealtimeClient scopes.)
        let channelName = "objects-sync-interrupt-\(UUID().uuidString)"

        // Disconnect after first OBJECT_SYNC frame
        // (spec rule comment: "RTO5a2: Disconnect after first OBJECT_SYNC to interrupt sync".
        // OBJECT_SYNC must be matched by the numeric string "20" — uts-proxy resolves action
        // names only up to AUTH (17); wsFrameToClientRule stringifies the number.)
        try await withProxySession(rules: [
            wsFrameToClientRule(action: ["type": "disconnect"], messageAction: 20, times: 1),
        ]) { app, session in
            let options = objectsProxyClientOptions(for: app, through: session)
            try await withRealtimeClient(options) { client in
                let channel = objectsChannel(client, channelName)

                // Test Steps
                client.connect()
                guard await awaitState(client, .connected, timeout: 15) else { return }

                // First attach triggers sync; proxy disconnects mid-sync
                channel.attach()
                guard await awaitState(client, .disconnected, timeout: 15) else { return }

                // Client auto-reconnects; re-attach triggers fresh sync
                guard await awaitState(client, .connected, timeout: 30) else { return }

                // get() waits for SYNCED — will only resolve if re-sync completes
                // (spec: WITH timeout: 30 seconds — `await` takes no per-call timeout; a hang
                // surfaces as the test-runner timeout)
                let root = try await channel.object.get()

                // Assertions
                // ASSERT root IS PathObject
                // (no runtime assertion: satisfied by get()'s return type, `any LiveMapPathObject`)
                #expect(root.path == "")
            }
        }
    }

    // UTS: objects/proxy/RTO7-RTO8/mutations-buffered-during-resync-0
    @Test
    func RTO7_RTO8_mutations_during_resync_are_buffered_and_applied() async throws {
        // Setup
        let channelName = "objects-buffer-resync-\(UUID().uuidString)"

        // (The spec creates client A before the proxy session; withProxySession owns the app +
        // session provisioning so the session scope opens first — functionally equivalent, since
        // only client B's traffic passes through the proxy.)
        try await withProxySession(rules: []) { app, session in
            // Client A: direct connection (no proxy), publishes mutations
            // (the spec doesn't fix client A's protocol; JSON to match the proxy tier)
            let optionsA = objectsClientOptions(key: app.defaultKey, useBinaryProtocol: false)
            try await withRealtimeClient(optionsA) { clientA in
                clientA.connect()
                guard await awaitState(clientA, .connected, timeout: 15) else { return }

                let channelA = objectsChannel(clientA, channelName)
                let rootA = try await channelA.object.get()

                // Set initial data
                try await rootA.set(key: "key1", value: "initial")

                // Client B: through proxy, will be disconnected
                let optionsB = objectsProxyClientOptions(for: app, through: session)
                try await withRealtimeClient(optionsB) { clientB in
                    let channelB = objectsChannel(clientB, channelName)

                    // Test Steps
                    // Client B connects and syncs
                    clientB.connect()
                    guard await awaitState(clientB, .connected, timeout: 15) else { return }

                    let rootB = try await channelB.object.get()
                    guard await pollUntil("rootB.key1 == \"initial\"", timeout: 10, {
                        stringValue(at: rootB.get(key: "key1")) == "initial"
                    }) else { return }

                    // Disconnect client B
                    try await session.triggerAction(["type": "disconnect"])
                    guard await awaitState(clientB, .disconnected, timeout: 15) else { return }

                    // While B is disconnected, A publishes a mutation
                    try await rootA.set(key: "key1", value: "updated_during_disconnect")

                    // Client B reconnects and re-syncs; the mutation should be visible
                    guard await awaitState(clientB, .connected, timeout: 30) else { return }

                    let resyncedRootB = try await channelB.object.get()
                    guard await pollUntil("rootB.key1 == \"updated_during_disconnect\"", timeout: 15, {
                        stringValue(at: resyncedRootB.get(key: "key1")) == "updated_during_disconnect"
                    }) else { return }

                    // Assertions
                    #expect(stringValue(at: resyncedRootB.get(key: "key1")) == "updated_during_disconnect")

                    // Teardown (spec: client_a.close() / client_b.close() / session.close()) —
                    // handled by the withRealtimeClient / withProxySession scopes.
                }
            }
        }
    }

    // UTS: objects/proxy/RTO17/server-detach-resync-0
    @Test
    func RTO17_server_initiated_detach_triggers_resync_on_reattach() async throws {
        // Setup
        let channelName = "objects-detach-resync-\(UUID().uuidString)"

        try await withProxySession(rules: []) { app, session in
            let options = objectsProxyClientOptions(for: app, through: session)
            try await withRealtimeClient(options) { client in
                let channel = objectsChannel(client, channelName)

                // Test Steps
                client.connect()
                guard await awaitState(client, .connected, timeout: 15) else { return }

                let root = try await channel.object.get()

                // Set some data
                try await root.set(key: "before_detach", value: "hello")
                #expect(stringValue(at: root.get(key: "before_detach")) == "hello")

                // Inject server-initiated DETACHED
                let detachedMessage: [String: any Sendable] = ["action": 13, "channel": channelName]
                try await session.triggerAction(["type": "inject_to_client", "message": detachedMessage])

                // Client should auto-re-attach (RTL13a)
                guard await awaitChannelState(channel, .attached, timeout: 30) else { return }

                // Re-sync should restore data
                let resyncedRoot = try await channel.object.get()
                guard await pollUntil("root.before_detach == \"hello\" after re-attach", timeout: 15, {
                    stringValue(at: resyncedRoot.get(key: "before_detach")) == "hello"
                }) else { return }

                // Assertions
                #expect(stringValue(at: resyncedRoot.get(key: "before_detach")) == "hello")
            }
        }
    }

    // UTS: objects/proxy/RTO20e/publish-fails-on-channel-failed-0
    @Test
    func RTO20e_publishAndApply_fails_when_channel_enters_FAILED_during_SYNCING() async throws {
        // Setup
        let channelName = "objects-publish-failed-\(UUID().uuidString)"

        try await withProxySession(rules: []) { app, session in
            let options = objectsProxyClientOptions(for: app, through: session)
            try await withRealtimeClient(options) { client in
                let channel = objectsChannel(client, channelName)

                // Test Steps
                client.connect()
                guard await awaitState(client, .connected, timeout: 15) else { return }

                let root = try await channel.object.get()

                // Force the objects back into SYNCING: inject an ATTACHED (action 11) carrying the
                // HAS_OBJECTS flag (bit 7, i.e. flags: 128). RTO4c starts a new sync sequence on every
                // ATTACHED protocol message; the server never sent this ATTACHED, so no OBJECT_SYNC
                // follows and the objects remain SYNCING. The channel itself stays ATTACHED.
                let attachedMessage: [String: any Sendable] = [
                    "action": 11,
                    "channel": channelName,
                    "flags": 128,
                ]
                try await session.triggerAction(["type": "inject_to_client", "message": attachedMessage])

                // Mutate WHILE SYNCING: the channel is ATTACHED so the write preconditions (RTO26)
                // pass and the publish + ACK complete against the real server; publishAndApply then
                // waits for a SYNCED that will never arrive (RTO20e). Do not await yet.
                let pending = Task { try await root.set(key: "key", value: "value") }

                // Ensure the operation is in the RTO20e sync-wait, not still publishing: wait until
                // the proxy log shows the server's ACK (action 1) for the OBJECT publish, then allow
                // a brief real-time yield for the client to move the ACKed operation into the wait.
                // (There is no observable client state between "ACK processed" and "parked in the
                // sync-wait" to poll on, so a small fixed yield is required — the deriving SDK may
                // substitute an equivalent scheduler yield.)
                guard await pollUntil("server ACK (action 1) recorded in the proxy log", timeout: 10, {
                    let log = (try? await session.getLog()) ?? []
                    return log.contains { event in
                        event.type == "ws_frame"
                            && event.direction == "server_to_client"
                            && event.message?["action"] as? Int == 1
                    }
                }) else { return }
                // WAIT 500ms  // real (wall-clock) time
                try await Task.sleep(nanoseconds: 500_000_000)

                // The channel enters FAILED whilst the operation waits for SYNCED (RTO20e1)
                let errorMessage: [String: any Sendable] = [
                    "action": 9,
                    "channel": channelName,
                    "error": ["statusCode": 400, "code": 90000, "message": "injected error"] as [String: any Sendable],
                ]
                try await session.triggerAction(["type": "inject_to_client", "message": errorMessage])

                guard await awaitChannelState(channel, .failed, timeout: 15) else { return }

                // AWAIT pending FAILS WITH error
                // (spec: WITH timeout: 15 seconds — `await` takes no per-call timeout; a hang
                // surfaces as the test-runner timeout)
                do {
                    try await pending.value
                    Issue.record("expected the pending set operation to fail with 92008 (RTO20e1)")
                } catch {
                    // Assertions
                    let errorInfo = try #require(error as? ARTErrorInfo) // Task erases the typed throw
                    #expect(errorInfo.code == 92008)
                    #expect(errorInfo.statusCode == 400)
                    // RTO20e1: cause is set to RealtimeChannel.errorReason — the injected channel ERROR
                    let cause = try #require(errorInfo.cause)
                    #expect(cause.code == 90000)
                }
            }
        }
    }

    // UTS: objects/proxy/RTO5-RTO7/publish-during-sync-echo-after-0
    @Test
    func RTO5_RTO7_publish_during_sync_echo_arrives_after_sync_completes() async throws {
        // Setup
        let channelName = "objects-publish-during-sync-\(UUID().uuidString)"

        // (As in the RTO7-RTO8 test, the spec creates client A before the proxy session; the
        // withProxySession scope opens first here, which is functionally equivalent — the delay
        // rule only sees client B's traffic.)
        // (spec rule comment: "Delay first OBJECT_SYNC to keep B in SYNCING state".
        // OBJECT_SYNC is matched by the numeric string "20".)
        try await withProxySession(rules: [
            wsFrameToClientRule(action: ["type": "delay", "delayMs": 3000], messageAction: 20, times: 1),
        ]) { app, session in
            // Client A: direct, no proxy
            // (the spec doesn't fix client A's protocol; JSON to match the proxy tier)
            let optionsA = objectsClientOptions(key: app.defaultKey, useBinaryProtocol: false)
            try await withRealtimeClient(optionsA) { clientA in
                clientA.connect()
                guard await awaitState(clientA, .connected, timeout: 15) else { return }

                let channelA = objectsChannel(clientA, channelName)
                let rootA = try await channelA.object.get()

                // Set up initial data
                try await rootA.set(key: "existing", value: "before")

                // Client B: through proxy with delayed OBJECT_SYNC
                let optionsB = objectsProxyClientOptions(for: app, through: session)
                try await withRealtimeClient(optionsB) { clientB in
                    let channelB = objectsChannel(clientB, channelName)

                    // Test Steps
                    // Start client B — will be stuck in SYNCING due to delayed OBJECT_SYNC
                    clientB.connect()
                    guard await awaitState(clientB, .connected, timeout: 15) else { return }
                    channelB.attach()

                    // While B is syncing, A publishes a mutation
                    try await rootA.set(key: "existing", value: "after")

                    // B's get() will resolve once delayed sync completes
                    // (spec: WITH timeout: 30 seconds — `await` takes no per-call timeout)
                    let rootB = try await channelB.object.get()

                    // The mutation from A should be visible (either in sync data or buffered OBJECT)
                    guard await pollUntil("rootB.existing == \"after\"", timeout: 15, {
                        stringValue(at: rootB.get(key: "existing")) == "after"
                    }) else { return }

                    // Assertions
                    #expect(stringValue(at: rootB.get(key: "existing")) == "after")

                    // Teardown (spec: client_a.close() / client_b.close() / session.close()) —
                    // handled by the withRealtimeClient / withProxySession scopes.
                }
            }
        }
    }
}

extension ObjectsFaultsTests {
    /// Proxy client options (token auth, JSON, localhost proxy — the base class's
    /// `proxyClientOptions`) with the LiveObjects plugin installed (accessing `channel.object`
    /// without it is a programmer error) and the spec's `autoConnect: false`.
    ///
    /// The spec's proxied clients use `key: api_key` directly, but the proxy serves plain ws
    /// (`tls: false`) and basic auth is TLS-only (RSA1), so `proxyClientOptions` substitutes a
    /// locally-signed TokenRequest — the standard proxy-tier adaptation.
    func objectsProxyClientOptions(for app: SandboxApp, through session: ProxySession) -> ARTClientOptions {
        let options = proxyClientOptions(for: app, through: session)
        options.plugins = [.liveObjects: AblyLiveObjects.Plugin.self]
        options.autoConnect = false
        return options
    }
}

#endif
