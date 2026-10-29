@testable import AblyLiveObjects
import Foundation

extension InternalDefaultLiveMap {
    var testsOnly_data: [String: InternalObjectsMapEntry] {
        mutableStateMutex.withSync { mutableState in
            mutableState.data
        }
    }

    var testsOnly_semantics: WireEnum<ProtocolTypes.ObjectsMapSemantics>? {
        mutableStateMutex.withSync { mutableState in
            mutableState.semantics
        }
    }

    var testsOnly_siteTimeserials: [String: String] {
        mutableStateMutex.withSync { mutableState in
            mutableState.liveObjectMutableState.siteTimeserials
        }
    }

    var testsOnly_createOperationIsMerged: Bool {
        mutableStateMutex.withSync { mutableState in
            mutableState.liveObjectMutableState.createOperationIsMerged
        }
    }

    var testsOnly_clearTimeserial: String? {
        mutableStateMutex.withSync { mutableState in
            mutableState.clearTimeserial
        }
    }

    // MARK: - Test-only setters

    /// Test-only setter for `siteTimeserials`, executing on the internal queue.
    func testsOnly_setSiteTimeserials(_ siteTimeserials: [String: String]) {
        mutableStateMutex.withSync { mutableState in
            mutableState.liveObjectMutableState.siteTimeserials = siteTimeserials
        }
    }

    /// Test-only setter for `tombstonedAt`, executing on the internal queue.
    func testsOnly_setTombstonedAt(_ tombstonedAt: Date?) {
        mutableStateMutex.withSync { mutableState in
            mutableState.liveObjectMutableState.tombstonedAt = tombstonedAt
        }
    }

    /// Test-only setter for `createOperationIsMerged`, executing on the internal queue.
    func testsOnly_setCreateOperationIsMerged(_ createOperationIsMerged: Bool) {
        mutableStateMutex.withSync { mutableState in
            mutableState.liveObjectMutableState.createOperationIsMerged = createOperationIsMerged
        }
    }

    /// Test-only setter for `clearTimeserial`, executing on the internal queue.
    func testsOnly_setClearTimeserial(_ clearTimeserial: String?) {
        mutableStateMutex.withSync { mutableState in
            mutableState.clearTimeserial = clearTimeserial
        }
    }

    var testsOnly_parentReferences: [String: Set<String>] {
        mutableStateMutex.withSync { mutableState in
            mutableState.liveObjectMutableState.parentReferences
        }
    }

    /// Test-only setter for `parentReferences`, executing on the internal queue.
    func testsOnly_setParentReferences(_ parentReferences: [String: Set<String>]) {
        mutableStateMutex.withSync { mutableState in
            mutableState.liveObjectMutableState.parentReferences = parentReferences
        }
    }

    /// Test-only accessor: hops onto the internal queue and delegates to
    /// `ObjectsPool.nosync_getFullPaths(forObjectID:)`.
    func testsOnly_getFullPaths(objectsPool: ObjectsPool) -> [[String]] {
        mutableStateMutex.dispatchQueue.ably_syncNoDeadlock {
            objectsPool.nosync_getFullPaths(forObjectID: objectID)
        }
    }

    // MARK: - Data access

    /// Test-only accessor for objectID that handles locking internally.
    var testsOnly_objectID: String {
        mutableStateMutex.withSync { mutableState in
            mutableState.liveObjectMutableState.objectID
        }
    }

    // MARK: - Data manipulation

    /// Test-only method to apply a MAP_CREATE operation, per RTLM16.
    func testsOnly_applyMapCreateOperation(_ operation: ProtocolTypes.ObjectOperation, objectsPool: inout ObjectsPool) -> LiveObjectUpdate<DefaultLiveMapUpdate> {
        mutableStateMutex.withSync { mutableState in
            mutableState.applyMapCreateOperation(
                operation,
                objectsPool: &objectsPool,
                logger: logger,
                internalQueue: mutableStateMutex.dispatchQueue,
                userCallbackQueue: userCallbackQueue,
                clock: clock,
            )
        }
    }

