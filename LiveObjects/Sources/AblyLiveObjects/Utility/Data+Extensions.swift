import Ably
import Foundation

/// Errors that can occur during decoding operations.
internal enum DecodingError: Error, Equatable {
    case invalidBase64String(String)
}

internal extension Data {
    /// Initialize Data from a Base64-encoded string, throwing an error if decoding fails.
    /// - Parameter base64String: The Base64-encoded string to decode
    /// - Throws: `ARTErrorInfo` if the string cannot be decoded as Base64
    static func fromBase64Throwing(_ base64String: String) throws(ARTErrorInfo) -> Data {
        guard let data = Data(base64Encoded: base64String) else {
            throw DecodingError.invalidBase64String(base64String).toARTErrorInfo()
        }
        return data
    }
}
