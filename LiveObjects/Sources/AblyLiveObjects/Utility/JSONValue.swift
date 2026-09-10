import Ably
import Foundation

/// A JSON value (where "value" has the meaning defined by the [JSON specification](https://www.json.org)).
///
/// `JSONValue` provides a type-safe API for working with JSON values. It implements Swift's `ExpressibleBy*Literal` protocols. This allows you to write type-safe JSON values using familiar syntax. For example:
///
/// ```swift
/// let jsonValue: JSONValue = [
///     "someArray": [
///         [
///             "someStringKey": "someString",
///             "someIntegerKey": 123,
///             "someFloatKey": 123.456,
///             "someTrueKey": true,
///             "someFalseKey": false,
///             "someNullKey": .null,
///         ],
///         "someOtherArrayElement",
///     ],
///     "someNestedObject": [
///         "someOtherKey": "someOtherValue",
///     ],
/// ]
///  ```
///
/// > Note: To write a `JSONValue` that corresponds to the `null` JSON value, you must explicitly write `.null`. `JSONValue` deliberately does not implement the `ExpressibleByNilLiteral` protocol in order to avoid confusion between a value of type `JSONValue?` and a `JSONValue` with case `.null`.
public indirect enum JSONValue: Sendable, Equatable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    // MARK: - Convenience getters for associated values

    /// If this `JSONValue` has case `object`, this returns the associated value. Else, it returns `nil`.
    public var objectValue: [String: JSONValue]? {
        if case let .object(objectValue) = self {
            objectValue
        } else {
            nil
        }
    }

    /// If this `JSONValue` has case `array`, this returns the associated value. Else, it returns `nil`.
    public var arrayValue: [JSONValue]? {
        if case let .array(arrayValue) = self {
            arrayValue
        } else {
            nil
        }
    }

    /// If this `JSONValue` has case `string`, this returns the associated value. Else, it returns `nil`.
    public var stringValue: String? {
        if case let .string(stringValue) = self {
            stringValue
        } else {
            nil
        }
    }

    /// If this `JSONValue` has case `number`, this returns the associated value. Else, it returns `nil`.
    public var numberValue: Double? {
        if case let .number(numberValue) = self {
            numberValue
        } else {
            nil
        }
    }

    /// If this `JSONValue` has case `bool`, this returns the associated value. Else, it returns `nil`.
    public var boolValue: Bool? {
        if case let .bool(boolValue) = self {
            boolValue
        } else {
            nil
        }
    }

    /// Returns true if and only if this `JSONValue` has case `null`.
    public var isNull: Bool {
        if case .null = self {
            true
        } else {
            false
        }
    }
}

extension JSONValue: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(.init(uniqueKeysWithValues: elements))
    }
}

extension JSONValue: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: JSONValue...) {
        self = .array(elements)
    }
}

extension JSONValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = .string(value)
    }
}

extension JSONValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self = .number(Double(value))
    }
}

extension JSONValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self = .number(value)
    }
}

extension JSONValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        self = .bool(value)
    }
}

// MARK: - Bridging with JSONSerialization

internal extension JSONValue {
    /// Creates a `JSONValue` from the output of Foundation's `JSONSerialization`.
    ///
    /// This means that it accepts either:
    ///
    /// - The result of serializing an array or dictionary using `JSONSerialization`
    /// - Some nested element of the result of serializing such an array or dictionary
    init(jsonSerializationOutput: Any) {
        // art_doubleValue, not doubleValue: this is the JSONSerialization boundary itself, where a
        // high-precision number arrives as an NSDecimalNumber
        let extended = ExtendedJSONValue<Double, Never>(deserialized: jsonSerializationOutput, createNumberValue: { $0.art_doubleValue }, createExtraValue: { deserializedExtraValue in
            // JSONSerialization is not conforming to our assumptions; our assumptions are probably wrong. Either way, bring this loudly to our attention instead of trying to carry on
            preconditionFailure("JSONValue(jsonSerializationOutput:) was given unsupported value \(deserializedExtraValue)")
        })

        self.init(extendedJSONValue: extended)
    }

