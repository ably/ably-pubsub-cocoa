internal import _AblyPluginSupportPrivate
import Ably

/// Protocol for accessing objects from the ObjectsPool. This is used by a LiveMap when it needs to return an object given an object ID.
internal protocol LiveMapObjectsPoolDelegate: AnyObject, Sendable {
    /// A snapshot of the objects pool.
    var nosync_objectsPool: ObjectsPool { get }
}

/// This provides the implementation behind ``PublicDefaultLiveMap``, via internal versions of the ``LiveMap`` API.
internal final class InternalDefaultLiveMap: Sendable {
    internal let mutableStateMutex: DispatchQueueMutex<MutableState> // internal for AblyLiveObjectsTesting

    internal let logger: Logger // internal for AblyLiveObjectsTesting
    internal let userCallbackQueue: DispatchQueue // internal for AblyLiveObjectsTesting
    internal let clock: SimpleClock // internal for AblyLiveObjectsTesting

    /// The RTLO3a `objectId`. Set once at construction and never mutated (RTINS3a), so it is stored
    /// directly on the object and read without a queue hop.
    internal let objectID: String // internal for AblyLiveObjectsTesting

    // MARK: - Initialization

    internal init( // internal for AblyLiveObjectsTesting
        data: [String: InternalObjectsMapEntry],
        objectID: String,
        semantics: WireEnum<ProtocolTypes.ObjectsMapSemantics>?,
        logger: Logger,
        internalQueue: DispatchQueue,
        userCallbackQueue: DispatchQueue,
        clock: SimpleClock,
    ) {
        self.objectID = objectID
        mutableStateMutex = .init(
            dispatchQueue: internalQueue,
            initialValue: .init(liveObjectMutableState: .init(objectID: objectID), data: data, semantics: semantics),
        )
        self.logger = logger
        self.userCallbackQueue = userCallbackQueue
        self.clock = clock
    }

    /// Creates a "zero-value LiveMap", per RTLM4.
    ///
    /// - Parameters:
    ///   - objectID: The value to use for the RTLO3a `objectID` property.
    ///   - semantics: The value to use for the "private `semantics` field" of RTO5c1b1b.
    internal static func createZeroValued(
        objectID: String,
        semantics: WireEnum<ProtocolTypes.ObjectsMapSemantics>? = nil,
        logger: Logger,
        internalQueue: DispatchQueue,
        userCallbackQueue: DispatchQueue,
        clock: SimpleClock,
    ) -> Self {
        .init(
            data: [:],
            objectID: objectID,
            semantics: semantics,
            logger: logger,
            internalQueue: internalQueue,
            userCallbackQueue: userCallbackQueue,
            clock: clock,
        )
    }

    // MARK: - Data access

    // MARK: - Internal methods that back LiveMap conformance

    /// Returns the value associated with a given key, following RTLM5d specification.
    internal func get(key: String, coreSDK: CoreSDK, delegate: LiveMapObjectsPoolDelegate) throws(ARTErrorInfo) -> InternalLiveMapValue? {
        try mutableStateMutex.withSync { mutableState throws(ARTErrorInfo) in
            try mutableState.nosync_get(
                key: key,
                coreSDK: coreSDK,
                objectsPool: delegate.nosync_objectsPool,
            )
        }
    }

    internal func size(coreSDK: CoreSDK, delegate: LiveMapObjectsPoolDelegate) throws(ARTErrorInfo) -> Int {
        try mutableStateMutex.withSync { mutableState throws(ARTErrorInfo) in
            try mutableState.nosync_size(
                coreSDK: coreSDK,
                objectsPool: delegate.nosync_objectsPool,
            )
        }
    }

    internal func entries(coreSDK: CoreSDK, delegate: LiveMapObjectsPoolDelegate) throws(ARTErrorInfo) -> [(key: String, value: InternalLiveMapValue)] {
        try mutableStateMutex.withSync { mutableState throws(ARTErrorInfo) in
            try mutableState.nosync_entries(
                coreSDK: coreSDK,
                objectsPool: delegate.nosync_objectsPool,
            )
        }
    }

    internal func keys(coreSDK: CoreSDK, delegate: LiveMapObjectsPoolDelegate) throws(ARTErrorInfo) -> [String] {
        // RTLM12b: Identical to LiveMap#entries, except that it returns only the keys from the internal data map
        try entries(coreSDK: coreSDK, delegate: delegate).map(\.key)
    }

    internal func values(coreSDK: CoreSDK, delegate: LiveMapObjectsPoolDelegate) throws(ARTErrorInfo) -> [InternalLiveMapValue] {
        // RTLM13b: Identical to LiveMap#entries, except that it returns only the values from the internal data map
        try entries(coreSDK: coreSDK, delegate: delegate).map(\.value)
    }

    /// Implements `InternalLiveMap#set` (RTLM20). A `LiveCounter`/`LiveMap` blueprint `value` is
    /// evaluated (RTLM20e7g1) into the ordered `*_CREATE` `ObjectMessages` that create it (and any
    /// nested objects), and the `MAP_SET` is published together with those creates in a single
    /// `publishAndApply` array (RTLM20h1) so the whole graph is committed atomically. A primitive
    /// `value` publishes the `MAP_SET` alone (RTLM20h2). The pooled objects for a blueprint are created
    /// by the ACK-time local apply of the batched creates (RTLM7g1/RTO6), exactly as for remote creates.
    internal func set(key: String, value: LiveMapValue, coreSDK: CoreSDK, realtimeObjects: any InternalRealtimeObjectsProtocol) async throws(ARTErrorInfo) {
        // RTO26: check the write-API channel-state precondition up front, before any evaluation
        // (which may fetch server time) or publish. Fail fast, matching `RealtimeObjects.createMap`.
        try mutableStateMutex.withSync { _ throws(ARTErrorInfo) in
            try coreSDK.nosync_validateChannelStateForWriteAPI(operationDescription: "LiveMap.set")
        }

        // RTLM20e7: resolve the MAP_SET value's ObjectData and any preceding *_CREATE messages.
        let mapSetValue: ProtocolTypes.ObjectData
        let createMessages: [ProtocolTypes.OutboundObjectMessage]
        switch value {
        case let .primitive(primitive):
            // RTLM20e7b–f: a primitive maps 1:1 onto its ObjectData; no creates are needed.
            mapSetValue = InternalLiveMapValue(primitive).nosync_toObjectData
            createMessages = []
        case let .liveCounter(blueprint):
            // RTLM20e7g1: evaluate the LiveCounter into its COUNTER_CREATE.
            let evaluated = try await ObjectCreationHelpers.evaluate(liveCounter: blueprint, coreSDK: coreSDK, internalQueue: mutableStateMutex.dispatchQueue)
            // RTLM20e7g2: reference the created object by its objectId.
            mapSetValue = .init(objectId: evaluated.objectId)
            createMessages = evaluated.messages
        case let .liveMap(blueprint):
            // RTLM20e7g1: evaluate the LiveMap into its (depth-first) MAP_CREATE messages.
            let evaluated = try await ObjectCreationHelpers.evaluate(liveMap: blueprint, coreSDK: coreSDK, internalQueue: mutableStateMutex.dispatchQueue)
            // RTLM20e7g2: reference the created object by the final message's objectId.
            mapSetValue = .init(objectId: evaluated.objectId)
            createMessages = evaluated.messages
        }

        try await withCheckedContinuation { (continuation: CheckedContinuation<Result<Void, ARTErrorInfo>, _>) in
            do throws(ARTErrorInfo) {
                try mutableStateMutex.withSync { mutableState throws(ARTErrorInfo) in
                    // RTLM20e: the MAP_SET ObjectMessage
                    let mapSetMessage = ProtocolTypes.OutboundObjectMessage(
                        operation: .init(
                            // RTLM20e2
                            action: .known(.mapSet),
                            // RTLM20e3
                            objectId: mutableState.liveObjectMutableState.objectID,
                            mapSet: .init(
                                // RTLM20e6
                                key: key,
                                // RTLM20e7
                                value: mapSetValue,
                            ),
                        ),
                    )

                    // RTLM20h: publish the *_CREATE messages (RTLM20h1) — empty for a primitive
                    // (RTLM20h2) — followed by the MAP_SET, as one atomic array.
                    realtimeObjects.nosync_publishAndApply(objectMessages: createMessages + [mapSetMessage], coreSDK: coreSDK) { result in
                        continuation.resume(returning: result)
                    }
                }
            } catch {
                continuation.resume(returning: .failure(error))
            }
        }.get()
    }

