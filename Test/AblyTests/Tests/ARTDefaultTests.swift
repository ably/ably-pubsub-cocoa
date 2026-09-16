import XCTest

import AblyPubSubDevice.ARTDefault // System under Test

class ARTDefaultTests: XCTestCase {

    func testVersions() {
        XCTAssertEqual(Default.apiVersion(), "6")
        XCTAssertEqual(Default.libraryVersion(), "2.0.0")
    }
}
