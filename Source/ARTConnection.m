#import "ARTConnection+Private.h"
#import "ARTDefault.h"
#import "ARTRealtimeClient+Private.h"
#import "ARTEventEmitter+Private.h"
#import "ARTQueuedDealloc.h"
#import "ARTRealtimeChannels+Private.h"
#import "ARTRealtimeChannel+Private.h"
#import "ARTDefault+Private.h"
#import "ARTClientOptions+Private.h"
#import "ARTGCD.h"

#define IsInactiveConnectionState(state) (state == ARTRealtimeClosing || state == ARTRealtimeClosed || state == ARTRealtimeFailed || state == ARTRealtimeSuspended)

@implementation ARTConnection {
    ARTQueuedDealloc *_dealloc;
}

- (ARTConnectionInternal *_Nonnull)internal_nosync {
    return _internal;
}

- (NSString *)id {
    return _internal.id;
}

- (NSString *)key {
    return _internal.key;
}

// RTN16g - recovery key as a JSON serialized version of [ARTConnectionRecoveryKey]
- (NSString *)createRecoveryKey {
    return [_internal createRecoveryKey];
}

- (NSInteger)maxMessageSize {
    return _internal.maxMessageSize;
}

- (ARTRealtimeConnectionState)state {
    return _internal.state;
}

- (ARTErrorInfo *)errorReason {
    return _internal.errorReason;
}

- (instancetype)initWithInternal:(ARTConnectionInternal *)internal queuedDealloc:(ARTQueuedDealloc *)dealloc {
    self = [super init];
    if (self) {
        _internal = internal;
        _dealloc = dealloc;
    }
    return self;
}

- (void)close {
    [_internal close];
}

- (void)connect {
    [_internal connect];
}

- (void)off {
    [_internal off];
}

- (void)off:(nonnull ARTEventListener *)listener {
    [_internal off:listener];
}

- (void)off:(ARTRealtimeConnectionEvent)event listener:(nonnull ARTEventListener *)listener {
    [_internal off:event listener:listener];
}

- (nonnull ARTEventListener *)on:(nonnull ARTConnectionStateCallback)cb {
    return [_internal on:cb];
}

- (nonnull ARTEventListener *)on:(ARTRealtimeConnectionEvent)event callback:(nonnull ARTConnectionStateCallback)cb {
    return [_internal on:event callback:cb];
}

- (nonnull ARTEventListener *)once:(nonnull ARTConnectionStateCallback)cb {
    return [_internal once:cb];
}

- (nonnull ARTEventListener *)once:(ARTRealtimeConnectionEvent)event callback:(nonnull ARTConnectionStateCallback)cb {
    return [_internal once:event callback:cb];
}

- (void)ping:(nonnull ARTCallback)cb {
    [_internal ping:cb];
}

@end

@implementation ARTConnectionInternal {
    _Nonnull dispatch_queue_t _queue;
    NSString *_id;
    NSString *_key;
    NSInteger _maxMessageSize;
    ARTRealtimeConnectionState _state;
    ARTErrorInfo *_errorReason;
}

- (instancetype)initWithRealtime:(ARTRealtimeClientInternal *)realtime logger:(ARTInternalLog *)logger {
    if (self = [super init]) {
        _eventEmitter = [[ARTPublicEventEmitter alloc] initWithRest:realtime.rest logger:logger];
        _realtime = realtime;
        _queue = _realtime.rest.queue;
    }
    return self;
}

- (void)connect {
    [_realtime connect];
}

- (void)close {
    [_realtime close];
}

- (void)ping:(ARTCallback)cb {
    [_realtime ping:cb];
}

- (NSString *)id {
    __block NSString *ret;
art_dispatch_sync(_queue, ^{
    ret = [self id_nosync];
});
    return ret;
}

- (NSString *)key {
    __block NSString *ret;
art_dispatch_sync(_queue, ^{
    ret = [self key_nosync];
});
    return ret;
}

- (ARTRealtimeConnectionState)state {
    __block ARTRealtimeConnectionState ret;
art_dispatch_sync(_queue, ^{
    ret = [self state_nosync];
});
    return ret;
}

- (ARTErrorInfo *)errorReason {
    __block ARTErrorInfo *ret;
art_dispatch_sync(_queue, ^{
    ret = [self errorReason_nosync];
});
    return ret;
}

- (ARTErrorInfo *)error_nosync {
    if (self.errorReason_nosync) {
        return self.errorReason_nosync;
    }
    switch (self.state_nosync) {
        case ARTRealtimeDisconnected:
            return [ARTErrorInfo createWithCode:ARTErrorDisconnected status:400 message:@"Connection to server temporarily unavailable"];
        case ARTRealtimeSuspended:
            return [ARTErrorInfo createWithCode:ARTErrorConnectionSuspended status:400 message:@"Connection to server unavailable"];
        case ARTRealtimeFailed:
            return [ARTErrorInfo createWithCode:ARTErrorConnectionFailed status:400 message:@"Connection failed or disconnected by server"];
        case ARTRealtimeClosing:
            return [ARTErrorInfo createWithCode:ARTErrorConnectionClosed status:400 message:@"Connection closing"];
        case ARTRealtimeClosed:
            return [ARTErrorInfo createWithCode:ARTErrorDisconnected status:400 message:@"Connection closed"];
        default:
            return [ARTErrorInfo createWithCode:ARTErrorInvalidTransportHandle status:400 message:[NSString stringWithFormat:@"Invalid operation (connection state is %lu - %@)", (unsigned long)self.state_nosync, ARTRealtimeConnectionStateToStr(self.state_nosync)]];
    }
}

- (BOOL)isActive_nosync {
    return self.realtime.isActive;
}

