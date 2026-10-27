import Foundation
import Testing
import Ably

/// Base class for **direct-sandbox** integration suites (the counterpart of `UTSTestCase` for the
/// unit tier): `@Suite(.serialized) final class FooTests: IntegrationTestCase`.
///
/// Swift Testing has no `setUp()`/`tearDown()` hooks and `deinit` cannot `await`, so setup and
/// async teardown are provided as **scoped-resource methods** instead: each `with…` method
/// provisions its resource, runs your body, and *always* tears the resource down — even when the
/// body throws or a wait inside it failed. A thrown error is rethrown after cleanup, so the test
/// still fails with the original error and nothing is orphaned.
///
/// ```swift
/// try await withSandboxApp { app in
///     let options = ARTClientOptions(key: app.defaultKey)
///     …
///     try await withRealtimeClient(options) { client in
///         // scenario — client is closed and app deleted afterwards, no matter what
///     }
/// }
/// ```
class IntegrationTestCase {

    /// Provisions a fresh sandbox app, runs `body`, then always deletes the app.
    func withSandboxApp(_ body: (SandboxApp) async throws -> Void) async throws {
        let app = try await SandboxApp.create()
        try await runThenCleanUp(app, body: body) { app in
            try await app.delete()
        }
    }

    /// Builds a real (unmocked) `ARTRealtime` from `options`, runs `body`, then always closes the
    /// client and waits for CLOSED.
    func withRealtimeClient(_ options: ARTClientOptions, _ body: (ARTRealtime) async throws -> Void) async throws {
        let client = ARTRealtime(options: options)
        try await runThenCleanUp(client, body: body) { client in
            // Per the specs' common cleanup: only close from a state that can reach CLOSED.
            // close() never transitions out of FAILED (terminal) or INITIALIZED (never
            // connected) — see ARTRealtime `_close` — so awaiting CLOSED there would burn the
            // timeout and record a spurious failure after the body passed.
            let state = client.connection.state
            if state != .failed, state != .initialized {
                client.close()
                await awaitState(client, .closed)
            }
        }
    }

    /// The scoped-resource engine every `with…` method is built on: run `body` over `resource`,
    /// then always run `cleanup` — rethrowing the body's error afterwards so the test fails with
    /// the original error and nothing is orphaned. Subclasses use this for their own scopes.
    func runThenCleanUp<Resource>(_ resource: Resource,
                                  body: (Resource) async throws -> Void,
                                  cleanup: (Resource) async throws -> Void) async throws {
        var thrown: Error?
        do {
            try await body(resource)
        } catch {
            thrown = error
        }
        do {
            try await cleanup(resource)
        } catch {
            // Never let a cleanup error mask the body's failure; surface it only when the body
            // succeeded (e.g. cooperative cancellation propagated from teardown).
            if thrown == nil { thrown = error }
        }
        if let thrown { throw thrown }
    }
}
