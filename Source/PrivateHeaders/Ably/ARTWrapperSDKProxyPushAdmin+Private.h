#import <AblyPubSubDevice/ARTWrapperSDKProxyPushAdmin.h>

@class ARTWrapperSDKProxyOptions;

NS_ASSUME_NONNULL_BEGIN

@interface ARTWrapperSDKProxyPushAdmin ()

- (instancetype)initWithPushAdmin:(ARTPushAdmin *)pushAdmin
                     proxyOptions:(ARTWrapperSDKProxyOptions *)proxyOptions NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
