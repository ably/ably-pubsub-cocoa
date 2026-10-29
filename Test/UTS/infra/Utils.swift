import Foundation
import Testing
import AblyPubSubDevice
import AblyPubSubDevice.Private

/// Shared helpers used by every tier (the cocoa counterpart of ably-java's `infra/Utils.kt`).
///
/// The unit tier's state waits live on `UTSTestCase` (`awaitConnectionState` / `awaitChannelState` /
/// `poll`) — they poll synchronously, which is fine when a frozen `MockTimeProvider` settles the SDK
/// in microseconds. The integration tier waits on *real* network and proxy state, where blocking the
/// test thread for seconds is wasteful, so it uses the async helpers below (the UTS specs'
/// anti-flake rule: no fixed blind waits — poll on observable state, with a short interval
/// between checks).

/// The integration tier's `poll_until` (the spec's `RETURN result IF … ELSE null` contract, the
/// same loop shape as ably-java's `Utils.pollUntil`): polls `condition` every `interval` seconds
/// until it yields a value and returns that settled value, or records a test failure once
/// `timeout` (wall-clock seconds) elapses. Callers assert on the returned page rather than
/// refetching — a refetch can hit a less-replicated frontend and return fewer items than the poll
/// just observed, reintroducing the eventual-consistency race the poll just absorbed.
///
/// `condition` is `rethrows`: if it throws, the poll aborts immediately and the error propagates
/// to the caller (failing the test) — no timeout `Issue` is recorded. This matches the spec's
/// plain `poll_until`: a thrown error is a genuine failure, whereas a not-ready state is
/// signalled by returning nil (e.g. an under-replicated item count), not by throwing.
@discardableResult
func pollUntil<T>(_ description: String,
                  timeout: TimeInterval = 15,
                  interval: TimeInterval = 0.1,
                  sourceLocation: SourceLocation = #_sourceLocation,
                  _ condition: () async throws -> T?) async rethrows -> T? {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline, !Task.isCancelled {
        if let value = try await condition() {
            return value
        }
        try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
    }
    Issue.record(Task.isCancelled ? "Cancelled while polling for: \(description)"
                                  : "Timed out after \(timeout)s polling for: \(description)",
                 sourceLocation: sourceLocation)
    return nil
}

/// Bare-condition form of `pollUntil` (the spec's `poll_until(condition: …)` used as a statement,
/// for latch/monotonic conditions with no page to keep).
@discardableResult
func pollUntil(_ description: String,
               timeout: TimeInterval = 15,
               interval: TimeInterval = 0.1,
               sourceLocation: SourceLocation = #_sourceLocation,
               _ condition: () async throws -> Bool) async rethrows -> Bool {
    try await pollUntil(description, timeout: timeout, interval: interval, sourceLocation: sourceLocation) {
        try await condition() ? true : nil
    } != nil
}

/// Suspends until `client.connection.state == expected` (the integration tier's `AWAIT_STATE`,
/// against a real backend — the async counterpart of `UTSTestCase.awaitConnectionState`).
///
/// A state-change listener latches the transition (registered before the current-state check), so a
/// transient state — e.g. `.disconnected` under the RTN15a immediate reconnect — cannot be missed.
/// Entering FAILED while awaiting another state short-circuits with the failure reason (FAILED is
/// terminal, so the expected state can no longer arrive; waiting out the timeout just hides the
/// cause).
@discardableResult
func awaitState(_ client: PubSubClient,
                _ expected: RealtimeConnectionState,
                timeout: TimeInterval = 15,
                sourceLocation: SourceLocation = #_sourceLocation) async -> Bool {
    let reached = Captured<Bool>()
    let failedReason = Captured<String>()
    let listener = client.connection.on { change in
        if change.current == expected {
            reached.append(true)
        } else if change.current == .failed {
            failedReason.append(change.reason?.message ?? "no reason")
        }
    }
    defer { client.connection.off(listener) }
    if client.connection.state == expected {
        reached.append(true)
    } else if client.connection.state == .failed {
        failedReason.append(client.connection.errorReason?.message ?? "no reason")
    }
    await pollUntil("connection.state == \(realtimeConnectionStateToStr(expected))",
                    timeout: timeout, sourceLocation: sourceLocation) {
        reached.count > 0 || failedReason.count > 0
    }
    if reached.count > 0 {
        return true
    }
    if let reason = failedReason.first {
        Issue.record("connection entered FAILED while awaiting \(realtimeConnectionStateToStr(expected)): \(reason)",
                     sourceLocation: sourceLocation)
    }
    return false
}

