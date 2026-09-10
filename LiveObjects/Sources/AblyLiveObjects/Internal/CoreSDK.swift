internal import _AblyPluginSupportPrivate
import Ably

/// The API that the internal components of the SDK (that is, `DefaultLiveObjects` and down) use to interact with our core SDK (i.e. ably-cocoa).
///
/// This provides us with a mockable interface to ably-cocoa, and it also allows internal components and their tests not to need to worry about some of the boring details of how we bridge Swift types to `_AblyPluginSupportPrivate`'s Objective-C API (i.e. boxing).
internal protocol CoreSDK: AnyObject, Sendable {
    /// Implements the internal `#publish` method of RTO15.
    func nosync_publish(objectMessages: [ProtocolTypes.OutboundObjectMessage], callback: @escaping @Sendable (Result<PublishResult, ARTErrorInfo>) -> Void)

    /// Implements the server time fetch of RTO16, including the storing and usage of the local clock offset.
    func nosync_fetchServerTime(callback: @escaping @Sendable (Result<Date, ARTErrorInfo>) -> Void)

    // testsOnly_ residual: protocol requirement — a foreign module cannot add requirements; see Test/AblyLiveObjectsTesting/README.md
    /// Replaces the implementation of ``nosync_publish(objectMessages:callback:)``.
    ///
    /// Used by integration tests, for example to disable `ObjectMessage` publishing so that a test can verify that a behaviour is not a side effect of an `ObjectMessage` sent by the SDK.
    func testsOnly_overridePublish(with newImplementation: @escaping ([ProtocolTypes.OutboundObjectMessage]) async throws(ARTErrorInfo) -> PublishResult)

    /// Returns the current state of the Realtime channel that this wraps.
    var nosync_channelState: _AblyPluginSupportPrivate.RealtimeChannelState { get }

    /// The name of the Realtime channel that this wraps (PAOM2e/PAOM3b). Used to populate the
    /// `channel` field of a public `ObjectMessage`.
    var channelName: String { get }

    /// The channel's effective object-related channel modes (RTO2a/RTO2b), used by the RTO2a2/RTO2b2
    /// mode guards. Resolved by the core SDK as the attached modes if present, else the channel-options
    /// modes.
    var nosync_objectChannelModes: _AblyPluginSupportPrivate.ChannelMode { get }

    /// Whether the client has the `echoMessages` option enabled (RTO26c).
    var echoMessages: Bool { get }

    /// The error that makes the client's connection unpublishable, or `nil` if the connection is in a
    /// publishable (active) state. Spec: RTO15b (the publish adheres to the RTL6c connection-state
    /// conditions).
    var nosync_connectionStateError: ARTErrorInfo? { get }

    /// RTO15d: The connection's negotiated `maxMessageSize`, read from the latest `CONNECTED`
    /// `ProtocolMessage`'s `connectionDetails`. `nil` when the core SDK has no connection details yet or
    /// the server did not send a limit; callers fall back to the Ably default of 65536 bytes.
    var nosync_maxMessageSize: Int? { get }

    /// Initiates an implicit attach (RTL33b) on the wrapped Realtime channel, used by the
    /// *ensure-active-channel* procedure of `RealtimeObject.get()` (RTO23e / RTL33). The callback
    /// receives `nil` on success, or the `ARTErrorInfo` that caused the attach to fail (RTL33b1). The
    /// callback fires on the internal queue.
    func nosync_attach(callback: @escaping @Sendable (ARTErrorInfo?) -> Void)
}

internal final class DefaultCoreSDK: CoreSDK {
    /// Used to synchronize access to internal mutable state.
    private let mutex = NSLock()

    private let channel: _AblyPluginSupportPrivate.RealtimeChannel
    private let client: _AblyPluginSupportPrivate.RealtimeClient
    private let pluginAPI: PluginAPIProtocol
    private let logger: Logger

