import XCTest

import Ably.ARTDefault // System under Test

class ARTDefaultTests: XCTestCase {

    func testVersions() {
        XCTAssertEqual(ARTDefault.apiVersion(), "6")
        XCTAssertEqual(ARTDefault.libraryVersion(), "2.0.0")
    }
}
