import Ably
import Foundation

/// Default implementation of ``PathObject``, the untyped node in the path-addressed view of the
/// LiveObjects graph.
///
/// A `DefaultPathObject` stores a dot-delimited path and resolves it **fresh on every call** against
/// the live objects graph via ``resolveValueAtCurrentPath()``, walking root → children through the
/// pool. It never holds a stale reference: if the object at a path changes, the same path object
/// resolves to the new object on the next call.
///
/// The `as*` casts (``asLiveMap()``/``asLiveCounter()``/``asPrimitive()``) return a typed view of the
/// same position without resolving it (RTTS5). Reads degrade to `nil`/`false`/empty on an unresolved
/// path (best-effort, RTPO3c1); writes throw 92005 (RTPO3c2) — implemented by the typed subclasses.
///
/// The shared subclasses ``DefaultLiveMapPathObject``, ``DefaultLiveCounterPathObject`` and
/// ``DefaultPrimitivePathObject`` add the type-specific members on top of this base.
///
/// Spec: `RTPO1`, `RTPO2`, `RTPO3`, `RTTS3`.
///
/// `@unchecked Sendable`: a non-`final` base class cannot get a checked `Sendable` conformance, but
/// every stored property here is an immutable `let` of a `Sendable` type, and the typed subclasses
/// add no stored state — so the conformance is sound.
internal class DefaultPathObject: PathObject, @unchecked Sendable {
    /// The channel's realtime-objects engine. Supplies the objects pool for resolution and backs the
    /// node accessors' pool-delegate parameter and the write path.
    internal let channelObject: any InternalRealtimeObjectsProtocol
    internal let coreSDK: CoreSDK
    internal let internalQueue: DispatchQueue

    /// The stored path, as an ordered list of raw string segments (RTPO2a). The empty list is the root
    /// (zero segments, RTPO4c).
    internal let segments: [String]

    /// RTPO4 — the dot-delimited string rendering of ``segments`` (dots inside a segment escaped).
    internal var path: String {
        PathSegments.join(segments)
    }

    internal init(
        channelObject: any InternalRealtimeObjectsProtocol,
        coreSDK: CoreSDK,
        internalQueue: DispatchQueue,
        segments: [String],
    ) {
        self.channelObject = channelObject
        self.coreSDK = coreSDK
        self.internalQueue = internalQueue
        self.segments = segments
    }

    // MARK: - PathObject

    internal func instance() throws(ARTErrorInfo) -> Instance? {
        try ChannelConfigGuards.throwIfInvalidAccessApiConfiguration(coreSDK: coreSDK, internalQueue: internalQueue) // RTPO8a
        // RTPO8e — unresolved path yields no instance.
        guard let resolved = try resolveValueAtCurrentPath() else {
            return nil
        }
        // RTPO8c/RTPO8f — wrap the resolved value (live object or primitive) in its typed Instance.
        return Instance.from(internalValue: resolved, coreSDK: coreSDK, realtimeObjects: channelObject, internalQueue: internalQueue)
    }

    internal func compactJson() throws(ARTErrorInfo) -> JSONValue? {
        // Single access-guard site: `instance()` runs the RTPO14a (RTO25) preconditions — including the
        // RTO25a `object_subscribe` mode check that the delegated instance layer does not re-run — and
        // resolves the path (RTPO3c1 -> nil). RTPO14b recursive compaction (cycle markers, base64
        // binary) is exactly the instance layer's `compactJson`, so reuse it rather than re-deriving.
        try instance()?.compactJson()
    }

    internal func exists() throws(ARTErrorInfo) -> Bool {
        try ChannelConfigGuards.throwIfInvalidAccessApiConfiguration(coreSDK: coreSDK, internalQueue: internalQueue)
        // RTTS4a — a value exists iff the path resolves.
        return try resolveValueAtCurrentPath() != nil
    }

    internal func type() throws(ARTErrorInfo) -> ValueType? {
        try ChannelConfigGuards.throwIfInvalidAccessApiConfiguration(coreSDK: coreSDK, internalQueue: internalQueue)
        // RTTS4b3 — nil when nothing resolves at the path.
        guard let resolved = try resolveValueAtCurrentPath() else {
            return nil
        }
        return Self.valueType(of: resolved)
    }