    /// If set, ``publish(objectMessages:)`` delegates to this implementation.
    ///
    /// This enables the `testsOnly_overridePublish(with:)` test hook.
    ///
    /// - Note: This should be `throws(ARTErrorInfo)` but that causes a compilation error of "Runtime support for typed throws function types is only available in macOS 15.0.0 or newer".
    private nonisolated(unsafe) var overriddenPublishImplementation: (([ProtocolTypes.OutboundObjectMessage]) async throws -> PublishResult)?

    internal init(
        channel: _AblyPluginSupportPrivate.RealtimeChannel,
        client: _AblyPluginSupportPrivate.RealtimeClient,
        pluginAPI: PluginAPIProtocol,
        logger: Logger
    ) {
        self.channel = channel
        self.client = client
        self.pluginAPI = pluginAPI
        self.logger = logger
    }

    // MARK: - CoreSDK conformance

    internal func nosync_publish(objectMessages: [ProtocolTypes.OutboundObjectMessage], callback: @escaping @Sendable (Result<PublishResult, ARTErrorInfo>) -> Void) {
        logger.log("nosync_publish(objectMessages: \(LoggingUtilities.formatObjectMessagesForLogging(objectMessages)))", level: .debug)

        let overriddenImplementation = mutex.withLock {
            overriddenPublishImplementation
        }
        if let overriddenImplementation {
            let queue = pluginAPI.internalQueue(for: client)
            Task {
                do {
                    let publishResult = try await overriddenImplementation(objectMessages)
                    queue.async { callback(.success(publishResult)) }
                } catch {
                    guard let artErrorInfo = error as? ARTErrorInfo else {
                        preconditionFailure("Expected ARTErrorInfo, got \(error)")
                    }
                    queue.async { callback(.failure(artErrorInfo)) }
                }
            }
            return
        }

        // The RTO15d message-size gate lives in `InternalDefaultRealtimeObjects` and guards `publishAndApply` only; this lower-level publish path is not size-checked here.
        DefaultInternalPlugin.nosync_sendObject(
            objectMessages: objectMessages,
            channel: channel,
            client: client,
            pluginAPI: pluginAPI,
            callback: callback,
        )
    }

    // testsOnly_ residual: production-embedded instrumentation — cannot move to AblyLiveObjectsTesting; see Test/AblyLiveObjectsTesting/README.md
    internal func testsOnly_overridePublish(with newImplementation: @escaping ([ProtocolTypes.OutboundObjectMessage]) async throws(ARTErrorInfo) -> PublishResult) {
        mutex.withLock {
            overriddenPublishImplementation = newImplementation
        }
    }

    internal func nosync_fetchServerTime(callback: @escaping @Sendable (Result<Date, ARTErrorInfo>) -> Void) {
        let internalQueue = pluginAPI.internalQueue(for: client)

        pluginAPI.nosync_fetchServerTime(for: client) { serverTime, error in
            dispatchPrecondition(condition: .onQueue(internalQueue))

            if let error {
                callback(.failure(ARTErrorInfo.castPluginPublicErrorInfo(error)))
            } else {
                guard let serverTime else {
                    preconditionFailure("nosync_fetchServerTime gave nil serverTime and nil error")
                }
                callback(.success(serverTime))
            }
        }
    }

    internal var nosync_channelState: _AblyPluginSupportPrivate.RealtimeChannelState {
        pluginAPI.nosync_state(for: channel)
    }

    internal var channelName: String {
        pluginAPI.name(for: channel)
    }

    internal var nosync_objectChannelModes: _AblyPluginSupportPrivate.ChannelMode {
        pluginAPI.nosync_objectChannelModes(for: channel)
    }

    internal var echoMessages: Bool {
        // The plugin API exposes client options as an opaque marker protocol; cast to the concrete
        // `ARTClientOptions` (the only conformer) to read `echoMessages`.
        ARTClientOptions.castPluginPublicClientOptions(pluginAPI.options(for: client)).echoMessages
    }

