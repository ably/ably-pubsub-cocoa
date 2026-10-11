//
//  ARTPubSubClient.m
//
//

#import "ARTPubSubClient+Private.h"
#import "ARTPubSubClient+WrapperSDKProxy.h"

#import "ARTRealtimeChannel+Private.h"
#import "ARTStatus.h"
#import "ARTErrorInfo+Private.h"
#import "ARTDefault.h"
#import "ARTHttpClient+Private.h"
#import "ARTAuth+Private.h"
#import "ARTTokenDetails.h"
#import "ARTMessage.h"
#import "ARTClientOptions.h"
#import "ARTClientOptions+TestConfiguration.h"
#import "ARTClientOptions+Private.h"
#import "ARTTestClientOptions.h"
#import "ARTChannelOptions.h"
#import "ARTPresenceMessage.h"
#import "ARTWebSocketTransport+Private.h"
#import "ARTOSReachability.h"
#import "ARTNSArray+ARTFunctional.h"
#import "ARTProtocolMessage.h"
#import "ARTProtocolMessage+Private.h"
#import "ARTEventEmitter+Private.h"
#import "ARTQueuedMessage.h"
#import "ARTPendingMessage.h"
#import "ARTConnection+Private.h"
#import "ARTConnectionDetails.h"
#import "ARTStats.h"
#import "ARTRealtimeTransport.h"
#import "ARTFallback.h"
#import "ARTFallbackHosts.h"
#import "ARTAuthDetails.h"
#import "ARTGCD.h"
#import "ARTEncoder.h"
#import "ARTRealtimeChannels+Private.h"
#import "ARTPush+Private.h"
#import "ARTQueuedDealloc.h"
#import "ARTTypes.h"
#import "ARTChannels.h"
#import "ARTConstants.h"
#import "ARTCrypto.h"
#import "ARTDeviceIdentityTokenDetails.h"
#import "ARTErrorChecker.h"
#import "ARTConnectionStateChangeParams.h"
#import "ARTChannelStateChangeParams.h"
#import "ARTAttachRequestParams.h"
#import "ARTRetrySequence.h"
#import "ARTBackoffRetryDelayCalculator.h"
#import "ARTTypes+Private.h"
#import "ARTInternalLog.h"
#import "ARTRealtimeTransportFactory.h"
#import "ARTConnectRetryState.h"
#import "ARTWrapperSDKProxyRealtime+Private.h"
#import "ARTConnectionDetails+Private.h"
#import "ARTTimeProvider.h"

@interface ARTConnectionStateChange ()

- (void)setRetryIn:(NSTimeInterval)retryIn;

@end

#pragma mark - ARTPubSubClient implementation

@implementation ARTPubSubClient {
    ARTQueuedDealloc *_dealloc;
}

- (void)internalAsync:(void (^)(ARTPubSubClientInternal * _Nonnull))use {
    art_dispatch_async(_internal.queue, ^{
        use(self->_internal);
    });
}

- (void)internalSync:(void (^)(ARTPubSubClientInternal * _Nonnull))use {
    art_dispatch_sync(_internal.queue, ^{
        use(self->_internal);
    });
}

- (ARTConnection *)connection {
    return [[ARTConnection alloc] initWithInternal:_internal.connection queuedDealloc:_dealloc];
}

- (ARTRealtimeChannels *)channels {
    return [[ARTRealtimeChannels alloc] initWithInternal:_internal.channels pubsubInternal:_internal queuedDealloc:_dealloc];
}

- (ARTAuth *)auth {
    return [[ARTAuth alloc] initWithInternal:_internal.auth queuedDealloc:_dealloc];
}

- (ARTPush *)push {
    return [[ARTPush alloc] initWithInternal:_internal.push queuedDealloc:_dealloc];
}

#if TARGET_OS_IOS
- (ARTLocalDevice *)device {
    return _internal.device;
}
#endif

- (NSString *)clientId {
    return _internal.clientId;
}

- (void)initCommon {
    _dealloc = [[ARTQueuedDealloc alloc] init:_internal queue:_internal.queue];
}

- (instancetype)initWithOptions:(ARTClientOptions *)options {
    self = [super init];
    if (self) {
        _internal = [[ARTPubSubClientInternal alloc] initWithOptions:options];
        [self initCommon];
    }
    return self;
}

- (instancetype)initWithKey:(NSString *)key {
    self = [super init];
    if (self) {
        _internal = [[ARTPubSubClientInternal alloc] initWithKey:key];
        [self initCommon];
    }
    return self;
}

- (instancetype)initWithToken:(NSString *)token {
    self = [super init];
    if (self) {
        _internal = [[ARTPubSubClientInternal alloc] initWithToken:token];
        [self initCommon];
    }
    return self;
}

- (void)time:(ARTDateTimeCallback)cb {
    [_internal timeWithWrapperSDKAgents:nil
                             completion:cb];
}

- (void)request:(NSString *)method
           path:(NSString *)path
         params:(nullable NSStringDictionary *)params
           body:(nullable id)body
        headers:(nullable NSStringDictionary *)headers
       callback:(ARTHTTPPaginatedCallback)callback {
    [_internal request:method path:path params:params body:body headers:headers wrapperSDKAgents:nil callback:callback];
}

- (void)ping:(ARTCallback)cb {
    [_internal ping:cb];
}

- (void)stats:(ARTPaginatedStatsCallback)callback {
    [_internal statsWithWrapperSDKAgents:nil
                                callback:callback];
}

- (void)stats:(nullable ARTStatsQuery *)query callback:(ARTPaginatedStatsCallback)callback {
    [_internal stats:query wrapperSDKAgents:nil callback:callback];
}

- (void)connect {
    [_internal connect];
}

- (void)close {
    [_internal close];
}

@end

@implementation ARTPubSubClient (WrapperSDKProxy)

- (ARTWrapperSDKProxyRealtime *)createWrapperSDKProxyWithOptions:(ARTWrapperSDKProxyOptions *)options {
    return [[ARTWrapperSDKProxyRealtime alloc] initWithPubSub:self
                                                   proxyOptions:options];

}

@end

NS_ASSUME_NONNULL_BEGIN

@interface ARTPubSubClientInternal ()

@property (nonatomic, readonly) ARTConnectRetryState *connectRetryState;
@property (nonatomic, readonly) ARTInternalLog *logger;

/// The time provider used by this client; sourced from `options.testOptions.timeProvider` at `-init` time.
@property (nonatomic, readonly) id<ARTTimeProvider> timeProvider;

// Redeclaration as readwrite
@property (nullable, readwrite, nonatomic) ARTConnectionDetails *latestConnectionDetails;

@end

NS_ASSUME_NONNULL_END

typedef NS_ENUM(NSUInteger, ARTNetworkState) {
    ARTNetworkStateIsUnknown,
    ARTNetworkStateIsReachable,
    ARTNetworkStateIsUnreachable
};

@implementation ARTPubSubClientInternal {
    BOOL _resuming;
    BOOL _renewingToken;
    NSTimeInterval _immediateReconnectionDelay;
    ARTEventEmitter<ARTEvent *, ARTErrorInfo *> *_pingEventEmitter;
    NSDate *_connectionLostAt;
    NSDate *_lastActivity;
    Class _reachabilityClass;
    ARTNetworkState _networkState;
    id<ARTRealtimeTransport> _transport;
    ARTFallback *_fallbacks;
    __weak ARTEventListener *_connectionRetryFromSuspendedListener;
    __weak ARTEventListener *_connectionRetryFromDisconnectedListener;
    __weak ARTEventListener *_connectingTimeoutListener;
    id<ARTSchedulerHandle> _authenitcatingTimeoutWork;
    NSObject<ARTCancellable> *_authTask;
    id<ARTSchedulerHandle> _idleTimer;
    dispatch_queue_t _userQueue;
    dispatch_queue_t _queue;
}

