import _AblyPluginSupportPrivate
import AblyPubSubDevice
@testable import AblyLiveObjects

final class MockCoreSDK: CoreSDK {
    /// Synchronizes access to `_publishHandler` and `_publishCallbackHandler`.
    private let mutex = NSLock()
    private nonisolated(unsafe) var _publishHandler: (([ProtocolTypes.OutboundObjectMessage]) async throws(ErrorInfo) -> AblyLiveObjects.PublishResult)?
    private nonisolated(unsafe) var _publishCallbackHandler: (([ProtocolTypes.OutboundObjectMessage], @escaping @Sendable (Result<AblyLiveObjects.PublishResult, ErrorInfo>) -> Void) -> Void)?
    /// Custom handler for `nosync_attach` (RTL33b implicit attach). If unset, `nosync_attach`
    /// simulates a successful attach that transitions the channel to ATTACHED.
    private nonisolated(unsafe) var _attachHandler: ((@escaping @Sendable (ErrorInfo?) -> Void) -> Void)?

    private let channelStateMutex: DispatchQueueMutex<_AblyPluginSupportPrivate.RealtimeChannelState>
    private let serverTime: Date
    let channelName: String

    /// The value returned by ``nosync_maxMessageSize`` (RTO15d). `nil` (the default) simulates a
    /// connection with no negotiated limit, so the RTO15d gate falls back to the Ably default.
    private nonisolated(unsafe) var _maxMessageSize: Int?

    /// The value returned by ``nosync_objectChannelModes`` (RTO2a2/RTO2b2).
    private nonisolated(unsafe) var _objectChannelModes: _AblyPluginSupportPrivate.ChannelMode
    /// The value returned by ``echoMessages`` (RTO26).
    private nonisolated(unsafe) var _echoMessages: Bool
    /// The value returned by ``nosync_connectionStateError`` (RTO26); `nil` = connection is active.
    private nonisolated(unsafe) var _connectionStateError: ErrorInfo?

    init(
        channelState: _AblyPluginSupportPrivate.RealtimeChannelState,
        serverTime: Date = .init(),
        maxMessageSize: Int? = nil,
        channelName: String = "",
        objectChannelModes: _AblyPluginSupportPrivate.ChannelMode = [.objectSubscribe, .objectPublish],
        echoMessages: Bool = true,
        connectionStateError: ErrorInfo? = nil,
        internalQueue: DispatchQueue,
    ) {
        channelStateMutex = DispatchQueueMutex(dispatchQueue: internalQueue, initialValue: channelState)
        self.serverTime = serverTime
        _maxMessageSize = maxMessageSize
        self.channelName = channelName
        _objectChannelModes = objectChannelModes
        _echoMessages = echoMessages
        _connectionStateError = connectionStateError
    }

    var nosync_objectChannelModes: _AblyPluginSupportPrivate.ChannelMode {
        mutex.withLock { _objectChannelModes }
    }

    func setObjectChannelModes(_ modes: _AblyPluginSupportPrivate.ChannelMode) {
        mutex.withLock { _objectChannelModes = modes }
    }

    var echoMessages: Bool {
        mutex.withLock { _echoMessages }
    }

    func setEchoMessages(_ enabled: Bool) {
        mutex.withLock { _echoMessages = enabled }
    }

    var nosync_connectionStateError: ErrorInfo? {
        mutex.withLock { _connectionStateError }
    }

    func setConnectionStateError(_ error: ErrorInfo?) {
        mutex.withLock { _connectionStateError = error }
    }

    var nosync_maxMessageSize: Int? {
        mutex.withLock { _maxMessageSize }
    }

    /// Sets the value returned by ``nosync_maxMessageSize`` (RTO15d).
    func setMaxMessageSize(_ maxMessageSize: Int?) {
        mutex.withLock { _maxMessageSize = maxMessageSize }
    }

