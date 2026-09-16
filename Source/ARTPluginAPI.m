#ifdef ABLY_SUPPORTS_PLUGINS

#import "ARTPluginAPI.h"
#import "ARTRealtimeChannel+Private.h"
#import "ARTChannel+Private.h"
#import "ARTInternalLog.h"
#import "ARTPublicRealtimeChannelUnderlyingObjects.h"
#import "ARTClientOptions+Private.h"
#import "ARTErrorInfo+Private.h"
#import "ARTConnectionDetails+Private.h"
#import "ARTPublishResult+Private.h"
#import "ARTPublishResultSerial+Private.h"
#import "ARTConnection+Private.h"
#import "ARTRealtimeChannelOptions.h"

static ARTErrorInfo *_ourPublicErrorInfo(id<APPublicErrorInfo> pluginPublicErrorInfo) {
    if (![pluginPublicErrorInfo isKindOfClass:[ARTErrorInfo class]]) {
        [NSException raise:NSInternalInconsistencyException format:@"Expected ARTErrorInfo, got %@", pluginPublicErrorInfo];
    }
    return (ARTErrorInfo *)pluginPublicErrorInfo;
}

static ARTClientOptions *_ourPublicClientOptions(id<APPublicClientOptions> pluginPublicClientOptions) {
    if (![pluginPublicClientOptions isKindOfClass:[ARTClientOptions class]]) {
        [NSException raise:NSInternalInconsistencyException format:@"Expected ARTClientOptions, got %@", pluginPublicClientOptions];
    }
    return (ARTClientOptions *)pluginPublicClientOptions;
}

static ARTRealtimeChannel *_ourPublicRealtimeChannel(id<APPublicRealtimeChannel> pluginPublicRealtimeChannel) {
    if (![pluginPublicRealtimeChannel isKindOfClass:[ARTRealtimeChannel class]]) {
        [NSException raise:NSInternalInconsistencyException format:@"Expected ARTRealtimeChannel, got %@", pluginPublicRealtimeChannel];
    }
    return (ARTRealtimeChannel *)pluginPublicRealtimeChannel;
}

static ARTRealtimeChannelInternal *_internalRealtimeChannel(id<APRealtimeChannel> pluginRealtimeChannel) {
    if (![pluginRealtimeChannel isKindOfClass:[ARTRealtimeChannelInternal class]]) {
        [NSException raise:NSInternalInconsistencyException format:@"Expected ARTRealtimeChannelInternal, got %@", pluginRealtimeChannel];
    }
    return (ARTRealtimeChannelInternal *)pluginRealtimeChannel;
}

static ARTRealtimeClientInternal *_internalRealtimeClient(id<APRealtimeClient> pluginRealtimeClient) {
    if (![pluginRealtimeClient isKindOfClass:[ARTRealtimeClientInternal class]]) {
        [NSException raise:NSInternalInconsistencyException format:@"Expected ARTRealtimeClientInternal, got %@", pluginRealtimeClient];
    }
    return (ARTRealtimeClientInternal *)pluginRealtimeClient;
}

static ARTInternalLog *_internalLogger(id<APLogger> pluginLogger) {
    if (![pluginLogger isKindOfClass:[ARTInternalLog class]]) {
        [NSException raise:NSInternalInconsistencyException format:@"Expected ARTInternalLog, got %@", pluginLogger];
    }
    return (ARTInternalLog *)pluginLogger;
}

APRealtimeChannelState ARTConvertToPluginChannelState(ARTRealtimeChannelState ourRealtimeChannelState) {
    switch (ourRealtimeChannelState) {
    case ARTRealtimeChannelInitialized:
        return APRealtimeChannelStateInitialized;
    case ARTRealtimeChannelAttaching:
        return APRealtimeChannelStateAttaching;
    case ARTRealtimeChannelAttached:
        return APRealtimeChannelStateAttached;
    case ARTRealtimeChannelDetaching:
        return APRealtimeChannelStateDetaching;
    case ARTRealtimeChannelDetached:
        return APRealtimeChannelStateDetached;
    case ARTRealtimeChannelSuspended:
        return APRealtimeChannelStateSuspended;
    case ARTRealtimeChannelFailed:
        return APRealtimeChannelStateFailed;
    }

    [NSException raise:NSInternalInconsistencyException format:@"ARTConvertToPluginChannelState failed to map %lu", ourRealtimeChannelState];
}

