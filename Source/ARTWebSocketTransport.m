#import "ARTWebSocketTransport+Private.h"

#import "ARTHttpClient.h"
#import "ARTHttpClient+Private.h"
#import "ARTProtocolMessage.h"
#import "ARTClientOptions.h"
#import "ARTClientOptions+Private.h"
#import "ARTTokenParams.h"
#import "ARTTokenDetails.h"
#import "ARTStatus.h"
#import "ARTEncoder.h"
#import "ARTDefault.h"
#import "ARTRealtimeTransport.h"
#import "ARTGCD.h"
#import "ARTEventEmitter+Private.h"
#import "NSURLQueryItem+Stringifiable.h"
#import "ARTNSMutableDictionary+ARTDictionaryUtil.h"
#import "ARTStringifiable.h"
#import "ARTClientInformation.h"
#import "ARTConnection+Private.h"
#import "ARTInternalLog.h"
#import "ARTWebSocketFactory.h"

enum {
    ARTWsNeverConnected = -1,
    ARTWsBuggyClose = -2,
    ARTWsCloseNormal = 1000,
    ARTWsGoingAway = 1001,
    ARTWsCloseProtocolError = 1002,
    ARTWsRefuse = 1003,
    ARTWsNoUtf8 = 1007,
    ARTWsPolicyValidation = 1008,
    ARTWsTooBig = 1009,
    ARTWsExtension = 1010,
    ARTWsUnexpectedCondition = 1011,
    ARTWsTlsError = 1015
};

NSString *WebSocketStateToStr(ARTWebSocketReadyState state);

NS_ASSUME_NONNULL_BEGIN

@interface ARTWebSocketTransport ()

@property (nonatomic, readonly) id<ARTWebSocketFactory> webSocketFactory;

@end

NS_ASSUME_NONNULL_END

@implementation ARTWebSocketTransport {
    id<ARTRealtimeTransportDelegate> _delegate;
    ARTRealtimeTransportState _state;
    /**
      The dispatch queue for firing the events. Must be the same for the whole library.
     */
    _Nonnull dispatch_queue_t _workQueue;

    /**
      The dispatch queue on which we call `-open` on our `ARTWebSocket`.

      The important thing here is that it has a fixed QoS class (of `QOS_CLASS_DEFAULT`). This is so that, regardless of from which thread or dispatch queue we try to start an `ARTWebSocketTransport`, apps do not get an Xcode Thread Performance Checker runtime warning of the form "Thread running at User-initiated quality-of-service class waiting on a lower QoS thread running at Default quality-of-service class. Investigate ways to avoid priority inversions". These errors are caused by a lower-priority thread being blocked by one of the following in `ARTSRProxyConnect`:

      - the fetch of `+[NSRunLoop ARTSR_networkRunLoop]`
      - the calls to `-[NSStream open]` (it's not clear to me what exactly is blocking here but it triggers an Xcode warning so let's avoid it)
     */
    _Nonnull dispatch_queue_t _websocketOpenQueue;
}

@synthesize delegate = _delegate;
@synthesize stateEmitter = _stateEmitter;

- (instancetype)initWithRest:(ARTHttpClientInternal *)rest options:(ARTClientOptions *)options resumeKey:(NSString *)resumeKey logger:(ARTInternalLog *)logger webSocketFactory:(id<ARTWebSocketFactory>)webSocketFactory {
    self = [super init];
    if (self) {
        _workQueue = rest.queue;
        _websocketOpenQueue = dispatch_queue_create("io.ably.websocketOpen", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_DEFAULT, 0));
        _websocket = nil;
        _state = ARTRealtimeTransportStateClosed;
        _encoder = rest.defaultEncoder;
        _logger = logger;
        _options = [options copy];
        _resumeKey = resumeKey;
        _stateEmitter = [[ARTInternalEventEmitter alloc] initWithQueue:_workQueue timeProvider:rest.timeProvider];
        _webSocketFactory = webSocketFactory;

        ARTLogVerbose(self.logger, @"R:%p WS:%p alloc", _delegate, self);
    }
    return self;
}

- (void)dealloc {
    ARTLogVerbose(self.logger, @"R:%p WS:%p dealloc", _delegate, self);
    self.websocket.delegate = nil;
    self.websocket = nil;
    self.delegate = nil;
}

