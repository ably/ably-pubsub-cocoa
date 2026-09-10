import Ably
import Foundation

internal protocol WireEncodable {
    var toWireValue: WireValue { get }
}

internal protocol WireDecodable {
    init(wireValue: WireValue) throws(ARTErrorInfo)
}

internal typealias WireCodable = WireDecodable & WireEncodable

internal protocol WireObjectEncodable: WireEncodable {
    var toWireObject: [String: WireValue] { get }
}

// Default implementation of `WireEncodable` conformance for `WireObjectEncodable`
internal extension WireObjectEncodable {
    var toWireValue: WireValue {
        .object(toWireObject)
    }
}

internal protocol WireObjectDecodable: WireDecodable {
    init(wireObject: [String: WireValue]) throws(ARTErrorInfo)
}

internal enum WireValueDecodingError: Error {
    case valueIsNotObject
    case noValueForKey(String)
    case wrongTypeForKey(String, actualValue: WireValue)
    case failedToDecodeFromRawValue(String)
}

// Default implementation of `WireDecodable` conformance for `WireObjectDecodable`
internal extension WireObjectDecodable {
    init(wireValue: WireValue) throws(ARTErrorInfo) {
        guard case let .object(wireObject) = wireValue else {
            throw WireValueDecodingError.valueIsNotObject.toARTErrorInfo()
        }

        self = try .init(wireObject: wireObject)
    }
}

internal typealias WireObjectCodable = WireObjectDecodable & WireObjectEncodable

// MARK: - Extracting primitive values from a dictionary

/// This extension adds some helper methods for extracting values from a dictionary of `WireValue` values; you may find them helpful when implementing `WireCodable`.
internal extension [String: WireValue] {
    /// If this dictionary contains a value for `key`, and this value has case `object`, this returns the associated value.
    ///
    /// - Throws:
    ///   - `WireValueDecodingError.noValueForKey` if the key is absent
    ///   - `WireValueDecodingError.wrongTypeForKey` if the value does not have case `object`
    func objectValueForKey(_ key: String) throws(ARTErrorInfo) -> [String: WireValue] {
        guard let value = self[key] else {
            throw WireValueDecodingError.noValueForKey(key).toARTErrorInfo()
        }

        guard case let .object(objectValue) = value else {
            throw WireValueDecodingError.wrongTypeForKey(key, actualValue: value).toARTErrorInfo()
        }

        return objectValue
    }

    /// If this dictionary contains a value for `key`, and this value has case `object`, this returns the associated value. If this dictionary does not contain a value for `key`, or if the value for `key` has case `null`, it returns `nil`.
    ///
    /// - Throws: `WireValueDecodingError.wrongTypeForKey` if the value does not have case `object` or `null`
    func optionalObjectValueForKey(_ key: String) throws(ARTErrorInfo) -> [String: WireValue]? {
        guard let value = self[key] else {
            return nil
        }

        if case .null = value {
            return nil
        }

        guard case let .object(objectValue) = value else {
            throw WireValueDecodingError.wrongTypeForKey(key, actualValue: value).toARTErrorInfo()
        }

        return objectValue
    }

    /// If this dictionary contains a value for `key`, and this value has case `array`, this returns the associated value.
    ///
    /// - Throws:
    ///   - `WireValueDecodingError.noValueForKey` if the key is absent
    ///   - `WireValueDecodingError.wrongTypeForKey` if the value does not have case `array`
    func arrayValueForKey(_ key: String) throws(ARTErrorInfo) -> [WireValue] {
        guard let value = self[key] else {
            throw WireValueDecodingError.noValueForKey(key).toARTErrorInfo()
        }

        guard case let .array(arrayValue) = value else {
            throw WireValueDecodingError.wrongTypeForKey(key, actualValue: value).toARTErrorInfo()
        }

        return arrayValue
    }

