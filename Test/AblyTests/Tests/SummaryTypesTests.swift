import XCTest
@testable import AblyPubSubDevice

class SummaryTypesTests: XCTestCase {

    // MARK: - Global Summary Functions Tests

    func test__ARTSummaryFlagV1__parses_from_dictionary() {
        let dictionary: [String: Any] = [
            "total": 3,
            "clientIds": ["client1", "client2", "client3"]
        ]

        let summary = ARTSummaryFlagV1(dictionary)

        XCTAssertNotNil(summary)
        XCTAssertEqual(summary?.total, 3)
        XCTAssertEqual(summary?.clientIds, ["client1", "client2", "client3"])
    }

    func test__ARTSummaryFlagV1__returns_nil_for_invalid_dictionary() {
        let invalidDictionary: [String: Any] = [
            "total": 3,
            "clientIds": [123, 456] // Invalid - should be strings
        ]

        let summary = ARTSummaryFlagV1(invalidDictionary)

        XCTAssertNil(summary)
    }

    func test__ARTSummaryFlagV1__with_clipped_property() {
        let dictionary: [String: Any] = [
            "total": 5,
            "clientIds": ["client1", "client2"],
            "clipped": true
        ]

        let summary = ARTSummaryFlagV1(dictionary)

        XCTAssertNotNil(summary)
        XCTAssertEqual(summary?.total, 5)
        XCTAssertEqual(summary?.clientIds, ["client1", "client2"])
        XCTAssertEqual(summary?.clipped, true)
    }

    func test__ARTSummaryMultipleV1__parses_dictionary_of_summaries() {
        let dictionary: [String: Any] = [
            "like": [
                "total": 10,
                "clientIds": [
                    "client1": 5,
                    "client2": 3,
                    "client3": 2
                ]
            ],
            "love": [
                "total": 8,
                "clientIds": [
                    "client1": "5", // String number should be converted
                    "client2": 3    // Regular number should work
                ]
            ]
        ]

        let summaryDict = ARTSummaryMultipleV1(dictionary)

        XCTAssertNotNil(summaryDict)
        XCTAssertEqual(summaryDict?.count, 2)

        let likeSummary = summaryDict?["like"]
        XCTAssertNotNil(likeSummary)
        XCTAssertEqual(likeSummary?.total, 10)
        XCTAssertEqual(likeSummary?.clientIds["client1"], NSNumber(value: 5))
        XCTAssertEqual(likeSummary?.clientIds["client2"], NSNumber(value: 3))
        XCTAssertEqual(likeSummary?.clientIds["client3"], NSNumber(value: 2))

        let loveSummary = summaryDict?["love"]
        XCTAssertNotNil(loveSummary)
        XCTAssertEqual(loveSummary?.total, 8)
        XCTAssertEqual(loveSummary?.clientIds["client1"], NSNumber(value: 5))
        XCTAssertEqual(loveSummary?.clientIds["client2"], NSNumber(value: 3))
    }

    func test__ARTSummaryMultipleV1__returns_nil_for_invalid_values() {
        let invalidDictionary: [String: Any] = [
            "like": [
                "total": 5,
                "clientIds": [
                    "client1": 3,
                    "client2": "invalid_number" // Invalid string that can't be converted
                ]
            ]
        ]

        let summaryDict = ARTSummaryMultipleV1(invalidDictionary)

        // Should return dictionary but with nil values for invalid entries
        XCTAssertNotNil(summaryDict)
        XCTAssertNil(summaryDict?["like"]) // This specific entry should be nil due to invalid data
    }

    func test__ARTSummaryDistinctV1__parses_dictionary_of_summaries() {
        let dictionary: [String: Any] = [
            "like": [
                "total": 3,
                "clientIds": ["client1", "client2", "client3"]
            ],
            "love": [
                "total": 2,
                "clientIds": ["client1", "client4"],
                "clipped": true
            ]
        ]

        let summaryDict = ARTSummaryDistinctV1(dictionary)

        XCTAssertNotNil(summaryDict)
        XCTAssertEqual(summaryDict?.count, 2)

        let likeSummary = summaryDict?["like"]
        XCTAssertNotNil(likeSummary)
        XCTAssertEqual(likeSummary?.total, 3)
        XCTAssertEqual(likeSummary?.clientIds, ["client1", "client2", "client3"])

        let loveSummary = summaryDict?["love"]
        XCTAssertNotNil(loveSummary)
        XCTAssertEqual(loveSummary?.total, 2)
        XCTAssertEqual(loveSummary?.clientIds, ["client1", "client4"])
        XCTAssertEqual(loveSummary?.clipped, true)
    }

    func test__ARTSummaryUniqueV1__parses_dictionary_of_summaries() {
        let dictionary: [String: Any] = [
            "reaction": [
                "total": 5,
                "clientIds": ["user1", "user2", "user3", "user4", "user5"]
            ]
        ]

        let summaryDict = ARTSummaryUniqueV1(dictionary)

        XCTAssertNotNil(summaryDict)
        XCTAssertEqual(summaryDict?.count, 1)

        let reactionSummary = summaryDict?["reaction"]
        XCTAssertNotNil(reactionSummary)
        XCTAssertEqual(reactionSummary?.total, 5)
        XCTAssertEqual(reactionSummary?.clientIds.count, 5)
        XCTAssertTrue(reactionSummary?.clientIds.contains("user1") ?? false)
        XCTAssertTrue(reactionSummary?.clientIds.contains("user5") ?? false)
    }

    func test__ARTSummaryTotalV1__parses_from_dictionary() {
        let dictionary: [String: Any] = [
            "total": 42
        ]

        let summary = ARTSummaryTotalV1(dictionary)

        XCTAssertNotNil(summary)
        XCTAssertEqual(summary?.total, 42)
    }

    func test__ARTSummaryTotalV1__parses_string_number_from_dictionary() {
        let dictionary: [String: Any] = [
            "total": "123" // String number should be converted to integer
        ]

        let summary = ARTSummaryTotalV1(dictionary)

        XCTAssertNotNil(summary)
        XCTAssertEqual(summary?.total, 123)
    }
}
