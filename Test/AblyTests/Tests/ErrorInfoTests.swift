import AblyPubSubDevice
import XCTest

class ErrorInfoTests: XCTestCase {
    func test__001__ErrorInfo__from_a_system_error__keeps_it_as_the_underlying_error() throws {
        let systemError = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotFindHost, userInfo: [NSLocalizedDescriptionKey: "A server with the specified hostname could not be found."])

        let error = ErrorInfo.create(from: systemError)

        XCTAssertEqual(error.domain, ablyErrorDomain)
        XCTAssertEqual(error.code, Int(ErrorCode.internalError.rawValue))
        XCTAssertEqual(error.statusCode, 500)
        XCTAssertEqual(error.message, "A server with the specified hostname could not be found.")
        let underlyingError = try XCTUnwrap(error.underlyingErrors.first as NSError?)
        XCTAssertEqual(underlyingError.domain, NSURLErrorDomain)
        XCTAssertEqual(underlyingError.code, NSURLErrorCannotFindHost)
        XCTAssertNil(error.cause)
    }

    func test__002__ErrorInfo__from_a_URL_timeout__has_the_timeout_code() throws {
        let systemError = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut, userInfo: nil)

        let error = ErrorInfo.create(from: systemError)

        XCTAssertEqual(error.domain, ablyErrorDomain)
        XCTAssertEqual(error.code, Int(ErrorCode.timeoutError.rawValue))
        XCTAssertEqual(error.statusCode, 500)
        let underlyingError = try XCTUnwrap(error.underlyingErrors.first as NSError?)
        XCTAssertEqual(underlyingError.code, NSURLErrorTimedOut)
    }

    func test__003__ErrorInfo__from_an_Ably_domain_error__keeps_its_code() {
        let ablyError = NSError(domain: ablyErrorDomain, code: 40140, userInfo: [NSLocalizedDescriptionKey: "token error"])

        let error = ErrorInfo.create(from: ablyError)

        XCTAssertEqual(error.domain, ablyErrorDomain)
        XCTAssertEqual(error.code, 40140)
        XCTAssertEqual(error.message, "token error")
        XCTAssertTrue(error.underlyingErrors.isEmpty)
    }

    func test__004__ErrorInfo__wrap__keeps_the_underlying_error() throws {
        let systemError = NSError(domain: NSPOSIXErrorDomain, code: Int(ENETDOWN), userInfo: nil)

        let error = ErrorInfo.wrap(ErrorInfo.create(from: systemError), prepend: "Request failed with ")

        XCTAssertTrue(error.message.hasPrefix("Request failed with "))
        let underlyingError = try XCTUnwrap(error.underlyingErrors.first as NSError?)
        XCTAssertEqual(underlyingError.domain, NSPOSIXErrorDomain)
        XCTAssertEqual(underlyingError.code, Int(ENETDOWN))
    }

    func test__005__ErrorInfo__cause__returns_an_underlying_ErrorInfo() throws {
        let underlyingError = ErrorInfo.create(withCode: 40140, message: "token error")

        let error = ErrorInfo.create(withCode: 80019, message: "auth failed", additionalUserInfo: [NSUnderlyingErrorKey: underlyingError])

        let cause = try XCTUnwrap(error.cause)
        XCTAssertIdentical(cause, underlyingError)
        XCTAssertEqual(cause.code, 40140)
        XCTAssertEqual(cause.message, "token error")
    }

    func test__006__ErrorInfo__cause__converts_an_underlying_Ably_domain_error() throws {
        let underlyingError = NSError(domain: ablyErrorDomain, code: 40140, userInfo: [NSLocalizedDescriptionKey: "token error"])

        let error = ErrorInfo.create(withCode: 80019, message: "auth failed", additionalUserInfo: [NSUnderlyingErrorKey: underlyingError])

        let cause = try XCTUnwrap(error.cause)
        XCTAssertEqual(cause.domain, ablyErrorDomain)
        XCTAssertEqual(cause.code, 40140)
        XCTAssertEqual(cause.message, "token error")
    }
}
