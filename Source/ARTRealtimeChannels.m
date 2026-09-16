#import <Foundation/Foundation.h>
#import "ARTRealtimeChannels+Private.h"
#import "ARTChannels+Private.h"
#import "ARTRealtimeChannel+Private.h"
#import "ARTRealtimeClient+Private.h"
#import "ARTClientOptions+Private.h"
#import "ARTRealtimePresence+Private.h"
#import "ARTClientOptions+TestConfiguration.h"
#import "ARTTestClientOptions.h"
#import "ARTGCD.h"
#import "ARTInternalLog.h"

@implementation ARTRealtimeChannels {
    ARTQueuedDealloc *_dealloc;
}

- (instancetype)initWithInternal:(ARTRealtimeChannelsInternal *)internal realtimeInternal:(ARTRealtimeClientInternal *)realtimeInternal queuedDealloc:(ARTQueuedDealloc *)dealloc {
    self = [super init];
    if (self) {
        _internal = internal;
        _realtimeInternal = realtimeInternal;
        _dealloc = dealloc;
    }
    return self;
}

- (BOOL)exists:(NSString *)name {
    return [_internal exists:(NSString *)name];
}

- (ARTRealtimeChannel *)get:(NSString *)name {
    return [[ARTRealtimeChannel alloc] initWithInternal:[_internal get:(NSString *)name] realtimeInternal:_realtimeInternal queuedDealloc:_dealloc];
}

- (ARTRealtimeChannel *)get:(NSString *)name options:(ARTRealtimeChannelOptions *)options {
    return [[ARTRealtimeChannel alloc] initWithInternal:[_internal get:(NSString *)name options:options] realtimeInternal:_realtimeInternal queuedDealloc:_dealloc];
}

- (void)release:(NSString *)name callback:(nullable ARTCallback)errorInfo {
    [_internal release:(NSString *)name callback:errorInfo];
}

- (void)release:(NSString *)name {
    [_internal release:(NSString *)name];
}

- (id<NSFastEnumeration>)iterate {
    return [_internal copyIntoIteratorWithMapper:^ARTRealtimeChannel *(ARTRealtimeChannelInternal *internalChannel) {
        return [[ARTRealtimeChannel alloc] initWithInternal:internalChannel realtimeInternal:self->_realtimeInternal queuedDealloc:self->_dealloc];
    }];
}

@end

@interface ARTRealtimeChannelsInternal ()

@property (nonatomic, readonly) ARTInternalLog *logger;
@property (weak, nonatomic) ARTRealtimeClientInternal *realtime; // weak because realtime owns self

@end

@interface ARTRealtimeChannelsInternal () <ARTChannelsDelegate>
@end

@implementation ARTRealtimeChannelsInternal {
    ARTChannels *_channels;
    dispatch_queue_t _userQueue;
}

- (instancetype)initWithRealtime:(ARTRealtimeClientInternal *)realtime logger:(ARTInternalLog *)logger {
    if (self = [super init]) {
        _realtime = realtime;
        _userQueue = _realtime.rest.userQueue;
        _queue = _realtime.rest.queue;
        _logger = logger;
        _channels = [[ARTChannels alloc] initWithDelegate:self dispatchQueue:_queue prefix:_realtime.options.testOptions.channelNamePrefix];
    }
    return self;
}

- (id)makeChannel:(NSString *)name options:(ARTRealtimeChannelOptions *)options {
    return [[ARTRealtimeChannelInternal alloc] initWithRealtime:_realtime andName:name withOptions:options logger:_logger];
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

- (void)release:(NSString *)name callback:(ARTCallback)cb {
    name = [_channels addPrefix:name];

    if (cb) {
        ARTCallback userCallback = cb;
        cb = ^(ARTErrorInfo *error) {
            art_dispatch_async(self->_userQueue, ^{
                userCallback(error);
            });
        };
    }

art_dispatch_sync(_queue, ^{
    if (![self->_channels _exists:name]) {
        if (cb) cb(nil);
        return;
    }

    ARTRealtimeChannelInternal *channel = [self->_channels _get:name];
    const ARTRealtimeChannelState state = channel.state_nosync;
    if (state != ARTRealtimeChannelInitialized && state != ARTRealtimeChannelDetached && state != ARTRealtimeChannelFailed) {
        // RTS4b
        ARTLogWarn(self.logger, @"Calling `channels.release()` on a channel in the %@ state is deprecated, and will throw an error in the next major version. Call `channel.detach()` and wait for it to complete before calling `channels.release(name)`.", [ARTRealtimeChannelStateToStr(state) lowercaseString]);
    }
    [channel _detach:^(ARTErrorInfo *errorInfo) {
        [channel off_nosync];
        [channel _unsubscribe];
        [channel.presence _unsubscribe];

        // Only release if the stored channel now is the same as whne.
        // Otherwise, subsequent calls to this release method race, and
        // a new channel, created between the first call releases the stored
        // one and the second call's detach callback is called, can be
        // released unwillingly.
        if ([self->_channels _exists:name] && [self->_channels _get:name] == channel) {
#ifdef ABLY_SUPPORTS_PLUGINS
            // Runs on the internal queue (the `_detach:` callback queue). See
            // `-nosync_onChannelRelease:` for what the plugin does with this.
            [self.realtime.options.liveObjectsPlugin nosync_onChannelRelease:channel];
#endif

            [self->_channels _release:name];
        }

        if (cb) cb(errorInfo);
    }];
});
}

- (void)release:(NSString *)name {
    [self release:name callback:nil];
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
