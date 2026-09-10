internal import _AblyPluginSupportPrivate
import Ably
import Foundation

/// This provides the implementation behind ``PublicDefaultLiveCounter``, via internal versions of the ``LiveCounter`` API.
internal final class InternalDefaultLiveCounter: Sendable {
    internal let mutableStateMutex: DispatchQueueMutex<MutableState> // internal for AblyLiveObjectsTesting

    internal let logger: Logger // internal for AblyLiveObjectsTesting
    private let userCallbackQueue: DispatchQueue
    private let clock: SimpleClock

    /// The RTLO3a `objectId`. Set once at construction and never mutated (RTINS3a), so it is stored
    /// directly on the object and read without a queue hop.
    internal let objectID: String // internal for AblyLiveObjectsTesting

    // MARK: - Initialization

    internal init( // internal for AblyLiveObjectsTesting
        data: Double,
        objectID: String,
        logger: Logger,
        internalQueue: DispatchQueue,
        userCallbackQueue: DispatchQueue,
        clock: SimpleClock
    ) {
        self.objectID = objectID
        mutableStateMutex = .init(
            dispatchQueue: internalQueue,
            initialValue: .init(liveObjectMutableState: .init(objectID: objectID), data: data),
        )
        self.logger = logger
        self.userCallbackQueue = userCallbackQueue
        self.clock = clock
    }

    /// Creates a "zero-value LiveCounter", per RTLC4.
    ///
    /// - Parameters:
    ///   - objectID: The value for the "private objectId field" of RTO5c1b1a.
    internal static func createZeroValued(
        objectID: String,
        logger: Logger,
        internalQueue: DispatchQueue,
        userCallbackQueue: DispatchQueue,
        clock: SimpleClock,
    ) -> Self {
        .init(
            data: 0,
            objectID: objectID,
            logger: logger,
            internalQueue: internalQueue,
            userCallbackQueue: userCallbackQueue,
            clock: clock,
        )
    }

    // MARK: - Internal methods that back LiveCounter conformance

    internal func value(coreSDK: CoreSDK) throws(ARTErrorInfo) -> Double {
        try mutableStateMutex.withSync { mutableState throws(ARTErrorInfo) in
            try mutableState.nosync_value(coreSDK: coreSDK)
        }
    }

    internal func increment(amount: Double, coreSDK: CoreSDK, realtimeObjects: any InternalRealtimeObjectsProtocol) async throws(ARTErrorInfo) {
        try await withCheckedContinuation { (continuation: CheckedContinuation<Result<Void, ARTErrorInfo>, _>) in
            do throws(ARTErrorInfo) {
                try mutableStateMutex.withSync { mutableState throws(ARTErrorInfo) in
                    // RTLC12e1
                    if !amount.isFinite {
                        throw LiveObjectsError.counterIncrementAmountInvalid(amount: amount).toARTErrorInfo()
                    }

                    // RTO26
                    try coreSDK.nosync_validateChannelStateForWriteAPI(operationDescription: "LiveCounter.increment")

                    let objectMessage = ProtocolTypes.OutboundObjectMessage(
                        operation: .init(
                            // RTLC12e2
                            action: .known(.counterInc),
                            // RTLC12e3
                            objectId: mutableState.liveObjectMutableState.objectID,
                            counterInc: .init(
                                // RTLC12e5
                                number: .init(value: amount),
                            ),
                        ),
                    )

                    // RTLC12g
                    realtimeObjects.nosync_publishAndApply(objectMessages: [objectMessage], coreSDK: coreSDK) { result in
                        continuation.resume(returning: result)
                    }
                }
            } catch {
                continuation.resume(returning: .failure(error))
            }
        }.get()
    }

    internal func decrement(amount: Double, coreSDK: CoreSDK, realtimeObjects: any InternalRealtimeObjectsProtocol) async throws(ARTErrorInfo) {
        // RTLC13b
        try await increment(amount: -amount, coreSDK: coreSDK, realtimeObjects: realtimeObjects)
    }