    /// Converts a `JSONValue` to an input for Foundation's `JSONSerialization`.
    ///
    /// This means that it returns:
    ///
    /// - All cases: An object which we can put inside an array or dictionary that we ask `JSONSerialization` to serialize
    /// - Additionally, if case `object` or `array`: An object which we can ask `JSONSerialization` to serialize
    var toJSONSerializationInputElement: Any {
        toExtendedJSONValue.serialized(serializeNumberValue: { $0 as NSNumber }, serializeExtraValue: { _ in })
    }
}

// MARK: - JSON objects and arrays

/// A subset of ``JSONValue`` that has only `object` or `array` cases.
///
/// > Note: These are the two cases a JSON *text* was restricted to under RFC 4627, so `JSON` would be a
/// > natural name for this type. It is spelled out instead: `JSON` is broad enough to be mistaken for
/// > `JSONValue`, and current JSON (RFC 8259, and the json.org grammar linked above) allows any value at
/// > the top level, so the short name would no longer say what the restriction is.
internal enum JSONObjectOrArray: Equatable {
    case object([String: JSONValue])
    case array([JSONValue])

    internal enum ConversionError: Swift.Error {
        case incompatibleJSONValue(JSONValue)
    }

    internal init(jsonValue: JSONValue) throws(ARTErrorInfo) {
        self = switch jsonValue {
        case let .array(array):
            .array(array)
        case let .object(object):
            .object(object)
        case .bool, .number, .string, .null:
            throw ConversionError.incompatibleJSONValue(jsonValue).toARTErrorInfo()
        }
    }

    // MARK: - Convenience getters for associated values

    /// If this `JSONObjectOrArray` has case `object`, this returns the associated value. Else, it returns `nil`.
    internal var objectValue: [String: JSONValue]? {
        if case let .object(value) = self {
            return value
        }
        return nil
    }

    /// If this `JSONObjectOrArray` has case `array`, this returns the associated value. Else, it returns `nil`.
    internal var arrayValue: [JSONValue]? {
        if case let .array(value) = self {
            return value
        }
        return nil
    }

    /// The equivalent ``JSONValue``: an `object`/`array` case carries straight across. Used to surface
    /// the OD2g decoded value publicly (the wire form is the OD5-decoded JSON-encoded string).
    internal var toJSONValue: JSONValue {
        switch self {
        case let .object(object):
            .object(object)
        case let .array(array):
            .array(array)
        }
    }
}

extension JSONObjectOrArray: ExpressibleByDictionaryLiteral {
    internal init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(.init(uniqueKeysWithValues: elements))
    }
}

extension JSONObjectOrArray: ExpressibleByArrayLiteral {
    internal init(arrayLiteral elements: JSONValue...) {
        self = .array(elements)
    }
}

internal extension [String: JSONValue] {
    /// Converts a dictionary that has string keys and `JSONValue` values into an input for Foundation's `JSONSerialization`.
    var toJSONSerializationInput: [String: Any] {
        mapValues(\.toJSONSerializationInputElement)
    }
}

internal extension [JSONValue] {
    /// Converts an array that has `JSONValue` values into an input for Foundation's `JSONSerialization`.
    var toJSONSerializationInput: [Any] {
        map(\.toJSONSerializationInputElement)
    }
}

// MARK: - Conversion to/from ExtendedJSONValue

internal extension JSONValue {
    init(extendedJSONValue: ExtendedJSONValue<Double, Never>) {
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
        }
    }

    var toExtendedJSONValue: ExtendedJSONValue<Double, Never> {
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
        }
    }
}

// MARK: Serializing to and deserializing from a JSON string

internal extension JSONObjectOrArray {
    enum DecodingError: Swift.Error {
        case incompatibleJSONValue(JSONValue)
    }

