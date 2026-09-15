import _AblyPluginSupportPrivate
@testable import AblyLiveObjects
import AblyPubSubDevice
import Foundation
import Testing

// Note that the usage of rawValue when referring to an EncodingFormat in a parameterised test argument in this test file is a workaround for an Xcode issue that means that, if you use the struct value directly, you get a runtime crash of "Internal inconsistency: No test reporter for test case argumentIDs"; seems like it's an issue that people report happening with various combinations of test arguments, I guess this is one that triggers it. See if fixed in a future Xcode version (I tested in Xcode 16.4 and it wasn't).

struct ObjectMessageTests {
    struct ObjectDataTests {
        struct EncodingTests {
            struct MessagePackTests {
                // @spec OD4c1
                @Test
                func boolean() {
                    let objectData = ProtocolTypes.ObjectData(boolean: true)
                    let wireData = objectData.toWire(format: .messagePack)

                    // OD4c1: A boolean payload is encoded as a MessagePack boolean type, and the result is set on the ObjectData.boolean attribute
                    #expect(wireData.boolean == true)
                    #expect(wireData.bytes == nil)
                    #expect(wireData.number == nil)
                    #expect(wireData.string == nil)
                    #expect(wireData.json == nil)
                }

                // @spec OD4c2
                @Test
                func binary() {
                    let testData = Data([1, 2, 3, 4])
                    let objectData = ProtocolTypes.ObjectData(bytes: testData)
                    let wireData = objectData.toWire(format: .messagePack)

                    // OD4c2: A binary payload is encoded as a MessagePack binary type, and the result is set on the ObjectData.bytes attribute
                    #expect(wireData.boolean == nil)
                    switch wireData.bytes {
                    case let .data(data):
                        #expect(data == testData)
                    default:
                        Issue.record("Expected .data case")
                    }
                    #expect(wireData.number == nil)
                    #expect(wireData.string == nil)
                    #expect(wireData.json == nil)
                }

                // @spec OD4c3
                @Test(arguments: [15, 42.0])
                func number(testNumber: NSNumber) throws {
                    let objectData = ProtocolTypes.ObjectData(number: testNumber)
                    let wireData = objectData.toWire(format: .messagePack)

                    // OD4c3 A number payload is encoded as a MessagePack float64 type, and the result is set on the ObjectData.number attribute
                    #expect(wireData.boolean == nil)
                    #expect(wireData.bytes == nil)
                    CFNumberGetType(testNumber)
                    let number = try #require(wireData.number)
                    #expect(CFNumberGetType(number) == .float64Type)
                    #expect(number == testNumber)
                    #expect(wireData.number == testNumber)
                    #expect(wireData.string == nil)
                    #expect(wireData.json == nil)
                }

                // @spec OD4c4
                @Test
                func string() {
                    let testString = "hello world"
                    let objectData = ProtocolTypes.ObjectData(string: testString)
                    let wireData = objectData.toWire(format: .messagePack)

                    // OD4c4: A string payload is encoded as a MessagePack string type, and the result is set on the ObjectData.string attribute
                    #expect(wireData.boolean == nil)
                    #expect(wireData.bytes == nil)
                    #expect(wireData.number == nil)
                    #expect(wireData.string == testString)
                    #expect(wireData.json == nil)
                }

