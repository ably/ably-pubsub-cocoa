// Proxy tests spawn a local uts-proxy process — macOS-only.
#if os(macOS)

import Testing
import Foundation
import AblyPubSubDevice

/// Auth re-authorization (RTN22, RTC8a)
/// Derived from ably/specification `uts/realtime/integration/proxy/auth_reauth.md`
///
/// Proxy integration test against Ably Sandbox endpoint.
///
/// Uses the programmable uts-proxy to inject transport-level faults while the
/// SDK communicates with the real Ably backend. See
/// `uts/docs/proxy.md` for proxy infrastructure details.
///
/// Needs outbound network (the uts-proxy binary on first run, then the Ably sandbox):
///
/// ```bash
/// swift test --filter UTS.AuthReauthTests
/// ```
@Suite(.serialized)
final class AuthReauthTests: ProxyTestCase {

    // UTS: realtime/proxy/RTN22/server-initiated-reauth-0
    @Test
    func test_RTN22_RTC8a_server_initiated_reauthentication() async throws {
        // Setup
        // Proxy rules: None (passthrough). The AUTH injection is triggered imperatively after the
        // SDK connects. (The spec's BEFORE/AFTER ALL sandbox app provisioning and the session
        // teardown are owned by the withProxySession scope.)
        try await withProxySession(rules: []) { app, session in
            // SDK config: Use authCallback so re-authentication can be observed.
            // Generate a JWT token signed with the sandbox key
            // (cocoa equivalent: a TokenRequest signed locally with the sandbox key by a separate
            // TLS "token signer" ARTRest — the proxyClientOptions pattern, inlined here so the
            // test can count the authCallback invocations itself)
            let authCallbackInvocations = Captured<ARTTokenParams>()
            let signerOptions = ARTClientOptions(key: app.defaultKey)
            signerOptions.restHost = SandboxApp.sandboxHost
            let tokenSigner = ARTRest(options: signerOptions)

            let options = ARTClientOptions()
            options.authCallback = { params, callback in
                authCallbackInvocations.append(params)
                tokenSigner.auth.createTokenRequest(params, options: nil) { tokenRequest, error in
                    callback(tokenRequest, error)
                }
            }
            // endpoint "localhost" + proxy port + tls: false + useBinaryProtocol: false
            options.connectThroughProxy(session)
            options.autoConnect = false

            try await withRealtimeClient(options) { client in
                // Test Steps
                // Connect through proxy
                client.connect()
                guard await awaitState(client, .connected, timeout: 15) else { return }

                // Record identity and auth state before injection
                // ASSERT original_connection_id IS NOT null
                let originalConnectionId = try #require(client.connection.id)
                let originalAuthCallbackCount = authCallbackInvocations.count
                #expect(originalAuthCallbackCount >= 1)

                // Record state changes from this point
                let stateChanges = Captured<ARTRealtimeConnectionState>()
                client.connection.on { change in
                    stateChanges.append(change.current)
                }

                // Inject a server-initiated AUTH ProtocolMessage (action 17)
                // This simulates Ably requesting re-authentication
                try await session.triggerAction(["type": "inject_to_client", "message": ["action": 17]])

                // Wait for the SDK to process the AUTH and send its response
                // The authCallback should be invoked, and the SDK should send AUTH back.
                // Allow time for the token request round-trip to the sandbox.
                guard await pollUntil("authCallback re-invoked after injected AUTH", timeout: 15, {
                    authCallbackInvocations.count > originalAuthCallbackCount
                }) else { return }
                // Timing adaptation (not a deviation): the spec's callback returns a ready JWT, so
                // the AUTH frame follows the callback immediately. The cocoa callback returns a
                // TokenRequest that the SDK still exchanges for a token (a REST round-trip through
                // the proxy) before sending AUTH — so also wait for the AUTH frame to reach the
                // proxy log before asserting on it.
                guard let clientAuthFrames = await pollUntil("client-to-server AUTH frame recorded in the proxy log", timeout: 15, interval: 0.5, {
                    let log = (try? await session.getLog()) ?? []
                    let frames = self.clientToServerAuthFrames(in: log)
                    return frames.isEmpty ? nil : frames
                }) else { return }

                // Assertions
                // authCallback was called again (re-authentication triggered)
                #expect(authCallbackInvocations.count == originalAuthCallbackCount + 1)

                // Connection remains CONNECTED (re-auth does not disrupt the connection)
                #expect(client.connection.state == .connected)

                // Connection ID is unchanged (no reconnection occurred)
                #expect(client.connection.id == originalConnectionId)

                // No state transitions away from CONNECTED occurred
                let nonConnectedChanges = stateChanges.all.filter { state in
                    state != .connected
                }
                #expect(nonConnectedChanges.count == 0)

                // Proxy log shows the SDK sent an AUTH frame (action 17) from client to server
                // (the frames the poll above settled on — the log is append-only, so they stand)
                #expect(clientAuthFrames.count >= 1)

                // Spec note: after the SDK sends the AUTH response, the server may respond with a
                // CONNECTED message (connection update per RTN24). Since the injected AUTH was not
                // a genuine server request, the real Ably server may not respond as expected — the
                // key assertions are that the SDK's auth machinery was triggered (authCallback
                // invoked, AUTH frame sent) and that the connection was not disrupted.
            }
            // Cleanup (per spec): client.connection.close() + AWAIT_STATE closed (15s) is handled
            // by the withRealtimeClient scope; session.close() by the withProxySession scope.
        }
    }
}

extension AuthReauthTests {
    /// Client→server AUTH frames (action 17) carrying non-nil `auth` details — the spec's
    /// `client_auth_frames` filter over the proxy event log.
    func clientToServerAuthFrames(in log: [ProxyEvent]) -> [ProxyEvent] {
        log.filter { event in
            event.type == "ws_frame"
                && event.direction == "client_to_server"
                && (event.message?["action"] as? Int == 17 || event.message?["action"] as? String == "AUTH")
                && event.message?["auth"] != nil
        }
    }
}

#endif
