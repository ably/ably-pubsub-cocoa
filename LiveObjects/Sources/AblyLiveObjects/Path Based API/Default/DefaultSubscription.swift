import Ably

/// Default implementation of the public ``Subscription`` (SUB). It wraps the internal engine's
/// ``SubscribeResponse`` handle so that `unsubscribe()` deregisters the listener on the underlying
/// live object. Spec: `SUB2a`, `SUB2b`.
internal final class DefaultSubscription: Subscription, Sendable {
    private let response: any SubscribeResponse

    internal init(response: any SubscribeResponse) {
        self.response = response
    }

    internal func unsubscribe() {
        response.unsubscribe()
    }
}
