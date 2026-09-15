#import <AblyPubSubDevice/ARTWrapperSDKProxyPush.h>

@class ARTWrapperSDKProxyOptions;

NS_ASSUME_NONNULL_BEGIN

@interface ARTWrapperSDKProxyPush ()

- (instancetype)initWithPush:(ARTPush *)push
                proxyOptions:(ARTWrapperSDKProxyOptions *)proxyOptions NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