    /// Applies a `MAP_SET` operation to a key, per RTLM7.
    ///
    /// This is currently exposed just so that the tests can test RTLM7 without having to go through a convoluted replaceData(…) call, but I _think_ that it's going to be used in further contexts when we introduce the handling of incoming object operations in a future spec PR.
    func testsOnly_applyMapSetOperation(
        key: String,
        operationTimeserial: String?,
        operationData: ProtocolTypes.ObjectData,
        objectsPool: inout ObjectsPool,
    ) -> LiveObjectUpdate<DefaultLiveMapUpdate> {
        mutableStateMutex.withSync { mutableState in
            mutableState.applyMapSetOperation(
                key: key,
                operationTimeserial: operationTimeserial,
                operationData: operationData,
                objectsPool: &objectsPool,
                logger: logger,
                internalQueue: mutableStateMutex.dispatchQueue,
                userCallbackQueue: userCallbackQueue,
                clock: clock,
            )
        }
    }

    /// Applies a `MAP_REMOVE` operation to a key, per RTLM8.
    ///
    /// This is currently exposed just so that the tests can test RTLM8 without having to go through a convoluted replaceData(…) call, but I _think_ that it's going to be used in further contexts when we introduce the handling of incoming object operations in a future spec PR.
    func testsOnly_applyMapRemoveOperation(key: String, operationTimeserial: String?, operationSerialTimestamp: Date?, objectsPool: ObjectsPool) -> LiveObjectUpdate<DefaultLiveMapUpdate> {
        mutableStateMutex.withSync { mutableState in
            mutableState.applyMapRemoveOperation(
                key: key,
                operationTimeserial: operationTimeserial,
                operationSerialTimestamp: operationSerialTimestamp,
                objectsPool: objectsPool,
                logger: logger,
                clock: clock,
            )
        }
    }

    /// Test-only method to apply a MAP_CLEAR operation, per RTLM24.
    func testsOnly_applyMapClearOperation(serial: String?, objectsPool: ObjectsPool) -> LiveObjectUpdate<DefaultLiveMapUpdate> {
        mutableStateMutex.withSync { mutableState in
            mutableState.applyMapClearOperation(
                serial: serial,
                objectsPool: objectsPool,
            )
        }
    }

    // MARK: - LiveObject

    /// Test-only accessor for isTombstone that handles locking internally.
    var testsOnly_isTombstone: Bool {
        mutableStateMutex.withSync { mutableState in
            mutableState.liveObjectMutableState.isTombstone
        }
    }

    /// Test-only accessor for tombstonedAt that handles locking internally.
    var testsOnly_tombstonedAt: Date? {
        mutableStateMutex.withSync { mutableState in
            mutableState.liveObjectMutableState.tombstonedAt
        }
    }

    /// Test-only wrapper over the RTLM14 `nosync_isEntryTombstoned` helper.
    ///
    /// This is a pure function of its arguments, so it does not need to execute on the internal queue.
    func testsOnly_isEntryTombstoned(_ entry: InternalObjectsMapEntry, objectsPool: ObjectsPool) -> Bool {
        MutableState.nosync_isEntryTombstoned(entry, objectsPool: objectsPool)
    }

    // MARK: - Test-only initializers

    convenience init(
        testsOnly_data data: [String: InternalObjectsMapEntry],
        objectID: String,
        testsOnly_semantics semantics: WireEnum<ProtocolTypes.ObjectsMapSemantics>? = nil,
        logger: Logger,
        internalQueue: DispatchQueue,
        userCallbackQueue: DispatchQueue,
        clock: SimpleClock,
    ) {
        self.init(
            data: data,
            objectID: objectID,
            semantics: semantics,
            logger: logger,
            internalQueue: internalQueue,
            userCallbackQueue: userCallbackQueue,
            clock: clock,
        )
    }
}
