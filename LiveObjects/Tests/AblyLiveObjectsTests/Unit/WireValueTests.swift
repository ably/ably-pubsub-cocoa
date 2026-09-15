@testable import AblyLiveObjects
import AblyPubSubDevice.Private
import Foundation
import Testing

struct WireValueTests {
    // MARK: Conversion from _AblyPluginSupportPrivate data

    @Test(arguments: [
        // object
        (pluginSupportData: ["someKey": "someValue"], expectedResult: ["someKey": "someValue"]),
        // array
        (pluginSupportData: ["someElement"], expectedResult: ["someElement"]),
        // string
        (pluginSupportData: "someString", expectedResult: "someString"),
        // number
        (pluginSupportData: NSNumber(value: 0), expectedResult: 0),
        (pluginSupportData: NSNumber(value: 1), expectedResult: 1),
        (pluginSupportData: NSNumber(value: 123), expectedResult: 123),
        (pluginSupportData: NSNumber(value: 123.456), expectedResult: 123.456),
        // bool
        (pluginSupportData: NSNumber(value: true), expectedResult: true),
        (pluginSupportData: NSNumber(value: false), expectedResult: false),
        // null
        (pluginSupportData: NSNull(), expectedResult: .null),
        // data
        (pluginSupportData: Data([0x01, 0x02, 0x03]), expectedResult: .data(Data([0x01, 0x02, 0x03]))),
    ] as[(pluginSupportData: Sendable, expectedResult: WireValue?)])
    func initWithPluginSupportData(pluginSupportData: Sendable, expectedResult: WireValue?) {
        #expect(WireValue(pluginSupportData: pluginSupportData) == expectedResult)
    }