    internal var nosync_connectionStateError: ARTErrorInfo? {
        pluginAPI.nosync_connectionStateError(for: client).map { ARTErrorInfo.castPluginPublicErrorInfo($0) }
    }

    internal var nosync_maxMessageSize: Int? {
        // The core SDK surfaces the limit via the latest CONNECTED ProtocolMessage's connectionDetails;
        // a `0`/absent value means the server sent no limit, so we return nil to let the caller fall
        // back to the Ably default.
        guard let connectionDetails = pluginAPI.nosync_latestConnectionDetails(for: client) else {
            return nil
        }
        let maxMessageSize = connectionDetails.maxMessageSize
        return maxMessageSize > 0 ? maxMessageSize : nil
    }

    internal func nosync_attach(callback: @escaping @Sendable (ARTErrorInfo?) -> Void) {
        logger.log("nosync_attach()", level: .debug)
        pluginAPI.nosync_attach(channel) { error in
            callback(error.map { ARTErrorInfo.castPluginPublicErrorInfo($0) })
        }
    }
}

// MARK: - Channel State Validation

/// Extension on CoreSDK providing the RTO25b/RTO26b channel-state preconditions that the internal
/// (nosync) engine runs before a public read/write operation touches the object graph.
///
/// These two named helpers replace raw per-call-site state lists (e.g.
/// `notIn: [.detached, .failed, .suspended]`), so a call site names the API kind it guards rather
/// than restating a state list that could drift out of sync with the spec.
///
/// They live here — on the `nosync_` `CoreSDK` layer — rather than in `ChannelConfigGuards` on
/// purpose: this layer runs with the internal queue already held, whereas `ChannelConfigGuards` is
/// the public path/instance-API guard layer that performs its own internal-queue hop and also
/// checks channel modes / `echoMessages`. The two layers are deliberately distinct, so the guards
/// are not shared between them (`ChannelConfigGuards` keeps its own on-queue channel-state check).
internal extension CoreSDK {
    /// RTO25b — the *access API* channel-state precondition for read operations (map get/size/entries,
    /// counter value, subscribe): throws an `ARTErrorInfo` with code 90001 and statusCode 400 when the
    /// channel is in the `DETACHED` or `FAILED` state (`SUSPENDED` is permitted for reads).
    ///
    /// - Parameter operationDescription: A description of the operation, used in the error message.
    func nosync_validateChannelStateForAccessAPI(operationDescription: String) throws(ARTErrorInfo) {
        try nosync_validateChannelState(notIn: [.detached, .failed], operationDescription: operationDescription)
    }

    /// RTO26b — the *write API* channel-state precondition for mutation operations (map set/remove,
    /// counter increment/decrement, createMap/createCounter): throws an `ARTErrorInfo` with code 90001
    /// and statusCode 400 when the channel is in the `DETACHED`, `FAILED`, or `SUSPENDED` state.
    ///
    /// - Parameter operationDescription: A description of the operation, used in the error message.
    func nosync_validateChannelStateForWriteAPI(operationDescription: String) throws(ARTErrorInfo) {
        try nosync_validateChannelState(notIn: [.detached, .failed, .suspended], operationDescription: operationDescription)
    }

    /// Throws an `ARTErrorInfo` with code 90001 and statusCode 400 if the channel is currently in any
    /// of `invalidStates`. Shared implementation for the RTO25b/RTO26b helpers above; call those named
    /// helpers from operation call sites rather than this generic one.
    private func nosync_validateChannelState(
        notIn invalidStates: [_AblyPluginSupportPrivate.RealtimeChannelState],
        operationDescription: String,
    ) throws(ARTErrorInfo) {
        let currentChannelState = nosync_channelState
        if invalidStates.contains(currentChannelState) {
            throw LiveObjectsError.objectsOperationFailedInvalidChannelState(
                operationDescription: operationDescription,
                channelState: currentChannelState,
            )
            .toARTErrorInfo()
        }
    }
}