    internal func remove(key: String, coreSDK: CoreSDK, realtimeObjects: any InternalRealtimeObjectsProtocol) async throws(ARTErrorInfo) {
        try await withCheckedContinuation { (continuation: CheckedContinuation<Result<Void, ARTErrorInfo>, _>) in
            do throws(ARTErrorInfo) {
                try mutableStateMutex.withSync { mutableState throws(ARTErrorInfo) in
                    // RTO26
                    try coreSDK.nosync_validateChannelStateForWriteAPI(operationDescription: "LiveMap.remove")

                    let objectMessage = ProtocolTypes.OutboundObjectMessage(
                        operation: .init(
                            // RTLM21e2
                            action: .known(.mapRemove),
                            // RTLM21e3
                            objectId: mutableState.liveObjectMutableState.objectID,
                            mapRemove: .init(
                                // RTLM21e5
                                key: key,
                            ),
                        ),
                    )

                    // RTLM21g
                    realtimeObjects.nosync_publishAndApply(objectMessages: [objectMessage], coreSDK: coreSDK) { result in
                        continuation.resume(returning: result)
                    }
                }
            } catch {
                continuation.resume(returning: .failure(error))
            }
        }.get()
    }

    @discardableResult
    internal func subscribe(listener: @escaping LiveObjectUpdateCallback<DefaultLiveMapUpdate>, coreSDK: CoreSDK) throws(ARTErrorInfo) -> any SubscribeResponse {
        try mutableStateMutex.withSync { mutableState throws(ARTErrorInfo) in
            // swiftlint:disable:next trailing_closure
            try mutableState.liveObjectMutableState.nosync_subscribe(listener: listener, coreSDK: coreSDK, updateSelfLater: { [weak self] action in
                guard let self else {
                    return
                }

                mutableStateMutex.withSync { mutableState in
                    action(&mutableState.liveObjectMutableState)
                }
            })
        }
    }

    internal func unsubscribeAll() {
        mutableStateMutex.withSync { mutableState in
            mutableState.liveObjectMutableState.unsubscribeAll()
        }
    }

    @discardableResult
    internal func on(event: LiveObjectLifecycleEvent, callback: @escaping LiveObjectLifecycleEventCallback) -> any OnLiveObjectLifecycleEventResponse {
        mutableStateMutex.withSync { mutableState in
            // swiftlint:disable:next trailing_closure
            mutableState.liveObjectMutableState.on(event: event, callback: callback, updateSelfLater: { [weak self] action in
                guard let self else {
                    return
                }

                mutableStateMutex.withSync { mutableState in
                    action(&mutableState.liveObjectMutableState)
                }
            })
        }
    }

    internal func offAll() {
        mutableStateMutex.withSync { mutableState in
            mutableState.liveObjectMutableState.offAll()
        }
    }

    // MARK: - Emitting update from external sources

    /// Emit an event from this `LiveMap`.
    ///
    /// This is used to instruct this map to emit updates during an `OBJECT_SYNC`.
    internal func nosync_emit(_ update: LiveObjectUpdate<DefaultLiveMapUpdate>) {
        mutableStateMutex.withoutSync { mutableState in
            mutableState.liveObjectMutableState.emit(update, on: userCallbackQueue)
        }
    }

    // MARK: - Data manipulation

    /// Replaces the internal data of this map with the provided ObjectState, per RTLM6.
    ///
    /// - Parameters:
    ///   - objectsPool: The pool into which should be inserted any objects created by a `MAP_SET` operation.
    ///   - objectMessageSerialTimestamp: The `serialTimestamp` of the containing `ObjectMessage`. Used if we need to tombstone this map.
    internal func nosync_replaceData(
        using state: ProtocolTypes.ObjectState,
        objectMessageSerialTimestamp: Date?,
        objectsPool: inout ObjectsPool,
    ) -> LiveObjectUpdate<DefaultLiveMapUpdate> {
        mutableStateMutex.withoutSync { mutableState in
            mutableState.replaceData(
                using: state,
                objectMessageSerialTimestamp: objectMessageSerialTimestamp,
                objectsPool: &objectsPool,
                logger: logger,
                clock: clock,
                internalQueue: mutableStateMutex.dispatchQueue,
                userCallbackQueue: userCallbackQueue,
            )
        }
    }

    /// Merges the initial value from an ObjectOperation into this LiveMap, per RTLM23.
    internal func nosync_mergeInitialValue(from operation: ProtocolTypes.ObjectOperation, objectsPool: inout ObjectsPool) -> LiveObjectUpdate<DefaultLiveMapUpdate> {
        mutableStateMutex.withoutSync { mutableState in
            mutableState.mergeInitialValue(
                from: operation,
                objectsPool: &objectsPool,
                logger: logger,
                internalQueue: mutableStateMutex.dispatchQueue,
                userCallbackQueue: userCallbackQueue,
                clock: clock,
            )
        }
    }

    /// Attempts to apply an operation from an inbound `ObjectMessage`, per RTLM15.
    ///
    /// - Returns: The update that was emitted if the operation was applied (which may be `.noop`), or `nil` if the operation was skipped (RTLM15g).
    @discardableResult
    internal func nosync_apply(
        _ operation: ProtocolTypes.ObjectOperation,
        source: ObjectsOperationSource,
        objectMessage: ProtocolTypes.InboundObjectMessage,
        objectsPool: inout ObjectsPool,
    ) -> LiveObjectUpdate<DefaultLiveMapUpdate>? {
        mutableStateMutex.withoutSync { mutableState in
            mutableState.apply(
                operation,
                source: source,
                objectMessage: objectMessage,
                objectsPool: &objectsPool,
                logger: logger,
                internalQueue: mutableStateMutex.dispatchQueue,
                userCallbackQueue: userCallbackQueue,
                clock: clock,
            )
        }
    }

