import Foundation
import AblyPubSubDevice
import AblyPubSubDevice.Private

/// The UTS `MockHttpClient` — a fake `ARTHTTPExecuting` that intercepts the SDK's outgoing HTTP
/// requests so tests can observe them and inject responses, with no real network. Installed via
/// `rest.internal.httpExecutor` (the cocoa mapping of the spec's `install_mock`).
///
/// Mirrors `uts/rest/unit/helpers/mock_http.md`. The cocoa HTTP seam is **request-level**
/// (`executeRequest:completion:`), so each `execute(_:)` is a standalone attempt: `onConnectionAttempt`
/// is consulted first (its `respond_with_refused`/`timeout`/`dns_error` fail the request with the
/// corresponding `NSError`), and unless the connection failed, the request is delivered to `onRequest`.
final class MockHTTPClient: NSObject, ARTHTTPExecuting, Sendable {
    /// Returns the error the connection should fail with, or `nil` if it succeeds.
    typealias ConnectionHandler = @Sendable (PendingHTTPConnection) -> NSError?
    typealias RequestHandler = @Sendable (PendingHTTPRequest) -> Void

    private let onConnectionAttempt: ConnectionHandler?
    private let onRequest: RequestHandler?

    init(onConnectionAttempt: ConnectionHandler? = nil, onRequest: RequestHandler? = nil) {
        self.onConnectionAttempt = onConnectionAttempt
        self.onRequest = onRequest
        super.init()
    }

    // MARK: ARTHTTPExecuting

    func execute(_ request: URLRequest, completion callback: ((HTTPURLResponse?, Data?, Error?) -> Void)? = nil) -> (Cancellable & NSObjectProtocol)? {
        // Connection phase — fail the request if the connection handler rejects it.
        if let connectionError = onConnectionAttempt?(PendingHTTPConnection(request: request)) {
            callback?(nil, nil, connectionError)
            return NoopCancellable()
        }

        // Request phase — deliver to onRequest.
        guard let onRequest else {
            // A request reached the mock with no handler installed: a test set-up error.
            fatalError("MockHTTPClient received a request but no onRequest handler is installed")
        }
        onRequest(PendingHTTPRequest(request: request, completion: callback))
        return NoopCancellable()
    }
}

/// A connection attempt (UTS `PendingConnection`). The cocoa HTTP seam doesn't expose real TCP, so
/// this is derived from the request's URL; the `onConnectionAttempt` handler inspects it and returns
/// the resulting error (or `nil`). Immutable — the result is the handler's return value.
struct PendingHTTPConnection {
    let host: String
    let port: Int
    let tls: Bool
    /// Query parameters parsed from the request URL (UTS `url.query_params`).
    let queryParams: [String: String]

    init(request: URLRequest) {
        guard let url = request.url, let host = url.host else {
            // The SDK should never make a request without a URL host; if it does, the test set-up
            // (or the SDK) is broken, so fail fast rather than fabricate a connection.
            fatalError("MockHTTPClient received a connection attempt for a request without a URL host")
        }
        self.tls = (url.scheme?.lowercased() == "https")
        self.host = host
        self.port = url.port ?? (tls ? 443 : 80)
        self.queryParams = parseQueryParams(of: url)
    }

    /// Connection succeeds; requests proceed (UTS `respond_with_success`).
    func respondWithSuccess() -> NSError? { nil }
    /// TCP connection refused (UTS `respond_with_refused`).
    func respondWithRefused() -> NSError? { Self.urlError(.cannotConnectToHost) }
    /// Connection times out (UTS `respond_with_timeout`).
    func respondWithTimeout() -> NSError? { Self.urlError(.timedOut) }
    /// DNS resolution fails (UTS `respond_with_dns_error`).
    func respondWithDNSError() -> NSError? { Self.urlError(.cannotFindHost) }

    private static func urlError(_ code: URLError.Code) -> NSError {
        NSError(domain: NSURLErrorDomain, code: code.rawValue, userInfo: nil)
    }
}

/// A request the SDK made (UTS `PendingRequest`): inspectable, and respondable by the test. Holds the
/// completion callback rather than any mutable state.
struct PendingHTTPRequest {
    let request: URLRequest
    private let completion: ((HTTPURLResponse?, Data?, Error?) -> Void)?

    init(request: URLRequest, completion: ((HTTPURLResponse?, Data?, Error?) -> Void)?) {
        self.request = request
        self.completion = completion
    }

    var url: URL {
        guard let url = request.url else {
            fatalError("MockHTTPClient received a request without a URL")
        }
        return url
    }
    var method: String { request.httpMethod ?? "GET" }
    var headers: [String: String] { request.allHTTPHeaderFields ?? [:] }
    var body: Data? { request.httpBody }

    /// Query parameters parsed from the request URL (UTS `url.query_params`).
    var queryParams: [String: String] {
        parseQueryParams(of: request.url)
    }

    /// Sends an HTTP response (UTS `respond_with`). `body` may be `Data`, `String`, or a
    /// JSON-serialisable value (dictionary/array); defaults to a JSON content type.
    func respondWith(status: Int, body: Any, headers: [String: String] = [:]) {
        var headerFields = headers
        if headerFields["Content-Type"] == nil {
            headerFields["Content-Type"] = "application/json"
        }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headerFields)
        completion?(response, Self.data(from: body), nil)
    }

    /// Sends an HTTP response after `delay` seconds (UTS `respond_with_delay` — for slow-server
    /// specs). The response is built up front; only the delivery is deferred.
    func respondWithDelay(_ delay: TimeInterval, status: Int, body: Any) {
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])
        let data = Self.data(from: body)
        let completion = DelayedCompletionBox(completion: self.completion)
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
            completion.completion?(response, data, nil)
        }
    }

    /// Simulates a request timeout after the connection was established (UTS `respond_with_timeout`).
    func respondWithTimeout() {
        completion?(nil, nil, NSError(domain: NSURLErrorDomain, code: URLError.timedOut.rawValue, userInfo: nil))
    }

    private static func data(from body: Any) -> Data {
        switch body {
        case let data as Data: return data
        case let string as String: return Data(string.utf8)
        default: return (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        }
    }
}

/// Carries a completion handler across the `asyncAfter` hop for `respondWithDelay`. The handler is
/// only ever invoked once, from that single deferred block, so the unchecked-Sendable wrapper is safe.
private final class DelayedCompletionBox: @unchecked Sendable {
    let completion: ((HTTPURLResponse?, Data?, Error?) -> Void)?
    init(completion: ((HTTPURLResponse?, Data?, Error?) -> Void)?) { self.completion = completion }
}

/// No-op cancellable returned by `MockHTTPClient.execute` (the response is delivered synchronously, so
/// there's nothing to cancel).
private final class NoopCancellable: NSObject, Cancellable {
    func cancel() {}
}
