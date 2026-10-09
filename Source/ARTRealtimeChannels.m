#import <Foundation/Foundation.h>
#import "ARTRealtimeChannels+Private.h"
#import "ARTChannels+Private.h"
#import "ARTRealtimeChannel+Private.h"
#import "ARTPubSubClient+Private.h"
#import "ARTClientOptions+Private.h"
#import "ARTRealtimePresence+Private.h"
#import "ARTClientOptions+TestConfiguration.h"
#import "ARTTestClientOptions.h"
#import "ARTGCD.h"

@implementation ARTRealtimeChannels {
    ARTQueuedDealloc *_dealloc;
}

- (instancetype)initWithInternal:(ARTRealtimeChannelsInternal *)internal pubsubInternal:(ARTPubSubClientInternal *)pubsubInternal queuedDealloc:(ARTQueuedDealloc *)dealloc {
    self = [super init];
    if (self) {
        _internal = internal;
        _realtimeInternal = pubsubInternal;
        _dealloc = dealloc;
    }
    return self;
}

- (BOOL)exists:(NSString *)name {
    return [_internal exists:(NSString *)name];
}

- (ARTRealtimeChannel *)get:(NSString *)name {
    return [[ARTRealtimeChannel alloc] initWithInternal:[_internal get:(NSString *)name] pubsubInternal:_realtimeInternal queuedDealloc:_dealloc];
}

- (ARTRealtimeChannel *)get:(NSString *)name options:(ARTRealtimeChannelOptions *)options {
    return [[ARTRealtimeChannel alloc] initWithInternal:[_internal get:(NSString *)name options:options] pubsubInternal:_realtimeInternal queuedDealloc:_dealloc];
}

- (BOOL)release:(NSString *)name error:(NSError *_Nullable *_Nullable)error {
    return [_internal release:name error:error];
}

- (id<NSFastEnumeration>)iterate {
    return [_internal copyIntoIteratorWithMapper:^ARTRealtimeChannel *(ARTRealtimeChannelInternal *internalChannel) {
        return [[ARTRealtimeChannel alloc] initWithInternal:internalChannel pubsubInternal:self->_realtimeInternal queuedDealloc:self->_dealloc];
    }];
}

@end

@interface ARTRealtimeChannelsInternal ()

@property (nonatomic, readonly) ARTInternalLog *logger;
@property (weak, nonatomic) ARTPubSubClientInternal *realtime; // weak because realtime owns self

@end

@interface ARTRealtimeChannelsInternal () <ARTChannelsDelegate>
@end

@implementation ARTRealtimeChannelsInternal {
    ARTChannels *_channels;
}

- (instancetype)initWithPubSub:(ARTPubSubClientInternal *)pubsub logger:(ARTInternalLog *)logger {
    if (self = [super init]) {
        _realtime = pubsub;
        _queue = _realtime.rest.queue;
        _logger = logger;
        _channels = [[ARTChannels alloc] initWithDelegate:self dispatchQueue:_queue prefix:_realtime.options.testOptions.channelNamePrefix];
    }
    return self;
}

- (id)makeChannel:(NSString *)name options:(ARTRealtimeChannelOptions *)options {
    return [[ARTRealtimeChannelInternal alloc] initWithPubSub:_realtime andName:name withOptions:options logger:_logger];
}

- (id<NSFastEnumeration>)copyIntoIteratorWithMapper:(ARTRealtimeChannel *(^)(ARTRealtimeChannelInternal *))mapper {
    return [_channels copyIntoIteratorWithMapper:mapper];
}

- (ARTRealtimeChannelInternal *)get:(NSString *)name {
    return [_channels get:name];
}

- (ARTRealtimeChannelInternal *)get:(NSString *)name options:(ARTChannelOptions *)options {
    return [_channels get:name options:options];
}

- (BOOL)exists:(NSString *)name {
    return [_channels exists:name];
}

- (BOOL)release:(NSString *)name error:(NSError *_Nullable *_Nullable)errorPtr {
    name = [_channels addPrefix:name];

    __block ARTErrorInfo *error = nil;
art_dispatch_sync(_queue, ^{
    error = [self _release:name];
});

    if (error) {
        if (errorPtr) {
            *errorPtr = error;
        }
        return NO;
    }
    return YES;
}

- (nullable ARTErrorInfo *)_release:(NSString *)name {
    // RTS4c
    if (![_channels _exists:name]) {
        return nil;
    }

    ARTRealtimeChannelInternal *const channel = [_channels _get:name];
    const ARTRealtimeChannelState state = channel.state_nosync;
    // RTS4e
    if (state != ARTRealtimeChannelInitialized && state != ARTRealtimeChannelDetached && state != ARTRealtimeChannelFailed) {
        return [ARTErrorInfo createWithCode:ARTErrorChannelReleaseInvalidState
                                     status:400
                                    message:[NSString stringWithFormat:@"Can only release a channel in a state where there is no possibility of further updates from the server being received (initialized, detached, or failed). The current state is %@", [ARTRealtimeChannelStateToStr(state) lowercaseString]]];
    }

    // RTS4d
    [channel off_nosync];
    [channel _unsubscribe];
    [channel.presence _unsubscribe];
#ifdef ABLY_SUPPORTS_PLUGINS
    // See `-nosync_onChannelRelease:` for what the plugin does with this.
    [self.realtime.options.liveObjectsPlugin nosync_onChannelRelease:channel];
#endif
    [_channels _release:name];
    return nil;
}

- (NSMutableDictionary *)getCollection {
    return _channels.channels;
}

- (id<NSFastEnumeration>)getNosyncIterable {
    return [_channels getNosyncIterable];
}

- (ARTRealtimeChannelInternal *)_getChannel:(NSString *)name options:(ARTChannelOptions *)options addPrefix:(BOOL)addPrefix {
    return [_channels _getChannel:name options:options addPrefix:addPrefix];
}

@end