- (instancetype)initWithOptions:(ARTClientOptions *)options {
    self = [super init];
    if (self) {
        NSAssert(options, @"ARTPubSubClient: No options provided");

        _logger = [[ARTInternalLog alloc] initWithClientOptions:options];
        _timeProvider = options.testOptions.timeProvider;
        _rest = [[ARTHttpClientInternal alloc] initWithOptions:options realtime:self logger:_logger];
        _userQueue = _rest.userQueue;
        _queue = _rest.queue;
        _internalEventEmitter = [[ARTInternalEventEmitter alloc] initWithQueue:_rest.queue timeProvider:_timeProvider];
        _connectedEventEmitter = [[ARTInternalEventEmitter alloc] initWithQueue:_rest.queue timeProvider:_timeProvider];
        _pingEventEmitter = [[ARTInternalEventEmitter alloc] initWithQueue:_rest.queue timeProvider:_timeProvider];
        _channels = [[ARTRealtimeChannelsInternal alloc] initWithPubSub:self logger:self.logger];
        _transport = nil;
        _networkState = ARTNetworkStateIsUnknown;
        _reachabilityClass = options.testOptions.reachabilityClass;
        _msgSerial = 0;
        _queuedMessages = [NSMutableArray array];
        _pendingMessages = [NSMutableArray array];
        _pendingMessageStartSerial = 0;
        _pendingAuthorizations = [NSMutableArray array];
        _connection = [[ARTConnectionInternal alloc] initWithPubSub:self logger:self.logger];
        _connectionStateTtl = [ARTDefault connectionStateTtl];
        _immediateReconnectionDelay = 0.1;
        const id<ARTRetryDelayCalculator> connectRetryDelayCalculator = [[ARTBackoffRetryDelayCalculator alloc] initWithInitialRetryTimeout:options.disconnectedRetryTimeout
                                                                                                                 jitterCoefficientGenerator:options.testOptions.jitterCoefficientGenerator];
        _connectRetryState = [[ARTConnectRetryState alloc] initWithRetryDelayCalculator:connectRetryDelayCalculator
                                                                                 logger:_logger
                                                                       logMessagePrefix:[NSString stringWithFormat:@"RT: %p ", self]];
        self.auth.delegate = self;

        [self.connection setState:ARTRealtimeInitialized];

        ARTLogVerbose(self.logger, @"R:%p initialized with RS:%p", self, _rest);

        self.rest.prioritizedHost = nil;

        if (options.recover) {
            NSError *error;
            ARTConnectionRecoveryKey *const recoveryKey = [ARTConnectionRecoveryKey fromJsonString:options.recover error:&error];
            if (error) {
                ARTLogError(self.logger, @"Couldn't construct a recovery key from the string provided: %@", options.recover);
            }
            else {
                _msgSerial = recoveryKey.msgSerial; // RTN16f
                for (NSString *const channelName in recoveryKey.channelSerials) {
                    ARTRealtimeChannelInternal *const channel = [_channels get:channelName];
                    channel.channelSerial = recoveryKey.channelSerials[channelName]; // RTN16j
                }
            }
        }

        if (options.autoConnect) {
            [self connect];
        }
    }
    return self;
}

#pragma mark - ARTAuthDelegate

- (void)auth:(ARTAuthInternal *)auth didAuthorize:(ARTTokenDetails *)tokenDetails completion:(void (^)(ARTAuthorizationState, ARTErrorInfo *_Nullable))completion {
    void (^waitForResponse)(void) = ^{
        [self.pendingAuthorizations art_enqueue:^(ARTRealtimeConnectionState state, ARTErrorInfo *_Nullable error){
            switch (state) {
                case ARTRealtimeConnected:
                    completion(ARTAuthorizationSucceeded, nil);
                    break;
                case ARTRealtimeFailed:
                    completion(ARTAuthorizationFailed, error);
                    break;
                case ARTRealtimeSuspended:
                    completion(ARTAuthorizationFailed, [ARTErrorInfo createWithCode:ARTStateAuthorizationFailed message:@"Connection has been suspended"]);
                    break;
                case ARTRealtimeClosed:
                    completion(ARTAuthorizationFailed, [ARTErrorInfo createWithCode:ARTStateAuthorizationFailed message:@"Connection has been closed"]);
                    break;
                case ARTRealtimeDisconnected:
                    completion(ARTAuthorizationCancelled, nil);
                    break;
                case ARTRealtimeInitialized:
                case ARTRealtimeConnecting:
                case ARTRealtimeClosing:
                    ARTLogDebug(self.logger, @"RS:%p authorize completion has been ignored because the connection state is unexpected (%@)", self.rest, ARTRealtimeConnectionStateToStr(state));
                    break;
            }
        }];
    };

    void (^haltCurrentConnectionAndReconnect)(void) = ^{
        // Halt the current connection and reconnect with the most recent token
        ARTLogDebug(self.logger, @"RS:%p halt current connection and reconnect with %@", self.rest, tokenDetails);
        [self abortAndReleaseTransport:[ARTStatus state:ARTStateOk]];
        [self setTransportWithResumeKey:self->_transport.resumeKey];
        [self->_transport connectWithToken:tokenDetails.token];
        [self cancelAllPendingAuthorizations];
        waitForResponse();
    };

    switch (self.connection.state_nosync) {
        case ARTRealtimeConnected: {
            // Update (send AUTH message)
            ARTLogDebug(self.logger, @"RS:%p AUTH message using %@", self.rest, tokenDetails);
            ARTProtocolMessage *msg = [[ARTProtocolMessage alloc] init];
            msg.action = ARTProtocolMessageAuth;
            msg.auth = [[ARTAuthDetails alloc] initWithToken:tokenDetails.token];
            [self send:msg sentCallback:nil ackCallback:nil];
            waitForResponse();
            break;
        }
        case ARTRealtimeConnecting: {
            [_transport.stateEmitter once:[ARTEvent newWithTransportState:ARTRealtimeTransportStateOpened] callback:^(id sender) {
                haltCurrentConnectionAndReconnect();
            }];
            break;
        }
        case ARTRealtimeClosing: {
            // Should ignore because the connection is being closed
            ARTLogDebug(self.logger, @"RS:%p authorize has been cancelled because the connection is closing", self.rest);
            [self cancelAllPendingAuthorizations];
            break;
        }
        default: {
            // Client state is NOT Connecting or Connected, so it should start a new connection
            ARTLogDebug(self.logger, @"RS:%p new connection from successfull authorize %@", self.rest, tokenDetails);
            [self performTransitionToState:ARTRealtimeConnecting withParams:[[ARTConnectionStateChangeParams alloc] init]];
            waitForResponse();
            break;
        }
    }
}

- (void)performPendingAuthorizationWithState:(ARTRealtimeConnectionState)state error:(nullable ARTErrorInfo *)error {
    void (^pendingAuthorization)(ARTRealtimeConnectionState, ARTErrorInfo *_Nullable) = [self.pendingAuthorizations art_dequeue];
    if (!pendingAuthorization) {
        return;
    }
    switch (state) {
        case ARTRealtimeConnected:
            pendingAuthorization(state, nil);
            break;
        case ARTRealtimeFailed:
            pendingAuthorization(state, error);
            break;
        default:
            [self discardPendingAuthorizations];
            pendingAuthorization(state, error);
            break;
    }
}

- (void)cancelAllPendingAuthorizations {
    [self.pendingAuthorizations enumerateObjectsUsingBlock:^(void (^pendingAuthorization)(ARTRealtimeConnectionState, ARTErrorInfo * _Nullable), NSUInteger idx, BOOL * _Nonnull stop) {
        pendingAuthorization(ARTRealtimeDisconnected, nil);
    }];
    [self.pendingAuthorizations removeAllObjects];
}

- (void)discardPendingAuthorizations {
    [self.pendingAuthorizations removeAllObjects];
}

#pragma mark - Realtime

- (instancetype)initWithKey:(NSString *)key {
    return [self initWithOptions:[[ARTClientOptions alloc] initWithKey:key]];
}

- (instancetype)initWithToken:(NSString *)token {
    return [self initWithOptions:[[ARTClientOptions alloc] initWithToken:token]];
}

- (id<ARTRealtimeTransport>)transport {
    return _transport;
}

- (ARTClientOptions *)getClientOptions {
    return _rest.options;
}

- (NSString *)clientId {
    // RTC17
    return _rest.auth.clientId;
}

- (NSString *)description {
    NSString *info;
    if (self.options.token) {
        info = [NSString stringWithFormat:@"token: %@", self.options.token];
    }
    else if (self.options.authUrl) {
        info = [NSString stringWithFormat:@"authUrl: %@", self.options.authUrl];
    }
    else if (self.options.authCallback) {
        info = [NSString stringWithFormat:@"authCallback: %@", self.options.authCallback];
    }
    else {
        info = [NSString stringWithFormat:@"key: %@", self.options.key];
    }
    return [NSString stringWithFormat:@"%@ - \n\t %@;", [super description], info];
}

- (ARTAuthInternal *)auth {
    return self.rest.auth;
}

- (ARTPushInternal *)push {
    return self.rest.push;
}

- (void)dealloc {
    ARTLogVerbose(self.logger, @"R:%p dealloc", self);

    self.rest.prioritizedHost = nil;
}

- (void)connect {
    art_dispatch_sync(_queue, ^{
        [self _connect];
    });
}

- (void)_connect {
    if (self.connection.state_nosync == ARTRealtimeConnecting) {
        ARTLogError(self.logger, @"R:%p Ignoring new connection attempt - already in the CONNECTING state.", self);
        return;
    }
    if (self.connection.state_nosync == ARTRealtimeClosing) {
        // New connection
        _transport = nil;
    }
    [self performTransitionToState:ARTRealtimeConnecting withParams:[[ARTConnectionStateChangeParams alloc] init]];
}

- (void)close {
    art_dispatch_sync(_queue, ^{
        [self _close];
    });
}

- (void)_close {
    [self setReachabilityActive:NO];
    [self cancelTimers];

    switch (self.connection.state_nosync) {
        case ARTRealtimeInitialized:
        case ARTRealtimeClosing:
        case ARTRealtimeClosed:
        case ARTRealtimeFailed:
            return;
        case ARTRealtimeConnecting: {
            [_internalEventEmitter once:^(ARTConnectionStateChange *change) {
                [self _close];
            }];
            return;
        }
        case ARTRealtimeDisconnected:
        case ARTRealtimeSuspended:
            [self performTransitionToState:ARTRealtimeClosed withParams:[[ARTConnectionStateChangeParams alloc] init]];
            break;
        case ARTRealtimeConnected:
            [self performTransitionToState:ARTRealtimeClosing withParams:[[ARTConnectionStateChangeParams alloc] init]];
            break;
    }
}

