internal import _AblyPluginSupportPrivate

/// Maintains the list of objects present on a channel, as described by RTO3.
///
/// Note that this is a value type.
internal struct ObjectsPool {
    /// The possible `ObjectsPool` entries, as described by RTO3a.
    internal enum Entry {
        case map(InternalDefaultLiveMap)
        case counter(InternalDefaultLiveCounter)

        /// Convenience getter for accessing the map value if this entry is a map
        internal var mapValue: InternalDefaultLiveMap? {
            switch self {
            case let .map(map):
                map
            case .counter:
                nil
            }
        }

        /// Convenience getter for accessing the counter value if this entry is a counter
        internal var counterValue: InternalDefaultLiveCounter? {
            switch self {
            case .map:
                nil
            case let .counter(counter):
                counter
            }
        }

        /// The outcome of applying an operation to a LiveObject, carrying both the RTO9a2a4 dedup
        /// signal and what the RTO24 path-subscription dispatch needs.
        internal struct ApplyResult {
            /// `true` if an operation was applied (a non-nil update, including a `.noop`), `false` if
            /// it was skipped (RTLM15g/RTLC7g). Drives the RTO9a2a4 applied-on-ACK dedup.
            internal let applied: Bool
            /// The changed map keys of the emitted update, used to build the RTO24b2a2 deeper path
            /// candidates (empty for a counter update). `nil` when nothing should be dispatched to
            /// path subscriptions — i.e. the operation was skipped or produced a `.noop` update
            /// (RTLO4b4c1). A non-`nil` (possibly empty) value means "dispatch a path event".
            internal let changedMapKeysForPathEvent: [String]?
        }

        /// Applies an operation to a LiveObject, per RTO9a2a3.
        internal func nosync_apply(
            _ operation: ProtocolTypes.ObjectOperation,
            source: ObjectsOperationSource,
            objectMessage: ProtocolTypes.InboundObjectMessage,
            objectsPool: inout ObjectsPool,
        ) -> ApplyResult {
            switch self {
            case let .map(map):
                // A non-`.noop` map update carries the set of keys it changed; those drive the
                // RTO24b2a2 deeper path candidates. A `nil`/`.noop` update dispatches nothing.
                let update = map.nosync_apply(
                    operation,
                    source: source,
                    objectMessage: objectMessage,
                    objectsPool: &objectsPool,
                )
                return .init(applied: update != nil, changedMapKeysForPathEvent: update?.update.map { Array($0.update.keys) })
            case let .counter(counter):
                // A counter update contributes no deeper candidates; a non-`.noop` update still
                // dispatches a path event at the object's own path (empty key list).
                let update = counter.nosync_apply(
                    operation,
                    source: source,
                    objectMessage: objectMessage,
                    objectsPool: &objectsPool,
                )
                return .init(applied: update != nil, changedMapKeysForPathEvent: update?.update.map { _ in [String]() })
            }
        }

        /// A LiveObject plus an update that can be emitted on this LiveObject. Can be used to store pending events while applying the `SyncObjectsPool`.
        fileprivate enum DeferredUpdate {
            case map(InternalDefaultLiveMap, LiveObjectUpdate<DefaultLiveMapUpdate>)
            case counter(InternalDefaultLiveCounter, LiveObjectUpdate<DefaultLiveCounterUpdate>)

            /// Causes the referenced `LiveObject` to emit the stored event to its subscribers.
            ///
            /// If the update tombstones the object (a sync-originated tombstone, RTLM6f/RTLC6f), the
            /// object's subscriptions are deregistered after emitting, per the RTLO4b4c3c teardown.
            internal func nosync_emit() {
                switch self {
                case let .map(map, update):
                    map.nosync_emit(update)
                    if update.tombstone {
                        map.nosync_deregisterSubscriptionsForTombstone()
                    }
                case let .counter(counter, update):
                    counter.nosync_emit(update)
                    if update.tombstone {
                        counter.nosync_deregisterSubscriptionsForTombstone()
                    }
                }
            }

            /// What the RTO24 path-subscription dispatch needs for this deferred (sync-originated)
            /// update: the updated object's ID and the changed map keys (the RTO24b2a2 deeper
            /// candidates; empty for a counter). `nil` for a `.noop` update — noops dispatch nothing
            /// (RTLO4b4c1).
            internal var nosync_pathDispatchInfo: (objectID: String, changedMapKeys: [String])? {
                switch self {
                case let .map(map, update):
                    guard let payload = update.update else {
                        return nil // .noop
                    }
                    return (objectID: map.objectID, changedMapKeys: Array(payload.update.keys))
                case let .counter(counter, update):
                    guard update.update != nil else {
                        return nil // .noop
                    }
                    return (objectID: counter.objectID, changedMapKeys: [])
                }
            }
        }

