#import "ARTWrapperSDKProxyPushChannel+Private.h"
#import "ARTPushChannel+Private.h"
#import "ARTWrapperSDKProxyOptions.h"

NS_ASSUME_NONNULL_BEGIN

@interface ARTWrapperSDKProxyPushChannel ()

@property (nonatomic, readonly) ARTPushChannel *underlyingPushChannel;
@property (nonatomic, readonly) ARTWrapperSDKProxyOptions *proxyOptions;

@end

NS_ASSUME_NONNULL_END

@implementation ARTWrapperSDKProxyPushChannel

- (instancetype)initWithPushChannel:(ARTPushChannel *)pushChannel proxyOptions:(ARTWrapperSDKProxyOptions *)proxyOptions {
    if (self = [super init]) {
        _underlyingPushChannel = pushChannel;
        _proxyOptions = proxyOptions;
    }

    return self;
}

- (void)listSubscriptions:(nonnull NSStringDictionary *)params callback:(nonnull ARTPaginatedPushChannelCallback)callback {
    [self.underlyingPushChannel listSubscriptions:params callback:callback];
}

- (void)subscribeClient {
    [self.underlyingPushChannel.internal subscribeClientWithWrapperSDKAgents:self.proxyOptions.agents];
}

- (void)subscribeClient:(nullable ARTCallback)callback {
    [self.underlyingPushChannel.internal subscribeClientWithWrapperSDKAgents:self.proxyOptions.agents
                                                                  completion:callback];
}

- (void)subscribeDevice {
    [self.underlyingPushChannel.internal subscribeDeviceWithWrapperSDKAgents:self.proxyOptions.agents];
}

- (void)subscribeDevice:(nullable ARTCallback)callback {
    [self.underlyingPushChannel.internal subscribeDeviceWithWrapperSDKAgents:self.proxyOptions.agents
                                                                  completion:callback];
}

- (void)unsubscribeClient {
    [self.underlyingPushChannel.internal unsubscribeClientWithWrapperSDKAgents:self.proxyOptions.agents];
}

- (void)unsubscribeClient:(nullable ARTCallback)callback {
    [self.underlyingPushChannel.internal unsubscribeClientWithWrapperSDKAgents:self.proxyOptions.agents
                                                                    completion:callback];
}

- (void)unsubscribeDevice {
    [self.underlyingPushChannel.internal unsubscribeDeviceWithWrapperSDKAgents:self.proxyOptions.agents];
}

- (void)unsubscribeDevice:(nullable ARTCallback)callback {
    [self.underlyingPushChannel.internal unsubscribeDeviceWithWrapperSDKAgents:self.proxyOptions.agents
                                                                    completion:callback];
}

@end