- (void)timeWithWrapperSDKAgents:(nullable NSStringDictionary *)wrapperSDKAgents
                      completion:(ARTDateTimeCallback)cb {
    [self.rest timeWithWrapperSDKAgents:wrapperSDKAgents
                             completion:cb];
}

- (void)request:(NSString *)method
           path:(NSString *)path
         params:(nullable NSStringDictionary *)params
           body:(nullable id)body
        headers:(nullable NSStringDictionary *)headers
wrapperSDKAgents:(nullable NSStringDictionary *)wrapperSDKAgents
       callback:(ARTHTTPPaginatedCallback)callback {
    [self.rest request:method path:path params:params body:body headers:headers wrapperSDKAgents:wrapperSDKAgents callback:callback];
}

- (void)ping:(ARTCallback) cb {
    if (cb) {
        ARTCallback userCallback = cb;
        cb = ^(ARTErrorInfo *_Nullable error) {
            art_dispatch_async(self->_userQueue, ^{
                userCallback(error);
            });
        };
    }

    art_dispatch_async(_queue, ^{
        switch (self.connection.state_nosync) {
            case ARTRealtimeInitialized:
            case ARTRealtimeSuspended:
            case ARTRealtimeClosing:
            case ARTRealtimeClosed:
            case ARTRealtimeFailed:
                cb([ARTErrorInfo createWithCode:0 status:ARTStateConnectionFailed message:[NSString stringWithFormat:@"Can't ping a %@ connection", ARTRealtimeConnectionStateToStr(self.connection.state_nosync)]]);
                return;
            case ARTRealtimeConnecting:
            case ARTRealtimeDisconnected:
            case ARTRealtimeConnected:
                if (![self shouldSendEvents]) {
                    [self->_connectedEventEmitter once:^(NSNull *n) {
                        [self ping:cb];
                    }];
                    return;
                }
                [[[self->_pingEventEmitter once:cb] setTimer:self.options.realtimeRequestTimeout onTimeout:^{
                    ARTLogVerbose(self.logger, @"R:%p ping timed out", self);
                    cb([ARTErrorInfo createWithCode:ARTErrorConnectionTimedOut status:ARTStateConnectionFailed message:@"timed out"]);
                }] startTimer];
                [self.transport sendPing];
        }
    });
}

- (void)statsWithWrapperSDKAgents:(nullable NSStringDictionary *)wrapperSDKAgents
                         callback:(ARTPaginatedStatsCallback)callback {
    [self stats:[[ARTStatsQuery alloc] init] wrapperSDKAgents:wrapperSDKAgents callback:callback];
}

- (void)stats:(ARTStatsQuery *)query wrapperSDKAgents:(nullable NSStringDictionary *)wrapperSDKAgents callback:(ARTPaginatedStatsCallback)callback {
    [self.rest stats:query wrapperSDKAgents:wrapperSDKAgents callback:callback];
}

- (void)performTransitionToDisconnectedOrSuspendedWithParams:(ARTConnectionStateChangeParams *)params {
    if ([self isSuspendMode]) {
        [self performTransitionToState:ARTRealtimeSuspended withParams:params];
    }
    else {
        [self performTransitionToState:ARTRealtimeDisconnected withParams:params];
    }
}

- (void)updateWithErrorInfo:(nullable ARTErrorInfo *)errorInfo {
    ARTLogDebug(self.logger, @"R:%p update requested", self);

    if (self.connection.state_nosync != ARTRealtimeConnected) {
        ARTLogWarn(self.logger, @"R:%p update ignored because connection is not connected", self);
        return;
    }

    ARTConnectionStateChangeParams *const params = [[ARTConnectionStateChangeParams alloc] initWithErrorInfo:errorInfo];
    [self performTransitionToState:ARTRealtimeConnected withParams:params];
}

- (void)didChangeNetworkStateFromState:(ARTNetworkState)previousState {
    if (_networkState == ARTNetworkStateIsReachable) {
        switch (_connection.state_nosync) {
            case ARTRealtimeConnecting: {
                if (previousState == ARTNetworkStateIsUnreachable) {
                    [self transportReconnectWithExistingParameters];
                }
                break;
            }
            case ARTRealtimeDisconnected:
            case ARTRealtimeSuspended:
                [self performTransitionToState:ARTRealtimeConnecting withParams:[[ARTConnectionStateChangeParams alloc] init]];
            default:
                break;
        }
    }
    else {
        switch (_connection.state_nosync) {
            case ARTRealtimeConnecting:
            case ARTRealtimeConnected: {
                ARTErrorInfo *unreachable = [ARTErrorInfo createWithCode:-1003 message:@"unreachable host"];
                ARTConnectionStateChangeParams *const params = [[ARTConnectionStateChangeParams alloc] initWithErrorInfo:unreachable];
                [self performTransitionToDisconnectedOrSuspendedWithParams:params];
                break;
            }
            default:
                break;
        }
    }
}

- (void)setReachabilityActive:(BOOL)active {
    if (active && _reachability == nil) {
        _reachability = [[_reachabilityClass alloc] initWithLogger:self.logger queue:_queue];
    }
    if (active) {
        __weak ARTPubSubClientInternal *weakSelf = self;
        [_reachability listenForHost:[_transport host] callback:^(BOOL reachable) {
            ARTPubSubClientInternal *strongSelf = weakSelf;
            if (!strongSelf) return;

            ARTNetworkState previousState = strongSelf->_networkState;
            strongSelf->_networkState = reachable ? ARTNetworkStateIsReachable : ARTNetworkStateIsUnreachable;
            [strongSelf didChangeNetworkStateFromState:previousState];
        }];
    }
    else {
        [_reachability off];
        _networkState = ARTNetworkStateIsUnknown;
    }
}

- (void)clearConnectionStateIfInactive {
    NSTimeInterval intervalSinceLast = [[_timeProvider wallClockNow] timeIntervalSinceDate:_lastActivity];
    if (intervalSinceLast > (_maxIdleInterval + _connectionStateTtl)) {
        [self.connection setId:nil];
        [self.connection setKey:nil];
    }
}

