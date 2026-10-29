#import <AblyPubSubDevice/ARTWrapperSDKProxyPushDeviceRegistrations.h>

@class ARTWrapperSDKProxyOptions;

NS_ASSUME_NONNULL_BEGIN

@interface ARTWrapperSDKProxyPushDeviceRegistrations ()

- (instancetype)initWithPushDeviceRegistrations:(ARTPushDeviceRegistrations *)pushDeviceRegistrations
                                   proxyOptions:(ARTWrapperSDKProxyOptions *)proxyOptions NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
