import Ably
import Foundation

/// Default implementation of ``PrimitiveInstance``. Per RTTS6h, the six per-primitive `Instance`
/// sub-classes of RTTS10c are collapsed into a single type fronting a ``Primitive`` enum, bound to an
/// already-extracted value (RTINS2a). Spec: `RTINS1`, `RTTS10c`, `RTTS6h`.
///
/// A primitive has no backing internal node, so the RTO25b access-precondition check is run by
/// hopping onto the shared `internalQueue`.
internal final class DefaultPrimitiveInstance: PrimitiveInstance {
    private let primitive: Primitive
    private let valueType: ValueType
    private let coreSDK: CoreSDK
    private let internalQueue: DispatchQueue

    internal init(value: Primitive, type: ValueType, coreSDK: CoreSDK, internalQueue: DispatchQueue) {
        primitive = value
        valueType = type
        self.coreSDK = coreSDK
        self.internalQueue = internalQueue
    }

    // MARK: - PrimitiveInstance

    internal var value: Primitive {
        get throws(ARTErrorInfo) {
            // RTINS4a: access API preconditions per RTO25
            try sync_checkAccessPreconditionsOnQueue()
            // RTINS4c: return the value directly
            return primitive
        }
    }

    internal var type: ValueType {
        // RTTS8: no access-precondition check (non-throwing accessor)
        valueType
    }

    internal func compactJson() throws(ARTErrorInfo) -> JSONValue {
        // RTINS11a: access API preconditions per RTO25
        try sync_checkAccessPreconditionsOnQueue()
        // RTINS11b -> RTPO14: a primitive compacts to itself, with binary base64-encoded (RTPO14b1)
        return Self.compactJson(for: primitive)
    }

    // MARK: - Helpers

    /// Performs its own synchronisation: hops onto the shared internal queue to run the RTO25b
    /// channel-state check (DETACHED/FAILED -> 90001), reusing the exact check the map/counter node
    /// accessors run (`value(coreSDK:)`, `get(...)`). Must NOT be called while already on the queue.
    private func sync_checkAccessPreconditionsOnQueue() throws(ARTErrorInfo) {
        let result: Result<Void, ARTErrorInfo> = internalQueue.ably_syncNoDeadlock {
            do throws(ARTErrorInfo) {
                // RTO25b
                try coreSDK.nosync_validateChannelStateForAccessAPI(operationDescription: "PrimitiveInstance")
                return .success(())
            } catch {
                return .failure(error)
            }
        }
        try result.get()
    }

    /// Compacts a ``Primitive`` to a JSON-serializable ``JSONValue``, per RTPO13c4/RTPO14b1.
    internal static func compactJson(for primitive: Primitive) -> JSONValue {
        switch primitive {
        case let .string(value):
            .string(value)
        case let .number(value):
            .number(value)
        case let .bool(value):
            .bool(value)
        case let .data(value):
            // RTPO14b1: binary values are encoded as base64 strings
            .string(value.base64EncodedString())
        case let .jsonArray(value):
            .array(value)
        case let .jsonObject(value):
            .object(value)
        }
    }
}
