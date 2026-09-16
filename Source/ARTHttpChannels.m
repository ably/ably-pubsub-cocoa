#import <Foundation/Foundation.h>
#import "ARTHttpChannels+Private.h"
#import "ARTChannels+Private.h"
#import "ARTHttpChannel+Private.h"
#import "ARTHttpClient+Private.h"
#import "ARTClientOptions+TestConfiguration.h"
#import "ARTTestClientOptions.h"

@implementation ARTHttpChannels {
    ARTQueuedDealloc *_dealloc;
}

- (instancetype)initWithInternal:(ARTHttpChannelsInternal *)internal queuedDealloc:(ARTQueuedDealloc *)dealloc {
    self = [super init];
    if (self) {
        _internal = internal;
        _dealloc = dealloc;
    }
    return self;
}

- (BOOL)exists:(NSString *)name {
    return [_internal exists:(NSString *)name];
}

- (ARTHttpChannel *)get:(NSString *)name {
    return [[ARTHttpChannel alloc] initWithInternal:[_internal get:(NSString *)name] queuedDealloc:_dealloc];
}

- (ARTHttpChannel *)get:(NSString *)name options:(ARTChannelOptions *)options {
    return [[ARTHttpChannel alloc] initWithInternal:[_internal get:(NSString *)name options:(ARTChannelOptions *)options] queuedDealloc:_dealloc];
}

- (void)release:(NSString *)name {
    [_internal release:(NSString *)name];
}

- (id<NSFastEnumeration>)iterate {
    return [_internal copyIntoIteratorWithMapper:^ARTHttpChannel *(ARTHttpChannelInternal *internalChannel) {
        return [[ARTHttpChannel alloc] initWithInternal:internalChannel queuedDealloc:self->_dealloc];
    }];
}

@end

NS_ASSUME_NONNULL_BEGIN

@interface ARTHttpChannelsInternal ()

@property (weak, nonatomic, nullable) ARTHttpClientInternal *rest; // weak because rest owns self
@property (nonatomic, readonly) ARTInternalLog *logger;

@end

NS_ASSUME_NONNULL_END

@interface ARTHttpChannelsInternal () <ARTChannelsDelegate>
@end

@implementation ARTHttpChannelsInternal {
    ARTChannels *_channels;
}

- (instancetype)initWithRest:(ARTHttpClientInternal *)rest logger:(ARTInternalLog *)logger {
    if (self = [super init]) {
        _rest = rest;
        _channels = [[ARTChannels alloc] initWithDelegate:self dispatchQueue:_rest.queue prefix:rest.options.testOptions.channelNamePrefix];
        _logger = logger;
    }
    return self;
}

- (id)makeChannel:(NSString *)name options:(ARTChannelOptions *)options {
    return [[ARTHttpChannelInternal alloc] initWithName:name withOptions:options andRest:_rest logger:_logger];
}

- (id<NSFastEnumeration>)copyIntoIteratorWithMapper:(ARTHttpChannel *(^)(ARTHttpChannelInternal *))mapper {
    return [_channels copyIntoIteratorWithMapper:mapper];
}

- (ARTHttpChannelInternal *)get:(NSString *)name {
    return [_channels get:name];
}

- (ARTHttpChannelInternal *)get:(NSString *)name options:(ARTChannelOptions *)options {
    return [_channels get:name options:options];
}

- (BOOL)exists:(NSString *)name {
    return [_channels exists:name];
}

- (void)release:(NSString *)name {
    [_channels release:name];
}

- (ARTHttpChannelInternal *)_getChannel:(NSString *)name options:(ARTChannelOptions *)options addPrefix:(BOOL)addPrefix {
    return [_channels _getChannel:name options:options addPrefix:addPrefix];
}

@end
