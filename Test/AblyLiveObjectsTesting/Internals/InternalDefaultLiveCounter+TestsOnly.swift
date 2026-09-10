@testable import AblyLiveObjects
import Foundation

extension InternalDefaultLiveCounter {
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

    /// Test-only setter for the counter's `data` (the count), executing on the internal queue.
    func testsOnly_setData(_ data: Double) {
        mutableStateMutex.withSync { mutableState in
            mutableState.data = data
        }
    }

    var testsOnly_data: Double {
        mutableStateMutex.withSync { mutableState in
            mutableState.data
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

    /// Test-only method to apply a COUNTER_CREATE operation, per RTLC8.
    func testsOnly_applyCounterCreateOperation(_ operation: ProtocolTypes.ObjectOperation) -> LiveObjectUpdate<DefaultLiveCounterUpdate> {
        mutableStateMutex.withSync { mutableState in
            mutableState.applyCounterCreateOperation(operation, logger: logger)
        }
    }

    /// Test-only method to apply a COUNTER_INC operation, per RTLC9.
    func testsOnly_applyCounterIncOperation(_ operation: WireCounterInc?) -> LiveObjectUpdate<DefaultLiveCounterUpdate> {
        mutableStateMutex.withSync { mutableState in
            mutableState.applyCounterIncOperation(operation)
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

    // MARK: - Test-only initializers

    convenience init(
        testsOnly_data data: Double,
        objectID: String,
        logger: Logger,
        internalQueue: DispatchQueue,
        userCallbackQueue: DispatchQueue,
        clock: SimpleClock
    ) {
        self.init(
            data: data,
            objectID: objectID,
            logger: logger,
            internalQueue: internalQueue,
            userCallbackQueue: userCallbackQueue,
            clock: clock,
        )
    }
}
