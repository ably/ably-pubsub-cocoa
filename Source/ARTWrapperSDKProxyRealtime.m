#import "ARTWrapperSDKProxyRealtime+Private.h"
#import "ARTWrapperSDKProxyRealtimeChannels+Private.h"
#import "ARTWrapperSDKProxyPush+Private.h"
#import "ARTWrapperSDKProxyOptions.h"
#import "ARTPubSubClient+Private.h"

NS_ASSUME_NONNULL_BEGIN

@interface ARTWrapperSDKProxyRealtime ()

@property (nonatomic, readonly) ARTPubSubClient *underlyingRealtime;
@property (nonatomic, readonly) ARTWrapperSDKProxyOptions *proxyOptions;

@end

NS_ASSUME_NONNULL_END

@implementation ARTWrapperSDKProxyRealtime

- (instancetype)initWithPubSub:(ARTPubSubClient *)pubsub
                  proxyOptions:(ARTWrapperSDKProxyOptions *)proxyOptions {
    if (self = [super init]) {
        _underlyingRealtime = pubsub;
        _proxyOptions = proxyOptions;
        _channels = [[ARTWrapperSDKProxyRealtimeChannels alloc] initWithChannels:pubsub.channels
                                                                    proxyOptions:proxyOptions];
        _push = [[ARTWrapperSDKProxyPush alloc] initWithPush:pubsub.push
                                                proxyOptions:proxyOptions];
    }

    return self;
}

- (ARTConnection *)connection {
    return self.underlyingRealtime.connection;
}

- (ARTAuth *)auth {
    return self.underlyingRealtime.auth;
}

- (NSString *)clientId {
    return self.underlyingRealtime.clientId;
}

#if TARGET_OS_IOS
- (ARTLocalDevice *)device {
    return self.underlyingRealtime.device;
}
#endif

- (void)close {
    [self.underlyingRealtime close];
}

- (void)connect {
    [self.underlyingRealtime connect];
}

- (void)ping:(nonnull ARTCallback)cb {
    [self.underlyingRealtime ping:cb];
}

- (void)request:(nonnull NSString *)method
           path:(nonnull NSString *)path
         params:(nullable NSStringDictionary *)params
           body:(nullable id)body
        headers:(nullable NSStringDictionary *)headers
       callback:(nonnull ARTHTTPPaginatedCallback)callback {
    [self.underlyingRealtime.internal request:method
                                         path:path
                                       params:params
                                         body:body
                                      headers:headers
                             wrapperSDKAgents:self.proxyOptions.agents
                                     callback:callback];
}

- (void)stats:(nonnull ARTPaginatedStatsCallback)callback {
    [self.underlyingRealtime.internal statsWithWrapperSDKAgents:self.proxyOptions.agents
                                                       callback:callback];
}

- (void)stats:(nullable ARTStatsQuery *)query callback:(nonnull ARTPaginatedStatsCallback)callback {
    [self.underlyingRealtime.internal stats:query
                           wrapperSDKAgents:self.proxyOptions.agents
                                   callback:callback];
}

- (void)time:(nonnull ARTDateTimeCallback)callback {
    [self.underlyingRealtime.internal timeWithWrapperSDKAgents:self.proxyOptions.agents
                                                    completion:callback];
}

@end
