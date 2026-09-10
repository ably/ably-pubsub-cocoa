import Foundation

/// Handles subscription bookkeeping, providing methods for subscribing and emitting events.
internal struct SubscriptionStorage<EventName: Hashable & Sendable, Update: Sendable> {
    /// Internal bookkeeping for subscriptions, organized by event name.
    /// Each event name maps to a dictionary of subscriptions keyed by their ID.
    private var subscriptionsByEventName: [EventName: [Subscription.ID: Subscription]] = [:]

    // MARK: - Subscriptions

    private struct Subscription: Identifiable {
        var id = UUID()
        var listener: LiveObjectUpdateCallback<Update>
        var updateSubscriptionStorage: UpdateSubscriptionStorage
    }

    /// A function that allows a `SubscriptionStorage` to later perform mutations to an externally-held copy of itself. This is used to allow a `SubscribeResponse` to unsubscribe.
    ///
    /// Accepts an action, which, if called, should be called with an `inout` reference to the externally-held copy. The function is not required to call this action (for example, if the function holds a weak reference which is now `nil`).
    ///
    /// Note that the `SubscriptionStorage` will store a copy of this function and thus this function should be careful not to introduce a strong reference cycle.
    internal typealias UpdateSubscriptionStorage = @Sendable (_ action: (inout Self) -> Void) -> Void

    private struct SubscribeResponse: AblyLiveObjects.SubscribeResponse {
        var subscriptionID: Subscription.ID
        var eventName: EventName
        var updateSubscriptionStorage: UpdateSubscriptionStorage

        func unsubscribe() {
            updateSubscriptionStorage { subscriptionStorage in
                subscriptionStorage.unsubscribe(subscriptionID: subscriptionID, eventName: eventName)
            }
        }
    }

    @discardableResult
    internal mutating func subscribe(
        listener: @escaping LiveObjectUpdateCallback<Update>,
        eventName: EventName,
        updateSelfLater: @escaping UpdateSubscriptionStorage,
    ) -> any AblyLiveObjects.SubscribeResponse {
        let subscription = Subscription(listener: listener, updateSubscriptionStorage: updateSelfLater)

        if subscriptionsByEventName[eventName] == nil {
            subscriptionsByEventName[eventName] = [:]
        }

        subscriptionsByEventName[eventName]?[subscription.id] = subscription

        return SubscribeResponse(subscriptionID: subscription.id, eventName: eventName, updateSubscriptionStorage: updateSelfLater)
    }

    internal mutating func unsubscribeAll() {
        subscriptionsByEventName.removeAll()
    }

    private mutating func unsubscribe(subscriptionID: Subscription.ID, eventName: EventName) {
        subscriptionsByEventName[eventName]?.removeValue(forKey: subscriptionID)

        if subscriptionsByEventName[eventName]?.isEmpty == true {
            subscriptionsByEventName.removeValue(forKey: eventName)
        }
    }

    internal func emit(_ update: Update, eventName: EventName, on queue: DispatchQueue) {
        guard let subscriptions = subscriptionsByEventName[eventName] else {
            return
        }

        for subscription in subscriptions.values {
            queue.async {
                let response = SubscribeResponse(subscriptionID: subscription.id, eventName: eventName, updateSubscriptionStorage: subscription.updateSubscriptionStorage)
                subscription.listener(update, response)
            }
        }
    }
}

// MARK: - Convenience extension for Void updates

internal extension SubscriptionStorage where Update == Void {
    /// Convenience method for emitting events when there's no update data to pass.
    func emit(eventName: EventName, on queue: DispatchQueue) {
        emit((), eventName: eventName, on: queue)
    }
}
