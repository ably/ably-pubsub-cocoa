public extension ConnectionProtocol {
    /// Pings the server over the connection. See `ping(_:)`.
    nonisolated(nonsending) func ping() async throws(ErrorInfo) {
        try await withErrorCallback { ping($0) }
    }
}
