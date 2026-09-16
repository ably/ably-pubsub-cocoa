import AblyPubSubDevice.Private

class MockVersion2Log: NSObject, Version2Log {
    var logLevel: LogLevel = .none

    var lastReceivedLogMessageArguments: (message: String, level: LogLevel, fileName: String, line: Int)?

    func log(_ message: String, with level: LogLevel, file fileName: String, line: Int) {
        lastReceivedLogMessageArguments = (message: message, level: level, fileName: fileName, line: line)
    }
}
