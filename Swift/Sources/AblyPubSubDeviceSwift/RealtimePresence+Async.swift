public extension RealtimePresenceProtocol {
    /// Enters the presence set for the channel. See `enter(_:callback:)`.
    nonisolated(nonsending) func enter(_ data: Any?) async throws(ErrorInfo) {
        try await withErrorCallback { enter(data, callback: $0) }
    }

    /// Updates the data for the present member. See `update(_:callback:)`.
    nonisolated(nonsending) func update(_ data: Any?) async throws(ErrorInfo) {
        try await withErrorCallback { update(data, callback: $0) }
    }

    /// Leaves the presence set for the channel. See `leave(_:callback:)`.
    nonisolated(nonsending) func leave(_ data: Any?) async throws(ErrorInfo) {
        try await withErrorCallback { leave(data, callback: $0) }
    }

    /// Enters the presence set on behalf of the given client ID. See `enterClient(_:data:callback:)`.
    nonisolated(nonsending) func enterClient(_ clientId: String, data: Any?) async throws(ErrorInfo) {
        try await withErrorCallback { enterClient(clientId, data: data, callback: $0) }
    }

    /// Updates the data for the member with the given client ID. See `updateClient(_:data:callback:)`.
    nonisolated(nonsending) func updateClient(_ clientId: String, data: Any?) async throws(ErrorInfo) {
        try await withErrorCallback { updateClient(clientId, data: data, callback: $0) }
    }

    /// Leaves the presence set on behalf of the given client ID. See `leaveClient(_:data:callback:)`.
    nonisolated(nonsending) func leaveClient(_ clientId: String, data: Any?) async throws(ErrorInfo) {
        try await withErrorCallback { leaveClient(clientId, data: data, callback: $0) }
    }
}