    /// Deserializes a JSON string into a `JSONObjectOrArray`. Throws an error if not given a valid JSON string.
    init(jsonString: String) throws(ARTErrorInfo) {
        let data = Data(jsonString.utf8)
        let jsonSerializationOutput: Any
        do {
            jsonSerializationOutput = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw LiveObjectsError.other(error).toARTErrorInfo()
        }

        let jsonValue = JSONValue(jsonSerializationOutput: jsonSerializationOutput)
        try self.init(jsonValue: jsonValue)
    }

    /// Converts a `JSONObjectOrArray` into an input for Foundation's `JSONSerialization`.
    private var toJSONSerializationInput: Any {
        switch self {
        case let .array(array):
            array.toJSONSerializationInput
        case let .object(object):
            object.toJSONSerializationInput
        }
    }

    /// Serializes a `JSONObjectOrArray` to a JSON string.
    var toJSONString: String {
        let data: Data
        do {
            data = try JSONSerialization.data(withJSONObject: toJSONSerializationInput)
        } catch {
            preconditionFailure("Unexpected error encoding to JSON: \(error)")
        }

        guard let string = String(data: data, encoding: .utf8) else {
            preconditionFailure("Unexpected failure to decode output of JSONSerialization as UTF-8")
        }

        return string
    }
}

extension JSONValue: CustomStringConvertible {
    /// Compact JSON text, with object keys sorted for deterministic output.
    ///
    /// ```swift
    /// let jsonValue: JSONValue = ["likes": 10, "hearts": 0]
    /// print("Reactions updated: \(jsonValue)") // Reactions updated: {"hearts":0,"likes":10}
    /// ```
    ///
    /// > Note: This is a display and debugging aid, not a guaranteed-stable serialization format; the
    /// > exact bytes — for example where exponent notation is used — may change.
    ///
    /// > Note: JSON has no representation for the non-finite `Double` values, so a `number` whose value
    /// > is NaN or infinite is written as `null`.
    public var description: String {
        // The text is built here rather than by `JSONSerialization`, which offers no option to change
        // any of the three things that make its output unsuitable: it writes numbers to a fixed 17
        // significant digits rather than the shortest form that round-trips, so `0.1` prints as
        // `0.10000000000000001`; it escapes the forward slash, so URLs print as
        // `https:\/\/example.com`; and it raises an Objective-C exception, uncatchable from Swift, when
        // asked to write a non-finite number, which `number(_:)` makes constructible.
        //
        // Sorting the keys also gives a plain lexicographic order, where `JSONSerialization`'s
        // `sortedKeys` compares digits numerically and treats case as secondary.
        switch self {
        case let .object(object):
            let members = object
                .sorted { $0.key < $1.key }
                .map { key, value in "\(Self.jsonText(forString: key)):\(value.description)" }
            return "{\(members.joined(separator: ","))}"
        case let .array(array):
            return "[\(array.map(\.description).joined(separator: ","))]"
        case let .string(string):
            return Self.jsonText(forString: string)
        case let .number(number):
            return Self.jsonText(forNumber: number)
        case let .bool(bool):
            return bool ? "true" : "false"
        case .null:
            return "null"
        }
    }
}

extension JSONValue: CustomDebugStringConvertible {
    /// Compact JSON text, with object keys sorted for deterministic output; the same as ``description``,
    /// so that `String(reflecting:)` and LLDB's `po` also show the value rather than the enum's structure.
    public var debugDescription: String {
        description
    }
}

