#import "ARTRealtimeChannel+Private.h"
#import "ARTChannel+Private.h"
#import "ARTDataQuery+Private.h"

#import "ARTPubSubClient+Private.h"
#import "ARTMessage.h"
#import "ARTBaseMessage+Private.h"
#import "ARTAuth.h"
#import "ARTRealtimePresence+Private.h"
#import "ARTRealtimeAnnotations+Private.h"
#import "ARTChannel.h"
#import "ARTChannelOptions.h"
#import "ARTRealtimeChannelOptions.h"
#import "ARTProtocolMessage.h"
#import "ARTProtocolMessage+Private.h"
#import "ARTNSArray+ARTFunctional.h"
#import "ARTStatus.h"
#import "ARTDefault.h"
#import "ARTHttpClient.h"
#import "ARTClientOptions.h"
#import "ARTClientOptions+TestConfiguration.h"
#import "ARTClientOptions+Private.h"
#import "ARTTestClientOptions.h"
#import "ARTTypes.h"
#import "ARTTypes+Private.h"
#import "ARTGCD.h"
#import "ARTConnection+Private.h"
#import "ARTHttpChannels+Private.h"
#import "ARTEventEmitter+Private.h"
#import "ARTChannelStateChangeParams.h"
#import "ARTAttachRequestParams.h"
#import "ARTRetrySequence.h"
#import "ARTBackoffRetryDelayCalculator.h"
#import "ARTInternalLog.h"
#import "ARTAttachRetryState.h"
#import "ARTPublishResult.h"
#import "ARTPublishResultSerial.h"
#import "ARTUpdateDeleteResult.h"
#if TARGET_OS_IPHONE
#import "ARTPushChannel+Private.h"
#endif

#import "ARTErrorInfo+Private.h"

#ifdef ABLY_SUPPORTS_PLUGINS
@import _AblyPluginSupportPrivate;
#import "ARTPluginAPI.h"
#endif

@implementation ARTRealtimeChannel {
    ARTQueuedDealloc *_dealloc;
}

- (void)internalAsync:(void (^)(ARTRealtimeChannelInternal * _Nonnull))use {
    art_dispatch_async(_internal.queue, ^{
        use(self->_internal);
    });
}

- (void)internalSync:(void (^)(ARTRealtimeChannelInternal * _Nonnull))use {
    art_dispatch_sync(_internal.queue, ^{
        use(self->_internal);
    });
}

- (instancetype)initWithInternal:(ARTRealtimeChannelInternal *)internal pubsubInternal:(ARTPubSubClientInternal *)pubsubInternal queuedDealloc:(ARTQueuedDealloc *)dealloc {
    self = [super init];
    if (self) {
        _internal = internal;
        _realtimeInternal = pubsubInternal;
        _dealloc = dealloc;
    }
    return self;
}

- (NSString *)name {
    return _internal.name;
}

- (ARTRealtimeChannelState)state {
    return _internal.state;
}

- (ARTChannelMode)modes {
    return _internal.modes;
}

- (ARTChannelProperties *)properties {
    return _internal.properties;
}

- (ARTErrorInfo *)errorReason {
    return _internal.errorReason;
}

- (ARTRealtimePresence *)presence {
    return [[ARTRealtimePresence alloc] initWithInternal:_internal.presence queuedDealloc:_dealloc];
}

- (ARTRealtimeAnnotations *)annotations {
    return [[ARTRealtimeAnnotations alloc] initWithInternal:_internal.annotations queuedDealloc:_dealloc];
}

#if TARGET_OS_IPHONE

- (ARTPushChannel *)push {
    return [[ARTPushChannel alloc] initWithInternal:_internal.push queuedDealloc:_dealloc];
}

#endif

- (void)publish:(nullable NSString *)name data:(nullable id)data {
    [_internal publish:name data:data];
}

- (void)publish:(nullable NSString *)name data:(nullable id)data callback:(nullable ARTCallback)callback {
    [_internal publish:name data:data callback:callback];
}

- (void)publish:(nullable NSString *)name data:(nullable id)data resultCallback:(nullable ARTPublishResultCallback)resultCallback {
    [_internal publish:name data:data resultCallback:resultCallback];
}

- (void)publish:(nullable NSString *)name data:(nullable id)data clientId:(NSString *)clientId {
    [_internal publish:name data:data clientId:clientId];
}

- (void)publish:(nullable NSString *)name data:(nullable id)data clientId:(NSString *)clientId callback:(nullable ARTCallback)callback {
    [_internal publish:name data:data clientId:clientId callback:callback];
}

- (void)publish:(nullable NSString *)name data:(nullable id)data extras:(nullable id<ARTJsonCompatible>)extras {
    [_internal publish:name data:data extras:extras];
}

- (void)publish:(nullable NSString *)name data:(nullable id)data extras:(nullable id<ARTJsonCompatible>)extras callback:(nullable ARTCallback)callback {
    [_internal publish:name data:data extras:extras callback:callback];
}

- (void)publish:(nullable NSString *)name data:(nullable id)data clientId:(NSString *)clientId extras:(nullable id<ARTJsonCompatible>)extras {
    [_internal publish:name data:data clientId:clientId extras:extras];
}

- (void)publish:(nullable NSString *)name data:(nullable id)data clientId:(NSString *)clientId extras:(nullable id<ARTJsonCompatible>)extras callback:(nullable ARTCallback)callback {
    [_internal publish:name data:data clientId:clientId extras:extras callback:callback];
}

- (void)publish:(NSArray<ARTMessage *> *)messages {
    [_internal publish:messages];
}

- (void)publish:(NSArray<ARTMessage *> *)messages callback:(nullable ARTCallback)callback {
    [_internal publish:messages callback:callback];
}

- (void)publish:(NSArray<ARTMessage *> *)messages resultCallback:(nullable ARTPublishResultCallback)resultCallback {
    [_internal publish:messages resultCallback:resultCallback];
}

- (void)updateMessage:(ARTMessage *)message operation:(nullable ARTMessageOperation *)operation params:(nullable NSDictionary<NSString *, ARTStringifiable *> *)params callback:(nullable ARTEditResultCallback)callback {
    [_internal updateMessage:message operation:operation params:params wrapperSDKAgents:nil callback:callback];
}

- (void)deleteMessage:(ARTMessage *)message operation:(nullable ARTMessageOperation *)operation params:(nullable NSDictionary<NSString *, ARTStringifiable *> *)params callback:(nullable ARTEditResultCallback)callback {
    [_internal deleteMessage:message operation:operation params:params wrapperSDKAgents:nil callback:callback];
}

- (void)appendMessage:(ARTMessage *)message operation:(nullable ARTMessageOperation *)operation params:(nullable NSDictionary<NSString *, ARTStringifiable *> *)params callback:(nullable ARTEditResultCallback)callback {
    [_internal appendMessage:message operation:operation params:params wrapperSDKAgents:nil callback:callback];
}

- (void)getMessageWithSerial:(NSString *)serial callback:(ARTMessageErrorCallback)callback {
    [_internal getMessageWithSerial:serial wrapperSDKAgents:nil callback:callback];
}