    internal func asLiveMap() -> any LiveMapPathObject {
        // RTTS5a — pure type refinement; does not resolve the path, never throws.
        DefaultLiveMapPathObject(channelObject: channelObject, coreSDK: coreSDK, internalQueue: internalQueue, segments: segments)
    }

    internal func asLiveCounter() -> any LiveCounterPathObject {
        // RTTS5b
        DefaultLiveCounterPathObject(channelObject: channelObject, coreSDK: coreSDK, internalQueue: internalQueue, segments: segments)
    }

    internal func asPrimitive() -> any PrimitivePathObject {
        // RTTS5c
        DefaultPrimitivePathObject(channelObject: channelObject, coreSDK: coreSDK, internalQueue: internalQueue, segments: segments)
    }

    @discardableResult
    internal func subscribe(options: PathObjectSubscriptionOptions?, listener: @escaping PathObjectSubscriptionCallback) throws(ARTErrorInfo) -> any Subscription {
        try ChannelConfigGuards.throwIfInvalidAccessApiConfiguration(coreSDK: coreSDK, internalQueue: internalQueue) // RTPO19b
        // RTPO19c1a — the shipped `PathObjectSubscriptionOptions.init(depth:)` is non-throwing
        // and frozen, so `depth <= 0` (40003) is validated here rather than in the initializer.
        try ChannelConfigGuards.validateSubscriptionDepth(options?.depth)

        // The subscription's coverage path is this object's stored segments (RTPO19f).
        let segments = segments

        // The factory that builds each event's PathObject (RTO24b2b1 / RTPO19e1). Captures this
        // object's resolution context *weakly*, so the long-lived register never keeps the channel
        // object (or core SDK) alive; a released context makes the subscription a silent no-op.
        let channelObject = channelObject
        let coreSDK = coreSDK
        let internalQueue = internalQueue
        let makePathObject: PathObjectSubscriptionRegister.PathObjectFactory = { [weak channelObject, weak coreSDK] eventSegments in
            guard let channelObject, let coreSDK else {
                return nil
            }
            return DefaultPathObject(channelObject: channelObject, coreSDK: coreSDK, internalQueue: internalQueue, segments: eventSegments)
        }

        // The register is queue-confined; its `subscribe` performs the internal-queue hop itself. The
        // returned Subscription's `unsubscribe()` deregisters (SUB2a/SUB2b).
        return channelObject.pathObjectSubscriptionRegister.subscribe(
            segments: segments,
            depth: options?.depth,
            listener: listener,
            makePathObject: makePathObject,
        )
    }

    // MARK: - Path resolution (RTPO3)

    /// RTPO3 path resolution against the local objects graph, evaluated fresh at call time. Returns
    /// `nil` on resolution failure; read callers degrade per RTPO3c1, write callers throw 92005 per
    /// RTPO3c2.
    ///
    /// The root is always present and always a map (RTO3b); the pool never replaces the root instance
    /// (RTO4b2, RTO5c2a), so looking it up per call is equivalent to holding the RTPO2b root reference.
    internal func resolveValueAtCurrentPath() throws(ARTErrorInfo) -> InternalLiveMapValue? {
        // Read the root map node on the internal queue (the `nosync_` pool accessor must run there).
        let rootNode = internalQueue.ably_syncNoDeadlock { channelObject.nosync_objectsPool.root }
        var current: InternalLiveMapValue = .liveMap(rootNode)
        // An empty segment list is the root itself — zero segments (RTPO3b).
        for segment in segments {
            // RTPO3a1 — a non-map value mid-path cannot be navigated further.
            guard case let .liveMap(mapNode) = current else {
                return nil
            }
            // RTPO3a2 — look up the next segment via RTLM5 (the node accessor runs the RTO25b check).
            guard let next = try mapNode.get(key: segment, coreSDK: coreSDK, delegate: channelObject) else {
                return nil
            }
            current = next
        }
        return current // RTPO3a3
    }

    /// Maps a resolved value to its ``ValueType`` (RTTS2).
    private static func valueType(of value: InternalLiveMapValue) -> ValueType {
        switch value {
        case .liveMap:
            .liveMap
        case .liveCounter:
            .liveCounter
        case .string:
            .string
        case .number:
            .number
        case .bool:
            .boolean
        case .data:
            .binary
        case .jsonArray:
            .jsonArray
        case .jsonObject:
            .jsonObject
        }
    }
}
