@preconcurrency import AblyPubSubDevice.Private

class TestProxyTransportFactory: RealtimeTransportFactory {
    // This value will be used by all TestProxyTransportFactory instances created by this factory (including those created before this property is updated).
    var fakeNetworkResponse: FakeNetworkResponse?

    // This value will be used by all TestProxyTransportFactory instances created by this factory (including those created before this property is updated).
    var networkConnectEvent: ((ARTRealtimeTransport, URL) -> Void)?

    var transportCreatedEvent: ((ARTRealtimeTransport) -> Void)?

    func transport(withRest rest: ARTHttpClientInternal, options: ARTClientOptions, resumeKey: String?, logger: InternalLog) -> ARTRealtimeTransport {
        let webSocketFactory = WebSocketFactory()

        let testProxyTransport = TestProxyTransport(
            factory: self,
            rest: rest,
            options: options,
            resumeKey: resumeKey,
            logger: logger,
            webSocketFactory: webSocketFactory,
        )

        webSocketFactory.testProxyTransport = testProxyTransport

        transportCreatedEvent?(testProxyTransport)

        return testProxyTransport
    }

    private class WebSocketFactory: AblyPubSubDevice.WebSocketFactory {
        weak var testProxyTransport: TestProxyTransport?

        func createWebSocket(with request: URLRequest, logger: InternalLog?) -> ARTWebSocket {
            let webSocket = WebSocket(urlRequest: request, logger: logger)
            webSocket.testProxyTransport = testProxyTransport

            return webSocket
        }
    }

    private class WebSocket: ARTSRWebSocket {
        weak var testProxyTransport: TestProxyTransport?

        override func open() {
            guard let testProxyTransport else {
                preconditionFailure("Tried to fetch testProxyTransport but it's already been deallocated")
            }
            if !testProxyTransport.handleWebSocketOpen() {
                super.open()
            }
        }
    }
}

/// Records each message for test purpose.
class TestProxyTransport: ARTWebSocketTransport, @unchecked Sendable {
    /// The factory that created this TestProxyTransport instance.
    private weak var _factory: TestProxyTransportFactory?
    private var factory: TestProxyTransportFactory {
        guard let _factory else {
            preconditionFailure("Tried to fetch factory but it's already been deallocated")
        }
        return _factory
    }

    init(factory: TestProxyTransportFactory, rest: ARTHttpClientInternal, options: ARTClientOptions, resumeKey: String?, logger: InternalLog, webSocketFactory: WebSocketFactory) {
        _factory = factory
        super.init(rest: rest, options: options, resumeKey: resumeKey, logger: logger, webSocketFactory: webSocketFactory)
    }

    fileprivate(set) var lastUrl: URL?

    private var _protocolMessagesReceived: [ARTProtocolMessage] = []
    var protocolMessagesReceived: [ARTProtocolMessage] {
        var result: [ARTProtocolMessage] = []
        queue.sync {
            result = self._protocolMessagesReceived
        }
        return result
    }

    private var _protocolMessagesSent: [ARTProtocolMessage] = []
    var protocolMessagesSent: [ARTProtocolMessage] {
        var result: [ARTProtocolMessage] = []
        queue.sync {
            result = self._protocolMessagesSent
        }
        return result
    }

    private var _protocolMessagesSentIgnored: [ARTProtocolMessage] = []
    var protocolMessagesSentIgnored: [ARTProtocolMessage] {
        var result: [ARTProtocolMessage] = []
        queue.sync {
            result = self._protocolMessagesSentIgnored
        }
        return result
    }

    fileprivate(set) var rawDataSent = [Data]()
    fileprivate(set) var rawDataReceived = [Data]()

    private var replacingAcksWithNacks: ARTErrorInfo?

    var ignoreWebSocket = false
    var ignoreSends = false
    var actionsIgnored = [ARTProtocolMessageAction]()

    var queue: DispatchQueue {
        guard let delegateDispatchQueue = websocket?.delegateDispatchQueue else {
            preconditionFailure("I don't know what queue to use in this case (in ably-cocoa they used AblyTests.queue); cross this bridge if we come to it")
        }
        return delegateDispatchQueue
    }

