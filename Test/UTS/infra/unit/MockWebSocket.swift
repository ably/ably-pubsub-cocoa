import Foundation
import Ably
import Ably.Private

/// The UTS `mock_ws` — the object test code interacts with. It outlives any single socket
/// (the SDK creates a new `MockWebSocket` for every connection attempt), holding the
/// `onConnectionAttempt` handler and the history of all connection attempts.
///
/// It is installed via `ARTClientOptions.testOptions.transportFactory` (the cocoa mapping of the
/// spec's `install_mock`). The SDK still builds a *real* `ARTWebSocketTransport`, so URL and
/// query-param construction (`recover`, `resume`, `format`, …) is exercised by production code;
/// only the underlying socket is faked, via the `ARTWebSocketFactory` seam.
///
/// `onConnectionAttempt` is the handler-based pattern from the spec: it receives the `MockWebSocket`
/// for each connection the SDK opens, and configures the simulated server's response
/// (`respondWithSuccess()` + `sendToClient(...)`).
final class MockWebSocketProvider: @unchecked Sendable {
    typealias ConnectionAttemptHandler = @Sendable (MockWebSocket) -> Void

    private let onConnectionAttempt: ConnectionAttemptHandler?
    private let lock = NSLock()
    private var latestConnection: MockWebSocket?

    /// The most recent connection (UTS `active_connection`). Set on the internal queue, read from
    /// the test thread, so guarded by a lock. Tests that need the full history of connection
    /// attempts capture them into a local array inside `onConnectionAttempt` (the spec's pattern).
    var activeConnection: MockWebSocket? {
        lock.lock(); defer { lock.unlock() }
        return latestConnection
    }

    init(onConnectionAttempt: ConnectionAttemptHandler? = nil) {
        self.onConnectionAttempt = onConnectionAttempt
    }

    fileprivate func register(_ socket: MockWebSocket) {
        lock.lock()
        latestConnection = socket
        lock.unlock()
    }

    fileprivate func fireConnectionAttempt(_ socket: MockWebSocket) {
        onConnectionAttempt?(socket)
    }
}

/// A single simulated WebSocket connection. Conforms to `ARTWebSocket` so the real
/// `ARTWebSocketTransport` can drive it, and exposes the UTS server-side API
/// (`respondWithSuccess`, `sendToClient`, `simulateDisconnect`, …) for tests.
final class MockWebSocket: NSObject, ARTWebSocket, @unchecked Sendable {

    // MARK: ARTWebSocket

    weak var delegate: ARTWebSocketDelegate?
    var delegateDispatchQueue: DispatchQueue?

    /// `ARTWebSocket.readyState`. Written on the transport's private queue and the delegate queue,
    /// read from the test thread, so guarded by the same `lock` as `sent` / `capturedClose`.
    var readyState: ARTWebSocketReadyState {
        lock.lock(); defer { lock.unlock() }
        return _readyState
    }
    private var _readyState: ARTWebSocketReadyState = .connecting
    private func setReadyState(_ newValue: ARTWebSocketReadyState) {
        lock.lock()
        _readyState = newValue
        lock.unlock()
    }

    // MARK: Inspection

    /// The full request the SDK built for this connection (real production URL building).
    let request: URLRequest
    /// Convenience accessor for the connection URL.
    var url: URL { request.url ?? URL(string: "wss://invalid")! }
    /// Query parameters parsed from the connection URL (UTS `url.query_params`).
    var queryParams: [String: String] {
        parseQueryParams(of: request.url)
    }

    /// Protocol messages the SDK has sent towards the server, decoded, in order
    /// (UTS client-to-server `ws_frame` events). Appended on the internal queue, read from the
    /// test thread, so guarded by a lock.
    var sentMessages: [ARTProtocolMessage] {
        lock.lock(); defer { lock.unlock() }
        return sent
    }
    private var sent: [ARTProtocolMessage] = []
    /// The `(code, reason)` of a client-initiated close (UTS `await_client_close`), or `nil` if the
    /// SDK hasn't closed this socket. Recorded inside `close(withCode:reason:)` because the real
    /// `ARTWebSocketTransport` nils its delegate *before* closing, so a delegate callback can't reach
    /// the test — the mock must capture it directly. Guarded by `lock` like `sent`.
    private var capturedClose: (code: Int, reason: String?)?
    private let lock = NSLock()

