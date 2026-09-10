internal enum LiveObjectUpdate<Update: Sendable>: Sendable {
    case noop // RTLO4b4
    case update(Update) // RTLO4b4a

    // MARK: - Convenience getters

    /// Returns `true` if and only if this `LiveObjectUpdate` has case `noop`.
    internal var isNoop: Bool {
        if case .noop = self {
            true
        } else {
            false
        }
    }

    /// If this `LiveObjectUpdate` has case `update`, returns the associated value. Else, returns `nil`.
    internal var update: Update? {
        if case let .update(update) = self {
            update
        } else {
            nil
        }
    }
}

extension LiveObjectUpdate: Equatable where Update: Equatable {}

// MARK: - Message/tombstone enrichment

internal extension LiveObjectUpdate where Update: LiveObjectUpdatePayload {
    /// The internal source object message carried by an `update` payload (`nil` for `noop` or
    /// sync-originated updates). The public message is projected per PAOM3 at delivery. Spec: RTLO4b4d.
    var objectMessage: ProtocolTypes.InboundObjectMessage? {
        update?.objectMessage
    }

    /// Whether this update tombstones the object. `false` for `noop`. Spec: RTLO4b4e.
    var tombstone: Bool {
        update?.tombstone ?? false
    }

    /// Returns a copy of this update whose `update` payload carries the given internal source object
    /// message; `noop` updates are returned unchanged. Used to stamp the source message onto an
    /// update at emission time (RTLO4b4d); the public message is projected per PAOM3 at delivery.
    func nosync_stampingObjectMessage(_ message: ProtocolTypes.InboundObjectMessage?) -> Self {
        guard case var .update(payload) = self else {
            return self
        }
        payload.objectMessage = message
        return .update(payload)
    }
}
