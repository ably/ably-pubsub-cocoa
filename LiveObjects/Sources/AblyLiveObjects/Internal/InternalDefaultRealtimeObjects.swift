internal import _AblyPluginSupportPrivate
import Ably

/// Protocol that abstracts `InternalDefaultRealtimeObjects`, for testability.
internal protocol InternalRealtimeObjectsProtocol: LiveMapObjectsPoolDelegate {
    /// Per RTO20.
    ///
    /// The callback may be invoked while exclusive access to internal state is held, so it must not
    /// call other methods on this object that read or mutate its state.
    /// https://github.com/ably/ably-liveobjects-swift-plugin/issues/120 tracks removing this restriction.
    func nosync_publishAndApply(
        objectMessages: [ProtocolTypes.OutboundObjectMessage],
        coreSDK: CoreSDK,
        callback: @escaping @Sendable (Result<Void, ARTErrorInfo>) -> Void,
    )

    /// The channel's path-subscription registry. Used by ``DefaultPathObject`` to register path
    /// subscriptions. A `Sendable` reference type confined to the internal queue (it enforces this with dispatch preconditions), so it is
    /// freely readable off any queue. Spec: RTO24a.
    var pathObjectSubscriptionRegister: PathObjectSubscriptionRegister { get }
}

/// This provides the implementation behind ``PublicDefaultRealtimeObjects``, via internal versions of the ``RealtimeObjects`` API.
internal final class InternalDefaultRealtimeObjects: Sendable, InternalRealtimeObjectsProtocol {
    internal let mutableStateMutex: DispatchQueueMutex<MutableState> // internal for AblyLiveObjectsTesting

    internal let logger: Logger // internal for AblyLiveObjectsTesting
    internal let userCallbackQueue: DispatchQueue // internal for AblyLiveObjectsTesting
    internal let clock: SimpleClock // internal for AblyLiveObjectsTesting

    /// The channel's path-subscription registry (RTO24a). A `Sendable` reference type with its own
    /// internal synchronisation, so it lives here as an immutable class-level property rather than
    /// inside the mutex-guarded `MutableState`; `deinit` can then reach it without the mutex.
    internal let pathObjectSubscriptionRegister: PathObjectSubscriptionRegister

    // These drive the testsOnly_* properties that expose the received ProtocolMessages to the test suite.
    private let receivedObjectProtocolMessages: AsyncStream<[ProtocolTypes.InboundObjectMessage]>
    private let receivedObjectProtocolMessagesContinuation: AsyncStream<[ProtocolTypes.InboundObjectMessage]>.Continuation
    private let receivedObjectSyncProtocolMessages: AsyncStream<[ProtocolTypes.InboundObjectMessage]>
    private let receivedObjectSyncProtocolMessagesContinuation: AsyncStream<[ProtocolTypes.InboundObjectMessage]>.Continuation

    /// The RTO10a interval at which we will perform garbage collection.
    private let garbageCollectionInterval: TimeInterval
    // The task that runs the periodic garbage collection described in RTO10.
    private nonisolated(unsafe) var garbageCollectionTask: Task<Void, Never>!

    /// Parameters used to control the garbage collection of tombstoned objects and map entries, as described in RTO10.
    internal struct GarbageCollectionOptions: Encodable, Hashable {
        /// The RTO10a interval at which we will perform garbage collection.
        ///
        /// The default value comes from the suggestion in RTO10a.
        internal var interval: TimeInterval = 5 * 60

        /// The initial RTO10b grace period for which we will retain tombstoned objects and map entries. This value may later get overridden by the `objectsGCGracePeriod` of a `CONNECTED` `ProtocolMessage` from Realtime.
        ///
        /// This default value comes from RTO10b3; can be overridden for testing.
        internal var gracePeriod: GracePeriod = .dynamic(Self.defaultGracePeriod)

        /// The default value from RTO10b3.
        internal static let defaultGracePeriod: TimeInterval = 24 * 60 * 60

        internal enum GracePeriod: Encodable, Hashable {
            /// The client will always use this grace period, and will not update the grace period from the `objectsGCGracePeriod` of a `CONNECTED` `ProtocolMessage`.
            ///
            /// - Important: This should only be used in tests.
            case fixed(TimeInterval)

            /// The client will use this grace period, which may be subsequently updated by the `objectsGCGracePeriod` of a `CONNECTED` `ProtocolMessage`.
            case dynamic(TimeInterval)

            internal var toTimeInterval: TimeInterval {
                switch self {
                case let .fixed(timeInterval), let .dynamic(timeInterval):
                    timeInterval
                }
            }
        }
    }

    // These drive the testsOnly_waitingForSyncEvents property that informs the test suite when `getRoot()` is waiting for the object sync sequence to complete per RTO23c.
    private let waitingForSyncEvents: AsyncStream<Void>
    private let waitingForSyncEventsContinuation: AsyncStream<Void>.Continuation
    // testsOnly_ residual: production-embedded instrumentation — cannot move to AblyLiveObjectsTesting; see Test/AblyLiveObjectsTesting/README.md
    /// Emits an element whenever `getRoot()` starts waiting for the object sync sequence to complete per RTO23c.
    internal var testsOnly_waitingForSyncEvents: AsyncStream<Void> {
        waitingForSyncEvents
    }

    /// Contains the data gathered during an `OBJECT_SYNC` sequence.
    internal struct SyncSequence { // internal for AblyLiveObjectsTesting (cascade: reachable from the raised MutableState)
        /// The sync sequence ID, per RTO5a1.
        internal var id: String

        /// The `ObjectMessage`s gathered during this sync sequence.
        internal var syncObjectsPool: SyncObjectsPool
    }

    internal init(
        logger: Logger,
        internalQueue: DispatchQueue,
        userCallbackQueue: DispatchQueue,
        clock: SimpleClock,
        channelName: String,
        garbageCollectionOptions: GarbageCollectionOptions = .init()
    ) {
        self.logger = logger
        self.userCallbackQueue = userCallbackQueue
        self.clock = clock
        (receivedObjectProtocolMessages, receivedObjectProtocolMessagesContinuation) = AsyncStream.makeStream()
        (receivedObjectSyncProtocolMessages, receivedObjectSyncProtocolMessagesContinuation) = AsyncStream.makeStream()
        (waitingForSyncEvents, waitingForSyncEventsContinuation) = AsyncStream.makeStream()
        (completedGarbageCollectionEventsWithoutBuffering, completedGarbageCollectionEventsWithoutBufferingContinuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(0))
        pathObjectSubscriptionRegister = .init(
            internalQueue: internalQueue,
            userCallbackQueue: userCallbackQueue,
        )
        mutableStateMutex = .init(
            dispatchQueue: internalQueue,
            initialValue: .init(
                objectsPool: .init(
                    logger: logger,
                    internalQueue: internalQueue,
                    userCallbackQueue: userCallbackQueue,
                    clock: clock,
                ),
                channelName: channelName,
                garbageCollectionGracePeriod: garbageCollectionOptions.gracePeriod,
            ),
        )
        garbageCollectionInterval = garbageCollectionOptions.interval

        garbageCollectionTask = Task { [weak self, garbageCollectionInterval] in
            do {
                while true {
                    logger.log("Will perform garbage collection in \(garbageCollectionInterval)s", level: .debug)
                    try await Task.sleep(nanoseconds: UInt64(garbageCollectionInterval * Double(NSEC_PER_SEC)))

                    guard let self else {
                        return
                    }

                    performGarbageCollection()
                }
            } catch {
                precondition(error is CancellationError)
                logger.log("Garbage collection task terminated due to cancellation", level: .debug)
            }
        }
    }