        /// Overrides the internal data for the object as per RTLC6, RTLM6.
        ///
        /// Returns a ``DeferredUpdate`` which contains the object plus an update that should be emitted on this object once the `SyncObjectsPool` has been applied.
        ///
        /// - Parameters:
        ///   - objectMessageSerialTimestamp: The `serialTimestamp` of the containing `ObjectMessage`. Used if we need to tombstone the object.
        fileprivate func nosync_replaceData(
            using state: ProtocolTypes.ObjectState,
            objectMessageSerialTimestamp: Date?,
            objectsPool: inout ObjectsPool,
            userCallbackQueue: DispatchQueue,
        ) -> DeferredUpdate {
            switch self {
            case let .map(map):
                .map(
                    map,
                    map.nosync_replaceData(
                        using: state,
                        objectMessageSerialTimestamp: objectMessageSerialTimestamp,
                        objectsPool: &objectsPool,
                    ),
                )
            case let .counter(counter):
                .counter(
                    counter,
                    counter.nosync_replaceData(
                        using: state,
                        objectMessageSerialTimestamp: objectMessageSerialTimestamp,
                    ),
                )
            }
        }

        /// Returns the object's RTLO3d `isTombstone` property.
        internal var nosync_isTombstone: Bool {
            switch self {
            case let .counter(counter):
                counter.nosync_isTombstone
            case let .map(map):
                map.nosync_isTombstone
            }
        }

        internal var nosync_tombstonedAt: Date? {
            switch self {
            case let .counter(counter):
                counter.nosync_tombstonedAt
            case let .map(map):
                map.nosync_tombstonedAt
            }
        }

        // MARK: - Parent-reference graph (RTLO3f)

        /// The object's RTLO3f `parentReferences`.
        internal var nosync_parentReferences: [String: Set<String>] {
            switch self {
            case let .counter(counter):
                counter.nosync_parentReferences
            case let .map(map):
                map.nosync_parentReferences
            }
        }

        /// Records that the map identified by `parentObjectID` references this object at `key`, per RTLO4g.
        internal func nosync_addParentReference(parentObjectID: String, key: String) {
            switch self {
            case let .counter(counter):
                counter.nosync_addParentReference(parentObjectID: parentObjectID, key: key)
            case let .map(map):
                map.nosync_addParentReference(parentObjectID: parentObjectID, key: key)
            }
        }

        /// Removes the recorded reference from the map identified by `parentObjectID` at `key`, per RTLO4h.
        internal func nosync_removeParentReference(parentObjectID: String, key: String) {
            switch self {
            case let .counter(counter):
                counter.nosync_removeParentReference(parentObjectID: parentObjectID, key: key)
            case let .map(map):
                map.nosync_removeParentReference(parentObjectID: parentObjectID, key: key)
            }
        }

        /// Resets `parentReferences` to an empty map, per RTO5c10a.
        internal func nosync_clearParentReferences() {
            switch self {
            case let .counter(counter):
                counter.nosync_clearParentReferences()
            case let .map(map):
                map.nosync_clearParentReferences()
            }
        }
    }

