import XCTest
import AblyPubSubDevice.Private

class DefaultInternalLogCoreTests: XCTestCase {
    func test_initWithClientOptions_whenClientOptionsLogLevelIsNotNone() throws {
        // Given: client options whose logLevel is .verbose (arbitrarily chosen, not .none), and whose logHandler has logLevel .info (arbitrarily chosen, not equal to .verbose)
        let clientOptions = ClientOptions()
        clientOptions.logLevel = .verbose
        clientOptions.logHandler.logLevel = .info

        // When: we create a DefaultInternalLogCore from these client options
        let core = DefaultInternalLogCore(clientOptions: clientOptions)

        // Then: the created object wraps a LogAdapter instance, which wraps the client options' logHandler, and the client options's logHandler's logLevel gets set to match the client options' logLevel
        let adapter = try XCTUnwrap(core.logger as? LogAdapter)
        let logger = adapter.logger
        XCTAssertEqual(logger, clientOptions.logHandler)
        XCTAssertEqual(clientOptions.logHandler.logLevel, .verbose)
    }

    func test_initWithClientOptions_whenClientOptionsLogLevelIsNone() throws {
        // Given: client options whose logLevel is .none, and whose logHandler has logLevel .info (arbitrarily chosen, not equal to .none)

        let clientOptions = ClientOptions()
        clientOptions.logLevel = .none
        clientOptions.logHandler.logLevel = .info

        // When: we create a DefaultInternalLogCore from these client options
        let core = DefaultInternalLogCore(clientOptions: clientOptions)

        // Then: the created object wraps a LogAdapter instance, which wraps the client options' logHandler, and the client options's logHandler's logLevel does not get changed
        let adapter = try XCTUnwrap(core.logger as? LogAdapter)
        let logger = adapter.logger
        XCTAssertEqual(logger, clientOptions.logHandler)
        XCTAssertEqual(clientOptions.logHandler.logLevel, .info)
    }

    func test_logMessage() {
        let mock = MockVersion2Log()
        let core = DefaultInternalLogCore(logger: mock)

        let logLevels: [LogLevel] = [.verbose, .debug, .info, .warn, .error, .none]
        for (index, level) in logLevels.enumerated() {
            let message = "Message \(index)"
            core.log(message, with: level, file: "/foo/bar/myFile.m", line: 123)

            let logged = mock.lastReceivedLogMessageArguments!
            XCTAssertEqual(logged.level, level)
            XCTAssertEqual(logged.message, message)
            XCTAssertEqual(logged.fileName, "myFile.m")
            XCTAssertEqual(logged.line, 123)
        }
    }

    func test_logLevel() {
        let mock = MockVersion2Log()
        mock.logLevel = .info
        let core = DefaultInternalLogCore(logger: mock)

        XCTAssertEqual(core.logLevel, .info)
    }

    func test_setLogLevel() {
        let mock = MockVersion2Log()
        mock.logLevel = .info
        let core = DefaultInternalLogCore(logger: mock)

        core.logLevel = .debug
        XCTAssertEqual(mock.logLevel, .debug)
    }
}
