#import "ARTFallbackHosts.h"

#import "ARTDefault+Private.h"
#import "ARTClientOptions+Private.h"

@implementation ARTFallbackHosts

+ (nullable NSArray<NSString *> *)hostsFromOptions:(ARTClientOptions *)options {
    if (options.fallbackHosts) {
        return options.fallbackHosts;
    }

    if (options.hasEnvironmentDifferentThanProduction) {
        return [ARTDefault fallbackHostsWithEnvironment:options.environment];
    }
    if (options.hasCustomRestHost || options.hasCustomRealtimeHost || options.hasCustomPort || options.hasCustomTlsPort) {
        return nil;
    }
    return [ARTDefault fallbackHosts];
}

@end
