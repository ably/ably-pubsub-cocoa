import Ably

// MARK: - Instance (RTINS / RTTS9)

/// A direct-reference view of a `LiveObject` or primitive value.
///
/// Unlike ``PathObject``, which is path-addressed and re-resolves on each call, an `Instance` is
/// identity-addressed: it follows the specific object it was created with, regardless of where that
/// object sits in the graph.
///
/// An `Instance` is obtained from ``PathObject/instance()``. It is modelled as an **enum** so that
/// callers can exhaustively `switch` over the three instance kinds and obtain the correctly-typed
/// payload directly:
///
/// ```swift
/// switch instance {
/// case let .liveMap(map): …
/// case let .liveCounter(counter): …
/// case let .primitive(primitive): …
/// }
/// ```
///
/// > Note: This enum shape is a Swift-specific decision (chosen over the language-agnostic
/// > base-type + `as*`-cast model of spec `RTTS9`, so that discrimination is compile-time-exhaustive
/// > and there is no undefined mismatch path). Spec: `RTINS1`, `RTTS9`.
public enum Instance: Sendable {
    case liveMap(any LiveMapInstance)
    case liveCounter(any LiveCounterInstance)
    case primitive(any PrimitiveInstance)

    /// The type of the wrapped value. Spec: `RTTS8`.
    public var type: ValueType {
        switch self {
        case .liveMap:
            .liveMap
        case .liveCounter:
            .liveCounter
        case let .primitive(instance):
            instance.type
        }
    }

    /// Returns a JSON-serializable, recursively-compacted representation of the wrapped value.
    /// Spec: `RTINS11`, `RTINS11c` (never `nil`), `RTTS7a`.
    ///
    /// - Complexity: O(n) in the size of the wrapped value's subtree.
    public func compactJson() throws(ARTErrorInfo) -> JSONValue {
        switch self {
        case let .liveMap(instance):
            try instance.compactJson()
        case let .liveCounter(instance):
            try instance.compactJson()
        case let .primitive(instance):
            try instance.compactJson()
        }
    }
}

// MARK: - LiveMapInstance (RTINS / RTTS10, map subset)

/// An ``Instance`` payload exposing the members applicable when the wrapped value is a map.
/// Spec: `RTTS10`.
public protocol LiveMapInstance: Sendable {
    /// The `objectId` of the wrapped map. Spec: `RTINS3`.
    var id: String { get }

    /// Looks up `key` and returns an ``Instance`` wrapping the result, or `nil` if absent.
    /// Spec: `RTINS5`, `RTINS5c`.
    func get(key: String) throws(ARTErrorInfo) -> Instance?

    /// Returns an array of `[key, Instance]` pairs for the wrapped map. Spec: `RTINS6`.
    ///
    /// - Complexity: O(n) in the number of entries.
    func entries() throws(ARTErrorInfo) -> [(key: String, value: Instance)]

    /// Returns the keys of the wrapped map. Spec: `RTINS7`.
    ///
    /// - Complexity: O(n) in the number of entries.
    func keys() throws(ARTErrorInfo) -> [String]

    /// Returns an ``Instance`` for each value of the wrapped map. Spec: `RTINS8`.
    ///
    /// - Complexity: O(n) in the number of entries.
    func values() throws(ARTErrorInfo) -> [Instance]

    /// Returns the number of entries in the wrapped map. Spec: `RTTS10a`, `RTINS9`.
    ///
    /// Non-optional: an `Instance` is bound to an already-resolved map, so this always yields a value
    /// (`throws` only for the `RTO25` access-precondition check).
    var size: Int { get throws(ARTErrorInfo) }

    /// Sends an operation to set `key` to `value` on the wrapped map. Spec: `RTINS12`.
    func set(key: String, value: LiveMapValue) async throws(ARTErrorInfo)

    /// Sends an operation to remove `key` from the wrapped map. Spec: `RTINS13`.
    func remove(key: String) async throws(ARTErrorInfo)

    /// Registers a listener that is called each time the wrapped map is updated. Spec: `RTINS16`.
    @discardableResult
    func subscribe(listener: @escaping InstanceSubscriptionCallback) throws(ARTErrorInfo) -> any Subscription

    /// A JSON-serializable, recursively-compacted representation of the wrapped map.
    /// Spec: `RTINS11`, `RTINS11c` (never `nil`).
    ///
    /// - Complexity: O(n) in the size of the map's subtree.
    func compactJson() throws(ARTErrorInfo) -> JSONValue
}

// MARK: - LiveCounterInstance (RTINS / RTTS10, counter subset)

/// An ``Instance`` payload exposing the members applicable when the wrapped value is a counter.
/// Spec: `RTTS10`.
public protocol LiveCounterInstance: Sendable {
    /// The `objectId` of the wrapped counter. Spec: `RTINS3`.
    var id: String { get }

    /// The current value of the wrapped counter. Spec: `RTTS10b`, `RTINS4`.
    ///
    /// Non-optional: an `Instance` is bound to an already-resolved counter, so this always yields a
    /// value (`throws` only for the `RTO25` access-precondition check).
    var value: Double { get throws(ARTErrorInfo) }

