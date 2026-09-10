import Ably
import Foundation

// MARK: - ValueType

/// Identifies the type of the value at a path or wrapped by an ``Instance``. Spec: `RTTS2`.
///
/// Used by ``PathObject/type()`` to discriminate a path's resolved type before casting, and by
/// ``PrimitiveInstance/type`` / ``Instance/type`` to identify the wrapped value's type.
///
/// > Note: the spec name for this type is `ValueType` (`RTTS2`). A rename to `TypeOfValue` has been
/// > suggested on specification #491 but is not yet decided; this SDK follows the current spec name.
public enum ValueType: Sendable, Equatable {
    case string
    case number
    case boolean
    case binary
    case jsonObject
    case jsonArray
    case liveMap
    case liveCounter
    /// The resolved value has an unrecognised type. Spec: `RTTS2`.
    case unknown
}

// MARK: - Primitive

/// Represents a primitive value that can be stored at a path in the LiveObjects graph.
///
/// A ``PrimitivePathObject`` or ``PrimitiveInstance`` resolves to a `Primitive` when its
/// ``PrimitivePathObject/value()`` (resp. ``PrimitiveInstance/value``) is read and the underlying
/// value is in fact a primitive.
///
/// > Note: **Deliberate divergence from `RTTS6c`/`RTTS10c`.** The spec defines six separate primitive
/// > path-object and instance sub-types (`StringPathObject`, `NumberPathObject`, … / `StringInstance`,
/// > `NumberInstance`, …), each with a type-filtered `value`. This SDK instead collapses them into a
/// > single ``PrimitivePathObject``/``PrimitiveInstance`` that resolves to this `Primitive` enum,
/// > which callers pattern-match. This is a Swift-idiomatic consolidation agreed for this SDK; it
/// > means `value` returns whatever primitive resolved rather than being pre-filtered to one type.
public enum Primitive: Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case data(Data)
    case jsonArray([JSONValue])
    case jsonObject([String: JSONValue])
}

// MARK: - Primitive convenience getters for associated values

/// These back the same-named accessors on ``PrimitivePathObject`` and ``PrimitiveInstance``, which is
/// how callers outside the SDK reach them; on a `Primitive` in hand, `switch` over the cases.
internal extension Primitive {
    /// If this `Primitive` has case `string`, this returns the associated value. Else, it returns `nil`.
    var stringValue: String? {
        if case let .string(value) = self {
            return value
        }
        return nil
    }

    /// If this `Primitive` has case `number`, this returns the associated value. Else, it returns `nil`.
    var numberValue: Double? {
        if case let .number(value) = self {
            return value
        }
        return nil
    }

    /// If this `Primitive` has case `bool`, this returns the associated value. Else, it returns `nil`.
    var boolValue: Bool? {
        if case let .bool(value) = self {
            return value
        }
        return nil
    }

    /// If this `Primitive` has case `data`, this returns the associated value. Else, it returns `nil`.
    var dataValue: Data? {
        if case let .data(value) = self {
            return value
        }
        return nil
    }

    /// If this `Primitive` has case `jsonArray`, this returns the associated value. Else, it returns `nil`.
    var jsonArrayValue: [JSONValue]? {
        if case let .jsonArray(value) = self {
            return value
        }
        return nil
    }

    /// If this `Primitive` has case `jsonObject`, this returns the associated value. Else, it returns `nil`.
    var jsonObjectValue: [String: JSONValue]? {
        if case let .jsonObject(value) = self {
            return value
        }
        return nil
    }
}

// MARK: - LiveCounter (value type, RTLCV)

/// A value type describing a new `LiveCounter` to be created, for use as a value passed to
/// ``LiveMapPathObject/set(key:value:)`` (or the equivalent on ``LiveMapInstance``).
///
/// This is **not** a live, synchronized counter; it is a lightweight, local description of the
/// counter to create. The live counter is created on the Ably system when this value is set into the
/// graph. Spec: `RTLCV`.
public struct LiveCounter: Sendable, Equatable {
    /// The initial count for the counter. Spec: `RTLCV2a`.
    internal let count: Double

    private init(count: Double) {
        self.count = count
    }

    /// Creates a new `LiveCounter` value type with the provided initial count.
    ///
    /// - Parameter initialCount: The initial value for the new counter.
    /// Spec: `RTLCV3`.
    public static func create(initialCount: Double) -> LiveCounter {
        .init(count: initialCount)
    }

