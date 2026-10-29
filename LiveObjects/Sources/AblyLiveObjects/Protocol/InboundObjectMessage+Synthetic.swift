internal extension ProtocolTypes.InboundObjectMessage {
    /// Creates a synthetic inbound message from an outbound message, per RTO20d2 and RTO20d3.
    ///
    /// Used to apply a locally-published operation upon receipt of the ACK from Realtime.
    static func createSynthetic(from outboundMessage: ProtocolTypes.OutboundObjectMessage, serial: String, siteCode: String) -> ProtocolTypes.InboundObjectMessage {
        ProtocolTypes.InboundObjectMessage(
            id: outboundMessage.id,
            clientId: outboundMessage.clientId,
            connectionId: outboundMessage.connectionId,
            extras: outboundMessage.extras,
            timestamp: outboundMessage.timestamp,
            operation: outboundMessage.operation,
            object: nil,
            serial: serial, // RTO20d2a
            siteCode: siteCode, // RTO20d2b
            serialTimestamp: nil,
        )
    }
}
