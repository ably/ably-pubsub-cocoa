#import "ARTWrapperSDKProxyRealtime+Private.h"
#import "ARTWrapperSDKProxyRealtimeChannels+Private.h"
#import "ARTWrapperSDKProxyPush+Private.h"
#import "ARTWrapperSDKProxyOptions.h"
#import "ARTRealtimeClient+Private.h"

NS_ASSUME_NONNULL_BEGIN

@interface ARTWrapperSDKProxyRealtime ()

@property (nonatomic, readonly) ARTRealtimeClient *underlyingRealtime;
@property (nonatomic, readonly) ARTWrapperSDKProxyOptions *proxyOptions;

@end

NS_ASSUME_NONNULL_END

@implementation ARTWrapperSDKProxyRealtime

- (instancetype)initWithRealtime:(ARTRealtimeClient *)realtime
                    proxyOptions:(ARTWrapperSDKProxyOptions *)proxyOptions {
    if (self = [super init]) {
        _underlyingRealtime = realtime;
        _proxyOptions = proxyOptions;
        _channels = [[ARTWrapperSDKProxyRealtimeChannels alloc] initWithChannels:realtime.channels
                                                                    proxyOptions:proxyOptions];
        _push = [[ARTWrapperSDKProxyPush alloc] initWithPush:realtime.push
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

- (BOOL)request:(nonnull NSString *)method
           path:(nonnull NSString *)path
         params:(nullable NSStringDictionary *)params
           body:(nullable id)body
        headers:(nullable NSStringDictionary *)headers
       callback:(nonnull ARTHTTPPaginatedCallback)callback
          error:(NSError * _Nullable __autoreleasing * _Nullable)errorPtr {
    return [self.underlyingRealtime.internal request:method
                                                path:path
                                              params:params
                                                body:body
                                             headers:headers
                                    wrapperSDKAgents:self.proxyOptions.agents
                                            callback:callback
                                               error:errorPtr];
}

- (BOOL)stats:(nonnull ARTPaginatedStatsCallback)callback {
    return [self.underlyingRealtime.internal statsWithWrapperSDKAgents:self.proxyOptions.agents
                                                              callback:callback];
}

- (BOOL)stats:(nullable ARTStatsQuery *)query callback:(nonnull ARTPaginatedStatsCallback)callback error:(NSError * _Nullable __autoreleasing * _Nullable)errorPtr {
    return [self.underlyingRealtime.internal stats:query
                                  wrapperSDKAgents:self.proxyOptions.agents
                                          callback:callback
                                             error:errorPtr];
}

- (void)time:(nonnull ARTDateTimeCallback)callback {
    [self.underlyingRealtime.internal timeWithWrapperSDKAgents:self.proxyOptions.agents
                                                    completion:callback];
}

@end