    /// The `(code, reason)` the SDK closed this socket with (UTS client-close observation), or `nil`
    /// if it hasn't. Read from the test thread; guarded by `lock`.
    var clientClose: (code: Int, reason: String?)? {
        lock.lock(); defer { lock.unlock() }
        return capturedClose
    }

    /// Blocks until the SDK has closed this socket, returning the `(code, reason)` it closed with, or
    /// `nil` if `timeout` elapses first (UTS `await_client_close`). Polls `clientClose` on the test
    /// thread — the same synchronous-poll style as `UTSTestCase`'s awaits and `sentMessages`
    /// inspection, which is fine because a frozen `MockTimeProvider` settles the SDK in microseconds.
    @discardableResult
    func awaitClientClose(timeout: TimeInterval = 1) -> (code: Int, reason: String?)? {
        let deadline = Date().addingTimeInterval(timeout)
        while clientClose == nil {
            if Date() >= deadline { return nil }
            Thread.sleep(forTimeInterval: 0.0005)
        }
        return clientClose
    }

    private let decoder: ARTEncoder

    init(request: URLRequest, decoder: ARTEncoder) {
        self.request = request
        self.decoder = decoder
        super.init()
    }

    func setDelegateDispatchQueue(_ queue: DispatchQueue) {
        delegateDispatchQueue = queue
    }

    func open() {
        // No-op: opening is driven by the test via `onConnectionAttempt` → `respondWithSuccess()`,
        // not by the real network. (The transport calls this on a private queue we don't control;
        // keeping it a no-op means all simulated server activity is delivered via the delegate queue.)
    }

    func close(withCode code: Int, reason: String?) {
        lock.lock()
        _readyState = .closed
        capturedClose = (code, reason)
        lock.unlock()
        // No delegate callback here: the transport has already nil'd its delegate before calling
        // close, so client-initiated close is observable only via `clientClose` / `awaitClientClose`.
    }

    func send(_ message: Any?) {
        guard let data = message as? Data else { return }
        guard let decoded = try? decoder.decodeProtocolMessage(data) else { return }
        lock.lock()
        sent.append(decoded)
        lock.unlock()
    }

    // MARK: UTS server-side API

    /// Accepts the connection at the transport level (UTS `respond_with_success()`).
    func respondWithSuccess() {
        setReadyState(.open)
        deliverToDelegate { [weak self] in
            guard let self else { return }
            self.delegate?.webSocketDidOpen?(self)
        }
    }

    /// Accepts the connection and immediately delivers `message` — usually `.connectedMessage`
    /// (UTS `respond_with_success(message)`, the convenience ably-java also offers).
    func respondWithSuccess(_ message: ProtocolMessage) {
        respondWithSuccess()
        sendToClient(message)
    }

    /// Delivers a protocol message to the client, leaving the connection open
    /// (UTS `send_to_client`).
    func sendToClient(_ message: ProtocolMessage) {
        deliverToDelegate { [weak self] in
            guard let self else { return }
            guard self.readyState == .open else { return }
            self.delegate?.webSocket?(self, didReceiveMessage: message.makeProtocolMessage())
        }
    }

    /// Delivers a protocol message and then closes the connection (UTS `send_to_client_and_close`).
    /// Used for connection-level `ERROR` (no channel) and `DISCONNECTED`.
    func sendToClientAndClose(_ message: ProtocolMessage) {
        deliverToDelegate { [weak self] in
            guard let self else { return }
            if self.readyState == .open {
                self.delegate?.webSocket?(self, didReceiveMessage: message.makeProtocolMessage())
            }
            self.setReadyState(.closed)
            self.delegate?.webSocket?(self, didCloseWithCode: WSCloseCode.normal, reason: "Normal Closure", wasClean: true)
        }
    }

