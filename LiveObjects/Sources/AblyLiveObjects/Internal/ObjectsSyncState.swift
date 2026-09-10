/// The type that the spec uses to represent the client's state of syncing its local Objects data with the server, per RTO17a.
internal enum ObjectsSyncState {
    case initialized
    case syncing
    case synced

    /// The event to emit when transitioning to this state, per RTO17b.
    internal var toEvent: ObjectsEvent? {
        switch self {
        case .initialized:
            nil
        case .syncing:
            .syncing
        case .synced:
            .synced
        }
    }
}
