import Ably
import Foundation

/// Default implementation of ``LiveMapInstance``, bound to a specific
/// ``InternalDefaultLiveMap`` (RTINS2a). Spec: `RTINS1`, `RTTS10a`.
internal final class DefaultLiveMapInstance: LiveMapInstance {
    private let node: InternalDefaultLiveMap
    private let coreSDK: CoreSDK
    private let realtimeObjects: any InternalRealtimeObjectsProtocol
    private let internalQueue: DispatchQueue

    /// The wrapped map's `objectId` (RTINS3a).
    internal let id: String

    internal init(
        node: InternalDefaultLiveMap,
        coreSDK: CoreSDK,
        realtimeObjects: any InternalRealtimeObjectsProtocol,
        internalQueue: DispatchQueue,
    ) {
        self.node = node
        self.coreSDK = coreSDK
        self.realtimeObjects = realtimeObjects
        self.internalQueue = internalQueue
        // RTINS3a: the node's objectId is immutable (set at construction), so it is read directly.
        id = node.objectID
    }

    // MARK: - LiveMapInstance

    internal func get(key: String) throws(ARTErrorInfo) -> Instance? {
        // RTINS5b (the node accessor runs the RTO25b check), RTINS5c
        guard let value = try node.get(key: key, coreSDK: coreSDK, delegate: realtimeObjects) else {
            // RTINS5c: an absent/dangling result stays nil
            return nil
        }
        return Instance.from(internalValue: value, coreSDK: coreSDK, realtimeObjects: realtimeObjects, internalQueue: internalQueue)
    }

    internal func entries() throws(ARTErrorInfo) -> [(key: String, value: Instance)] {
        // RTINS6b: delegate to the node's entries (tombstoned/dangling entries already excluded) and
        // wrap each value in an Instance.
        try node.entries(coreSDK: coreSDK, delegate: realtimeObjects).map { key, value in
            (key: key, value: Instance.from(internalValue: value, coreSDK: coreSDK, realtimeObjects: realtimeObjects, internalQueue: internalQueue))
        }
    }

    internal func keys() throws(ARTErrorInfo) -> [String] {
        // RTINS7b -> RTLM12
        try node.keys(coreSDK: coreSDK, delegate: realtimeObjects)
    }

    internal func values() throws(ARTErrorInfo) -> [Instance] {
        // RTINS8b: the values of the entries
        try entries().map(\.value)
    }

    internal var size: Int {
        get throws(ARTErrorInfo) {
            // RTINS9b -> RTLM10d
            try node.size(coreSDK: coreSDK, delegate: realtimeObjects)
        }
    }

    internal func set(key: String, value: LiveMapValue) async throws(ARTErrorInfo) {
        // RTINS12c -> RTLM20: delegate straight to the node's set, which handles both primitive values
        // and LiveMap/LiveCounter blueprints (evaluating a blueprint and publishing its *_CREATE
        // messages atomically with the MAP_SET, per RTLM20e7g/RTLM20h1).
        try await node.set(key: key, value: value, coreSDK: coreSDK, realtimeObjects: realtimeObjects)
    }

    internal func remove(key: String) async throws(ARTErrorInfo) {
        // RTINS13c -> RTLM21
        try await node.remove(key: key, coreSDK: coreSDK, realtimeObjects: realtimeObjects)
    }

    @discardableResult
    internal func subscribe(listener: @escaping InstanceSubscriptionCallback) throws(ARTErrorInfo) -> any Subscription {
        // RTINS16b (the node's subscribe runs the RTO25b check), RTINS16d -> RTLO4b
        let response = try node.subscribe(
            listener: { [weak self] update, _ in
                guard let self else {
                    return
                }
                // RTINS16e1: an Instance wrapping this map (identity-based, RTINS16g).
                // RTINS16e2: project the stored internal source message to the public message per
                // PAOM3 at this delivery boundary (nil for sync-originated updates).
                listener(.init(object: .liveMap(self), message: update.objectMessage?.toPublicObjectMessage(channelName: coreSDK.channelName)))
            },
            coreSDK: coreSDK,
        )
        // RTINS16f
        return DefaultSubscription(response: response)
    }

    internal func compactJson() throws(ARTErrorInfo) -> JSONValue {
        // RTINS11a/RTINS11b -> RTPO14: recursive compaction with cycle markers (see the helper).
        var visited: Set<String> = []
        return try Self.compactJson(
            mapNode: node,
            objectID: id,
            coreSDK: coreSDK,
            delegate: realtimeObjects,
            visited: &visited,
        )
    }

    // MARK: - compactJson (RTPO13c / RTPO14b)