    /// Creates a new `LiveCounter` value type with an initial count of zero.
    /// Spec: `RTLCV3`.
    public static func create() -> LiveCounter {
        .init(count: 0)
    }
}

// MARK: - LiveMap (value type, RTLMV)

/// A value type describing a new `LiveMap` to be created, for use as a value passed to
/// ``LiveMapPathObject/set(key:value:)`` (or the equivalent on ``LiveMapInstance``).
///
/// This is **not** a live, synchronized map; it is a lightweight, local description of the map to
/// create. The live map is created on the Ably system when this value is set into the graph.
/// Spec: `RTLMV`.
public struct LiveMap: Sendable, Equatable {
    /// The initial entries for the map. Spec: `RTLMV2a`.
    internal let entries: [String: LiveMapValue]?

    private init(entries: [String: LiveMapValue]?) {
        self.entries = entries
    }

    /// Creates a new `LiveMap` value type with the provided initial entries.
    ///
    /// - Parameter entries: The initial entries for the new map.
    /// Spec: `RTLMV3`.
    public static func create(entries: [String: LiveMapValue]) -> LiveMap {
        .init(entries: entries)
    }

    /// Creates a new empty `LiveMap` value type.
    /// Spec: `RTLMV3`.
    public static func create() -> LiveMap {
        .init(entries: nil)
    }
}

// MARK: - LiveMapValue

/// Represents the type of data that can be stored for a given key in a map, when *writing* to the
/// graph via ``LiveMapPathObject/set(key:value:)`` or ``LiveMapInstance/set(key:value:)``.
///
/// It may be a primitive value (string, number, boolean, binary data, JSON array, or JSON object),
/// or a new ``LiveMap``/``LiveCounter`` value type to be created.
///
/// `LiveMapValue` implements Swift's `ExpressibleBy*Literal` protocols. This, in combination with
/// `JSONValue`'s conformance to these protocols, allows you to write type-safe map values using
/// familiar syntax. For example:
///
/// ```swift
/// try await root.asLiveMap().set(key: "someStringKey", value: "someString")
/// try await root.asLiveMap().set(key: "someJSONObjectKey", value: [
///     "someNestedJSONObjectKey": [
///         "someOtherKey": "someOtherValue",
///     ],
/// ])
/// ```
///
/// Spec: `RTTS11` — the typed public write-value type carrying the map set-value union
/// (`Boolean | Binary | Number | String | JsonArray | JsonObject | LiveCounter | LiveMap`) accepted by
/// `set`. `RTTS11a` names Swift's idiomatic realisation: an enum with literal conformances (below).
public enum LiveMapValue: Sendable, Equatable {
    /// A primitive value (string, number, boolean, binary data, JSON array, or JSON object).
    case primitive(Primitive)
    case liveMap(LiveMap)
    case liveCounter(LiveCounter)

    // MARK: - Convenience getters for associated values

    /// If this `LiveMapValue` has case `primitive`, this returns the associated value. Else, it returns `nil`.
    public var primitiveValue: Primitive? {
        if case let .primitive(value) = self {
            return value
        }
        return nil
    }

    /// If this `LiveMapValue` has case `liveMap`, this returns the associated value. Else, it returns `nil`.
    public var liveMapValue: LiveMap? {
        if case let .liveMap(value) = self {
            return value
        }
        return nil
    }

    /// If this `LiveMapValue` has case `liveCounter`, this returns the associated value. Else, it returns `nil`.
    public var liveCounterValue: LiveCounter? {
        if case let .liveCounter(value) = self {
            return value
        }
        return nil
    }
}

// MARK: - ExpressibleBy*Literal conformances

extension LiveMapValue: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .primitive(.jsonObject(.init(uniqueKeysWithValues: elements)))
    }
}

extension LiveMapValue: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: JSONValue...) {
        self = .primitive(.jsonArray(elements))
    }
}

extension LiveMapValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = .primitive(.string(value))
    }
}

extension LiveMapValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self = .primitive(.number(Double(value)))
    }
}

extension LiveMapValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self = .primitive(.number(value))
    }
}

extension LiveMapValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        self = .primitive(.bool(value))
    }
}