    /// Performs the RTLO4b4c3c tombstone teardown (deregistering this map's subscriptions) for the
    /// deferred OBJECT_SYNC path (RTO5c), which computes updates during the sync and emits them once
    /// it finishes; the inline apply path instead tears down within `nosync_emitAndTearDown`.
    internal func nosync_deregisterSubscriptionsForTombstone() {
        mutableStateMutex.withoutSync { mutableState in
            mutableState.liveObjectMutableState.unsubscribeAll()
        }
    }

    /// Resets the map's data, per RTO4b2. This is to be used when an `ATTACHED` ProtocolMessage indicates that the only object in a channel is an empty root map.
    /// - Returns: The keys reported as `removed` by the emitted update (see
    ///   `MutableState.resetData`); used by the RTO4b reset path to fan out to path subscriptions.
    @discardableResult
    internal func nosync_resetData() -> [String] {
        mutableStateMutex.withoutSync { mutableState in
            mutableState.resetData(userCallbackQueue: userCallbackQueue)
        }
    }

    /// RTO27a1: Clears this map's data to that of a new empty object of its type (an empty map per
    /// RTLM4c) **without emitting any update event**, and drops the parent references it holds on its referenced children
    /// (RTLO4e9) so the parent-reference graph stays consistent once the data is gone.
    ///
    /// Used by the RTO27a DETACHED/FAILED channel-state clear. Unlike ``nosync_resetData`` (the
    /// RTO4b reset) it emits no event, and the object itself remains in the pool.
    internal func nosync_resetDataToZeroValued(objectsPool: ObjectsPool) {
        mutableStateMutex.withoutSync { mutableState in
            // RTLO4e9: drop the parent references this map holds on its referenced children, so
            // those children no longer record this map as a parent once its data is cleared.
            mutableState.nosync_dropHeldParentReferences(objectsPool: objectsPool)
            // RTLM4: reset the map's data to the zero value (empty map, nil clearTimeserial).
            mutableState.resetDataToZeroValued()
        }
    }

    /// Releases entries that were tombstoned more than `gracePeriod` ago, per RTLM19.
    internal func nosync_releaseTombstonedEntries(gracePeriod: TimeInterval, clock: SimpleClock) {
        mutableStateMutex.withoutSync { mutableState in
            mutableState.releaseTombstonedEntries(gracePeriod: gracePeriod, logger: logger, clock: clock)
        }
    }

    // MARK: - LiveObject

    /// Returns the object's RTLO3d `isTombstone` property.
    internal var nosync_isTombstone: Bool {
        mutableStateMutex.withoutSync { mutableState in
            mutableState.liveObjectMutableState.isTombstone
        }
    }

    /// Returns the object's RTLO3e `tombstonedAt` property.
    internal var nosync_tombstonedAt: Date? {
        mutableStateMutex.withoutSync { mutableState in
            mutableState.liveObjectMutableState.tombstonedAt
        }
    }

    // MARK: - Parent-reference graph (RTLO3f)

    /// The object's RTLO3f `parentReferences`.
    internal var nosync_parentReferences: [String: Set<String>] {
        mutableStateMutex.withoutSync { mutableState in
            mutableState.liveObjectMutableState.parentReferences
        }
    }

    /// Records that the map identified by `parentObjectID` references this object at `key`, per RTLO4g.
    internal func nosync_addParentReference(parentObjectID: String, key: String) {
        mutableStateMutex.withoutSync { mutableState in
            mutableState.nosync_addParentReference(parentObjectID: parentObjectID, key: key)
        }
    }

    /// Removes the recorded reference from the map identified by `parentObjectID` at `key`, per RTLO4h.
    internal func nosync_removeParentReference(parentObjectID: String, key: String) {
        mutableStateMutex.withoutSync { mutableState in
            mutableState.nosync_removeParentReference(parentObjectID: parentObjectID, key: key)
        }
    }

    /// Resets `parentReferences` to an empty map, per RTO5c10a.
    internal func nosync_clearParentReferences() {
        mutableStateMutex.withoutSync { mutableState in
            mutableState.nosync_clearParentReferences()
        }
    }

    /// Computes all key-paths from root to this object, per RTLO4f.
    internal func nosync_getFullPaths(objectsPool: ObjectsPool) -> [[String]] {
        objectsPool.nosync_getFullPaths(forObjectID: objectID)
    }

    /// The raw internal data map. Used by the RTO5c10 rebuild.
    internal var nosync_rawData: [String: InternalObjectsMapEntry] {
        mutableStateMutex.withoutSync { mutableState in
            mutableState.data
        }
    }

    /// Returns whether a map entry should be considered tombstoned, per RTLM14. Used by the
    /// RTO5c10 rebuild; a pure function of its arguments, so it does not need the internal queue.
    internal static func nosync_isEntryTombstoned(_ entry: InternalObjectsMapEntry, objectsPool: ObjectsPool) -> Bool {
        MutableState.nosync_isEntryTombstoned(entry, objectsPool: objectsPool)
    }

    // MARK: - Mutable state and the operations that affect it

    internal struct MutableState: InternalLiveObject { // internal for AblyLiveObjectsTesting
        /// The mutable state common to all LiveObjects.
        internal var liveObjectMutableState: LiveObjectMutableState<DefaultLiveMapUpdate>

        /// The internal data that this map holds, per RTLM3.
        internal var data: [String: InternalObjectsMapEntry]

        /// The "private `semantics` field" of RTO5c1b1b.
        internal var semantics: WireEnum<ProtocolTypes.ObjectsMapSemantics>?

        /// RTLM25
        internal var clearTimeserial: String?

