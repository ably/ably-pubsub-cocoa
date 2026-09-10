@testable import AblyLiveObjects
import Foundation

extension ObjectCreationHelpers {
    /// Creates an Object ID for a new LiveObject instance, per RTO14.
    static func testsOnly_createObjectID(
        type: String,
        initialValue: String,
        nonce: String,
        timestamp: Date,
    ) -> String {
        createObjectID(
            type: type,
            initialValue: initialValue,
            nonce: nonce,
            timestamp: timestamp,
        )
    }
}
