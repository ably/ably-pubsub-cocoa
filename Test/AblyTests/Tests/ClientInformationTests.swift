import XCTest
import Ably

final class ClientInformationTests: XCTestCase {

    // CR2, CR2a
    func testAgents() {
        let agents = ARTClientInformation.agents

        XCTAssertEqual(agents.keys.count, 2)

        XCTAssertEqual(agents["ably-pubsub-cocoa"], "2.0.0")

        #if os(iOS)
        XCTAssertTrue(agents.keys.contains("iOS"))
        #elseif os(tvOS)
        XCTAssertTrue(agents.keys.contains("tvOS"))
        #elseif os(watchOS)
        XCTAssertTrue(agents.keys.contains("watchOS"))
        #elseif os(macOS)
        XCTAssertTrue(agents.keys.contains("macOS"))
        #else
        #error("Building for unknown OS")
        #endif
    }

    // CR3, CR3b
    func testAgentIdentifierWithAdditionalAgents_withNilAdditionalAgents() {
        let expectedIdentifier = [
            "ably-pubsub-cocoa/2.0.0",
            ARTDefault.platformAgent()
        ].sorted().joined(separator: " ")

        XCTAssertEqual(ARTClientInformation.agentIdentifier(withAdditionalAgents: nil), expectedIdentifier)
    }

    // CR3, CR3b, CR3c
    func testAgentIdentifierWithAdditionalAgents_withNonNilAdditionalAgents() {
        let additionalAgents = [
            "demolib": "0.0.1",
            "morelib": ARTClientInformationAgentNotVersioned
        ]

        let expectedIdentifier = [
            "ably-pubsub-cocoa/2.0.0",
            "demolib/0.0.1",
            "morelib",
            ARTDefault.platformAgent()
        ].sorted().joined(separator: " ")

        XCTAssertEqual(ARTClientInformation.agentIdentifier(withAdditionalAgents: additionalAgents), expectedIdentifier)
    }
}
