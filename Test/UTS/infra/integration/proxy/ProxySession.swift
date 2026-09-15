// Proxy sessions talk to a locally spawned uts-proxy (see ProxyManager), which is macOS-only.
#if os(macOS)

import Foundation
import AblyPubSubDevice

// MARK: - Rule type + factory helpers

/// A proxy rule: a dictionary with at minimum `"match"` and `"action"` keys.
///
/// Use the factory helpers (`wsConnectRule`, `wsFrameToClientRule`, `wsFrameToServerRule`,
/// `httpRequestRule`) to construct rules without hard-coding dictionary literals everywhere.
///
/// Rules are evaluated in order; the first matching rule wins. Unmatched traffic passes through.
/// When `"times"` is set the rule auto-removes after that many firings.
typealias ProxyRule = [String: any Sendable]

/// Builds a rule that matches WebSocket connection attempts.
///
/// - Parameters:
///   - action: The action to take (e.g. `["type": "refuse_connection"]`).
///   - count: 1-based occurrence index; `2` matches only the 2nd connection attempt.
///   - queryContains: Match only if the WS URL query params contain these key/value pairs.
///     Use `"*"` as a wildcard value (matches any non-null value).
///   - times: Auto-remove the rule after this many firings.
func wsConnectRule(action: ProxyRule,
                   count: Int? = nil,
                   queryContains: [String: String]? = nil,
                   times: Int? = nil) -> ProxyRule {
    var match: ProxyRule = ["type": "ws_connect"]
    if let count { match["count"] = count }
    if let queryContains { match["queryContains"] = queryContains }
    var rule: ProxyRule = ["match": match, "action": action]
    if let times { rule["times"] = times }
    return rule
}

/// Builds a rule that matches WebSocket frames travelling **server → client**.
///
/// - Parameters:
///   - action: The action to take (e.g. `["type": "suppress"]`).
///   - messageAction: The Ably protocol message action number to match (see the action table in
///     the spec repo's `uts/docs/proxy.md`; e.g. `4` = CONNECTED, `11` = ATTACHED).
///   - channel: If set, additionally match only frames for this channel name.
///   - times: Auto-remove the rule after this many firings.
func wsFrameToClientRule(action: ProxyRule,
                         messageAction: Int? = nil,
                         channel: String? = nil,
                         times: Int? = nil) -> ProxyRule {
    var match: ProxyRule = ["type": "ws_frame_to_client"]
    // The proxy's MatchConfig.Action is a Go string (action name or numeric string).
    if let messageAction { match["action"] = String(messageAction) }
    if let channel { match["channel"] = channel }
    var rule: ProxyRule = ["match": match, "action": action]
    if let times { rule["times"] = times }
    return rule
}

/// Builds a rule that matches WebSocket frames travelling **client → server**.
///
/// - Parameters:
///   - action: The action to take.
///   - messageAction: The Ably protocol message action number to match
///     (e.g. `10` = ATTACH, `17` = AUTH).
///   - channel: If set, additionally match only frames for this channel name.
///   - times: Auto-remove the rule after this many firings.
func wsFrameToServerRule(action: ProxyRule,
                         messageAction: Int? = nil,
                         channel: String? = nil,
                         times: Int? = nil) -> ProxyRule {
    var match: ProxyRule = ["type": "ws_frame_to_server"]
    // The proxy's MatchConfig.Action is a Go string (action name or numeric string).
    if let messageAction { match["action"] = String(messageAction) }
    if let channel { match["channel"] = channel }
    var rule: ProxyRule = ["match": match, "action": action]
    if let times { rule["times"] = times }
    return rule
}

/// Builds a rule that matches HTTP requests passing through the proxy.
///
/// - Parameters:
///   - action: The action to take (e.g. `["type": "http_respond", "status": 401]`).
///   - pathContains: Match only requests whose path contains this substring.
///   - method: Match only requests with this HTTP method (e.g. `"GET"`, `"POST"`).
///   - times: Auto-remove the rule after this many firings.
func httpRequestRule(action: ProxyRule,
                     pathContains: String? = nil,
                     method: String? = nil,
                     times: Int? = nil) -> ProxyRule {
    var match: ProxyRule = ["type": "http_request"]
    if let pathContains { match["pathContains"] = pathContains }
    if let method { match["method"] = method }
    var rule: ProxyRule = ["match": match, "action": action]
    if let times { rule["times"] = times }
    return rule
}

// MARK: - Event

