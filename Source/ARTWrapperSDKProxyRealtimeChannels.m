#import "ARTWrapperSDKProxyRealtimeChannels+Private.h"
#import "ARTWrapperSDKProxyRealtimeChannel+Private.h"
#import "ARTRealtimeChannelOptions.h"
#import "ARTWrapperSDKProxyOptions.h"
#import "ARTClientInformation+Private.h"

NS_ASSUME_NONNULL_BEGIN

@interface ARTWrapperSDKProxyRealtimeChannels ()

@property (nonatomic, readonly) ARTRealtimeChannels *underlyingChannels;
@property (nonatomic, readonly) ARTWrapperSDKProxyOptions *proxyOptions;

@end

NS_ASSUME_NONNULL_END

@implementation ARTWrapperSDKProxyRealtimeChannels

- (instancetype)initWithChannels:(ARTRealtimeChannels *)channels proxyOptions:(ARTWrapperSDKProxyOptions *)proxyOptions {
    if (self = [super init]) {
        _underlyingChannels = channels;
        _proxyOptions = proxyOptions;
    }

    return self;
}

- (BOOL)exists:(nonnull NSString *)name {
    return [self.underlyingChannels exists:name];
}

- (BOOL)release:(nonnull NSString *)name error:(NSError *_Nullable *_Nullable)error {
    return [self.underlyingChannels release:name error:error];
}

- (ARTWrapperSDKProxyRealtimeChannel *)get:(NSString *)name maybeOptions:(nullable ARTRealtimeChannelOptions *)options {
    ARTRealtimeChannelOptions *resolvedOptions = [self addingAgentToOptions:options];
    ARTRealtimeChannel *channel;
    if (resolvedOptions) {
        channel = [self.underlyingChannels get:name options:resolvedOptions];
    } else {
        channel = [self.underlyingChannels get:name];
    }

    ARTWrapperSDKProxyRealtimeChannel *proxy = [[ARTWrapperSDKProxyRealtimeChannel alloc] initWithChannel:channel
                                                                                             proxyOptions:self.proxyOptions];

    return proxy;
}

- (nullable ARTRealtimeChannelOptions *)addingAgentToOptions:(nullable ARTRealtimeChannelOptions *)options {
    if (!self.proxyOptions.agents) {
        return options;
    }

    NSMutableDictionary<NSString *, NSString *> *resolvedParams = options.params ? [options.params mutableCopy] : [NSMutableDictionary dictionary];
    resolvedParams[@"agent"] = [ARTClientInformation agentIdentifierForAgents:self.proxyOptions.agents];

    ARTRealtimeChannelOptions *resolvedOptions = options ? [options copy] : [[ARTRealtimeChannelOptions alloc] init];
    resolvedOptions.params = resolvedParams;

    return resolvedOptions;
}

- (ARTWrapperSDKProxyRealtimeChannel *)get:(NSString *)name {
    return [self get:name maybeOptions:nil];
}

- (ARTWrapperSDKProxyRealtimeChannel *)get:(NSString *)name options:(ARTRealtimeChannelOptions *)options {
    return [self get:name maybeOptions:options];
}

@end

