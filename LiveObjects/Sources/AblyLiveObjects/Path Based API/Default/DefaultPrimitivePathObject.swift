import Ably

/// Default implementation of ``PrimitivePathObject``, a terminal primitive view adding a
/// type-narrowed ``value()`` on top of ``DefaultPathObject``. Per RTTS6h, the six per-primitive
/// `PathObject` sub-classes of RTTS6c are collapsed into a single type fronting a ``Primitive`` enum.
///
/// Spec: `RTTS6c`, `RTTS6h`.
internal final class DefaultPrimitivePathObject: DefaultPathObject, PrimitivePathObject, @unchecked Sendable {
    internal func value() throws(ARTErrorInfo) -> Primitive? {
        try ChannelConfigGuards.throwIfInvalidAccessApiConfiguration(coreSDK: coreSDK, internalQueue: internalQueue)
        // RTPO7f — path resolution fails -> nil (RTPO3c1).
        guard let resolved = try resolveValueAtCurrentPath() else {
            return nil
        }
        // RTTS6h: the collapsed primitive view returns whatever primitive resolved (rather than the
        // six type-filtered views of RTTS6c).
        switch resolved {
        // RTPO7d — a resolved primitive is returned directly.
        case let .string(value):
            return .string(value)
        case let .number(value):
            return .number(value)
        case let .bool(value):
            return .bool(value)
        case let .data(value):
            return .data(value)
        case let .jsonArray(value):
            return .jsonArray(value)
        case let .jsonObject(value):
            return .jsonObject(value)
        // RTPO7e — an InternalLiveMap resolves to nil; a counter likewise (RTTS6c never yields a
        // LiveObject's value, unlike the general RTPO7c).
        case .liveMap, .liveCounter:
            return nil
        }
    }
}
