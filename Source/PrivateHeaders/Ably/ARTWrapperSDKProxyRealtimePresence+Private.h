#import <AblyPubSubDevice/ARTWrapperSDKProxyRealtimePresence.h>

@class ARTWrapperSDKProxyOptions;

NS_ASSUME_NONNULL_BEGIN

@interface ARTWrapperSDKProxyRealtimePresence ()

- (instancetype)initWithRealtimePresence:(ARTRealtimePresence *)realtimePresence
                            proxyOptions:(ARTWrapperSDKProxyOptions *)proxyOptions NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
