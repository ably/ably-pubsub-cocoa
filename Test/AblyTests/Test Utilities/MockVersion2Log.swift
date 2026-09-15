import AblyPubSubDevice.Private

class MockVersion2Log: NSObject, Version2Log {
    var logLevel: ARTLogLevel = .none

    var lastReceivedLogMessageArguments: (message: String, level: ARTLogLevel, fileName: String, line: Int)?

    func log(_ message: String, with level: ARTLogLevel, file fileName: String, line: Int) {
        lastReceivedLogMessageArguments = (message: message, level: level, fileName: fileName, line: line)
    }
}