- (void)getMessageVersionsWithSerial:(NSString *)serial callback:(ARTPaginatedMessagesCallback)callback {
    [_internal getMessageVersionsWithSerial:serial wrapperSDKAgents:nil callback:callback];
}

- (void)history:(ARTPaginatedMessagesCallback)callback {
    [_internal historyWithWrapperSDKAgents:nil completion:callback];
}

- (BOOL)exceedMaxSize:(NSArray<ARTBaseMessage *> *)messages {
    return [_internal exceedMaxSize:messages];
}

- (void)attach {
    [_internal attach];
}

- (void)attach:(nullable ARTCallback)callback {
    [_internal attach:callback];
}

- (void)detach {
    [_internal detach];
}

- (void)detach:(nullable ARTCallback)callback {
    [_internal detach:callback];
}

- (ARTEventListener *_Nullable)subscribe:(ARTMessageCallback)callback {
    return [_internal subscribe:callback];
}

- (ARTEventListener *_Nullable)subscribeWithAttachCallback:(nullable ARTCallback)onAttach callback:(ARTMessageCallback)cb {
    return [_internal subscribeWithAttachCallback:onAttach callback:cb];
}

- (ARTEventListener *_Nullable)subscribe:(NSString *)name callback:(ARTMessageCallback)cb {
    return [_internal subscribe:name callback:cb];
}

- (ARTEventListener *_Nullable)subscribe:(NSString *)name onAttach:(nullable ARTCallback)onAttach callback:(ARTMessageCallback)cb {
    return [_internal subscribe:name onAttach:onAttach callback:cb];
}

- (void)unsubscribe {
    [_internal unsubscribe];
}

- (void)unsubscribe:(ARTEventListener *_Nullable)listener {
    [_internal unsubscribe:listener];
}

- (void)unsubscribe:(NSString *)name listener:(ARTEventListener *_Nullable)listener {
    [_internal unsubscribe:name listener:listener];
}

- (BOOL)history:(ARTRealtimeHistoryQuery *_Nullable)query callback:(ARTPaginatedMessagesCallback)callback error:(NSError *_Nullable *_Nullable)errorPtr {
    return [_internal history:query wrapperSDKAgents:nil callback:callback error:errorPtr];
}

- (ARTEventListener *)on:(ARTChannelStateCallback)cb {
    return [_internal on:cb];
}

- (ARTEventListener *)once:(ARTChannelEvent)event callback:(ARTChannelStateCallback)cb {
    return [_internal once:event callback:cb];
}

- (ARTEventListener *)once:(ARTChannelStateCallback)cb {
    return [_internal once:cb];
}

- (void)off:(ARTChannelEvent)event listener:(ARTEventListener *)listener {
    [_internal off:event listener:listener];
}

- (void)off:(ARTEventListener *)listener {
    [_internal off:listener];
}

- (void)off {
    [_internal off];
}

- (nonnull ARTEventListener *)on:(ARTChannelEvent)event callback:(nonnull ARTChannelStateCallback)cb {
    return [_internal on:event callback:cb];
}

- (ARTRealtimeChannelOptions *)getOptions {
    return [_internal getOptions];
}

- (void)setOptions:(ARTRealtimeChannelOptions *_Nullable)options callback:(nullable ARTCallback)cb {
    [_internal setOptions:options callback:cb];
}

@end

@interface ARTRealtimeChannelInternal () {
    ARTRealtimePresenceInternal *_realtimePresence;
    ARTRealtimeAnnotationsInternal *_realtimeAnnotations;
    #if TARGET_OS_IPHONE
    ARTPushChannelInternal *_pushChannel;
    #endif
    CFRunLoopTimerRef _attachTimer;
    CFRunLoopTimerRef _detachTimer;
    ARTEventEmitter<ARTEvent *, ARTErrorInfo *> *_attachedEventEmitter;
    ARTEventEmitter<ARTEvent *, ARTErrorInfo *> *_detachedEventEmitter;
    NSString * _Nullable _lastPayloadMessageId;
    BOOL _decodeFailureRecoveryInProgress;
}

@end

NS_ASSUME_NONNULL_BEGIN

@interface ARTRealtimeChannelInternal ()

@property (nonatomic, readonly) ARTAttachRetryState *attachRetryState;
@property (nonatomic, readonly) NSMutableDictionary<NSString *, id> *pluginData;

@end

NS_ASSUME_NONNULL_END

@implementation ARTRealtimeChannelInternal {
    dispatch_queue_t _queue;
    dispatch_queue_t _userQueue;
    ARTErrorInfo *_errorReason;
    ARTChannelMode _modes;
}

- (instancetype)initWithPubSub:(ARTPubSubClientInternal *)pubsub andName:(NSString *)name withOptions:(ARTRealtimeChannelOptions *)options logger:(ARTInternalLog *)logger {
    self = [super initWithName:name andOptions:options rest:pubsub.rest logger:logger];
    if (self) {
        _realtime = pubsub;
        _queue = pubsub.rest.queue;
        _userQueue = pubsub.rest.userQueue;
        _restChannel = [_realtime.rest.channels _getChannel:self.name options:options addPrefix:true];
        _state = ARTRealtimeChannelInitialized;
        _modes = 0;
        _attachSerial = nil;
        _realtimePresence = [[ARTRealtimePresenceInternal alloc] initWithChannel:self logger:self.logger];
        _realtimeAnnotations = [[ARTRealtimeAnnotationsInternal alloc] initWithChannel:self logger:self.logger];
        _statesEventEmitter = [[ARTPublicEventEmitter alloc] initWithRest:_realtime.rest logger:logger];
        _messagesEventEmitter = [[ARTInternalEventEmitter alloc] initWithQueues:_queue userQueue:_userQueue timeProvider:_realtime.rest.timeProvider];
        _attachedEventEmitter = [[ARTInternalEventEmitter alloc] initWithQueue:_queue timeProvider:_realtime.rest.timeProvider];
        _detachedEventEmitter = [[ARTInternalEventEmitter alloc] initWithQueue:_queue timeProvider:_realtime.rest.timeProvider];
        _internalEventEmitter = [[ARTInternalEventEmitter alloc] initWithQueue:_queue timeProvider:_realtime.rest.timeProvider];
        const id<ARTRetryDelayCalculator> attachRetryDelayCalculator = [[ARTBackoffRetryDelayCalculator alloc] initWithInitialRetryTimeout:pubsub.options.channelRetryTimeout
                                                                                                                jitterCoefficientGenerator:pubsub.options.testOptions.jitterCoefficientGenerator];
        _attachRetryState = [[ARTAttachRetryState alloc] initWithRetryDelayCalculator:attachRetryDelayCalculator
                                                                               logger:logger
                                                                     logMessagePrefix:[NSString stringWithFormat:@"RT: %p C:%p ", _realtime, self]];
        _pluginData = [[NSMutableDictionary alloc] init];

#ifdef ABLY_SUPPORTS_PLUGINS
        // We need to register the pluginAPI before the LiveObjects plugin tries to fetch it in the call to prepareChannel below (and also before the LiveObjects plugin later tries to use it in its extension of ARTRealtimeChannel).
        [ARTPluginAPI registerSelf];

        // If the LiveObjects plugin has been provided, set up LiveObjects functionality for this channel.
        id<APLiveObjectsInternalPluginProtocol> liveObjectsPlugin = pubsub.options.liveObjectsPlugin;
        if (liveObjectsPlugin) {
            [liveObjectsPlugin nosync_prepareChannel:self client:pubsub];
        }
#endif
    }
    return self;
}