- (void)performTransitionToState:(ARTRealtimeConnectionState)state withParams:(ARTConnectionStateChangeParams *)params {
    ARTChannelStateChangeParams *channelStateChangeParams = nil;
    ARTEventListener *stateChangeEventListener = nil;

    ARTLogVerbose(self.logger, @"R:%p realtime state transitions to %tu - %@%@", self, state, ARTRealtimeConnectionStateToStr(state), params.retryAttempt ? [NSString stringWithFormat: @" (result of %@)", params.retryAttempt.id] : @"");

    ARTRealtimeConnectionEvent event = state == self.connection.state_nosync ? ARTRealtimeConnectionEventUpdate : (ARTRealtimeConnectionEvent)state;

    ARTConnectionStateChange *stateChange = [[ARTConnectionStateChange alloc] initWithCurrent:state
                                                                                     previous:self.connection.state_nosync
                                                                                        event:event
                                                                                       reason:params.errorInfo
                                                                                      retryIn:0
                                                                                 retryAttempt:params.retryAttempt];

    ARTLogDebug(self.logger, @"RT:%p realtime is transitioning from %tu - %@ to %tu - %@", self, stateChange.previous, ARTRealtimeConnectionStateToStr(stateChange.previous), stateChange.current, ARTRealtimeConnectionStateToStr(stateChange.current));

    [self.connection setState:state];
    [self.connection setErrorReason:params.errorInfo];

    [self.connectRetryState connectionWillTransitionToState:stateChange.current];

    switch (stateChange.current) {
        case ARTRealtimeConnecting: {

            // RTN15g We want to enforce a new connection also when there hasn't been activity for longer than (idle interval + TTL)
            if (stateChange.previous == ARTRealtimeDisconnected || stateChange.previous == ARTRealtimeSuspended) {
                [self clearConnectionStateIfInactive];
            }

            stateChangeEventListener = [self unlessStateChangesBefore:self.options.realtimeRequestTimeout do:^{
                [self onConnectionTimeOut];
            }];
            _connectingTimeoutListener = stateChangeEventListener;

            BOOL usingFallback = NO;

            if (_fallbacks != nil) {
                usingFallback = [self reconnectWithFallback]; // RTN17j
            }
            if (!usingFallback) {
                if (!_transport) {
                    BOOL resume = stateChange.previous == ARTRealtimeFailed ||
                                  stateChange.previous == ARTRealtimeDisconnected ||
                                  stateChange.previous == ARTRealtimeSuspended;
                    [self createAndConnectTransportWithConnectionResume:resume];
                }
                // Connecting can fail synchronously (e.g. the token can't be renewed), running a nested
                // transition that changes the state and releases the transport before we get here
                if (self.connection.state_nosync == ARTRealtimeConnecting && _transport) {
                    [self setReachabilityActive:YES];
                }
            }

            break;
        }
        case ARTRealtimeClosing: {
            [self stopIdleTimer];
            [self setReachabilityActive:NO];
            stateChangeEventListener = [self unlessStateChangesBefore:self.options.realtimeRequestTimeout do:^{
                [self performTransitionToState:ARTRealtimeClosed withParams:[[ARTConnectionStateChangeParams alloc] init]];
            }];
            [self.transport sendClose];
            break;
        }
        case ARTRealtimeClosed:
            [self stopIdleTimer];
            [self setReachabilityActive:NO];
            [self closeAndReleaseTransport];
            _connection.key = nil;
            _connection.id = nil;
            _transport = nil;
            _fallbacks = nil;
            self.rest.prioritizedHost = nil;
            [self.auth cancelAuthorization:nil];
            [self failPendingMessages:[ARTStatus state:ARTStateError info:[ARTErrorInfo createWithCode:ARTErrorConnectionClosed message:@"connection broken before receiving publishing acknowledgment"]]];
            break;
        case ARTRealtimeFailed: {
            ARTStatus *const status = [ARTStatus state:ARTStateConnectionFailed info:stateChange.reason];
            channelStateChangeParams = [[ARTChannelStateChangeParams alloc] initWithState:status.state errorInfo:status.errorInfo];
            [self abortAndReleaseTransport:status];
            _fallbacks = nil;
            self.rest.prioritizedHost = nil;
            [self.auth cancelAuthorization:stateChange.reason];
            [self failPendingMessages:[ARTStatus state:ARTStateError info:[ARTErrorInfo createWithCode:ARTErrorConnectionFailed message:@"connection broken before receiving publishing acknowledgment"]]];
            break;
        }
        case ARTRealtimeDisconnected: {
            [self closeAndReleaseTransport];
            if (!_connectionLostAt) {
                _connectionLostAt = [_timeProvider wallClockNow];
                ARTLogVerbose(self.logger, @"RT:%p set connection lost time; expected suspension at %@ (ttl=%f)", self, [self suspensionTime], self.connectionStateTtl);
            }

            NSTimeInterval retryDelay;
            ARTRetryAttempt *retryAttempt;

            // Immediate reconnection as per internal discussion:
            // https://ably-real-time.slack.com/archives/CURL4U2FP/p1742211172312389?thread_ts=1741387920.007779&cid=CURL4U2FP
            // See comment to `testRTN14dAndRTB1` test function for details
            if (stateChange.previous == ARTRealtimeConnected || _fallbacks != nil) {
                retryDelay = _immediateReconnectionDelay; // RTN15a, RTN15h3
            }
            else {
                retryAttempt = [self.connectRetryState addRetryAttempt];
                retryDelay = retryAttempt.delay;
            }
            [stateChange setRetryIn:retryDelay];
            ARTLogVerbose(self.logger, @"RT:%p expecting retry in %f seconds...", self, retryDelay);
            stateChangeEventListener = [self unlessStateChangesBefore:stateChange.retryIn do:^{
                self->_connectionRetryFromDisconnectedListener = nil;
                ARTConnectionStateChangeParams *const params = [[ARTConnectionStateChangeParams alloc] initWithErrorInfo:nil retryAttempt:retryAttempt];
                [self performTransitionToState:ARTRealtimeConnecting withParams:params];
            }];
            _connectionRetryFromDisconnectedListener = stateChangeEventListener;
            break;
        }
        case ARTRealtimeSuspended: {
            _fallbacks = nil; // RTN17i - "must always prefer the primary domain", thus resetting fallbacks to start connection sequence again with the primary domain
            [_connectionRetryFromDisconnectedListener stopTimer];
            _connectionRetryFromDisconnectedListener = nil;
            [self.auth cancelAuthorization:nil];
            [self closeAndReleaseTransport];
            [stateChange setRetryIn:self.options.suspendedRetryTimeout];
            stateChangeEventListener = [self unlessStateChangesBefore:stateChange.retryIn do:^{
                self->_connectionRetryFromSuspendedListener = nil;
                [self performTransitionToState:ARTRealtimeConnecting withParams:[[ARTConnectionStateChangeParams alloc] init]];
            }];
            _connectionRetryFromSuspendedListener = stateChangeEventListener;
            break;
        }
        case ARTRealtimeConnected: {
            _fallbacks = nil; // RTN17i
            _connectionLostAt = nil;
            self.options.recover = nil; // RTN16k
            [self resendPendingMessagesWithResumed:params.resumed]; // RTN19a1
            [_connectedEventEmitter emit:nil with:nil];
            break;
        }
        case ARTRealtimeInitialized:
            break;
    }

    // If there's a channels.release() going on waiting on this channel
    // to detach, doing those operations on it here would fire its event listener and
    // immediately remove the channel from the channels dictionary, thus
    // invalidating the iterator and causing a crashing.
    //
    // So copy the channels and operate on them later, when we're done using the iterator.
    NSMutableArray<ARTRealtimeChannelInternal *> * const channels = [[NSMutableArray alloc] init];
    for (ARTRealtimeChannelInternal *channel in self.channels.nosyncIterable) {
        [channels addObject:channel];
    }

    if ([self shouldSendEvents]) {
        for (ARTRealtimeChannelInternal *channel in channels) {
            ARTAttachRequestParams *const params = [[ARTAttachRequestParams alloc] initWithReason:stateChange.reason];
            [channel proceedAttachDetachWithParams:params];
        }
        [self sendQueuedMessages];
    }
    else if (!self.isActive) {
        if (!channelStateChangeParams) {
            if (stateChange.reason) {
                channelStateChangeParams = [[ARTChannelStateChangeParams alloc] initWithState:ARTStateError
                                                                                    errorInfo:stateChange.reason];
            } else {
                channelStateChangeParams = [[ARTChannelStateChangeParams alloc] initWithState:ARTStateError];
            }
        }

        ARTStatus *const channelStatus = [ARTStatus state:channelStateChangeParams.state info:channelStateChangeParams.errorInfo];
        [self failQueuedMessages:channelStatus];

        // Channels
        for (ARTRealtimeChannelInternal *channel in channels) {
            switch (stateChange.current) {
                case ARTRealtimeClosing:
                    //do nothing. Closed state is coming.
                    break;
                case ARTRealtimeClosed: {
                    ARTChannelStateChangeParams *const params = [[ARTChannelStateChangeParams alloc] initWithState:ARTStateOk];
                    [channel detachChannel:params];
                    break;
                }
                case ARTRealtimeSuspended: {
                    [channel setSuspended:channelStateChangeParams];
                    break;
                }
                case ARTRealtimeFailed: {
                    [channel setFailed:channelStateChangeParams];
                    break;
                }
                default:
                    break;
            }
        }
    }

    [self.connection emit:stateChange.event with:stateChange];

    [self performPendingAuthorizationWithState:stateChange.current error:stateChange.reason];

    [_internalEventEmitter emit:[ARTEvent newWithConnectionEvent:(ARTRealtimeConnectionEvent)state] with:stateChange];

    // stateChangeEventListener may be nil if we're in a failed state
    if (stateChangeEventListener != nil) {
        [stateChangeEventListener startTimer];
    }
}

- (void)createAndConnectTransportWithConnectionResume:(BOOL)resume {
    NSString *resumeKey = nil;
    if (resume) {
        resumeKey = self.connection.key_nosync;
        _resuming = true;
    }
    [self setTransportWithResumeKey:resumeKey];
    [self transportConnectForcingNewToken:_renewingToken newConnection:true];
}

- (void)abortAndReleaseTransport:(ARTStatus *)status {
    [_transport abort:status];
    _transport = nil;
}

- (void)closeAndReleaseTransport {
    if (_transport) {
        [_transport close];
        _transport = nil;
    }
}

- (void)resetTransportWithResumeKey:(NSString *const)resumeKey {
    [self closeAndReleaseTransport];
    [self setTransportWithResumeKey:resumeKey];
}

- (void)setTransportWithResumeKey:(NSString *)resumeKey {
    const id<ARTRealtimeTransportFactory> factory = self.options.testOptions.transportFactory;
    _transport = [factory transportWithRest:self.rest options:self.options resumeKey:resumeKey logger:self.logger];
    _transport.delegate = self;
}

- (ARTEventListener *)unlessStateChangesBefore:(NSTimeInterval)deadline do:(void(^)(void))callback __attribute__((warn_unused_result)) {
    return [[_internalEventEmitter once:^(ARTConnectionStateChange *change) {
        // Any state change cancels the timeout.
    }] setTimer:deadline onTimeout:^{
        if (callback) {
            callback();
        }
    }];
}

- (void)onHeartbeat {
    ARTLogVerbose(self.logger, @"R:%p heartbeat received", self);
    if(self.connection.state_nosync != ARTRealtimeConnected) {
        NSString *msg = [NSString stringWithFormat:@"received a ping when in state %@", ARTRealtimeConnectionStateToStr(self.connection.state_nosync)];
        ARTLogWarn(self.logger, @"R:%p %@", self, msg);
    }
    [_pingEventEmitter emit:nil with:nil];
}