private extension JSONValue {
    /// The JSON text for a string, including the surrounding quotation marks.
    ///
    /// Only the escapes that JSON requires are applied. In particular the forward slash, which JSON
    /// permits escaping but does not require it to be escaped, is left alone so that URLs stay readable.
    static func jsonText(forString string: String) -> String {
        var result = "\""

        for scalar in string.unicodeScalars {
            switch scalar {
            case "\"":
                result += #"\""#
            case "\\":
                result += #"\\"#
            case "\n":
                result += #"\n"#
            case "\r":
                result += #"\r"#
            case "\t":
                result += #"\t"#
            case "\u{08}":
                result += #"\b"#
            case "\u{0C}":
                result += #"\f"#
            case _ where scalar.value < 0x20:
                result += String(format: #"\u%04x"#, scalar.value)
            default:
                result.unicodeScalars.append(scalar)
            }
        }

        return result + "\""
    }

    /// The JSON text for a number.
    ///
    /// `Double`'s own description is the shortest representation that round-trips, so it supplies the
    /// digits. Two pieces of its punctuation are dropped: the zeros that trail a fractional part, so
    /// that `10` is not written as `10.0`, and the zeros that pad an exponent, so that `1e-7` is not
    /// written as `1e-07`.
    ///
    /// Where `Double`'s description chooses exponent notation is left as it is, which is not always
    /// where `JSON.stringify` chooses it: `4.4854284003116864e+17` here is `448542840031168640` there.
    /// Both are valid JSON carrying the same digits, and both parse back to this value.
    static func jsonText(forNumber number: Double) -> String {
        guard number.isFinite else {
            // NaN and the infinities have no JSON representation.
            return "null" // .nan, .infinity -> null
        }

        let text = String(number)

        guard let exponentIndex = text.firstIndex(where: { $0 == "e" || $0 == "E" }) else {
            return withoutTrailingFractionZeros(text) // 10.0 -> 10; 0.1 -> 0.1; -0.0 -> -0
        }

        let mantissa = withoutTrailingFractionZeros(String(text[..<exponentIndex]))
        let exponent = withoutExponentPadding(String(text[text.index(after: exponentIndex)...]))

        return "\(mantissa)e\(exponent)" // 1e-07 -> 1e-7; 1.7976931348623157e+308 unchanged
    }

    /// Drops the zeros trailing a fractional part, and the decimal point too if they were all of it.
    static func withoutTrailingFractionZeros(_ text: String) -> String {
        // Without a point the trailing zeros are significant: 100 must not become 1.
        guard text.contains(".") else {
            return text
        }

        var result = text
        while result.hasSuffix("0") {
            result.removeLast()
        }
        if result.hasSuffix(".") {
            result.removeLast()
        }

        return result // 10.0 -> 10; 1.10 -> 1.1; 0.0 -> 0; 123.456 -> 123.456
    }

    /// Drops the zeros `Double`'s description pads a single-digit exponent with.
    static func withoutExponentPadding(_ text: String) -> String {
        var sign = ""
        var digits = Substring(text)

        if let first = digits.first, first == "+" || first == "-" {
            sign = String(first)
            digits = digits.dropFirst()
        }

        // Keep the last digit even if it is a zero, so that an exponent of 0 survives.
        while digits.count > 1, digits.first == "0" {
            digits = digits.dropFirst()
        }

        return sign + digits // -07 -> -7; +308 -> +308
    }
}

extension JSONObjectOrArray: CustomStringConvertible {
    /// Compact JSON text, with object keys sorted for deterministic output.
    ///
    /// ```swift
    /// let jsonObject: JSONObjectOrArray = ["likes": 10, "hearts": 0]
    /// print("Reactions updated: \(jsonObject)") // Reactions updated: {"hearts":0,"likes":10}
    /// ```
    ///
    /// Since this type is the `object`/`array` subset of ``JSONValue``, it defers to that type's
    /// ``JSONValue/description`` rather than repeating the rendering; see there for how numbers and
    /// strings are written.
    internal var description: String {
        toJSONValue.description
    }
}

extension JSONObjectOrArray: CustomDebugStringConvertible {
    /// Compact JSON text, with object keys sorted for deterministic output; the same as ``description``,
    /// so that `String(reflecting:)` and LLDB's `po` also show the value rather than the enum's structure.
    internal var debugDescription: String {
        description
    }
}
