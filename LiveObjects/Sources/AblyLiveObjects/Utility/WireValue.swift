import Ably
import Foundation

/// A wire value that can be represents the kinds of data that we expect to find inside a deserialized wire object received from `_AblyPluginSupportPrivate`, or which we may put inside a serialized wire object that we send to `_AblyPluginSupportPrivate`.
///
/// Its cases are a superset of those of ``JSONValue``, adding a further `data` case for binary data (we expect to be able to send and receive binary data in the case where ably-cocoa is using the MessagePack format). Also, its `number` case is `NSNumber` instead of `Double`, to allow us to communicate to ably-cocoa's MessagePack encoder that it should encode certain values (e.g. enums) as integers, not doubles.
internal indirect enum WireValue: Sendable, Equatable {
    case object([String: WireValue])
    case array([WireValue])
    case string(String)
    case number(NSNumber)
    case bool(Bool)
    case null
    case data(Data)

    // MARK: - Convenience getters for associated values

    /// If this `WireValue` has case `object`, this returns the associated value. Else, it returns `nil`.
    internal var objectValue: [String: WireValue]? {
        if case let .object(objectValue) = self {
            objectValue
        } else {
            nil
        }
    }

    /// If this `WireValue` has case `array`, this returns the associated value. Else, it returns `nil`.
    internal var arrayValue: [WireValue]? {
        if case let .array(arrayValue) = self {
            arrayValue
        } else {
            nil
        }
    }

    /// If this `WireValue` has case `string`, this returns the associated value. Else, it returns `nil`.
    internal var stringValue: String? {
        if case let .string(stringValue) = self {
            stringValue
        } else {
            nil
        }
    }

    /// If this `WireValue` has case `number`, this returns the associated value. Else, it returns `nil`.
    internal var numberValue: NSNumber? {
        if case let .number(numberValue) = self {
            numberValue
        } else {
            nil
        }
    }

    /// If this `WireValue` has case `bool`, this returns the associated value. Else, it returns `nil`.
    internal var boolValue: Bool? {
        if case let .bool(boolValue) = self {
            boolValue
        } else {
            nil
        }
    }

    /// If this `WireValue` has case `data`, this returns the associated value. Else, it returns `nil`.
    internal var dataValue: Data? {
        if case let .data(dataValue) = self {
            dataValue
        } else {
            nil
        }
    }

    /// Returns true if and only if this `WireValue` has case `null`.
    internal var isNull: Bool {
        if case .null = self {
            true
        } else {
            false
        }
    }
}

extension WireValue: ExpressibleByDictionaryLiteral {
    internal init(dictionaryLiteral elements: (String, WireValue)...) {
        self = .object(.init(uniqueKeysWithValues: elements))
    }
}

extension WireValue: ExpressibleByArrayLiteral {
    internal init(arrayLiteral elements: WireValue...) {
        self = .array(elements)
    }
}

extension WireValue: ExpressibleByStringLiteral {
    internal init(stringLiteral value: String) {
        self = .string(value)
    }
}

extension WireValue: ExpressibleByIntegerLiteral {
    internal init(integerLiteral value: Int) {
        self = .number(value as NSNumber)
    }
}

extension WireValue: ExpressibleByFloatLiteral {
    internal init(floatLiteral value: Double) {
        self = .number(value as NSNumber)
    }
}

extension WireValue: ExpressibleByBooleanLiteral {
    internal init(booleanLiteral value: Bool) {
        self = .bool(value)
    }
}

// MARK: - Bridging with ably-cocoa

internal extension WireValue {
    /// Creates a `WireValue` from an `_AblyPluginSupportPrivate` deserialized wire object.
    ///
    /// Specifically, `pluginSupportData` can be a value that was passed to `LiveObjectsPlugin.decodeObjectMessage:…`.
    init(pluginSupportData: Any) {
        let extendedJSONValue = ExtendedJSONValue<NSNumber, ExtraValue>(deserialized: pluginSupportData, createNumberValue: { $0 }, createExtraValue: { deserializedExtraValue in
            // We support binary data (used for MessagePack format) in addition to JSON values
            if let data = deserializedExtraValue as? Data {
                return .data(data)
            }

            // ably-cocoa is not conforming to our assumptions; our assumptions are probably wrong. Either way, bring this loudly to our attention instead of trying to carry on
            preconditionFailure("WireValue(pluginSupportData:) was given unsupported value \(deserializedExtraValue)")
        })

        self.init(extendedJSONValue: extendedJSONValue)
    }

