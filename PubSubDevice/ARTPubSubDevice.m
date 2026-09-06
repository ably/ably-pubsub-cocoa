#import <AblyPubSubDevice/ARTPubSubDevice.h>

/**
 * The agent entry that declares a client is running on an end user's device.
 *
 * Ably matches this exact string to classify a connection for monthly active user counting, so
 * changing it reclassifies every client this package creates. It is sent without a version: it
 * states which kind of runtime the client is on, and the SDK's own entry alongside it carries the
 * version.
 */
static NSString *const ARTPubSubDeviceAgentName = @"ably-pubsub-device";

@implementation ARTPubSubDevice

/// Returns a copy of `options` carrying the device declaration.
///
/// The caller's options object and its `agents` dictionary are both left untouched. The
/// declaration is applied last, so it wins if the caller set an entry under the same name.
+ (ARTClientOptions *)optionsDeclaringDevice:(ARTClientOptions *)options {
    ARTClientOptions *const newOptions = [options copy];

    NSMutableDictionary<NSString *, NSString *> *const agents = options.agents ? [options.agents mutableCopy] : [NSMutableDictionary dictionary];
    agents[ARTPubSubDeviceAgentName] = ARTClientInformationAgentNotVersioned;
    newOptions.agents = agents;

    return newOptions;
}

+ (ARTRealtime *)createClientWithOptions:(ARTClientOptions *)options {
    return [[ARTRealtime alloc] initWithOptions:[self optionsDeclaringDevice:options]];
}

+ (ARTRealtime *)createClientWithKey:(NSString *)key {
    return [self createClientWithOptions:[[ARTClientOptions alloc] initWithKey:key]];
}

+ (ARTRealtime *)createClientWithToken:(NSString *)token {
    return [self createClientWithOptions:[[ARTClientOptions alloc] initWithToken:token]];
}

@end
