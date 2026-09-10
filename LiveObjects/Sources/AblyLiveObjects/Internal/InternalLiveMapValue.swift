import Foundation

/// The internal representation of a LiveMap value, with associated values of internal type.
internal enum InternalLiveMapValue: Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case data(Data)
    case jsonArray([JSONValue])
    case jsonObject([String: JSONValue])
    case liveMap(InternalDefaultLiveMap)
    case liveCounter(InternalDefaultLiveCounter)

    // MARK: - Construction from a public primitive

    /// 1:1 mapping of a public ``Primitive`` onto the internal representation. Used by the RTLM20e7
    /// `MAP_SET` value conversion and the RTLMV4d3–d7 blueprint-entry conversion.
    internal init(_ primitive: Primitive) {
        switch primitive {
        case let .string(value):
            self = .string(value)
        case let .number(value):
            self = .number(value)
        case let .bool(value):
            self = .bool(value)
        case let .data(value):
            self = .data(value)
        case let .jsonArray(value):
            self = .jsonArray(value)
        case let .jsonObject(value):
            self = .jsonObject(value)
        }
    }

    // MARK: - Representation in the Realtime protocol

    /// Converts an `InternalLiveMapValue` to the value that should be used when creating or updating a map entry in the Realtime protocol, per the rules of RTLMV4d and RTLM20e7.
    internal var nosync_toObjectData: ProtocolTypes.ObjectData {
        // RTLMV4d: Create an ObjectsMapEntry for the current value
        switch self {
        case let .bool(value):
            .init(boolean: value)
        case let .data(value):
            .init(bytes: value)
        case let .number(value):
            .init(number: NSNumber(value: value))
        case let .string(value):
            .init(string: value)
        case let .jsonArray(value):
            .init(json: .array(value))
        case let .jsonObject(value):
            .init(json: .object(value))
        case let .liveMap(liveMap):
            // RTLMV4d2: If the value is of type LiveMap, set ObjectsMapEntry.data.objectId to the objectId of that object
            .init(objectId: liveMap.objectID)
        case let .liveCounter(liveCounter):
            // RTLMV4d1: If the value is of type LiveCounter, set ObjectsMapEntry.data.objectId to the objectId of that object
            .init(objectId: liveCounter.objectID)
        }
    }

    // MARK: - Convenience getters for associated values

    /// If this `InternalLiveMapValue` has case `liveMap`, this returns the associated value. Else, it returns `nil`.
    internal var liveMapValue: InternalDefaultLiveMap? {
        if case let .liveMap(value) = self {
            return value
        }
        return nil
    }

    /// If this `InternalLiveMapValue` has case `liveCounter`, this returns the associated value. Else, it returns `nil`.
    internal var liveCounterValue: InternalDefaultLiveCounter? {
        if case let .liveCounter(value) = self {
            return value
        }
        return nil
    }

    /// If this `InternalLiveMapValue` has case `string`, this returns that value. Else, it returns `nil`.
    internal var stringValue: String? {
        if case let .string(value) = self {
            return value
        }
        return nil
    }

    /// If this `InternalLiveMapValue` has case `number`, this returns that value. Else, it returns `nil`.
    internal var numberValue: Double? {
        if case let .number(value) = self {
            return value
        }
        return nil
    }

    /// If this `InternalLiveMapValue` has case `bool`, this returns that value. Else, it returns `nil`.
    internal var boolValue: Bool? {
        if case let .bool(value) = self {
            return value
        }
        return nil
    }

    /// If this `InternalLiveMapValue` has case `data`, this returns that value. Else, it returns `nil`.
    internal var dataValue: Data? {
        if case let .data(value) = self {
            return value
        }
        return nil
    }

    /// If this `InternalLiveMapValue` has case `jsonArray`, this returns that value. Else, it returns `nil`.
    internal var jsonArrayValue: [JSONValue]? {
        if case let .jsonArray(value) = self {
            return value
        }
        return nil
    }

    /// If this `InternalLiveMapValue` has case `jsonObject`, this returns that value. Else, it returns `nil`.
    internal var jsonObjectValue: [String: JSONValue]? {
        if case let .jsonObject(value) = self {
            return value
        }
        return nil
    }

    // MARK: - Equatable Implementation

    internal static func == (lhs: InternalLiveMapValue, rhs: InternalLiveMapValue) -> Bool {
        switch (lhs, rhs) {
        case let (.string(lhsValue), .string(rhsValue)):
            lhsValue == rhsValue
        case let (.number(lhsValue), .number(rhsValue)):
            lhsValue == rhsValue
        case let (.bool(lhsValue), .bool(rhsValue)):
            lhsValue == rhsValue
        case let (.data(lhsValue), .data(rhsValue)):
            lhsValue == rhsValue
        case let (.jsonArray(lhsValue), .jsonArray(rhsValue)):
            lhsValue == rhsValue
        case let (.jsonObject(lhsValue), .jsonObject(rhsValue)):
            lhsValue == rhsValue
        case let (.liveMap(lhsMap), .liveMap(rhsMap)):
            lhsMap === rhsMap
        case let (.liveCounter(lhsCounter), .liveCounter(rhsCounter)):
            lhsCounter === rhsCounter
        default:
            false
        }
    }
}