- (ARTRealtimeChannelState)state {
    __block ARTRealtimeChannelState ret;
art_dispatch_sync(_queue, ^{
    ret = [self state_nosync];
});
    return ret;
}

- (ARTErrorInfo *)errorReason {
    __block ARTErrorInfo * ret;
art_dispatch_sync(_queue, ^{
    ret = [self errorReason_nosync];
});
    return ret;
}

- (ARTChannelMode)modes {
    __block ARTChannelMode ret;
art_dispatch_sync(_queue, ^{
    ret = [self modes_nosync];
});
    return ret;
}

- (ARTRealtimeChannelState)state_nosync {
    return _state;
}

- (ARTChannelMode)modes_nosync {
    return _modes;
}

- (BOOL)canBeReattached {
    switch (self.state_nosync) {
        case ARTRealtimeChannelAttaching:
        case ARTRealtimeChannelAttached:
        case ARTRealtimeChannelSuspended:
            return YES;
        default:
            return NO;
    }
}

- (BOOL)shouldAttach {
    switch (self.state_nosync) {
        case ARTRealtimeChannelInitialized:
        case ARTRealtimeChannelDetaching:
        case ARTRealtimeChannelDetached:
            return YES;
        default:
            return NO;
    }
}

- (BOOL)isAnnotationSubscribeGranted {
    return self.modes_nosync & ARTChannelModeAnnotationSubscribe;
}

- (ARTErrorInfo *)errorReason_nosync {
    return _errorReason;
}

- (ARTRealtimePresenceInternal *)presence {
    return _realtimePresence;
}

- (ARTRealtimeAnnotationsInternal *)annotations {
    return _realtimeAnnotations;
}

#if TARGET_OS_IPHONE
- (ARTPushChannelInternal *)push {
    if (!_pushChannel) {
        _pushChannel = [[ARTPushChannelInternal alloc] init:self.realtime.rest withChannel:self logger:self.logger];
    }
    return _pushChannel;
}
#endif

- (void)internalPostMessages:(id)data callback:(ARTPublishResultCallback)callback {
    if (callback) {
        ARTPublishResultCallback userCallback = callback;
        callback = ^(ARTPublishResult *__nullable result, ARTErrorInfo *__nullable error) {
            art_dispatch_async(self->_userQueue, ^{
                userCallback(result, error);
            });
        };
    }

    if (![data isKindOfClass:[NSArray class]]) {
        data = @[data];
    }

art_dispatch_sync(_queue, ^{
    if ([data isKindOfClass:[ARTMessage class]]) {
        ARTMessage *message = (ARTMessage *)data;
        if (message.clientId && self->_realtime.rest.auth.clientId_nosync && ![message.clientId isEqualToString:self->_realtime.rest.auth.clientId_nosync]) {
            if (callback)
                callback(nil, [ARTErrorInfo createWithCode:ARTStateMismatchedClientId message:@"attempted to publish message with an invalid clientId"]);
            return;
        }
    }
    else if ([data isKindOfClass:[NSArray class]]) {
        NSArray<ARTMessage *> *messages = (NSArray *)data;
        for (ARTMessage *message in messages) {
            if (message.clientId && self->_realtime.rest.auth.clientId_nosync && ![message.clientId isEqualToString:self->_realtime.rest.auth.clientId_nosync]) {
                if (callback)
                    callback(nil, [ARTErrorInfo createWithCode:ARTStateMismatchedClientId message:@"attempted to publish message with an invalid clientId"]);
                return;
            }
        }
    }

    ARTProtocolMessage *msg = [[ARTProtocolMessage alloc] init];
    msg.action = ARTProtocolMessageMessage;
    msg.channel = self.name;
    msg.messages = data;

    [self publishProtocolMessage:msg callback:^void(ARTMessageSendStatus *status) {
        if (callback)
            callback(status.publishResult, status.status.errorInfo);
    }];
});
}

#ifdef ABLY_SUPPORTS_PLUGINS
- (void)sendObjectWithObjectMessages:(NSArray<id<APObjectMessageProtocol>> *)objectMessages
                          completion:(void (^)(ARTPublishResult *_Nullable publishResult, ARTErrorInfo *_Nullable error))completion {
    ARTProtocolMessage *pm = [[ARTProtocolMessage alloc] init];
    pm.action = ARTProtocolMessageObject;
    pm.channel = self.name;
    pm.state = objectMessages;

    [self publishProtocolMessage:pm callback:^(ARTMessageSendStatus *status) {
        if (completion) {
            completion(status.publishResult, status.status.errorInfo);
        }
    }];
}
#endif

- (void)internalSendEditRequestForMessage:(ARTMessage *)message
                                   params:(nullable NSDictionary<NSString *, ARTStringifiable *> *)params
                         wrapperSDKAgents:(nullable NSStringDictionary *)wrapperSDKAgents
                                 callback:(nullable ARTEditResultCallback)callback {
    if (callback) {
        ARTEditResultCallback userCallback = callback;
        callback = ^(ARTUpdateDeleteResult *_Nullable result, ARTErrorInfo *_Nullable error) {
            art_dispatch_async(self->_userQueue, ^{
                userCallback(result, error);
            });
        };
    }

    art_dispatch_sync(_queue, ^{
        // RTL32b
        ARTProtocolMessage *msg = [[ARTProtocolMessage alloc] init];
        msg.action = ARTProtocolMessageMessage;
        msg.channel = self.name;
        msg.messages = @[message];

        // RTL32e: include params in ProtocolMessage
        if (params && params.count > 0) {
            NSMutableDictionary<NSString *, NSString *> *stringParams = [NSMutableDictionary dictionaryWithCapacity:params.count];
            for (NSString *key in params) {
                stringParams[key] = params[key].stringValue;
            }
            msg.params = stringParams;
        }

        [self publishProtocolMessage:msg callback:^void(ARTMessageSendStatus *status) {
            if (callback) {
                if (status.status.errorInfo) {
                    callback(nil, status.status.errorInfo);
                } else {
                    // RTL32d: Extract the versionSerial from the ACK and create an UpdateDeleteResult
                    NSString *versionSerial = status.publishResult.serials.firstObject.value;
                    ARTUpdateDeleteResult *updateDeleteResult = [[ARTUpdateDeleteResult alloc] initWithVersionSerial:versionSerial];
                    callback(updateDeleteResult, nil);
                }
            }
        }];
    });
}

- (void)getMessageWithSerial:(NSString *)serial wrapperSDKAgents:(nullable NSStringDictionary *)wrapperSDKAgents callback:(ARTMessageErrorCallback)callback {
    [self.restChannel getMessageWithSerial:serial wrapperSDKAgents:wrapperSDKAgents callback:callback];
}