    private var callbackBeforeProcessingIncomingMessage: ((ARTProtocolMessage) -> Void)?
    private var callbackAfterProcessingIncomingMessage: ((ARTProtocolMessage) -> Void)?
    private var callbackBeforeProcessingOutgoingMessage: ((ARTProtocolMessage) -> Void)?
    private var callbackBeforeIncomingMessageModifier: ((ARTProtocolMessage) -> ARTProtocolMessage?)?
    private var callbackAfterIncomingMessageModifier: ((ARTProtocolMessage) -> ARTProtocolMessage?)?

    // Represents a request to replace the implementation of a method.
    private final class Hook: Sendable {
        private let implementation: @Sendable () -> Void

        init(implementation: @escaping @Sendable () -> Void) {
            self.implementation = implementation
        }

        func performImplementation() {
            implementation()
        }
    }

    /// The active request, if any, to replace the implementation of the ARTWebSocket#open method for all WebSocket objects created by this transport. Access must be synchronised using webSocketOpenHookSemaphore.
    private var webSocketOpenHook: Hook?
    /// Used for synchronising access to webSocketOpenHook.
    private let webSocketOpenHookSempahore = DispatchSemaphore(value: 1)

    func setListenerBeforeProcessingIncomingMessage(_ callback: ((ARTProtocolMessage) -> Void)?) {
        queue.sync {
            self.callbackBeforeProcessingIncomingMessage = callback
        }
    }

    func setListenerAfterProcessingIncomingMessage(_ callback: ((ARTProtocolMessage) -> Void)?) {
        queue.sync {
            self.callbackAfterProcessingIncomingMessage = callback
        }
    }

    func setListenerBeforeProcessingOutgoingMessage(_ callback: ((ARTProtocolMessage) -> Void)?) {
        queue.sync {
            self.callbackBeforeProcessingOutgoingMessage = callback
        }
    }

    /// The modifier will be called on the internal queue.
    ///
    /// If `callback` returns nil, the message will be ignored.
    func setBeforeIncomingMessageModifier(_ callback: ((ARTProtocolMessage) -> ARTProtocolMessage?)?) {
        callbackBeforeIncomingMessageModifier = callback
    }

    /// The modifier will be called on the internal queue.
    ///
    /// If `callback` returns nil, the message will be ignored.
    func setAfterIncomingMessageModifier(_ callback: ((ARTProtocolMessage) -> ARTProtocolMessage?)?) {
        callbackAfterIncomingMessageModifier = callback
    }

    func enableReplaceAcksWithNacks(with errorInfo: ARTErrorInfo) {
        queue.sync {
            self.replacingAcksWithNacks = errorInfo
        }
    }

    func disableReplaceAcksWithNacks() {
        queue.sync {
            self.replacingAcksWithNacks = nil
        }
    }

    func emulateTokenRevokationBeforeConnected() {
        setBeforeIncomingMessageModifier { protocolMessage in
            if protocolMessage.action == .connected {
                protocolMessage.action = .disconnected
                protocolMessage.error = .create(withCode: Int(ARTErrorCode.tokenRevoked.rawValue), status: 401, message: "Test token revokation")
            }
            return protocolMessage
        }
    }

    // MARK: ARTWebSocket

    override func connect(withKey key: String) {
        if let fakeResponse = factory.fakeNetworkResponse {
            setupFakeNetworkResponse(fakeResponse)
        }
        super.connect(withKey: key)
        performNetworkConnectEvent()
    }

    override func connect(withToken token: String) {
        if let fakeResponse = factory.fakeNetworkResponse {
            setupFakeNetworkResponse(fakeResponse)
        }
        super.connect(withToken: token)
        performNetworkConnectEvent()
    }

    private func addWebSocketOpenHook(withImplementation implementation: @Sendable @escaping () -> Void) -> Hook {
        webSocketOpenHookSempahore.wait()
        let hook = Hook(implementation: implementation)
        webSocketOpenHook = hook
        webSocketOpenHookSempahore.signal()
        return hook
    }

    private func removeWebSocketOpenHook(_ hook: Hook) {
        webSocketOpenHookSempahore.wait()
        if webSocketOpenHook === hook {
            webSocketOpenHook = nil
        }
        webSocketOpenHookSempahore.signal()
    }

    /// If this transport has been configured with a replacement implementation of ARTWebSocket#open, then this performs that implementation and returns `true`. Else, returns `false`.
    func handleWebSocketOpen() -> Bool {
        let hook: Hook?
        webSocketOpenHookSempahore.wait()
        hook = webSocketOpenHook
        webSocketOpenHookSempahore.signal()

        if let hook {
            hook.performImplementation()
            return true
        } else {
            return false
        }
    }