    deinit {
        // Full teardown: cancel the GC task, fail any in-flight sync waiters and drop all
        // subscriptions. `nosync_dispose` is idempotent, so an earlier explicit `dispose()` call
        // makes this a no-op beyond the (already-idempotent) GC cancellation.
        //
        // deinit must NOT reuse the blocking `dispose()`: ARC may run this deinit *on* the internal
        // queue (e.g. when the owning `ARTRealtimeChannel` is deallocated during client/channel
        // teardown, which happens on that queue), and `dispose()`'s `withSync` asserts `.notOnQueue`
        // (`ably_syncNoDeadlock`) — so a blocking teardown from deinit would trap (SIGTRAP). Instead,
        // use a non-blocking teardown that cancels via structured cancellation and never sync-hops
        // its own queue: cancel the GC task (thread-safe
        // from any thread), then hop the queue-confined cleanup onto the internal queue with `async`,
        // capturing ONLY the mutex and the (`Sendable`) register by value — never `self`, which is
        // being deallocated. This deinit-on-queue hazard is cocoa-specific (absent in a GC'd runtime).
        // The async hop fails any detached-continuation waiters slightly later than an explicit
        // `dispose()` would, but still fails (never drops) them.
        garbageCollectionTask.cancel()
        let mutex = mutableStateMutex
        let register = pathObjectSubscriptionRegister
        mutex.dispatchQueue.async {
            mutex.withoutSync { mutableState in
                Self.nosync_dispose(&mutableState, register: register)
            }
        }
    }

    /// The channel objects engine's internal serial queue. Shared out
    /// so the public proxy can construct path objects (whose accessors hop onto it). Every mutation
    /// of this object's state still goes through `mutableStateMutex`.
    internal var internalQueue: DispatchQueue {
        mutableStateMutex.dispatchQueue
    }

    // MARK: - Dispose lifecycle

    /// Tears down the resources associated with this objects engine:
    ///
    /// - cancels the periodic garbage-collection `Task`;
    /// - fails every in-flight `publishAndApply` / `get()` sync waiter (via structured cancellation),
    ///   so a suspended `get()` awaiting sync is resolved rather than
    ///   orphaned — it surfaces the RTO20e1 error (code 92008);
    /// - drops all path subscriptions;
    /// - drops all status-event (`.syncing`/`.synced`) subscriptions.
    ///
    /// It deliberately does **not** invalidate the sync state or the objects pool: the dispatch scope
    /// stays alive so a later `get()` still works, and the instance stays usable —
    /// a subsequent `get()` returns the root path object once the channel re-syncs. Idempotent.
    ///
    /// `ObjectsPool` itself needs no dispose hook: it is a value type owned inside `MutableState`
    /// whose only long-lived resource — the GC `Task` — is owned here and cancelled above.
    internal func dispose() {
        garbageCollectionTask.cancel()
        // Off-queue callers (the explicit teardown, e.g. `PublicRealtimeObjectTests`) block on the
        // internal queue via `withSync`; `deinit` uses a non-blocking `async` hop instead (see the
        // `deinit` note above). Both run the same queue-confined `nosync_dispose`.
        mutableStateMutex.withSync { mutableState in
            Self.nosync_dispose(&mutableState, register: pathObjectSubscriptionRegister)
        }
    }

    /// Disposes the engine in response to a channel release (`channels.release()`), failing any
    /// in-flight sync waiters with a **release-specific** cause (a 40000 "Channel has been released"
    /// error) rather than the generic `.channelStateFailed` reason used by `deinit`/`dispose()`. Called
    /// on the internal queue by the core SDK's channel-release path (via the plugin's
    /// `nosync_onChannelRelease:` hook → `DefaultInternalPlugin`).
    /// Idempotent.
    ///
    /// Like `dispose()`, this keeps the instance usable (the sync state and pool are untouched), so a
    /// later `get()` after a re-attach still works (the dispatch scope survives dispose).
    internal func nosync_disposeForChannelRelease() {
        garbageCollectionTask.cancel()
        let releaseCause = LiveObjectsError.channelReleased.toARTErrorInfo()
        mutableStateMutex.withoutSync { mutableState in
            Self.nosync_dispose(&mutableState, register: pathObjectSubscriptionRegister, reason: releaseCause)
        }
    }

    /// The queue-confined teardown shared by the blocking `dispose()` (off-queue caller, via
    /// `withSync`), `deinit` (which hops onto the internal queue via `async` + `withoutSync`) and the
    /// channel-release path (`nosync_disposeForChannelRelease`). Operates only on the passed-in
    /// `mutableState` and `register`, so it never touches — or resurrects — `self`, which is essential
    /// when it runs from `deinit`. Idempotent (a prior dispose leaves the waiter set, subscription
    /// register and status emitter already drained).
    ///
    /// - Parameter reason: the cause attached to the RTO20e1 failure delivered to in-flight sync
    ///   waiters. `nil` (the default, used by `deinit`/`dispose()`) fails them with no specific cause;
    ///   the channel-release path passes a release-specific error.
    private static func nosync_dispose(
        _ mutableState: inout MutableState,
        register: PathObjectSubscriptionRegister,
        reason: ARTErrorInfo? = nil,
    ) {
        // Fail any pending publishAndApply / get() sync waiters (RTO20e1 path).
        mutableState.nosync_drainPublishAndApplySyncWaiters(
            outcome: .channelStateFailed(state: .failed, reason: reason),
        )
        // Drop all path subscriptions.
        register.nosync_dispose()
        // Drop all status-event subscriptions.
        mutableState.offAll()
    }

    // MARK: - LiveMapObjectsPoolDelegate

    internal var nosync_objectsPool: ObjectsPool {
        mutableStateMutex.withoutSync { mutableState in
            mutableState.objectsPool
        }
    }

    // MARK: - Internal methods that power RealtimeObjects conformance

    internal func getRoot(coreSDK: CoreSDK) async throws(ARTErrorInfo) -> InternalDefaultLiveMap {
        let state = try mutableStateMutex.withSync { mutableState throws(ARTErrorInfo) in
            // RTO1b: If the channel is in the DETACHED or FAILED state, the library should indicate an error with code 90001
            try coreSDK.nosync_validateChannelStateForAccessAPI(operationDescription: "getRoot")

            return mutableState.state
        }

        if state.toObjectsSyncState != .synced {
            // RTO23c
            waitingForSyncEventsContinuation.yield()
            logger.log("getRoot started waiting for sync sequence to complete", level: .debug)
            await withCheckedContinuation { continuation in
                onInternal(event: .synced) { subscription in
                    subscription.off()
                    continuation.resume()
                }
            }
            logger.log("getRoot completed waiting for sync sequence to complete", level: .debug)
        }

        return mutableStateMutex.withSync { mutableState in
            // RTO23d
            mutableState.objectsPool.root
        }
    }

    /// RTO23c: Suspends until the initial object sync has completed (state `.synced`), for the
    /// path-based `RealtimeObject.get()`.
    ///
    /// The state check and the waiter registration happen inside a **single** `mutableStateMutex`
    /// block, so a `.synced` transition can never slip between them and be lost (the lost-wakeup
    /// invariant). This reuses the existing `publishAndApplySyncWaiters` machinery
    /// (RTO20e/RTO20e1): the waiter is resumed with success when sync completes, and failed with the
    /// RTO23c1 error (code 92008) if the channel enters DETACHED/SUSPENDED/FAILED — or if the engine
    /// is disposed — while waiting.
    ///
    /// Unlike the internal `getRoot()` (the old RTO1 API, which registers its `.synced` listener in a
    /// separate queue hop), this keeps check-and-register atomic.
    internal func ensureSynced() async throws(ARTErrorInfo) {
        try await withCheckedContinuation { (continuation: CheckedContinuation<Result<Void, ARTErrorInfo>, Never>) in
            mutableStateMutex.withSync { mutableState in
                // Atomic with the registration below (same queue block): if already synced, resume now.
                if mutableState.state.toObjectsSyncState == .synced {
                    continuation.resume(returning: .success(()))
                    return
                }
                // RTO23c-style signal that a get() has started waiting (used by the test suite).
                waitingForSyncEventsContinuation.yield()
                logger.log("get() started waiting for sync sequence to complete", level: .debug)
                mutableState.publishAndApplySyncWaiters.append { _, outcome in
                    switch outcome {
                    case .synced:
                        continuation.resume(returning: .success(()))
                    case let .channelStateFailed(state, reason):
                        // RTO23c1 -> code 92008 (sync did not complete): the get()-side counterpart of the publishAndApply RTO20e1 failure below.
                        let error = LiveObjectsError.getFailedChannelStateChanged(
                            channelState: state,
                            reason: reason,
                        )
                        continuation.resume(returning: .failure(error.toARTErrorInfo()))
                    }
                }
            }
        }.get()
    }

