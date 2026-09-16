#import <Foundation/Foundation.h>
#import <AblyPubSubDevice/ARTRealtimeClient.h>

@class ARTConnection;
@class ARTWrapperSDKProxyRealtimeChannels;
@class ARTWrapperSDKProxyPush;
@class ARTAuth;

NS_ASSUME_NONNULL_BEGIN

/**
 * An object which wraps an instance of `ARTRealtimeClient` and provides a similar API. It allows Ably-authored wrapper SDKs to send analytics information so that Ably can track the usage of the wrapper SDK.
 *
 * - Important: This class should only be used by Ably-authored SDKs.
 */
NS_SWIFT_SENDABLE
NS_SWIFT_NAME(WrapperSDKProxyRealtime)
@interface ARTWrapperSDKProxyRealtime : NSObject <ARTRealtimeInstanceMethodsProtocol>

- (instancetype)init NS_UNAVAILABLE;

@property (readonly) ARTConnection *connection;
@property (readonly) ARTWrapperSDKProxyRealtimeChannels *channels;
@property (readonly) ARTWrapperSDKProxyPush *push;
@property (readonly) ARTAuth *auth;

@end

NS_ASSUME_NONNULL_END
