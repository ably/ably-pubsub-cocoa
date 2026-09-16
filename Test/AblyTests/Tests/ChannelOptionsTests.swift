import AblyPubSubDevice
import XCTest

class ChannelOptionsTests: XCTestCase {
    // MARK: - ChannelOptions

    func test_copyChannelOptions() throws {
        let options = ChannelOptions()
        options.cipher = Crypto.getDefaultParams(["key": Crypto.generateRandomKey()])

        let copied = try XCTUnwrap(options.copy() as? ChannelOptions)

        // Check it creates a new object
        XCTAssertFalse(options === copied)

        // Check properties
        XCTAssertIdentical(options.cipher, copied.cipher)
    }

    func test_copyingFrozenChannelOptions_createsUnfrozenCopy() throws {
        let options = ChannelOptions()
        options.isFrozen = true

        let copied = try XCTUnwrap(options.copy() as? ChannelOptions)
        XCTAssertFalse(copied.isFrozen)
    }

    // MARK: - RealtimeChannelOptions

    func test_copyRealtimeChannelOptions() throws {
        let options = RealtimeChannelOptions()
        options.cipher = Crypto.getDefaultParams(["key": Crypto.generateRandomKey()])
        options.params = ["foo": "bar"]
        options.modes = [.subscribe]
        options.attachOnSubscribe = false

        let copied = try XCTUnwrap(options.copy() as? RealtimeChannelOptions)

        // Check it creates a new object
        XCTAssertFalse(options === copied)

        // Check properties
        XCTAssertIdentical(options.cipher, copied.cipher)
        XCTAssertIdentical(options.params as NSDictionary?, copied.params as NSDictionary?)
        XCTAssertEqual(options.modes, copied.modes)
        XCTAssertEqual(options.attachOnSubscribe, copied.attachOnSubscribe)
    }

    func test_copyingFrozenRealtimeChannelOptions_createsUnfrozenCopy() throws {
        let options = RealtimeChannelOptions()
        options.isFrozen = true

        let copied = try XCTUnwrap(options.copy() as? RealtimeChannelOptions)
        XCTAssertFalse(copied.isFrozen)
    }
}