    internal func createMap(entries: [String: InternalLiveMapValue], coreSDK: CoreSDK) async throws(ARTErrorInfo) -> InternalDefaultLiveMap {
        try await withCheckedContinuation { (continuation: CheckedContinuation<Result<InternalDefaultLiveMap, ARTErrorInfo>, _>) in
            do throws(ARTErrorInfo) {
                try mutableStateMutex.withSync { _ throws(ARTErrorInfo) in
                    // RTO26
                    try coreSDK.nosync_validateChannelStateForWriteAPI(operationDescription: "RealtimeObjects.createMap")

                    // RTLMV4h
                    coreSDK.nosync_fetchServerTime { [self] result in
                        let timestamp: Date
                        switch result {
                        case let .failure(error):
                            continuation.resume(returning: .failure(error))
                            return
                        case let .success(t):
                            timestamp = t
                        }

                        // RTLMV4
                        let creationOperation = ObjectCreationHelpers.nosync_creationOperationForLiveMap(
                            entries: entries,
                            timestamp: timestamp,
                        )

                        // RTLMV4k/RTO20: publish the MAP_CREATE and apply it locally on ACK
                        nosync_publishAndApply(objectMessages: [creationOperation.objectMessage], coreSDK: coreSDK) { mutableState, result in
                            switch result {
                            case let .failure(error):
                                continuation.resume(returning: .failure(error))
                            case .success:
                                // RTLMV3: return the created LiveMap

                                // RTLMV3
                                guard case let .map(existingMap) = mutableState.objectsPool.entries[creationOperation.objectID] else {
                                    // RTLMV3: Object should have been created by publishAndApply
                                    let error = LiveObjectsError.newlyCreatedObjectNotInPool(objectID: creationOperation.objectID).toARTErrorInfo()
                                    continuation.resume(returning: .failure(error))
                                    return
                                }

                                continuation.resume(returning: .success(existingMap))
                            }
                        }
                    }
                }
            } catch {
                continuation.resume(returning: .failure(error))
            }
        }.get()
    }

    internal func createMap(coreSDK: CoreSDK) async throws(ARTErrorInfo) -> InternalDefaultLiveMap {
        // RTLMV4e2
        try await createMap(entries: [:], coreSDK: coreSDK)
    }

    internal func createCounter(count: Double, coreSDK: CoreSDK) async throws(ARTErrorInfo) -> InternalDefaultLiveCounter {
        try await withCheckedContinuation { (continuation: CheckedContinuation<Result<InternalDefaultLiveCounter, ARTErrorInfo>, _>) in
            do throws(ARTErrorInfo) {
                try mutableStateMutex.withSync { _ throws(ARTErrorInfo) in
                    // RTO26
                    try coreSDK.nosync_validateChannelStateForWriteAPI(operationDescription: "RealtimeObjects.createCounter")

                    // RTLCV4a
                    if !count.isFinite {
                        throw LiveObjectsError.counterInitialValueInvalid(value: count).toARTErrorInfo()
                    }

                    // RTLCV4

                    // RTLCV4e
                    coreSDK.nosync_fetchServerTime { [self] result in
                        let timestamp: Date
                        switch result {
                        case let .failure(error):
                            continuation.resume(returning: .failure(error))
                            return
                        case let .success(t):
                            timestamp = t
                        }

                        let creationOperation = ObjectCreationHelpers.creationOperationForLiveCounter(
                            count: count,
                            timestamp: timestamp,
                        )

                        // RTLCV4/RTO20: publish the COUNTER_CREATE and apply it locally on ACK
                        nosync_publishAndApply(objectMessages: [creationOperation.objectMessage], coreSDK: coreSDK) { mutableState, result in
                            switch result {
                            case let .failure(error):
                                continuation.resume(returning: .failure(error))
                            case .success:
                                // RTLCV3: return the created LiveCounter

                                // RTLCV3
                                guard case let .counter(existingCounter) = mutableState.objectsPool.entries[creationOperation.objectID] else {
                                    // RTLCV3: Object should have been created by publishAndApply
                                    let error = LiveObjectsError.newlyCreatedObjectNotInPool(objectID: creationOperation.objectID).toARTErrorInfo()
                                    continuation.resume(returning: .failure(error))
                                    return
                                }

                                continuation.resume(returning: .success(existingCounter))
                            }
                        }
                    }
                }
            } catch {
                continuation.resume(returning: .failure(error))
            }
        }.get()
    }

    internal func createCounter(coreSDK: CoreSDK) async throws(ARTErrorInfo) -> InternalDefaultLiveCounter {
        // RTLCV4b1
        try await createCounter(count: 0, coreSDK: coreSDK)
    }

    // RTO18
    @discardableResult
    internal func on(event: ObjectsEvent, callback: @escaping ObjectsEventCallback) -> any OnObjectsEventResponse {
        mutableStateMutex.withSync { mutableState in
            // swiftlint:disable:next trailing_closure
            mutableState.on(event: event, callback: callback, updateSelfLater: { [weak self] action in
                guard let self else {
                    return
                }

                mutableStateMutex.withSync { mutableState in
                    action(&mutableState)
                }
            })
        }
    }

    /// Adds a subscriber to the ``internalObjectsEventSubscriptionStorage`` (i.e. unaffected by `offAll()`).
    @discardableResult
    internal func onInternal(event: ObjectsEvent, callback: @escaping ObjectsEventCallback) -> any OnObjectsEventResponse {
        // TODO: Looking at this again later the whole process for adding a subscriber is really verbose and boilerplate-y, and I think the unfortunate result of me trying to be clever at some point; revisit in https://github.com/ably/ably-liveobjects-swift-plugin/issues/102
        mutableStateMutex.withSync { mutableState in
            // swiftlint:disable:next trailing_closure
            mutableState.onInternal(event: event, callback: callback, updateSelfLater: { [weak self] action in
                guard let self else {
                    return
                }

                mutableStateMutex.withSync { mutableState in
                    action(&mutableState)
                }
            })
        }
    }

    internal func offAll() {
        mutableStateMutex.withSync { mutableState in
            mutableState.offAll()
        }
    }

    // MARK: Handling channel events

    internal func nosync_onChannelAttached(hasObjects: Bool) {
        mutableStateMutex.withoutSync { mutableState in
            mutableState.nosync_onChannelAttached(
                hasObjects: hasObjects,
                logger: logger,
                userCallbackQueue: userCallbackQueue,
                pathObjectSubscriptionRegister: pathObjectSubscriptionRegister,
            )
        }
    }

    internal func nosync_onChannelStateChanged(toState state: _AblyPluginSupportPrivate.RealtimeChannelState, reason: ARTErrorInfo?) {
        mutableStateMutex.withoutSync { mutableState in
            mutableState.nosync_onChannelStateChanged(
                toState: state,
                reason: reason,
                logger: logger,
            )
        }
    }