    private func setupFakeNetworkResponse(_ networkResponse: FakeNetworkResponse) {
        nonisolated(unsafe) var hook: Hook?
        hook = addWebSocketOpenHook {
            if self.factory.fakeNetworkResponse == nil {
                return
            }

            func performFakeConnectionError(_ secondsForDelay: TimeInterval, error: ARTRealtimeTransportError) {
                self.queue.asyncAfter(deadline: .now() + secondsForDelay) {
                    self.delegate?.realtimeTransportFailed(self, withError: error)
                    if let hook {
                        self.removeWebSocketOpenHook(hook)
                    }
                }
            }

            guard let url = self.lastUrl else {
                fatalError("MockNetworkResponse: lastUrl should not be nil")
            }

            switch networkResponse {
            case .noInternet,
                 .hostUnreachable,
                 .hostInternalError,
                 .host400BadRequest,
                 .arbitraryError:
                performFakeConnectionError(0.1, error: networkResponse.transportError(for: url))
            case let .requestTimeout(timeout):
                performFakeConnectionError(0.1 + timeout, error: networkResponse.transportError(for: url))
            }
        }
    }

    private func performNetworkConnectEvent() {
        guard let networkConnectEventHandler = factory.networkConnectEvent else {
            return
        }
        if let lastUrl {
            networkConnectEventHandler(self, lastUrl)
        } else {
            queue.asyncAfter(deadline: .now() + 0.1) {
                // Repeat until `lastUrl` is assigned.
                self.performNetworkConnectEvent()
            }
        }
    }

    override func setupWebSocket(_ params: [String: URLQueryItem], with options: ARTClientOptions, resumeKey: String?) -> URL {
        let url = super.setupWebSocket(params, with: options, resumeKey: resumeKey)
        lastUrl = url
        return url
    }

    func send(_ message: ARTProtocolMessage) {
        // swiftlint:disable:next force_try
        let data = try! encoder.encode(message)
        send(data, withSource: message)
    }

    @discardableResult
    override func send(_ data: Data, withSource decodedObject: Any?) -> Bool {
        if let networkAnswer = factory.fakeNetworkResponse, let ws = websocket {
            // Ignore it because it should fake a failure.
            webSocket(ws, didFailWithError: networkAnswer.error)
            return false
        }

        if let msg = decodedObject as? ARTProtocolMessage {
            if ignoreSends {
                _protocolMessagesSentIgnored.append(msg)
                return false
            }
            _protocolMessagesSent.append(msg)
            if let performEvent = callbackBeforeProcessingOutgoingMessage {
                DispatchQueue.main.async {
                    performEvent(msg)
                }
            }
        }
        rawDataSent.append(data)
        return super.send(data, withSource: decodedObject)
    }

    override func receive(_ original: ARTProtocolMessage) {
        if original.action == .ack || original.action == .presence {
            if let error = replacingAcksWithNacks {
                original.action = .nack
                original.error = error
            }
        }
        _protocolMessagesReceived.append(original)
        if actionsIgnored.contains(original.action) {
            return
        }
        if let performEvent = callbackBeforeProcessingIncomingMessage {
            DispatchQueue.main.async {
                performEvent(original)
            }
        }
        var msg = original
        if let performEvent = callbackBeforeIncomingMessageModifier {
            guard let modifiedMsg = performEvent(msg) else {
                return
            }
            msg = modifiedMsg
        }
        super.receive(msg)
        if let performEvent = callbackAfterIncomingMessageModifier {
            guard let modifiedMsg = performEvent(msg) else {
                return
            }
            msg = modifiedMsg
        }
        if let performEvent = callbackAfterProcessingIncomingMessage {
            DispatchQueue.main.async {
                performEvent(msg)
            }
        }
    }

    override func receive(with data: Data) -> ARTProtocolMessage? {
        rawDataReceived.append(data)
        return super.receive(with: data)
    }

    override func webSocketDidOpen(_ webSocket: ARTWebSocket) {
        if !ignoreWebSocket {
            super.webSocketDidOpen(webSocket)
        }
    }

    override func webSocket(_ webSocket: ARTWebSocket, didFailWithError error: Error) {
        if !ignoreWebSocket {
            super.webSocket(webSocket, didFailWithError: error)
        }
    }