- (void)onConnected:(ARTProtocolMessage *)message {
    _renewingToken = false;

    switch (self.connection.state_nosync) {
        case ARTRealtimeConnecting: {
            if (_resuming) {
                if ([message.connectionId isEqualToString:self.connection.id_nosync]) {
                    ARTLogDebug(self.logger, @"RT:%p connection \"%@\" has reconnected and resumed successfully", self, message.connectionId);
                }
                else {
                    ARTLogWarn(self.logger, @"RT:%p connection \"%@\" has reconnected, but resume failed. Error: \"%@\"", self, message.connectionId, message.error.message);
                }
            }
            // If there's no previous connectionId, then don't reset the msgSerial
            //as it may have been set by recover data (unless the recover failed).
            NSString *prevConnId = self.connection.id_nosync;
            BOOL connIdChanged = prevConnId && ![message.connectionId isEqualToString:prevConnId];
            BOOL recoverFailure = !prevConnId && message.error; // RTN16d
            BOOL resumed = !(connIdChanged || recoverFailure);
            if (!resumed) {
                ARTLogDebug(self.logger, @"RT:%p msgSerial of connection \"%@\" has been reset", self, self.connection.id_nosync);
                self.msgSerial = 0;
                self.pendingMessageStartSerial = 0;
            }

            [self.connection setId:message.connectionId];
            [self.connection setKey:message.connectionKey];
            [self.connection setMaxMessageSize:message.connectionDetails.maxMessageSize];

            if (message.connectionDetails && message.connectionDetails.connectionStateTtl) {
                _connectionStateTtl = message.connectionDetails.connectionStateTtl;
            }
            if (message.connectionDetails && message.connectionDetails.maxIdleInterval) {
                _maxIdleInterval = message.connectionDetails.maxIdleInterval;
                _lastActivity = [_timeProvider wallClockNow];
                [self setIdleTimer];
            }
            ARTConnectionStateChangeParams *const params = [[ARTConnectionStateChangeParams alloc] initWithErrorInfo:message.error];
            params.resumed = resumed;  // RTN19a
            [self performTransitionToState:ARTRealtimeConnected withParams:params];

            break;
        }
        case ARTRealtimeConnected: {
            // Renewing token.
            [self updateWithErrorInfo:message.error];
        }
        default:
            break;
    }

    _resuming = false;
}

- (void)onDisconnected {
    [self onDisconnected:nil];
}

- (void)onDisconnected:(ARTProtocolMessage *)message {
    ARTLogInfo(self.logger, @"R:%p Realtime disconnected", self);
    ARTErrorInfo * const error = message.error;

    if (
        [self isTokenError:error]
        && !_renewingToken // If already reconnecting, give up.
        ) {
        if (![self.auth tokenIsRenewable]) {
            ARTConnectionStateChangeParams *const params = [[ARTConnectionStateChangeParams alloc] initWithErrorInfo:error];
            [self performTransitionToState:ARTRealtimeFailed withParams:params];
            return;
        }

        ARTConnectionStateChangeParams *const params = [[ARTConnectionStateChangeParams alloc] initWithErrorInfo:error];
        [self performTransitionToDisconnectedOrSuspendedWithParams:params];
        [self.connection setErrorReason:nil];
        _renewingToken = true;
        [self performTransitionToState:ARTRealtimeConnecting withParams:[[ARTConnectionStateChangeParams alloc] init]];
        return;
    }

    ARTConnectionStateChangeParams *const params = [[ARTConnectionStateChangeParams alloc] initWithErrorInfo:error];
    [self performTransitionToDisconnectedOrSuspendedWithParams:params];
}

- (void)onClosed {
    ARTLogInfo(self.logger, @"R:%p Realtime closed", self);
    switch (self.connection.state_nosync) {
        case ARTRealtimeClosed:
            break;
        case ARTRealtimeClosing:
            [self.connection setId:nil];
            [self performTransitionToState:ARTRealtimeClosed withParams:[[ARTConnectionStateChangeParams alloc] init]];
            break;
        default:
            NSAssert(false, @"Invalid Realtime state transitioning to Closed: expected Closing or Closed, has %@", ARTRealtimeConnectionStateToStr(self.connection.state_nosync));
            break;
    }
}

- (void)onAuth {
    ARTLogInfo(self.logger, @"R:%p server has requested an authorize", self);
    switch (self.connection.state_nosync) {
        case ARTRealtimeConnecting:
        case ARTRealtimeConnected:
            [self transportConnectForcingNewToken:true newConnection:false];
            break;
        default:
            ARTLogError(self.logger, @"Invalid Realtime state: expected Connecting or Connected, has %@", ARTRealtimeConnectionStateToStr(self.connection.state_nosync));
            break;
    }
}

- (void)onError:(ARTProtocolMessage *)message {
    if (message.channel) {
        [self onChannelMessage:message];
    } else {
        ARTErrorInfo *error = message.error;

        if ([self isTokenError:error] && [self.auth tokenIsRenewable]) {
            if (_renewingToken) {
                // Already retrying; give up.
                [self.connection setErrorReason:error];
                ARTConnectionStateChangeParams *const params = [[ARTConnectionStateChangeParams alloc] initWithErrorInfo:error];
                [self performTransitionToDisconnectedOrSuspendedWithParams:params];
                return;
            }
            [self transportReconnectWithRenewedToken];
            return;
        }

        [self.connection setId:nil];
        ARTConnectionStateChangeParams *const params = [[ARTConnectionStateChangeParams alloc] initWithErrorInfo:message.error];
        [self performTransitionToState:ARTRealtimeFailed withParams:params];
    }
}

- (void)cancelTimers {
    ARTLogVerbose(self.logger, @"R:%p cancel timers", self);
    [_connectionRetryFromSuspendedListener stopTimer];
    _connectionRetryFromSuspendedListener = nil;
    [_connectionRetryFromDisconnectedListener stopTimer];
    _connectionRetryFromDisconnectedListener = nil;
    // Cancel connecting scheduled work
    [_connectingTimeoutListener stopTimer];
    _connectingTimeoutListener = nil;
    // Cancel auth scheduled work
    [_authenitcatingTimeoutWork cancel];
    _authenitcatingTimeoutWork = nil;
    [_authTask cancel];
    _authTask = nil;
    // Idle timer
    [self stopIdleTimer];
    // Ping timer
    [_pingEventEmitter off];
}

- (void)onConnectionTimeOut {
    ARTLogVerbose(self.logger, @"R:%p connection timed out", self);
    // Cancel connecting scheduled work
    [_connectingTimeoutListener stopTimer];
    _connectingTimeoutListener = nil;
    // Cancel auth scheduled work
    [_authenitcatingTimeoutWork cancel];
    _authenitcatingTimeoutWork = nil;
    [_authTask cancel];
    _authTask = nil;

    ARTErrorInfo *error;
    if (self.auth.authorizing_nosync && (self.options.authUrl || self.options.authCallback)) {
        error = [ARTErrorInfo createWithCode:ARTErrorAuthConfiguredProviderFailure status:ARTStateConnectionFailed message:@"timed out"];
    }
    else {
        error = [ARTErrorInfo createWithCode:ARTErrorConnectionTimedOut status:ARTStateConnectionFailed message:@"timed out"];
    }
    switch (self.connection.state_nosync) {
        case ARTRealtimeConnected: {
            ARTConnectionStateChangeParams *const params = [[ARTConnectionStateChangeParams alloc] initWithErrorInfo:error];
            [self performTransitionToState:ARTRealtimeConnected withParams:params];
            break;
        }
        default: {
            ARTConnectionStateChangeParams *const params = [[ARTConnectionStateChangeParams alloc] initWithErrorInfo:error];
            [self performTransitionToDisconnectedOrSuspendedWithParams:params];
            break;
        }
    }
}

- (BOOL)isTokenError:(nullable ARTErrorInfo *)error {
    return error != nil && [[[ARTDefaultErrorChecker alloc] init] isTokenError:error];
}

- (void)transportReconnectWithExistingParameters {
    [self resetTransportWithResumeKey:_transport.resumeKey];
    NSString *host = [self getClientOptions].testOptions.reconnectionRealtimeHost; // for tests purposes only, always `nil` in production
    if (host != nil) {
        [self.transport setHost:host];
    }
    [self transportConnectForcingNewToken:false newConnection:true];
}

- (void)transportReconnectWithHost:(NSString *)host {
    [self resetTransportWithResumeKey:_transport.resumeKey];
    [self.transport setHost:host];
    [self transportConnectForcingNewToken:false newConnection:true];
}

- (void)transportReconnectWithRenewedToken {
    _renewingToken = true;
    [self resetTransportWithResumeKey:_transport.resumeKey];
    [_connectingTimeoutListener restartTimer];
    [self transportConnectForcingNewToken:true newConnection:true];
}