/// A single event recorded in a `ProxySession`'s log, returned by `ProxySession.getLog()`.
///
/// Mirrors the proxy's `Event` struct. Fields that are absent from a given event are `nil`
/// (Go's `omitempty` tags), so every property is optional. A thin typed wrapper over the raw JSON
/// object so the arbitrary protocol `message` stays introspectable
/// (`event.message?["action"] as? Int`).
struct ProxyEvent: @unchecked Sendable {
    /// The raw event JSON.
    let raw: [String: Any]

    /// RFC3339 timestamp, e.g. `2026-06-22T21:43:56.747996Z`.
    var timestamp: String? { raw["timestamp"] as? String }
    /// `ws_connect`, `ws_frame`, `ws_disconnect`, `http_request`, `http_response`, or `action`.
    var type: String? { raw["type"] as? String }
    /// `client_to_server` or `server_to_client`.
    var direction: String? { raw["direction"] as? String }
    var url: String? { raw["url"] as? String }
    var queryParams: [String: String]? { raw["queryParams"] as? [String: String] }
    /// The protocol message carried by a `ws_frame` event. Introspect via
    /// `message?["action"] as? Int` etc.
    var message: [String: Any]? { raw["message"] as? [String: Any] }
    var method: String? { raw["method"] as? String }
    var path: String? { raw["path"] as? String }
    var status: Int? { raw["status"] as? Int }
    /// `client`, `server`, or `proxy`.
    var initiator: String? { raw["initiator"] as? String }
    var closeCode: Int? { raw["closeCode"] as? Int }
    var ruleMatched: String? { raw["ruleMatched"] as? String }
    var headers: [String: String]? { raw["headers"] as? [String: String] }
}

// MARK: - ProxySession

/// A single proxy session wrapping the `uts-proxy` control REST API.
///
/// Each test should create one session, run its scenario, and always `close()` it in teardown:
///
/// ```swift
/// let session = try await ProxySession.create(rules: [
///     wsConnectRule(action: ["type": "refuse_connection"], count: 2),
/// ])
/// // The proxy serves plain ws (`tls = false`) and basic (key) auth is TLS-only (RSA1),
/// // so authenticate with a TokenRequest signed locally by a TLS "token signer" client:
/// let options = ARTClientOptions()
/// options.authCallback = { params, callback in
///     tokenSigner.auth.createTokenRequest(params, options: nil) { callback($0, $1) }
/// }
/// options.connectThroughProxy(session)
/// let client = ARTRealtime(options: options)
/// // … test scenario …
/// await session.close()   // always — `defer` can't await, so close at the end of every path
/// ```
///
/// > Note: `getLog()` returns typed `ProxyEvent`s; the raw protocol message is exposed as
/// > `ProxyEvent.message` — introspect it via `message?["action"]`.
///
/// Mirrors ably-java's `infra/integration/proxy/ProxySession.kt`.
final class ProxySession: Sendable {

    /// Opaque session identifier assigned by the proxy.
    let sessionId: String
    /// The port on `localhost` that the proxy is listening on for this session.
    let proxyPort: Int
    /// Always `"localhost"`. Exposed for use by `connectThroughProxy`.
    let proxyHost = "localhost"

    // Finite timeouts so a stalled local proxy/control endpoint fails fast instead of hanging teardown.
    private static let session = makeURLSession(requestTimeout: 15)

    private init(sessionId: String, proxyPort: Int) {
        self.sessionId = sessionId
        self.proxyPort = proxyPort
    }

    /// Creates a new proxy session pointing at the Ably sandbox.
    ///
    /// - Parameters:
    ///   - rules: Initial rule set applied to all traffic through this session.
    ///   - port: Specific port to listen on; `0` (default) lets the proxy choose.
    ///   - timeoutMs: Session idle-timeout in ms; `nil` uses the proxy default (30 000 ms).
    ///   - realtimeHost: Upstream Ably realtime host (defaults to sandbox).
    ///   - restHost: Upstream Ably REST host (defaults to sandbox).
    static func create(rules: [ProxyRule] = [],
                       port: Int = 0,
                       timeoutMs: Int? = nil,
                       realtimeHost: String = SandboxApp.sandboxHost,
                       restHost: String = SandboxApp.sandboxHost) async throws -> ProxySession {
        var body: [String: Any] = [
            "target": ["realtimeHost": realtimeHost, "restHost": restHost],
            "rules": rules,
        ]
        if port != 0 { body["port"] = port }
        if let timeoutMs { body["timeoutMs"] = timeoutMs }

        let data = try await controlPost("/sessions", body: body)
        guard let response = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sessionId = response["sessionId"] as? String,
              let proxy = response["proxy"] as? [String: Any],
              let proxyPort = proxy["port"] as? Int else {
            throw HTTPError("Proxy POST /sessions returned an unexpected body")
        }
        return ProxySession(sessionId: sessionId, proxyPort: proxyPort)
    }

