import Foundation

internal enum LoggingUtilities {
    /// Formats an array of object messages for logging with one message per line.
    /// - Parameter objectMessages: The array of object messages to format
    /// - Returns: A formatted string with one message per line
    internal static func formatObjectMessagesForLogging(_ objectMessages: [some CustomDebugStringConvertible]) -> String {
        guard !objectMessages.isEmpty else {
            return "[]"
        }

        return "[\n" + objectMessages.map { "  \($0)" }.joined(separator: ",\n") + "\n]"
    }
}