- (void)transportConnectForcingNewToken:(BOOL)forceNewToken newConnection:(BOOL)newConnection {
    ARTClientOptions *options = [self.options copy];
    if ([options isBasicAuth]) {
        // Basic
        [self.transport connectWithKey:options.key];
    }
    else {
        // Token
        ARTLogDebug(self.logger, @"R:%p connecting with token auth; authorising (timeout of %f)", self, self.options.realtimeRequestTimeout);

        if (!forceNewToken && [self.auth tokenRemainsValid]) {
            // Reuse token
            ARTLogDebug(self.logger, @"R:%p reusing token for auth", self);
            [self.transport connectWithToken:self.auth.tokenDetails.token];
        }
        else {
            // New Token
            [self.auth setTokenDetails:nil];

            // Schedule timeout handler
            _authenitcatingTimeoutWork = [_timeProvider scheduleAfter:self.options.realtimeRequestTimeout queue:_rest.queue block:^{
                [self onConnectionTimeOut];
            }];

            id<ARTAuthDelegate> delegate = self.auth.delegate;
            if (newConnection) {
                // Deactivate use of `ARTAuthDelegate`: `authorize` should complete without waiting for a CONNECTED state.
                self.auth.delegate = nil;
            }
            @try {
                _authTask = [self.auth _authorize:nil options:options callback:^(ARTTokenDetails *tokenDetails, NSError *error) {
                    // Cancel scheduled work
                    [self->_authenitcatingTimeoutWork cancel];
                    self->_authenitcatingTimeoutWork = nil;
                    self->_authTask = nil;

                    // It's still valid?
                    switch (self.connection.state_nosync) {
                        case ARTRealtimeClosing:
                        case ARTRealtimeClosed:
                            return;
                        default:
                            break;
                    }

                    ARTLogDebug(self.logger, @"R:%p authorized: %@ error: %@", self, tokenDetails, error);
                    if (error) {
                        [self handleTokenAuthError:error];
                        return;
                    }

                    if (forceNewToken && newConnection) {
                        [self resetTransportWithResumeKey:self->_transport.resumeKey];
                    }
                    if (newConnection) {
                        [self.transport connectWithToken:tokenDetails.token];
                    }
                }];
            }
            @finally {
                self.auth.delegate = delegate;
            }
        }
    }
}

- (void)handleTokenAuthError:(NSError *)error {
    ARTLogError(self.logger, @"R:%p token auth failed with %@", self, error.description);
    if (error.code == ARTErrorIncompatibleCredentials) {
        // RSA15c
        ARTErrorInfo *const errorInfo = [ARTErrorInfo createFromNSError:error];
        ARTConnectionStateChangeParams *const params = [[ARTConnectionStateChangeParams alloc] initWithErrorInfo:errorInfo];
        [self performTransitionToState:ARTRealtimeFailed withParams:params];
    }
    else if (self.options.authUrl || self.options.authCallback) {
        if (error.code == ARTErrorForbidden /* RSA4d */) {
            ARTErrorInfo *errorInfo = [ARTErrorInfo createWithCode:ARTErrorAuthConfiguredProviderFailure
                                                            status:error.artStatusCode
                                                           message:error.description];
            ARTConnectionStateChangeParams *const params = [[ARTConnectionStateChangeParams alloc] initWithErrorInfo:errorInfo];
            [self performTransitionToState:ARTRealtimeFailed withParams:params];
        } else {
            ARTErrorInfo *errorInfo = [ARTErrorInfo createWithCode:ARTErrorAuthConfiguredProviderFailure status:ARTStateConnectionFailed message:error.description];
            switch (self.connection.state_nosync) {
                case ARTRealtimeConnected:
                    // RSA4c3
                    [self.connection setErrorReason:errorInfo];
                    break;
                default: {
                    // RSA4c
                    ARTConnectionStateChangeParams *const params = [[ARTConnectionStateChangeParams alloc] initWithErrorInfo:errorInfo];
                    [self performTransitionToDisconnectedOrSuspendedWithParams:params];
                    break;
                }
            }
        }
    }
    else {
        // RSA4b
        ARTErrorInfo *const errorInfo = [ARTErrorInfo createFromNSError:error];
        ARTConnectionStateChangeParams *const params = [[ARTConnectionStateChangeParams alloc] initWithErrorInfo:errorInfo];
        [self performTransitionToDisconnectedOrSuspendedWithParams:params];
    }
}

- (void)onAck:(ARTProtocolMessage *)message {
    [self ack:message];
}

- (void)onNack:(ARTProtocolMessage *)message {
    [self nack:message];
}

- (void)onChannelMessage:(ARTProtocolMessage *)message {
    if (message.channel == nil) {
        return;
    }
    ARTRealtimeChannelInternal *channel = [self.channels _getChannel:message.channel options:nil addPrefix:false];
    [channel onChannelMessage:message];
}

- (void)onSuspended {
    [self performTransitionToState:ARTRealtimeSuspended withParams:[[ARTConnectionStateChangeParams alloc] init]];
}

- (NSDate *)suspensionTime {
    return [_connectionLostAt dateByAddingTimeInterval:self.connectionStateTtl];
}

- (BOOL)isSuspendMode {
    NSDate *currentTime = [_timeProvider wallClockNow];
    return [currentTime timeIntervalSinceDate:[self suspensionTime]] > 0;
}

- (BOOL)shouldSendEvents {
    switch (self.connection.state_nosync) {
        case ARTRealtimeConnected:
            return !_renewingToken;
        default:
            return false;
    }
}

- (BOOL)isActive {
    if (self.shouldSendEvents) {
        return true;
    }
    switch (self.connection.state_nosync) {
        case ARTRealtimeInitialized:
        case ARTRealtimeConnecting:
        case ARTRealtimeDisconnected:
            return true;
        case ARTRealtimeConnected:
            return _renewingToken;
        default:
            return false;
    }
}

- (void)sendImpl:(ARTProtocolMessage *)pm reuseMsgSerial:(BOOL)reuseMsgSerial sentCallback:(ARTCallback)sentCallback ackCallback:(ARTMessageSendCallback)ackCallback {
    if (pm.ackRequired) {
        if (!reuseMsgSerial) { // RTN19a2
            pm.msgSerial = [NSNumber numberWithLongLong:self.msgSerial];
        }
    }

    for (ARTMessage *msg in pm.messages) {
        msg.connectionId = self.connection.id_nosync;
    }

    NSError *error = nil;
    NSData *data = [self.rest.defaultEncoder encodeProtocolMessage:pm error:&error];

    if (error) {
        ARTErrorInfo *e = [ARTErrorInfo createFromNSError:error];
        if (sentCallback) sentCallback(e);
        if (ackCallback) ackCallback([ARTMessageSendStatus errorWithInfo:e]);
        return;
    }
    else if (!data) {
        ARTErrorInfo *e = [ARTErrorInfo createWithCode:ARTClientCodeErrorInvalidType message:@"Encoder as failed without error."];
        if (sentCallback) sentCallback(e);
        if (ackCallback) ackCallback([ARTMessageSendStatus errorWithInfo:e]);
        return;
    }

    if (pm.ackRequired) {
        if (!reuseMsgSerial) {
            self.msgSerial++;
        }
        ARTPendingMessage *pendingMessage = [[ARTPendingMessage alloc] initWithProtocolMessage:pm ackCallback:ackCallback];
        [self.pendingMessages addObject:pendingMessage];
    }

    ARTLogDebug(self.logger, @"RT:%p sending action %tu - %@", self, pm.action, ARTProtocolMessageActionToStr(pm.action));
    if ([self.transport send:data withSource:pm]) {
        if (sentCallback) sentCallback(nil);
        // `ackCallback()` is called with ACK/NACK action
    }
}

- (void)send:(ARTProtocolMessage *)msg reuseMsgSerial:(BOOL)reuseMsgSerial sentCallback:(ARTCallback)sentCallback ackCallback:(ARTMessageSendCallback)ackCallback {
    if ([self shouldSendEvents]) {
        [self sendImpl:msg reuseMsgSerial:reuseMsgSerial sentCallback:sentCallback ackCallback:ackCallback];
    }
    // see RTL6c2, RTN19, RTN7 and TO3g
    else if (msg.ackRequired) {
        if (self.isActive && self.options.queueMessages) {
            ARTQueuedMessage *qm = [[ARTQueuedMessage alloc] initWithProtocolMessage:msg sentCallback:sentCallback ackCallback:ackCallback];
            [self.queuedMessages addObject:qm];
            ARTLogDebug(self.logger, @"RT:%p (channel: %@) protocol message with action '%lu - %@' has been queued (%@)", self, msg.channel, (unsigned long)msg.action, ARTProtocolMessageActionToStr(msg.action), msg.messages);
        }
        // RTL6c4
        else {
            ARTErrorInfo *error = self.connection.error_nosync;
            ARTLogDebug(self.logger, @"RT:%p (channel: %@) protocol message with action '%lu - %@' can't be sent or queued: %@", self, msg.channel, (unsigned long)msg.action, ARTProtocolMessageActionToStr(msg.action), error);
            if (sentCallback) {
                sentCallback(error);
            }
            if (ackCallback) {
                ackCallback([ARTMessageSendStatus errorWithInfo:error]);
            }
        }
    }
    else {
        ARTLogDebug(self.logger, @"RT:%p (channel: %@) sending protocol message with action '%lu - %@' was ignored: %@", self, msg.channel, (unsigned long)msg.action, ARTProtocolMessageActionToStr(msg.action), self.connection.error_nosync);
    }
}

