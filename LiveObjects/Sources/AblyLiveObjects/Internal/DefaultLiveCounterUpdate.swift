internal struct DefaultLiveCounterUpdate: LiveCounterUpdate, Equatable {
    internal var amount: Double
    /// The internal source object message (op-bearing only), or `nil` for sync-originated updates
    /// (RTO4b2a). The public message is projected per PAOM3 at delivery.
    internal var objectMessage: ProtocolTypes.InboundObjectMessage?
    /// Whether this update tombstones the counter (RTLO4b4e).
    internal var tombstone: Bool

    internal init(amount: Double, objectMessage: ProtocolTypes.InboundObjectMessage? = nil, tombstone: Bool = false) {
        self.amount = amount
        self.objectMessage = objectMessage
        self.tombstone = tombstone
    }
}
