import Ably

// This file contains supporting types for the internal live-object engine (the callbacks, update
// descriptors and subscription-handle protocols used by `InternalDefaultLiveMap` /
// `InternalDefaultLiveCounter` and `InternalDefaultRealtimeObjects`). None of these are exposed to
// users; the public surface is the path-object / instance API (see the `Path Based API` directory).

/// A callback used by an internal live object to listen for updates to the object.
internal typealias LiveObjectUpdateCallback<T> = @Sendable (_ update: sending T, _ subscription: SubscribeResponse) -> Void

/// The callback used for the lifecycle events emitted by an internal live object.
internal typealias LiveObjectLifecycleEventCallback = @Sendable (_ subscription: OnLiveObjectLifecycleEventResponse) -> Void

/// Describes the lifecycle events emitted by an internal live object.
internal enum LiveObjectLifecycleEvent: Sendable {
    /// Indicates that the object has been deleted from the Objects pool and should no longer be interacted with.
    case deleted
}

// The `ObjectsEvent` enum that these types refer to now lives in `RealtimeObject.swift` as part of
// the new public API; its cases (`.syncing` / `.synced`) are unchanged, so the internal engine
// continues to use it. The following two supporting types were part of the old public API surface
// but are still needed internally by `InternalDefaultRealtimeObjects` (e.g. `getRoot()` waits for a
// sync via `onInternal(event:callback:)`), so they are retained as `internal`.

/// The callback used for the events emitted by ``InternalDefaultRealtimeObjects``.
internal typealias ObjectsEventCallback = @Sendable (_ subscription: OnObjectsEventResponse) -> Void

/// Object returned from an `on` call, allowing the listener provided in that call to be deregistered.
internal protocol OnObjectsEventResponse: Sendable {
    /// Deregisters the listener passed to the `on` call.
    func off()
}

/// Describes whether an entry in ``LiveMapUpdate/update`` represents an update or a removal.
internal enum LiveMapUpdateAction: Sendable {
    /// The value of a key in the map was updated.
    case updated
    /// The value of a key in the map was removed.
    case removed
}

/// The message/tombstone enrichment carried by every non-noop update, per RTLO4b4d/RTLO4b4e.
///
/// - `objectMessage` is the internal source ``ProtocolTypes/InboundObjectMessage`` the operation
///   came from, or `nil` for sync-originated updates (RTO4b2a). The public ``ObjectMessage`` is
///   projected from it per PAOM3 at the delivery boundary, not stored here.
/// - `tombstone` is `true` when the update results from this object being tombstoned; the emitter
///   deregisters the object's subscriptions afterwards (RTLO4b4c3c).
internal protocol LiveObjectUpdatePayload: Sendable {
    /// The internal source object message (op-bearing only), or `nil` for sync-originated updates.
    var objectMessage: ProtocolTypes.InboundObjectMessage? { get set }
    /// Whether this update tombstones the object.
    var tombstone: Bool { get set }
}

/// Represents an update to an internal live map (``InternalDefaultLiveMap``).
internal protocol LiveMapUpdate: LiveObjectUpdatePayload {
    /// The keys that have changed, along with their change status.
    var update: [String: LiveMapUpdateAction] { get }
}

/// Represents an update to an internal live counter (``InternalDefaultLiveCounter``).
internal protocol LiveCounterUpdate: LiveObjectUpdatePayload {
    /// Holds the numerical change to the counter value.
    var amount: Double { get }
}

/// Object returned from a `subscribe` call, allowing the listener provided in that call to be deregistered.
internal protocol SubscribeResponse: Sendable {
    /// Deregisters the listener passed to the `subscribe` call.
    func unsubscribe()
}

/// Object returned from an `on` call, allowing the listener provided in that call to be deregistered.
internal protocol OnLiveObjectLifecycleEventResponse: Sendable {
    /// Deregisters the listener passed to the `on` call.
    func off()
}
