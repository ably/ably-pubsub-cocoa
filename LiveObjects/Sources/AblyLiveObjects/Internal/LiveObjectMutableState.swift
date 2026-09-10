internal import _AblyPluginSupportPrivate
import Ably

/// This is the equivalent of the `LiveObject` abstract class described in RTLO.
///
/// ``InternalDefaultLiveCounter`` and ``InternalDefaultLiveMap`` include it by composition.
internal struct LiveObjectMutableState<Update: Sendable> {
    // RTLO3a
    internal var objectID: String
    // RTLO3b
    internal var siteTimeserials: [String: String] = [:]
    // RTLO3c
    internal var createOperationIsMerged = false
    // RTLO3d
    internal var isTombstone: Bool {
        // TODO: Confirm that we don't need to store this (https://github.com/ably/specification/pull/350/files#r2213895661)
        tombstonedAt != nil
    }

    // RTLO3e
    internal var tombstonedAt: Date?

    /// Reverse references: parent map `objectID` -> the set of keys at which that map references
    /// this object. Keyed by objectID per RTLO3f/RTLO3f1 (references between objects are stored as
    /// objectIds and resolved via the pool).
    /// Spec: RTLO3f, RTLO3f2 (initialised to an empty map).
    internal var parentReferences: [String: Set<String>] = [:]

    private enum EventName {
        case update
    }

    /// Internal subscription storage.
    private var subscriptionStorage = SubscriptionStorage<EventName, Update>()

    /// Internal lifecycle event subscription storage.
    private var lifecycleEventSubscriptionStorage = SubscriptionStorage<LiveObjectLifecycleEvent, Void>()

    internal init(objectID: String) {
        self.objectID = objectID
    }

    /// Represents parameters of an operation that `canApplyOperation` has decided can be applied to a `LiveObject`.
    ///
    /// The key thing is that it offers a non-nil `serial` and `siteCode`, which will be needed when subsequently performing the operation.
    internal struct ApplicableOperation: Equatable {
        internal let objectMessageSerial: String
        internal let objectMessageSiteCode: String
    }

    /// Indicates whether an operation described by an `ObjectMessage` should be applied or discarded, per RTLO4a.
    ///
    /// Instead of returning a `Bool`, in the case where the operation can be applied it returns a non-nil `ApplicableOperation` (whose non-nil `serial` and `siteCode` will be needed as part of subsequently performing this operation).
    internal func canApplyOperation(objectMessageSerial: String?, objectMessageSiteCode: String?, logger: Logger) -> ApplicableOperation? {
        // RTLO4a3: Both ObjectMessage.serial and ObjectMessage.siteCode must be non-empty strings
        guard let serial = objectMessageSerial, !serial.isEmpty,
              let siteCode = objectMessageSiteCode, !siteCode.isEmpty
        else {
            // RTLO4a3: Otherwise, log a warning that the object operation message has invalid serial values
            logger.log("Object operation message has invalid serial values: serial=\(objectMessageSerial ?? "nil"), siteCode=\(objectMessageSiteCode ?? "nil")", level: .warn)
            return nil
        }

        // RTLO4a4: Get the siteSerial value stored for this LiveObject in the siteTimeserials map using the key ObjectMessage.siteCode
        let siteSerial = siteTimeserials[siteCode]

        // RTLO4a5: If the siteSerial for this LiveObject is null or an empty string, return true
        guard let siteSerial, !siteSerial.isEmpty else {
            return ApplicableOperation(objectMessageSerial: serial, objectMessageSiteCode: siteCode)
        }

        // RTLO4a6: If the siteSerial for this LiveObject is not an empty string, return true if ObjectMessage.serial is greater than siteSerial when compared lexicographically
        if serial > siteSerial {
            return ApplicableOperation(objectMessageSerial: serial, objectMessageSiteCode: siteCode)
        }

        return nil
    }

    // MARK: - Subscriptions

    internal typealias UpdateLiveObject = @Sendable (_ action: (inout Self) -> Void) -> Void

    @discardableResult
    internal mutating func nosync_subscribe(listener: @escaping LiveObjectUpdateCallback<Update>, coreSDK: CoreSDK, updateSelfLater: @escaping UpdateLiveObject) throws(ARTErrorInfo) -> any AblyLiveObjects.SubscribeResponse {
        // RTO25
        try coreSDK.nosync_validateChannelStateForAccessAPI(operationDescription: "subscribe")

        let updateSubscriptionStorage: SubscriptionStorage<EventName, Update>.UpdateSubscriptionStorage = { action in
            updateSelfLater { liveObject in
                action(&liveObject.subscriptionStorage)
            }
        }

        return subscriptionStorage.subscribe(
            listener: listener,
            eventName: .update,
            updateSelfLater: updateSubscriptionStorage,
        )
    }

    @discardableResult
    internal mutating func on(event: LiveObjectLifecycleEvent, callback: @escaping LiveObjectLifecycleEventCallback, updateSelfLater: @escaping UpdateLiveObject) -> any OnLiveObjectLifecycleEventResponse {
        let updateSubscriptionStorage: SubscriptionStorage<LiveObjectLifecycleEvent, Void>.UpdateSubscriptionStorage = { action in
            updateSelfLater { liveObject in
                action(&liveObject.lifecycleEventSubscriptionStorage)
            }
        }

        let subscription = lifecycleEventSubscriptionStorage.subscribe(
            listener: { _, subscriptionInCallback in
                let response = LifecycleEventResponse(subscription: subscriptionInCallback)
                callback(response)
            },
            eventName: event,
            updateSelfLater: updateSubscriptionStorage,
        )

        return LifecycleEventResponse(subscription: subscription)
    }

    private struct LifecycleEventResponse: OnLiveObjectLifecycleEventResponse {
        let subscription: any SubscribeResponse

        func off() {
            subscription.unsubscribe()
        }
    }

    internal mutating func unsubscribeAll() {
        subscriptionStorage.unsubscribeAll()
    }

    internal mutating func offAll() {
        lifecycleEventSubscriptionStorage.unsubscribeAll()
    }

    internal func emit(_ update: LiveObjectUpdate<Update>, on queue: DispatchQueue) {
        switch update {
        case .noop:
            // RTLO4b4c1
            return
        case let .update(update):
            // RTLO4b4c3a
            subscriptionStorage.emit(update, eventName: .update, on: queue)
        }
    }

    internal func emitLifecycleEvent(_ event: LiveObjectLifecycleEvent, on queue: DispatchQueue) {
        lifecycleEventSubscriptionStorage.emit(eventName: event, on: queue)
    }
}