static ARTLogLevel _convertPluginLogLevel(APLogLevel pluginLogLevel) {
    switch (pluginLogLevel) {
        case APLogLevelVerbose:
            return ARTLogLevelVerbose;
        case APLogLevelDebug:
            return ARTLogLevelDebug;
        case APLogLevelInfo:
            return ARTLogLevelInfo;
        case APLogLevelWarn:
            return ARTLogLevelWarn;
        case APLogLevelError:
            return ARTLogLevelError;
        case APLogLevelNone:
            return ARTLogLevelNone;
    }

    [NSException raise:NSInternalInconsistencyException format:@"_convertPluginLogLevel failed to map %lu", pluginLogLevel];
}

@implementation ARTPluginAPI

- (BOOL)usesLiveObjectsProtocolV6 {
    return YES;
}

+ (void)registerSelf {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        ARTPluginAPI *instanceToRegister = [[ARTPluginAPI alloc] init];
        [[APDependencyStore sharedInstance] registerPluginAPI:instanceToRegister];
    });
}

- (id<APPublicRealtimeChannelUnderlyingObjects>)underlyingObjectsForPublicRealtimeChannel:(id<APPublicRealtimeChannel>)channel {
    ARTRealtimeChannel *ours = _ourPublicRealtimeChannel(channel);
    return [[APDefaultPublicRealtimeChannelUnderlyingObjects alloc] initWithClient:ours.realtimeInternal
                                                                           channel:ours.internal];

}

- (void)nosync_setPluginDataValue:(nonnull id)value
                           forKey:(nonnull NSString *)key
                          channel:(nonnull id<APRealtimeChannel>)channel {
    ARTRealtimeChannelInternal *internalChannel = _internalRealtimeChannel(channel);
    dispatch_assert_queue(internalChannel.queue);

    [internalChannel setPluginDataValue:value forKey:key];
}

- (nullable id)nosync_pluginDataValueForKey:(nonnull NSString *)key
                                    channel:(nonnull id<APRealtimeChannel>)channel {
    ARTRealtimeChannelInternal *internalChannel = _internalRealtimeChannel(channel);
    dispatch_assert_queue(internalChannel.queue);

    return [internalChannel pluginDataValueForKey:key];
}

- (id<APLogger>)loggerForChannel:(id<APRealtimeChannel>)channel {
    return _internalRealtimeChannel(channel).logger;
}

- (NSString *)nameForChannel:(id<APRealtimeChannel>)channel {
    // The name is immutable (set at channel creation), so no queue assertion is needed.
    return _internalRealtimeChannel(channel).name;
}

- (void)setPluginOptionsValue:(id)value forKey:(NSString *)key clientOptions:(id<APPublicClientOptions>)options {
    [_ourPublicClientOptions(options) setPluginOptionsValue:value forKey:key];
}

- (id)pluginOptionsValueForKey:(NSString *)key clientOptions:(id<APPublicClientOptions>)options {
    return [_ourPublicClientOptions(options) pluginOptionsValueForKey:key];
}

- (ARTClientOptions *)optionsForClient:(id<APRealtimeClient>)client {
    return [_internalRealtimeClient(client).options copy];
}

- (dispatch_queue_t)callbackQueueForClient:(id<APRealtimeClient>)client {
    return _internalRealtimeClient(client).options.dispatchQueue;
}

- (dispatch_queue_t)internalQueueForClient:(id<APRealtimeClient>)client {
    return _internalRealtimeClient(client).options.internalDispatchQueue;
}

- (void)nosync_sendObjectWithObjectMessages:(NSArray<id<APObjectMessageProtocol>> *)objectMessages
                                    channel:(id<APRealtimeChannel>)channel
                                 completion:(void (^)(id<APPublishResultProtocol> _Nullable publishResult, id<APPublicErrorInfo> _Nullable error))completion {
    ARTRealtimeChannelInternal *internalChannel = _internalRealtimeChannel(channel);
    dispatch_assert_queue(internalChannel.queue);

    [internalChannel sendObjectWithObjectMessages:objectMessages
                                       completion:^(ARTPublishResult *publishResult, ARTErrorInfo *error) {
        if (completion) {
            completion(publishResult, error);
        }
    }];
}