- (NSString *)id_nosync {
    return _id;
}

- (NSString *)key_nosync {
    return _key;
}

- (NSInteger)maxMessageSize {
    if (_maxMessageSize)
        return _maxMessageSize;
    return _realtime.options.isProductionEnvironment ? [ARTDefault maxProductionMessageSize] : [ARTDefault maxSandboxMessageSize];
}

- (ARTRealtimeConnectionState)state_nosync {
    return _state;
}

- (ARTErrorInfo *)errorReason_nosync {
    return _errorReason;
}

- (void)setId:(NSString *)newId {
    _id = newId;
}

- (void)setKey:(NSString *)key {
    _key = key;
}

- (void)setMaxMessageSize:(NSInteger)maxMessageSize {
    _maxMessageSize = maxMessageSize;
}

- (void)setState:(ARTRealtimeConnectionState)state {
    _state = state;
    if (IsInactiveConnectionState(state)) {
        _id = nil; // RTN8c
        _key = nil; // RTN9c
    }
}

- (void)setErrorReason:(ARTErrorInfo *_Nullable)errorReason {
    _errorReason = errorReason;
}

- (ARTEventListener *)on:(ARTRealtimeConnectionEvent)event callback:(ARTConnectionStateCallback)cb {
    return [_eventEmitter on:[ARTEvent newWithConnectionEvent:event] callback:cb];
}

- (ARTEventListener *)on:(ARTConnectionStateCallback)cb {
    return [_eventEmitter on:cb];
}

- (ARTEventListener *)once:(ARTRealtimeConnectionEvent)event callback:(ARTConnectionStateCallback)cb {
    return [_eventEmitter once:[ARTEvent newWithConnectionEvent:event] callback:cb];
}

- (ARTEventListener *)once:(ARTConnectionStateCallback)cb {
    return [_eventEmitter once:cb];
}

- (void)off {
    if (_realtime && _realtime.rest) {
        [_eventEmitter off];
    } else {
        [_eventEmitter off];
    }
}
- (void)off:(ARTRealtimeConnectionEvent)event listener:(ARTEventListener *)listener {
    [_eventEmitter off:[ARTEvent newWithConnectionEvent:event] listener:listener];
}

- (void)off:(ARTEventListener *)listener {
    [_eventEmitter off:listener];
}

- (NSString *)createRecoveryKey_nosync {
    if (_key == nil || IsInactiveConnectionState(_state)) { // RTN16g2
        return nil;
    }

    NSMutableDictionary<NSString *, NSString *> *channelSerials = [NSMutableDictionary new];
    for (ARTRealtimeChannelInternal *const channel in _realtime.channels.nosyncIterable) {
        if (channel.state_nosync == ARTRealtimeChannelAttached) {
            channelSerials[channel.name] = channel.channelSerial;
        }
    }

    ARTConnectionRecoveryKey *const recoveryKey = [[ARTConnectionRecoveryKey alloc] initWithConnectionKey:_key
                                                                                                msgSerial:_realtime.msgSerial
                                                                                           channelSerials:channelSerials];
    return [recoveryKey jsonString];
}

- (NSString *)createRecoveryKey {
    __block NSString *ret;
art_dispatch_sync(_queue, ^{
    ret = [self createRecoveryKey_nosync];
});
    return ret;
}

- (void)emit:(ARTRealtimeConnectionEvent)event with:(ARTConnectionStateChange *)data {
    [_eventEmitter emit:[ARTEvent newWithConnectionEvent:event] with:data];
}

@end

#pragma mark - ARTEvent

@implementation ARTEvent (ConnectionEvent)

- (instancetype)initWithConnectionEvent:(ARTRealtimeConnectionEvent)value {
    return [self initWithString:[NSString stringWithFormat:@"ARTRealtimeConnectionEvent%@", ARTRealtimeConnectionEventToStr(value)]];
}

+ (instancetype)newWithConnectionEvent:(ARTRealtimeConnectionEvent)value {
    return [[self alloc] initWithConnectionEvent:value];
}

@end

@implementation ARTConnectionRecoveryKey

- (instancetype)initWithConnectionKey:(NSString *)connectionKey
                            msgSerial:(int64_t)msgSerial
                       channelSerials:(NSDictionary<NSString *, NSString *> *)channelSerials {
    self = [super init];
    if (self) {
        _connectionKey = connectionKey;
        _msgSerial = msgSerial;
        _channelSerials = channelSerials;
    }
    return self;
}

- (NSString *)jsonString {
    NSError *error;
    NSDictionary *const object = @{
        @"msgSerial": @(_msgSerial),
        @"connectionKey": _connectionKey,
        @"channelSerials": _channelSerials
    };

    NSData *const jsonData = [NSJSONSerialization dataWithJSONObject:object
                                                             options:0
                                                               error:&error];
    if (error) {
        @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                       reason:[NSString stringWithFormat:@"%@: This JSON serialization should pass without errors.", self.class]
                                     userInfo:nil];
    }

    return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
}

+ (ARTConnectionRecoveryKey *)fromJsonString:(NSString *)json error:(NSError **)errorPtr {
    NSData *const jsonData = [json dataUsingEncoding:NSUTF8StringEncoding];

    NSError *error = nil;
    NSDictionary *const object = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&error];

    if (error) {
        if (errorPtr) {
            *errorPtr = error;
        }
        return nil;
    }

    return [[ARTConnectionRecoveryKey alloc] initWithConnectionKey:[object valueForKey:@"connectionKey"]
                                                         msgSerial:[[object valueForKey:@"msgSerial"] longLongValue]
                                                    channelSerials:[object valueForKey:@"channelSerials"]];
}

@end
