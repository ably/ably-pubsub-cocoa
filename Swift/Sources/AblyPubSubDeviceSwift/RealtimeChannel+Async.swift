public extension RealtimeChannelProtocol {
    /// Attaches to this channel. See `attach(_:)`.
    nonisolated(nonsending) func attach() async throws(ErrorInfo) {
        try await withErrorCallback { attach($0) }
    }

    /// Detaches from this channel. See `detach(_:)`.
    nonisolated(nonsending) func detach() async throws(ErrorInfo) {
        try await withErrorCallback { detach($0) }
    }

    /// Sets the channel's options. See `setOptions(_:callback:)`.
    nonisolated(nonsending) func setOptions(_ options: RealtimeChannelOptions?) async throws(ErrorInfo) {
        try await withErrorCallback { setOptions(options, callback: $0) }
    }

    /// Publishes a single message to this channel. See `publish(_:data:resultCallback:)`.
    ///
    /// - Returns: The serials the server assigned to the published message, or `nil` if the server's acknowledgement didn't include them.
    @discardableResult
    nonisolated(nonsending) func publish(_ name: String?, data: Any?) async throws(ErrorInfo) -> PublishResult? {
        try await withResultCallback { publish(name, data: data, resultCallback: $0) }
    }

    /// Publishes messages to this channel. See `publish(_:resultCallback:)`.
    ///
    /// - Returns: The serials the server assigned to the published messages, or `nil` if the server's acknowledgement didn't include them.
    @discardableResult
    nonisolated(nonsending) func publish(_ messages: [Message]) async throws(ErrorInfo) -> PublishResult? {
        try await withResultCallback { publish(messages, resultCallback: $0) }
    }
}