    /// If this dictionary contains a value for `key`, and this value has case `array`, this returns the associated value. If this dictionary does not contain a value for `key`, or if the value for `key` has case `null`, it returns `nil`.
    ///
    /// - Throws: `WireValueDecodingError.wrongTypeForKey` if the value does not have case `array` or `null`
    func optionalArrayValueForKey(_ key: String) throws(ARTErrorInfo) -> [WireValue]? {
        guard let value = self[key] else {
            return nil
        }

        if case .null = value {
            return nil
        }

        guard case let .array(arrayValue) = value else {
            throw WireValueDecodingError.wrongTypeForKey(key, actualValue: value).toARTErrorInfo()
        }

        return arrayValue
    }

    /// If this dictionary contains a value for `key`, and this value has case `string`, this returns the associated value.
    ///
    /// - Throws:
    ///   - `WireValueDecodingError.noValueForKey` if the key is absent
    ///   - `WireValueDecodingError.wrongTypeForKey` if the value does not have case `string`
    func stringValueForKey(_ key: String) throws(ARTErrorInfo) -> String {
        guard let value = self[key] else {
            throw WireValueDecodingError.noValueForKey(key).toARTErrorInfo()
        }

        guard case let .string(stringValue) = value else {
            throw WireValueDecodingError.wrongTypeForKey(key, actualValue: value).toARTErrorInfo()
        }

        return stringValue
    }

    /// If this dictionary contains a value for `key`, and this value has case `string`, this returns the associated value. If this dictionary does not contain a value for `key`, or if the value for `key` has case `null`, it returns `nil`.
    ///
    /// - Throws: `WireValueDecodingError.wrongTypeForKey` if the value does not have case `string` or `null`
    func optionalStringValueForKey(_ key: String) throws(ARTErrorInfo) -> String? {
        guard let value = self[key] else {
            return nil
        }

        if case .null = value {
            return nil
        }

        guard case let .string(stringValue) = value else {
            throw WireValueDecodingError.wrongTypeForKey(key, actualValue: value).toARTErrorInfo()
        }

        return stringValue
    }

    /// If this dictionary contains a value for `key`, and this value has case `number`, this returns the associated value.
    ///
    /// - Throws:
    ///   - `WireValueDecodingError.noValueForKey` if the key is absent
    ///   - `WireValueDecodingError.wrongTypeForKey` if the value does not have case `number`
    func numberValueForKey(_ key: String) throws(ARTErrorInfo) -> NSNumber {
        guard let value = self[key] else {
            throw WireValueDecodingError.noValueForKey(key).toARTErrorInfo()
        }

        guard case let .number(numberValue) = value else {
            throw WireValueDecodingError.wrongTypeForKey(key, actualValue: value).toARTErrorInfo()
        }

        return numberValue
    }

    /// If this dictionary contains a value for `key`, and this value has case `number`, this returns the associated value. If this dictionary does not contain a value for `key`, or if the value for `key` has case `null`, it returns `nil`.
    ///
    /// - Throws: `WireValueDecodingError.wrongTypeForKey` if the value does not have case `number` or `null`
    func optionalNumberValueForKey(_ key: String) throws(ARTErrorInfo) -> NSNumber? {
        guard let value = self[key] else {
            return nil
        }

        if case .null = value {
            return nil
        }

        guard case let .number(numberValue) = value else {
            throw WireValueDecodingError.wrongTypeForKey(key, actualValue: value).toARTErrorInfo()
        }

        return numberValue
    }

    /// If this dictionary contains a value for `key`, and this value has case `bool`, this returns the associated value.
    ///
    /// - Throws:
    ///   - `WireValueDecodingError.noValueForKey` if the key is absent
    ///   - `WireValueDecodingError.wrongTypeForKey` if the value does not have case `bool`
    func boolValueForKey(_ key: String) throws(ARTErrorInfo) -> Bool {
        guard let value = self[key] else {
            throw WireValueDecodingError.noValueForKey(key).toARTErrorInfo()
        }

        guard case let .bool(boolValue) = value else {
            throw WireValueDecodingError.wrongTypeForKey(key, actualValue: value).toARTErrorInfo()
        }

        return boolValue
    }

