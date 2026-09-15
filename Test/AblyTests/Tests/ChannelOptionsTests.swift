import AblyPubSubDevice
import XCTest

class ChannelOptionsTests: XCTestCase {
    // MARK: - ARTChannelOptions

    func test_copyChannelOptions() throws {
        let options = ARTChannelOptions()
        options.cipher = ARTCrypto.getDefaultParams(["key": ARTCrypto.generateRandomKey()])

        let copied = try XCTUnwrap(options.copy() as? ARTChannelOptions)

        // Check it creates a new object
        XCTAssertFalse(options === copied)

        // Check properties
        XCTAssertIdentical(options.cipher, copied.cipher)
    }

    func test_copyingFrozenChannelOptions_createsUnfrozenCopy() throws {
        let options = ARTChannelOptions()
        options.isFrozen = true

        let copied = try XCTUnwrap(options.copy() as? ARTChannelOptions)
        XCTAssertFalse(copied.isFrozen)
    }

    // MARK: - ARTRealtimeChannelOptions

    func test_copyRealtimeChannelOptions() throws {
        let options = ARTRealtimeChannelOptions()
        options.cipher = ARTCrypto.getDefaultParams(["key": ARTCrypto.generateRandomKey()])
        options.params = ["foo": "bar"]
        options.modes = [.subscribe]
        options.attachOnSubscribe = false

        let copied = try XCTUnwrap(options.copy() as? ARTRealtimeChannelOptions)

        // Check it creates a new object
        XCTAssertFalse(options === copied)

        // Check properties
        XCTAssertIdentical(options.cipher, copied.cipher)
        XCTAssertIdentical(options.params as NSDictionary?, copied.params as NSDictionary?)
        XCTAssertEqual(options.modes, copied.modes)
        XCTAssertEqual(options.attachOnSubscribe, copied.attachOnSubscribe)
    }

    func test_copyingFrozenRealtimeChannelOptions_createsUnfrozenCopy() throws {
        let options = ARTRealtimeChannelOptions()
        options.isFrozen = true

        let copied = try XCTUnwrap(options.copy() as? ARTRealtimeChannelOptions)
        XCTAssertFalse(copied.isFrozen)
    }
}
