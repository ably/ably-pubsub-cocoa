import Foundation
import Testing
import Ably
import Ably.Private

/// Base class for UTS-derived unit tests.
///
/// UTS suites are Swift Testing suites that subclass this (`@Suite(.serialized) final class FooTests: UTSTestCase`).
/// Swift Testing creates a fresh instance per `@Test`, so each test gets its own clients/mocks and
/// `deinit` tears them down.
///
/// Provides the cocoa mappings of the UTS infra primitives:
/// - `installMock(_:)` — the spec's `install_mock`: registers the `MockWebSocketProvider` / `MockHTTPClient`
///   so the next client built by `makeRealtime()` / `makeRest()` picks it up. The mock is never
///   passed to the client constructor (a mistake per `uts/docs/writing-test-specs.md`).
/// - `awaitConnectionState` / `awaitChannelState` — the spec's `AWAIT_STATE`: proceed immediately
///   if the condition already holds, otherwise poll until it does or the timeout expires.
/// - `advanceTime(byMilliseconds:)` — fake-timer advancement (`ADVANCE_TIME`).
/// - protocol-message builders, and cleanup of clients and scheduled timers.
class UTSTestCase {

    /// Default `AWAIT_STATE` timeout. Generous: with a frozen `MockTimeProvider` the SDK settles in
    /// microseconds, so this only bites when a state genuinely never arrives (a real failure).
    static let defaultAwaitTimeout: TimeInterval = 2

    /// The deterministic clock, installed into clients only after `enableFakeTimers()` is called.
    var timeProvider: MockTimeProvider?

    private var installedWebSocketProvider: MockWebSocketProvider?
    private var installedMockHTTPClient: MockHTTPClient?
    private var clients: [ARTRealtime] = []

    // MARK: Enable fake timers

    /// UTS `enable_fake_timers()`. Clients built *after* this call use the deterministic
    /// `MockTimeProvider` (advanced via `advanceTime(byMilliseconds:)`); by default — and for clients
    /// built before this call — they use the real `ARTSystemTimeProvider`. Mirrors the spec, where
    /// most tests run on real timers and only those exercising timeouts/retries opt into fake ones.
    func enableFakeTimers() {
        timeProvider = MockTimeProvider()
    }

    // MARK: Install mock

    /// Registers `wsProvider` to be used by the next `makeRealtime()` call (UTS `install_mock`).
    func installMock(_ wsProvider: MockWebSocketProvider) {
        installedWebSocketProvider = wsProvider
    }

    /// Registers `mockHTTP` to be used by the next `makeRest()` call (UTS `install_mock`).
    func installMock(_ mockHTTP: MockHTTPClient) {
        installedMockHTTPClient = mockHTTP
    }

    // MARK: Client construction

    /// Builds an `ARTRealtime` wired to the currently installed `MockWebSocketProvider` and the
    /// shared `MockTimeProvider`. A provider must be installed first via `installMock(_:)`. Like the
    /// UTS specs, this leaves the SDK's `autoConnect` default (`true`) in place; tests that need to
    /// control connection timing set `options.autoConnect = false` in the `configure` closure.
    func makeRealtime(configure: (ARTClientOptions) -> Void = { _ in }, sourceLocation: SourceLocation = #_sourceLocation) -> ARTRealtime {
        guard let wsProvider = installedWebSocketProvider else {
            Issue.record("No MockWebSocketProvider installed — call installMock(_:) before makeRealtime()", sourceLocation: sourceLocation)
            fatalError("No MockWebSocketProvider installed")
        }

        // Seed a dummy key (ably-java's ClientOptionsBuilder does the same) so specs that don't
        // exercise auth need no explicit key; the configure block can override it.
        let options = ARTClientOptions(key: "appId.keyId:keySecret")
        options.useBinaryProtocol = false

        let suffix = UUID().uuidString
        options.internalDispatchQueue = DispatchQueue(label: "io.ably.uts.internal.\(suffix)")
        options.dispatchQueue = DispatchQueue(label: "io.ably.uts.callback.\(suffix)")

        if let timeProvider {
            options.testOptions.timeProvider = timeProvider
        }
        options.testOptions.transportFactory = MockWebSocketTransportFactory(wsProvider: wsProvider)
        options.testOptions.reachabilityClass = NoOpReachability.self
        // Realtime specs also use `install_mock(mock_http)` (auth callbacks, connection failures,
        // fallback hosts, …), so wire an installed MockHTTPClient into the client's REST layer too.
        if let installedMockHTTPClient {
            options.testOptions.httpExecutor = installedMockHTTPClient
            if let timeProvider {
                installedMockHTTPClient.useTimeProvider(timeProvider)
            }
        }

        configure(options)

        let client = ARTRealtime(options: options)
        clients.append(client)
        return client
    }