    // testsOnly_ residual: production-embedded instrumentation — cannot move to AblyLiveObjectsTesting; see Test/AblyLiveObjectsTesting/README.md
    internal var testsOnly_receivedObjectProtocolMessages: AsyncStream<[ProtocolTypes.InboundObjectMessage]> {
        receivedObjectProtocolMessages
    }

    /// Implements the `OBJECT` handling of RTO8.
    internal func nosync_handleObjectProtocolMessage(objectMessages: [ProtocolTypes.InboundObjectMessage]) {
        mutableStateMutex.withoutSync { mutableState in
            mutableState.nosync_handleObjectProtocolMessage(
                objectMessages: objectMessages,
                logger: logger,
                internalQueue: mutableStateMutex.dispatchQueue,
                userCallbackQueue: userCallbackQueue,
                clock: clock,
                pathObjectSubscriptionRegister: pathObjectSubscriptionRegister,
                receivedObjectProtocolMessagesContinuation: receivedObjectProtocolMessagesContinuation,
            )
        }
    }

    // testsOnly_ residual: production-embedded instrumentation — cannot move to AblyLiveObjectsTesting; see Test/AblyLiveObjectsTesting/README.md
    internal var testsOnly_receivedObjectSyncProtocolMessages: AsyncStream<[ProtocolTypes.InboundObjectMessage]> {
        receivedObjectSyncProtocolMessages
    }

    /// Implements the `OBJECT_SYNC` handling of RTO5.
    internal func nosync_handleObjectSyncProtocolMessage(objectMessages: [ProtocolTypes.InboundObjectMessage], protocolMessageChannelSerial: String?) {
        mutableStateMutex.withoutSync { mutableState in
            mutableState.nosync_handleObjectSyncProtocolMessage(
                objectMessages: objectMessages,
                protocolMessageChannelSerial: protocolMessageChannelSerial,
                logger: logger,
                internalQueue: mutableStateMutex.dispatchQueue,
                userCallbackQueue: userCallbackQueue,
                clock: clock,
                pathObjectSubscriptionRegister: pathObjectSubscriptionRegister,
                receivedObjectSyncProtocolMessagesContinuation: receivedObjectSyncProtocolMessagesContinuation,
            )
        }
    }

    // MARK: - Sending `OBJECT` ProtocolMessage

    /// The Ably default maximum message size, in bytes, used as a fallback when the connection has not
    /// negotiated one. Matches the core SDK's `ARTDefault.maxMessageSize`.
    private static let defaultMaxMessageSize = 65536

    /// RTO15d: Validates that the total size of `objectMessages` (each calculated per OM3) does not
    /// exceed the connection's `maxMessageSize`. If it does, the publish is rejected with an
    /// `ErrorInfo` of `statusCode` 400 and `code` 40009.
    ///
    /// The effective limit is the connection's negotiated `maxMessageSize`, read from the latest
    /// `CONNECTED` `ProtocolMessage`'s `connectionDetails` via `CoreSDK.nosync_maxMessageSize`; we fall
    /// back to ``defaultMaxMessageSize`` when the core SDK has no connection details yet or the server
    /// did not send a limit.
    ///
    /// Must be called on the internal queue (it reads the `nosync_` connection-details accessor).
    internal static func ensureMessageSizeWithinLimit(_ objectMessages: [ProtocolTypes.OutboundObjectMessage], coreSDK: CoreSDK) throws(ARTErrorInfo) { // internal for AblyLiveObjectsTesting
        let maximumAllowedSize = coreSDK.nosync_maxMessageSize ?? defaultMaxMessageSize
        let totalSize = objectMessages.reduce(0) { $0 + $1.size }
        if totalSize > maximumAllowedSize {
            throw LiveObjectsError.maxMessageSizeExceeded(size: totalSize, maxSize: maximumAllowedSize).toARTErrorInfo()
        }
    }

    /// RTO20: Publishes ObjectMessages and applies them locally upon receiving the ACK from the server.
    ///
    /// Must be called from within `mutableStateMutex.withSync` (i.e. on the internal queue).
    internal func nosync_publishAndApply(
        objectMessages: [ProtocolTypes.OutboundObjectMessage],
        coreSDK: CoreSDK,
        callback: @escaping @Sendable (Result<Void, ARTErrorInfo>) -> Void,
    ) {
        nosync_publishAndApply(objectMessages: objectMessages, coreSDK: coreSDK) { _, result in
            callback(result)
        }
    }

    /// Internal variant of ``nosync_publishAndApply`` whose callback receives `inout MutableState`,
    /// allowing the caller to access mutable state (e.g. to look up a newly-created object) without
    /// re-acquiring the mutex.
    ///
    /// This is a workaround for the fact that behavioural methods currently live on `MutableState`,
    /// meaning callbacks are invoked while the mutex is held. See
    /// https://github.com/ably/ably-liveobjects-swift-plugin/issues/120 for the longer-term fix.
    ///
    /// Must be called from within `mutableStateMutex.withSync` (i.e. on the internal queue).
    private func nosync_publishAndApply(
        objectMessages: [ProtocolTypes.OutboundObjectMessage],
        coreSDK: CoreSDK,
        mutableStateCallback: @escaping @Sendable (inout MutableState, Result<Void, ARTErrorInfo>) -> Void,
    ) {
        // RTO15d: Reject the publish before contacting the core SDK if the total ObjectMessage size
        // exceeds maxMessageSize.
        do throws(ARTErrorInfo) {
            try Self.ensureMessageSizeWithinLimit(objectMessages, coreSDK: coreSDK)
        } catch {
            mutableStateMutex.withoutSync { mutableState in
                mutableStateCallback(&mutableState, .failure(error))
            }
            return
        }

        // RTO20b: Publish via the core SDK. The callback fires asynchronously on the internal queue.
        coreSDK.nosync_publish(objectMessages: objectMessages) { [self] result in
            let publishResult: PublishResult
            switch result {
            case let .failure(error):
                mutableStateMutex.withoutSync { mutableState in
                    mutableStateCallback(&mutableState, .failure(error))
                }
                return
            case let .success(pr):
                publishResult = pr
            }

            logger.log("nosync_publishAndApply: received ACK for \(objectMessages.count) message(s), applying locally", level: .debug)

            mutableStateMutex.withoutSync { mutableState in
                // RTO20c1: Check siteCode
                guard let siteCode = mutableState.siteCode else {
                    logger.log("nosync_publishAndApply: operations will not be applied locally: siteCode not available from connectionDetails", level: .error)
                    mutableStateCallback(&mutableState, .success(()))
                    return
                }

                // RTO20c2: Check serials length
                guard publishResult.serials.count == objectMessages.count else {
                    logger.log("nosync_publishAndApply: operations will not be applied locally: PublishResult.serials has unexpected length (expected \(objectMessages.count), got \(publishResult.serials.count))", level: .error)
                    mutableStateCallback(&mutableState, .success(()))
                    return
                }

                // RTO20d: Create synthetic inbound ObjectMessages
                let syntheticMessages = objectMessages.enumerated().compactMap { index, outboundMessage -> ProtocolTypes.InboundObjectMessage? in
                    // RTO20d1: Skip null serials (conflated)
                    guard let serial = publishResult.serials[index] else {
                        logger.log("nosync_publishAndApply: operation at index \(index) will not be applied locally: serial is null in PublishResult", level: .debug)
                        return nil
                    }

                    // RTO20d2, RTO20d3: Create synthetic inbound message
                    return .createSynthetic(from: outboundMessage, serial: serial, siteCode: siteCode)
                }

                // RTO20d4: empty synthetic list — complete successfully without the RTO20e wait (avoids a spurious RTO20e1/92008 failure if the channel drops meanwhile).
                guard !syntheticMessages.isEmpty else {
                    mutableStateCallback(&mutableState, .success(()))
                    return
                }

                // RTO20e: Build a waiter closure that owns both the apply-on-success
                // and error-construction-on-failure logic. The waiter receives `inout MutableState`
                // so it can apply synthetic messages and pass the reference through to the callback,
                // avoiding re-entrant mutex acquisition.
                let waiter: (inout MutableState, MutableState.PublishAndApplySyncWaiterOutcome) -> Void = { [self] mutableState, outcome in
                    switch outcome {
                    case .synced:
                        // RTO20f: Apply synthetic messages with source: .local
                        for syntheticMessage in syntheticMessages {
                            mutableState.nosync_applyObjectProtocolMessageObjectMessage(
                                syntheticMessage,
                                source: .local,
                                logger: logger,
                                internalQueue: mutableStateMutex.dispatchQueue,
                                userCallbackQueue: userCallbackQueue,
                                clock: clock,
                                pathObjectSubscriptionRegister: pathObjectSubscriptionRegister,
                            )
                        }
                        mutableStateCallback(&mutableState, .success(()))
                    case let .channelStateFailed(state, reason):
                        // RTO20e1
                        let error = LiveObjectsError.publishAndApplyFailedChannelStateChanged(
                            channelState: state,
                            reason: reason,
                        )
                        mutableStateCallback(&mutableState, .failure(error.toARTErrorInfo()))
                    }
                }

                if mutableState.state.toObjectsSyncState != .synced {
                    // RTO20e, RTO20e1: Store as a waiter; will be invoked when sync completes
                    // or when the channel enters detached/suspended/failed.
                    logger.log("nosync_publishAndApply: waiting for sync to complete before applying \(syntheticMessages.count) message(s)", level: .debug)
                    mutableState.publishAndApplySyncWaiters.append(waiter)
                } else {
                    waiter(&mutableState, .synced)
                }
            }
        }
    }

