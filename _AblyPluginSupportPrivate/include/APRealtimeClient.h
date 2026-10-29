@import Foundation;

NS_ASSUME_NONNULL_BEGIN

/// The interface that plugins use to interact with a realtime client.
///
/// This exists so that plugins do not need to make use of the public `ARTPubSubClient` class, which allows the internal components of ably-cocoa to continue the (existing before we introduced plugins) pattern of also not making use of this public class.
///
/// Note that `_AblyPluginSupportPrivate` does not allow you to pass it arbitrary objects that conform to this protocol; rather you must pass it an object which it previously passed to the plugin (e.g. via TODO we don't have an example yet; will come later).
NS_SWIFT_NAME(RealtimeClient)
NS_SWIFT_SENDABLE
@protocol APRealtimeClient <NSObject>
@end

NS_ASSUME_NONNULL_END