    /// Builds an `ARTRest` whose HTTP layer is the currently installed `MockHTTPClient` (so requests are
    /// intercepted, not sent over the network). A mock must be installed first via `installMock(_:)`.
    func makeRest(configure: (ARTClientOptions) -> Void = { _ in }, sourceLocation: SourceLocation = #_sourceLocation) -> ARTRest {
        guard let mockHTTP = installedMockHTTPClient else {
            Issue.record("No MockHTTPClient installed — call installMock(_:) before makeRest()", sourceLocation: sourceLocation)
            fatalError("No MockHTTPClient installed")
        }

        // Seed a dummy key (ably-java's ClientOptionsBuilder does the same) so specs that don't
        // exercise auth need no explicit key; the configure block can override it.
        let options = ARTClientOptions(key: "appId.keyId:keySecret")
        options.useBinaryProtocol = false

        let suffix = UUID().uuidString
        options.internalDispatchQueue = DispatchQueue(label: "io.ably.uts.internal.\(suffix)")
        options.dispatchQueue = DispatchQueue(label: "io.ably.uts.callback.\(suffix)")

        if let timeProvider {
            options.testOptions.timeProvider = timeProvider
            mockHTTP.useTimeProvider(timeProvider)
        }
        options.testOptions.httpExecutor = mockHTTP

        configure(options)

        let rest = ARTRest(options: options)
        return rest
    }

    // MARK: AWAIT_STATE

    /// Waits until `client.connection.state == expected` (UTS `AWAIT_STATE`).
    func awaitConnectionState(_ client: ARTRealtime,
                              _ expected: ARTRealtimeConnectionState,
                              timeout: TimeInterval = defaultAwaitTimeout,
                              sourceLocation: SourceLocation = #_sourceLocation) {
        poll("connection.state == \(ARTRealtimeConnectionStateToStr(expected))",
             timeout: timeout, sourceLocation: sourceLocation) {
            client.connection.state == expected
        }
    }

    /// Waits until `channel.state == expected` (UTS `AWAIT_STATE`).
    func awaitChannelState(_ channel: ARTRealtimeChannel,
                           _ expected: ARTRealtimeChannelState,
                           timeout: TimeInterval = defaultAwaitTimeout,
                           sourceLocation: SourceLocation = #_sourceLocation) {
        poll("channel '\(channel.name)'.state == \(ARTRealtimeChannelStateToStr(expected))",
             timeout: timeout, sourceLocation: sourceLocation) {
            channel.state == expected
        }
    }

    /// Generic `AWAIT_STATE`: proceed immediately if `condition` already holds, otherwise poll until
    /// it does or `timeout` elapses (then fail). Used for non-state conditions such as "a frame has
    /// been sent". The small sleep just avoids a hot busy-loop.
    @discardableResult
    func poll(_ description: String,
              timeout: TimeInterval = defaultAwaitTimeout,
              sourceLocation: SourceLocation = #_sourceLocation,
              until condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() >= deadline {
                Issue.record("Timed out after \(timeout)s awaiting: \(description)", sourceLocation: sourceLocation)
                return false
            }
            Thread.sleep(forTimeInterval: 0.0005)
        }
        return true
    }

    // MARK: Fake timers

    /// Advances the fake clock (UTS `ADVANCE_TIME`). Requires `enableFakeTimers()` to have been
    /// called — otherwise clients are on the real clock and there is nothing to advance.
    func advanceTime(byMilliseconds milliseconds: Double, sourceLocation: SourceLocation = #_sourceLocation) {
        guard let timeProvider else {
            Issue.record("advanceTime requires enableFakeTimers() before makeRealtime()", sourceLocation: sourceLocation)
            return
        }
        timeProvider.advanceTime(byMilliseconds: milliseconds)
    }

    /// Closes a client (UTS `CLOSE_CLIENT`).
    func closeClient(_ client: ARTRealtime) {
        client.close()
    }

    // MARK: Cleanup

    /// Per-test teardown. Swift Testing releases the suite instance after each `@Test`, so this runs
    /// once per test: it closes any clients and cancels surviving fake timers (the leak safety net).
    deinit {
        for client in clients {
            client.close()
        }
        timeProvider?.cancelAllScheduled()
    }
}
