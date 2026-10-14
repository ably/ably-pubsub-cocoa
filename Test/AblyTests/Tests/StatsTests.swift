import AblyPubSubDevice
import AblyPubSubDevice.Private
import Foundation
import XCTest

private let encoder = ARTJsonLikeEncoder(delegate: ARTJsonEncoder(), timeProvider: SystemTimeProvider())

private func decodeStats(_ item: [String: Any]) throws -> Stats {
    let rawData = try JSONUtility.serialize([item])
    return try XCTUnwrap(encoder.decodeStats(rawData).first as? Stats)
}

private let statsJSON: [String: Any] = [
    "intervalId": "2004-02-01:05:06",
    "unit": "minute",
    "inProgress": "2004-02-01:05:06",
    "entries": [
        "messages.inbound.realtime.messages.count": 50,
        "messages.inbound.realtime.messages.data": 5000,
        "channels.peak": 10,
    ],
    "schema": "https://schemas.ably.com/json/app-stats-0.0.5.json",
    "appId": "appId",
]

class StatsTests: XCTestCase {
    // TS12a
    func test__Stats__intervalId__is_decoded() throws {
        let stats = try decodeStats(statsJSON)
        XCTAssertEqual(stats.intervalId, "2004-02-01:05:06")
    }

    // TS12p
    func test__Stats__intervalTime__is_the_start_of_the_interval() throws {
        let stats = try decodeStats(statsJSON)

        let dateComponents = NSDateComponents()
        dateComponents.year = 2004
        dateComponents.month = 2
        dateComponents.day = 1
        dateComponents.hour = 5
        dateComponents.minute = 6
        dateComponents.timeZone = NSTimeZone(name: "UTC") as TimeZone?

        let expected = NSCalendar(identifier: NSCalendar.Identifier.gregorian)?.date(from: dateComponents as DateComponents)

        XCTAssertEqual(stats.intervalTime, expected)
    }

    // TS12c
    func test__Stats__unit__is_decoded_from_the_unit_property() throws {
        let expectedUnits: [String: StatsGranularity] = [
            "minute": .minute,
            "hour": .hour,
            "day": .day,
            "month": .month,
        ]
        for (unit, expected) in expectedUnits {
            var json = statsJSON
            json["unit"] = unit
            // The intervalId is minute-level throughout, so the unit can't have been calculated from it
            XCTAssertEqual(try decodeStats(json).unit, expected, "unit \(unit)")
        }
    }

    // TS12q
    func test__Stats__inProgress__is_decoded() throws {
        let stats = try decodeStats(statsJSON)
        XCTAssertEqual(stats.inProgress, "2004-02-01:05:06")
    }

    // TS12q
    func test__Stats__inProgress__is_nil_when_absent() throws {
        var json = statsJSON
        json["inProgress"] = nil
        XCTAssertNil(try decodeStats(json).inProgress)
    }

    // TS12r
    func test__Stats__entries__are_decoded() throws {
        let stats = try decodeStats(statsJSON)
        XCTAssertEqual(stats.entries, [
            "messages.inbound.realtime.messages.count": 50,
            "messages.inbound.realtime.messages.data": 5000,
            "channels.peak": 10,
        ])
    }

    // TS12r
    func test__Stats__entries__keep_only_numeric_values() throws {
        var json = statsJSON
        json["entries"] = ["channels.peak": 10, "channels.name": "foo"] as [String: Any]
        XCTAssertEqual(try decodeStats(json).entries, ["channels.peak": 10])
    }

    // TS12r
    func test__Stats__entries__are_empty_when_absent() throws {
        var json = statsJSON
        json["entries"] = nil
        XCTAssertEqual(try decodeStats(json).entries, [:])
    }

    // TS12s
    func test__Stats__schema__is_decoded() throws {
        let stats = try decodeStats(statsJSON)
        XCTAssertEqual(stats.schema, "https://schemas.ably.com/json/app-stats-0.0.5.json")
    }

    // TS12t
    func test__Stats__appId__is_decoded() throws {
        let stats = try decodeStats(statsJSON)
        XCTAssertEqual(stats.appId, "appId")
    }
}
