#import "ARTFallbackHosts.h"

#import "ARTDefault+Private.h"
#import "ARTClientOptions+Private.h"

@implementation ARTFallbackHosts

+ (nullable NSArray<NSString *> *)hostsFromOptions:(ARTClientOptions *)options {
    if (options.fallbackHosts) { // REC2a2
        return options.fallbackHosts;
    }
    // A custom port means a development server, which has no fallback hosts on that port.
    if (options.hasCustomPort || options.hasCustomTlsPort) {
        return @[];
    }
    return options.endpointFallbackHosts; // REC2c
}

@end