- (void)getMessageVersionsWithSerial:(NSString *)serial wrapperSDKAgents:(nullable NSStringDictionary *)wrapperSDKAgents callback:(ARTPaginatedMessagesCallback)callback {
    [self.restChannel getMessageVersionsWithSerial:serial wrapperSDKAgents:wrapperSDKAgents callback:callback];
}

- (void)publishProtocolMessage:(ARTProtocolMessage *)pm callback:(ARTMessageSendCallback)cb {
    switch (self.state_nosync) {
        case ARTRealtimeChannelSuspended:
        case ARTRealtimeChannelFailed: {
            if (cb) {
                ARTErrorInfo *error = [ARTErrorInfo createWithCode:ARTErrorChannelOperationFailedInvalidState message:[NSString stringWithFormat:@"channel operation failed (invalid channel state: %@)", ARTRealtimeChannelStateToStr(self.state_nosync)]];
                cb([ARTMessageSendStatus errorWithInfo:error]);
            }
            break;
        }
        case ARTRealtimeChannelInitialized:
        case ARTRealtimeChannelDetaching:
        case ARTRealtimeChannelDetached:
        case ARTRealtimeChannelAttaching:
        case ARTRealtimeChannelAttached: {
            [self.realtime send:pm sentCallback:nil ackCallback:^(ARTMessageSendStatus *status) {
                if (cb) cb(status);
            }];
            break;
        }
    }
}

- (ARTEventListener *)_subscribe:(nullable NSString *)name onAttach:(nullable ARTCallback)onAttach callback:(nullable ARTMessageCallback)cb {
    if (cb) {
        ARTMessageCallback userCallback = cb;
        cb = ^(ARTMessage *_Nonnull m) {
            if (self.state_nosync != ARTRealtimeChannelAttached) { // RTL17
                return;
            }
            art_dispatch_async(self->_userQueue, ^{
                userCallback(m);
            });
        };
    }
    if (onAttach) {
        ARTCallback userOnAttach = onAttach;
        onAttach = ^(ARTErrorInfo *_Nullable e) {
            art_dispatch_async(self->_userQueue, ^{
                userOnAttach(e);
            });
        };
    }

    __block ARTEventListener *listener = nil;
art_dispatch_sync(_queue, ^{
    ARTRealtimeChannelOptions *options = self.getOptions_nosync;
    BOOL attachOnSubscribe = options != nil ? options.attachOnSubscribe : true;
    if (self.state_nosync == ARTRealtimeChannelFailed) {
        if (onAttach && attachOnSubscribe) { // RTL7h
            onAttach([ARTErrorInfo createWithCode:ARTErrorChannelOperationFailedInvalidState message:@"attempted to subscribe while channel is in FAILED state."]);
        }
        ARTLogWarn(self.logger, @"R:%p C:%p (%@) subscribe of '%@' has been ignored (attempted to subscribe while channel is in FAILED state)", self->_realtime, self, self.name, name == nil ? @"all" : name);
        return;
    }
    if (self.shouldAttach && attachOnSubscribe) { // RTL7g
        [self _attach:onAttach];
    }
    listener = name == nil ? [self.messagesEventEmitter on:cb] : [self.messagesEventEmitter on:name callback:cb];
    ARTLogVerbose(self.logger, @"R:%p C:%p (%@) subscribe to '%@' event(s)", self->_realtime, self, self.name, name == nil ? @"all" : name);
});
    return listener;
}

- (ARTEventListener *)subscribe:(ARTMessageCallback)cb {
    return [self _subscribe:nil onAttach:nil callback:cb];
}

- (ARTEventListener *)subscribeWithAttachCallback:(ARTCallback)onAttach callback:(ARTMessageCallback)cb {
    return [self _subscribe:nil onAttach:onAttach callback:cb];
}

- (ARTEventListener *)subscribe:(NSString *)name callback:(ARTMessageCallback)cb {
    return [self _subscribe:name onAttach:nil callback:cb];
}

- (ARTEventListener *)subscribe:(NSString *)name onAttach:(ARTCallback)onAttach callback:(ARTMessageCallback)cb {
    return [self _subscribe:name onAttach:onAttach callback:cb];
}

- (void)unsubscribe {
art_dispatch_sync(_queue, ^{
    [self _unsubscribe];
    ARTLogVerbose(self.logger, @"R:%p C:%p (%@) unsubscribe to all events", self->_realtime, self, self.name);
});
}

- (void)_unsubscribe {
    [self.messagesEventEmitter off];
}

- (void)unsubscribe:(ARTEventListener *)listener {
art_dispatch_sync(_queue, ^{
    [self.messagesEventEmitter off:listener];
    ARTLogVerbose(self.logger, @"RT:%p C:%p (%@) unsubscribe to all events", self->_realtime, self, self.name);
});
}

- (void)unsubscribe:(NSString *)name listener:(ARTEventListener *)listener {
art_dispatch_sync(_queue, ^{
    [self.messagesEventEmitter off:name listener:listener];
    ARTLogVerbose(self.logger, @"RT:%p C:%p (%@) unsubscribe to event '%@'", self->_realtime, self, self.name, name);
});
}

- (ARTEventListener *)on:(ARTChannelEvent)event callback:(ARTChannelStateCallback)cb {
    return [self.statesEventEmitter on:[ARTEvent newWithChannelEvent:event] callback:cb];
}

- (ARTEventListener *)on:(ARTChannelStateCallback)cb {
    return [self.statesEventEmitter on:cb];
}

- (ARTEventListener *)once:(ARTChannelEvent)event callback:(ARTChannelStateCallback)cb {
    return [self.statesEventEmitter once:[ARTEvent newWithChannelEvent:event] callback:cb];
}

- (ARTEventListener *)once:(ARTChannelStateCallback)cb {
    return [self.statesEventEmitter once:cb];
}

- (void)off {
    [self.statesEventEmitter off];
}


- (void)off_nosync {
    [(ARTPublicEventEmitter *)self.statesEventEmitter off_nosync];
}

- (void)off:(ARTChannelEvent)event listener:listener {
    [self.statesEventEmitter off:[ARTEvent newWithChannelEvent:event] listener:listener];
}

- (void)off:(ARTEventListener *)listener {
    [self.statesEventEmitter off:listener];
}

- (void)emit:(ARTChannelEvent)event with:(ARTChannelStateChange *)data {
    [self.statesEventEmitter emit:[ARTEvent newWithChannelEvent:event] with:data];
    [self.internalEventEmitter emit:[ARTEvent newWithChannelEvent:event] with:data];
}