    /// Creates a `WireValue` from an `_AblyPluginSupportPrivate` deserialized wire object. Specifically, `pluginSupportData` can be a value that was passed to `LiveObjectsPlugin.decodeObjectMessage:…`.
    static func objectFromPluginSupportData(_ pluginSupportData: [String: Any]) -> [String: WireValue] {
        let wireValue = WireValue(pluginSupportData: pluginSupportData)
        guard case let .object(wireObject) = wireValue else {
            preconditionFailure()
        }

        return wireObject
    }

    /// Creates an `_AblyPluginSupportPrivate` deserialized wire object from a `WireValue`.
    ///
    /// Used by `[String: WireValue].toPluginSupportDataDictionary`.
    var toPluginSupportData: Any {
        toExtendedJSONValue.serialized(serializeNumberValue: { $0 }, serializeExtraValue: { extendedValue in
            switch extendedValue {
            case let .data(data):
                data
            }
        })
    }
}

internal extension [String: WireValue] {
    /// Creates an `_AblyPluginSupportPrivate` deserialized wire object from a dictionary that has string keys and `WireValue` values.
    ///
    /// Specifically, the value of this property can be returned from `APLiveObjectsPlugin.encodeObjectMessage:`.
    var toPluginSupportDataDictionary: [String: Any] {
        mapValues(\.toPluginSupportData)
    }
}

// MARK: - Conversion to/from ExtendedJSONValue

internal extension WireValue {
    enum ExtraValue {
        case data(Data)
    }

    init(extendedJSONValue: ExtendedJSONValue<NSNumber, ExtraValue>) {
        switch extendedJSONValue {
        case let .object(underlying):
            self = .object(underlying.mapValues { .init(extendedJSONValue: $0) })
        case let .array(underlying):
            self = .array(underlying.map { .init(extendedJSONValue: $0) })
        case let .string(underlying):
            self = .string(underlying)
        case let .number(underlying):
            self = .number(underlying)
        case let .bool(underlying):
            self = .bool(underlying)
        case .null:
            self = .null
        case let .extra(extra):
            switch extra {
            case let .data(data):
                self = .data(data)
            }
        }
    }

    var toExtendedJSONValue: ExtendedJSONValue<NSNumber, ExtraValue> {
        switch self {
        case let .object(underlying):
            .object(underlying.mapValues(\.toExtendedJSONValue))
        case let .array(underlying):
            .array(underlying.map(\.toExtendedJSONValue))
        case let .string(underlying):
            .string(underlying)
        case let .number(underlying):
            .number(underlying)
        case let .bool(underlying):
            .bool(underlying)
        case .null:
            .null
        case let .data(data):
            .extra(.data(data))
        }
    }
}

// MARK: - Conversion to/from JSONValue

internal extension WireValue {
    /// Converts a `JSONValue` to its corresponding `WireValue`.
    init(jsonValue: JSONValue) {
        self.init(extendedJSONValue: jsonValue.toExtendedJSONValue.map(number: { (number: Double) -> NSNumber in
            number as NSNumber
        }, extra: { (extra: Never) in extra }))
    }

    enum ConversionError: Error {
        case dataCannotBeConvertedToJSONValue
    }

    /// Tries to convert this `WireValue` to its corresponding `JSONValue`.
    ///
    /// - Throws: `ConversionError.dataCannotBeConvertedToJSONValue` if `WireValue` represents binary data.
    var toJSONValue: JSONValue {
        get throws(ARTErrorInfo) {
            let neverExtended = try toExtendedJSONValue.map(number: { (number: NSNumber) throws(ARTErrorInfo) -> Double in
                // art_doubleValue: an inbound WireValue's numbers are as JSON decoded them
                number.art_doubleValue
            }, extra: { (extra: ExtraValue) throws(ARTErrorInfo) -> Never in
                switch extra {
                case .data:
                    throw ConversionError.dataCannotBeConvertedToJSONValue.toARTErrorInfo()
                }
            })

            return .init(extendedJSONValue: neverExtended)
        }
    }
}
