import Foundation

/// The entries stored in a `LiveMap`'s data. Same as an `ObjectsMapEntry` but with an additional `tombstonedAt` property, per RTLM3a.
internal struct InternalObjectsMapEntry: Equatable {
    internal var tombstonedAt: Date? // RTLM3a
    internal var tombstone: Bool {
        // TODO: Confirm that we don't need to store this (https://github.com/ably/specification/pull/350/files#r2213895661)
        tombstonedAt != nil
    }

    internal var timeserial: String? // OME2b
    internal var data: ProtocolTypes.ObjectData? // OME2c
}

internal extension InternalObjectsMapEntry {
    init(objectsMapEntry: ProtocolTypes.ObjectsMapEntry, tombstonedAt: Date?) {
        self.tombstonedAt = tombstonedAt
        timeserial = objectsMapEntry.timeserial
        data = objectsMapEntry.data
    }
}