- (void)performTransitionToState:(ARTRealtimeChannelState)state withParams:(ARTChannelStateChangeParams *)params {
    ARTLogDebug(self.logger, @"RT:%p C:%p (%@) channel state transitions from %tu - %@ to %tu - %@%@", _realtime, self, self.name, self.state_nosync, ARTRealtimeChannelStateToStr(self.state_nosync), state, ARTRealtimeChannelStateToStr(state), params.retryAttempt ? [NSString stringWithFormat: @" (result of %@)", params.retryAttempt.id] : @"");
    ARTChannelStateChange *stateChange = [[ARTChannelStateChange alloc] initWithCurrent:state previous:self.state_nosync event:(ARTChannelEvent)state reason:params.errorInfo resumed:params.resumed retryAttempt:params.retryAttempt];
    self.state = state;

    if (params.storeErrorInfo) {
        _errorReason = params.errorInfo;
    }

    [self.attachRetryState channelWillTransitionToState:state];

    ARTEventListener *channelRetryListener = nil;
    switch (state) {
        case ARTRealtimeChannelAttached:
            self.attachResume = true;
            break;
        case ARTRealtimeChannelSuspended: {
            self.channelSerial = nil; // RTP5a1
            ARTRetryAttempt *const retryAttempt = [self.attachRetryState addRetryAttempt];

            [_attachedEventEmitter emit:nil with:params.errorInfo];
            if (self.realtime.shouldSendEvents) {
                channelRetryListener = [self unlessStateChangesBefore:retryAttempt.delay do:^{
                    ARTLogDebug(self.logger, @"RT:%p C:%p (%@) reattach initiated by retry timeout, acting on retry attempt %@", self->_realtime, self, self.name, retryAttempt.id);
                    ARTAttachRequestParams *const attachParams = [[ARTAttachRequestParams alloc] initWithReason:nil channelSerial:nil retryAttempt:retryAttempt];
                    [self reattachWithParams:attachParams];
                }];
            }
            break;
        }
        case ARTRealtimeChannelDetaching:
            self.attachResume = false;
            break;
        case ARTRealtimeChannelDetached:
            self.channelSerial = nil; // RTP5a1
            [self.presence failsSync:params.errorInfo]; // RTP5a
            break;
        case ARTRealtimeChannelFailed:
            self.channelSerial = nil; // RTP5a1
            self.attachResume = false;
            [_attachedEventEmitter emit:nil with:params.errorInfo];
            [_detachedEventEmitter emit:nil with:params.errorInfo];
            [self.presence failsSync:params.errorInfo]; // RTP5a
            break;
        default:
            break;
    }

    [self emit:stateChange.event with:stateChange];

#ifdef ABLY_SUPPORTS_PLUGINS
    id<APLiveObjectsInternalPluginProtocol> plugin = self.realtime.options.liveObjectsPlugin;
    [plugin nosync_onChannelStateChanged:self toState:ARTConvertToPluginChannelState(state) reason:params.errorInfo];
#endif

    if (channelRetryListener) {
        [channelRetryListener startTimer];
    }
}

- (ARTEventListener *)unlessStateChangesBefore:(NSTimeInterval)deadline do:(void(^)(void))callback {
    return [[self.internalEventEmitter once:^(ARTChannelStateChange *stateChange) {
        // Any state change cancels the timeout.
    }] setTimer:deadline onTimeout:^{
        if (callback) {
            callback();
        }
    }];
}

- (void)onChannelMessage:(ARTProtocolMessage *)message {
    ARTLogDebug(self.logger, @"R:%p C:%p (%@) received channel message %tu - %@", _realtime, self, self.name, message.action, ARTProtocolMessageActionToStr(message.action));
    switch (message.action) {
        case ARTProtocolMessageAttached:
            ARTLogDebug(self.logger, @"R:%p C:%p (%@) %@", _realtime, self, self.name, message.description);
            [self setAttached:message];
            break;
        case ARTProtocolMessageDetach:
        case ARTProtocolMessageDetached:
            [self setDetached:message];
            break;
        case ARTProtocolMessageMessage:
            if (_decodeFailureRecoveryInProgress) {
                ARTLogDebug(self.logger, @"R:%p C:%p (%@) message decode recovery in progress, message skipped: %@", _realtime, self, self.name, message.description);
                break;
            }
            [self onMessage:message];
            break;
        case ARTProtocolMessagePresence:
            [self onPresence:message];
            break;
        case ARTProtocolMessageAnnotation:
            [self onAnnotation:message];
            break;
        case ARTProtocolMessageError:
            [self onError:message];
            break;
        case ARTProtocolMessageSync:
            [self onSync:message];
            break;
        case ARTProtocolMessageObject:
            [self onObject:message];
            break;
        case ARTProtocolMessageObjectSync:
            [self onObjectSync:message];
            break;
        default:
            ARTLogWarn(self.logger, @"R:%p C:%p (%@) unknown ARTProtocolMessage action: %tu", _realtime, self, self.name, message.action);
            break;
    }
}

- (void)setAttached:(ARTProtocolMessage *)message {
    ARTRealtimeChannelState state = self.state_nosync;
    switch (state) {
        case ARTRealtimeChannelDetaching:
        case ARTRealtimeChannelFailed:
            // Ignore
            return;
        default:
            break;
    }

    if (message.resumed) {
        ARTLogDebug(self.logger, @"R:%p C:%p (%@) channel has resumed", _realtime, self, self.name);
    }
    // RTL15a
    self.attachSerial = message.channelSerial;

    // RTL15b
    if (message.channelSerial) {
        self.channelSerial = message.channelSerial;
    }

    // RTL4m
    self.modes = message.channelModes;

#ifdef ABLY_SUPPORTS_PLUGINS
    [self.realtime.options.liveObjectsPlugin nosync_onChannelAttached:self
                                                           hasObjects:message.hasObjects];
#endif

    if (state == ARTRealtimeChannelAttached) {
        if (!message.resumed) { // RTL12
            if (message.error != nil) {
                _errorReason = message.error;
            }
            ARTChannelStateChange *stateChange = [[ARTChannelStateChange alloc] initWithCurrent:state previous:state event:ARTChannelEventUpdate reason:message.error resumed:message.resumed];
            [self emit:stateChange.event with:stateChange];
            [self.presence onAttached:message];
        }
        return;
    }

    ARTChannelStateChangeParams *params;
    if (message.error) {
        params = [[ARTChannelStateChangeParams alloc] initWithState:ARTStateError errorInfo:message.error];
    } else {
        params = [[ARTChannelStateChangeParams alloc] initWithState:ARTStateOk];
    }
    params.resumed = message.resumed;
    [self performTransitionToState:ARTRealtimeChannelAttached withParams:params];
    [self.presence onAttached:message];
    [_attachedEventEmitter emit:nil with:nil];
}

