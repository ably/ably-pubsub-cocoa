import Ably

/// Default implementation of ``LiveMapPathObject``, adding map
/// navigation and read/write operations on top of ``DefaultPathObject``.
///
/// Spec: `RTTS6a`.
internal final class DefaultLiveMapPathObject: DefaultPathObject, LiveMapPathObject, @unchecked Sendable {
    // MARK: - Navigation (RTPO5, RTPO6)

    internal func get(key: String) -> any PathObject {
        // RTPO5c/RTPO5d — purely navigational, no resolution; appends the raw key (RTTS3h).
        DefaultPathObject(channelObject: channelObject, coreSDK: coreSDK, internalQueue: internalQueue, segments: segments + [key])
    }

    internal func at(path: String) -> any PathObject {
        // RTPO6b/RTPO6c/RTPO6d — purely navigational; parse the dot-delimited sub-path (backslash-escaped
        // dots honoured) and append its segments.
        DefaultPathObject(channelObject: channelObject, coreSDK: coreSDK, internalQueue: internalQueue, segments: segments + PathSegments.parse(path))
    }

    // MARK: - Reads (RTPO9, RTPO10, RTPO11, RTPO12)

    internal func entries() throws(ARTErrorInfo) -> [(key: String, value: any PathObject)] {
        try ChannelConfigGuards.throwIfInvalidAccessApiConfiguration(coreSDK: coreSDK, internalQueue: internalQueue) // RTPO9a
        // RTPO9d — not a LiveMap (or unresolved) -> empty.
        guard let mapNode = try resolvedMapNode() else {
            return []
        }
        // RTPO9c — derive from the map's keys at call time; child paths as if by get().
        return try mapNode.keys(coreSDK: coreSDK, delegate: channelObject).map { key in
            (key: key, value: get(key: key))
        }
    }

    internal func keys() throws(ARTErrorInfo) -> [String] {
        try ChannelConfigGuards.throwIfInvalidAccessApiConfiguration(coreSDK: coreSDK, internalQueue: internalQueue) // RTPO10a
        // RTPO10d — not a LiveMap (or unresolved) -> empty.
        guard let mapNode = try resolvedMapNode() else {
            return []
        }
        // RTPO10c — via RTLM12.
        return try mapNode.keys(coreSDK: coreSDK, delegate: channelObject)
    }

    internal func values() throws(ARTErrorInfo) -> [any PathObject] {
        try ChannelConfigGuards.throwIfInvalidAccessApiConfiguration(coreSDK: coreSDK, internalQueue: internalQueue) // RTPO11a
        // RTPO11d — not a LiveMap (or unresolved) -> empty.
        guard let mapNode = try resolvedMapNode() else {
            return []
        }
        // RTPO11c — child paths as if by get().
        return try mapNode.keys(coreSDK: coreSDK, delegate: channelObject).map { key in
            get(key: key)
        }
    }

    internal func size() throws(ARTErrorInfo) -> Int? {
        try ChannelConfigGuards.throwIfInvalidAccessApiConfiguration(coreSDK: coreSDK, internalQueue: internalQueue) // RTPO12a
        // RTPO12d — not a LiveMap (or unresolved) -> nil.
        guard let mapNode = try resolvedMapNode() else {
            return nil
        }
        // RTPO12c — via RTLM10d.
        return try mapNode.size(coreSDK: coreSDK, delegate: channelObject)
    }

    // MARK: - Writes (RTPO15, RTPO16)

    internal func set(key: String, value: LiveMapValue) async throws(ARTErrorInfo) {
        try ChannelConfigGuards.throwIfInvalidWriteApiConfiguration(coreSDK: coreSDK, internalQueue: internalQueue) // RTPO15b / RTO26
        // RTPO15c / RTPO3c2 — unresolved write path throws 92005.
        guard let resolved = try resolveValueAtCurrentPath() else {
            throw LiveObjectsError.pathNotResolved(path: path).toARTErrorInfo()
        }
        // RTPO15e — wrong-type write wrapper throws 92007.
        guard case let .liveMap(mapInstance) = Instance.from(internalValue: resolved, coreSDK: coreSDK, realtimeObjects: channelObject, internalQueue: internalQueue) else {
            throw LiveObjectsError.pathTypeMismatch(operationDescription: "Cannot set a key on a non-LiveMap object at path: \"\(path)\"").toARTErrorInfo()
        }
        // RTPO15d -> RTLM20 (via the instance layer, which materialises blueprint values).
        try await mapInstance.set(key: key, value: value)
    }

    internal func remove(key: String) async throws(ARTErrorInfo) {
        try ChannelConfigGuards.throwIfInvalidWriteApiConfiguration(coreSDK: coreSDK, internalQueue: internalQueue) // RTPO16b / RTO26
        // RTPO16c / RTPO3c2 — unresolved write path throws 92005.
        guard let resolved = try resolveValueAtCurrentPath() else {
            throw LiveObjectsError.pathNotResolved(path: path).toARTErrorInfo()
        }
        // RTPO16e — wrong-type write wrapper throws 92007.
        guard case let .liveMap(mapInstance) = Instance.from(internalValue: resolved, coreSDK: coreSDK, realtimeObjects: channelObject, internalQueue: internalQueue) else {
            throw LiveObjectsError.pathTypeMismatch(operationDescription: "Cannot remove a key from a non-LiveMap object at path: \"\(path)\"").toARTErrorInfo()
        }
        // RTPO16d -> RTLM21.
        try await mapInstance.remove(key: key)
    }

    // MARK: - Helpers

    /// Resolves the current path and narrows to the backing map node, or `nil` if the path is
    /// unresolved or does not resolve to a map (RTPO9d/RTPO10d/RTPO11d/RTPO12d).
    private func resolvedMapNode() throws(ARTErrorInfo) -> InternalDefaultLiveMap? {
        guard let resolved = try resolveValueAtCurrentPath(), case let .liveMap(mapNode) = resolved else {
            return nil
        }
        return mapNode
    }
}