        /// Replaces the internal data of this map with the provided ObjectState, per RTLM6.
        ///
        /// - Parameters:
        ///   - objectsPool: The pool into which should be inserted any objects created by a `MAP_SET` operation.
        ///   - objectMessageSerialTimestamp: The `serialTimestamp` of the containing `ObjectMessage`. Used if we need to tombstone this map.
        internal mutating func replaceData(
            using state: ProtocolTypes.ObjectState,
            objectMessageSerialTimestamp: Date?,
            objectsPool: inout ObjectsPool,
            logger: Logger,
            clock: SimpleClock,
            internalQueue: DispatchQueue,
            userCallbackQueue: DispatchQueue,
        ) -> LiveObjectUpdate<DefaultLiveMapUpdate> {
            // RTLM6a: Replace the private siteTimeserials with the value from ObjectState.siteTimeserials
            liveObjectMutableState.siteTimeserials = state.siteTimeserials

            // RTLM6e, RTLM6e1: No-op if we're already tombstone
            if liveObjectMutableState.isTombstone {
                return .noop
            }

            // RTLM6f: Tombstone if state indicates tombstoned
            if state.tombstone {
                // RTLO4e10: the root object must never be tombstoned — an ObjectState with
                // tombstone set for `root` is a faulty message. Log and return a noop update
                // without performing any of the subsequent RTLO4e steps.
                if liveObjectMutableState.objectID == ObjectsPool.rootKey {
                    logger.log("Ignoring ObjectState tombstone targeting the root object (RTLO4e10)", level: .warn)
                    return .noop
                }

                let dataBeforeTombstoning = data

                // RTLO4e9: drop the parent references this map holds on its referenced children
                nosync_dropHeldParentReferences(objectsPool: objectsPool)

                tombstone(
                    objectMessageSerialTimestamp: objectMessageSerialTimestamp,
                    logger: logger,
                    clock: clock,
                    userCallbackQueue: userCallbackQueue,
                )

                // RTLM6f/RTLM6f2: tombstone via LiveObject.tombstone and return its update.
                // RTLO4e5/RTLM22b: the update is the diff between the pre-tombstone data and the
                // now-cleared data, which considers only NON-tombstoned entries. Entries that were
                // already tombstoned were not visible to subscribers, so they must not be reported
                // as newly `removed`.
                return .update(.init(update: dataBeforeTombstoning.filter { !$0.value.tombstone }.mapValues { _ in .removed }, tombstone: true))
            }

            // RTLM6g: Store the current data value as previousData for use in RTLM6h
            let previousData = data

            // RTLM6i
            clearTimeserial = state.map?.clearTimeserial

            // RTLM6b: Set the private flag createOperationIsMerged to false
            liveObjectMutableState.createOperationIsMerged = false

            // RTLM6c: Set data to ObjectState.map.entries, or to an empty map if it does not exist
            data = state.map?.entries?.mapValues { entry in
                let tombstonedAt: Date?
                if entry.tombstone == true {
                    // RTLO6a
                    if let serialTimestamp = entry.serialTimestamp {
                        tombstonedAt = serialTimestamp
                    } else {
                        // RTLO6b
                        logger.log("serialTimestamp not found in ObjectsMapEntry, using local clock for tombstone timestamp", level: .debug)
                        // RTLO6b1
                        tombstonedAt = clock.now
                    }
                } else {
                    tombstonedAt = nil
                }

                return .init(objectsMapEntry: entry, tombstonedAt: tombstonedAt)
            } ?? [:]

            // RTLM6d: If ObjectState.createOp is present, merge the initial value into the LiveMap as described in RTLM23
            // Discard the LiveMapUpdate object returned by the merge operation
            if let createOp = state.createOp {
                _ = mergeInitialValue(
                    from: createOp,
                    objectsPool: &objectsPool,
                    logger: logger,
                    internalQueue: internalQueue,
                    userCallbackQueue: userCallbackQueue,
                    clock: clock,
                )
            }

            // RTLM6h: Calculate the diff between previousData and the current data per RTLM22
            return ObjectDiffHelpers.calculateMapDiff(previousData: previousData, newData: data)
        }

        /// Merges the initial value from an ObjectOperation into this LiveMap, per RTLM23.
        internal mutating func mergeInitialValue(
            from operation: ProtocolTypes.ObjectOperation,
            objectsPool: inout ObjectsPool,
            logger: Logger,
            internalQueue: DispatchQueue,
            userCallbackQueue: DispatchQueue,
            clock: SimpleClock,
        ) -> LiveObjectUpdate<DefaultLiveMapUpdate> {
            // RTLM23: Resolve mapCreate from either the direct property or the one
            // from which mapCreateWithObjectId was derived (RTLMV4j5)
            let mapCreate = operation.mapCreate ?? operation.mapCreateWithObjectId?.derivedFrom

            // RTLM23a: For each key–ObjectsMapEntry pair in mapCreate.entries
            let perKeyUpdates: [LiveObjectUpdate<DefaultLiveMapUpdate>] = if let entries = mapCreate?.entries {
                entries.map { key, entry in
                    if entry.tombstone == true {
                        // RTLM23a2: If ObjectsMapEntry.tombstone is true, apply the MAP_REMOVE operation
                        // as described in RTLM8, passing in the current key as MapRemove, ObjectsMapEntry.timeserial as the operation's serial, and ObjectsMapEntry.serialTimestamp as the operation's serial timestamp
                        applyMapRemoveOperation(
                            key: key,
                            operationTimeserial: entry.timeserial,
                            operationSerialTimestamp: entry.serialTimestamp,
                            objectsPool: objectsPool,
                            logger: logger,
                            clock: clock,
                        )
                    } else {
                        // RTLM23a1: If ObjectsMapEntry.tombstone is false, apply the MAP_SET operation
                        // as described in RTLM7, passing in ObjectsMapEntry.data and the current key as MapSet, and ObjectsMapEntry.timeserial as the operation's serial
                        applyMapSetOperation(
                            key: key,
                            operationTimeserial: entry.timeserial,
                            operationData: entry.data,
                            objectsPool: &objectsPool,
                            logger: logger,
                            internalQueue: internalQueue,
                            userCallbackQueue: userCallbackQueue,
                            clock: clock,
                        )
                    }
                }
            } else {
                []
            }

            // RTLM23b: Set the private flag createOperationIsMerged to true
            liveObjectMutableState.createOperationIsMerged = true

            // RTLM23c: Merge the updates, skipping no-ops
            // I don't love having to use uniqueKeysWithValues, when I shouldn't have to. I should be able to reason _statically_ that there are no overlapping keys. The problem that we're trying to use LiveMapUpdate throughout instead of something more communicative. But I don't know what's to come in the spec so I don't want to mess with this internal interface.
            let filteredPerKeyUpdates = perKeyUpdates.compactMap { update -> LiveMapUpdate? in
                switch update {
                case .noop:
                    nil
                case let .update(update):
                    update
                }
            }
            let filteredPerKeyUpdateKeyValuePairs = filteredPerKeyUpdates.reduce(into: []) { result, element in
                result.append(contentsOf: Array(element.update))
            }
            let update = Dictionary(uniqueKeysWithValues: filteredPerKeyUpdateKeyValuePairs)
            return .update(DefaultLiveMapUpdate(update: update))
        }