                // TODO: Needs specification (see https://github.com/ably/ably-liveobjects-swift-plugin/issues/46)
                @Test(arguments: [
                    // We intentionally use a single-element object so that we get a stable encoding to JSON
                    (jsonObjectOrArray: ["key": "value"] as JSONObjectOrArray, expectedJSONString: #"{"key":"value"}"#),
                    (jsonObjectOrArray: [123, "hello world"] as JSONObjectOrArray, expectedJSONString: #"[123,"hello world"]"#),
                ])
                func json(jsonObjectOrArray: JSONObjectOrArray, expectedJSONString: String) {
                    let objectData = ProtocolTypes.ObjectData(json: jsonObjectOrArray)
                    let wireData = objectData.toWire(format: .messagePack)

                    #expect(wireData.boolean == nil)
                    #expect(wireData.bytes == nil)
                    #expect(wireData.number == nil)
                    #expect(wireData.string == nil)
                    #expect(wireData.json == expectedJSONString)
                }
            }

            struct JSONTests {
                // @spec OD4d1
                @Test
                func boolean() {
                    let objectData = ProtocolTypes.ObjectData(boolean: true)
                    let wireData = objectData.toWire(format: .json)

                    // OD4d1: A boolean payload is represented as a JSON boolean and set on the ObjectData.boolean attribute
                    #expect(wireData.boolean == true)
                    #expect(wireData.bytes == nil)
                    #expect(wireData.number == nil)
                    #expect(wireData.string == nil)
                    #expect(wireData.json == nil)
                }

                // @spec OD4d2
                @Test
                func binary() {
                    let testData = Data([1, 2, 3, 4])
                    let objectData = ProtocolTypes.ObjectData(bytes: testData)
                    let wireData = objectData.toWire(format: .json)

                    // OD4d2: A binary payload is Base64-encoded and represented as a JSON string; the result is set on the ObjectData.bytes attribute
                    #expect(wireData.boolean == nil)
                    switch wireData.bytes {
                    case let .string(base64String):
                        #expect(base64String == testData.base64EncodedString())
                    default:
                        Issue.record("Expected .string case")
                    }
                    #expect(wireData.number == nil)
                    #expect(wireData.string == nil)
                    #expect(wireData.json == nil)
                }

                // @spec OD4d3
                @Test
                func number() {
                    let testNumber = NSNumber(value: 42)
                    let objectData = ProtocolTypes.ObjectData(number: testNumber)
                    let wireData = objectData.toWire(format: .json)

                    // OD4d3: A number payload is represented as a JSON number and set on the ObjectData.number attribute
                    #expect(wireData.boolean == nil)
                    #expect(wireData.bytes == nil)
                    #expect(wireData.number == testNumber)
                    #expect(wireData.string == nil)
                    #expect(wireData.json == nil)
                }

                // @spec OD4d4
                @Test
                func string() {
                    let testString = "hello world"
                    let objectData = ProtocolTypes.ObjectData(string: testString)
                    let wireData = objectData.toWire(format: .json)

                    // OD4d4: A string payload is represented as a JSON string and set on the ObjectData.string attribute
                    #expect(wireData.boolean == nil)
                    #expect(wireData.bytes == nil)
                    #expect(wireData.number == nil)
                    #expect(wireData.string == testString)
                    #expect(wireData.json == nil)
                }

                // TODO: Needs specification (see https://github.com/ably/ably-liveobjects-swift-plugin/issues/46)
                @Test(arguments: [
                    // We intentionally use a single-element object so that we get a stable encoding to JSON
                    (jsonObjectOrArray: ["key": "value"] as JSONObjectOrArray, expectedJSONString: #"{"key":"value"}"#),
                    (jsonObjectOrArray: [123, "hello world"] as JSONObjectOrArray, expectedJSONString: #"[123,"hello world"]"#),
                ])
                func json(jsonObjectOrArray: JSONObjectOrArray, expectedJSONString: String) {
                    let objectData = ProtocolTypes.ObjectData(json: jsonObjectOrArray)
                    let wireData = objectData.toWire(format: .json)

                    #expect(wireData.boolean == nil)
                    #expect(wireData.bytes == nil)
                    #expect(wireData.number == nil)
                    #expect(wireData.string == nil)
                    #expect(wireData.json == expectedJSONString)
                }
            }
        }

        struct DecodingTests {
            struct MessagePackTests {
                // @specOneOf(1/5) OD5a1
                @Test
                func boolean() throws {
                    let wireData = WireObjectData(boolean: true)
                    let objectData = try ProtocolTypes.ObjectData(wireObjectData: wireData, format: .messagePack)

                    // OD5a1: The payloads in ObjectData.boolean, ObjectData.bytes, ObjectData.number, and ObjectData.string are decoded as their corresponding MessagePack types
                    #expect(objectData.boolean == true)
                    #expect(objectData.bytes == nil)
                    #expect(objectData.number == nil)
                    #expect(objectData.string == nil)
                    #expect(objectData.json == nil)
                }

                // @specOneOf(2/5) OD5a1
                @Test
                func binary() throws {
                    let testData = Data([1, 2, 3, 4])
                    let wireData = WireObjectData(bytes: .data(testData))
                    let objectData = try ProtocolTypes.ObjectData(wireObjectData: wireData, format: .messagePack)

                    // OD5a1: The payloads in ObjectData.boolean, ObjectData.bytes, ObjectData.number, and ObjectData.string are decoded as their corresponding MessagePack types
                    #expect(objectData.boolean == nil)
                    #expect(objectData.bytes == testData)
                    #expect(objectData.number == nil)
                    #expect(objectData.string == nil)
                    #expect(objectData.json == nil)
                }

                // @specOneOf(3/5) OD5a1 - The spec isn't clear about what's meant to happen if you get string data in the `bytes` field; I'm choosing to ignore it but I think it's a bit moot - shouldn't happen. The only reason I'm considering it here is because of our slightly weird WireObjectData.bytes type which is typed as a string or data; might be good to at some point figure out how to rule out the string case earlier when using MessagePack, but it's not a big issue
                @Test
                func whenBytesIsString() throws {
                    let testData = Data([1, 2, 3, 4])
                    let base64String = testData.base64EncodedString()
                    let wireData = WireObjectData(bytes: .string(base64String))
                    let objectData = try ProtocolTypes.ObjectData(wireObjectData: wireData, format: .messagePack)

                    // OD5a1: The payloads in ObjectData.boolean, ObjectData.bytes, ObjectData.number, and ObjectData.string are decoded as their corresponding MessagePack types
                    #expect(objectData.boolean == nil)
                    #expect(objectData.bytes == nil)
                    #expect(objectData.number == nil)
                    #expect(objectData.string == nil)
                    #expect(objectData.json == nil)
                }

                // @specOneOf(4/5) OD5a1
                @Test
                func number() throws {
                    let testNumber = NSNumber(value: 42)
                    let wireData = WireObjectData(number: testNumber)
                    let objectData = try ProtocolTypes.ObjectData(wireObjectData: wireData, format: .messagePack)

                    // OD5a1: The payloads in ObjectData.boolean, ObjectData.bytes, ObjectData.number, and ObjectData.string are decoded as their corresponding MessagePack types
                    #expect(objectData.boolean == nil)
                    #expect(objectData.bytes == nil)
                    #expect(objectData.number == testNumber)
                    #expect(objectData.string == nil)
                    #expect(objectData.json == nil)
                }

                // @specOneOf(5/5) OD5a1
                @Test
                func string() throws {
                    let testString = "hello world"
                    let wireData = WireObjectData(string: testString)
                    let objectData = try ProtocolTypes.ObjectData(wireObjectData: wireData, format: .messagePack)

                    // OD5a1: The payloads in ObjectData.boolean, ObjectData.bytes, ObjectData.number, and ObjectData.string are decoded as their corresponding MessagePack types
                    #expect(objectData.boolean == nil)
                    #expect(objectData.bytes == nil)
                    #expect(objectData.number == nil)
                    #expect(objectData.string == testString)
                    #expect(objectData.json == nil)
                }

                // TODO: Needs specification (see https://github.com/ably/ably-liveobjects-swift-plugin/issues/46)
                @Test
                func json() throws {
                    let jsonString = "{\"key\":\"value\",\"number\":123}"
                    let wireData = WireObjectData(json: jsonString)
                    let objectData = try ProtocolTypes.ObjectData(wireObjectData: wireData, format: .messagePack)

                    // TODO: Needs specification (see https://github.com/ably/ably-liveobjects-swift-plugin/issues/46)
                    #expect(objectData.boolean == nil)
                    #expect(objectData.bytes == nil)
                    #expect(objectData.number == nil)
                    #expect(objectData.string == nil)
                    #expect(objectData.json == ["key": "value", "number": 123])
                }

                // TODO: Needs specification (see https://github.com/ably/ably-liveobjects-swift-plugin/issues/46)
                // The spec doesn't say what to do if JSON parsing fails; I'm choosing to treat it as an error
                @Test
                func json_invalidJson() {
                    let invalidJsonString = "invalid json"
                    let wireData = WireObjectData(json: invalidJsonString)

                    // Should throw when JSON parsing fails, even in MessagePack format
                    #expect(throws: ARTErrorInfo.self) {
                        _ = try ProtocolTypes.ObjectData(wireObjectData: wireData, format: .messagePack)
                    }
                }

                // TODO: Needs specification (see https://github.com/ably/ably-liveobjects-swift-plugin/issues/46)
                // The spec doesn't say what to do if given serialized JSON that contains a non-object-or-array value; I'm choosing to treat it as an error
                @Test(arguments: [
                    // string
                    "\"hello world\"",
                    // number
                    "42",
                    // boolean true
                    "true",
                    // boolean false
                    "false",
                    // null
                    "null",
                ])
                func json_validJsonButNotObjectOrArray(jsonString: String) {
                    let wireData = WireObjectData(json: jsonString)

                    // Should throw when JSON is valid but not an object or array
                    #expect(throws: ARTErrorInfo.self) {
                        _ = try ProtocolTypes.ObjectData(wireObjectData: wireData, format: .messagePack)
                    }
                }
            }

            struct JSONTests {
                // @specOneOf(1/3) OD5b1
                @Test
                func boolean() throws {
                    let wireData = WireObjectData(boolean: true)
                    let objectData = try ProtocolTypes.ObjectData(wireObjectData: wireData, format: .json)

                    // OD5b1: The payloads in ObjectData.boolean, ObjectData.number, and ObjectData.string are decoded as their corresponding JSON types
                    #expect(objectData.boolean == true)
                    #expect(objectData.bytes == nil)
                    #expect(objectData.number == nil)
                    #expect(objectData.string == nil)
                    #expect(objectData.json == nil)
                }

                // @specOneOf(2/3) OD5b1
                @Test
                func number() throws {
                    let testNumber = NSNumber(value: 42)
                    let wireData = WireObjectData(number: testNumber)
                    let objectData = try ProtocolTypes.ObjectData(wireObjectData: wireData, format: .json)

                    // OD5b1: The payloads in ObjectData.boolean, ObjectData.number, and ObjectData.string are decoded as their corresponding JSON types
                    #expect(objectData.boolean == nil)
                    #expect(objectData.bytes == nil)
                    #expect(objectData.number == testNumber)
                    #expect(objectData.string == nil)
                    #expect(objectData.json == nil)
                }

                // @specOneOf(3/3) OD5b1
                @Test
                func string() throws {
                    let testString = "hello world"
                    let wireData = WireObjectData(string: testString)
                    let objectData = try ProtocolTypes.ObjectData(wireObjectData: wireData, format: .json)

                    // OD5b1: The payloads in ObjectData.boolean, ObjectData.number, and ObjectData.string are decoded as their corresponding JSON types
                    #expect(objectData.boolean == nil)
                    #expect(objectData.bytes == nil)
                    #expect(objectData.number == nil)
                    #expect(objectData.string == testString)
                    #expect(objectData.json == nil)
                }

                // @specOneOf(1/2) OB5b2
                @Test
                func binary() throws {
                    let testData = Data([1, 2, 3, 4])
                    let base64String = testData.base64EncodedString()
                    let wireData = WireObjectData(bytes: .string(base64String))
                    let objectData = try ProtocolTypes.ObjectData(wireObjectData: wireData, format: .json)

                    // OD5b2: The ObjectData.bytes payload is Base64-decoded into a binary value
                    #expect(objectData.boolean == nil)
                    #expect(objectData.bytes == testData)
                    #expect(objectData.number == nil)
                    #expect(objectData.string == nil)
                    #expect(objectData.json == nil)
                }

                // @specOneOf(2/2) OB5b2 - The spec doesn't say what to do if Base64 decoding fails; we're choosing to treat it as an error
                @Test
                func binary_invalidBase64() {
                    let invalidBase64String = "not base64!"
                    let wireData = WireObjectData(bytes: .string(invalidBase64String))

                    // Should throw when Base64 decoding fails
                    #expect(throws: ARTErrorInfo.self) {
                        _ = try ProtocolTypes.ObjectData(wireObjectData: wireData, format: .json)
                    }
                }

                // TODO: Needs specification (see https://github.com/ably/ably-liveobjects-swift-plugin/issues/46)
                @Test
                func json() throws {
                    let jsonString = "{\"key\":\"value\",\"number\":123}"
                    let wireData = WireObjectData(json: jsonString)
                    let objectData = try ProtocolTypes.ObjectData(wireObjectData: wireData, format: .json)

                    #expect(objectData.boolean == nil)
                    #expect(objectData.bytes == nil)
                    #expect(objectData.number == nil)
                    #expect(objectData.string == nil)
                    #expect(objectData.json == ["key": "value", "number": 123])
                }

                // TODO: Needs specification (see https://github.com/ably/ably-liveobjects-swift-plugin/issues/46)
                // The spec doesn't say what to do if JSON parsing fails; I'm choosing to treat it as an error
                @Test
                func json_invalidJson() {
                    let invalidJsonString = "invalid json"
                    let wireData = WireObjectData(json: invalidJsonString)

                    // Should throw when JSON parsing fails
                    #expect(throws: ARTErrorInfo.self) {
                        _ = try ProtocolTypes.ObjectData(wireObjectData: wireData, format: .json)
                    }
                }

