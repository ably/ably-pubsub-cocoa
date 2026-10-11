#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Represents default library settings.
 */
NS_SWIFT_NAME(Default)
@interface ARTDefault : NSObject

+ (NSString *)apiVersion;
+ (NSString *)libraryVersion;

+ (NSArray<NSString *> *)fallbackHosts;
+ (int)port;
+ (int)tlsPort;

/**
 Default in seconds of requested time to live for the token.
 */
+ (NSTimeInterval)ttl;

/**
 When the client is in the `ARTRealtimeConnectionState.ARTRealtimeDisconnected` state, once this TTL has passed, the client should change the state to the `ARTRealtimeConnectionState.ARTRealtimeSuspended` state signifying that the state is now lost i.e. channels need to be reattached manually.

 Note that this default is override by any `ARTConnectionDetails.connectionStateTtl` of the `ARTProtocolMessageConnected` of the `ARTProtocolMessage`.
 */
+ (NSTimeInterval)connectionStateTtl;

/// :nodoc: TODO: docstring
+ (NSString *)libraryAgent;

/// :nodoc: TODO: docstring
+ (NSString *)platformAgent;

@end

NS_ASSUME_NONNULL_END