    /// Keyed by `objectId`.
    ///
    /// Per RTO3b, always contains an entry for `ObjectsPool.rootKey`, and this entry is always of type `map`.
    internal var entries: [String: Entry] // internal setter for AblyLiveObjectsTesting

    /// The key under which the root object is stored.
    internal static let rootKey = "root"

    // MARK: - Initialization

    /// Creates an `ObjectsPool` whose root is a zero-value `LiveMap`.
    internal init(
        logger: Logger,
        internalQueue: DispatchQueue,
        userCallbackQueue: DispatchQueue,
        clock: SimpleClock,
    ) {
        self.init(
            logger: logger,
            internalQueue: internalQueue,
            userCallbackQueue: userCallbackQueue,
            clock: clock,
            otherEntries: nil,
        )
    }

    internal init( // internal for AblyLiveObjectsTesting
        logger: Logger,
        internalQueue: DispatchQueue,
        userCallbackQueue: DispatchQueue,
        clock: SimpleClock,
        otherEntries: [String: Entry]?
    ) {
        entries = otherEntries ?? [:]
        // TODO: What initial root entry to use? https://github.com/ably/specification/pull/333/files#r2152312933
        entries[Self.rootKey] = .map(
            .createZeroValued(
                objectID: Self.rootKey,
                logger: logger,
                internalQueue: internalQueue,
                userCallbackQueue: userCallbackQueue,
                clock: clock,
            ),
        )
    }

    // MARK: - Typed root

    /// Fetches the root object.
    internal var root: InternalDefaultLiveMap {
        guard let rootEntry = entries[Self.rootKey] else {
            preconditionFailure("ObjectsPool should always contain a root object")
        }

        switch rootEntry {
        case let .map(map):
            return map
        case .counter:
            preconditionFailure("The ObjectsPool root object must always be a map")
        }
    }

    // MARK: - Data manipulation

    /// Creates a zero-value object if it does not exist in the pool, per RTO6. This is used when applying a `MAP_SET` operation that contains a reference to another object.
    ///
    /// - Parameters:
    ///   - objectID: The ID of the object to create
    ///   - logger: The logger to use for any created LiveObject
    ///   - userCallbackQueue: The callback queue to use for any created LiveObject
    ///   - clock: The clock to use for any created LiveObject
    /// - Returns: The existing or newly created object
    internal mutating func createZeroValueObject(
        forObjectID objectID: String,
        logger: Logger,
        internalQueue: DispatchQueue,
        userCallbackQueue: DispatchQueue,
        clock: SimpleClock,
    ) -> Entry? {
        // RTO6a: If an object with objectId exists in ObjectsPool, do not create a new object
        if let existingEntry = entries[objectID] {
            return existingEntry
        }

        // RTO6b: The expected type of the object can be inferred from the provided objectId
        // RTO6b1: Split the objectId (formatted as type:hash@timestamp) on the separator : and parse the first part as the type string
        let components = objectID.split(separator: ":")
        guard let typeString = components.first else {
            return nil
        }

        // RTO6b2: If the parsed type is map, create a zero-value LiveMap per RTLM4 in the ObjectsPool
        // RTO6b3: If the parsed type is counter, create a zero-value LiveCounter per RTLC4 in the ObjectsPool
        let entry: Entry
        switch typeString {
        case "map":
            entry = .map(
                .createZeroValued(
                    objectID: objectID,
                    logger: logger,
                    internalQueue: internalQueue,
                    userCallbackQueue: userCallbackQueue,
                    clock: clock,
                ),
            )
        case "counter":
            entry = .counter(
                .createZeroValued(
                    objectID: objectID,
                    logger: logger,
                    internalQueue: internalQueue,
                    userCallbackQueue: userCallbackQueue,
                    clock: clock,
                ),
            )
        default:
            return nil
        }

        // Note that already know that the key is not "root" per the above check so there's no risk of breaking the RTO3b invariant that the root object is always a map
        entries[objectID] = entry
        return entry
    }

