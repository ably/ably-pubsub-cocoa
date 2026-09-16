#import <Foundation/Foundation.h>
#import <AblyPubSubDevice/ARTRealtimeChannels.h>

@class ARTWrapperSDKProxyRealtimeChannel;

NS_ASSUME_NONNULL_BEGIN

/**
 * An object which wraps an instance of `ARTRealtimeChannels` and provides a similar API. It allows Ably-authored wrapper SDKs to send analytics information so that Ably can track the usage of the wrapper SDK.
 *
 * - Important: This class should only be used by Ably-authored SDKs.
 */
NS_SWIFT_SENDABLE
NS_SWIFT_NAME(WrapperSDKProxyRealtimeChannels)
@interface ARTWrapperSDKProxyRealtimeChannels : NSObject <ARTRealtimeChannelsProtocol>

- (instancetype)init NS_UNAVAILABLE;

- (ARTWrapperSDKProxyRealtimeChannel *)get:(NSString *)name;
- (ARTWrapperSDKProxyRealtimeChannel *)get:(NSString *)name options:(ARTRealtimeChannelOptions *)options;

@end

NS_ASSUME_NONNULL_END