- (APRealtimeChannelState)nosync_stateForChannel:(id<APRealtimeChannel>)channel {
    ARTRealtimeChannelInternal *internalChannel = _internalRealtimeChannel(channel);
    dispatch_assert_queue(internalChannel.queue);

    return ARTConvertToPluginChannelState(internalChannel.state_nosync);
}

- (APChannelMode)nosync_objectChannelModesForChannel:(id<APRealtimeChannel>)channel {
    ARTRealtimeChannelInternal *internalChannel = _internalRealtimeChannel(channel);
    dispatch_assert_queue(internalChannel.queue);

    // RTO2a: use the attached modes if present (non-empty); RTO2b: otherwise fall back to the
    // user-provided channel-options modes.
    ARTChannelMode effectiveModes = internalChannel.modes_nosync;
    if (effectiveModes == 0) {
        ARTRealtimeChannelOptions *options = internalChannel.options_nosync;
        if (options) {
            effectiveModes = options.modes;
        }
    }

    // `ARTChannelMode` and `APChannelMode` are distinct option types: this both masks out the
    // non-object modes (this accessor exposes only the object modes to the plugin) and maps each
    // object bit to its `APChannelMode` counterpart, so the result does not depend on the two
    // types' raw bit values coinciding.
    APChannelMode result = 0;
    if (effectiveModes & ARTChannelModeObjectSubscribe) {
        result |= APChannelModeObjectSubscribe;
    }
    if (effectiveModes & ARTChannelModeObjectPublish) {
        result |= APChannelModeObjectPublish;
    }
    return result;
}

- (id<APPublicErrorInfo>)nosync_connectionStateErrorForClient:(id<APRealtimeClient>)client {
    ARTRealtimeClientInternal *internalRealtimeClient = _internalRealtimeClient(client);
    dispatch_assert_queue(internalRealtimeClient.queue);

    // Object publishing must meet the same connection-state preconditions as message publishing
    // (RTO15b -> RTL6c): if the connection is not active, publishing cannot proceed (RTL6c4), so
    // report the connection's error to the caller.
    ARTConnectionInternal *connection = internalRealtimeClient.connection;
    if ([connection isActive_nosync]) {
        return nil;
    }

    ARTErrorInfo *errorReason = [connection errorReason_nosync];
    if (errorReason) {
        return errorReason;
    }
    // RTL6c4: the operation must result in an error even when the inactive connection carries no
    // error reason (e.g. a cleanly closed connection), so fall back to the same error this SDK's
    // attach/detach use for an inactive connection.
    return [ARTErrorInfo createWithCode:ARTErrorChannelOperationFailed
                                message:@"Can't publish when not in an active state"];
}

- (void)nosync_attachChannel:(id<APRealtimeChannel>)channel
                  completion:(void (^)(id<APPublicErrorInfo> _Nullable error))completion {
    ARTRealtimeChannelInternal *internalChannel = _internalRealtimeChannel(channel);
    dispatch_assert_queue(internalChannel.queue);

    // `-_attach:` is the internal (already-on-queue) form of the public `-[ARTRealtimeChannel attach:]`;
    // it invokes its callback on the channel's internal queue when the attach resolves.
    [internalChannel _attach:^(ARTErrorInfo *_Nullable error) {
        if (completion) {
            completion(error);
        }
    }];
}

- (void)nosync_fetchServerTimeForClient:(id<APRealtimeClient>)client
                             completion:(void (^)(NSDate * _Nullable, id<APPublicErrorInfo> _Nullable))completion {
    ARTRealtimeClientInternal *internalRealtimeClient = _internalRealtimeClient(client);
    dispatch_assert_queue(internalRealtimeClient.queue);

    [internalRealtimeClient.auth fetchServerTimeWithCompletion:completion];
}

- (id<APConnectionDetailsProtocol>)nosync_latestConnectionDetailsForClient:(id<APRealtimeClient>)client {
    ARTRealtimeClientInternal *internalRealtimeClient = _internalRealtimeClient(client);
    dispatch_assert_queue(internalRealtimeClient.queue);

    return internalRealtimeClient.latestConnectionDetails;
}

- (void)log:(NSString *)message
        withLevel:(APLogLevel)level
        file:(const char *)fileName
        line:(NSInteger)line
        logger:(id<APLogger>)logger {
    [_internalLogger(logger) log:message
                             withLevel:_convertPluginLogLevel(level)
                             file:fileName
                             line:line];
}

@end

#endif
