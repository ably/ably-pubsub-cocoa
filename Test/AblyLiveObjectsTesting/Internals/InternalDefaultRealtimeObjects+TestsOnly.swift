import Ably
@testable import AblyLiveObjects

extension InternalDefaultRealtimeObjects {
    var testsOnly_objectsPool: ObjectsPool {
        mutableStateMutex.withSync { mutableState in
            mutableState.objectsPool
        }
    }

    /// Test-only setter that inserts or replaces an entry in the *owned* `ObjectsPool` held
    /// inside `MutableState`, executing on the internal queue.
    ///
    /// Note that `testsOnly_objectsPool` returns a struct *copy*, so mutating that copy would not
    /// affect this object's state; this seam goes through the mutex to the owned instance.
    func testsOnly_setPoolEntry(_ entry: ObjectsPool.Entry, forObjectID objectID: String) {
        mutableStateMutex.withSync { mutableState in
            mutableState.objectsPool.testsOnly_setEntry(entry, forObjectID: objectID)
        }
    }

    /// Test-only read seam over the RTO17 sync state, executing on the internal queue.
    var testsOnly_syncState: ObjectsSyncState {
        mutableStateMutex.withSync { mutableState in
            mutableState.state.toObjectsSyncState
        }
    }

    /// Test-only seam that applies the given inbound `OBJECT` object messages, executing on the
    /// internal queue by forwarding to `MutableState.nosync_applyObjectProtocolMessageObjectMessage`.
    func testsOnly_applyObjectMessages(_ objectMessages: [ProtocolTypes.InboundObjectMessage], source: ObjectsOperationSource) {
        mutableStateMutex.withSync { mutableState in
            for objectMessage in objectMessages {
                mutableState.nosync_applyObjectProtocolMessageObjectMessage(
                    objectMessage,
                    source: source,
                    logger: logger,
                    internalQueue: mutableStateMutex.dispatchQueue,
                    userCallbackQueue: userCallbackQueue,
                    clock: clock,
                    pathObjectSubscriptionRegister: pathObjectSubscriptionRegister,
                )
            }
        }
    }

    /// If this returns false, it means that there is currently no stored sync sequence ID, SyncObjectsPool, or BufferedObjectOperations.
    var testsOnly_hasSyncSequence: Bool {
        mutableStateMutex.withSync { mutableState in
            if case let .syncing(syncingData) = mutableState.state, syncingData.syncSequence != nil {
                true
            } else {
                false
            }
        }
    }

    /// Returns the number of buffered object operations if in the SYNCING state, or nil otherwise.
    var testsOnly_bufferedObjectOperationsCount: Int? {
        mutableStateMutex.withSync { mutableState in
            if case let .syncing(syncingData) = mutableState.state {
                syncingData.bufferedObjectOperations.count
            } else {
                nil
            }
        }
    }

    var testsOnly_onChannelAttachedHasObjects: Bool? {
        mutableStateMutex.withSync { mutableState in
            mutableState.onChannelAttachedHasObjects
        }
    }

    /// Creates a zero-value LiveObject in the object pool for this object ID.
    ///
    /// Intended as a way for tests to populate the object pool.
    func testsOnly_createZeroValueLiveObject(forObjectID objectID: String) -> ObjectsPool.Entry? {
        mutableStateMutex.withSync { mutableState in
            mutableState.objectsPool.createZeroValueObject(
                forObjectID: objectID,
                logger: logger,
                internalQueue: mutableStateMutex.dispatchQueue,
                userCallbackQueue: userCallbackQueue,
                clock: clock,
            )
        }
    }

    /// Test-only seam for sending an OBJECT ProtocolMessage: validates the messages with the
    /// production RTO15d size check (`ensureMessageSizeWithinLimit`) and publishes them via the
    /// production `CoreSDK.nosync_publish` — deliberately *without* the RTO20 apply-on-ACK stage
    /// of `nosync_publishAndApply`, which its callers (the wire-size RTO15d tests and the plugin
    /// round-trip test) must not trigger. A lead-approved exception to the dumb-accessor rule; see README.md.
    func testsOnly_publish(objectMessages: [ProtocolTypes.OutboundObjectMessage], coreSDK: CoreSDK) async throws(ARTErrorInfo) {
        try await withCheckedContinuation { (continuation: CheckedContinuation<Result<Void, ARTErrorInfo>, _>) in
            mutableStateMutex.withSync { _ in
                // RTO15d: reject the publish if the total ObjectMessage size exceeds maxMessageSize.
                // The check reads the connection's negotiated limit (a `nosync_` accessor), so it must
                // run on the internal queue.
                do throws(ARTErrorInfo) {
                    try Self.ensureMessageSizeWithinLimit(objectMessages, coreSDK: coreSDK)
                } catch {
                    continuation.resume(returning: .failure(error))
                    return
                }
                coreSDK.nosync_publish(objectMessages: objectMessages) { result in
                    continuation.resume(returning: result.map { _ in })
                }
            }
        }.get()
    }

    var testsOnly_siteCode: String? {
        mutableStateMutex.withSync { mutableState in
            mutableState.siteCode
        }
    }

    var testsOnly_appliedOnAckSerials: Set<String> {
        mutableStateMutex.withSync { mutableState in
            mutableState.appliedOnAckSerials
        }
    }
}
