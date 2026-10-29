internal import _AblyPluginSupportPrivate
import AblyPubSubDevice

/// Upcasts an instance of an `_AblyPluginSupportPrivate` marker protocol to the concrete type that this marker protocol represents.
internal func castPluginPublicMarkerProtocolValue<T>(_ pluginMarkerProtocolValue: Any, to _: T.Type) -> T {
    guard let actualPublicValue = pluginMarkerProtocolValue as? T else {
        preconditionFailure("Expected \(T.self), got \(type(of: pluginMarkerProtocolValue))")
    }

    return actualPublicValue
}

internal extension AblyPubSubDevice.RealtimeChannel {
    /// Downcasts this `RealtimeChannel` to its `_AblyPluginSupportPrivate` equivalent type `PublicRealtimeChannel`.
    ///
    /// - Note: Swift compiler restrictions prevent us from declaring `RealtimeChannel` as conforming to `PublicRealtimeChannel` (this is due to our use of `internal import`).
    var asPluginPublicRealtimeChannel: _AblyPluginSupportPrivate.PublicRealtimeChannel {
        // In order for this cast to succeed, we rely on the fact that ably-cocoa internally declares RealtimeChannel as conforming to PublicRealtimeChannel.
        // swiftlint:disable:next force_cast
        self as! _AblyPluginSupportPrivate.PublicRealtimeChannel
    }
}

internal extension ClientOptions {
    /// Downcasts this `ClientOptions` to its `_AblyPluginSupportPrivate` marker protocol type `PublicClientOptions`.
    ///
    /// - Note: Swift compiler restrictions prevent us from declaring `ClientOptions` as conforming to `PublicClientOptions` (this is due to our use of `internal import`).
    var asPluginPublicClientOptions: _AblyPluginSupportPrivate.PublicClientOptions {
        // In order for this cast to succeed, we rely on the fact that ably-cocoa internally declares ClientOptions as conforming to PublicClientOptions.
        // swiftlint:disable:next force_cast
        self as! _AblyPluginSupportPrivate.PublicClientOptions
    }

    /// Upcasts an instance of `_AblyPluginSupportPrivate`'s `PublicClientOptions`, which is the marker protocol that it uses to represent a `ClientOptions`, to a `ClientOptions`.
    static func castPluginPublicClientOptions(_ pluginPublicClientOptions: PublicClientOptions) -> Self {
        castPluginPublicMarkerProtocolValue(pluginPublicClientOptions, to: Self.self)
    }
}

internal extension ErrorInfo {
    /// Downcasts this `ErrorInfo` to its `_AblyPluginSupportPrivate` marker protocol type `PublicErrorInfo`.
    ///
    /// - Note: Swift compiler restrictions prevent us from declaring `ErrorInfo` as conforming to `PublicErrorInfo` (this is due to our use of `internal import`).
    var asPluginPublicErrorInfo: _AblyPluginSupportPrivate.PublicErrorInfo {
        // In order for this cast to succeed, we rely on the fact that ably-cocoa internally declares ErrorInfo as conforming to PublicErrorInfo.
        // swiftlint:disable:next force_cast
        self as! _AblyPluginSupportPrivate.PublicErrorInfo
    }

    /// Upcasts an instance of `_AblyPluginSupportPrivate`'s `PublicErrorInfo`, which is the marker protocol that it uses to represent an `ErrorInfo`, to an `ErrorInfo`.
    static func castPluginPublicErrorInfo(_ pluginPublicErrorInfo: PublicErrorInfo) -> Self {
        castPluginPublicMarkerProtocolValue(pluginPublicErrorInfo, to: Self.self)
    }
}
