/// RTO22: Describes the source of an operation being applied.
internal enum ObjectsOperationSource {
    /// RTO22a: An operation that originated locally, being applied upon receipt of the ACK from Realtime.
    case local
    /// RTO22b: An operation received over a Realtime channel.
    case channel
}
