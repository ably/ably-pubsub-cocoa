import Foundation

/// Like ``JSONValue``, but provides a flexible `number` case and an additional case named `extra`, which allows you to support additional types of data. It's used as a common base for the implementations of ``JSONValue`` and ``WireValue``, and for converting between them.
internal indirect enum ExtendedJSONValue<Number, Extra> {
    case object([String: Self])
    case array([Self])
    case string(String)
    case number(Number)
    case bool(Bool)
    case null
    case extra(Extra)
}

// MARK: - Bridging with Foundation

internal extension ExtendedJSONValue {
    /// Creates an `ExtendedJSONValue` from an object.
    ///
    /// The rules for what `deserialized` will accept are the same as those of `JSONValue.init(jsonSerializationOutput)`, with one addition: any nonsupported values are passed to the `createExtraValue` function, and the result of this function will be used to create an `ExtendedJSONValue` of case `.extra`.
    init(deserialized: Any, createNumberValue: (NSNumber) -> Number, createExtraValue: (Any) -> Extra) {
        switch deserialized {
        case let dictionary as [String: Any]:
            self = .object(dictionary.mapValues { .init(deserialized: $0, createNumberValue: createNumberValue, createExtraValue: createExtraValue) })
        case let array as [Any]:
            self = .array(array.map { .init(deserialized: $0, createNumberValue: createNumberValue, createExtraValue: createExtraValue) })
        case let string as String:
            self = .string(string)
        case let number as NSNumber:
            // We need to be careful to distinguish booleans from numbers of value 0 or 1; technique taken from https://forums.swift.org/t/jsonserialization-turns-bool-value-to-nsnumber/31909/3
            if number === kCFBooleanTrue {
                self = .bool(true)
            } else if number === kCFBooleanFalse {
                self = .bool(false)
            } else {
                self = .number(createNumberValue(number))
            }
        case is NSNull:
            self = .null
        default:
            self = .extra(createExtraValue(deserialized))
        }
    }

    /// Converts an `ExtendedJSONValue` to an object.
    ///
    /// The contract for what this will return are the same as those of `JSONValue.toJSONSerializationInputElement`, with one addition: any values in the input of case `.extra` will be passed to the `serializeExtraValue` function, and the result of this function call will be inserted into the output object.
    func serialized(serializeNumberValue: (Number) -> Any, serializeExtraValue: (Extra) -> Any) -> Any {
        switch self {
        case let .object(underlying):
            underlying.mapValues { $0.serialized(serializeNumberValue: serializeNumberValue, serializeExtraValue: serializeExtraValue) }
        case let .array(underlying):
            underlying.map { $0.serialized(serializeNumberValue: serializeNumberValue, serializeExtraValue: serializeExtraValue) }
        case let .string(underlying):
            underlying
        case let .number(underlying):
            serializeNumberValue(underlying)
        case let .bool(underlying):
            underlying
        case .null:
            NSNull()
        case let .extra(extra):
            serializeExtraValue(extra)
        }
    }
}

// MARK: - Transforming the extra data

internal extension ExtendedJSONValue {
    /// Converts this `ExtendedJSONValue<Number, Extra>` to an `ExtendedJSONValue<NewNumber, NewExtra>` using given transformations.
    func map<NewNumber, NewExtra, Failure>(number transformNumber: @escaping (Number) throws(Failure) -> NewNumber, extra transformExtra: @escaping (Extra) throws(Failure) -> NewExtra) throws(Failure) -> ExtendedJSONValue<NewNumber, NewExtra> {
        switch self {
        case let .object(underlying):
            try .object(underlying.ablyLiveObjects_mapValuesWithTypedThrow { value throws(Failure) in
                try value.map(number: transformNumber, extra: transformExtra)
            })
        case let .array(underlying):
            try .array(underlying.map { element throws(Failure) in
                try element.map(number: transformNumber, extra: transformExtra)
            })
        case let .string(underlying):
            .string(underlying)
        case let .number(underlying):
            try .number(transformNumber(underlying))
        case let .bool(underlying):
            .bool(underlying)
        case .null:
            .null
        case let .extra(extra):
            try .extra(transformExtra(extra))
        }
    }
}
