import Ably

/// Default implementation of ``LiveCounterPathObject``.
///
/// Counters are terminal nodes (no navigation), so this only adds the counter read/write operations
/// on top of ``DefaultPathObject``.
///
/// Spec: `RTTS6b`.
internal final class DefaultLiveCounterPathObject: DefaultPathObject, LiveCounterPathObject, @unchecked Sendable {
    // MARK: - Read (RTTS6b)

    internal func value() throws(ARTErrorInfo) -> Double? {
        try ChannelConfigGuards.throwIfInvalidAccessApiConfiguration(coreSDK: coreSDK, internalQueue: internalQueue)
        guard let resolved = try resolveValueAtCurrentPath(), case let .liveCounter(counterNode) = resolved else {
            return nil // RTTS6b
        }
        // RTPO7c via RTLC5 (the node accessor runs the RTO25b check).
        return try counterNode.value(coreSDK: coreSDK)
    }

    // MARK: - Writes (RTPO17, RTPO18)

    internal func increment(amount: Double) async throws(ARTErrorInfo) {
        let counterNode = try resolvedCounterNodeForWrite(operation: "increment") // RTPO17b/c/e
        // RTPO17d -> RTLC12.
        try await counterNode.increment(amount: amount, coreSDK: coreSDK, realtimeObjects: channelObject)
    }

    internal func decrement(amount: Double) async throws(ARTErrorInfo) {
        let counterNode = try resolvedCounterNodeForWrite(operation: "decrement") // RTPO18b/c/e
        // RTPO18d -> RTLC13.
        try await counterNode.decrement(amount: amount, coreSDK: coreSDK, realtimeObjects: channelObject)
    }

    // MARK: - Helpers

    /// Runs the write-API guard, resolves the path (throwing 92005 when unresolved, RTPO3c2) and
    /// narrows to the backing counter node (throwing 92007 on a type mismatch, RTPO17e/RTPO18e).
    private func resolvedCounterNodeForWrite(operation: String) throws(ARTErrorInfo) -> InternalDefaultLiveCounter {
        try ChannelConfigGuards.throwIfInvalidWriteApiConfiguration(coreSDK: coreSDK, internalQueue: internalQueue) // RTO26
        guard let resolved = try resolveValueAtCurrentPath() else {
            throw LiveObjectsError.pathNotResolved(path: path).toARTErrorInfo() // RTPO3c2
        }
        guard case let .liveCounter(counterNode) = resolved else {
            throw LiveObjectsError.pathTypeMismatch(operationDescription: "Cannot \(operation) a non-LiveCounter object at path: \"\(path)\"").toARTErrorInfo() // RTPO17e/RTPO18e
        }
        return counterNode
    }
}