    @discardableResult
    internal func subscribe(listener: @escaping LiveObjectUpdateCallback<DefaultLiveCounterUpdate>, coreSDK: CoreSDK) throws(ARTErrorInfo) -> any SubscribeResponse {
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

    /// Emit an event from this `LiveCounter`.
    ///
    /// This is used to instruct this counter to emit updates during an `OBJECT_SYNC`.
    internal func nosync_emit(_ update: LiveObjectUpdate<DefaultLiveCounterUpdate>) {
        mutableStateMutex.withoutSync { mutableState in
            mutableState.liveObjectMutableState.emit(update, on: userCallbackQueue)
        }
    }

    // MARK: - Data manipulation

    /// Replaces the internal data of this counter with the provided ObjectState, per RTLC6.
    ///
    /// - Parameters:
    ///   - objectMessageSerialTimestamp: The `serialTimestamp` of the containing `ObjectMessage`. Used if we need to tombstone this counter.
    internal func nosync_replaceData(
        using state: ProtocolTypes.ObjectState,
        objectMessageSerialTimestamp: Date?,
    ) -> LiveObjectUpdate<DefaultLiveCounterUpdate> {
        mutableStateMutex.withoutSync { mutableState in
            mutableState.replaceData(
                using: state,
                objectMessageSerialTimestamp: objectMessageSerialTimestamp,
                logger: logger,
                clock: clock,
                userCallbackQueue: userCallbackQueue,
            )
        }
    }

    /// RTO27a1: Clears this counter's data to that of a new empty object of its type (a counter with
    /// `data` `0` per RTLC4b) **without emitting any update event**. Used by the RTO27a
    /// DETACHED/FAILED channel-state clear; the object itself remains in the pool.
    internal func nosync_resetDataToZeroValued() {
        mutableStateMutex.withoutSync { mutableState in
            // RTLC4: reset the counter's data to zero.
            mutableState.resetDataToZeroValued()
        }
    }

    /// Merges the initial value from an ObjectOperation into this LiveCounter, per RTLC16.
    internal func nosync_mergeInitialValue(from operation: ProtocolTypes.ObjectOperation) -> LiveObjectUpdate<DefaultLiveCounterUpdate> {
        mutableStateMutex.withoutSync { mutableState in
            mutableState.mergeInitialValue(from: operation)
        }
    }

    /// Attempts to apply an operation from an inbound `ObjectMessage`, per RTLC7.
    ///
    /// - Returns: The update that was emitted if the operation was applied (which may be `.noop`), or `nil` if the operation was skipped (RTLC7g).
    @discardableResult
    internal func nosync_apply(
        _ operation: ProtocolTypes.ObjectOperation,
        source: ObjectsOperationSource,
        objectMessage: ProtocolTypes.InboundObjectMessage,
        objectsPool: inout ObjectsPool,
    ) -> LiveObjectUpdate<DefaultLiveCounterUpdate>? {
        mutableStateMutex.withoutSync { mutableState in
            mutableState.apply(
                operation,
                source: source,
                objectMessage: objectMessage,
                objectsPool: &objectsPool,
                logger: logger,
                clock: clock,
                userCallbackQueue: userCallbackQueue,
            )
        }
    }

    /// Performs the RTLO4b4c3c tombstone teardown (deregistering this counter's subscriptions) for
    /// the deferred OBJECT_SYNC path (RTO5c), which computes updates during the sync and emits them
    /// once it finishes; the inline apply path instead tears down within `nosync_emitAndTearDown`.
    internal func nosync_deregisterSubscriptionsForTombstone() {
        mutableStateMutex.withoutSync { mutableState in
            mutableState.liveObjectMutableState.unsubscribeAll()
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

    // MARK: - Mutable state and the operations that affect it

    internal struct MutableState: InternalLiveObject { // internal for AblyLiveObjectsTesting
        /// The mutable state common to all LiveObjects.
        internal var liveObjectMutableState: LiveObjectMutableState<DefaultLiveCounterUpdate>

        /// The internal data that this map holds, per RTLC3.
        internal var data: Double

        /// Replaces the internal data of this counter with the provided ObjectState, per RTLC6.
        ///
        /// - Parameters:
        ///   - objectMessageSerialTimestamp: The `serialTimestamp` of the containing `ObjectMessage`. Used if we need to tombstone this counter.
        internal mutating func replaceData(
            using state: ProtocolTypes.ObjectState,
            objectMessageSerialTimestamp: Date?,
            logger: Logger,
            clock: SimpleClock,
            userCallbackQueue: DispatchQueue,
        ) -> LiveObjectUpdate<DefaultLiveCounterUpdate> {
            // RTLC6a: Replace the private siteTimeserials with the value from ObjectState.siteTimeserials
            liveObjectMutableState.siteTimeserials = state.siteTimeserials

            // RTLC6e, RTLC6e1: No-op if we're already tombstone
            if liveObjectMutableState.isTombstone {
                return .noop
            }

            // RTLC6f: Tombstone if state indicates tombstoned
            if state.tombstone {
                let dataBeforeTombstoning = data

                tombstone(
                    objectMessageSerialTimestamp: objectMessageSerialTimestamp,
                    logger: logger,
                    clock: clock,
                    userCallbackQueue: userCallbackQueue,
                )

                // RTLC6f/RTLC6f2: tombstone via LiveObject.tombstone and return its update.
                // The diff helper is deliberately bypassed here: a zero-valued counter's tombstone must still emit an update (RTLO4b4c3c teardown), whereas calculateCounterDiff would return a noop for the zero delta (the RTLC14c zero-delta exception).
                return .update(.init(amount: -dataBeforeTombstoning, tombstone: true))
            }

            // RTLC6g: Store the current data value as previousData for use in RTLC6h
            let previousData = data

            // RTLC6b: Set the private flag createOperationIsMerged to false
            liveObjectMutableState.createOperationIsMerged = false

            // RTLC6c: Set data to the value of ObjectState.counter.count, or to 0 if it does not exist
            // art_doubleValue: this count came off the wire, where JSON decoding can give us an NSDecimalNumber
            data = state.counter?.count?.art_doubleValue ?? 0

            // RTLC6d: If ObjectState.createOp is present, merge the initial value into the LiveCounter as described in RTLC16
            // Discard the LiveCounterUpdate object returned by the merge operation
            if let createOp = state.createOp {
                _ = mergeInitialValue(from: createOp)
            }

            // RTLC6h: Calculate the diff between previousData and the current data per RTLC14
            return ObjectDiffHelpers.calculateCounterDiff(previousData: previousData, newData: data)
        }

        /// Merges the initial value from an ObjectOperation into this LiveCounter, per RTLC16.
        internal mutating func mergeInitialValue(from operation: ProtocolTypes.ObjectOperation) -> LiveObjectUpdate<DefaultLiveCounterUpdate> {
            let update: LiveObjectUpdate<DefaultLiveCounterUpdate>

            // RTLC16: Resolve counterCreate from either the direct property or the one
            // from which counterCreateWithObjectId was derived (RTLCV4g5)
            let counterCreate = operation.counterCreate ?? operation.counterCreateWithObjectId?.derivedFrom

            // RTLC16a: Add counterCreate.count to data, if it exists
            // art_doubleValue: for a remotely-created counter this count came off the wire (a locally-created
            // one comes from `derivedFrom`, where it is already a Double, and is unaffected)
            if let operationCount = counterCreate?.count?.art_doubleValue {
                data += operationCount
                // RTLC16c
                update = .update(DefaultLiveCounterUpdate(amount: operationCount))
            } else {
                // RTLC16d
                update = .noop
            }

            // RTLC16b: Set the private flag createOperationIsMerged to true
            liveObjectMutableState.createOperationIsMerged = true

            return update
        }

        /// Attempts to apply an operation from an inbound `ObjectMessage`, per RTLC7.
        ///
        /// - Returns: The update that was emitted if the operation was applied (which may be `.noop`), or `nil` if the operation was skipped (RTLC7g).
        internal mutating func apply(
            _ operation: ProtocolTypes.ObjectOperation,
            source: ObjectsOperationSource,
            objectMessage: ProtocolTypes.InboundObjectMessage,
            objectsPool: inout ObjectsPool,
            logger: Logger,
            clock: SimpleClock,
            userCallbackQueue: DispatchQueue,
        ) -> LiveObjectUpdate<DefaultLiveCounterUpdate>? {
            // RTLO4a3: the serial/siteCode guard reads these off the source message (same values).
            guard let applicableOperation = liveObjectMutableState.canApplyOperation(objectMessageSerial: objectMessage.serial, objectMessageSiteCode: objectMessage.siteCode, logger: logger) else {
                // RTLC7b
                logger.log("Operation \(operation) (serial: \(String(describing: objectMessage.serial)), siteCode: \(String(describing: objectMessage.siteCode))) should not be applied; discarding", level: .debug)
                return nil
            }

            // RTLC7c
            if source == .channel {
                liveObjectMutableState.siteTimeserials[applicableOperation.objectMessageSiteCode] = applicableOperation.objectMessageSerial
            }

            // RTLC7e
            // TODO: are we still meant to update siteTimeserials? https://github.com/ably/specification/pull/350/files#r2218718854
            if liveObjectMutableState.isTombstone {
                return nil
            }

            switch operation.action {
            case .known(.counterCreate):
                // RTLC7d1
                let update = applyCounterCreateOperation(
                    operation,
                    logger: logger,
                )
                // RTLC7d1a, RTLC7d1b: emit the enriched update (carrying the source message)
                return nosync_emitAndTearDown(update, sourceObjectMessage: objectMessage, userCallbackQueue: userCallbackQueue)
            case .known(.counterInc):
                // RTLC7d5
                let update = applyCounterIncOperation(operation.counterInc)
                // RTLC7d5a, RTLC7d5b
                return nosync_emitAndTearDown(update, sourceObjectMessage: objectMessage, userCallbackQueue: userCallbackQueue)
            case .known(.objectDelete):
                let dataBeforeApplyingOperation = data

                // RTLC7d4
                applyObjectDeleteOperation(
                    objectMessageSerialTimestamp: objectMessage.serialTimestamp,
                    logger: logger,
                    clock: clock,
                    userCallbackQueue: userCallbackQueue,
                )

                // RTLC7d4c, RTLC7d4b: tombstone update drives the RTLO4b4c3c teardown
                // The diff helper is deliberately bypassed here: a zero-valued counter's tombstone must still emit an update (RTLO4b4c3c teardown), whereas calculateCounterDiff would return a noop for the zero delta (the RTLC14c zero-delta exception).
                let update: LiveObjectUpdate<DefaultLiveCounterUpdate> = .update(.init(amount: -dataBeforeApplyingOperation, tombstone: true))
                return nosync_emitAndTearDown(update, sourceObjectMessage: objectMessage, userCallbackQueue: userCallbackQueue)
            default:
                // RTLC7d3
                logger.log("Operation \(operation) has unsupported action for LiveCounter; discarding", level: .warn)
                return nil
            }
        }

        /// Applies a `COUNTER_CREATE` operation, per RTLC8.
        internal mutating func applyCounterCreateOperation(
            _ operation: ProtocolTypes.ObjectOperation,
            logger: Logger,
        ) -> LiveObjectUpdate<DefaultLiveCounterUpdate> {
            if liveObjectMutableState.createOperationIsMerged {
                // RTLC8b
                logger.log("Not applying COUNTER_CREATE because a COUNTER_CREATE has already been applied", level: .warn)
                return .noop
            }

            // RTLC8c, RTLC8e
            return mergeInitialValue(from: operation)
        }

        /// Applies a `COUNTER_INC` operation, per RTLC9.
        internal mutating func applyCounterIncOperation(_ operation: WireCounterInc?) -> LiveObjectUpdate<DefaultLiveCounterUpdate> {
            guard let operation else {
                // RTLC9h
                return .noop
            }

            // RTLC9f, RTLC9g
            // art_doubleValue: an inbound counterInc number arrives as JSON decoded it
            let amount = operation.number.art_doubleValue
            data += amount
            return .update(DefaultLiveCounterUpdate(amount: amount))
        }

        /// Needed for ``InternalLiveObject`` conformance.
        internal mutating func resetDataToZeroValued() {
            // RTLC4
            data = 0
        }

        internal func nosync_value(coreSDK: CoreSDK) throws(ARTErrorInfo) -> Double {
            // RTO25: If the channel is in the DETACHED or FAILED state, the library should indicate an error with code 90001
            try coreSDK.nosync_validateChannelStateForAccessAPI(operationDescription: "LiveCounter.value")

            // RTLC5c
            return data
        }
    }
}
