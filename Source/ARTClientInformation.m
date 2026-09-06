#import "ARTClientInformation.h"
#import "ARTClientInformation+Private.h"
#import "ARTDefault.h"
#import "ARTDefault+Private.h"
#import "ARTClientOptions.h"
#import <sys/utsname.h>

NSString *const ARTClientInformationAgentNotVersioned = @"ARTClientInformationAgentNotVersioned";
NSString *const ARTClientInformation_libraryVersion = @"2.0.0";
static NSString *const _libraryName = @"ably-cocoa";

// NSOperatingSystemVersion has NSInteger as version components for some reason, so mitigate it here.
static inline UInt32 conformVersionComponent(const NSInteger component) {
    return (component < 0) ? 0 : (UInt32)component;
}

@implementation ARTClientInformation

+ (NSDictionary<NSString *, NSString *> *)agents {
    NSMutableDictionary<NSString *, NSString *> *const result = [NSMutableDictionary dictionary];

    [result addEntriesFromDictionary:[self platformAgent]];
    [result addEntriesFromDictionary:[self libraryAgent]];

    return result;
}

+ (NSString *)agentIdentifierWithAdditionalAgents:(nullable NSDictionary<NSString *, NSString *> *const)additionalAgents {
    NSMutableDictionary<NSString *, NSString *> *const agents = [self.agents mutableCopy];

    for (NSString *const additionalAgentName in additionalAgents) {
        agents[additionalAgentName] = additionalAgents[additionalAgentName];
    }

    return [self agentIdentifierForAgents:agents];
}

+ (NSString *)agentIdentifierForAgents:(NSDictionary<NSString *, NSString*> *)agents {
    NSMutableArray<NSString *> *const components = [NSMutableArray array];

    // We sort the agent names so that we have a predictable order when testing.
    NSArray<NSString *> *sortedAgentNames = [agents.allKeys sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *name in sortedAgentNames) {
        NSString *const version = agents[name];
        if (version == ARTClientInformationAgentNotVersioned) {
            [components addObject:name];
        } else {
            [components addObject:[NSString stringWithFormat:@"%@/%@", name, version]];
        }
    }

    return [components componentsJoinedByString:@" "];
}

+ (NSDictionary<NSString *, NSString *> *)libraryAgent {
    return @{ _libraryName: ARTClientInformation_libraryVersion };
}

+ (NSString *)libraryAgentIdentifier {
    return [self agentIdentifierForAgents:[self libraryAgent]];
}

+ (NSDictionary<NSString *, NSString *> *)platformAgent {
    NSString *const osName = [self osName];

    if (osName == nil) {
        return @{};
    }

    return @{ osName: [self osVersionString] };
}

+ (NSString *)platformAgentIdentifier {
    return [self agentIdentifierForAgents:[self platformAgent]];
}

+ (NSString *)osName {
    return
        #if TARGET_OS_IOS
            @"iOS"
        #elif TARGET_OS_TV
            @"tvOS"
        #elif TARGET_OS_WATCH
            @"watchOS"
        #elif TARGET_OS_OSX
            @"macOS"
        #else
            nil
        #endif
        ;
}

+ (NSString *)osVersionString {
    static NSString *versionString;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSOperatingSystemVersion version = [[NSProcessInfo processInfo] operatingSystemVersion];
        versionString = [NSString stringWithFormat:@"%lu.%lu.%lu",
             (unsigned long)conformVersionComponent(version.majorVersion),
             (unsigned long)conformVersionComponent(version.minorVersion),
             (unsigned long)conformVersionComponent(version.patchVersion)];
    });
    return versionString;
}

+ (NSString *)deviceModel {
    struct utsname systemInfo;
    if (uname(&systemInfo) < 0) {
        return nil;
    }
    return [NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding];
}

@end
