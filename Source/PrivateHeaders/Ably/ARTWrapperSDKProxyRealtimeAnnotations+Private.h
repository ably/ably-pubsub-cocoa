#import <AblyPubSubDevice/ARTWrapperSDKProxyRealtimeAnnotations.h>

@class ARTWrapperSDKProxyOptions;

NS_ASSUME_NONNULL_BEGIN

@interface ARTWrapperSDKProxyRealtimeAnnotations ()

- (instancetype)initWithRealtimeAnnotations:(ARTRealtimeAnnotations *)realtimeAnnotations
                            proxyOptions:(ARTWrapperSDKProxyOptions *)proxyOptions NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
