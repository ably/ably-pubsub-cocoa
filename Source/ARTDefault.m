#import "AblyPubSubDevice.h"
#import "ARTDefault+Private.h"
#import "ARTNSArray+ARTFunctional.h"
#import "ARTClientInformation+Private.h"

static NSString *const ARTDefault_apiVersion = @"6"; // CSV2

NSString *const ARTDefaultProduction = @"production";

static NSString *const ARTDefault_restHost = @"rest.ably.io";
static NSString *const ARTDefault_realtimeHost = @"realtime.ably.io";

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

+ (NSArray*)fallbackHostsWithEnvironment:(NSString *)environment {
    NSArray<NSString *> * fallbacks = @[@"a", @"b", @"c", @"d", @"e"];
    NSString *prefix = @"";
    NSString *suffix = @"";
    if (environment && ![environment isEqualToString:@""] && ![environment isEqualToString:ARTDefaultProduction]) {
        prefix = [NSString stringWithFormat:@"%@-", environment];
        suffix = @"-fallback";
    }

    return [fallbacks artMap:^NSString *(NSString * fallback) {
        return [NSString stringWithFormat:@"%@%@%@.ably-realtime.com", prefix, fallback, suffix];
    }];
}

+ (NSArray*)fallbackHosts {
    return [self fallbackHostsWithEnvironment:nil];
}

+ (NSString*)restHost {
    return ARTDefault_restHost;
}

+ (NSString*)realtimeHost {
    return ARTDefault_realtimeHost;
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