    override func webSocket(_ webSocket: ARTWebSocket, didReceiveMessage message: Any?) {
        if let networkAnswer = factory.fakeNetworkResponse, let ws = websocket {
            // Ignore it because it should fake a failure.
            self.webSocket(ws, didFailWithError: networkAnswer.error)
            return
        }

        if !ignoreWebSocket {
            super.webSocket(webSocket, didReceiveMessage: message as Any)
        }
    }

    override func webSocket(_ webSocket: ARTWebSocket, didCloseWithCode code: Int, reason: String?, wasClean: Bool) {
        if !ignoreWebSocket {
            super.webSocket(webSocket, didCloseWithCode: code, reason: reason, wasClean: wasClean)
        }
    }

    // MARK: Helpers

    func simulateTransportSuccess(clientId: String? = nil) {
        ignoreWebSocket = true
        let msg = ARTProtocolMessage()
        msg.action = .connected
        msg.connectionId = "x-xxxxxxxx"
        msg.connectionKey = "xxxxxxx-xxxxxxxxxxxxxx-xxxxxxxx"
        msg.connectionDetails = ARTConnectionDetails(clientId: clientId, connectionKey: "a8c10!t-3D0O4ejwTdvLkl-b33a8c10", maxMessageSize: 16384, maxFrameSize: 262_144, maxInboundRate: 250, connectionStateTtl: 60, serverId: "testServerId", maxIdleInterval: 15000, objectsGCGracePeriod: 86_400_000, siteCode: nil)
        super.receive(msg)
    }
}

// swiftlint:disable:next identifier_name
let AblyTestsErrorDomain = "test.ably.io"

enum FakeNetworkResponse {
    case noInternet
    case hostUnreachable
    case requestTimeout(timeout: TimeInterval)
    case hostInternalError(code: Int)
    case host400BadRequest
    case arbitraryError

    var error: NSError {
        switch self {
        case .noInternet:
            NSError(domain: NSPOSIXErrorDomain, code: 50, userInfo: [NSLocalizedDescriptionKey: "network is down", NSLocalizedFailureReasonErrorKey: AblyTestsErrorDomain + ".FakeNetworkResponse"])
        case .hostUnreachable:
            NSError(domain: kCFErrorDomainCFNetwork as String, code: 2, userInfo: [NSLocalizedDescriptionKey: "host unreachable", NSLocalizedFailureReasonErrorKey: AblyTestsErrorDomain + ".FakeNetworkResponse"])
        case .requestTimeout:
            NSError(domain: "com.squareup.SocketRocket", code: 504, userInfo: [NSLocalizedDescriptionKey: "timed out", NSLocalizedFailureReasonErrorKey: AblyTestsErrorDomain + ".FakeNetworkResponse"])
        case let .hostInternalError(code):
            NSError(domain: AblyTestsErrorDomain, code: code, userInfo: [NSLocalizedDescriptionKey: "internal error", NSLocalizedFailureReasonErrorKey: AblyTestsErrorDomain + ".FakeNetworkResponse"])
        case .host400BadRequest:
            NSError(domain: AblyTestsErrorDomain, code: 400, userInfo: [NSLocalizedDescriptionKey: "bad request", NSLocalizedFailureReasonErrorKey: AblyTestsErrorDomain + ".FakeNetworkResponse"])
        case .arbitraryError:
            NSError(domain: AblyTestsErrorDomain, code: 1, userInfo: [NSLocalizedDescriptionKey: "error from FakeNetworkResponse.arbitraryError"])
        }
    }

    func transportError(for url: URL) -> ARTRealtimeTransportError {
        switch self {
        case .noInternet:
            ARTRealtimeTransportError(error: error, type: .noInternet, url: url)
        case .hostUnreachable:
            ARTRealtimeTransportError(error: error, type: .hostUnreachable, url: url)
        case .requestTimeout:
            ARTRealtimeTransportError(error: error, type: .timeout, url: url)
        case let .hostInternalError(code):
            ARTRealtimeTransportError(error: error, badResponseCode: code, url: url)
        case .host400BadRequest:
            ARTRealtimeTransportError(error: error, badResponseCode: 400, url: url)
        case .arbitraryError:
            ARTRealtimeTransportError(error: error, type: .other, url: url)
        }
    }
}
