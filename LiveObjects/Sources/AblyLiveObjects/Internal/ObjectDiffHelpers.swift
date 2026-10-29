import Foundation

/// Helper methods for calculating diffs between LiveObject data values.
internal enum ObjectDiffHelpers {
    /// Calculates the diff between two LiveCounter data values, per RTLC14.
    ///
    /// - Parameters:
    ///   - previousData: The previous `data` value (RTLC14a1).
    ///   - newData: The new `data` value (RTLC14a2).
    /// - Returns: Per RTLC14b.
    internal static func calculateCounterDiff(
        previousData: Double,
        newData: Double,
    ) -> LiveObjectUpdate<DefaultLiveCounterUpdate> {
        // RTLC14c: a zero delta (newData == previousData) is a no-op update per RTLO4b4b, not a spurious zero-amount update.
        if newData == previousData {
            return .noop
        }
        return .update(DefaultLiveCounterUpdate(amount: newData - previousData))
    }

    /// Calculates the diff between two LiveMap data values, per RTLM22.
    ///
    /// - Parameters:
    ///   - previousData: The previous `data` value (RTLM22a1).
    ///   - newData: The new `data` value (RTLM22a2).
    /// - Returns: Per RTLM22b.
    internal static func calculateMapDiff(
        previousData: [String: InternalObjectsMapEntry],
        newData: [String: InternalObjectsMapEntry],
    ) -> LiveObjectUpdate<DefaultLiveMapUpdate> {
        // RTLM22b
        let previousNonTombstonedKeys = Set(previousData.filter { !$0.value.tombstone }.keys)
        let newNonTombstonedKeys = Set(newData.filter { !$0.value.tombstone }.keys)

        var update: [String: LiveMapUpdateAction] = [:]

        // RTLM22b1
        for key in previousNonTombstonedKeys.subtracting(newNonTombstonedKeys) {
            update[key] = .removed
        }

        // RTLM22b2
        for key in newNonTombstonedKeys.subtracting(previousNonTombstonedKeys) {
            update[key] = .updated
        }

        // RTLM22b3
        for key in previousNonTombstonedKeys.intersection(newNonTombstonedKeys) {
            let previousEntry = previousData[key]!
            let newEntry = newData[key]!

            if previousEntry.data != newEntry.data {
                update[key] = .updated
            }
        }

        // RTLM22c: an empty key diff (no changed keys) is a no-op update per RTLO4b4b, not a spurious empty update.
        if update.isEmpty {
            return .noop
        }

        return .update(DefaultLiveMapUpdate(update: update))
    }
}