    // MARK: - Garbage collection of deleted objects and map entries

    /// Performs garbage collection of tombstoned objects and map entries, per RTO10c.
    internal func performGarbageCollection() {
        mutableStateMutex.withSync { mutableState in
            mutableState.objectsPool.nosync_performGarbageCollection(
                gracePeriod: mutableState.garbageCollectionGracePeriod.toTimeInterval,
                clock: clock,
                logger: logger,
                eventsContinuation: completedGarbageCollectionEventsWithoutBufferingContinuation,
            )
        }
    }

    // The completed-garbage-collection event stream. Production writes its continuation from
    // `performGarbageCollection` and `testsOnly_finishAllTestHelperStreams` finishes it; the stream
    // value is retained alongside its continuation (the two are produced together by `makeStream`).
    private let completedGarbageCollectionEventsWithoutBuffering: AsyncStream<Void>
    private let completedGarbageCollectionEventsWithoutBufferingContinuation: AsyncStream<Void>.Continuation

    /// Sets the `siteCode` from the latest `connectionDetails`.
    ///
    /// Call this upon receiving a `CONNECTED` `ProtocolMessage`.
    internal func nosync_setSiteCode(_ siteCode: String?) {
        mutableStateMutex.withoutSync { mutableState in
            mutableState.siteCode = siteCode
        }
    }

    /// Sets the garbage collection grace period.
    ///
    /// Call this upon receiving a `CONNECTED` `ProtocolMessage`, per RTO10b2.
    ///
    /// - Note: If the `.fixed` grace period option was chosen on instantiation, this is a no-op.
    internal func nosync_setGarbageCollectionGracePeriod(_ gracePeriod: TimeInterval) {
        mutableStateMutex.withoutSync { mutableState in
            switch mutableState.garbageCollectionGracePeriod {
            case .fixed:
                // no-op
                break
            case .dynamic:
                mutableState.garbageCollectionGracePeriod = .dynamic(gracePeriod)
            }
        }
    }

    // MARK: - Testing

    // testsOnly_ residual: production-embedded instrumentation — cannot move to AblyLiveObjectsTesting; see Test/AblyLiveObjectsTesting/README.md
    /// Finishes the following streams, to allow a test to perform assertions about which elements the streams have emitted to this moment:
    ///
    /// - testsOnly_receivedObjectProtocolMessages
    /// - testsOnly_receivedObjectSyncProtocolMessages
    /// - testsOnly_waitingForSyncEvents
    /// - the completed-garbage-collection event stream (`completedGarbageCollectionEventsWithoutBuffering`; no public accessor)
    internal func testsOnly_finishAllTestHelperStreams() {
        receivedObjectProtocolMessagesContinuation.finish()
        receivedObjectSyncProtocolMessagesContinuation.finish()
        waitingForSyncEventsContinuation.finish()
        completedGarbageCollectionEventsWithoutBufferingContinuation.finish()
    }

    // MARK: - Mutable state and the operations that affect it

    internal struct MutableState { // internal for AblyLiveObjectsTesting
        internal var objectsPool: ObjectsPool

        /// The name of the channel these objects belong to. Used to populate the `channel` field of
        /// the public ``ObjectMessage`` produced at emission (PAOM2e/PAOM3b).
        ///
        /// In production this is bound to the real channel name at construction: the `channelName`
        /// init parameter is supplied by `DefaultInternalPlugin.nosync_prepare` via the
        /// `nameForChannel:` plugin bridge.
        internal var channelName: String

        internal var onChannelAttachedHasObjects: Bool?
        internal var objectsEventSubscriptionStorage = SubscriptionStorage<ObjectsEvent, Void>()

        /// Used when the object wishes to subscribe to its own events (i.e. unaffected by `offAll()`); used e.g. to wait for a sync before returning from `getRoot()`, per RTO23c.
        internal var internalObjectsEventSubscriptionStorage = SubscriptionStorage<ObjectsEvent, Void>()

        /// The RTO10b grace period for which we will retain tombstoned objects and map entries.
        internal var garbageCollectionGracePeriod: GarbageCollectionOptions.GracePeriod

        /// RTO7b: Serials of operations that have been applied locally upon ACK but whose echoed OBJECT message has not yet been received.
        internal var appliedOnAckSerials: Set<String> = [] // RTO7b1

        /// The `siteCode` from the latest `ConnectionDetails`, pushed via ``nosync_setSiteCode``.
        internal var siteCode: String?

        /// The outcome passed to a `nosync_publishAndApply` sync waiter closure.
        internal enum PublishAndApplySyncWaiterOutcome: Sendable {
            case synced
            case channelStateFailed(
                state: _AblyPluginSupportPrivate.RealtimeChannelState,
                reason: ARTErrorInfo?,
            )
        }

        /// RTO20e/RTO20e1: Pending `nosync_publishAndApply` calls waiting for sync to complete.
        /// Each closure captures the synthetic messages to apply and the user callback.
        /// On sync completion, closures are called with `.synced`.
        /// On channel state change to detached/suspended/failed, closures are called with `.channelStateFailed`.
        ///
        /// Waiters receive `inout MutableState` so they can apply synthetic messages and pass
        /// mutable state access through to their callback, avoiding re-entrant mutex acquisition.
        internal var publishAndApplySyncWaiters: [(inout MutableState, PublishAndApplySyncWaiterOutcome) -> Void] = []

        /// The RTO17 sync state. Also stores the sync sequence data.
        internal var state = State.initialized

        /// Has the same cases as `ObjectsSyncState` but with associated data to store the sync sequence data and represent the constraint that you only have a sync sequence if you're SYNCING.
        internal enum State {
            case initialized
            case syncing(AssociatedData.Syncing)
            case synced

            /// Note: We follow the same pattern as used in the WIP ably-swift: a state's associated data is a class instance and the convention is that to update the associated data for the current state you mutate the existing instance instead of creating a new one.
            internal enum AssociatedData {
                internal class Syncing {
                    /// `OBJECT` ProtocolMessages that were received whilst SYNCING, to be applied once the sync sequence is complete, per RTO7a.
                    internal var bufferedObjectOperations: [ProtocolTypes.InboundObjectMessage]

