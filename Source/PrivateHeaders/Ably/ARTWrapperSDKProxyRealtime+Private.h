#import <AblyPubSubDevice/ARTWrapperSDKProxyRealtime.h>

@class ARTWrapperSDKProxyOptions;

NS_ASSUME_NONNULL_BEGIN

@interface ARTWrapperSDKProxyRealtime ()

- (instancetype)initWithPubSub:(ARTPubSubClient *)pubsub
                    proxyOptions:(ARTWrapperSDKProxyOptions *)proxyOptions NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
