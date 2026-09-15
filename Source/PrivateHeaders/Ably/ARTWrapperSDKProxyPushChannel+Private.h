#import <AblyPubSubDevice/ARTWrapperSDKProxyPushChannel.h>

@class ARTWrapperSDKProxyOptions;

NS_ASSUME_NONNULL_BEGIN

@interface ARTWrapperSDKProxyPushChannel ()

- (instancetype)initWithPushChannel:(ARTPushChannel *)pushChannel
                       proxyOptions:(ARTWrapperSDKProxyOptions *)proxyOptions NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
