import Ably

// MARK: - PathObject (RTPO)

/// A lazy, path-based reference into the LiveObjects graph.
///
/// A `PathObject` stores a path (an ordered list of string segments) from the root map and resolves
/// it at the time each method is called. This means a `PathObject` survives object replacements: if
/// the object at a given path changes, the same `PathObject` will resolve to the new object on
/// subsequent calls.
///
/// A `PathObject` is obtained from ``RealtimeObject/get()``, which returns a ``LiveMapPathObject``
/// rooted at the channel's root map with an empty path. Further path objects are obtained by
/// navigating with ``LiveMapPathObject/get(key:)`` or ``LiveMapPathObject/at(path:)``.
///
/// `PathObject` is loosely typed. To obtain a view with the methods applicable to a particular
/// expected type, use ``asLiveMap()``, ``asLiveCounter()`` or ``asPrimitive()``. These do not
/// guarantee that the value actually at the path has that type; that can only be determined when the
/// value is evaluated (e.g. via `value()`), at which point `nil` is returned if the actual type
/// differs from the one requested. To discriminate the type before casting, use ``type()`` or
/// ``exists()``.
///
/// > Note: `PathObject`'s path-resolving accessors (``instance()``, ``compactJson()``, ``exists()``
/// > etc.) are exposed as **methods** (rather than properties) because each resolves the path at call
/// > time and is therefore O(path length) — see the Swift API Design Guidelines note on documenting
/// > non-O(1) computed properties. ``path`` is a property, since it is constant for a given
/// > `PathObject` and can be trivially cached.
///
/// Spec: `RTPO1`.
public protocol PathObject: Sendable {
    /// A dot-delimited string representation of the stored path segments. Dot characters
    /// occurring within individual segments are escaped with a backslash. An empty path (the root)
    /// is the empty string. Spec: `RTPO4`.
    var path: String { get }

    /// Resolves the path and returns an ``Instance`` wrapping the resolved value — whether that value
    /// is a `LiveObject` (RTPO8c) or a primitive (RTPO8f). Returns `nil` only if resolution fails
    /// (RTPO8e). Spec: `RTPO8`.
    func instance() throws(ARTErrorInfo) -> Instance?

    /// Resolves the path and returns a JSON-serializable, recursively-compacted representation of the
    /// resolved value, or `nil` if resolution fails. Spec: `RTPO14`.
    func compactJson() throws(ARTErrorInfo) -> JSONValue?

    /// Registers a listener that is called when the object at this path is updated.
    ///
    /// - Parameters:
    ///   - options: Subscription options, such as the nesting depth to observe.
    ///   - listener: The listener to call with a ``PathObjectSubscriptionEvent``.
    /// - Returns: A ``Subscription`` that allows the listener to be deregistered.
    /// Spec: `RTPO19`.
    @discardableResult
    func subscribe(options: PathObjectSubscriptionOptions?, listener: @escaping PathObjectSubscriptionCallback) throws(ARTErrorInfo) -> any Subscription

    /// Resolves the path and reports whether a value exists there. Spec: `RTTS4a`.
    func exists() throws(ARTErrorInfo) -> Bool

    /// Resolves the path and returns the ``ValueType`` of the value there, or `nil` if nothing
    /// resolves at the path. Spec: `RTTS4b`.
    func type() throws(ARTErrorInfo) -> ValueType?

    /// Returns a view of this path object typed as a ``LiveMapPathObject``. Purely a type refinement;
    /// it does not resolve the path and never throws on a type mismatch. Spec: `RTTS5a`.
    func asLiveMap() -> any LiveMapPathObject

    /// Returns a view of this path object typed as a ``LiveCounterPathObject``. Purely a type
    /// refinement; it does not resolve the path and never throws on a type mismatch. Spec: `RTTS5b`.
    func asLiveCounter() -> any LiveCounterPathObject

    /// Returns a view of this path object typed as a ``PrimitivePathObject``. Purely a type
    /// refinement; it does not resolve the path and never throws on a type mismatch. Spec: `RTTS5c`.
    func asPrimitive() -> any PrimitivePathObject
}

public extension PathObject {
    /// Registers a listener that is called when the object at this path is updated, using default
    /// options. Spec: `RTPO19`.
    @discardableResult
    func subscribe(listener: @escaping PathObjectSubscriptionCallback) throws(ARTErrorInfo) -> any Subscription {
        try subscribe(options: nil, listener: listener)
    }
}

/// `AsyncStream`-based subscription.
public extension PathObject {
    /// Returns an `AsyncSequence` that emits a ``PathObjectSubscriptionEvent`` each time the object at
    /// this path is updated. The underlying subscription is removed when the stream is terminated.
    /// Spec: `RTPO19`.
    func events(options: PathObjectSubscriptionOptions? = nil) throws(ARTErrorInfo) -> AsyncStream<PathObjectSubscriptionEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: PathObjectSubscriptionEvent.self)
        let subscription = try subscribe(options: options) { event in
            continuation.yield(event)
        }
        continuation.onTermination = { _ in
            subscription.unsubscribe()
        }
        return stream
    }
}

// MARK: - LiveMapPathObject (RTPO / RTTS6, map subset)

/// A ``PathObject`` view exposing the methods applicable when the value at the path is expected to be
/// a map. Spec: `RTTS6`.
public protocol LiveMapPathObject: PathObject {
    /// Returns a new ``PathObject`` with `key` appended to this object's path. Purely navigational;
    /// does not resolve the path. Spec: `RTPO5`.
    func get(key: String) -> any PathObject

