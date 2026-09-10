import Ably

// MARK: - Subscription (SUB)

/// A registration for receiving events from a subscribe operation. Spec: `SUB`.
public protocol Subscription: Sendable {
    /// Deregisters the listener registered by the corresponding `subscribe` call. Once called, the
    /// listener must not be called for any subsequent events. Calling more than once is a no-op.
    /// Spec: `SUB2a`, `SUB2b`.
    func unsubscribe()
}

// MARK: - StatusSubscription (RTO18f)

/// Object returned from ``RealtimeObject/on(event:callback:)``, allowing the listener provided in
/// that call to be deregistered. Spec: `RTO18f`.
public protocol StatusSubscription: Sendable {
    /// Deregisters the listener passed to the `on` call. Spec: `RTO18f1`.
    func off()
}

// MARK: - PathObject subscription

/// The event delivered to a ``PathObject/subscribe(options:listener:)`` listener. Spec: `RTPO19e`.
public struct PathObjectSubscriptionEvent: Sendable {
    /// A ``PathObject`` pointing to the path where the change occurred. Spec: `RTPO19e1`.
    public let object: any PathObject
    /// The object message that triggered this event, if available. Spec: `RTPO19e2`.
    public let message: ObjectMessage?

    public init(object: any PathObject, message: ObjectMessage? = nil) {
        self.object = object
        self.message = message
    }
}

/// Options for ``PathObject/subscribe(options:listener:)``. Spec: `RTPO19c`.
public struct PathObjectSubscriptionOptions: Sendable {
    /// Controls how many levels of path nesting below the subscription path trigger the listener.
    /// Defaults to `nil`. If provided, must be a positive integer. Spec: `RTPO19c1`.
    public let depth: Int?

    public init(depth: Int? = nil) {
        self.depth = depth
    }
}

/// The callback used by ``PathObject/subscribe(options:listener:)``. Spec: `RTPO19a1`.
public typealias PathObjectSubscriptionCallback = @Sendable (_ event: PathObjectSubscriptionEvent) -> Void

// MARK: - Instance subscription

/// The event delivered to an ``Instance`` subscribe listener. Spec: `RTINS16e`.
public struct InstanceSubscriptionEvent: Sendable {
    /// An ``Instance`` wrapping the underlying object. Spec: `RTINS16e1`.
    public let object: Instance
    /// The object message that triggered this event, if available. Spec: `RTINS16e2`.
    public let message: ObjectMessage?

    public init(object: Instance, message: ObjectMessage? = nil) {
        self.object = object
        self.message = message
    }
}

/// The callback used by an ``Instance`` subscribe. Spec: `RTINS16a1`.
public typealias InstanceSubscriptionCallback = @Sendable (_ event: InstanceSubscriptionEvent) -> Void