                    /// Note that we only ever populate this during a multi-`ProtocolMessage` sync sequence. It is not used in the RTO4b or RTO5a5 cases where the sync data is entirely contained within a single ProtocolMessage, because an individual ProtocolMessage is processed atomically and so no other operations that might wish to query this property can occur concurrently with the handling of these cases.
                    ///
                    /// It is optional because there are times that we transition to SYNCING even when the sync data is contained in a single ProtocolMessage.
                    internal var syncSequence: SyncSequence?

                    internal init(bufferedObjectOperations: [ProtocolTypes.InboundObjectMessage], syncSequence: SyncSequence?) {
                        self.bufferedObjectOperations = bufferedObjectOperations
                        self.syncSequence = syncSequence
                    }
                }
            }

            internal var toObjectsSyncState: ObjectsSyncState {
                switch self {
                case .initialized:
                    .initialized
                case .syncing:
                    .syncing
                case .synced:
                    .synced
                }
            }
        }

        internal mutating func transition(
            to newState: State,
            userCallbackQueue: DispatchQueue,
        ) {
            guard newState.toObjectsSyncState != state.toObjectsSyncState else {
                preconditionFailure("Cannot transition to the current state")
            }
            state = newState
            guard let event = newState.toObjectsSyncState.toEvent else {
                return
            }
            // RTO17b
            emitObjectsEvent(event, on: userCallbackQueue)
        }

        internal mutating func nosync_onChannelAttached(
            hasObjects: Bool,
            logger: Logger,
            userCallbackQueue: DispatchQueue,
            pathObjectSubscriptionRegister: PathObjectSubscriptionRegister,
        ) {
            logger.log("onChannelAttached(hasObjects: \(hasObjects)", level: .debug)

            onChannelAttachedHasObjects = hasObjects

            // We will subsequently transition to .synced either by the completion of the RTO4a OBJECT_SYNC, or by the RTO4b no-HAS_OBJECTS case below
            switch state {
            case let .syncing(syncingData):
                // RTO4d
                syncingData.bufferedObjectOperations = []
            case .initialized, .synced:
                // RTO4c, RTO4d
                transition(to: .syncing(.init(bufferedObjectOperations: [], syncSequence: nil)), userCallbackQueue: userCallbackQueue)
            }

            // We only care about the case where HAS_OBJECTS is not set (RTO4b); if it is set then we're going to shortly receive an OBJECT_SYNC instead (RTO4a)
            guard !hasObjects else {
                return
            }

            // RTO4b1, RTO4b2: Reset the ObjectsPool to have a single empty root object
            let removedRootKeys = objectsPool.nosync_reset()

            // RTLO4b4c3b: fan the RTO4b2a reset update out to path subscriptions too (nil message,
            // RTO4b2a — sync-originated). Runs after `nosync_reset` returns, so no live object's
            // mutex is held during the fan-out. An unchanged (already-empty) root produced an empty
            // diff — nothing to dispatch, mirroring the empty-diff -> noop collapse (RTLO4b4c1).
            if !removedRootKeys.isEmpty {
                nosync_notifyPathSubscriptions(
                    objectID: ObjectsPool.rootKey,
                    changedMapKeys: removedRootKeys,
                    objectMessage: nil,
                    pathObjectSubscriptionRegister: pathObjectSubscriptionRegister,
                )
            }

            // RTO4b3, RTO4b4, RTO5c3, RTO5c4, RTO5c5, RTO5c8, RTO5c9: run the same sync-completion
            // actions as the OBJECT_SYNC path (via the shared `nosync_completeSync`), so the two
            // cannot drift. The differing data step above (`nosync_reset`, versus the OBJECT_SYNC
            // path's `applySyncObjectsPool` + buffered-op drain) is all that separates them.
            nosync_completeSync(userCallbackQueue: userCallbackQueue)
        }

        /// Implements the `OBJECT_SYNC` handling of RTO5.
        internal mutating func nosync_handleObjectSyncProtocolMessage(
            objectMessages: [ProtocolTypes.InboundObjectMessage],
            protocolMessageChannelSerial: String?,
            logger: Logger,
            internalQueue: DispatchQueue,
            userCallbackQueue: DispatchQueue,
            clock: SimpleClock,
            pathObjectSubscriptionRegister: PathObjectSubscriptionRegister,
            receivedObjectSyncProtocolMessagesContinuation: AsyncStream<[ProtocolTypes.InboundObjectMessage]>.Continuation,
        ) {
            logger.log("handleObjectSyncProtocolMessage(objectMessages: \(LoggingUtilities.formatObjectMessagesForLogging(objectMessages)), protocolMessageChannelSerial: \(String(describing: protocolMessageChannelSerial)))", level: .debug)

            receivedObjectSyncProtocolMessagesContinuation.yield(objectMessages)

            let syncCursor: SyncCursor?
            if let protocolMessageChannelSerial {
                do {
                    // RTO5a: parse the channelSerial into a sync cursor.
                    syncCursor = try SyncCursor(channelSerial: protocolMessageChannelSerial)
                } catch {
                    // RTO5a6: the channelSerial has no colon separator, so it does not conform to the
                    // RTO5a1 `<sequence id>:<cursor value>` shape. We treat a malformed channelSerial as
                    // if it were absent (per RTO5a5): the contained messages are applied and, since there
                    // is no cursor, the sync sequence ends. We log a warning rather than silently proceed.
                    logger.log("OBJECT_SYNC channelSerial is malformed (\(error)); treating as absent per RTO5a6", level: .warn)
                    syncCursor = nil
                }
            } else {
                // RTO5a5: no channelSerial; the sync data is entirely contained within this OBJECT_SYNC.
                syncCursor = nil
            }

            if case let .syncing(syncingData) = state {
                // Figure out whether to continue any existing sync sequence or start a new one
                let isNewSyncSequence = syncCursor == nil || syncingData.syncSequence?.id != syncCursor?.sequenceID
                if isNewSyncSequence {
                    // RTO5a2a: new sequence started, discard previous. Else we continue the existing sequence per RTO5a3
                    syncingData.syncSequence = nil
                }
            }

            // If populated, this contains a full set of sync data for the channel, and should be applied to the ObjectsPool.
            let completedSyncObjectsPool: SyncObjectsPool?
            // The SyncSequence, if any, to store in the SYNCING state that results from this OBJECT_SYNC.
            let syncSequenceForSyncingState: SyncSequence?

            if let syncCursor {
                let syncSequenceToContinue: SyncSequence? = if case let .syncing(syncingData) = state {
                    syncingData.syncSequence
                } else {
                    nil
                }
                var updatedSyncSequence = syncSequenceToContinue ?? .init(id: syncCursor.sequenceID, syncObjectsPool: .init())
                // RTO5f
                updatedSyncSequence.syncObjectsPool.accumulate(objectMessages, logger: logger)
                syncSequenceForSyncingState = updatedSyncSequence

                completedSyncObjectsPool = syncCursor.isEndOfSequence ? updatedSyncSequence.syncObjectsPool : nil
            } else {
                // RTO5a5: The sync data is contained entirely within this single OBJECT_SYNC
                var pool = SyncObjectsPool()
                pool.accumulate(objectMessages, logger: logger)
                completedSyncObjectsPool = pool
                syncSequenceForSyncingState = nil
            }

            if case let .syncing(syncingData) = state {
                syncingData.syncSequence = syncSequenceForSyncingState
            } else {
                // RTO5e
                transition(to: .syncing(.init(bufferedObjectOperations: [], syncSequence: syncSequenceForSyncingState)), userCallbackQueue: userCallbackQueue)
            }

            if let completedSyncObjectsPool {
                // RTO5c
                objectsPool.nosync_applySyncObjectsPool(
                    completedSyncObjectsPool,
                    logger: logger,
                    internalQueue: internalQueue,
                    userCallbackQueue: userCallbackQueue,
                    clock: clock,
                    // RTLO4b4c3b: sync-originated updates fan out to path subscriptions too (nil
                    // message, RTO4b2a), after the RTO5c10 rebuild inside applySyncObjectsPool.
                    pathObjectSubscriptionRegister: pathObjectSubscriptionRegister,
                )

                // RTO5c6
                guard case let .syncing(syncingData) = state else {
                    // We put ourselves into SYNCING above
                    preconditionFailure()
                }
                let bufferedObjectOperations = syncingData.bufferedObjectOperations
                if !bufferedObjectOperations.isEmpty {
                    logger.log("Applying \(bufferedObjectOperations.count) buffered OBJECT ObjectMessages", level: .debug)
                    for objectMessage in bufferedObjectOperations {
                        // RTO5c6
                        nosync_applyObjectProtocolMessageObjectMessage(
                            objectMessage,
                            source: .channel,
                            logger: logger,
                            internalQueue: internalQueue,
                            userCallbackQueue: userCallbackQueue,
                            clock: clock,
                            pathObjectSubscriptionRegister: pathObjectSubscriptionRegister,
                        )
                    }
                }

                // RTO5c3, RTO5c4, RTO5c5, RTO5c8, RTO5c9: shared sync-completion tail (clear
                // appliedOnAckSerials, transition to SYNCED, resume publishAndApply waiters) — the
                // same actions the RTO4b ATTACHED-with-HAS_OBJECTS-false path runs.
                nosync_completeSync(userCallbackQueue: userCallbackQueue)
            }
        }