- (void)send:(ARTProtocolMessage *)msg sentCallback:(ARTCallback)sentCallback ackCallback:(ARTMessageSendCallback)ackCallback {
    [self send:msg reuseMsgSerial:NO sentCallback:sentCallback ackCallback:ackCallback];
}

- (void)resendPendingMessagesWithResumed:(BOOL)resumed {
    NSArray<ARTPendingMessage *> *pendingMessages = self.pendingMessages;
    if (pendingMessages.count > 0) {
        ARTLogDebug(self.logger, @"RT:%p resending messages waiting for acknowledgment", self);
    }
    self.pendingMessages = [NSMutableArray array];
    for (ARTPendingMessage *pendingMessage in pendingMessages) {
        ARTProtocolMessage* pm = pendingMessage.msg;
        [self send:pm reuseMsgSerial:resumed sentCallback:nil ackCallback:^(ARTMessageSendStatus *status) {
            pendingMessage.ackCallback(status);
        }];
    }
}

- (void)failPendingMessages:(ARTStatus *)status {
    NSArray<ARTPendingMessage *> *pms = self.pendingMessages;
    self.pendingMessages = [NSMutableArray array];
    ARTMessageSendStatus *sendStatus = [[ARTMessageSendStatus alloc] initWithStatus:status publishResult:nil];
    for (ARTPendingMessage *pendingMessage in pms) {
        pendingMessage.ackCallback(sendStatus);
    }
}

- (void)sendQueuedMessages {
    NSArray *qms = self.queuedMessages;
    self.queuedMessages = [NSMutableArray array];

    for (ARTQueuedMessage *message in qms) {
        [self sendImpl:message.msg reuseMsgSerial:NO sentCallback:message.sentCallback ackCallback:message.ackCallback];
    }
}

- (void)failQueuedMessages:(ARTStatus *)status {
    NSArray *qms = self.queuedMessages;
    self.queuedMessages = [NSMutableArray array];
    ARTMessageSendStatus *sendStatus = [[ARTMessageSendStatus alloc] initWithStatus:status publishResult:nil];
    for (ARTQueuedMessage *message in qms) {
        message.sentCallback(status.errorInfo);
        message.ackCallback(sendStatus);
    }
}

- (void)ack:(ARTProtocolMessage *)message {
    int64_t serial = [message.msgSerial longLongValue];
    int count = message.count;
    NSArray *nackMessages = nil;
    NSArray *ackMessages = nil;
    ARTLogVerbose(self.logger, @"R:%p ACK: msgSerial=%lld, count=%d", self, serial, count);
    ARTLogVerbose(self.logger, @"R:%p ACK (before processing): pendingMessageStartSerial=%lld, pendingMessages=%lu", self, self.pendingMessageStartSerial, (unsigned long)self.pendingMessages.count);

    if (serial < self.pendingMessageStartSerial) {
        // This is an error condition and shouldn't happen but
        // we can handle it gracefully by only processing the
        // relevant portion of the response
        count -= (int)(self.pendingMessageStartSerial - serial);
        serial = self.pendingMessageStartSerial;
    }

    if (serial > self.pendingMessageStartSerial) {
        // This counts as a nack of the messages earlier than serial,
        // as well as an ack
        int nCount = (int)(serial - self.pendingMessageStartSerial);
        NSRange nackRange;
        if (nCount > self.pendingMessages.count) {
            NSString *message = [NSString stringWithFormat:@"R:%p ACK: receiving a serial greater than expected", self];
            ARTLogError(self.logger, @"%@", message);
            // Process all the available pending messages as nack
            nackRange = NSMakeRange(0, self.pendingMessages.count);
        }
        else {
            nackRange = NSMakeRange(0, nCount);
        }
        nackMessages = [self.pendingMessages subarrayWithRange:nackRange];
        [self.pendingMessages removeObjectsInRange:nackRange];
        self.pendingMessageStartSerial = serial;
    }

    if (serial == self.pendingMessageStartSerial) {
        NSRange ackRange;
        if (count > self.pendingMessages.count) {
            ARTLogError(self.logger, @"R:%p ACK: count response is greater than the total of pending messages", self);
            // Process all the available pending messages
            ackRange = NSMakeRange(0, self.pendingMessages.count);
        }
        else {
            ackRange = NSMakeRange(0, count);
        }
        ackMessages = [self.pendingMessages subarrayWithRange:ackRange];
        [self.pendingMessages removeObjectsInRange:ackRange];
        self.pendingMessageStartSerial += count;
    }

    for (ARTPendingMessage *msg in nackMessages) {
        msg.ackCallback([ARTMessageSendStatus errorWithInfo:message.error]);
    }

    NSUInteger index = 0;
    for (ARTPendingMessage *msg in ackMessages) {
        // TR4s: Extract the specific PublishResult for this message
        ARTPublishResult *publishResult = nil;
        if (message.res && index < message.res.count) {
            publishResult = message.res[index];
        }
        msg.ackCallback([ARTMessageSendStatus okWithPublishResult:publishResult]);
        index++;
    }

    ARTLogVerbose(self.logger, @"R:%p ACK (after processing): pendingMessageStartSerial=%lld, pendingMessages=%lu", self, self.pendingMessageStartSerial, (unsigned long)self.pendingMessages.count);
}

- (void)nack:(ARTProtocolMessage *)message {
    int64_t serial = [message.msgSerial longLongValue];
    int count = message.count;
    ARTLogVerbose(self.logger, @"R:%p NACK: msgSerial=%lld, count=%d", self, serial, count);
    ARTLogVerbose(self.logger, @"R:%p NACK (before processing): pendingMessageStartSerial=%lld, pendingMessages=%lu", self, self.pendingMessageStartSerial, (unsigned long)self.pendingMessages.count);

    if (serial != self.pendingMessageStartSerial) {
        // This is an error condition and it shouldn't happen but
        // we can handle it gracefully by only processing the
        // relevant portion of the response
        count -= (int)(self.pendingMessageStartSerial - serial);
    }

    NSRange nackRange;
    if (count > self.pendingMessages.count) {
        ARTLogError(self.logger, @"R:%p NACK: count response is greater than the total of pending messages", self);
        // Process all the available pending messages
        nackRange = NSMakeRange(0, self.pendingMessages.count);
    }
    else {
        nackRange = NSMakeRange(0, count);
    }

    NSArray *nackMessages = [self.pendingMessages subarrayWithRange:nackRange];
    [self.pendingMessages removeObjectsInRange:nackRange];
    self.pendingMessageStartSerial += count;

    for (ARTPendingMessage *msg in nackMessages) {
        msg.ackCallback([ARTMessageSendStatus errorWithInfo:message.error]);
    }

    ARTLogVerbose(self.logger, @"R:%p NACK (after processing): pendingMessageStartSerial=%lld, pendingMessages=%lu", self, self.pendingMessageStartSerial, (unsigned long)self.pendingMessages.count);
}

- (BOOL)reconnectWithFallback {
    NSString *host = [_fallbacks popFallbackHost];
    if (host != nil) {
        ARTLogDebug(self.logger, @"R:%p checking internet connection and then retrying realtime at %@", self, host);
        [self.rest internetIsUp:^void(BOOL isUp) { // RTN17j
            if (!isUp) {
                ARTErrorInfo *const errorInfo = [ARTErrorInfo createWithCode:0 message:@"no Internet connection"];
                ARTConnectionStateChangeParams *const params = [[ARTConnectionStateChangeParams alloc] initWithErrorInfo:errorInfo];
                [self performTransitionToState:ARTRealtimeDisconnected withParams:params];
                return;
            }

            ARTLogDebug(self.logger, @"R:%p internet OK; retrying realtime connection at %@", self, host);
            self.rest.prioritizedHost = host;
            [self transportReconnectWithHost:host];
        }];
        return true;
    } else {
        ARTLogDebug(self.logger, @"R:%p No fallback hosts left, trying primary one again...", self);
        _fallbacks = nil;
        return false;
    }
}

- (BOOL)shouldRetryWithFallbackForError:(ARTRealtimeTransportError *)error options:(ARTClientOptions *)options {
    if ((error.type == ARTRealtimeTransportErrorTypeBadResponse && error.badResponseCode >= 500 && error.badResponseCode <= 504) ||
         error.type == ARTRealtimeTransportErrorTypeHostUnreachable || error.type == ARTRealtimeTransportErrorTypeTimeout) {
        // RTN17g
        return [ARTFallbackHosts hostsFromOptions:options].count > 0;
    }
    return NO;
}

- (void)onActivity {
    ARTLogVerbose(self.logger, @"R:%p activity", self);
    _lastActivity = [_timeProvider wallClockNow];
    [self setIdleTimer];
}