    /// Applies the objects gathered during an `OBJECT_SYNC` to this `ObjectsPool`, per RTO5c1 and RTO5c2.
    ///
    /// - Parameter pathObjectSubscriptionRegister: When non-nil, each non-noop RTO5c7 deferred update
    ///   also fans out to path subscriptions with a `nil` message (RTO4b2a — sync-originated updates
    ///   never surface a public message), after the RTO5c10 parent-reference rebuild so paths reflect
    ///   the post-sync graph. `nil` (the default, used by tests driving the pool directly) skips path
    ///   dispatch.
    internal mutating func nosync_applySyncObjectsPool(
        _ syncObjectsPool: SyncObjectsPool,
        logger: Logger,
        internalQueue: DispatchQueue,
        userCallbackQueue: DispatchQueue,
        clock: SimpleClock,
        pathObjectSubscriptionRegister: PathObjectSubscriptionRegister? = nil,
    ) {
        logger.log("applySyncObjectsPool called with \(syncObjectsPool.count) objects", level: .debug)

        // Keep track of object IDs that were received during sync for RTO5c2
        var receivedObjectIds = Set<String>()

        // Keep track of updates to existing objects during sync for RTO5c1a2
        var updatesToExistingObjects: [ObjectsPool.Entry.DeferredUpdate] = []

        // RTO5c1: For each ObjectState member in the SyncObjectsPool list
        for objectMessage in syncObjectsPool {
            // Every message yielded by SyncObjectsPool is guaranteed to have a non-nil `.object` with `.map` or `.counter`.
            guard let state = objectMessage.object else {
                preconditionFailure("SyncObjectsPool yielded a message with nil object")
            }
            receivedObjectIds.insert(state.objectId)

            // RTO5c1a: If an object with ObjectState.objectId exists in the internal ObjectsPool
            if let existingEntry = entries[state.objectId] {
                logger.log("Updating existing object with ID: \(state.objectId)", level: .debug)

                // RTO5c1a1: Override the internal data for the object as per RTLC6, RTLM6
                let deferredUpdate = existingEntry.nosync_replaceData(
                    using: state,
                    objectMessageSerialTimestamp: objectMessage.serialTimestamp,
                    objectsPool: &self,
                    userCallbackQueue: userCallbackQueue,
                )
                // RTO5c1a2: Store this update to emit at end
                updatesToExistingObjects.append(deferredUpdate)
            } else {
                // RTO5c1b: If an object with ObjectState.objectId does not exist in the internal ObjectsPool
                // (The nosync_createObjectFromSync precondition that this is not the root object is satisfied because the pool always contains a root object. The precondition that state has counter or map is satisfied because SyncObjectsPool guarantees this for every yielded message.)
                nosync_createObjectFromSync(
                    objectMessage: objectMessage,
                    logger: logger,
                    internalQueue: internalQueue,
                    userCallbackQueue: userCallbackQueue,
                    clock: clock,
                )
            }
        }

        // RTO5c2: Remove any objects from the internal ObjectsPool for which objectIds were not received during the sync sequence
        // RTO5c2a: The object with ID "root" must not be removed from ObjectsPool, as per RTO3b
        let objectIdsToRemove = Set(entries.keys).subtracting(receivedObjectIds + [Self.rootKey])
        if !objectIdsToRemove.isEmpty {
            logger.log("Removing objects with IDs: \(objectIdsToRemove) as they were not in sync", level: .debug)
            for objectId in objectIdsToRemove {
                entries.removeValue(forKey: objectId)
            }
        }

        // RTO5c10: rebuild every parentReferences map after the pool has settled, so that
        // getFullPaths is correct by the time the RTO5c7 notifications below are dispatched
        nosync_rebuildParentReferences()

        // RTO5c7: Emit the updates to existing objects
        for deferredUpdate in updatesToExistingObjects {
            deferredUpdate.nosync_emit()

            // RTLO4b4c3b -> RTO24b: fan the sync-originated update out to path subscriptions too,
            // with a nil message (RTO4b2a). This runs after the RTO5c10 rebuild above, so the
            // getFullPaths DFS sees the post-sync graph. Noop updates dispatch nothing (RTLO4b4c1).
            if let register = pathObjectSubscriptionRegister, let info = deferredUpdate.nosync_pathDispatchInfo {
                nosync_notifyPathSubscriptions(
                    objectID: info.objectID,
                    changedMapKeys: info.changedMapKeys,
                    objectMessage: nil,
                    channelName: nil,
                    register: register,
                )
            }
        }

        logger.log("applySyncObjectsPool completed. Pool now contains \(entries.count) objects", level: .debug)
    }