        /// Attempts to apply an operation from an inbound `ObjectMessage`, per RTLM15.
        ///
        /// - Returns: `true` if the operation was applied, `false` if skipped (RTLM15g).
        internal mutating func apply(
            _ operation: ProtocolTypes.ObjectOperation,
            source: ObjectsOperationSource,
            objectMessage: ProtocolTypes.InboundObjectMessage,
            objectsPool: inout ObjectsPool,
            logger: Logger,
            internalQueue: DispatchQueue,
            userCallbackQueue: DispatchQueue,
            clock: SimpleClock,
        ) -> LiveObjectUpdate<DefaultLiveMapUpdate>? {
            // The map's helpers keep taking an extracted serialTimestamp; read it off the source
            // message once here (RTLM15d5/RTLM15d7 tombstone-clock inputs).
            let objectMessageSerialTimestamp = objectMessage.serialTimestamp

            // RTLO4a3: the serial/siteCode guard reads these off the source message (same values).
            guard let applicableOperation = liveObjectMutableState.canApplyOperation(objectMessageSerial: objectMessage.serial, objectMessageSiteCode: objectMessage.siteCode, logger: logger) else {
                // RTLM15b
                logger.log("Operation \(operation) (serial: \(String(describing: objectMessage.serial)), siteCode: \(String(describing: objectMessage.siteCode))) should not be applied; discarding", level: .debug)
                return nil
            }

            // RTLM15c
            if source == .channel {
                liveObjectMutableState.siteTimeserials[applicableOperation.objectMessageSiteCode] = applicableOperation.objectMessageSerial
            }

            // RTLM15e
            // TODO: are we still meant to update siteTimeserials? https://github.com/ably/specification/pull/350/files#r2218718854
            if liveObjectMutableState.isTombstone {
                return nil
            }

            switch operation.action {
            case .known(.mapCreate):
                // RTLM15d1
                let update = applyMapCreateOperation(
                    operation,
                    objectsPool: &objectsPool,
                    logger: logger,
                    internalQueue: internalQueue,
                    userCallbackQueue: userCallbackQueue,
                    clock: clock,
                )
                // RTLM15d1a, RTLM15d1b: emit the enriched update (carrying the source message)
                return nosync_emitAndTearDown(update, sourceObjectMessage: objectMessage, userCallbackQueue: userCallbackQueue)
            case .known(.mapSet):
                guard let mapSet = operation.mapSet else {
                    logger.log("Could not apply MAP_SET since operation.mapSet is missing", level: .warn)
                    return nil
                }
                guard let value = mapSet.value else {
                    logger.log("Could not apply MAP_SET since operation.mapSet.value is missing", level: .warn)
                    return nil
                }

                // RTLM15d6
                let update = applyMapSetOperation(
                    key: mapSet.key,
                    operationTimeserial: applicableOperation.objectMessageSerial,
                    operationData: value,
                    objectsPool: &objectsPool,
                    logger: logger,
                    internalQueue: internalQueue,
                    userCallbackQueue: userCallbackQueue,
                    clock: clock,
                )
                // RTLM15d6a, RTLM15d6b
                return nosync_emitAndTearDown(update, sourceObjectMessage: objectMessage, userCallbackQueue: userCallbackQueue)
            case .known(.mapRemove):
                guard let mapRemove = operation.mapRemove else {
                    return nil
                }

                // RTLM15d7
                let update = applyMapRemoveOperation(
                    key: mapRemove.key,
                    operationTimeserial: applicableOperation.objectMessageSerial,
                    operationSerialTimestamp: objectMessageSerialTimestamp,
                    objectsPool: objectsPool,
                    logger: logger,
                    clock: clock,
                )
                // RTLM15d7a, RTLM15d7b
                return nosync_emitAndTearDown(update, sourceObjectMessage: objectMessage, userCallbackQueue: userCallbackQueue)
            case .known(.objectDelete):
                // RTLO4e10: the root object must never be tombstoned — an OBJECT_DELETE targeting
                // `root` is a faulty message. Log and return a noop update without performing any
                // of the subsequent RTLO4e steps.
                if liveObjectMutableState.objectID == ObjectsPool.rootKey {
                    logger.log("Ignoring OBJECT_DELETE targeting the root object (RTLO4e10)", level: .warn)
                    return .noop
                }

                let dataBeforeApplyingOperation = data

                // RTLO4e9: drop the parent references this map holds on its referenced children
                nosync_dropHeldParentReferences(objectsPool: objectsPool)

                // RTLM15d5
                applyObjectDeleteOperation(
                    objectMessageSerialTimestamp: objectMessageSerialTimestamp,
                    logger: logger,
                    clock: clock,
                    userCallbackQueue: userCallbackQueue,
                )

                // RTLM15d5c, RTLM15d5b: tombstone update drives the RTLO4b4c3c teardown.
                // RTLO4e5/RTLM22b: diff considers only NON-tombstoned entries, so already-tombstoned
                // entries (not visible to subscribers) must not be reported as newly `removed`.
                let update: LiveObjectUpdate<DefaultLiveMapUpdate> = .update(.init(update: dataBeforeApplyingOperation.filter { !$0.value.tombstone }.mapValues { _ in .removed }, tombstone: true))
                return nosync_emitAndTearDown(update, sourceObjectMessage: objectMessage, userCallbackQueue: userCallbackQueue)
            case .known(.mapClear):
                // RTLM15d8
                let update = applyMapClearOperation(
                    serial: applicableOperation.objectMessageSerial,
                    objectsPool: objectsPool,
                )
                // RTLM15d8a, RTLM15d8b. MAP_CLEAR clears the map's data but does not tombstone the
                // object (tombstone stays false), so no teardown.
                return nosync_emitAndTearDown(update, sourceObjectMessage: objectMessage, userCallbackQueue: userCallbackQueue)
            default:
                // RTLM15d4
                logger.log("Operation \(operation) has unsupported action for LiveMap; discarding", level: .warn)
                return nil
            }
        }

        /// Applies a `MAP_SET` operation to a key, per RTLM7.
        internal mutating func applyMapSetOperation(
            key: String,
            operationTimeserial: String?,
            operationData: ProtocolTypes.ObjectData?,
            objectsPool: inout ObjectsPool,
            logger: Logger,
            internalQueue: DispatchQueue,
            userCallbackQueue: DispatchQueue,
            clock: SimpleClock,
        ) -> LiveObjectUpdate<DefaultLiveMapUpdate> {
            // RTLM7h
            if let clearTimeserial, operationTimeserial.map({ $0 <= clearTimeserial }) ?? true {
                return .noop
            }

            // RTLM7a: If an entry exists in the private data for the specified key
            if let existingEntry = data[key] {
                // RTLM7a1: If the operation cannot be applied as per RTLM9, discard the operation
                if !Self.canApplyMapOperation(entryTimeserial: existingEntry.timeserial, operationTimeserial: operationTimeserial) {
                    return .noop
                }
                // RTLM7a3: drop the parent reference held via the entry being overwritten
                if let oldRefId = existingEntry.data?.objectId {
                    // RTLM7a3a, RTLM7a3b (with the self-reference guard)
                    nosync_removeParentReferenceGuardingSelfReference(onObjectWithID: oldRefId, key: key, objectsPool: objectsPool)
                }
                // RTLM7a2: Otherwise, apply the operation
                // RTLM7a2e: Set ObjectsMapEntry.data to the MapSet.value
                // RTLM7a2b: Set ObjectsMapEntry.timeserial to the operation's serial
                // RTLM7a2c: Set ObjectsMapEntry.tombstone to false (same as RTLM7a2d: Set ObjectsMapEntry.tombstonedAt to nil)
                var updatedEntry = existingEntry
                updatedEntry.data = operationData
                updatedEntry.timeserial = operationTimeserial
                updatedEntry.tombstonedAt = nil
                data[key] = updatedEntry
            } else {
                // RTLM7b: If an entry does not exist in the private data for the specified key
                // RTLM7b4: Create a new entry in data for the specified key with the provided ObjectData and the operation's serial
                // RTLM7b2: Set ObjectsMapEntry.tombstone for the new entry to false (same as RTLM7b3: Set tombstonedAt to nil)
                data[key] = InternalObjectsMapEntry(tombstonedAt: nil, timeserial: operationTimeserial, data: operationData)
            }

            // RTLM7g: If MapSet.value.objectId is non-empty
            if let objectId = operationData?.objectId, !objectId.isEmpty {
                // RTLM7g1: Create a zero-value LiveObject in the internal ObjectsPool per RTO6
                _ = objectsPool.createZeroValueObject(
                    forObjectID: objectId,
                    logger: logger,
                    internalQueue: internalQueue,
                    userCallbackQueue: userCallbackQueue,
                    clock: clock,
                )
                // RTLM7g2: record the reverse reference for the newly referenced object
                // (with the self-reference guard)
                nosync_addParentReferenceGuardingSelfReference(onObjectWithID: objectId, key: key, objectsPool: objectsPool)
            }

            // RTLM7f
            return .update(DefaultLiveMapUpdate(update: [key: .updated]))
        }