    /// If this dictionary contains a value for `key`, and this value has case `bool`, this returns the associated value. If this dictionary does not contain a value for `key`, or if the value for `key` has case `null`, it returns `nil`.
    ///
    /// - Throws: `WireValueDecodingError.wrongTypeForKey` if the value does not have case `bool` or `null`
    func optionalBoolValueForKey(_ key: String) throws(ARTErrorInfo) -> Bool? {
        guard let value = self[key] else {
            return nil
        }

        if case .null = value {
            return nil
        }

        guard case let .bool(boolValue) = value else {
            throw WireValueDecodingError.wrongTypeForKey(key, actualValue: value).toARTErrorInfo()
        }

        return boolValue
    }

    /// If this dictionary contains a value for `key`, and this value has case `data`, this returns the associated value.
    ///
    /// - Throws:
    ///   - `WireValueDecodingError.noValueForKey` if the key is absent
    ///   - `WireValueDecodingError.wrongTypeForKey` if the value does not have case `data`
    func dataValueForKey(_ key: String) throws(ARTErrorInfo) -> Data {
        guard let value = self[key] else {
            throw WireValueDecodingError.noValueForKey(key).toARTErrorInfo()
        }

        guard case let .data(dataValue) = value else {
            throw WireValueDecodingError.wrongTypeForKey(key, actualValue: value).toARTErrorInfo()
        }

        return dataValue
    }

    /// If this dictionary contains a value for `key`, and this value has case `data`, this returns the associated value. If this dictionary does not contain a value for `key`, or if the value for `key` has case `null`, it returns `nil`.
    ///
    /// - Throws: `WireValueDecodingError.wrongTypeForKey` if the value does not have case `data` or `null`
    func optionalDataValueForKey(_ key: String) throws(ARTErrorInfo) -> Data? {
        guard let value = self[key] else {
            return nil
        }

        if case .null = value {
            return nil
        }

        guard case let .data(dataValue) = value else {
            throw WireValueDecodingError.wrongTypeForKey(key, actualValue: value).toARTErrorInfo()
        }

        return dataValue
    }
}

// MARK: - Extracting dates from a dictionary

internal extension [String: WireValue] {
    /// If this dictionary contains a value for `key`, and this value has case `number`, this returns a date created by interpreting this value as the number of milliseconds since the Unix epoch (which is the format used by Ably).
    ///
    /// - Throws:
    ///   - `WireValueDecodingError.noValueForKey` if the key is absent
    ///   - `WireValueDecodingError.wrongTypeForKey` if the value does not have case `number`
    func ablyProtocolDateValueForKey(_ key: String) throws(ARTErrorInfo) -> Date {
        let millisecondsSinceEpoch = try numberValueForKey(key).uint64Value

        return dateFromMillisecondsSinceEpoch(millisecondsSinceEpoch)
    }

    /// If this dictionary contains a value for `key`, and this value has case `number`, this returns a date created by interpreting this value as the number of milliseconds since the Unix epoch (which is the format used by Ably). If this dictionary does not contain a value for `key`, or if the value for `key` has case `null`, it returns `nil`.
    ///
    /// - Throws: `WireValueDecodingError.wrongTypeForKey` if the value does not have case `number` or `null`
    func optionalAblyProtocolDateValueForKey(_ key: String) throws(ARTErrorInfo) -> Date? {
        guard let millisecondsSinceEpoch = try optionalNumberValueForKey(key)?.uint64Value else {
            return nil
        }
        return dateFromMillisecondsSinceEpoch(millisecondsSinceEpoch)
    }

    private func dateFromMillisecondsSinceEpoch(_ millisecondsSinceEpoch: UInt64) -> Date {
        .init(timeIntervalSince1970: Double(millisecondsSinceEpoch) / 1000)
    }
}

// MARK: - Extracting RawRepresentable values from a dictionary

internal extension [String: WireValue] {
    /// If this dictionary contains a value for `key`, and this value has case `string`, this creates an instance of `T` using its `init(rawValue:)` initializer.
    ///
    /// - Throws:
    ///   - `WireValueDecodingError.noValueForKey` if the key is absent
    ///   - `WireValueDecodingError.wrongTypeForKey` if the value does not have case `string`
    ///   - `WireValueDecodingError.failedToDecodeFromRawValue` if `init(rawValue:)` returns `nil`
    func rawRepresentableValueForKey<T: RawRepresentable>(_ key: String, type _: T.Type = T.self) throws(ARTErrorInfo) -> T where T.RawValue == String {
        let rawValue = try stringValueForKey(key)

        return try rawRepresentableValueFromRawValue(rawValue, type: T.self)
    }