    /// Rebuilds all parent references from the settled pool state, per RTO5c10. Necessary after a
    /// sync because objects may reference other objects that were not yet in the pool when their
    /// references were first applied.
    internal mutating func nosync_rebuildParentReferences() {
        // RTO5c10a: reset every object's parentReferences to the initial (empty) value
        for entry in entries.values {
            entry.nosync_clearParentReferences()
        }

        // RTO5c10b: for each map, re-add a reference on every non-tombstoned object-valued entry.
        // We iterate the raw entries (rather than the resolved value() surface) since only
        // entry.data.objectId is needed here; tombstoned entries (RTLM14) are skipped.
        for (parentObjectID, entry) in entries {
            guard case let .map(map) = entry else {
                continue
            }
            for (key, mapEntry) in map.nosync_rawData {
                guard let refId = mapEntry.data?.objectId else {
                    continue
                }
                if InternalDefaultLiveMap.nosync_isEntryTombstoned(mapEntry, objectsPool: self) {
                    continue
                }
                entries[refId]?.nosync_addParentReference(parentObjectID: parentObjectID, key: key)
            }
        }
    }

    /// All key-paths from the root object to the object identified by `objectID`, per RTLO4f: one
    /// per simple path in the parent-reference graph, cycle-safe, order unspecified. Returns `[[]]`
    /// when `objectID` is root itself, and `[]` for an orphan (or an object absent from the pool).
    ///
    /// The DFS resolves each node's `parentReferences` through a brief, independent read
    /// (`Entry.nosync_parentReferences`); it deliberately never keeps a single object's queue-mutex
    /// open across the walk, so revisiting a node cannot cause an exclusive-access conflict.
    internal func nosync_getFullPaths(forObjectID objectID: String) -> [[String]] {
        var paths: [[String]] = []

        // Each stack element pairs the object being visited with the path built so far and the set
        // of objectIDs already visited on this branch.
        var stack: [(objectID: String, path: [String], visited: Set<String>)] = [
            (objectID: objectID, path: [], visited: []),
        ]

        while let (currentID, currentPath, visited) = stack.popLast() {
            // RTLO4f2: simple paths only — skip a node already visited on this branch (cycles)
            if visited.contains(currentID) {
                continue
            }
            let newVisited = visited.union([currentID])

            // RTLO4f2: the empty path is contributed only when the walk reaches root
            if currentID == Self.rootKey {
                paths.append(currentPath)
                continue
            }

            // A stale/absent object (left the pool) contributes no further path
            guard let parentReferences = entries[currentID]?.nosync_parentReferences else {
                continue
            }

            for (parentID, keys) in parentReferences {
                for key in keys {
                    stack.append((objectID: parentID, path: [key] + currentPath, visited: newVisited))
                }
            }
        }

        // RTLO4f3: each simple path appears exactly once; order is unspecified
        return paths
    }

