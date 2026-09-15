import XCTest
import AblyPubSubDevice.Private

class LogAdapterTests: XCTestCase {
    class MockARTLog: ARTLog {
        var lastReceivedLogMessageArguments: (message: String, level: ARTLogLevel)?

        override func log(_ message: String, with level: ARTLogLevel) {
            lastReceivedLogMessageArguments = (message: message, level: level)
        }
    }

    func test_logMessage() {
        let underlyingLogger = MockARTLog()
        let logger = LogAdapter(logger: underlyingLogger)

        let logLevels: [ARTLogLevel] = [.verbose, .debug, .info, .warn, .error, .none]
        for (index, level) in logLevels.enumerated() {
            let message = "Message \(index)"
            logger.log(message, with: level, file: "myFile.m", line: 123)

            let logged = underlyingLogger.lastReceivedLogMessageArguments!
            XCTAssertEqual(logged.level, level)
            XCTAssertEqual(logged.message, "(myFile.m:123) \(message)")
        }
    }

    func test_logLevel() {
        let underlyingLogger = ARTLog()
        underlyingLogger.logLevel = .info
        let logger = LogAdapter(logger: underlyingLogger)

        XCTAssertEqual(logger.logLevel, .info)
    }

    func test_setLogLevel() {
        let underlyingLogger = ARTLog()
        underlyingLogger.logLevel = .info
        let logger = LogAdapter(logger: underlyingLogger)

        logger.logLevel = .debug
        XCTAssertEqual(underlyingLogger.logLevel, .debug)
    }
}