- (void)setDetached:(ARTProtocolMessage *)message {
    switch (self.state_nosync) {
        case ARTRealtimeChannelAttached:
        case ARTRealtimeChannelSuspended: {
            ARTLogDebug(self.logger, @"RT:%p C:%p (%@) reattach initiated by DETACHED message", _realtime, self, self.name);
            ARTAttachRequestParams *const params = [[ARTAttachRequestParams alloc] initWithReason:message.error];
            [self reattachWithParams:params];
            return;
        }
        case ARTRealtimeChannelAttaching: {
            ARTLogDebug(self.logger, @"RT:%p C:%p (%@) reattach initiated by DETACHED message but it is currently attaching", _realtime, self, self.name);
            const ARTState state = message.error ? ARTStateError : ARTStateOk;
            ARTChannelStateChangeParams *const params = [[ARTChannelStateChangeParams alloc] initWithState:state
                                                                                                 errorInfo:message.error
                                                                                            storeErrorInfo:NO];
            [self setSuspended:params];
            return;
        }
        case ARTRealtimeChannelFailed:
            return;
        default:
            break;
    }

    self.attachSerial = nil;

    ARTErrorInfo *errorInfo = message.error ? message.error : [ARTErrorInfo createWithCode:0 message:@"channel has detached"];
    ARTChannelStateChangeParams *const params = [[ARTChannelStateChangeParams alloc] initWithState:ARTStateNotAttached errorInfo:errorInfo];
    [self detachChannel:params];
    [_detachedEventEmitter emit:nil with:nil];
}

- (void)failPendingPresenceWithState:(ARTState)state info:(nullable ARTErrorInfo *)info {
    ARTStatus *const status = [ARTStatus state:state info:info];
    [self.presence failPendingPresence:status];
}

- (void)detachChannel:(ARTChannelStateChangeParams *)params {
    if (self.state_nosync == ARTRealtimeChannelDetached) {
        return;
    }
    [self failPendingPresenceWithState:params.state info:params.errorInfo]; // RTP5a
    [self performTransitionToState:ARTRealtimeChannelDetached withParams:params];
}

- (void)setFailed:(ARTChannelStateChangeParams *)params {
    [self failPendingPresenceWithState:params.state info:params.errorInfo]; // RTP5a
    [self performTransitionToState:ARTRealtimeChannelFailed withParams:params];
}

- (void)setSuspended:(ARTChannelStateChangeParams *)params {
    [self failPendingPresenceWithState:params.state info:params.errorInfo]; // RTP5f
    [self performTransitionToState:ARTRealtimeChannelSuspended withParams:params];
}

- (void)onMessage:(ARTProtocolMessage *)pm {
    int i = 0;

    ARTMessage *firstMessage = pm.messages.firstObject;
    if (firstMessage.extras) {
        NSError *extrasDecodeError;
        NSDictionary *const extras = [firstMessage.extras toJSON:&extrasDecodeError];
        if (extrasDecodeError) {
            ARTLogError(self.logger, @"R:%p C:%p (%@) message extras %@ decode error: %@", _realtime, self, self.name, firstMessage.extras, extrasDecodeError);
        }
        else {
            NSString *const deltaFrom = [[extras objectForKey:@"delta"] objectForKey:@"from"];
            if (deltaFrom && _lastPayloadMessageId && ![deltaFrom isEqualToString:_lastPayloadMessageId]) {
                ARTErrorInfo *incompatibleIdError = [ARTErrorInfo createWithCode:ARTErrorUnableToDecodeMessage message:[NSString stringWithFormat:@"previous id '%@' is incompatible with message delta %@", _lastPayloadMessageId, firstMessage]];
                ARTLogError(self.logger, @"R:%p C:%p (%@) %@", _realtime, self, self.name, incompatibleIdError.message);
                for (int j = i + 1; j < pm.messages.count; j++) {
                    ARTLogVerbose(self.logger, @"R:%p C:%p (%@) message skipped %@", _realtime, self, self.name, pm.messages[j]);
                }
                [self startDecodeFailureRecoveryWithErrorInfo:incompatibleIdError];
                return;
            }
        }
    }

    ARTDataEncoder *dataEncoder = self.dataEncoder;
    for (ARTMessage *m in pm.messages) {
        ARTMessage *msg = m;

        if (msg.data && dataEncoder) {
            NSError *decodeError = nil;
            msg = [msg decodeWithEncoder:dataEncoder error:&decodeError];
            if (decodeError) {
                ARTErrorInfo *errorInfo = [ARTErrorInfo wrap:[ARTErrorInfo createWithCode:ARTErrorUnableToDecodeMessage message:decodeError.localizedFailureReason] prepend:@"Failed to decode data: "];
                ARTLogError(self.logger, @"R:%p C:%p (%@) %@", _realtime, self, self.name, errorInfo.message);
                _errorReason = errorInfo;
                ARTChannelStateChange *stateChange = [[ARTChannelStateChange alloc] initWithCurrent:self.state_nosync previous:self.state_nosync event:ARTChannelEventUpdate reason:errorInfo];
                [self emit:stateChange.event with:stateChange];

                if (decodeError.code == ARTErrorUnableToDecodeMessage) {
                    [self startDecodeFailureRecoveryWithErrorInfo:errorInfo];
                    return;
                }
            }
        }

        if (!msg.timestamp) {
            msg.timestamp = pm.timestamp;
        }
        if (!msg.id) {
            msg.id = [NSString stringWithFormat:@"%@:%d", pm.id, i];
        }
        if (!msg.connectionId) {
            msg.connectionId = pm.connectionId;
        }

        _lastPayloadMessageId = msg.id;

        [self.messagesEventEmitter emit:msg.name with:msg];

        ++i;
    }

    // RTL15b
    if (pm.channelSerial) {
        self.channelSerial = pm.channelSerial;
    }
}

- (void)onPresence:(ARTProtocolMessage *)message {
    ARTLogDebug(self.logger, @"RT:%p C:%p (%@) handle PRESENCE message", _realtime, self, self.name);
    // RTL15b
    if (message.channelSerial) {
        self.channelSerial = message.channelSerial;
    }
    [self.presence onMessage:message];
}

- (void)onAnnotation:(ARTProtocolMessage *)message {
    ARTLogDebug(self.logger, @"RT:%p C:%p (%@) handle ANNOTATION message", _realtime, self, self.name);
    // RTL15b
    if (message.channelSerial) {
        self.channelSerial = message.channelSerial;
    }
    [self.annotations onMessage:message];
}

- (void)onSync:(ARTProtocolMessage *)message {
    [self.presence onSync:message];
}

- (void)onError:(ARTProtocolMessage *)msg {
    ARTChannelStateChangeParams *const params = [[ARTChannelStateChangeParams alloc] initWithState:ARTStateError
                                                                                               errorInfo:msg.error];
    [self performTransitionToState:ARTRealtimeChannelFailed withParams:params];
    [self failPendingPresenceWithState:ARTStateError info:msg.error];
}

- (void)onObject:(ARTProtocolMessage *)pm {
    // RTL15b
    if (pm.channelSerial) {
        self.channelSerial = pm.channelSerial;
    }

#ifdef ABLY_SUPPORTS_PLUGINS
    if (!pm.state) {
        // Because the plugin isn't set up or because decoding failed
        return;
    }

    [self.realtime.options.liveObjectsPlugin nosync_handleObjectProtocolMessageWithObjectMessages:pm.state
                                                                                          channel:self];
#endif
}

- (void)onObjectSync:(ARTProtocolMessage *)pm {
#ifdef ABLY_SUPPORTS_PLUGINS
    if (!pm.state) {
        // Because the plugin isn't set up or because decoding failed
        return;
    }

    [self.realtime.options.liveObjectsPlugin nosync_handleObjectSyncProtocolMessageWithObjectMessages:pm.state
                                                                         protocolMessageChannelSerial:pm.channelSerial
                                                                                              channel:self];
#endif
}