        /// Implements the `OBJECT` handling of RTO8.
        internal mutating func nosync_handleObjectProtocolMessage(
            objectMessages: [ProtocolTypes.InboundObjectMessage],
            logger: Logger,
            internalQueue: DispatchQueue,
            userCallbackQueue: DispatchQueue,
            clock: SimpleClock,
            pathObjectSubscriptionRegister: PathObjectSubscriptionRegister,
            receivedObjectProtocolMessagesContinuation: AsyncStream<[ProtocolTypes.InboundObjectMessage]>.Continuation,
        ) {
            receivedObjectProtocolMessagesContinuation.yield(objectMessages)

            logger.log("handleObjectProtocolMessage(objectMessages: \(LoggingUtilities.formatObjectMessagesForLogging(objectMessages)))", level: .debug)

            if case let .syncing(syncingData) = state {
                // RTO8a: Buffer the OBJECT message, to be handled once the sync completes
                // Note that RTO8a says to buffer if "not SYNCED" (i.e. it includes the INITIALIZED state). But, "if SYNCING" is an equivalent check since we will only receive operations once attached, and we become SYNCING upon receipt of ATTACHED
                logger.log("Buffering OBJECT message due to in-progress sync", level: .debug)
                syncingData.bufferedObjectOperations.append(contentsOf: objectMessages)
            } else {
                // RTO8b: Handle the OBJECT message immediately
                for objectMessage in objectMessages {
                    nosync_applyObjectProtocolMessageObjectMessage(
                        objectMessage,
                        source: .channel,
                        logger: logger,
                        internalQueue: internalQueue,
                        userCallbackQueue: userCallbackQueue,
                        clock: clock,
                        pathObjectSubscriptionRegister: pathObjectSubscriptionRegister,
                    )
                }
            }
        }

        /// Implements the `OBJECT` application of RTO9.
        internal mutating func nosync_applyObjectProtocolMessageObjectMessage(
            _ objectMessage: ProtocolTypes.InboundObjectMessage,
            source: ObjectsOperationSource,
            logger: Logger,
            internalQueue: DispatchQueue,
            userCallbackQueue: DispatchQueue,
            clock: SimpleClock,
            pathObjectSubscriptionRegister: PathObjectSubscriptionRegister,
        ) {
            guard let operation = objectMessage.operation else {
                // RTO9a1
                logger.log("Unsupported OBJECT message received (no operation); \(objectMessage)", level: .warn)
                return
            }

            // RTO9a3: Skip if already applied on ACK
            if let serial = objectMessage.serial, appliedOnAckSerials.contains(serial) {
                logger.log("Skipping OBJECT message: already applied on ACK; serial=\(serial)", level: .debug)
                appliedOnAckSerials.remove(serial)
                return
            }

            // RTO9a2b: Discard unsupported actions *before* creating any zero-value object. Both this
            // and the RTO9a3 check above must precede the RTO9a2a1 creation so that a message that
            // will be discarded never leaves a spurious zero-value object in the pool.
            guard case let .known(action) = operation.action else {
                logger.log("Unsupported OBJECT operation action \(operation.action) received", level: .warn)
                return
            }

            // RTO9a2a1, RTO9a2a2
            let entry: ObjectsPool.Entry
            if let existingEntry = objectsPool.entries[operation.objectId] {
                entry = existingEntry
            } else {
                guard let newEntry = objectsPool.createZeroValueObject(
                    forObjectID: operation.objectId,
                    logger: logger,
                    internalQueue: internalQueue,
                    userCallbackQueue: userCallbackQueue,
                    clock: clock,
                ) else {
                    logger.log("Unable to create zero-value object for \(operation.objectId) when processing OBJECT message; dropping", level: .warn)
                    return
                }

                entry = newEntry
            }

            switch action {
            case .mapCreate, .mapSet, .mapRemove, .counterCreate, .counterInc, .objectDelete, .mapClear:
                // RTO9a2a3: thread the internal source message down through apply; the update stores
                // it (RTLO4b4d) and the public ObjectMessage is derived per PAOM3 only at delivery.
                let result = entry.nosync_apply(
                    operation,
                    source: source,
                    objectMessage: objectMessage,
                    objectsPool: &objectsPool,
                )

                // RTO9a2a4
                if source == .local, result.applied, let serial = objectMessage.serial {
                    appliedOnAckSerials.insert(serial)
                }

                // RTLO4b4c3b -> RTO24b: fan the emitted update out to path subscriptions. This
                // runs *after* `nosync_apply` returns (so no live object's mutex is held during
                // the `getFullPaths` DFS) and only for a non-`.noop` update (RTLO4b4c1). The
                // instance-subscription fan-out already happened inside apply.
                if let changedMapKeys = result.changedMapKeysForPathEvent {
                    nosync_notifyPathSubscriptions(
                        objectID: operation.objectId,
                        changedMapKeys: changedMapKeys,
                        objectMessage: objectMessage,
                        pathObjectSubscriptionRegister: pathObjectSubscriptionRegister,
                    )
                }
            }
        }

        /// Fans one object update out to path subscriptions, forwarding to the pool-hosted
        /// `ObjectsPool.nosync_notifyPathSubscriptions` (which documents the RTO24b semantics, the
        /// no-mutex-held precondition, and performs the PAOM3 conversion) with the given register.
        ///
        /// Passes this state's `channelName` so the pool can derive the public message (PAOM3);
        /// `objectMessage` is `nil` for sync-originated dispatch (RTO4b2a), which surfaces no message.
        internal func nosync_notifyPathSubscriptions(
            objectID: String,
            changedMapKeys: [String],
            objectMessage: ProtocolTypes.InboundObjectMessage?,
            pathObjectSubscriptionRegister: PathObjectSubscriptionRegister,
        ) {
            objectsPool.nosync_notifyPathSubscriptions(
                objectID: objectID,
                changedMapKeys: changedMapKeys,
                objectMessage: objectMessage,
                channelName: channelName,
                register: pathObjectSubscriptionRegister,
            )
        }

