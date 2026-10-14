#import "AblyPubSubDevice.h"
#import "ARTDefault+Private.h"
#import "ARTNSArray+ARTFunctional.h"
#import "ARTClientInformation+Private.h"

static NSString *const ARTDefault_apiVersion = @"6"; // CSV2

static NSString *const ARTDefault_endpoint = @"main";

static NSTimeInterval _connectionStateTtl = 60.0;

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

+ (void)setConnectionStateTtl:(NSTimeInterval)value {
    @synchronized (self) {
        _connectionStateTtl = value;
    }
}

+ (NSString *)libraryAgent {
    return [ARTClientInformation libraryAgentIdentifier];
}

+ (NSString *)platformAgent {
    return [ARTClientInformation platformAgentIdentifier];
}

@end