    /// Fans one object update out to path subscriptions. For every full path to the updated object (RTO24b1),
    /// dispatches one path event whose candidates are the object's own path (most-preferred,
    /// RTO24b2a1) followed by one deeper candidate per changed map key (RTO24b2a2). An orphaned
    /// object (unreachable from root) produces no events (RTO24b1).
    ///
    /// Hosted on the pool (like the `getFullPaths` DFS it drives) so both the operation
    /// apply path and the sync deferred-update path can share it.
    ///
    /// - Important: Must be called with **no live object's queue-mutex held** (the `getFullPaths`
    ///   DFS re-reads each node's `parentReferences`; holding the starting object's mutex would
    ///   trip Swift's exclusive-access checker). Callers invoke it after the
    ///   object-level apply/emit has returned.
    ///
    /// Spec: RTO24b (RTO24b1, RTO24b2, RTO24b2a1, RTO24b2a2).
    ///
    /// PAOM3: the public ``ObjectMessage`` handed to each path event is derived here — the path
    /// delivery boundary (RTPO19e2/RTO24b2b2) — from the internal source message, so the
    /// channel-agnostic register never needs the channel name. A sync-originated dispatch has no
    /// source message (RTO4b2a), passing `objectMessage`/`channelName` as `nil` and delivering a
    /// `nil` public message.
    internal func nosync_notifyPathSubscriptions(
        objectID: String,
        changedMapKeys: [String],
        objectMessage: ProtocolTypes.InboundObjectMessage?,
        channelName: String?,
        register: PathObjectSubscriptionRegister,
    ) {
        // PAOM3: convert the internal source message to the public message at this delivery boundary.
        let message: ObjectMessage? = if let objectMessage, let channelName {
            objectMessage.toPublicObjectMessage(channelName: channelName)
        } else {
            nil
        }

        let pathsToThis = nosync_getFullPaths(forObjectID: objectID) // RTO24b1
        if pathsToThis.isEmpty {
            return // orphaned object (not reachable from root) — no path events (RTO24b1)
        }
        for pathToThis in pathsToThis { // RTO24b2
            var candidates = [pathToThis] // RTO24b2a1 — most preferred first
            for key in changedMapKeys {
                candidates.append(pathToThis + [key]) // RTO24b2a2
            }
            register.nosync_notifyPathEvent(candidatePaths: candidates, message: message)
        }
    }

    /// Creates a new object from a sync entry and adds it to the pool, per RTO5c1b.
    ///
    /// - Precondition: `objectMessage.object` (OM2g) must be non-nil.
    /// - Precondition: the object's `objectId` must not be the root object ID, in order to preserve the RTO3b invariant that the root is always a map.
    /// - Precondition: the object must have either `.counter` or `.map` populated.
    private mutating func nosync_createObjectFromSync(
        objectMessage: ProtocolTypes.InboundObjectMessage,
        logger: Logger,
        internalQueue: DispatchQueue,
        userCallbackQueue: DispatchQueue,
        clock: SimpleClock,
    ) {
        guard let state = objectMessage.object else {
            preconditionFailure("SyncObjectsPool yielded a message with nil object")
        }
        precondition(state.objectId != ObjectsPool.rootKey)

        logger.log("Creating new object with ID: \(state.objectId)", level: .debug)

        // RTO5c1b1: Create a new LiveObject using the data from ObjectState and add it to the internal ObjectsPool:
        let newEntry: Entry

        if state.counter != nil {
            // RTO5c1b1a: If ObjectState.counter is present, create a zero-value LiveCounter,
            // set its private objectId equal to ObjectState.objectId and override its internal data per RTLC6
            let counter = InternalDefaultLiveCounter.createZeroValued(
                objectID: state.objectId,
                logger: logger,
                internalQueue: internalQueue,
                userCallbackQueue: userCallbackQueue,
                clock: clock,
            )
            _ = counter.nosync_replaceData(
                using: state,
                objectMessageSerialTimestamp: objectMessage.serialTimestamp,
            )
            newEntry = .counter(counter)
        } else if let objectsMap = state.map {
            // RTO5c1b1b: If ObjectState.map is present, create a zero-value LiveMap,
            // set its private objectId equal to ObjectState.objectId, set its private semantics
            // equal to ObjectState.map.semantics and override its internal data per RTLM6
            let map = InternalDefaultLiveMap.createZeroValued(
                objectID: state.objectId,
                semantics: objectsMap.semantics,
                logger: logger,
                internalQueue: internalQueue,
                userCallbackQueue: userCallbackQueue,
                clock: clock,
            )
            _ = map.nosync_replaceData(
                using: state,
                objectMessageSerialTimestamp: objectMessage.serialTimestamp,
                objectsPool: &self,
            )
            newEntry = .map(map)
        } else {
            preconditionFailure("state for objectId \(state.objectId) has neither counter nor map")
        }

        entries[state.objectId] = newEntry
    }