    /// Sends an operation to increment the wrapped counter. Spec: `RTINS14`.
    func increment(amount: Double) async throws(ARTErrorInfo)

    /// Sends an operation to decrement the wrapped counter. Spec: `RTINS15`.
    func decrement(amount: Double) async throws(ARTErrorInfo)

    /// Registers a listener that is called each time the wrapped counter is updated. Spec: `RTINS16`.
    @discardableResult
    func subscribe(listener: @escaping InstanceSubscriptionCallback) throws(ARTErrorInfo) -> any Subscription

    /// A JSON-serializable, recursively-compacted representation of the wrapped counter.
    /// Spec: `RTINS11`, `RTINS11c` (never `nil`).
    func compactJson() throws(ARTErrorInfo) -> JSONValue
}

public extension LiveCounterInstance {
    /// Sends an operation to increment the wrapped counter by 1. Spec: `RTINS14`.
    func increment() async throws(ARTErrorInfo) {
        try await increment(amount: 1)
    }

    /// Sends an operation to decrement the wrapped counter by 1. Spec: `RTINS15`.
    func decrement() async throws(ARTErrorInfo) {
        try await decrement(amount: 1)
    }
}

// MARK: - PrimitiveInstance (RTINS / RTTS10, primitive subset)

/// An ``Instance`` payload exposing the members applicable when the wrapped value is a primitive.
/// Spec: `RTTS10`. (See ``Primitive`` for the note on collapsing the six spec primitive sub-types.)
public protocol PrimitiveInstance: Sendable {
    /// The wrapped primitive value. Spec: `RTTS10c`, `RTINS4`.
    ///
    /// Non-optional: an `Instance` is bound to an already-resolved primitive, so this always yields a
    /// value (`throws` only for the `RTO25` access-precondition check).
    var value: Primitive { get throws(ARTErrorInfo) }

    /// The specific primitive type of the wrapped value (e.g. ``ValueType/string``, ``ValueType/number``).
    /// Spec: `RTTS8`.
    var type: ValueType { get }

    /// A JSON-serializable representation of the wrapped primitive. Spec: `RTINS11`, `RTINS11c` (never `nil`).
    func compactJson() throws(ARTErrorInfo) -> JSONValue
}

/// Convenience accessors for a single expected primitive type.
///
/// Each of these reads ``PrimitiveInstance/value`` and then the correspondingly-named getter on the
/// resulting ``Primitive``, so `nil` means that the wrapped primitive is of a different case.
public extension PrimitiveInstance {
    /// If the wrapped primitive has case `string`, this returns the associated value. Else, it returns `nil`.
    var stringValue: String? {
        get throws(ARTErrorInfo) {
            try value.stringValue
        }
    }

    /// If the wrapped primitive has case `number`, this returns the associated value. Else, it returns `nil`.
    var numberValue: Double? {
        get throws(ARTErrorInfo) {
            try value.numberValue
        }
    }

    /// If the wrapped primitive has case `bool`, this returns the associated value. Else, it returns `nil`.
    var boolValue: Bool? {
        get throws(ARTErrorInfo) {
            try value.boolValue
        }
    }

    /// If the wrapped primitive has case `data`, this returns the associated value. Else, it returns `nil`.
    var dataValue: Data? {
        get throws(ARTErrorInfo) {
            try value.dataValue
        }
    }

    /// If the wrapped primitive has case `jsonArray`, this returns the associated value. Else, it returns `nil`.
    var jsonArrayValue: [JSONValue]? {
        get throws(ARTErrorInfo) {
            try value.jsonArrayValue
        }
    }

    /// If the wrapped primitive has case `jsonObject`, this returns the associated value. Else, it returns `nil`.
    var jsonObjectValue: [String: JSONValue]? {
        get throws(ARTErrorInfo) {
            try value.jsonObjectValue
        }
    }
}

// MARK: - AsyncSequence subscription variants

/// `AsyncStream`-based subscription for map instances.
public extension LiveMapInstance {
    /// Returns an `AsyncSequence` that emits an ``InstanceSubscriptionEvent`` each time the wrapped
    /// map is updated. The underlying subscription is removed when the stream is terminated.
    /// Spec: `RTINS16`.
    func events() throws(ARTErrorInfo) -> AsyncStream<InstanceSubscriptionEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: InstanceSubscriptionEvent.self)
        let subscription = try subscribe { event in
            continuation.yield(event)
        }
        continuation.onTermination = { _ in
            subscription.unsubscribe()
        }
        return stream
    }
}

/// `AsyncStream`-based subscription for counter instances.
public extension LiveCounterInstance {
    /// Returns an `AsyncSequence` that emits an ``InstanceSubscriptionEvent`` each time the wrapped
    /// counter is updated. The underlying subscription is removed when the stream is terminated.
    /// Spec: `RTINS16`.
    func events() throws(ARTErrorInfo) -> AsyncStream<InstanceSubscriptionEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: InstanceSubscriptionEvent.self)
        let subscription = try subscribe { event in
            continuation.yield(event)
        }
        continuation.onTermination = { _ in
            subscription.unsubscribe()
        }
        return stream
    }
}
