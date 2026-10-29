#import <AblyPubSubDevice/ARTWrapperSDKProxyRealtimeChannels.h>

@class ARTWrapperSDKProxyOptions;

NS_ASSUME_NONNULL_BEGIN

@interface ARTWrapperSDKProxyRealtimeChannels ()

- (instancetype)initWithChannels:(ARTRealtimeChannels *)channels
                    proxyOptions:(ARTWrapperSDKProxyOptions *)proxyOptions NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
