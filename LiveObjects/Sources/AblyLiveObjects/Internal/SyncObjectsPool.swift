import Foundation

/// The RTO5f collection of objects gathered during an `OBJECT_SYNC` sequence, ready to be applied to the `ObjectsPool`.
///
/// Every stored message is guaranteed to have a non-nil `.object` with either `.map` or `.counter` populated.
internal struct SyncObjectsPool: Collection {
    /// Keyed by `objectId`. Every value has a non-nil `.object` with either `.map` or `.counter` populated; the
    /// `accumulate` method enforces this invariant.
    private var objectMessages: [String: ProtocolTypes.InboundObjectMessage]

    /// Creates an empty pool.
    internal init() {
        objectMessages = [:]
    }

    /// Accumulates object messages into the pool per RTO5f.
    internal mutating func accumulate(
        _ objectMessages: [ProtocolTypes.InboundObjectMessage],
        logger: Logger,
    ) {
        for objectMessage in objectMessages {
            accumulate(objectMessage, logger: logger)
        }
    }

    /// Accumulates a single `ObjectMessage` into the pool per RTO5f.
    private mutating func accumulate(
        _ objectMessage: ProtocolTypes.InboundObjectMessage,
        logger: Logger,
    ) {
        // RTO5f3: Reject unsupported object types before pool lookup. Only messages whose `.object` has `.map` or `.counter`
        // are stored, which callers of the iteration can rely on.
        guard let object = objectMessage.object, object.map != nil || object.counter != nil else {
            logger.log("Skipping unsupported object type during sync for objectId \(objectMessage.object?.objectId ?? "unknown")", level: .warn)
            return
        }

        let objectId = object.objectId

        if let existing = objectMessages[objectId] {
            // RTO5f2: An entry already exists for this objectId (partial object state).
            if object.map != nil {
                // RTO5f2a: Incoming message has a map.
                if object.tombstone {
                    // RTO5f2a1: Incoming tombstone is true — replace the entire entry.
                    objectMessages[objectId] = objectMessage
                } else {
                    // RTO5f2a2: Merge map entries into the existing message.
                    var merged = existing
                    if let incomingEntries = object.map?.entries {
                        var mergedObject = merged.object!
                        guard var mergedMap = mergedObject.map else {
                            // Not a specified scenario — the server won't send a map and a non-map for the same
                            // objectId in practice. Guard defensively rather than force-unwrapping.
                            logger.log("Existing entry for objectId \(objectId) is not a map; replacing with incoming message", level: .error)
                            objectMessages[objectId] = objectMessage
                            return
                        }
                        var mergedEntries = mergedMap.entries ?? [:]
                        mergedEntries.merge(incomingEntries) { _, new in new }
                        mergedMap.entries = mergedEntries
                        mergedObject.map = mergedMap
                        merged.object = mergedObject
                    }
                    objectMessages[objectId] = merged
                }
            } else {
                // RTO5f2b: Incoming message has a counter — log error, skip.
                logger.log("Received partial counter sync for objectId \(objectId); skipping", level: .error)
            }
        } else {
            // RTO5f1: No entry exists for this objectId — store the message.
            objectMessages[objectId] = objectMessage
        }
    }

    // MARK: - Collection conformance

    internal typealias Index = Dictionary<String, ProtocolTypes.InboundObjectMessage>.Values.Index
    internal typealias Element = ProtocolTypes.InboundObjectMessage

    internal var startIndex: Index { objectMessages.values.startIndex }
    internal var endIndex: Index { objectMessages.values.endIndex }
    internal func index(after i: Index) -> Index { objectMessages.values.index(after: i) }
    internal subscript(position: Index) -> Element { objectMessages.values[position] }
}
