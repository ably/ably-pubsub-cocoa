import AblyPubSubDevice
import Nimble
import XCTest

private let links = "<./messages?start=0&end=1535035746063&limit=100&direction=backwards&format=msgpack&firstEnd=1535035746063&fromDate=1535035746063&mode=all>; rel=\"first\", <./messages?start=0&end=1535035746063&limit=100&direction=backwards&format=msgpack&firstEnd=1535035746063&fromDate=1535035746063&mode=all>; rel=\"current\""

private let url = URL(string: "https://sandbox-rest.ably.io:443/channels/foo/messages?limit=100&direction=backwards")!

class RestPaginatedTests: XCTestCase {
    // XCTest invokes this method before executing the first test in the test suite. We use it to ensure that the global variables are initialized at the same moment, and in the same order, as they would have been when we used the Quick testing framework.
    override class var defaultTestSuite: XCTestSuite {
        _ = links
        _ = url

        return super.defaultTestSuite
    }

    func test__001__RestPaginated__should_extract_links_from_the_response() {
        guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Link": links]) else {
            fail("Invalid HTTPURLResponse"); return
        }
        guard let extractedLinks = response.extractLinks() else {
            fail("Couldn't extract links from response"); return
        }
        expect(extractedLinks.keys).to(contain("first", "current"))
    }

    func test__002__RestPaginated__should_create_next_first_last_request_from_extracted_link_path() {
        let request = URLRequest(url: url)

        guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Link": links]) else {
            fail("Invalid HTTPURLResponse"); return
        }
        guard let extractedLinks = response.extractLinks() else {
            fail("Couldn't extract links from response"); return
        }
        expect(extractedLinks.keys).to(contain("first", "current"))

        guard let firstLink = extractedLinks["first"] as? String else {
            fail("First link is missing from extracted links"); return
        }

        guard let firstRequest = NSMutableURLRequest(path: firstLink, relativeTo: request) else {
            fail("First link isn't a valid URL"); return
        }

        XCTAssertEqual(firstRequest.url?.absoluteString, "https://sandbox-rest.ably.io:443/channels/foo/messages?start=0&end=1535035746063&limit=100&direction=backwards&format=msgpack&firstEnd=1535035746063&fromDate=1535035746063&mode=all")
    }
}