/// Suspends until `channel.state == expected` (the integration tier's `AWAIT_STATE` for channels),
/// latching the transition and short-circuiting on FAILED like `awaitState` above.
@discardableResult
func awaitChannelState(_ channel: RealtimeChannel,
                       _ expected: RealtimeChannelState,
                       timeout: TimeInterval = 15,
                       sourceLocation: SourceLocation = #_sourceLocation) async -> Bool {
    let reached = Captured<Bool>()
    let failedReason = Captured<String>()
    let listener = channel.on { change in
        if change.current == expected {
            reached.append(true)
        } else if change.current == .failed {
            failedReason.append(change.reason?.message ?? "no reason")
        }
    }
    defer { channel.off(listener) }
    if channel.state == expected {
        reached.append(true)
    } else if channel.state == .failed {
        failedReason.append(channel.errorReason?.message ?? "no reason")
    }
    await pollUntil("channel '\(channel.name)'.state == \(realtimeChannelStateToStr(expected))",
                    timeout: timeout, sourceLocation: sourceLocation) {
        reached.count > 0 || failedReason.count > 0
    }
    if reached.count > 0 {
        return true
    }
    if let reason = failedReason.first {
        Issue.record("channel '\(channel.name)' entered FAILED while awaiting \(realtimeChannelStateToStr(expected)): \(reason)",
                     sourceLocation: sourceLocation)
    }
    return false
}

/// Query parameters parsed from a URL (UTS `url.query_params`) — the counterpart of ably-java's
/// `parseQueryString`. Shared by the WS and HTTP mocks so the parsing lives in one place.
func parseQueryParams(of url: URL?) -> [String: String] {
    guard let url,
          let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
          let items = components.queryItems else { return [:] }
    var result: [String: String] = [:]
    for item in items where item.value != nil {
        result[item.name] = item.value
    }
    return result
}

// MARK: - HTTP support for integration infra

/// Error thrown by `httpRequest` when the response is not an HTTP response, or by callers on an
/// unexpected status code.
struct HTTPError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// Minimal async wrapper over `URLSession.dataTask` used by the integration infrastructure
/// (`SandboxApp`, `ProxyManager`, `ProxySession`). A continuation-based helper rather than
/// `URLSession.data(for:)` so the target's deployment floor stays where the rest of the suite is.
/// Returns the body and status code; callers decide which statuses are acceptable.
func httpRequest(_ request: URLRequest, session: URLSession) async throws -> (data: Data, status: Int) {
    try await withCheckedThrowingContinuation { continuation in
        session.dataTask(with: request) { data, response, error in
            if let error {
                continuation.resume(throwing: error)
                return
            }
            guard let http = response as? HTTPURLResponse else {
                continuation.resume(throwing: HTTPError("Non-HTTP response for \(request.url?.absoluteString ?? "?")"))
                return
            }
            continuation.resume(returning: (data ?? Data(), http.statusCode))
        }.resume()
    }
}

/// Builds a JSON request. `body` (when present) is serialised with `JSONSerialization`.
func jsonRequest(_ method: String, _ url: URL, body: Any? = nil) throws -> URLRequest {
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if let body {
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
    }
    return request
}

/// A `URLSession` with finite timeouts so a stalled endpoint fails fast instead of hanging a suite.
func makeURLSession(requestTimeout: TimeInterval) -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = requestTimeout
    return URLSession(configuration: configuration)
}
