internal struct DefaultLiveMapUpdate: LiveMapUpdate, Equatable {
    internal var update: [String: LiveMapUpdateAction]
    /// The internal source object message (op-bearing only), or `nil` for sync-originated updates
    /// (RTO4b2a). The public message is projected per PAOM3 at delivery.
    internal var objectMessage: ProtocolTypes.InboundObjectMessage?
    /// Whether this update tombstones the map (RTLO4b4e).
    internal var tombstone: Bool

    internal init(update: [String: LiveMapUpdateAction], objectMessage: ProtocolTypes.InboundObjectMessage? = nil, tombstone: Bool = false) {
        self.update = update
        self.objectMessage = objectMessage
        self.tombstone = tombstone
    }
}
