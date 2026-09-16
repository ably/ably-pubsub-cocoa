import Testing
import Foundation
import AblyPubSubDevice

/// Realtime token request (RSA9, RSA9a, RSA9g)
/// Derived from ably/specification `uts/realtime/integration/auth/token_request_test.md`
///
/// Direct-sandbox integration test against the Ably Sandbox (`sandbox.realtime.ably-nonprod.net`,
/// via SandboxApp.sandboxHost) — no proxy, no fault injection. Provisions a throwaway SandboxApp
/// and connects real clients straight to the sandbox.
///
/// End-to-end verification that `auth.createTokenRequest` produces a signed TokenRequest that the
/// Ably service accepts — validating that the HMAC signature computation (RSA9g) is compatible
/// with the server.
///
/// Needs outbound network (the Ably sandbox):
///
/// ```bash
/// swift test --filter UTS.TokenRequestTests
/// ```
@Suite(.serialized)
final class TokenRequestTests: IntegrationTestCase {

    // UTS: realtime/integration/RSA9a/token-request-server-accepted-0
    @Test
    func test_RSA9a_RSA9g_createTokenRequest_produces_server_accepted_token() async throws {
        // The spec's BEFORE/AFTER ALL sandbox app provisioning is owned by the withSandboxApp scope.
        try await withSandboxApp { app in
            // Setup
            // Client A creates TokenRequests using the API key
            let creatorOptions = ARTClientOptions(key: app.defaultKey)
            creatorOptions.restHost = SandboxApp.sandboxHost
            let creator = ARTHttpClient(options: creatorOptions)

            // Client B connects using TokenRequests from client A
            let options = ARTClientOptions()
            options.authCallback = { _, callback in
                creator.auth.createTokenRequest(nil, options: nil) { tokenRequest, error in
                    callback(tokenRequest, error)
                }
            }
            options.realtimeHost = SandboxApp.sandboxHost
            options.restHost = SandboxApp.sandboxHost
            options.autoConnect = false
            options.useBinaryProtocol = false

            try await withRealtimeClient(options) { client in
                // Test Steps
                client.connect()
                guard await awaitState(client, .connected, timeout: 15) else { return }

                // Assertions
                #expect(client.connection.state == .connected)
                #expect(client.connection.id != nil)
                #expect(client.connection.errorReason == nil)

                // CLOSE_CLIENT(client) — handled by the withRealtimeClient scope
                // (close + await CLOSED).
            }
        }
    }

    // UTS: realtime/integration/RSA9/token-request-with-clientid-0
    @Test
    func test_RSA9_createTokenRequest_with_clientId() async throws {
        try await withSandboxApp { app in
            // Setup
            let testClientId = "token-request-client-\(UUID().uuidString)"

            let creatorOptions = ARTClientOptions(key: app.defaultKey)
            creatorOptions.restHost = SandboxApp.sandboxHost
            let creator = ARTHttpClient(options: creatorOptions)

            let options = ARTClientOptions()
            options.authCallback = { _, callback in
                creator.auth.createTokenRequest(ARTTokenParams(clientId: testClientId), options: nil) { tokenRequest, error in
                    callback(tokenRequest, error)
                }
            }
            options.clientId = testClientId
            options.realtimeHost = SandboxApp.sandboxHost
            options.restHost = SandboxApp.sandboxHost
            options.autoConnect = false
            options.useBinaryProtocol = false

            try await withRealtimeClient(options) { client in
                // Test Steps
                client.connect()
                guard await awaitState(client, .connected, timeout: 15) else { return }

                // Assertions
                #expect(client.connection.state == .connected)
                #expect(client.auth.clientId == testClientId)

                // CLOSE_CLIENT(client) — handled by the withRealtimeClient scope
                // (close + await CLOSED).
            }
        }
    }
}
