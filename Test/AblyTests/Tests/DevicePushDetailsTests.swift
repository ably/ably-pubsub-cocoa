import AblyPubSubDevice
import AblyPubSubDevice.Private
import Foundation
import XCTest

class DevicePushDetailsTests: XCTestCase {
    private func makeEncoder() -> ARTJsonLikeEncoder {
        ARTJsonLikeEncoder(delegate: ARTJsonEncoder(), timeProvider: SystemTimeProvider())
    }

    private func decodePushDetails(_ jsonObject: [String: Any]) throws -> DevicePushDetails {
        let data = try JSONSerialization.data(withJSONObject: jsonObject, options: [])
        return try makeEncoder().decodeDevicePushDetails(data)
    }

    // PCP4

    func test__decodes_active_state() throws {
        let details = try decodePushDetails(["state": "active", "recipient": [:] as [String: Any]])
        XCTAssertEqual(details.state, .active)
    }

    func test__decodes_failing_state() throws {
        let details = try decodePushDetails(["state": "failing", "recipient": [:] as [String: Any]])
        XCTAssertEqual(details.state, .failing)
    }

    func test__decodes_failed_state() throws {
        let details = try decodePushDetails(["state": "failed", "recipient": [:] as [String: Any]])
        XCTAssertEqual(details.state, .failed)
    }

    func test__decodes_unrecognised_state_as_unknown() throws {
        let details = try decodePushDetails(["state": "dormant", "recipient": [:] as [String: Any]])
        XCTAssertEqual(details.state, .unknown)
    }

    func test__decodes_missing_state_as_unknown() throws {
        let details = try decodePushDetails(["recipient": [:] as [String: Any]])
        XCTAssertEqual(details.state, .unknown)
    }

    func test__decodes_non_string_state_as_unknown() throws {
        let details = try decodePushDetails(["state": 1, "recipient": [:] as [String: Any]])
        XCTAssertEqual(details.state, .unknown)
    }

    func test__decodes_state_nested_in_device_details() throws {
        let jsonObject: [String: Any] = [
            "id": "device-id",
            "platform": "ios",
            "formFactor": "phone",
            "push": [
                "state": "failing",
                "recipient": ["transportType": "apns"],
                "errorReason": ["code": 40000, "statusCode": 400, "message": "bad token"] as [String: Any],
            ] as [String: Any],
        ]
        let data = try JSONSerialization.data(withJSONObject: jsonObject, options: [])
        let device = try makeEncoder().decodeDeviceDetails(data)
        XCTAssertEqual(device.push.state, .failing)
        XCTAssertEqual(device.push.errorReason?.code, 40000)
    }

    func test__new_push_details_have_unknown_state() {
        XCTAssertEqual(DevicePushDetails().state, .unknown)
    }

    func test__copy_preserves_state() throws {
        let details = try decodePushDetails(["state": "failed", "recipient": [:] as [String: Any]])
        let copy = try XCTUnwrap(details.copy() as? DevicePushDetails)
        XCTAssertEqual(copy.state, .failed)
    }

    func test__state_is_not_encoded() throws {
        let details = try decodePushDetails(["state": "active", "recipient": ["transportType": "apns"]])
        let data = try makeEncoder().encode(details)
        let jsonObject = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(jsonObject["state"])
    }

    func test__wire_values_round_trip() {
        let states: [DevicePushState] = [.active, .failing, .failed]
        for state in states {
            let wireValue = ARTDevicePushStateToWireValue(state)
            XCTAssertNotNil(wireValue)
            XCTAssertEqual(ARTDevicePushStateFromWireValue(wireValue), state)
        }
        XCTAssertNil(ARTDevicePushStateToWireValue(.unknown))
    }
}
