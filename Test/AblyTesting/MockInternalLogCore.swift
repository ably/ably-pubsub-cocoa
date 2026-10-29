import AblyPubSubDevice.Private

@objc(ARTMockInternalLogCore)
public class MockInternalLogCore: NSObject, InternalLogCore {
    public var logLevel: LogLevel = .none

    var lastReceivedLogMessageArguments: (message: String, level: LogLevel, fileName: UnsafePointer<CChar>, line: Int)?
    @objc public var lastReceivedLogMessageArgumentMessage: String?
    @objc public var lastReceivedLogMessageArgumentLevel: LogLevel = .none
    @objc public var lastReceivedLogMessageArgumentFileName: UnsafePointer<CChar>?
    @objc public var lastReceivedLogMessageArgumentLine: Int = -1

    public func log(_ message: String, with level: LogLevel, file fileName: UnsafePointer<CChar>, line: Int) {
        lastReceivedLogMessageArguments = (message: message, level: level, fileName: fileName, line: line)
        lastReceivedLogMessageArgumentMessage = message
        lastReceivedLogMessageArgumentLevel = level
        lastReceivedLogMessageArgumentFileName = fileName
        lastReceivedLogMessageArgumentLine = line
    }
}