- (BOOL)send:(NSData *)data withSource:(id)decodedObject {
    if (self.websocket.readyState == ARTWebSocketReadyStateOpen) {
        [self.websocket send:data];
        return true;
    }
    else {
        NSString *extraInformation = @"";
        if ([decodedObject isKindOfClass:[ARTProtocolMessage class]]) {
            ARTProtocolMessage *msg = (ARTProtocolMessage *)decodedObject;
            extraInformation = [NSString stringWithFormat:@"with action \"%tu - %@\" ", msg.action, ARTProtocolMessageActionToStr(msg.action)];
        }
        ARTLogDebug(self.logger, @"R:%p WS:%p sending message %@was ignored because websocket isn't ready", _delegate, self, extraInformation);
        return false;
    }
}

- (void)internalSend:(ARTProtocolMessage *)msg {
    ARTLogDebug(self.logger, @"R:%p WS:%p websocket sending action %tu - %@", _delegate, self, msg.action, ARTProtocolMessageActionToStr(msg.action));
    NSData *data = [self.encoder encodeProtocolMessage:msg error:nil];
    [self send:data withSource:msg];
}

- (void)receive:(ARTProtocolMessage *)msg {
    [self.delegate realtimeTransport:self didReceiveMessage:msg];
}

- (ARTProtocolMessage *)receiveWithData:(NSData *)data {
    ARTProtocolMessage *pm = [self.encoder decodeProtocolMessage:data error:nil];
    [self receive:pm];
    return pm;
}

- (void)connectWithKey:(NSString *)key {
    _state = ARTRealtimeTransportStateOpening;
    ARTLogDebug(self.logger, @"R:%p WS:%p websocket connect with key", _delegate, self);
    NSURLQueryItem *keyParam = [NSURLQueryItem queryItemWithName:@"key" value:key];
    [self setupWebSocket:@{keyParam.name: keyParam} withOptions:self.options resumeKey:self.resumeKey];
    // Connect
    [self openWebSocket];
}

- (void)connectWithToken:(NSString *)token {
    _state = ARTRealtimeTransportStateOpening;
    ARTLogDebug(self.logger, @"R:%p WS:%p websocket connect with token", _delegate, self);
    NSURLQueryItem *accessTokenParam = [NSURLQueryItem queryItemWithName:@"accessToken" value:token];
    [self setupWebSocket:@{accessTokenParam.name: accessTokenParam} withOptions:self.options resumeKey:self.resumeKey];
    // Connect
    [self openWebSocket];
}

- (NSURL *)setupWebSocket:(NSDictionary<NSString *, NSURLQueryItem *> *)params withOptions:(ARTClientOptions *)options resumeKey:(NSString *)resumeKey {
    __block NSMutableDictionary<NSString*, NSURLQueryItem*> *queryItems = [params mutableCopy];

    // ClientID
    if (options.clientId) {
        [queryItems addValueAsURLQueryItem:options.clientId forKey:@"clientId"];
    }

    // Echo
    [queryItems addValueAsURLQueryItem:options.echoMessages ? @"true" : @"false" forKey:@"echo"];

    // Format: MsgPack, JSON
    [queryItems addValueAsURLQueryItem:[_encoder formatAsString] forKey:@"format"];

    // RTN16k
    if (options.recover != nil) {
        NSError *error;
        ARTConnectionRecoveryKey *const recoveryKey = [ARTConnectionRecoveryKey fromJsonString:options.recover error:&error];
        if (error) {
            ARTLogError(_logger, @"Couldn't construct a recovery key from the string provided: %@", options.recover);
        }
        else {
            [queryItems addValueAsURLQueryItem:recoveryKey.connectionKey forKey:@"recover"];
        }
    }
    else if (resumeKey != nil) {
        [queryItems addValueAsURLQueryItem:resumeKey forKey:@"resume"]; // RTN15b1
    }

    [queryItems addValueAsURLQueryItem:[ARTDefault apiVersion] forKey:@"v"];

    // Lib
    [queryItems addValueAsURLQueryItem:[ARTClientInformation agentIdentifierWithAdditionalAgents:options.agents] forKey:@"agent"];

    // Transport Params
    if (options.transportParams != nil) {
        [options.transportParams enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, ARTStringifiable * _Nonnull obj, BOOL * _Nonnull stop) {
            [queryItems addValueAsURLQueryItem:obj.stringValue forKey:key];
        }];
    }

    // URL
    NSURLComponents *urlComponents = [NSURLComponents componentsWithString:@"/"];
    urlComponents.queryItems = [queryItems allValues];
    NSURL *url = [urlComponents URLRelativeToURL:[options realtimeUrl]];

    ARTLogDebug(_logger, @"R:%p WS:%p url %@", _delegate, self, url);

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];

    self.websocket = [self.webSocketFactory createWebSocketWithURLRequest:request logger:self.logger];
    [self.websocket setDelegateDispatchQueue:_workQueue];
    self.websocket.delegate = self;
    self.websocketURL = url;
    return url;
}