    /// If this dictionary contains a value for `key`, and this value has case `string`, this creates an instance of `T` using its `init(rawValue:)` initializer. If this dictionary does not contain a value for `key`, or if the value for `key` has case `null`, it returns `nil`.
    ///
    /// - Throws:
    ///   - `WireValueDecodingError.wrongTypeForKey` if the value does not have case `string` or `null`
    ///   - `WireValueDecodingError.failedToDecodeFromRawValue` if `init(rawValue:)` returns `nil`
    func optionalRawRepresentableValueForKey<T: RawRepresentable>(_ key: String, type _: T.Type = T.self) throws(ARTErrorInfo) -> T? where T.RawValue == String {
        guard let rawValue = try optionalStringValueForKey(key) else {
            return nil
        }

        return try rawRepresentableValueFromRawValue(rawValue, type: T.self)
    }

    private func rawRepresentableValueFromRawValue<T: RawRepresentable>(_ rawValue: String, type _: T.Type = T.self) throws(ARTErrorInfo) -> T where T.RawValue == String {
        guard let value = T(rawValue: rawValue) else {
            throw WireValueDecodingError.failedToDecodeFromRawValue(rawValue).toARTErrorInfo()
        }

        return value
    }
}

// MARK: - Extracting WireEnum values from a dictionary

internal extension [String: WireValue] {
    /// If this dictionary contains a value for `key`, and this value has case `number`, this creates a `WireEnum` instance using its `init(rawValue:)` initializer.
    ///
    /// - Throws:
    ///   - `WireValueDecodingError.noValueForKey` if the key is absent
    ///   - `WireValueDecodingError.wrongTypeForKey` if the value does not have case `number`
    func wireEnumValueForKey<Known: RawRepresentable>(_ key: String, type _: Known.Type = Known.self) throws(ARTErrorInfo) -> WireEnum<Known> where Known.RawValue == Int {
        let rawValue = try numberValueForKey(key).intValue
        return WireEnum(rawValue: rawValue)
    }

    /// If this dictionary contains a value for `key`, and this value has case `number`, this creates a `WireEnum` instance using its `init(rawValue:)` initializer. If this dictionary does not contain a value for `key`, or if the value for `key` has case `null`, it returns `nil`.
    ///
    /// - Throws: `WireValueDecodingError.wrongTypeForKey` if the value does not have case `number` or `null`
    func optionalWireEnumValueForKey<Known: RawRepresentable>(_ key: String, type _: Known.Type = Known.self) throws(ARTErrorInfo) -> WireEnum<Known>? where Known.RawValue == Int {
        guard let rawValue = try optionalNumberValueForKey(key)?.intValue else {
            return nil
        }
        return WireEnum(rawValue: rawValue)
    }
}

// MARK: - Extracting WireDecodable values from a dictionary

internal extension [String: WireValue] {
    /// If this dictionary contains a value for `key`, this attempts to decode it into an instance of `T` using its `init(wireValue:)` initializer.
    ///
    /// - Throws:
    ///   - `WireValueDecodingError.noValueForKey` if the key is absent
    ///   - Any error thrown by `T.init(wireValue:)`
    func decodableValueForKey<T: WireDecodable>(_ key: String, type _: T.Type = T.self) throws(ARTErrorInfo) -> T {
        guard let value = self[key] else {
            throw WireValueDecodingError.noValueForKey(key).toARTErrorInfo()
        }

        return try T(wireValue: value)
    }

    /// If this dictionary contains a value for `key`, this attempts to decode it into an instance of `T` using its `init(wireValue:)` initializer. If this dictionary does not contain a value for `key`, or if the value for `key` has case `null`, it returns `nil`.
    ///
    /// - Throws: Any error thrown by `T.init(wireValue:)`
    func optionalDecodableValueForKey<T: WireDecodable>(_ key: String, type _: T.Type = T.self) throws(ARTErrorInfo) -> T? {
        guard let value = self[key] else {
            return nil
        }

        if case .null = value {
            return nil
        }

        return try T(wireValue: value)
    }
}
