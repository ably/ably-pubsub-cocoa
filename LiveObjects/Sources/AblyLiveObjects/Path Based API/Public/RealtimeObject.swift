import Ably

/// Describes the events emitted by a ``RealtimeObject``. Spec: `RTO18b`.
public enum ObjectsEvent: Sendable {
    /// The local copy of Objects on a channel is currently being synchronized with the Ably service.
    case syncing
    /// The local copy of Objects on a channel has been synchronized with the Ably service.
    case synced
}

/// Enables the Objects on a channel to be read, modified and subscribed to, via path objects.
///
/// This is the entry point into the public LiveObjects API. ``get()`` returns a
/// ``LiveMapPathObject`` rooted at the channel's root map, from which the rest of the graph is
/// navigated. Spec: `RTO`.
public protocol RealtimeObject: Sendable {
    /// Returns a ``LiveMapPathObject`` rooted at the channel's root map with an empty path, once the
    /// objects are synchronized with the Ably service. Spec: `RTO23`.
    func get() async throws(ARTErrorInfo) -> any LiveMapPathObject

    /// Registers the provided listener for the specified event.
    ///
    /// To deregister the listener, call ``StatusSubscription/off()`` on the returned subscription.
    ///
    /// - Parameters:
    ///   - event: The event to listen for.
    ///   - callback: The listener to call when the event is emitted.
    /// - Returns: A ``StatusSubscription`` that allows the listener to be deregistered.
    /// Spec: `RTO18`.
    @discardableResult
    func on(event: ObjectsEvent, callback: @escaping @Sendable () -> Void) -> any StatusSubscription
}
