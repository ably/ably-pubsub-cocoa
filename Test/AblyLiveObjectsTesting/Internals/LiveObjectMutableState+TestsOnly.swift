@testable import AblyLiveObjects
import Foundation

extension LiveObjectMutableState {
    // MARK: - Test-only initializers

    init(
        objectID: String,
        testsOnly_siteTimeserials siteTimeserials: [String: String] = [:],
        testsOnly_tombstonedAt tombstonedAt: Date? = nil,
    ) {
        self.init(objectID: objectID)
        self.siteTimeserials = siteTimeserials
        self.tombstonedAt = tombstonedAt
    }
}
