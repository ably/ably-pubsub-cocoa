#import <AblyPubSubDevice/ARTWrapperSDKProxyRealtimeChannel.h>

@class ARTWrapperSDKProxyOptions;

NS_ASSUME_NONNULL_BEGIN

@interface ARTWrapperSDKProxyRealtimeChannel ()

- (instancetype)initWithChannel:(ARTRealtimeChannel *)channel
                   proxyOptions:(ARTWrapperSDKProxyOptions *)proxyOptions NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