    /// Refuses the connection at the network level (UTS `respond_with_refused()`); the SDK treats
    /// this as a retryable connection failure (`realtimeTransportRefused:`).
    func respondWithRefused() {
        deliverToDelegate { [weak self] in
            guard let self else { return }
            self.setReadyState(.closed)
            self.delegate?.webSocket?(self, didCloseWithCode: WSCloseCode.refuse, reason: "Connection refused", wasClean: false)
        }
    }

    /// Drops the connection without any server message (UTS `simulate_disconnect`).
    func simulateDisconnect() {
        deliverToDelegate { [weak self] in
            guard let self else { return }
            self.setReadyState(.closed)
            // GoingAway maps to `realtimeTransportDisconnected:` (an unexpected connectivity drop).
            self.delegate?.webSocket?(self, didCloseWithCode: WSCloseCode.goingAway, reason: "Going Away", wasClean: false)
        }
    }

    /// Delivers a delegate callback on the `delegateDispatchQueue` the transport set, per the
    /// `ARTWebSocket` contract (the real `ARTSRWebSocket` calls its delegate on this queue). It is
    /// always set before any server-side method runs: the transport sets it synchronously in
    /// `setupWebSocket`, before `onConnectionAttempt` (and any later test call) fires.
    private func deliverToDelegate(_ block: @escaping @Sendable () -> Void) {
        guard let queue = delegateDispatchQueue else {
            assertionFailure("MockWebSocket delegate callback before delegateDispatchQueue was set")
            return
        }
        queue.async(execute: block)
    }
}

/// WebSocket close codes interpreted by `ARTWebSocketTransport.webSocket:didCloseWithCode:…`.
private enum WSCloseCode {
    static let normal = 1000    // ARTWsCloseNormal  -> realtimeTransportClosed:
    static let goingAway = 1001 // ARTWsGoingAway    -> realtimeTransportDisconnected:
    static let refuse = 1003    // ARTWsRefuse       -> realtimeTransportRefused:
}

/// Creates `MockWebSocket`s and notifies the `MockWebSocketProvider` of each connection attempt.
final class MockWebSocketFactory: NSObject, WebSocketFactory {
    private let workQueue: DispatchQueue
    private let decoder: ARTEncoder
    private let wsProvider: MockWebSocketProvider

    init(workQueue: DispatchQueue, decoder: ARTEncoder, wsProvider: MockWebSocketProvider) {
        self.workQueue = workQueue
        self.decoder = decoder
        self.wsProvider = wsProvider
        super.init()
    }

    func createWebSocket(with request: URLRequest, logger: InternalLog?) -> ARTWebSocket {
        let webSocket = MockWebSocket(request: request, decoder: decoder)
        wsProvider.register(webSocket)
        // Fire `onConnectionAttempt` on the work queue. This block is enqueued during the transport's
        // `setupWebSocket` turn, so it runs *after* the transport has wired up `delegate` and
        // `delegateDispatchQueue` (both set synchronously right after this method returns).
        let wsProvider = self.wsProvider
        workQueue.async {
            wsProvider.fireConnectionAttempt(webSocket)
        }
        return webSocket
    }
}

/// A `RealtimeTransportFactory` that builds a real `ARTWebSocketTransport` backed by a
/// `MockWebSocketFactory`. Installed via `ARTClientOptions.testOptions.transportFactory`.
final class MockWebSocketTransportFactory: NSObject, RealtimeTransportFactory {
    private let wsProvider: MockWebSocketProvider

    init(wsProvider: MockWebSocketProvider) {
        self.wsProvider = wsProvider
        super.init()
    }

    func transport(withRest rest: ARTRestInternal, options: ARTClientOptions, resumeKey: String?, logger: InternalLog) -> ARTRealtimeTransport {
        let webSocketFactory = MockWebSocketFactory(workQueue: rest.queue, decoder: rest.defaultEncoder, wsProvider: wsProvider)
        return ARTWebSocketTransport(rest: rest, options: options, resumeKey: resumeKey, logger: logger, webSocketFactory: webSocketFactory)
    }
}