- (void)setIdleTimer {
    if (self.maxIdleInterval <= 0) {
        ARTLogVerbose(self.logger, @"R:%p set idle timer had been ignored", self);
        return;
    }
    [_idleTimer cancel];

    _idleTimer = [_timeProvider scheduleAfter:self.options.realtimeRequestTimeout + self.maxIdleInterval queue:_rest.queue block:^{
        ARTLogError(self.logger, @"R:%p No activity seen from realtime in %f seconds; assuming connection has dropped", self, [[self->_timeProvider wallClockNow] timeIntervalSinceDate:self->_lastActivity]);

        ARTErrorInfo *idleTimerExpired = [ARTErrorInfo createWithCode:ARTErrorDisconnected status:408 message:@"Idle timer expired"];
        ARTConnectionStateChangeParams *const params = [[ARTConnectionStateChangeParams alloc] initWithErrorInfo:idleTimerExpired];
        [self performTransitionToDisconnectedOrSuspendedWithParams:params];
    }];
}

- (void)stopIdleTimer {
    [_idleTimer cancel];
    _idleTimer = nil;
}

- (void)setReachabilityClass:(Class)reachabilityClass {
    _reachabilityClass = reachabilityClass;
}

#pragma mark - ARTRealtimeTransportDelegate implementation

- (void)realtimeTransport:(id)transport didReceiveMessage:(ARTProtocolMessage *)message {
    [self onActivity];

    if (!message) {
        // Invalid data
        return;
    }

    if (transport != self.transport) {
        // Old connection
        return;
    }

    if (self.connection.state_nosync == ARTRealtimeDisconnected) {
        // Already disconnected
        return;
    }

    ARTLogVerbose(self.logger, @"R:%p did receive Protocol Message %@ (connection state is %@)", self, ARTProtocolMessageActionToStr(message.action), ARTRealtimeConnectionStateToStr(self.connection.state_nosync));

    if (message.error) {
        ARTLogVerbose(self.logger, @"R:%p Protocol Message with error %@", self, message.error);
    }

    NSAssert(transport == self.transport, @"Unexpected transport");

#ifdef ABLY_SUPPORTS_PLUGINS
    NSArray<ARTRealtimeChannelInternal *> *allChannels = self.channels.collection.allValues;
#endif

    switch (message.action) {
        case ARTProtocolMessageHeartbeat:
            [self onHeartbeat];
            break;
        case ARTProtocolMessageError:
            [self onError:message];
            break;
        case ARTProtocolMessageConnected:
            self.latestConnectionDetails = message.connectionDetails;

            // Set Auth#clientId
            if (message.connectionDetails) {
                [self.auth setProtocolClientId:message.connectionDetails.clientId];
            }
#ifdef ABLY_SUPPORTS_PLUGINS
            for (ARTRealtimeChannelInternal *channel in allChannels) {
                [self.options.liveObjectsPlugin nosync_onConnectedWithConnectionDetails:message.connectionDetails
                                                                                channel:channel];
            }
#endif
            // Event
            [self onConnected:message];
            break;
        case ARTProtocolMessageDisconnect:
        case ARTProtocolMessageDisconnected:
            [self onDisconnected:message];
            break;
        case ARTProtocolMessageAck:
            [self onAck:message];
            break;
        case ARTProtocolMessageNack:
            [self onNack:message];
            break;
        case ARTProtocolMessageClosed:
            [self onClosed];
            break;
        case ARTProtocolMessageAuth:
            [self onAuth];
            break;
        default:
            [self onChannelMessage:message];
            break;
    }
}

- (void)realtimeTransportAvailable:(id<ARTRealtimeTransport>)transport {
    // Do nothing
}

- (void)realtimeTransportClosed:(id<ARTRealtimeTransport>)transport {
    if (transport != self.transport) {
        // Old connection
        return;
    }

    if (self.connection.state_nosync == ARTRealtimeClosing) {
        // Close succeeded. Nothing more to do.
        [self performTransitionToState:ARTRealtimeClosed withParams:[[ARTConnectionStateChangeParams alloc] init]];
    } else if (self.connection.state_nosync != ARTRealtimeClosed && self.connection.state_nosync != ARTRealtimeFailed) {
        // Unexpected closure; recover.
        [self performTransitionToDisconnectedOrSuspendedWithParams:[[ARTConnectionStateChangeParams alloc] init]];
    }
}

- (void)realtimeTransportDisconnected:(id<ARTRealtimeTransport>)transport withError:(ARTRealtimeTransportError *)error {
    if (transport != self.transport) {
        // Old connection
        return;
    }

    if (self.connection.state_nosync == ARTRealtimeClosing) {
        [self performTransitionToState:ARTRealtimeClosed withParams:[[ARTConnectionStateChangeParams alloc] init]];
    } else {
        ARTErrorInfo *const errorInfo = [ARTErrorInfo createFromNSError:error.error];
        ARTConnectionStateChangeParams *const params = [[ARTConnectionStateChangeParams alloc] initWithErrorInfo:errorInfo];
        [self performTransitionToDisconnectedOrSuspendedWithParams:params];
    }
}

- (void)realtimeTransportFailed:(id<ARTRealtimeTransport>)transport withError:(ARTRealtimeTransportError *)transportError {
    if (transport != self.transport) {
        // Old connection
        return;
    }

    ARTLogDebug(self.logger, @"R:%p realtime transport failed: %@", self, transportError);

    ARTErrorInfo *const errorInfo = [ARTErrorInfo createFromNSError:transportError.error];
    ARTConnectionStateChangeParams *const params = [[ARTConnectionStateChangeParams alloc] initWithErrorInfo:errorInfo];

    ARTClientOptions *const clientOptions = [self getClientOptions];

    if (![self isSuspendMode] && [self shouldRetryWithFallbackForError:transportError options:clientOptions]) {
        ARTLogDebug(self.logger, @"R:%p host is down; can retry with fallback host", self);
        if (!_fallbacks) {
            NSArray *hosts = [ARTFallbackHosts hostsFromOptions:clientOptions];
            _fallbacks = [[ARTFallback alloc] initWithFallbackHosts:hosts shuffleArray:clientOptions.testOptions.shuffleArray];
        }
        if (!_fallbacks || _fallbacks.isEmpty) {
            _fallbacks = nil;
            ARTLogVerbose(self.logger, @"R:%p No fallback hosts left, will try primary one again...", self);
        }
        [self performTransitionToDisconnectedOrSuspendedWithParams:params]; // RTN14d, RTN17j
    } else {
        [self performTransitionToDisconnectedOrSuspendedWithParams:params];
    }
}

- (void)realtimeTransportNeverConnected:(id<ARTRealtimeTransport>)transport {
    if (transport != self.transport) {
        // Old connection
        return;
    }

    ARTErrorInfo *const errorInfo = [ARTErrorInfo createWithCode:ARTClientCodeErrorTransport message:@"Transport never connected"];
    ARTConnectionStateChangeParams *const params = [[ARTConnectionStateChangeParams alloc] initWithErrorInfo:errorInfo];
    [self performTransitionToDisconnectedOrSuspendedWithParams:params];
}

- (void)realtimeTransportRefused:(id<ARTRealtimeTransport>)transport withError:(ARTRealtimeTransportError *)error {
    if (transport != self.transport) {
        // Old connection
        return;
    }

    if (error && error.type == ARTRealtimeTransportErrorTypeRefused) {
        ARTErrorInfo *const errorInfo = [ARTErrorInfo createWithCode:ARTClientCodeErrorTransport message:[NSString stringWithFormat:@"Connection refused using %@", error.url]];
        ARTConnectionStateChangeParams *const params = [[ARTConnectionStateChangeParams alloc] initWithErrorInfo:errorInfo];
        [self performTransitionToDisconnectedOrSuspendedWithParams:params];
    }
    else if (error) {
        ARTErrorInfo *const errorInfo = [ARTErrorInfo createFromNSError:error.error];
        ARTConnectionStateChangeParams *const params = [[ARTConnectionStateChangeParams alloc] initWithErrorInfo:errorInfo];
        [self performTransitionToDisconnectedOrSuspendedWithParams:params];
    }
    else {
        ARTConnectionStateChangeParams *const params = [[ARTConnectionStateChangeParams alloc] init];
        [self performTransitionToDisconnectedOrSuspendedWithParams:params];
    }
}

- (void)realtimeTransportTooBig:(id<ARTRealtimeTransport>)transport {
    if (transport != self.transport) {
        // Old connection
        return;
    }

    ARTErrorInfo *const errorInfo = [ARTErrorInfo createWithCode:ARTClientCodeErrorTransport message:@"Transport too big"];
    ARTConnectionStateChangeParams *const params = [[ARTConnectionStateChangeParams alloc] initWithErrorInfo:errorInfo];
    [self performTransitionToDisconnectedOrSuspendedWithParams:params];
}

- (void)realtimeTransportSetMsgSerial:(id<ARTRealtimeTransport>)transport msgSerial:(int64_t)msgSerial {
    if (transport != self.transport) {
        // Old connection
        return;
    }

    self.msgSerial = msgSerial;
}

#if TARGET_OS_IOS
- (ARTLocalDevice *)device {
    return _rest.device;
}
#endif

@end
