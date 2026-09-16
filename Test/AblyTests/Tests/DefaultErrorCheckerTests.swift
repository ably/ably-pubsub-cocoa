import XCTest
import AblyPubSubDevice.Private

final class DefaultErrorCheckerTests: XCTestCase {
    private let checker = DefaultErrorChecker()

    func test_isTokenError_statusCode401AndCodeBetween40140And40150() {
        let errorInfo = ErrorInfo.create(
            withCode: 40145, // arbitrarily chosen in range 40140 ..< 40150
            status: 401,
            message: "" // arbitrarily chosen
        )

        XCTAssertTrue(checker.isTokenError(errorInfo))
    }

    func test_isTokenError_statusCodeNot401() {
        let errorInfo = ErrorInfo.create(
            withCode: 40145, // arbitrarily chosen within range 40140 ..< 40150
            status: 200, // arbitrarily chosen, != 401
            message: "" // arbitrarily chosen
        )

        XCTAssertFalse(checker.isTokenError(errorInfo))
    }

    func test_isTokenError_statusCode401ButCodeLessThan40140() {
        let errorInfo = ErrorInfo.create(
            withCode: 40139, // arbitrarily chosen < 40140
            status: 401,
            message: "" // arbitrarily chosen
        )

        XCTAssertFalse(checker.isTokenError(errorInfo))
    }

    func test_isTokenError_statusCode401ButCodeGreaterThanOrEqualTo40150() {
        let errorInfo = ErrorInfo.create(
            withCode: 40150, // arbitrarily chosen >= 40150
            status: 401,
            message: "" // arbitrarily chosen
        )

        XCTAssertFalse(checker.isTokenError(errorInfo))
    }
}