        /// Applies a `MAP_REMOVE` operation to a key, per RTLM8.
        internal mutating func applyMapRemoveOperation(key: String, operationTimeserial: String?, operationSerialTimestamp: Date?, objectsPool: ObjectsPool, logger: Logger, clock: SimpleClock) -> LiveObjectUpdate<DefaultLiveMapUpdate> {
            // (Note that, where the spec tells us to set ObjectsMapEntry.data to nil, we actually set it to an empty ObjectData, which is equivalent, since it contains no data)

            // RTLM8g
            if let clearTimeserial, operationTimeserial.map({ $0 <= clearTimeserial }) ?? true {
                return .noop
            }

            // Calculate the tombstonedAt for the new or updated entry per RTLO6
            let tombstonedAt: Date?
            if let operationSerialTimestamp {
                // RTLO6a
                tombstonedAt = operationSerialTimestamp
            } else {
                // RTLO6b
                logger.log("serialTimestamp not provided for MAP_REMOVE, using local clock for tombstone timestamp", level: .debug)
                // RTLO6b1
                tombstonedAt = clock.now
            }

            // RTLM8a: If an entry exists in the private data for the specified key
            if let existingEntry = data[key] {
                // RTLM8a1: If the operation cannot be applied as per RTLM9, discard the operation
                if !Self.canApplyMapOperation(entryTimeserial: existingEntry.timeserial, operationTimeserial: operationTimeserial) {
                    return .noop
                }
                // RTLM8a3: drop the parent reference held via the entry being removed
                if let oldRefId = existingEntry.data?.objectId {
                    // RTLM8a3a, RTLM8a3b (with the self-reference guard)
                    nosync_removeParentReferenceGuardingSelfReference(onObjectWithID: oldRefId, key: key, objectsPool: objectsPool)
                }
                // RTLM8a2: Otherwise, apply the operation
                // RTLM8a2a: Set ObjectsMapEntry.data to undefined/null
                // RTLM8a2b: Set ObjectsMapEntry.timeserial to the operation's serial
                // RTLM8a2c: Set ObjectsMapEntry.tombstone to true (equivalent to next point)
                // RTLM8a2d: Set ObjectsMapEntry.tombstonedAt per RTLM8a2d
                var updatedEntry = existingEntry
                updatedEntry.data = nil
                updatedEntry.timeserial = operationTimeserial
                updatedEntry.tombstonedAt = tombstonedAt
                data[key] = updatedEntry
            } else {
                // RTLM8b: If an entry does not exist in the private data for the specified key
                // RTLM8b1: Create a new entry in data for the specified key, with ObjectsMapEntry.data set to undefined/null and the operation's serial
                // RTLM8b2: Set ObjectsMapEntry.tombstone for the new entry to true
                // RTLM8b3: Set ObjectsMapEntry.tombstonedAt per RTLO6
                data[key] = InternalObjectsMapEntry(tombstonedAt: tombstonedAt, timeserial: operationTimeserial, data: nil)
            }

            return .update(DefaultLiveMapUpdate(update: [key: .removed]))
        }

        /// Determines whether a map operation can be applied to a map entry, per RTLM9.
        private static func canApplyMapOperation(entryTimeserial: String?, operationTimeserial: String?) -> Bool {
            // I am going to treat "exists" and "is non-empty" as equivalent here, because the spec mentions "null or empty" in some places and is vague in others.
            func normalize(timeserial: String?) -> String? {
                // swiftlint:disable:next empty_string
                timeserial == "" ? nil : timeserial
            }

            let (
                normalizedEntryTimeserial,
                normalizedOperationTimeserial
            ) = (
                normalize(timeserial: entryTimeserial),
                normalize(timeserial: operationTimeserial),
            )

            return switch (normalizedEntryTimeserial, normalizedOperationTimeserial) {
            case let (.some(normalizedEntryTimeserial), .some(normalizedOperationTimeserial)):
                // RTLM9a: For a LiveMap using LWW (Last-Write-Wins) CRDT semantics, the operation must
                // only be applied if its serial is strictly greater ("after") than the entry's serial
                // when compared lexicographically
                // RTLM9e: If both serials exist, compare them lexicographically and allow operation
                // to be applied only if the operation's serial is greater than the entry's serial
                normalizedOperationTimeserial > normalizedEntryTimeserial
            case (nil, .some):
                // RTLM9d: If only the operation serial exists, it is considered greater than the missing
                // entry serial, so the operation can be applied
                true
            case (.some, nil):
                // RTLM9c: If only the entry serial exists, the missing operation serial is considered lower
                // than the existing entry serial, so the operation must not be applied
                false
            case (nil, nil):
                // RTLM9b: If both the entry serial and the operation serial are null or empty strings,
                // they are treated as the "earliest possible" serials and considered "equal",
                // so the operation must not be applied
                false
            }
        }

        /// Applies a `MAP_CREATE` operation, per RTLM16.
        internal mutating func applyMapCreateOperation(
            _ operation: ProtocolTypes.ObjectOperation,
            objectsPool: inout ObjectsPool,
            logger: Logger,
            internalQueue: DispatchQueue,
            userCallbackQueue: DispatchQueue,
            clock: SimpleClock,
        ) -> LiveObjectUpdate<DefaultLiveMapUpdate> {
            if liveObjectMutableState.createOperationIsMerged {
                // RTLM16b
                logger.log("Not applying MAP_CREATE because a MAP_CREATE has already been applied", level: .warn)
                return .noop
            }

            // TODO: RTLM16c `semantics` comparison; outstanding question in https://github.com/ably/specification/pull/343/files#r2192784482

            // RTLM16d, RTLM16f
            return mergeInitialValue(
                from: operation,
                objectsPool: &objectsPool,
                logger: logger,
                internalQueue: internalQueue,
                userCallbackQueue: userCallbackQueue,
                clock: clock,
            )
        }