- (void)openWebSocket {
    __weak ARTWebSocketTransport *weakSelf = self;
    art_dispatch_async(_websocketOpenQueue, ^{
        [weakSelf.websocket open];
    });
}

- (void)sendClose {
    _state = ARTRealtimeTransportStateClosing;
    ARTProtocolMessage *closeMessage = [[ARTProtocolMessage alloc] init];
    closeMessage.action = ARTProtocolMessageClose;
    [self internalSend:closeMessage];
}

- (void)sendPing {
    ARTProtocolMessage *heartbeatMessage = [[ARTProtocolMessage alloc] init];
    heartbeatMessage.action = ARTProtocolMessageHeartbeat;
    [self internalSend:heartbeatMessage];
}

- (void)close {
    self.delegate = nil;
    if (!_websocket) return;
    self.websocket.delegate = nil;
    [self.websocket closeWithCode:ARTWsCloseNormal reason:@"Normal Closure"];
    self.websocket = nil;
}

- (void)abort:(ARTStatus *)reason {
    self.delegate = nil;
    if (!_websocket) return;
    self.websocket.delegate = nil;
    if (reason.errorInfo) {
        [self.websocket closeWithCode:ARTWsCloseNormal reason:reason.errorInfo.description];
    }
    else {
        [self.websocket closeWithCode:ARTWsCloseNormal reason:@"Abnormal Closure"];
    }
    self.websocket = nil;
}

- (void)setHost:(NSString *)host {
    self.options.realtimeHost = host;
}

- (NSString *)host {
    return self.options.realtimeHost;
}

- (ARTRealtimeTransportState)state {
    if (self.websocket.readyState == ARTWebSocketReadyStateOpen) {
        return ARTRealtimeTransportStateOpened;
    }
    return _state;
}

- (void)setState:(ARTRealtimeTransportState)state {
    _state = state;
}

#pragma mark - ARTWebSocketDelegate

// All delegate methods from SocketRocket are called from rest's serial queue,
// since we pass it as delegate queue on setupWebSocket. So we can safely
// call all our delegate's methods.

- (void)webSocketDidOpen:(id<ARTWebSocket>)websocket {
    ARTLogDebug(self.logger, @"R:%p WS:%p websocket did open", _delegate, self);
    [_stateEmitter emit:[ARTEvent newWithTransportState:ARTRealtimeTransportStateOpened] with:nil];
    [_delegate realtimeTransportAvailable:self];
}

- (void)webSocket:(id<ARTWebSocket>)webSocket didCloseWithCode:(NSInteger)code reason:(NSString *)reason wasClean:(BOOL)wasClean {
    ARTLogDebug(self.logger, @"R:%p WS:%p websocket did disconnect (code %ld) %@", _delegate, self, (long)code, reason);

    switch (code) {
    case ARTWsCloseNormal:
        [_delegate realtimeTransportClosed:self];
        break;
    case ARTWsNeverConnected:
        [_delegate realtimeTransportNeverConnected:self];
        break;
    case ARTWsBuggyClose:
    case ARTWsGoingAway:
        // Connectivity issue
        [_delegate realtimeTransportDisconnected:self withError:nil];
        break;
    case ARTWsRefuse:
    case ARTWsPolicyValidation: {
        ARTErrorInfo *const errorInfo = [ARTErrorInfo createWithCode:code message:reason];
        ARTRealtimeTransportError *const error = [[ARTRealtimeTransportError alloc] initWithError:errorInfo
                                                                                             type:ARTRealtimeTransportErrorTypeRefused
                                                                                              url:self.websocketURL];
        [_delegate realtimeTransportRefused:self withError:error];
        break;
    }
    case ARTWsTooBig:
        [_delegate realtimeTransportTooBig:self];
        break;
    case ARTWsNoUtf8:
    case ARTWsCloseProtocolError:
    case ARTWsUnexpectedCondition:
    case ARTWsExtension:
    case ARTWsTlsError: {
        // Failed
        ARTErrorInfo *const errorInfo = [ARTErrorInfo createWithCode:code message:reason];
        ARTRealtimeTransportError *const error = [[ARTRealtimeTransportError alloc] initWithError:errorInfo
                                                                                             type:ARTRealtimeTransportErrorTypeOther
                                                                                              url:self.websocketURL];
        [_delegate realtimeTransportFailed:self withError:error];
        break;
    }
    default:
        NSAssert(true, @"WebSocket close: unknown code");
        break;
    }

    _state = ARTRealtimeTransportStateClosed;
    [_stateEmitter emit:[ARTEvent newWithTransportState:ARTRealtimeTransportStateClosed] with:nil];
}