- (void)attach {
    [self attach:nil];
}

- (void)attach:(ARTCallback)callback {
    if (callback) {
        ARTCallback userCallback = callback;
        callback = ^(ARTErrorInfo *__nullable error) {
            art_dispatch_async(self->_userQueue, ^{
                userCallback(error);
            });
        };
    }
art_dispatch_sync(_queue, ^{
    [self _attach:callback];
});
}

- (void)_attach:(ARTCallback)callback {
    switch (self.state_nosync) {
        case ARTRealtimeChannelAttaching:
            ARTLogVerbose(self.logger, @"RT:%p C:%p (%@) already attaching", _realtime, self, self.name);
            if (callback) [_attachedEventEmitter once:callback];
            return;
        case ARTRealtimeChannelAttached:
            ARTLogVerbose(self.logger, @"RT:%p C:%p (%@) already attached", _realtime, self, self.name);
            if (callback) callback(nil);
            return;
        default:
            break;
    }
    ARTAttachRequestParams *const params = [[ARTAttachRequestParams alloc] initWithReason:nil];
    [self internalAttach:callback withParams:params];
}

- (void)reattachWithParams:(ARTAttachRequestParams *)params {
    if ([self canBeReattached]) {
        ARTLogDebug(self.logger, @"RT:%p C:%p (%@) %@ and will reattach", _realtime, self, self.name, ARTRealtimeChannelStateToStr(self.state_nosync));
        [self internalAttach:nil withParams:params];
    } else {
        ARTLogDebug(self.logger, @"RT:%p C:%p (%@) %@ should not reattach", _realtime, self, self.name, ARTRealtimeChannelStateToStr(self.state_nosync));
    }
}

- (void)proceedAttachDetachWithParams:(ARTAttachRequestParams *)params {
    if (self.state_nosync == ARTRealtimeChannelDetaching) {
        ARTLogDebug(self.logger, @"RT:%p C:%p (%@) %@ proceeding with detach", _realtime, self, self.name, ARTRealtimeChannelStateToStr(self.state_nosync));
        [self internalDetach:nil];
    } else {
        [self reattachWithParams:params];
    }
}

- (void)internalAttach:(ARTCallback)callback withParams:(ARTAttachRequestParams *)params {
    switch (self.state_nosync) {
        case ARTRealtimeChannelDetaching: {
            ARTLogDebug(self.logger, @"RT:%p C:%p (%@) attach after the completion of Detaching", _realtime, self, self.name);
            [_detachedEventEmitter once:^(ARTErrorInfo *error) {
                [self _attach:callback];
            }];
            return;
        }
        default:
            break;
    }

    _errorReason = nil;

    if (![self.realtime isActive]) {
        ARTLogDebug(self.logger, @"RT:%p C:%p (%@) can't attach when not in an active state", _realtime, self, self.name);
        if (callback) callback([ARTErrorInfo createWithCode:ARTErrorChannelOperationFailed message:@"Can't attach when not in an active state"]);
        return;
    }

    if (callback) [_attachedEventEmitter once:callback];
    // Set state: Attaching
    if (self.state_nosync != ARTRealtimeChannelAttaching) {
        const ARTState state = params.reason ? ARTStateError : ARTStateOk;
        ARTChannelStateChangeParams *const stateChangeParams = [[ARTChannelStateChangeParams alloc] initWithState:state errorInfo:params.reason storeErrorInfo:NO retryAttempt:params.retryAttempt];
        [self performTransitionToState:ARTRealtimeChannelAttaching withParams:stateChangeParams];
    }
    [self attachAfterChecks];
}

- (void)attachAfterChecks {
    ARTProtocolMessage *attachMessage = [[ARTProtocolMessage alloc] init];
    attachMessage.action = ARTProtocolMessageAttach;
    attachMessage.channel = self.name;
    attachMessage.channelSerial = self.channelSerial; // RTL4c1
    attachMessage.params = self.options_nosync.params;
    attachMessage.flags = self.options_nosync.modes;

    if (self.attachResume) {
        attachMessage.flags = attachMessage.flags | ARTProtocolMessageFlagAttachResume;
    }

    [self.realtime send:attachMessage sentCallback:^(ARTErrorInfo *error) {
        if (error) {
            return;
        }
        // Set attach timer after the connection is active
        [[self unlessStateChangesBefore:self.realtime.options.testOptions.realtimeRequestTimeout do:^{
            // Timeout
            ARTErrorInfo *errorInfo = [ARTErrorInfo createWithCode:ARTStateAttachTimedOut message:@"attach timed out"];
            ARTChannelStateChangeParams *const params = [[ARTChannelStateChangeParams alloc] initWithState:ARTStateAttachTimedOut
                                                                                                 errorInfo:errorInfo];
            [self setSuspended:params];
        }] startTimer];
    } ackCallback:nil];
}

- (void)detach:(ARTCallback)callback {
    if (callback) {
        ARTCallback userCallback = callback;
        callback = ^(ARTErrorInfo *__nullable error) {
            art_dispatch_async(self->_userQueue, ^{
                userCallback(error);
            });
        };
    }
art_dispatch_sync(_queue, ^{
    [self _detach:callback];
});
}

- (void)_detach:(ARTCallback)callback {
    switch (self.state_nosync) {
        case ARTRealtimeChannelInitialized:
            ARTLogDebug(self.logger, @"RT:%p C:%p (%@) can't detach when not attached", _realtime, self, self.name);
            if (callback) callback(nil);
            return;
        case ARTRealtimeChannelDetaching:
            ARTLogDebug(self.logger, @"RT:%p C:%p (%@) already detaching", _realtime, self, self.name);
            if (callback) [_detachedEventEmitter once:callback];
            return;
        case ARTRealtimeChannelDetached:
            ARTLogDebug(self.logger, @"RT:%p C:%p (%@) already detached", _realtime, self, self.name);
            if (callback) callback(nil);
            return;
        case ARTRealtimeChannelSuspended: {
            ARTLogDebug(self.logger, @"RT:%p C:%p (%@) transitions immediately to the detached", _realtime, self, self.name);
            ARTChannelStateChangeParams *const params = [[ARTChannelStateChangeParams alloc] initWithState:ARTStateOk];
            [self performTransitionToState:ARTRealtimeChannelDetached withParams:params];
            if (callback) callback(nil);
            return;
        }
        case ARTRealtimeChannelFailed:
            ARTLogDebug(self.logger, @"RT:%p C:%p (%@) can't detach when in a failed state", _realtime, self, self.name);
            if (callback) callback([ARTErrorInfo createWithCode:ARTErrorChannelOperationFailed message:@"can't detach when in a failed state"]);
            return;
        default:
            break;
    }
    [self internalDetach:callback];
}

