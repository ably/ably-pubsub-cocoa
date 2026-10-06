#import "AblyPubSubDevice.h"
#import "ARTDefault+Private.h"
#import "ARTNSArray+ARTFunctional.h"
#import "ARTClientInformation+Private.h"

static NSString *const ARTDefault_apiVersion = @"6"; // CSV2

static NSString *const ARTDefault_endpoint = @"main";

static NSTimeInterval _connectionStateTtl = 60.0;
static NSInteger _maxProductionMessageSize = 65536;
static NSInteger _maxSandboxMessageSize = 16384;

@implementation ARTDefault

+ (NSString *)apiVersion {
    return ARTDefault_apiVersion;
}

+ (NSString *)libraryVersion {
    return ARTClientInformation_libraryVersion;
}

+ (NSString *)endpoint {
    return ARTDefault_endpoint;
}

+ (NSURL *)connectivityCheckUrl {
    return [NSURL URLWithString:@"https://internet-up.ably-realtime.com/is-the-internet-up.txt"];
}

+ (NSArray<NSString *> *)fallbackHostsForRoutingPolicyId:(NSString *)routingPolicyId domain:(NSString *)domain {
    return [@[@"a", @"b", @"c", @"d", @"e"] artMap:^NSString *(NSString *letter) {
        return [NSString stringWithFormat:@"%@.%@.fallback.%@", routingPolicyId, letter, domain];
    }];
}

// REC2c1
+ (NSArray<NSString *> *)fallbackHosts {
    return [self fallbackHostsForRoutingPolicyId:ARTDefault_endpoint domain:@"ably-realtime.com"];
}

+ (int)port {
    return 80;
}

+ (int)tlsPort {
    return 443;
}

+ (NSTimeInterval)ttl {
    return 60 * 60;
}

+ (NSTimeInterval)connectionStateTtl {
    return _connectionStateTtl;
}

+ (NSTimeInterval)realtimeRequestTimeout {
    return 10.0;
}

+ (NSInteger)maxMessageSize {
#if DEBUG
    return _maxSandboxMessageSize;
#else
    return _maxProductionMessageSize;
#endif
}

+ (NSInteger)maxSandboxMessageSize {
    return _maxSandboxMessageSize;
}

+ (NSInteger)maxProductionMessageSize {
    return _maxProductionMessageSize;
}

+ (void)setConnectionStateTtl:(NSTimeInterval)value {
    @synchronized (self) {
        _connectionStateTtl = value;
    }
}

+ (void)setMaxMessageSize:(NSInteger)value {
    @synchronized (self) {
#if DEBUG
        _maxSandboxMessageSize = value;
#else
        _maxProductionMessageSize = value;
#endif
    }
}

+ (void)setMaxProductionMessageSize:(NSInteger)value {
    @synchronized (self) {
        _maxProductionMessageSize = value;
    }
}

+ (void)setMaxSandboxMessageSize:(NSInteger)value {
    @synchronized (self) {
        _maxSandboxMessageSize = value;
    }
}

+ (NSString *)libraryAgent {
    return [ARTClientInformation libraryAgentIdentifier];
}

+ (NSString *)platformAgent {
    return [ARTClientInformation platformAgentIdentifier];
}

@end
