internal import _AblyPluginSupportPrivate

/// A reference to a line within a source code file.
internal struct CodeLocation: Equatable {
    /// A file identifier in the format used by Swift's `#fileID` macro. For example, `"AblyChat/Room.swift"`.
    internal var fileID: String
    /// The line number in the source code file referred to by ``fileID``.
    internal var line: Int
}

internal protocol Logger: Sendable {
    func log(_ message: String, level: _AblyPluginSupportPrivate.LogLevel, codeLocation: CodeLocation)
}

internal extension AblyLiveObjects.Logger {
    /// A convenience method that provides default values for `file` and `line`.
    func log(_ message: String, level: _AblyPluginSupportPrivate.LogLevel, fileID: String = #fileID, line: Int = #line) {
        let codeLocation = CodeLocation(fileID: fileID, line: line)
        log(message, level: level, codeLocation: codeLocation)
    }
}

internal final class DefaultLogger: Logger {
    private let pluginLogger: _AblyPluginSupportPrivate.Logger
    private let pluginAPI: _AblyPluginSupportPrivate.PluginAPIProtocol

    internal init(pluginLogger: _AblyPluginSupportPrivate.Logger, pluginAPI: _AblyPluginSupportPrivate.PluginAPIProtocol) {
        self.pluginLogger = pluginLogger
        self.pluginAPI = pluginAPI
    }

    internal func log(_ message: String, level: LogLevel, codeLocation: CodeLocation) {
        pluginAPI.log(
            message,
            with: level,
            file: codeLocation.fileID,
            line: codeLocation.line,
            logger: pluginLogger,
        )
    }
}