        /// Applies a `MAP_CLEAR` operation, per RTLM24.
        internal mutating func applyMapClearOperation(
            serial: String?,
            objectsPool: ObjectsPool,
        ) -> LiveObjectUpdate<DefaultLiveMapUpdate> {
            guard let serial else {
                return .noop
            }

            // RTLM24c: discard only if the existing clearTimeserial is *strictly* (lexicographically)
            // greater than the provided serial. On equality the operation is re-applied — note this
            // differs from RTLM7h/RTLM8g (MAP_SET/MAP_REMOVE), which discard on `>=`. Using `<=` here
            // would wrongly no-op a MAP_CLEAR whose serial equals clearTimeserial.
            if let clearTimeserial, serial < clearTimeserial {
                return .noop
            }

            // RTLM24d
            clearTimeserial = serial

            // RTLM24e, RTLM24e1: entry timeserial is nil, or serial > entry timeserial
            let keysToRemove = data.filter { _, entry in
                guard let entryTimeserial = entry.timeserial else {
                    return true
                }
                return serial > entryTimeserial
            }.keys

            for key in keysToRemove {
                // RTLM24e1c: drop the parent reference held via the cleared entry
                if let refId = data[key]?.data?.objectId {
                    // RTLM24e1c1, RTLM24e1c2 (with the self-reference guard)
                    nosync_removeParentReferenceGuardingSelfReference(onObjectWithID: refId, key: key, objectsPool: objectsPool)
                }
                data.removeValue(forKey: key)
            }

            // RTLM24e1b, RTLM24f
            let removedKeys = Dictionary(uniqueKeysWithValues: keysToRemove.map { ($0, LiveMapUpdateAction.removed) })
            return .update(DefaultLiveMapUpdate(update: removedKeys))
        }

        /// Drops the parent references this map holds on the objects referenced by its entries, per RTLO4e9.
        /// Called before the map's data is cleared during tombstoning (RTLO4e4), so that the referenced
        /// children no longer record this (now-tombstoned) map as a parent.
        ///
        /// `mutating` because a self-referencing entry mutates this map's own `parentReferences`
        /// (via the self-reference guard) rather than re-entering via the pool entry.
        internal mutating func nosync_dropHeldParentReferences(objectsPool: ObjectsPool) {
            for (key, entry) in data {
                guard let refId = entry.data?.objectId else {
                    continue
                }
                // RTLO4e9a, RTLO4e9b (with the self-reference guard)
                nosync_removeParentReferenceGuardingSelfReference(onObjectWithID: refId, key: key, objectsPool: objectsPool)
            }
        }

        /// Resets the map's data and emits a `removed` event for the existing keys, per RTO4b2 and RTO4b2a. This is to be used when an `ATTACHED` ProtocolMessage indicates that the only object in a channel is an empty root map.
        ///
        /// - Returns: The keys reported as `removed` by the emitted update, so the caller can fan the
        ///   reset out to path subscriptions (RTLO4b4c3b) after this map's mutex is released.
        internal mutating func resetData(userCallbackQueue: DispatchQueue) -> [String] {
            // RTO4b2
            let previousData = data
            resetDataToZeroValued()

            // RTO4b2a: the update consists of entries for the keys that were removed. Per RTLM22b,
            // only NON-tombstoned entries are user-visible, so already-tombstoned entries must not
            // be reported as newly `removed`.
            let mapUpdate = DefaultLiveMapUpdate(update: previousData.filter { !$0.value.tombstone }.mapValues { _ in .removed })
            // RTLO4b4c1: skip the instance-subscription emit when nothing was removed, so an
            // already-empty root reset does not fire a spurious instance event. Matches the
            // path-dispatch branch in `nosync_onChannelAttached`, which already skips on an empty diff.
            if !mapUpdate.update.isEmpty {
                liveObjectMutableState.emit(.update(mapUpdate), on: userCallbackQueue)
            }
            return Array(mapUpdate.update.keys)
        }

        /// Needed for ``InternalLiveObject`` conformance.
        internal mutating func resetDataToZeroValued() {
            // RTLM4
            data = [:]
            clearTimeserial = nil
        }

        /// Releases entries that were tombstoned more than `gracePeriod` ago, per RTLM19.
        internal mutating func releaseTombstonedEntries(
            gracePeriod: TimeInterval,
            logger: Logger,
            clock: SimpleClock,
        ) {
            let now = clock.now

            // RTLM19a, RTLM19a1
            data = data.filter { key, entry in
                let shouldRelease = {
                    guard let tombstonedAt = entry.tombstonedAt else {
                        return false
                    }

                    return now.timeIntervalSince(tombstonedAt) >= gracePeriod
                }()

                if shouldRelease {
                    logger.log("Releasing tombstoned entry \(entry) for key \(key)", level: .debug)
                }
                return !shouldRelease
            }
        }

        /// Returns the value associated with a given key, following RTLM5d specification.
        internal func nosync_get(key: String, coreSDK: CoreSDK, objectsPool: ObjectsPool) throws(ARTErrorInfo) -> InternalLiveMapValue? {
            // RTO25: If the channel is in the DETACHED or FAILED state, the library should indicate an error with code 90001
            try coreSDK.nosync_validateChannelStateForAccessAPI(operationDescription: "LiveMap.get")

            // RTLM5e - Return nil if self is tombstone
            if liveObjectMutableState.isTombstone {
                return nil
            }

            // RTLM5d1: If no ObjectsMapEntry exists at the key, return undefined/null
            guard let entry = data[key] else {
                return nil
            }

            // RTLM5d2: If a ObjectsMapEntry exists at the key, convert it using the shared logic
            return nosync_convertEntryToLiveMapValue(entry, objectsPool: objectsPool)
        }

        internal func nosync_size(coreSDK: CoreSDK, objectsPool: ObjectsPool) throws(ARTErrorInfo) -> Int {
            // RTO25: If the channel is in the DETACHED or FAILED state, the library should throw an ErrorInfo error with statusCode 400 and code 90001
            try coreSDK.nosync_validateChannelStateForAccessAPI(operationDescription: "LiveMap.size")

            // RTLM10d: Returns the number of non-tombstoned entries (per RTLM14) in the internal data map
            return data.values.count { entry in
                !nosync_isEntryTombstonedGuardingSelfReference(entry, objectsPool: objectsPool)
            }
        }

        internal func nosync_entries(coreSDK: CoreSDK, objectsPool: ObjectsPool) throws(ARTErrorInfo) -> [(key: String, value: InternalLiveMapValue)] {
            // RTO25: If the channel is in the DETACHED or FAILED state, the library should throw an ErrorInfo error with statusCode 400 and code 90001
            try coreSDK.nosync_validateChannelStateForAccessAPI(operationDescription: "LiveMap.entries")

            // RTLM11d: Returns key-value pairs from the internal data map
            // RTLM11d1: Pairs with tombstoned entries (per RTLM14) are not returned
            var result: [(key: String, value: InternalLiveMapValue)] = []

            for (key, entry) in data where !nosync_isEntryTombstonedGuardingSelfReference(entry, objectsPool: objectsPool) {
                // RTLM11d3: entry values are mapped following the same procedure as get(key:) (RTLM5d2)
                if let value = nosync_convertEntryToLiveMapValue(entry, objectsPool: objectsPool) {
                    result.append((key: key, value: value))
                }
            }

            return result
        }