- (void)webSocket:(id<ARTWebSocket>)webSocket didFailWithError:(NSError *)error {
    ARTLogDebug(self.logger, @"R:%p WS:%p websocket did receive error %@", _delegate, self, error);

    [_delegate realtimeTransportFailed:self withError:[self classifyError:error]];
    _state = ARTRealtimeTransportStateClosed;
}

- (ARTRealtimeTransportError *)classifyError:(NSError *)error {
    ARTRealtimeTransportErrorType type = ARTRealtimeTransportErrorTypeOther;

    if ([error.domain isEqualToString:@"com.squareup.SocketRocket"] && error.code == 504) {
        type = ARTRealtimeTransportErrorTypeTimeout;
    } else if ([error.domain isEqualToString:(NSString *)kCFErrorDomainCFNetwork]) {
        type = ARTRealtimeTransportErrorTypeHostUnreachable;
    } else if ([error.domain isEqualToString:@"NSPOSIXErrorDomain"] && (error.code == 57 || error.code == 50)) {
        type = ARTRealtimeTransportErrorTypeNoInternet;
    } else if ([error.domain isEqualToString:ARTSRWebSocketErrorDomain] && error.code == 2132) {
        id status = error.userInfo[ARTSRHTTPResponseErrorKey];
        if (status) {
            return [[ARTRealtimeTransportError alloc] initWithError:error
                                                    badResponseCode:[(NSNumber *)status integerValue]
                                                                url:self.websocketURL];
        }
    }

    return [[ARTRealtimeTransportError alloc] initWithError:error type:type url:self.websocketURL];
}

- (void)webSocket:(id<ARTWebSocket>)webSocket didReceiveMessage:(id)message {
    ARTLogVerbose(self.logger, @"R:%p WS:%p websocket did receive message", _delegate, self);

    if (self.websocket.readyState == ARTWebSocketReadyStateClosed) {
        ARTLogDebug(self.logger, @"R:%p WS:%p websocket is closed, message has been ignored", _delegate, self);
        return;
    }

    if ([message isKindOfClass:[NSString class]]) {
        [self webSocketMessageText:(NSString *)message];
    } else if ([message isKindOfClass:[NSData class]]) {
        [self webSocketMessageData:(NSData *)message];
    } else if ([message isKindOfClass:[ARTProtocolMessage class]]) {
        [self webSocketMessageProtocol:(ARTProtocolMessage *)message];
    }
}

- (void)webSocketMessageText:(NSString *)text {
    ARTLogDebug(self.logger, @"R:%p WS:%p websocket in %@ state did receive message %@", _delegate, self, WebSocketStateToStr(self.websocket.readyState), text);

    NSData *data = nil;
    data = [((NSString *)text) dataUsingEncoding:NSUTF8StringEncoding];

    [self receiveWithData:data];
}

- (void)webSocketMessageData:(NSData *)data {
    ARTLogVerbose(self.logger, @"R:%p WS:%p websocket in %@ state did receive data %@", _delegate, self, WebSocketStateToStr(self.websocket.readyState), data);

    [self receiveWithData:data];
}

- (void)webSocketMessageProtocol:(ARTProtocolMessage *)message {
    ARTLogDebug(self.logger, @"R:%p WS:%p websocket in %@ state did receive protocol message %@", _delegate, self, WebSocketStateToStr(self.websocket.readyState), message);

    [self receive:message];
}

@end

NSString *WebSocketStateToStr(ARTWebSocketReadyState state) {
    switch (state) {
        case ARTWebSocketReadyStateConnecting:
            return @"Connecting"; //0
        case ARTWebSocketReadyStateOpen:
            return @"Open"; //1
        case ARTWebSocketReadyStateClosing:
            return @"Closing"; //2
        case ARTWebSocketReadyStateClosed:
            return @"Closed"; //3
    }
}

NSString *ARTRealtimeTransportStateToStr(ARTRealtimeTransportState state) {
    switch (state) {
        case ARTRealtimeTransportStateOpening:
            return @"Connecting"; //0
        case ARTRealtimeTransportStateOpened:
            return @"Open"; //1
        case ARTRealtimeTransportStateClosing:
            return @"Closing"; //2
        case ARTRealtimeTransportStateClosed:
            return @"Closed"; //3
    }
}

#pragma mark - ARTEvent

@implementation ARTEvent (TransportState)

- (instancetype)initWithTransportState:(ARTRealtimeTransportState)value {
    return [self initWithString:[NSString stringWithFormat:@"ARTRealtimeTransportState%@", ARTRealtimeTransportStateToStr(value)]];
}

+ (instancetype)newWithTransportState:(ARTRealtimeTransportState)value {
    return [[self alloc] initWithTransportState:value];
}

@end
