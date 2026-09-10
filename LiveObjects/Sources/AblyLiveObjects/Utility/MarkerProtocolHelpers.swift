internal import _AblyPluginSupportPrivate
import Ably

/// Upcasts an instance of an `_AblyPluginSupportPrivate` marker protocol to the concrete type that this marker protocol represents.
internal func castPluginPublicMarkerProtocolValue<T>(_ pluginMarkerProtocolValue: Any, to _: T.Type) -> T {
    guard let actualPublicValue = pluginMarkerProtocolValue as? T else {
        preconditionFailure("Expected \(T.self), got \(type(of: pluginMarkerProtocolValue))")
    }

    return actualPublicValue
}

internal extension ARTRealtimeChannel {
    /// Downcasts this `ARTRealtimeChannel` to its `_AblyPluginSupportPrivate` equivalent type `PublicRealtimeChannel`.
    ///
    /// - Note: Swift compiler restrictions prevent us from declaring `ARTRealtimeChannel` as conforming to `PublicRealtimeChannel` (this is due to our use of `internal import`).
    var asPluginPublicRealtimeChannel: _AblyPluginSupportPrivate.PublicRealtimeChannel {
        // In order for this cast to succeed, we rely on the fact that ably-cocoa internally declares ARTRealtimeChannel as conforming to PublicRealtimeChannel.
        // swiftlint:disable:next force_cast
        self as! _AblyPluginSupportPrivate.PublicRealtimeChannel
    }
}

internal extension ARTClientOptions {
    /// Downcasts this `ARTClientOptions` to its `_AblyPluginSupportPrivate` marker protocol type `PublicClientOptions`.
    ///
    /// - Note: Swift compiler restrictions prevent us from declaring `ARTClientOptions` as conforming to `PublicClientOptions` (this is due to our use of `internal import`).
    var asPluginPublicClientOptions: _AblyPluginSupportPrivate.PublicClientOptions {
        // In order for this cast to succeed, we rely on the fact that ably-cocoa internally declares ARTClientOptions as conforming to PublicClientOptions.
        // swiftlint:disable:next force_cast
        self as! _AblyPluginSupportPrivate.PublicClientOptions
    }

    /// Upcasts an instance of `_AblyPluginSupportPrivate`'s `PublicClientOptions`, which is the marker protocol that it uses to represent an `ARTClientOptions`, to an `ARTClientOptions`.
    static func castPluginPublicClientOptions(_ pluginPublicClientOptions: PublicClientOptions) -> Self {
        castPluginPublicMarkerProtocolValue(pluginPublicClientOptions, to: Self.self)
    }
}

internal extension ARTErrorInfo {
    /// Downcasts this `ARTErrorInfo` to its `_AblyPluginSupportPrivate` marker protocol type `PublicErrorInfo`.
    ///
    /// - Note: Swift compiler restrictions prevent us from declaring `ARTErrorInfo` as conforming to `PublicErrorInfo` (this is due to our use of `internal import`).
    var asPluginPublicErrorInfo: _AblyPluginSupportPrivate.PublicErrorInfo {
        // In order for this cast to succeed, we rely on the fact that ably-cocoa internally declares ARTErrorInfo as conforming to PublicErrorInfo.
        // swiftlint:disable:next force_cast
        self as! _AblyPluginSupportPrivate.PublicErrorInfo
    }

    /// Upcasts an instance of `_AblyPluginSupportPrivate`'s `PublicErrorInfo`, which is the marker protocol that it uses to represent an `ARTErrorInfo`, to an `ARTErrorInfo`.
    static func castPluginPublicErrorInfo(_ pluginPublicErrorInfo: PublicErrorInfo) -> Self {
        castPluginPublicMarkerProtocolValue(pluginPublicErrorInfo, to: Self.self)
    }
}