        // MARK: - Helper Methods

        // Note: `internal` (rather than `private`/`fileprivate`) so that the
        // `testsOnly_isEntryTombstoned` wrapper in AblyLiveObjectsTesting can reach it; it is
        // still not part of any public surface.
        /// Returns whether a map entry should be considered tombstoned, per the check described in RTLM14.
        internal static func nosync_isEntryTombstoned(_ entry: InternalObjectsMapEntry, objectsPool: ObjectsPool) -> Bool { // internal (not fileprivate) for AblyLiveObjectsTesting
            // RTLM14a
            if entry.tombstone {
                return true
            }

            // RTLM14c
            if let objectId = entry.data?.objectId {
                if let poolEntry = objectsPool.entries[objectId], poolEntry.nosync_isTombstone {
                    return true
                }
            }

            // RTLM14b
            return false
        }

        /// Instance-level RTLM14 tombstone check used by the read accessors (`get`/`size`/`entries`),
        /// which run while this map's `mutableStateMutex` is exclusively held.
        ///
        /// It guards the RTLM14c *self-reference* case: if the entry references this very map,
        /// delegating to the static helper would read the pool entry's `nosync_isTombstone`,
        /// re-entering this map's already-held mutex — a Swift exclusive-access **crash** (the same
        /// exclusivity class as the `getFullPaths` finding). In that case we answer the
        /// tombstone question from the state already in hand. This guard exists only to satisfy
        /// Swift's exclusive-access enforcement; the observable behaviour is unchanged.
        internal func nosync_isEntryTombstonedGuardingSelfReference(_ entry: InternalObjectsMapEntry, objectsPool: ObjectsPool) -> Bool {
            // RTLM14a
            if entry.tombstone {
                return true
            }
            // RTLM14c self-reference guard (see doc comment).
            if let objectId = entry.data?.objectId, objectId == liveObjectMutableState.objectID {
                return liveObjectMutableState.isTombstone
            }
            // RTLM14b/RTLM14c for every other reference — safe to consult the pool.
            return Self.nosync_isEntryTombstoned(entry, objectsPool: objectsPool)
        }

        /// Records a parent reference from this map on the object with ID `objectID` (RTLO4g),
        /// guarding the *self-reference* case.
        ///
        /// If `objectID` is this map's own objectID, going through the pool entry
        /// (`objectsPool.entries[objectID]?.nosync_addParentReference`) would re-enter this map's
        /// already-held `mutableStateMutex` — a Swift exclusive-access **crash** (the same
        /// exclusivity class as the `getFullPaths` finding). A self-parent is a legitimate
        /// graph edge (the map referencing itself under a key), so we record it directly on the
        /// state already in hand; `ObjectsPool.nosync_getFullPaths`'s per-branch visited set
        /// (RTLO4f2) suppresses the resulting self-loop. This guard exists only to satisfy Swift's
        /// exclusive-access enforcement; the observable behaviour is unchanged.
        private mutating func nosync_addParentReferenceGuardingSelfReference(onObjectWithID objectID: String, key: String, objectsPool: ObjectsPool) {
            if objectID == liveObjectMutableState.objectID {
                nosync_addParentReference(parentObjectID: objectID, key: key)
            } else {
                objectsPool.entries[objectID]?.nosync_addParentReference(parentObjectID: liveObjectMutableState.objectID, key: key)
            }
        }

        /// Removes the parent reference this map holds on the object with ID `objectID` (RTLO4h),
        /// guarding the *self-reference* case for the same reason as
        /// ``nosync_addParentReferenceGuardingSelfReference(onObjectWithID:key:objectsPool:)``.
        private mutating func nosync_removeParentReferenceGuardingSelfReference(onObjectWithID objectID: String, key: String, objectsPool: ObjectsPool) {
            if objectID == liveObjectMutableState.objectID {
                nosync_removeParentReference(parentObjectID: objectID, key: key)
            } else {
                objectsPool.entries[objectID]?.nosync_removeParentReference(parentObjectID: liveObjectMutableState.objectID, key: key)
            }
        }

        /// Converts an InternalObjectsMapEntry to LiveMapValue using the same logic as get(key:)
        /// This is used by entries to ensure consistent value conversion
        private func nosync_convertEntryToLiveMapValue(_ entry: InternalObjectsMapEntry, objectsPool: ObjectsPool) -> InternalLiveMapValue? {
            // RTLM5d2h: If ObjectsMapEntry.tombstone is true, return undefined/null
            if entry.tombstone == true {
                return nil
            }

            // Handle primitive values in the order specified by RTLM5d2b through RTLM5d2e

            // RTLM5d2b: If ObjectsMapEntry.data.boolean exists, return it
            if let boolean = entry.data?.boolean {
                return .bool(boolean)
            }

            // RTLM5d2c: If ObjectsMapEntry.data.bytes exists, return it
            if let bytes = entry.data?.bytes {
                return .data(bytes)
            }

            // RTLM5d2d: If ObjectsMapEntry.data.number exists, return it
            if let number = entry.data?.number {
                // art_doubleValue: an entry set by another client holds the number as JSON decoded it
                return .number(number.art_doubleValue)
            }

            // RTLM5d2e: If ObjectsMapEntry.data.string exists, return it
            if let string = entry.data?.string {
                return .string(string)
            }

            // TODO: Needs specification (see https://github.com/ably/ably-liveobjects-swift-plugin/issues/46)
            if let json = entry.data?.json {
                switch json {
                case let .array(array):
                    return .jsonArray(array)
                case let .object(object):
                    return .jsonObject(object)
                }
            }

            // RTLM5d2f: If ObjectsMapEntry.data.objectId exists, get the object stored at that objectId from the internal ObjectsPool
            if let objectId = entry.data?.objectId {
                // RTLM5d2f1: If an object with id objectId does not exist, return undefined/null
                guard let poolEntry = objectsPool.entries[objectId] else {
                    return nil
                }

                // RTLM5d2h: If referenced object is tombstoned, return nil.
                // Self-reference guard: if the referenced object is this map itself, reading
                // `poolEntry.nosync_isTombstone` would re-enter our already-held mutex — a Swift
                // exclusive-access crash (same exclusivity class as the `getFullPaths`
                // finding). Answer from the tombstone state already in hand. (Merely *reading* the
                // `objectsPool.entries[objectId]` reference above does not enter the mutex.)
                let referencedIsTombstoned = objectId == liveObjectMutableState.objectID
                    ? liveObjectMutableState.isTombstone
                    : poolEntry.nosync_isTombstone
                if referencedIsTombstoned {
                    return nil
                }

                // RTLM5d2f2: Return referenced object
                switch poolEntry {
                case let .map(map):
                    return .liveMap(map)
                case let .counter(counter):
                    return .liveCounter(counter)
                }
            }

            // RTLM5d2g: Otherwise, return undefined/null
            return nil
        }
    }
}