        /// Drains all `nosync_publishAndApply` sync waiter closures, invoking each with the given outcome.
        ///
        /// Each waiter receives `&self` so it can apply synthetic messages and pass mutable state
        /// access through to its callback without re-acquiring the mutex.
        internal mutating func nosync_drainPublishAndApplySyncWaiters(
            outcome: PublishAndApplySyncWaiterOutcome,
        ) {
            let waiters = publishAndApplySyncWaiters
            publishAndApplySyncWaiters.removeAll()
            for waiter in waiters {
                waiter(&self, outcome)
            }
        }

        /// The sync-completion tail shared by the OBJECT_SYNC completion (RTO5c) path and the RTO4b
        /// ATTACHED-with-HAS_OBJECTS-false path. Each caller first performs its own (differing) data
        /// step — RTO5c `applySyncObjectsPool` plus the RTO5c6 buffered-operation drain, versus the
        /// RTO4b1/RTO4b2 `nosync_reset` — and then runs these identical completion actions, so the two
        /// paths cannot drift: the ATTACHED-with-HAS_OBJECTS-false path and the OBJECT_SYNC path both
        /// funnel through this single completion tail.
        internal mutating func nosync_completeSync(userCallbackQueue: DispatchQueue) {
            // RTO4b3, RTO4b4, RTO5c9: Clear appliedOnAckSerials after sync
            appliedOnAckSerials.removeAll()

            // RTO5c3, RTO5c4, RTO5c5, RTO5c8
            transition(to: .synced, userCallbackQueue: userCallbackQueue)

            // RTO20e: resume any publishAndApply waiters now that sync is complete
            nosync_drainPublishAndApplySyncWaiters(
                outcome: .synced,
            )
        }

        /// RTO27: Called when the channel transitions to a state other than `ATTACHED`. For the
        /// effect on in-progress operations see RTO20e1 (`publishAndApply`) and RTO23c1 (`get()`).
        ///
        /// - RTO20e1 / RTO23c1: on `DETACHED`/`SUSPENDED`/`FAILED`, fails any in-flight
        ///   `publishAndApply` (RTO20e1) / `get()` (RTO23c1) sync waiter with the code-92008 error.
        /// - RTO27a: on `DETACHED`/`FAILED` the current objects data can no longer be known, so
        ///   every object's data is cleared to that of a new empty object of its type (an empty map
        ///   per RTLM4c, or a counter with `data` `0` per RTLC4b) **without emitting events**
        ///   (RTO27a1) and the `SyncObjectsPool` is cleared (RTO27a2).
        /// - RTO27b: on `SUSPENDED` the stored objects data is retained unchanged (the connection
        ///   may still recover and the retained data remains a valid best-effort local copy), so no
        ///   clear is performed.
        internal mutating func nosync_onChannelStateChanged(
            toState state: _AblyPluginSupportPrivate.RealtimeChannelState,
            reason: ARTErrorInfo?,
            logger: Logger,
        ) {
            switch state {
            case .detached, .suspended, .failed:
                // RTO20e1: fail any in-flight publishAndApply / get() sync waiters. (Guarded so we
                // only log/drain when there is something to drain; the RTO27 data handling below
                // runs regardless of whether any waiters were present.)
                if !publishAndApplySyncWaiters.isEmpty {
                    logger.log("Channel entered \(state) state; rejecting \(publishAndApplySyncWaiters.count) publishAndApply waiter(s)", level: .debug)
                    nosync_drainPublishAndApplySyncWaiters(
                        outcome: .channelStateFailed(state: state, reason: reason),
                    )
                }

                // RTO27a / RTO27b: manage the stored objects data.
                switch state {
                case .detached, .failed:
                    // RTO27a: the current state of the objects data can no longer be known.
                    logger.log("Channel entered \(state) state; clearing objects data per RTO27a", level: .debug)
                    // RTO27a1: clear every object's data to that of a new empty object of its type, emitting no events.
                    objectsPool.nosync_clearObjectsData()
                    // RTO27a2: clear the SyncObjectsPool.
                    nosync_clearSyncObjectsPool()
                default:
                    // RTO27b (SUSPENDED): retain the stored objects data unchanged.
                    break
                }
            default:
                // RTO27: no action for any other channel state.
                break
            }
        }

        /// RTO27a2 (also RTO5c4): Clears the in-progress `SyncObjectsPool` — the accumulated
        /// `OBJECT_SYNC` data of a partial multi-`ProtocolMessage` sync sequence — by discarding the
        /// stored sync sequence. A no-op when no sync sequence is in progress. Deliberately does not
        /// clear `bufferedObjectOperations` (RTO27a2 concerns only the `SyncObjectsPool`) nor change
        /// the sync state.
        private mutating func nosync_clearSyncObjectsPool() {
            if case let .syncing(syncingData) = state {
                syncingData.syncSequence = nil
            }
        }

        internal typealias UpdateMutableState = @Sendable (_ action: (inout Self) -> Void) -> Void

        @discardableResult
        internal mutating func on(event: ObjectsEvent, callback: @escaping ObjectsEventCallback, updateSelfLater: @escaping UpdateMutableState) -> any OnObjectsEventResponse {
            let updateSubscriptionStorage: SubscriptionStorage<ObjectsEvent, Void>.UpdateSubscriptionStorage = { action in
                updateSelfLater { mutableState in
                    action(&mutableState.objectsEventSubscriptionStorage)
                }
            }

            let subscription = objectsEventSubscriptionStorage.subscribe(
                listener: { _, subscriptionInCallback in
                    let response = ObjectsEventResponse(subscription: subscriptionInCallback)
                    callback(response)
                },
                eventName: event,
                updateSelfLater: updateSubscriptionStorage,
            )

            return ObjectsEventResponse(subscription: subscription)
        }

        /// Adds a subscriber to the ``internalObjectsEventSubscriptionStorage`` (i.e. unaffected by `offAll()`).
        @discardableResult
        internal mutating func onInternal(event: ObjectsEvent, callback: @escaping ObjectsEventCallback, updateSelfLater: @escaping UpdateMutableState) -> any OnObjectsEventResponse {
            // TODO: Looking at this again later the whole process for adding a subscriber is really verbose and boilerplate-y, and I think the unfortunate result of me trying to be clever at some point; revisit in https://github.com/ably/ably-liveobjects-swift-plugin/issues/102. Also as things stand we end up not being able to use this method because we run into Swift exclusivity violations when we try to unsubscribe from within a listener that's invoked when the mutable state mutex is already held (see https://github.com/ably/ably-liveobjects-swift-plugin/issues/120), so e.g. the RTO20 wait-for-synced can't use this mechanism, which it should be able to.
            let updateSubscriptionStorage: SubscriptionStorage<ObjectsEvent, Void>.UpdateSubscriptionStorage = { action in
                updateSelfLater { mutableState in
                    action(&mutableState.internalObjectsEventSubscriptionStorage)
                }
            }

            let subscription = internalObjectsEventSubscriptionStorage.subscribe(
                listener: { _, subscriptionInCallback in
                    let response = ObjectsEventResponse(subscription: subscriptionInCallback)
                    callback(response)
                },
                eventName: event,
                updateSelfLater: updateSubscriptionStorage,
            )

            return ObjectsEventResponse(subscription: subscription)
        }

        // RTO18f
        private struct ObjectsEventResponse: OnObjectsEventResponse {
            let subscription: any SubscribeResponse

            func off() {
                subscription.unsubscribe()
            }
        }

        internal mutating func offAll() {
            objectsEventSubscriptionStorage.unsubscribeAll()
        }

        internal func emitObjectsEvent(_ event: ObjectsEvent, on queue: DispatchQueue) {
            objectsEventSubscriptionStorage.emit(eventName: event, on: queue)
            internalObjectsEventSubscriptionStorage.emit(eventName: event, on: queue)
        }
    }
}
