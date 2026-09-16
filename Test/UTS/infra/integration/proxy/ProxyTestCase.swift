// Proxy tests spawn a local uts-proxy process — macOS-only (see ProxyManager).
#if os(macOS)

import Foundation
import Testing
import AblyPubSubDevice

/// Base class for **proxy** integration suites:
/// `@Suite(.serialized) final class FooTests: ProxyTestCase`.
///
/// Extends `IntegrationTestCase` with the proxy tier's setup/teardown: `withProxySession` ensures
/// the proxy is running, provisions the sandbox app, creates the session, and always closes the
/// session and deletes the app afterwards — the shape every proxy test needs.
///
/// ```swift
/// try await withProxySession(rules: []) { app, session in
///     let options = proxyClientOptions(for: app, through: session)
///     options.autoConnect = false
///     try await withRealtimeClient(options) { client in
///         // scenario — late fault injection via session.triggerAction(…),
///         // verification via session.getLog()
///     }
/// }
/// ```
class ProxyTestCase: IntegrationTestCase {

    /// Ensures the proxy is running, provisions a sandbox app and a `ProxySession` with `rules`,
    /// runs `body`, then always closes the session and deletes the app.
    func withProxySession(rules: [ProxyRule] = [],
                          _ body: (SandboxApp, ProxySession) async throws -> Void) async throws {
        try await ProxyManager.shared.ensureProxy()
        try await withSandboxApp { app in
            let session = try await ProxySession.create(rules: rules)
            try await runThenCleanUp(session, body: { session in
                try await body(app, session)
            }) { session in
                await session.close()
            }
        }
    }

    /// Client options wired through the proxy with **token auth**: the proxy serves plain ws
    /// (`tls = false`) and basic (key) auth is TLS-only (RSA1), so the client authenticates via an
    /// `authCallback` that signs a `TokenRequest` locally using the sandbox key (through a
    /// separate TLS "token signer" client, as in ably-java's proxy tests).
    func proxyClientOptions(for app: SandboxApp, through session: ProxySession) -> ARTClientOptions {
        let signerOptions = ARTClientOptions(key: app.defaultKey)
        signerOptions.restHost = SandboxApp.sandboxHost
        let tokenSigner = ARTHttpClient(options: signerOptions)

        let options = ARTClientOptions()
        options.authCallback = { params, callback in
            tokenSigner.auth.createTokenRequest(params, options: nil) { tokenRequest, error in
                callback(tokenRequest, error)
            }
        }
        options.connectThroughProxy(session)
        return options
    }
}

#endif