- (void)internalDetach:(ARTCallback)callback {
    switch (self.state_nosync) {
        case ARTRealtimeChannelAttaching: {
            ARTLogDebug(self.logger, @"RT:%p C:%p (%@) waiting for the completion of the attaching operation", _realtime, self, self.name);
            [_attachedEventEmitter once:^(ARTErrorInfo *errorInfo) {
                if (callback && errorInfo) {
                    callback(errorInfo);
                    return;
                }
                [self _detach:callback];
            }];
            return;
        }
        default:
            break;
    }

    _errorReason = nil;

    if (![self.realtime isActive]) {
        ARTLogDebug(self.logger, @"RT:%p C:%p (%@) can't detach when not in an active state", _realtime, self, self.name);
        if (callback) callback([ARTErrorInfo createWithCode:ARTErrorChannelOperationFailed message:@"Can't detach when not in an active state"]);
        return;
    }

    if (callback) [_detachedEventEmitter once:callback];
    // Set state: Detaching
    ARTChannelStateChangeParams *const params = [[ARTChannelStateChangeParams alloc] initWithState:ARTStateOk];
    [self performTransitionToState:ARTRealtimeChannelDetaching withParams:params];

    [self detachAfterChecks];
}

- (void)detachAfterChecks {
    ARTProtocolMessage *detachMessage = [[ARTProtocolMessage alloc] init];
    detachMessage.action = ARTProtocolMessageDetach;
    detachMessage.channel = self.name;

    [self.realtime send:detachMessage sentCallback:nil ackCallback:nil];

    [[self unlessStateChangesBefore:self.realtime.options.testOptions.realtimeRequestTimeout do:^{
        if (!self.realtime) {
            return;
        }
        // Timeout
        ARTErrorInfo *errorInfo = [ARTErrorInfo createWithCode:ARTStateDetachTimedOut message:@"detach timed out"];
        ARTChannelStateChangeParams *const params = [[ARTChannelStateChangeParams alloc] initWithState:ARTStateAttachTimedOut
                                                                                             errorInfo:errorInfo];
        [self performTransitionToState:ARTRealtimeChannelAttached withParams:params];
        [self->_detachedEventEmitter emit:nil with:errorInfo];
    }] startTimer];

    if (self.presence.syncInProgress_nosync) {
        [self.presence failsSync:[ARTErrorInfo createWithCode:ARTErrorChannelOperationFailed message:@"channel is being DETACHED"]];
    }
}

- (void)detach {
    [self detach:nil];
}

- (NSString *)getClientId {
    return self.realtime.auth.clientId;
}

- (NSString *)clientId_nosync {
    return self.realtime.auth.clientId_nosync;
}

- (void)historyWithWrapperSDKAgents:(nullable NSStringDictionary *)wrapperSDKAgents
                         completion:(ARTPaginatedMessagesCallback)callback {
    [self history:[[ARTRealtimeHistoryQuery alloc] init] wrapperSDKAgents:wrapperSDKAgents callback:callback error:nil];
}

- (BOOL)history:(ARTRealtimeHistoryQuery *)query wrapperSDKAgents:(nullable NSStringDictionary *)wrapperSDKAgents callback:(ARTPaginatedMessagesCallback)callback error:(NSError **)errorPtr {
    query.realtimeChannel = self;
    return [_restChannel history:query wrapperSDKAgents:wrapperSDKAgents callback:callback error:errorPtr];
}

- (void)startDecodeFailureRecoveryWithErrorInfo:(ARTErrorInfo *)error {
    if (_decodeFailureRecoveryInProgress) {
        return;
    }

    ARTLogWarn(self.logger, @"R:%p C:%p (%@) starting delta decode failure recovery process", _realtime, self, self.name);
    _decodeFailureRecoveryInProgress = true;
    ARTAttachRequestParams *const params = [[ARTAttachRequestParams alloc] initWithReason:error];
    [self internalAttach:^(ARTErrorInfo *e) {
        self->_decodeFailureRecoveryInProgress = false;
    } withParams:params];
}

- (NSString *)connectionId {
    return _realtime.connection.id_nosync;
}

- (BOOL)exceedMaxSize:(NSArray<ARTBaseMessage *> *)messages {
    NSInteger size = 0;
    for (ARTMessage *message in messages) {
        size += [message messageSize];
    }
    NSInteger maxSize = _realtime.connection.maxMessageSize;
    return size > maxSize;
}

- (ARTRealtimeChannelOptions *)getOptions {
    return (ARTRealtimeChannelOptions *)[self options];
}

- (ARTRealtimeChannelOptions *)getOptions_nosync {
    return (ARTRealtimeChannelOptions *)[self options_nosync];
}

- (ARTChannelProperties *)properties {
    __block ARTChannelProperties *ret;
    art_dispatch_sync(_queue, ^{
        ret = [self properties_nosync];
    });
    return ret;
}

- (ARTChannelProperties *)properties_nosync {
    return [[ARTChannelProperties alloc] initWithAttachSerial:_attachSerial channelSerial:_channelSerial];
}

- (void)setOptions:(ARTRealtimeChannelOptions *_Nullable)options callback:(nullable ARTCallback)callback {
    if (callback) {
        ARTCallback userCallback = callback;
        callback = ^(ARTErrorInfo *_Nullable error) {
            art_dispatch_async(self->_userQueue, ^{
                userCallback(error);
            });
        };
    }
    art_dispatch_sync(_queue, ^{
        [self setOptions_nosync:options callback:callback];
    });
}

- (void)setOptions_nosync:(ARTRealtimeChannelOptions *_Nullable)options callback:(nullable ARTCallback)callback {
    [self setOptions_nosync:options];
    [self.restChannel setOptions_nosync:options];

    if (!options.modes && !options.params) {
        if (callback)
            callback(nil);
        return;
    }

    switch (self.state_nosync) {
        case ARTRealtimeChannelAttached:
        case ARTRealtimeChannelAttaching: {
            ARTLogDebug(self.logger, @"RT:%p C:%p (%@) set options in %@ state", _realtime, self, self.name, ARTRealtimeChannelStateToStr(self.state_nosync));
            ARTAttachRequestParams *const params = [[ARTAttachRequestParams alloc] initWithReason:nil];
            [self internalAttach:callback withParams:params];
            break;
        }
        default:
            if (callback)
                callback(nil);
            break;
    }
}

- (void)setPluginDataValue:(id)value forKey:(NSString *)key {
    [self.pluginData setValue:value forKey:key];
}

- (id)pluginDataValueForKey:(NSString *)key {
    return self.pluginData[key];
}

@end

#pragma mark - Channel Properties (RTL15)

@implementation ARTChannelProperties

- (instancetype)initWithAttachSerial:(NSString *)attachSerial channelSerial:(NSString *)channelSerial {
    self = [super init];
    if (self) {
        _attachSerial = attachSerial;
        _channelSerial = channelSerial;
    }
    return self;
}

@end

#pragma mark - ARTEvent

@implementation ARTEvent (ChannelEvent)

- (instancetype)initWithChannelEvent:(ARTChannelEvent)value {
    return [self initWithString:[NSString stringWithFormat:@"ARTChannelEvent%@",ARTChannelEventToStr(value)]];
}

+ (instancetype)newWithChannelEvent:(ARTChannelEvent)value {
    return [[self alloc] initWithChannelEvent:value];
}

@end
