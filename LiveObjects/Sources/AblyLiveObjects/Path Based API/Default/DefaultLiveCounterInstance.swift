import Ably
import Foundation

/// Default implementation of ``LiveCounterInstance``, bound to a specific
/// ``InternalDefaultLiveCounter`` (RTINS2a). Spec: `RTINS1`, `RTTS10b`.
internal final class DefaultLiveCounterInstance: LiveCounterInstance {
    private let node: InternalDefaultLiveCounter
    private let coreSDK: CoreSDK
    private let realtimeObjects: any InternalRealtimeObjectsProtocol
    private let internalQueue: DispatchQueue

    /// The wrapped counter's `objectId` (RTINS3a).
    internal let id: String

    internal init(
        node: InternalDefaultLiveCounter,
        coreSDK: CoreSDK,
        realtimeObjects: any InternalRealtimeObjectsProtocol,
        internalQueue: DispatchQueue,
    ) {
        self.node = node
        self.coreSDK = coreSDK
        self.realtimeObjects = realtimeObjects
        self.internalQueue = internalQueue
        // RTINS3a: the node's objectId is immutable (set at construction), so it is read directly.
        id = node.objectID
    }

    // MARK: - LiveCounterInstance

    internal var value: Double {
        get throws(ARTErrorInfo) {
            // RTINS4a/RTINS4b -> RTLC5 (the node accessor runs the RTO25b check)
            try node.value(coreSDK: coreSDK)
        }
    }

    internal func increment(amount: Double) async throws(ARTErrorInfo) {
        // RTINS14c -> RTLC12
        try await node.increment(amount: amount, coreSDK: coreSDK, realtimeObjects: realtimeObjects)
    }

    internal func decrement(amount: Double) async throws(ARTErrorInfo) {
        // RTINS15c -> RTLC13
        try await node.decrement(amount: amount, coreSDK: coreSDK, realtimeObjects: realtimeObjects)
    }

    @discardableResult
    internal func subscribe(listener: @escaping InstanceSubscriptionCallback) throws(ARTErrorInfo) -> any Subscription {
        // RTINS16b (the node's subscribe runs the RTO25b check), RTINS16d -> RTLO4b
        let response = try node.subscribe(
            listener: { [weak self] update, _ in
                guard let self else {
                    return
                }
                // RTINS16e1: an Instance wrapping this counter (identity-based, RTINS16g).
                // RTINS16e2: project the stored internal source message to the public message per
                // PAOM3 at this delivery boundary (nil for sync-originated updates).
                listener(.init(object: .liveCounter(self), message: update.objectMessage?.toPublicObjectMessage(channelName: coreSDK.channelName)))
            },
            coreSDK: coreSDK,
        )
        // RTINS16f
        return DefaultSubscription(response: response)
    }

    internal func compactJson() throws(ARTErrorInfo) -> JSONValue {
        // RTINS11a/RTINS11b -> RTPO14 -> RTPO13d: a counter compacts to its current numeric value.
        // The node's `value(coreSDK:)` runs the RTO25b check.
        try .number(node.value(coreSDK: coreSDK))
    }
}