                // TODO: Needs specification (see https://github.com/ably/ably-liveobjects-swift-plugin/issues/46)
                // The spec doesn't say what to do if given serialized JSON that contains a non-object-or-array value; I'm choosing to treat it as an error
                @Test(arguments: [
                    // string
                    "\"hello world\"",
                    // number
                    "42",
                    // boolean true
                    "true",
                    // boolean false
                    "false",
                    // null
                    "null",
                ])
                func json_validJsonButNotObjectOrArray(jsonString: String) {
                    let wireData = WireObjectData(json: jsonString)

                    // Should throw when JSON is valid but not an object or array
                    #expect(throws: ARTErrorInfo.self) {
                        _ = try ProtocolTypes.ObjectData(wireObjectData: wireData, format: .json)
                    }
                }
            }
        }
    }

    struct RoundTripTests {
        @Test(arguments: [
            // Test formats
            EncodingFormat.json.rawValue,
            EncodingFormat.messagePack.rawValue,
        ], [
            // Test each property type individually
            ProtocolTypes.ObjectData(boolean: true),
            ProtocolTypes.ObjectData(bytes: Data([1, 2, 3, 4])),
            ProtocolTypes.ObjectData(number: NSNumber(value: 42)),
            ProtocolTypes.ObjectData(string: "hello world"),
            ProtocolTypes.ObjectData(json: .object(["key": "value", "number": 123])),
            ProtocolTypes.ObjectData(json: .array([123, "hello world"])),
        ])
        func roundTrip(formatRawValue: EncodingFormat.RawValue, originalData: ProtocolTypes.ObjectData) throws {
            let format = try #require(EncodingFormat(rawValue: formatRawValue))
            let wireData = originalData.toWire(format: format)
            let decodedData = try ProtocolTypes.ObjectData(wireObjectData: wireData, format: format)

            // Compare boolean values
            #expect(decodedData.boolean == originalData.boolean)

            // Compare bytes values
            #expect(decodedData.bytes == originalData.bytes)

            // Compare number values
            #expect(decodedData.number == originalData.number)

            // Compare string values
            #expect(decodedData.string == originalData.string)

            // Compare JSON values
            #expect(decodedData.json == originalData.json)
        }
    }
}
