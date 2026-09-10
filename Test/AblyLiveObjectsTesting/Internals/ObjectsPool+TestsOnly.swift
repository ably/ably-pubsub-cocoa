@testable import AblyLiveObjects
import Foundation

extension ObjectsPool {
    // MARK: - Test-only initializers

    init(
        logger: Logger,
        internalQueue: DispatchQueue,
        userCallbackQueue: DispatchQueue,
        clock: SimpleClock,
        testsOnly_otherEntries otherEntries: [String: Entry]? = nil,
    ) {
        self.init(
            logger: logger,
            internalQueue: internalQueue,
            userCallbackQueue: userCallbackQueue,
            clock: clock,
            otherEntries: otherEntries,
        )
    }

    // MARK: - Test-only setters

    /// Test-only setter that inserts or replaces an entry for the given object ID.
    mutating func testsOnly_setEntry(_ entry: Entry, forObjectID objectID: String) {
        entries[objectID] = entry
    }
}
