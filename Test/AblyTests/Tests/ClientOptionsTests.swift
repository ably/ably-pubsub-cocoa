import AblyPubSubDevice
import XCTest

class ClientOptionsTests: XCTestCase {
    // TO3l11, TO3l8, TO3l9
    func test_defaults() {
        let options = ClientOptions()

        XCTAssertEqual(options.realtimeRequestTimeout, 10.0) // Seconds
        XCTAssertEqual(options.maxMessageSize, 65536)
        XCTAssertEqual(options.maxFrameSize, 524288)
    }

    func test_copyClientOptions() throws {
        let options = ClientOptions()
        options.realtimeRequestTimeout = 3.0
        options.maxMessageSize = 1024
        options.maxFrameSize = 2048

        let copied = try XCTUnwrap(options.copy() as? ClientOptions)

        XCTAssertEqual(copied.realtimeRequestTimeout, 3.0)
        XCTAssertEqual(copied.maxMessageSize, 1024)
        XCTAssertEqual(copied.maxFrameSize, 2048)
    }
}