    func nosync_publish(objectMessages: [ProtocolTypes.OutboundObjectMessage], callback: @escaping @Sendable (Result<AblyLiveObjects.PublishResult, ErrorInfo>) -> Void) {
        // We can't return _publishHandler from `mutex.withLock` because we get "error: runtime support for typed throws function types is only available in macOS 15.0.0 or newer"
        var asyncHandler: (([ProtocolTypes.OutboundObjectMessage]) async throws(ErrorInfo) -> AblyLiveObjects.PublishResult)?
        var callbackHandler: (([ProtocolTypes.OutboundObjectMessage], @escaping @Sendable (Result<AblyLiveObjects.PublishResult, ErrorInfo>) -> Void) -> Void)?
        mutex.withLock {
            asyncHandler = _publishHandler
            callbackHandler = _publishCallbackHandler
        }

        if let callbackHandler {
            callbackHandler(objectMessages, callback)
        } else if let asyncHandler {
            let queue = channelStateMutex.dispatchQueue
            Task {
                do throws(ErrorInfo) {
                    let publishResult = try await asyncHandler(objectMessages)
                    queue.async { callback(.success(publishResult)) }
                } catch {
                    queue.async { callback(.failure(error)) }
                }
            }
        } else {
            protocolRequirementNotImplemented()
        }
    }

    func testsOnly_overridePublish(with _: @escaping ([ProtocolTypes.OutboundObjectMessage]) async throws(ErrorInfo) -> AblyLiveObjects.PublishResult) {
        protocolRequirementNotImplemented()
    }

    var nosync_channelState: _AblyPluginSupportPrivate.RealtimeChannelState {
        channelStateMutex.withoutSync { $0 }
    }

    func nosync_attach(callback: @escaping @Sendable (ErrorInfo?) -> Void) {
        var handler: ((@escaping @Sendable (ErrorInfo?) -> Void) -> Void)?
        mutex.withLock { handler = _attachHandler }
        if let handler {
            handler(callback)
        } else {
            // Default: simulate a successful attach that transitions the channel to ATTACHED
            // (invoked on the internal queue by `ensureActiveChannel`, so `withoutSync` is valid).
            channelStateMutex.withoutSync { $0 = .attached }
            callback(nil)
        }
    }

    /// Sets a custom `nosync_attach` handler (RTL33b), e.g. to inject an attach failure or a state
    /// transition. The handler is invoked on the internal queue and must call the supplied callback.
    func setAttachHandler(_ handler: @escaping (@escaping @Sendable (ErrorInfo?) -> Void) -> Void) {
        mutex.withLock { _attachHandler = handler }
    }

    /// Overwrites the mock channel state (invoked on the internal queue).
    func nosync_setChannelState(_ state: _AblyPluginSupportPrivate.RealtimeChannelState) {
        channelStateMutex.withoutSync { $0 = state }
    }

    /// Sets a custom publish handler for testing.
    ///
    /// - Precondition: ``setPublishCallbackHandler(_:)`` must not have been called.
    func setPublishHandler(_ handler: @escaping ([ProtocolTypes.OutboundObjectMessage]) async throws(ErrorInfo) -> AblyLiveObjects.PublishResult) {
        mutex.withLock {
            precondition(_publishCallbackHandler == nil, "Cannot set both publishHandler and publishCallbackHandler")
            _publishHandler = handler
        }
    }

    /// Sets a callback-based publish handler for testing.
    ///
    /// Unlike ``setPublishHandler(_:)``, this variant receives the publish callback directly,
    /// avoiding the `Task`-based dispatch used by the async variant. This makes it easier to
    /// control the ordering of side effects relative to the publish callback — the handler can
    /// dispatch the callback and follow-up work as separate blocks on the internal queue, giving
    /// explicit control over their ordering.
    ///
    /// - Precondition: ``setPublishHandler(_:)`` must not have been called.
    func setPublishCallbackHandler(_ handler: @escaping ([ProtocolTypes.OutboundObjectMessage], @escaping @Sendable (Result<AblyLiveObjects.PublishResult, ErrorInfo>) -> Void) -> Void) {
        mutex.withLock {
            // We use pattern matching instead of `== nil` to avoid "runtime support for typed
            // throws function types is only available in macOS 15.0.0 or newer".
            if case .some = _publishHandler {
                preconditionFailure("Cannot set both publishHandler and publishCallbackHandler")
            }
            _publishCallbackHandler = handler
        }
    }

    func nosync_fetchServerTime(callback: @escaping @Sendable (Result<Date, ErrorInfo>) -> Void) {
        callback(.success(serverTime))
    }
}