    /// Removes all entries except the root, and clears the root's data. This is to be used when an `ATTACHED` ProtocolMessage indicates that the only object in a channel is an empty root map, per RTO4b.
    ///
    /// - Returns: The root keys reported as `removed` by the emitted RTO4b2a update, so the caller
    ///   can fan the reset out to path subscriptions (RTLO4b4c3b) after the root's mutex is released.
    @discardableResult
    internal mutating func nosync_reset() -> [String] {
        let root = root

        // RTO4b1
        entries = [Self.rootKey: .map(root)]

        // RTO4b2
        // TODO: this one is unclear (are we meant to replace the root or just clear its data?) https://github.com/ably/specification/pull/333/files#r2183493458. I believe that the answer is that we should just clear its data but the spec point needs to be clearer, see https://github.com/ably/specification/pull/346/files#r2201434895.
        return root.nosync_resetData()
    }

    /// RTO27a1: Clears the internal data of every object in the pool, resetting each to that of a
    /// new empty object of its type (an empty map per RTLM4c, or a counter with `data` `0` per
    /// RTLC4b) **without emitting any `LiveObjectUpdate` events**. The objects themselves remain in
    /// the pool; only their data is cleared.
    ///
    /// Each map additionally drops the parent references it holds on its referenced children
    /// (RTLO4e9), so that once every object's data has been cleared the parent-reference graph is
    /// left empty and consistent. Used by the RTO27a DETACHED/FAILED channel-state clear.
    ///
    /// Non-`mutating`: this reassigns no pool entry, only mutating the (reference-type) objects the
    /// entries hold, so it can pass `self` down to each map's clear without an exclusivity conflict.
    internal func nosync_clearObjectsData() {
        for entry in entries.values {
            switch entry {
            case let .map(map):
                map.nosync_resetDataToZeroValued(objectsPool: self)
            case let .counter(counter):
                counter.nosync_resetDataToZeroValued()
            }
        }
    }

    /// Performs garbage collection of tombstoned objects and map entries, per RTO10c.
    internal mutating func nosync_performGarbageCollection(
        gracePeriod: TimeInterval,
        clock: SimpleClock,
        logger: Logger,
        eventsContinuation: AsyncStream<Void>.Continuation,
    ) {
        logger.log("Performing garbage collection, grace period \(gracePeriod)s", level: .debug)

        let now = clock.now

        entries = entries.filter { key, entry in
            if case let .map(map) = entry {
                // RTO10c1a
                map.nosync_releaseTombstonedEntries(gracePeriod: gracePeriod, clock: clock)
            }

            // RTO10c1b
            let shouldRelease = {
                // RTO10c1b1: the object with ID `root` must never be removed from the ObjectsPool
                // (RTO3b). It can never become tombstoned per RTLO4e10, so this exclusion is an
                // additional safeguard for the RTO3b invariant.
                guard key != Self.rootKey else {
                    return false
                }

                guard let tombstonedAt = entry.nosync_tombstonedAt else {
                    return false
                }

                return now.timeIntervalSince(tombstonedAt) >= gracePeriod
            }()

            if shouldRelease {
                logger.log("Releasing tombstoned entry \(entry) for key \(key)", level: .debug)
            }
            return !shouldRelease
        }

        eventsContinuation.yield()
    }
}