    /// Recursively compacts a map node to a JSON-serializable ``JSONValue`` object.
    ///
    /// Cycle handling: a visited object id is added
    /// **before** iterating and never removed, so a map referenced twice on sibling branches yields the
    /// marker on the second sibling too. A cycle is emitted as a single-property object
    /// `{"objectId": <id>}` — the **RTPO14b2** marker format (distinct from RTPO13c5's in-memory-reference
    /// form, which is not JSON-serializable). Spec: `RTPO13c`, `RTPO14b`, `RTPO14b1`, `RTPO14b2`.
    private static func compactJson(
        mapNode: InternalDefaultLiveMap,
        objectID: String,
        coreSDK: CoreSDK,
        delegate: any InternalRealtimeObjectsProtocol,
        visited: inout Set<String>,
    ) throws(ARTErrorInfo) -> JSONValue {
        // RTPO14b2 parity: mark this map visited before descending.
        visited.insert(objectID)
        var result: [String: JSONValue] = [:]
        // RTPO13c1: tombstoned (and dangling) entries are already excluded by `entries`.
        for (key, value) in try mapNode.entries(coreSDK: coreSDK, delegate: delegate) {
            switch value {
            case let .liveMap(childNode):
                let childID = childNode.objectID
                if visited.contains(childID) {
                    // RTPO14b2: cyclic reference -> {"objectId": <id>}
                    result[key] = .object(["objectId": .string(childID)])
                } else {
                    // RTPO13c2: recurse into nested maps
                    result[key] = try compactJson(
                        mapNode: childNode,
                        objectID: childID,
                        coreSDK: coreSDK,
                        delegate: delegate,
                        visited: &visited,
                    )
                }
            case let .liveCounter(childNode):
                // RTPO13c3: nested counters resolve to their numeric value
                result[key] = try .number(childNode.value(coreSDK: coreSDK))
            case let .string(primitiveValue):
                // RTPO13c4 (and RTPO14b1 for binary): primitives included as-is
                result[key] = .string(primitiveValue)
            case let .number(primitiveValue):
                result[key] = .number(primitiveValue)
            case let .bool(primitiveValue):
                result[key] = .bool(primitiveValue)
            case let .data(primitiveValue):
                // RTPO14b1: binary encoded as base64 string
                result[key] = .string(primitiveValue.base64EncodedString())
            case let .jsonArray(primitiveValue):
                result[key] = .array(primitiveValue)
            case let .jsonObject(primitiveValue):
                result[key] = .object(primitiveValue)
            }
        }
        return .object(result)
    }
}

// MARK: - Instance construction seam (`PathObject.instance()`)

internal extension Instance {
    /// Builds the identity-addressed ``Instance`` wrapping a resolved map-entry value (RTINS2a).
    /// This is the seam the path layer's `PathObject.instance()` calls once it has
    /// resolved a value. Because `InternalLiveMapValue` cannot be an unknown/unrepresentable type, this
    /// is non-optional — a `nil` at an unresolved path is represented by the caller returning `nil`.
    static func from(
        internalValue: InternalLiveMapValue,
        coreSDK: CoreSDK,
        realtimeObjects: any InternalRealtimeObjectsProtocol,
        internalQueue: DispatchQueue,
    ) -> Instance {
        switch internalValue {
        case let .liveMap(node):
            .liveMap(DefaultLiveMapInstance(node: node, coreSDK: coreSDK, realtimeObjects: realtimeObjects, internalQueue: internalQueue))
        case let .liveCounter(node):
            .liveCounter(DefaultLiveCounterInstance(node: node, coreSDK: coreSDK, realtimeObjects: realtimeObjects, internalQueue: internalQueue))
        case let .string(value):
            .primitive(DefaultPrimitiveInstance(value: .string(value), type: .string, coreSDK: coreSDK, internalQueue: internalQueue))
        case let .number(value):
            .primitive(DefaultPrimitiveInstance(value: .number(value), type: .number, coreSDK: coreSDK, internalQueue: internalQueue))
        case let .bool(value):
            .primitive(DefaultPrimitiveInstance(value: .bool(value), type: .boolean, coreSDK: coreSDK, internalQueue: internalQueue))
        case let .data(value):
            .primitive(DefaultPrimitiveInstance(value: .data(value), type: .binary, coreSDK: coreSDK, internalQueue: internalQueue))
        case let .jsonArray(value):
            .primitive(DefaultPrimitiveInstance(value: .jsonArray(value), type: .jsonArray, coreSDK: coreSDK, internalQueue: internalQueue))
        case let .jsonObject(value):
            .primitive(DefaultPrimitiveInstance(value: .jsonObject(value), type: .jsonObject, coreSDK: coreSDK, internalQueue: internalQueue))
        }
    }

    /// Builds the identity-addressed ``Instance`` wrapping an ``ObjectsPool`` entry — a directly
    /// referenced `LiveObject` (e.g. the root map, or an `objectId`-resolved object). This is the
    /// seam for resolving a path to a concrete object rather than a map-entry value.
    static func from(
        poolEntry: ObjectsPool.Entry,
        coreSDK: CoreSDK,
        realtimeObjects: any InternalRealtimeObjectsProtocol,
        internalQueue: DispatchQueue,
    ) -> Instance {
        switch poolEntry {
        case let .map(node):
            .liveMap(DefaultLiveMapInstance(node: node, coreSDK: coreSDK, realtimeObjects: realtimeObjects, internalQueue: internalQueue))
        case let .counter(node):
            .liveCounter(DefaultLiveCounterInstance(node: node, coreSDK: coreSDK, realtimeObjects: realtimeObjects, internalQueue: internalQueue))
        }
    }
}
