#import "ARTChannels+Private.h"

#import "ARTHttpClient+Private.h"
#import "ARTChannel+Private.h"
#import "ARTChannelOptions.h"
#import "ARTHttpChannel.h"
#import "ARTGCD.h"

@interface ARTChannels() {
    __weak id<ARTChannelsDelegate> _delegate; // weak because delegates outlive their counterpart
    dispatch_queue_t _queue;
}

@end

@implementation ARTChannels

- (instancetype)initWithDelegate:(id)delegate dispatchQueue:(dispatch_queue_t)queue prefix:(NSString *)prefix {
    if (self = [super init]) {
        _queue = queue;
        _channels = [[NSMutableDictionary alloc] init];
        _delegate = delegate;
        _prefix = prefix;
    }
    return self;
}

- (id<NSFastEnumeration>)copyIntoIteratorWithMapper:(id (^)(id))mapper {
    __block id<NSFastEnumeration>ret;
art_dispatch_sync(_queue, ^{
    NSMutableArray *channels = [[NSMutableArray alloc] init];
    for (id internalChannel in [self getNosyncIterable]) {
        [channels addObject:mapper(internalChannel)];
    }
    ret = [channels objectEnumerator];
});
    return ret;
}

- (id<NSFastEnumeration>)getNosyncIterable {
    return [_channels objectEnumerator];
}

- (BOOL)exists:(NSString *)name {
    __block BOOL ret;
art_dispatch_sync(_queue, ^{
    ret = [self _exists:name];
});
    return ret;
}

- (BOOL)_exists:(NSString *)name {
    return self->_channels[[self addPrefix:name]] != nil;
}

- (id)get:(NSString *)name {
    return [self getChannel:[self addPrefix:name] options:nil];
}

- (id)get:(NSString *)name options:(ARTChannelOptions *)options {
    return [self getChannel:[self addPrefix:name] options:options];
}

- (void)release:(NSString *)name {
art_dispatch_sync(_queue, ^{
    [self _release:name];
});
}

- (void)_release:(NSString *)name {
    [self->_channels removeObjectForKey:[self addPrefix:name]];
}

- (ARTHttpChannel *)getChannel:(NSString *)name options:(ARTChannelOptions *)options {
    __block ARTHttpChannel *channel;
art_dispatch_sync(_queue, ^{
    channel = [self _getChannel:name options:options addPrefix:true];
});
    return channel;
}

- (ARTChannel *)_getChannel:(NSString *)name options:(ARTChannelOptions *)options addPrefix:(BOOL)addPrefix {
    if (addPrefix) {
        name = [self addPrefix:name];
    }
    ARTChannel *channel = [self _get:name];
    if (!channel) {
        channel = [_delegate makeChannel:name options:options];
        [self->_channels setObject:channel forKey:name];
    } else if (options) {
        [channel setOptions_nosync:options];
    }
    return channel;
}

- (id)_get:(NSString *)name {
    return self->_channels[name];
}

- (NSString *)addPrefix:(NSString *)name {
    if (_prefix) {
        if (![name hasPrefix:_prefix]) {
            return [NSString stringWithFormat:@"%@-%@", _prefix, name];
        }
    }
    return name;
}

@end