    // Tests that it correctly handles an object deserialized by `JSONSerialization` (which is what ably-cocoa uses for JSON deserialization).
    @Test
    func initWithPluginSupportData_endToEnd_json() throws {
        let jsonString = """
        {
          "someArray": [
            {
              "someStringKey": "someString",
              "zero": 0,
              "one": 1,
              "someIntegerKey": 123,
              "someFloatKey": 123.456,
              "someTrueKey": true,
              "someFalseKey": false,
              "someNullKey": null
            },
            "someOtherArrayElement"
          ],
          "someNestedObject": {
            "someOtherKey": "someOtherValue"
          }
        }
        """

        let pluginSupportData = try JSONSerialization.jsonObject(with: #require(jsonString.data(using: .utf8)))

        let expected: WireValue = [
            "someArray": [
                [
                    "someStringKey": "someString",
                    "zero": 0,
                    "one": 1,
                    "someIntegerKey": 123,
                    "someFloatKey": 123.456,
                    "someTrueKey": true,
                    "someFalseKey": false,
                    "someNullKey": .null,
                ],
                "someOtherArrayElement",
            ],
            "someNestedObject": [
                "someOtherKey": "someOtherValue",
            ],
        ]

        #expect(WireValue(pluginSupportData: pluginSupportData) == expected)
    }

    // Tests that it correctly handles an object deserialized by `ARTMsgPackEncoder` (which is what ably-cocoa uses for MessagePack deserialization).
    @Test
    func initWithPluginSupportData_endToEnd_msgpack() throws {
        // MessagePack representation of the same data structure as in the JSON test above, plus binary data
        // This represents:
        // {
        //   "someArray": [
        //     {
        //       "someStringKey": "someString",
        //       "someIntegerKey": 123,
        //       "zero": 0,
        //       "someFloatKey": 123.456,
        //       "someTrueKey": true,
        //       "someFalseKey": false,
        //       "someNullKey": null,
        //       "one": 1,
        //       "someBinaryKey": <binary data: 0x01, 0x02, 0x03, 0x04>
        //     },
        //     "someOtherArrayElement"
        //   ],
        //   "someNestedObject": {
        //     "someOtherKey": "someOtherValue"
        //   }
        // }
        let msgpackData = Data([
            // Root object - 2 elements map (fixmap format: 0x80 | count)
            0x82,

            // Key 1: "someArray" (fixstr format: 0xa0 | length = 9)
            0xA9, 0x73, 0x6F, 0x6D, 0x65, 0x41, 0x72, 0x72, 0x61, 0x79, // "someArray"

            // Value 1: Array with 2 elements (fixarray format: 0x90 | count)
            0x92,

            // Array element 1: Object with 9 elements (fixmap format: 0x80 | count)
            0x89,

            // Key-value pairs in map (order determined by MessagePack encoder):

            // "someStringKey": "someString"
            0xAD, 0x73, 0x6F, 0x6D, 0x65, 0x53, 0x74, 0x72, 0x69, 0x6E, 0x67, 0x4B, 0x65, 0x79, // key (13 chars)
            0xAA, 0x73, 0x6F, 0x6D, 0x65, 0x53, 0x74, 0x72, 0x69, 0x6E, 0x67, // value (10 chars)

            // "someIntegerKey": 123
            0xAE, 0x73, 0x6F, 0x6D, 0x65, 0x49, 0x6E, 0x74, 0x65, 0x67, 0x65, 0x72, 0x4B, 0x65, 0x79, // key (14 chars)
            0x7B, // value 123 (positive fixint)

            // "zero": 0
            0xA4, 0x7A, 0x65, 0x72, 0x6F, // key "zero" (4 chars)
            0x00, // value 0 (positive fixint)

            // "someFloatKey": 123.456
            0xAC, 0x73, 0x6F, 0x6D, 0x65, 0x46, 0x6C, 0x6F, 0x61, 0x74, 0x4B, 0x65, 0x79, // key (12 chars)
            0xCB, 0x40, 0x5E, 0xDD, 0x2F, 0x1A, 0x9F, 0xBE, 0x77, // value 123.456 (float64)

            // "someTrueKey": true
            0xAB, 0x73, 0x6F, 0x6D, 0x65, 0x54, 0x72, 0x75, 0x65, 0x4B, 0x65, 0x79, // key (11 chars)
            0xC3, // value true

            // "someFalseKey": false
            0xAC, 0x73, 0x6F, 0x6D, 0x65, 0x46, 0x61, 0x6C, 0x73, 0x65, 0x4B, 0x65, 0x79, // key (12 chars)
            0xC2, // value false

            // "someNullKey": null
            0xAB, 0x73, 0x6F, 0x6D, 0x65, 0x4E, 0x75, 0x6C, 0x6C, 0x4B, 0x65, 0x79, // key (11 chars)
            0xC0, // value null

            // "one": 1
            0xA3, 0x6F, 0x6E, 0x65, // key "one" (3 chars)
            0x01, // value 1 (positive fixint)

            // "someBinaryKey": binary data
            0xAD, 0x73, 0x6F, 0x6D, 0x65, 0x42, 0x69, 0x6E, 0x61, 0x72, 0x79, 0x4B, 0x65, 0x79, // key "someBinaryKey" (13 chars)
            0xC4, 0x04, 0x01, 0x02, 0x03, 0x04, // value: bin 8 format (0xc4 + 1 byte length + 4 bytes data)

            // Array element 2: "someOtherArrayElement"
            0xB5, 0x73, 0x6F, 0x6D, 0x65, 0x4F, 0x74, 0x68, 0x65, 0x72, 0x41, 0x72, 0x72, 0x61, 0x79, 0x45, 0x6C, 0x65, 0x6D, 0x65, 0x6E, 0x74, // "someOtherArrayElement" (21 chars)

            // Key 2: "someNestedObject"
            0xB0, 0x73, 0x6F, 0x6D, 0x65, 0x4E, 0x65, 0x73, 0x74, 0x65, 0x64, 0x4F, 0x62, 0x6A, 0x65, 0x63, 0x74, // "someNestedObject" (16 chars)

            // Value 2: Object with 1 element (fixmap format: 0x80 | count)
            0x81,

            // "someOtherKey": "someOtherValue"
            0xAC, 0x73, 0x6F, 0x6D, 0x65, 0x4F, 0x74, 0x68, 0x65, 0x72, 0x4B, 0x65, 0x79, // key (12 chars)
            0xAE, 0x73, 0x6F, 0x6D, 0x65, 0x4F, 0x74, 0x68, 0x65, 0x72, 0x56, 0x61, 0x6C, 0x75, 0x65, // value (14 chars)
        ])

        let pluginSupportData = try ARTMsgPackEncoder().decode(msgpackData)

        let expected: WireValue = [
            "someArray": [
                [
                    "someStringKey": "someString",
                    "zero": 0,
                    "one": 1,
                    "someIntegerKey": 123,
                    "someFloatKey": 123.456,
                    "someTrueKey": true,
                    "someFalseKey": false,
                    "someNullKey": .null,
                    "someBinaryKey": .data(Data([0x01, 0x02, 0x03, 0x04])),
                ],
                "someOtherArrayElement",
            ],
            "someNestedObject": [
                "someOtherKey": "someOtherValue",
            ],
        ]

        #expect(WireValue(pluginSupportData: pluginSupportData) == expected)
    }

    // MARK: Conversion to _AblyPluginSupportPrivate data

    @Test(arguments: [
        // object
        (value: ["someKey": "someValue"], expectedResult: ["someKey": "someValue"]),
        // array
        (value: ["someElement"], expectedResult: ["someElement"]),
        // string
        (value: "someString", expectedResult: "someString"),
        // number
        (value: 0, expectedResult: NSNumber(value: 0)),
        (value: 1, expectedResult: NSNumber(value: 1)),
        (value: 123, expectedResult: NSNumber(value: 123)),
        (value: 123.456, expectedResult: NSNumber(value: 123.456)),
        // bool
        (value: true, expectedResult: NSNumber(value: true)),
        (value: false, expectedResult: NSNumber(value: false)),
        // null
        (value: .null, expectedResult: NSNull()),
        // data
        (value: .data(Data([0x01, 0x02, 0x03])), expectedResult: Data([0x01, 0x02, 0x03])),
    ] as[(value: WireValue, expectedResult: Sendable)])
    func toPluginSupportData(value: WireValue, expectedResult: Sendable) throws {
        let resultAsNSObject = try #require(value.toPluginSupportData as? NSObject)
        let expectedResultAsNSObject = try #require(expectedResult as? NSObject)
        #expect(resultAsNSObject == expectedResultAsNSObject)
    }

    // Tests that it creates an object that can be serialized by `JSONSerialization` (which is what ably-cocoa uses for JSON serialization), and that the result of this serialization is what we'd expect.
    @Test
    func toPluginSupportData_endToEnd_json() throws {
        let value: WireValue = [
            "someArray": [
                [
                    "someStringKey": "someString",
                    "zero": 0,
                    "one": 1,
                    "someIntegerKey": 123,
                    "someFloatKey": 123.456,
                    "someTrueKey": true,
                    "someFalseKey": false,
                    "someNullKey": .null,
                ],
                "someOtherArrayElement",
            ],
            "someNestedObject": [
                "someOtherKey": "someOtherValue",
            ],
        ]

        let expectedJSONString = """
        {
          "someArray": [
            {
              "someStringKey": "someString",
              "someIntegerKey": 123,
              "someFloatKey": 123.456,
              "zero": 0,
              "one": 1,
              "someTrueKey": true,
              "someFalseKey": false,
              "someNullKey": null
            },
            "someOtherArrayElement"
          ],
          "someNestedObject": {
            "someOtherKey": "someOtherValue"
          }
        }
        """

        let jsonSerializationOptions: JSONSerialization.WritingOptions = [.sortedKeys]

        let valueData = try JSONSerialization.data(withJSONObject: value.toPluginSupportData, options: jsonSerializationOptions)
        let expectedData = try {
            let serialized = try JSONSerialization.jsonObject(with: #require(expectedJSONString.data(using: .utf8)))
            return try JSONSerialization.data(withJSONObject: serialized, options: jsonSerializationOptions)
        }()

        #expect(valueData == expectedData)
    }

    // Tests that it creates an object that can be serialized by `ARTMsgPackEncoder` (which is what ably-cocoa uses for MessagePack serialization), and that the result of this serialization is what we'd expect.
    @Test
    func toPluginSupportData_endToEnd_msgpack() throws {
        let value: WireValue = [
            "someArray": [
                [
                    "someStringKey": "someString",
                    "zero": 0,
                    "one": 1,
                    "someIntegerKey": 123,
                    "someFloatKey": 123.456,
                    "someTrueKey": true,
                    "someFalseKey": false,
                    "someNullKey": .null,
                    "someBinaryKey": .data(Data([0x01, 0x02, 0x03, 0x04])),
                ],
                "someOtherArrayElement",
            ],
            "someNestedObject": [
                "someOtherKey": "someOtherValue",
            ],
        ]

        // Expected MessagePack data - manually crafted representation of the WireValue structure including binary data
        // Note: The exact byte order may vary depending on how the encoder orders map keys,
        // so we'll verify by decoding both and comparing the results
        let expectedMsgPackData = Data([
            // Root object - 2 elements map (fixmap format: 0x80 | count)
            0x82,

            // Key 1: "someArray" (fixstr format: 0xa0 | length = 9)
            0xA9, 0x73, 0x6F, 0x6D, 0x65, 0x41, 0x72, 0x72, 0x61, 0x79, // "someArray"

            // Value 1: Array with 2 elements (fixarray format: 0x90 | count)
            0x92,

            // Array element 1: Object with 9 elements (fixmap format: 0x80 | count)
            0x89,

            // Key-value pairs in map (order determined by MessagePack encoder):

            // "someStringKey": "someString"
            0xAD, 0x73, 0x6F, 0x6D, 0x65, 0x53, 0x74, 0x72, 0x69, 0x6E, 0x67, 0x4B, 0x65, 0x79, // key (13 chars)
            0xAA, 0x73, 0x6F, 0x6D, 0x65, 0x53, 0x74, 0x72, 0x69, 0x6E, 0x67, // value (10 chars)

            // "someIntegerKey": 123
            0xAE, 0x73, 0x6F, 0x6D, 0x65, 0x49, 0x6E, 0x74, 0x65, 0x67, 0x65, 0x72, 0x4B, 0x65, 0x79, // key (14 chars)
            0x7B, // value 123 (positive fixint)

            // "zero": 0
            0xA4, 0x7A, 0x65, 0x72, 0x6F, // key "zero" (4 chars)
            0x00, // value 0 (positive fixint)

            // "someFloatKey": 123.456
            0xAC, 0x73, 0x6F, 0x6D, 0x65, 0x46, 0x6C, 0x6F, 0x61, 0x74, 0x4B, 0x65, 0x79, // key (12 chars)
            0xCB, 0x40, 0x5E, 0xDD, 0x2F, 0x1A, 0x9F, 0xBE, 0x77, // value 123.456 (float64)

            // "someTrueKey": true
            0xAB, 0x73, 0x6F, 0x6D, 0x65, 0x54, 0x72, 0x75, 0x65, 0x4B, 0x65, 0x79, // key (11 chars)
            0xC3, // value true

            // "someFalseKey": false
            0xAC, 0x73, 0x6F, 0x6D, 0x65, 0x46, 0x61, 0x6C, 0x73, 0x65, 0x4B, 0x65, 0x79, // key (12 chars)
            0xC2, // value false

            // "someNullKey": null
            0xAB, 0x73, 0x6F, 0x6D, 0x65, 0x4E, 0x75, 0x6C, 0x6C, 0x4B, 0x65, 0x79, // key (11 chars)
            0xC0, // value null

            // "one": 1
            0xA3, 0x6F, 0x6E, 0x65, // key "one" (3 chars)
            0x01, // value 1 (positive fixint)

            // "someBinaryKey": binary data
            0xAD, 0x73, 0x6F, 0x6D, 0x65, 0x42, 0x69, 0x6E, 0x61, 0x72, 0x79, 0x4B, 0x65, 0x79, // key "someBinaryKey" (13 chars)
            0xC4, 0x04, 0x01, 0x02, 0x03, 0x04, // value: bin 8 format (0xc4 + 1 byte length + 4 bytes data)

            // Array element 2: "someOtherArrayElement"
            0xB5, 0x73, 0x6F, 0x6D, 0x65, 0x4F, 0x74, 0x68, 0x65, 0x72, 0x41, 0x72, 0x72, 0x61, 0x79, 0x45, 0x6C, 0x65, 0x6D, 0x65, 0x6E, 0x74, // "someOtherArrayElement" (21 chars)

            // Key 2: "someNestedObject"
            0xB0, 0x73, 0x6F, 0x6D, 0x65, 0x4E, 0x65, 0x73, 0x74, 0x65, 0x64, 0x4F, 0x62, 0x6A, 0x65, 0x63, 0x74, // "someNestedObject" (16 chars)

            // Value 2: Object with 1 element (fixmap format: 0x80 | count)
            0x81,

            // "someOtherKey": "someOtherValue"
            0xAC, 0x73, 0x6F, 0x6D, 0x65, 0x4F, 0x74, 0x68, 0x65, 0x72, 0x4B, 0x65, 0x79, // key (12 chars)
            0xAE, 0x73, 0x6F, 0x6D, 0x65, 0x4F, 0x74, 0x68, 0x65, 0x72, 0x56, 0x61, 0x6C, 0x75, 0x65, // value (14 chars)
        ])

        let actualMsgPackData = try ARTMsgPackEncoder().encode(value.toPluginSupportData)

        // Verify that both decode to the same Foundation object structure
        let expectedDecoded = try ARTMsgPackEncoder().decode(expectedMsgPackData)
        let actualDecoded = try ARTMsgPackEncoder().decode(actualMsgPackData)

        let expectedDecodedAsNSObject = try #require(expectedDecoded as? NSObject)
        let actualDecodedAsNSObject = try #require(actualDecoded as? NSObject)

        #expect(actualDecodedAsNSObject == expectedDecodedAsNSObject)
    }
}