    /// Appends or prepends `rules` to this session's active rule list.
    ///
    /// - Parameters:
    ///   - rules: Rules to add.
    ///   - position: `"append"` (default) or `"prepend"`.
    func addRules(_ rules: [ProxyRule], position: String = "append") async throws {
        _ = try await Self.controlPost("/sessions/\(sessionId)/rules",
                                       body: ["rules": rules, "position": position])
    }

    /// Triggers an imperative action on the current active WebSocket connection.
    ///
    /// Common actions:
    /// ```swift
    /// try await session.triggerAction(["type": "disconnect"])
    /// try await session.triggerAction(["type": "close", "closeCode": 1000])
    /// try await session.triggerAction(["type": "inject_to_client", "message": ["action": 6]])
    /// ```
    func triggerAction(_ action: ProxyRule) async throws {
        _ = try await Self.controlPost("/sessions/\(sessionId)/actions", body: action)
    }

    /// Returns the ordered event log recorded by the proxy for this session as typed `ProxyEvent`s.
    ///
    /// Common `type` values: `ws_connect`, `ws_frame`, `ws_disconnect`, `http_request`,
    /// `http_response`, `action`. The raw protocol message is available via `ProxyEvent.message`.
    func getLog() async throws -> [ProxyEvent] {
        let data = try await Self.controlGet("/sessions/\(sessionId)/log")
        guard let body = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HTTPError("Proxy GET /log returned an unexpected body")
        }
        let events = body["events"] as? [[String: Any]] ?? []
        return events.map(ProxyEvent.init(raw:))
    }

    /// Closes this session and stops its proxy listener.
    /// Should always be called in teardown after a test completes. Cleanup errors are ignored.
    func close() async {
        await Self.controlDelete("/sessions/\(sessionId)")
    }

    // MARK: - Control-plane HTTP helpers

    private static func controlURL(_ path: String) -> URL {
        URL(string: "http://localhost:\(ProxyManager.controlPort)\(path)")!
    }

    private static func controlPost(_ path: String, body: Any) async throws -> Data {
        let request = try jsonRequest("POST", controlURL(path), body: body)
        let (data, status) = try await httpRequest(request, session: session)
        guard (200..<300).contains(status) else {
            throw HTTPError("Proxy control API returned \(status) for POST \(path): \(String(decoding: data, as: UTF8.self))")
        }
        return data
    }

    private static func controlGet(_ path: String) async throws -> Data {
        let (data, status) = try await httpRequest(URLRequest(url: controlURL(path)), session: session)
        guard (200..<300).contains(status) else {
            throw HTTPError("Proxy control API returned \(status) for GET \(path): \(String(decoding: data, as: UTF8.self))")
        }
        return data
    }

    private static func controlDelete(_ path: String) async {
        var request = URLRequest(url: controlURL(path))
        request.httpMethod = "DELETE"
        // Teardown should never throw, but a failed delete leaks a session — make it visible.
        do {
            let (_, status) = try await httpRequest(request, session: session)
            if !(200..<300).contains(status) {
                FileHandle.standardError.write(Data("Proxy control API returned \(status) for DELETE \(path)\n".utf8))
            }
        } catch {
            FileHandle.standardError.write(Data("Proxy DELETE \(path) failed: \(error)\n".utf8))
        }
    }
}

// MARK: - Client wiring

extension ARTClientOptions {
    /// Routes a client through the given proxy `session`.
    ///
    /// Sets `realtimeHost` and `restHost` to the proxy host, `port` to the session's assigned
    /// port, `tls = false` (the proxy serves plain HTTP/WS; TLS is only used upstream to the
    /// sandbox), and `useBinaryProtocol = false` (the proxy can only inspect text frames — the
    /// UTS proxy specs require JSON).
    ///
    /// Setting explicit hosts disables fallback hosts automatically (REC2c2), so no
    /// `fallbackHosts` juggling is needed.
    func connectThroughProxy(_ session: ProxySession) {
        realtimeHost = session.proxyHost
        restHost = session.proxyHost
        port = session.proxyPort
        tls = false
        useBinaryProtocol = false
    }
}

#endif