    /// Returns a new ``PathObject`` with the parsed segments of the dot-delimited `path` appended to
    /// this object's path. Purely navigational; does not resolve the path. Spec: `RTPO6`.
    func at(path: String) -> any PathObject

    /// Resolves the path and, if it resolves to a map, returns an array of `[key, PathObject]` pairs.
    /// Returns an empty array if the resolved value is not a map or resolution fails. Spec: `RTPO9`.
    func entries() throws(ARTErrorInfo) -> [(key: String, value: any PathObject)]

    /// Resolves the path and, if it resolves to a map, returns its keys. Returns an empty array if
    /// the resolved value is not a map or resolution fails. Spec: `RTPO10`.
    func keys() throws(ARTErrorInfo) -> [String]

    /// Resolves the path and, if it resolves to a map, returns a ``PathObject`` for each value.
    /// Returns an empty array if the resolved value is not a map or resolution fails. Spec: `RTPO11`.
    func values() throws(ARTErrorInfo) -> [any PathObject]

    /// Resolves the path and, if it resolves to a map, returns the number of entries. Returns `nil`
    /// if the resolved value is not a map or resolution fails. Spec: `RTPO12`.
    func size() throws(ARTErrorInfo) -> Int?

    /// Sends an operation to set `key` to `value` on the map at this path. Spec: `RTPO15`.
    func set(key: String, value: LiveMapValue) async throws(ARTErrorInfo)

    /// Sends an operation to remove `key` from the map at this path. Spec: `RTPO16`.
    func remove(key: String) async throws(ARTErrorInfo)
}

// MARK: - LiveCounterPathObject (RTPO / RTTS6, counter subset)

/// A ``PathObject`` view exposing the methods applicable when the value at the path is expected to be
/// a counter. Spec: `RTTS6`.
public protocol LiveCounterPathObject: PathObject {
    /// Resolves the path and, if it resolves to a counter, returns its current value (per `RTPO7c`).
    /// Returns `nil` otherwise, including when resolution fails or the value is not a counter.
    /// Spec: `RTTS6b`.
    func value() throws(ARTErrorInfo) -> Double?

    /// Sends an operation to increment the counter at this path. Spec: `RTPO17`.
    ///
    /// - Parameter amount: The amount by which to increment.
    func increment(amount: Double) async throws(ARTErrorInfo)

    /// Sends an operation to decrement the counter at this path. Spec: `RTPO18`.
    ///
    /// - Parameter amount: The amount by which to decrement.
    func decrement(amount: Double) async throws(ARTErrorInfo)
}

public extension LiveCounterPathObject {
    /// Sends an operation to increment the counter at this path by 1. Spec: `RTPO17`.
    func increment() async throws(ARTErrorInfo) {
        try await increment(amount: 1)
    }

    /// Sends an operation to decrement the counter at this path by 1. Spec: `RTPO18`.
    func decrement() async throws(ARTErrorInfo) {
        try await decrement(amount: 1)
    }
}

// MARK: - PrimitivePathObject (RTPO / RTTS6, primitive subset)

/// A ``PathObject`` view exposing the methods applicable when the value at the path is expected to be
/// a primitive. Spec: `RTTS6`. (See ``Primitive`` for the note on collapsing the six spec primitive
/// sub-types.)
public protocol PrimitivePathObject: PathObject {
    /// Resolves the path and, if it resolves to a primitive, returns it (per `RTPO7d`). Returns `nil`
    /// if the resolved value is a `LiveObject` (`RTPO7e`) or resolution fails (`RTPO7f`). Spec:
    /// `RTTS6b`.
    func value() throws(ARTErrorInfo) -> Primitive?
}

/// Convenience accessors for a single expected primitive type.
///
/// Each of these resolves the path via ``PrimitivePathObject/value()`` and then reads the
/// correspondingly-named getter on the resulting ``Primitive``, so `nil` means either that nothing
/// primitive resolved at the path or that what did resolve was a primitive of a different case.
///
/// These are methods, not properties, for the same reason as the rest of ``PathObject``'s
/// path-resolving accessors: each resolves the path at call time and is therefore O(path length).
public extension PrimitivePathObject {
    /// If the value at this path is a `string` primitive, this returns the associated value. Else, it returns `nil`.
    func stringValue() throws(ARTErrorInfo) -> String? {
        try value()?.stringValue
    }

    /// If the value at this path is a `number` primitive, this returns the associated value. Else, it returns `nil`.
    func numberValue() throws(ARTErrorInfo) -> Double? {
        try value()?.numberValue
    }

    /// If the value at this path is a `bool` primitive, this returns the associated value. Else, it returns `nil`.
    func boolValue() throws(ARTErrorInfo) -> Bool? {
        try value()?.boolValue
    }

    /// If the value at this path is a `data` primitive, this returns the associated value. Else, it returns `nil`.
    func dataValue() throws(ARTErrorInfo) -> Data? {
        try value()?.dataValue
    }

    /// If the value at this path is a `jsonArray` primitive, this returns the associated value. Else, it returns `nil`.
    func jsonArrayValue() throws(ARTErrorInfo) -> [JSONValue]? {
        try value()?.jsonArrayValue
    }

    /// If the value at this path is a `jsonObject` primitive, this returns the associated value. Else, it returns `nil`.
    func jsonObjectValue() throws(ARTErrorInfo) -> [String: JSONValue]? {
        try value()?.jsonObjectValue
    }
}
