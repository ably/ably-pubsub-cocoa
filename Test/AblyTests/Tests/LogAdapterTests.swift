import XCTest
import AblyPubSubDevice.Private

class LogAdapterTests: XCTestCase {
    class MockARTLog: Log {
        var lastReceivedLogMessageArguments: (message: String, level: LogLevel)?

        override func log(_ message: String, with level: LogLevel) {
            lastReceivedLogMessageArguments = (message: message, level: level)
        }
    }

    func test_logMessage() {
        let underlyingLogger = MockARTLog()
        let logger = LogAdapter(logger: underlyingLogger)

        let logLevels: [LogLevel] = [.verbose, .debug, .info, .warn, .error, .none]
        for (index, level) in logLevels.enumerated() {
            let message = "Message \(index)"
            logger.log(message, with: level, file: "myFile.m", line: 123)

            let logged = underlyingLogger.lastReceivedLogMessageArguments!
            XCTAssertEqual(logged.level, level)
            XCTAssertEqual(logged.message, "(myFile.m:123) \(message)")
        }
    }

    func test_logLevel() {
        let underlyingLogger = Log()
        underlyingLogger.logLevel = .info
        let logger = LogAdapter(logger: underlyingLogger)

        XCTAssertEqual(logger.logLevel, .info)
    }

    func test_setLogLevel() {
        let underlyingLogger = Log()
        underlyingLogger.logLevel = .info
        let logger = LogAdapter(logger: underlyingLogger)

        logger.logLevel = .debug
        XCTAssertEqual(underlyingLogger.logLevel, .debug)
    }
}
