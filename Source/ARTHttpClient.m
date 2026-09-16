#import "ARTHttpClient+Private.h"

#import "ARTChannel+Private.h"
#import "ARTHttpChannels+Private.h"
#import "ARTDataQuery+Private.h"
#import "ARTPaginatedResult+Private.h"
#import "ARTAuth+Private.h"
#import "ARTHTTPExecutor.h"
#import "ARTEncoder.h"
#import "ARTJsonLikeEncoder.h"
#import "ARTJsonEncoder.h"
#import "ARTMsgPackEncoder.h"
#import "ARTMessage.h"
#import "ARTPresence.h"
#import "ARTPresenceMessage.h"
#import "ARTHTTPExecutor.h"
#import "ARTClientOptions+Private.h"
#import "ARTDefault.h"
#import "ARTStats.h"
#import "ARTFallback+Private.h"
#import "ARTFallbackHosts.h"
#import "ARTNSDictionary+ARTDictionaryUtil.h"
#import "ARTNSArray+ARTFunctional.h"
#import "ARTHttpChannel.h"
#import "ARTTokenParams.h"
#import "ARTTokenDetails.h"
#import "ARTDefault.h"
#import "ARTGCD.h"
#import "ARTRealtime+Private.h"
#import "ARTPush.h"
#import "ARTPush+Private.h"
#import "ARTLocalDevice+Private.h"
#import "ARTLocalDeviceStorage.h"
#import "ARTThrowingLocalDeviceStorage.h"
#import "ARTNSMutableRequest+ARTHttpClient.h"
#import "ARTHTTPPaginatedResponse+Private.h"
#import "ARTNSError+ARTUtils.h"
#import "ARTNSMutableURLRequest+ARTUtils.h"
#import "ARTNSURL+ARTUtils.h"
#import "ARTClientInformation.h"
#import "ARTErrorChecker.h"
#import "ARTInternalLog.h"
#import "ARTLogAdapter.h"
#import "ARTClientOptions+TestConfiguration.h"
#import "ARTTestClientOptions.h"
#import "ARTTimeProvider.h"
#if TARGET_OS_IOS
#import "ARTPushActivationStateMachine+Private.h"
#import "ARTPushActivationEvent.h"
#endif

@implementation ARTHttpClient {
    ARTQueuedDealloc *_dealloc;
}

- (void)internalAsync:(void (^)(ARTHttpClientInternal * _Nonnull))use {
    art_dispatch_async(_internal.queue, ^{
        use(self->_internal);
    });
}

- (void)initCommon {
    _dealloc = [[ARTQueuedDealloc alloc] init:_internal queue:_internal.queue];
}

- (instancetype)initWithOptions:(ARTClientOptions *)options {
    self = [super init];
    if (self) {
        _internal = [[ARTHttpClientInternal alloc] initWithOptions:options];
        [self initCommon];
    }
    return self;
}

- (instancetype)initWithKey:(NSString *)key {
    self = [super init];
    if (self) {
        _internal = [[ARTHttpClientInternal alloc] initWithKey:key];
        [self initCommon];
    }
    return self;
}

- (instancetype)initWithToken:(NSString *)token {
    self = [super init];
    if (self) {
        _internal = [[ARTHttpClientInternal alloc] initWithToken:token];
        [self initCommon];
    }
    return self;
}

+ (instancetype)createWithOptions:(ARTClientOptions *)options {
    return [[ARTHttpClient alloc] initWithOptions:options];
}

+ (instancetype)createWithKey:(NSString *)key {
    return [[ARTHttpClient alloc] initWithKey:key];
}

+ (instancetype)createWithToken:(NSString *)tokenId {
    return [[ARTHttpClient alloc] initWithToken:tokenId];
}

- (void)time:(ARTDateTimeCallback)callback {
    [_internal timeWithWrapperSDKAgents:nil
                             completion:callback];
}

- (BOOL)request:(NSString *)method
           path:(NSString *)path
         params:(nullable NSStringDictionary *)params
           body:(nullable id)body
        headers:(nullable NSStringDictionary *)headers
       callback:(ARTHTTPPaginatedCallback)callback
          error:(NSError *_Nullable *_Nullable)errorPtr {
    return [_internal request:(NSString *)method path:path params:params body:body headers:headers wrapperSDKAgents:nil callback:callback error:errorPtr];
}

- (BOOL)stats:(ARTPaginatedStatsCallback)callback {
    return [_internal statsWithWrapperSDKAgents:nil
                                     completion:callback];
}

- (BOOL)stats:(nullable ARTStatsQuery *)query callback:(ARTPaginatedStatsCallback)callback error:(NSError *_Nullable *_Nullable)errorPtr {
    return [_internal stats:query wrapperSDKAgents:nil callback:callback error:errorPtr];
}

- (ARTHttpChannels *)channels {
    return [[ARTHttpChannels alloc] initWithInternal:_internal.channels queuedDealloc:_dealloc];
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

- (ARTLocalDevice *)device_nosync {
    return _internal.device_nosync;
}

#endif

@end

NS_ASSUME_NONNULL_BEGIN

@interface ARTHttpClientInternal ()

@property (nonatomic, readonly) ARTInternalLog *logger;

@end

NS_ASSUME_NONNULL_END

@implementation ARTHttpClientInternal {
    ARTInternalLog *_logger;
    NSUInteger _tokenErrorRetries;
}

@synthesize logger = _logger;

- (instancetype)initWithOptions:(ARTClientOptions *)options {
    ARTInternalLog *const logger = [[ARTInternalLog alloc] initWithClientOptions:options];
    return [self initWithOptions:options realtime:nil logger:logger];
}

- (instancetype)initWithOptions:(ARTClientOptions *)options realtime:(ARTRealtimeInternal *_Nullable)realtime logger:(ARTInternalLog *)logger {
    self = [super init];
    if (self) {
        NSAssert(options, @"ARTHttpClient: No options provided");

        _realtime = realtime;
        _options = [options copy];
        _logger = logger;
        _timeProvider = options.testOptions.timeProvider;
        _queue = options.internalDispatchQueue;
        _userQueue = options.dispatchQueue;
#if TARGET_OS_IOS
        if (_options.testOptions.disableLocalDevice) {
            _storage = [[ARTThrowingLocalDeviceStorage alloc] init];
        }
        else {
            _storage = [ARTLocalDeviceStorage newWithLogger:_logger
                                                  logValues:_options.testOptions.logLocalDeviceStorageValues];
        }
#endif
        _http = [[ARTHTTPExecutor alloc] initWithQueue:_queue logger:_logger];
        ARTLogVerbose(_logger, @"RS:%p %p alloc HTTP", self, _http);
        _httpExecutor = options.testOptions.httpExecutor ?: _http;

        id<ARTEncoder> jsonEncoder = [[ARTJsonLikeEncoder alloc] initWithRest:self delegate:[[ARTJsonEncoder alloc] init] logger:_logger];
        id<ARTEncoder> msgPackEncoder = [[ARTJsonLikeEncoder alloc] initWithRest:self delegate:[[ARTMsgPackEncoder alloc] init] logger:_logger];
        _encoders = @{
            [jsonEncoder mimeType]: jsonEncoder,
            [msgPackEncoder mimeType]: msgPackEncoder
        };
        _defaultEncoding = (_options.useBinaryProtocol ? [msgPackEncoder mimeType] : [jsonEncoder mimeType]);
        _fallbackCount = 0;
        _tokenErrorRetries = 0;

        _auth = [[ARTAuthInternal alloc] init:self withOptions:_options logger:_logger];
        _push = [[ARTPushInternal alloc] initWithRest:self logger:_logger];
        _channels = [[ARTHttpChannelsInternal alloc] initWithRest:self logger:_logger];

        ARTLogVerbose(self.logger, @"RS:%p initialized", self);
    }
    return self;
}

- (instancetype)initWithKey:(NSString *)key {
    return [self initWithOptions:[[ARTClientOptions alloc] initWithKey:key]];
}

- (instancetype)initWithToken:(NSString *)token {
    return [self initWithOptions:[[ARTClientOptions alloc] initWithToken:token]];
}

- (void)dealloc {
    ARTLogVerbose(self.logger, @"RS:%p dealloc", self);
}

- (ARTInternalLog *)logger_onlyForUseInClassMethodsAndTests {
    return self.logger;
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

- (NSObject<ARTCancellable> *)executeRequest:(NSMutableURLRequest *)request
                              withAuthOption:(ARTAuthentication)authOption
                            wrapperSDKAgents:(nullable NSDictionary<NSString *, NSString *> *)wrapperSDKAgents
                                  completion:(ARTURLRequestCallback)callback {
    request.URL = [NSURL URLWithString:request.URL.relativeString relativeToURL:self.baseUrl];

    switch (authOption) {
        case ARTAuthenticationOff:
            return [self executeRequest:request wrapperSDKAgents:wrapperSDKAgents completion:callback];
        case ARTAuthenticationOn:
            _tokenErrorRetries = 0;
            return [self executeRequestWithAuthentication:request withMethod:self.auth.method force:NO wrapperSDKAgents:wrapperSDKAgents completion:callback];
        case ARTAuthenticationNewToken:
            _tokenErrorRetries = 0;
            return [self executeRequestWithAuthentication:request withMethod:self.auth.method force:YES wrapperSDKAgents:wrapperSDKAgents completion:callback];
        case ARTAuthenticationTokenRetry:
            _tokenErrorRetries = _tokenErrorRetries + 1;
            return [self executeRequestWithAuthentication:request withMethod:self.auth.method force:YES wrapperSDKAgents:wrapperSDKAgents completion:callback];
        case ARTAuthenticationUseBasic:
            return [self executeRequestWithAuthentication:request withMethod:ARTAuthMethodBasic wrapperSDKAgents:wrapperSDKAgents completion:callback];
    }
}

- (NSObject<ARTCancellable> *)executeRequestWithAuthentication:(NSMutableURLRequest *)request
                                                    withMethod:(ARTAuthMethod)method
                                              wrapperSDKAgents:(nullable NSDictionary<NSString *, NSString *> *)wrapperSDKAgents
                                                    completion:(ARTURLRequestCallback)callback {
    return [self executeRequestWithAuthentication:request withMethod:method force:NO wrapperSDKAgents:wrapperSDKAgents completion:callback];
}

- (NSObject<ARTCancellable> *)executeRequestWithAuthentication:(NSMutableURLRequest *)request
                                                    withMethod:(ARTAuthMethod)method
                                                         force:(BOOL)force
                                              wrapperSDKAgents:(nullable NSDictionary<NSString *, NSString *> *)wrapperSDKAgents
                                                    completion:(ARTURLRequestCallback)callback {
    ARTLogDebug(self.logger, @"RS:%p calculating authorization %lu", self, (unsigned long)method);
    __block NSObject<ARTCancellable> *task;

    if (method == ARTAuthMethodBasic) {
        // Basic
        NSString *authorization = [self prepareBasicAuthorisationHeader:self.options.key];
        [request setValue:authorization forHTTPHeaderField:@"Authorization"];
        ARTLogVerbose(self.logger, @"RS:%p ARTHttpClient: %@", self, authorization);
        task = [self executeRequest:request wrapperSDKAgents:wrapperSDKAgents completion:callback];
    }
    else {
        if (!force && [self.auth tokenRemainsValid]) {
            // Reuse token
            NSString *authorization = [self prepareTokenAuthorisationHeader:self.auth.tokenDetails.token];
            ARTLogVerbose(self.logger, @"RS:%p ARTHttpClientInternal reusing token: authorization bearer in Base64 %@", self, authorization);
            [request setValue:authorization forHTTPHeaderField:@"Authorization"];
            task = [self executeRequest:request wrapperSDKAgents:wrapperSDKAgents completion:callback];
        }
        else {
            // New Token
            task = [self.auth _authorize:nil options:self.options callback:^(ARTTokenDetails *tokenDetails, NSError *error) {
                if (error) {
                    ARTLogDebug(self.logger, @"RS:%p ARTHttpClientInternal reissuing token failed %@", self, error);
                    if (callback) callback(nil, nil, error);
                    return;
                }
                NSString *authorization = [self prepareTokenAuthorisationHeader:tokenDetails.token];
                ARTLogVerbose(self.logger, @"RS:%p ARTHttpClientInternal reissuing token: authorization bearer %@", self, authorization);
                [request setValue:authorization forHTTPHeaderField:@"Authorization"];
                task = [self executeRequest:request wrapperSDKAgents:wrapperSDKAgents completion:callback];
            }];
        }
    }
    return task;
}

- (NSObject<ARTCancellable> *)executeRequest:(NSURLRequest *)request
                            wrapperSDKAgents:(nullable NSDictionary<NSString *, NSString *> *)wrapperSDKAgents
                                  completion:(ARTURLRequestCallback)callback {
    return [self executeRequest:request fallbacks:nil retries:0 originalRequestId:nil wrapperSDKAgents:wrapperSDKAgents completion:callback];
}

- (NSString *)agentIdentifierWithWrapperSDKAgents:(nullable NSDictionary<NSString *, NSString *> *)wrapperSDKAgents {
    NSMutableDictionary<NSString *, NSString *> *additionalAgents = [NSMutableDictionary dictionary];

    for (NSString *additionalAgentName in _options.agents) {
        additionalAgents[additionalAgentName] = _options.agents[additionalAgentName];
    }

    for (NSString *additionalAgentName in wrapperSDKAgents) {
        additionalAgents[additionalAgentName] = wrapperSDKAgents[additionalAgentName];
    }

    return [ARTClientInformation agentIdentifierWithAdditionalAgents:additionalAgents];
}

/**
 originalRequestId is used only for fallback requests. It should never be used to execute request by yourself, it's passed from within below method.
 */
- (NSObject<ARTCancellable> *)executeRequest:(NSURLRequest *)request
                                   fallbacks:(ARTFallback *)fallbacks
                                     retries:(NSUInteger)retries
                           originalRequestId:(nullable NSString *)originalRequestId
                            wrapperSDKAgents:(nullable NSDictionary<NSString *, NSString *> *)wrapperSDKAgents
                                  completion:(ARTURLRequestCallback)callback {
    NSString *requestId = nil;
    __block ARTFallback *blockFallbacks = fallbacks;

    if ([request isKindOfClass:[NSMutableURLRequest class]]) {
        NSMutableURLRequest *mutableRequest = (NSMutableURLRequest *)request;
        [mutableRequest setAcceptHeader:self.defaultEncoder encoders:self.encoders];
        [mutableRequest setTimeoutInterval:_options.httpRequestTimeout];
        // Only set X-Ably-Version if it's not already set (allows override for specific methods like stats)
        if (![mutableRequest valueForHTTPHeaderField:@"X-Ably-Version"]) {
            [mutableRequest setValue:[ARTDefault apiVersion] forHTTPHeaderField:@"X-Ably-Version"];
        }
        [mutableRequest setValue:[self agentIdentifierWithWrapperSDKAgents:wrapperSDKAgents] forHTTPHeaderField:@"Ably-Agent"];
        if (_options.clientId && !self.auth.isTokenAuth) {
            [mutableRequest setValue:encodeBase64(_options.clientId) forHTTPHeaderField:@"X-Ably-ClientId"];
        }

        if (_options.addRequestIds) {
            if (fallbacks != nil) {
                requestId = originalRequestId;
            } else {
                NSString *randomId = [NSUUID new].UUIDString;
                requestId = [[randomId dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
            }

            [mutableRequest appendQueryItem:[NSURLQueryItem queryItemWithName:@"request_id" value:requestId]];
        }

        // RSC15f - reset the successed fallback host on fallbackRetryTimeout expiration
        // change URLRequest host from `fallback host` to `default host`
        //
        if (self.currentFallbackHost != nil && self.fallbackRetryExpiration != nil && [[self.timeProvider continuousClockNow] isAfter:self.fallbackRetryExpiration]) {
            ARTLogDebug(self.logger, @"RS:%p fallbackRetryExpiration ids expired, reset `prioritizedHost` and `currentFallbackHost`", self);

            self.currentFallbackHost = nil;
            self.prioritizedHost = nil;
            [mutableRequest replaceHostWith:_options.restHost];
        }
    }


    ARTLogDebug(self.logger, @"RS:%p executing request %@", self, request);
    __block NSObject<ARTCancellable> *task;
    task = [self.httpExecutor executeRequest:request completion:^(NSHTTPURLResponse *response, NSData *data, NSError *error) {
        // Error messages in plaintext and HTML format (only if the URL request is different than `options.authUrl` and we don't have an error already)
        if (error == nil && data != nil && data.length != 0 && ![request.URL.host isEqualToString:[self.options.authUrl host]]) {
            NSString *contentType = [response.allHeaderFields objectForKey:@"Content-Type"];

            BOOL validContentType = NO;
            for (NSString *mimeType in [self->_encoders.allValues valueForKeyPath:@"mimeType"]) {
                if ([contentType containsString:mimeType]) {
                    validContentType = YES;
                    break;
                }
            }

            if (!validContentType) {
                NSString *plain = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                // Construct artificial error
                error = [ARTErrorInfo createWithCode:response.statusCode * 100
                                              status:response.statusCode
                                             message:[plain art_shortString] requestId:requestId];
                data = nil; // Discard data; format is unreliable.
                ARTLogError(self.logger, @"Request %@ failed with %@", request, error);
            }
        }

        if (response.statusCode >= 400) {
            if (data) {
                NSError *decodeError = nil;
                ARTErrorInfo *dataError = [self->_encoders[response.MIMEType] decodeErrorInfo:data
                                                                                   statusCode:response.statusCode
                                                                                        error:&decodeError];
                if ([self shouldRenewToken:&dataError] && [request isKindOfClass:[NSMutableURLRequest class]]) {
                    ARTLogDebug(self.logger, @"RS:%p retry request %@", self, request);
                    // Make a single attempt to reissue the token and resend the request
                    if (self->_tokenErrorRetries < 1) {
                        task = [self executeRequest:(NSMutableURLRequest *)request withAuthOption:ARTAuthenticationTokenRetry wrapperSDKAgents:wrapperSDKAgents completion:callback];
                        return;
                    }
                }
                if (dataError) {
                    error = dataError;
                }
                else if (decodeError) {
                    error = decodeError;
                }
            }
            if (!error) {
                // Return error with HTTP StatusCode if ARTErrorStatusCode does not exist
                error = [ARTErrorInfo createWithCode:response.statusCode * 100
                                              status:response.statusCode
                                             message:[[NSString alloc] initWithData:data ?: [NSData data] encoding:NSUTF8StringEncoding]
                                           requestId:requestId];
            }

        } else {
            // Response Status Code < 400 and no errors
            if (error == nil && self.currentFallbackHost != nil) {
                ARTLogDebug(self.logger, @"RS:%p switching `prioritizedHost` to fallback host %@", self, self.currentFallbackHost);
                self.prioritizedHost = self.currentFallbackHost;
            }
        }

        if (retries < self->_options.httpMaxRetryCount && [self shouldRetryWithFallback:request response:response error:error]) {
            if (!blockFallbacks) {
                NSArray *hosts = [ARTFallbackHosts hostsFromOptions:self->_options];
                blockFallbacks = [[ARTFallback alloc] initWithFallbackHosts:hosts shuffleArray:self->_options.testOptions.shuffleArray];
            }
            if (blockFallbacks) {
                NSString *host = [blockFallbacks popFallbackHost];
                if (host != nil) {
                    ARTLogDebug(self.logger, @"RS:%p host is down; retrying request at %@", self, host);

                    self.currentFallbackHost = host;
                    NSMutableURLRequest *newRequest = [request copy];
                    [newRequest setValue:host forHTTPHeaderField:@"Host"];
                    newRequest.URL = [NSURL copyFromURL:request.URL withHost:host];
                    task = [self executeRequest:newRequest
                                      fallbacks:blockFallbacks
                                        retries:retries + 1
                              originalRequestId:originalRequestId
                               wrapperSDKAgents:wrapperSDKAgents
                                     completion:callback];
                    return;
                }
            }
        }
        if (callback) {
            if (error != nil) {
                if ([error isKindOfClass:[ARTErrorInfo class]]) {
                    callback(response, data, error);
                } else {
                    callback(response, data, [NSError copyFromError:error withRequestId:requestId]);
                }
            } else {
                callback(response, data, nil);
            }
        }
    }];

    return task;
}

- (BOOL)shouldRenewToken:(ARTErrorInfo **)errorPtr {
    if (errorPtr && *errorPtr && [[[ARTDefaultErrorChecker alloc] init] isTokenError: *errorPtr]) {
        if ([self.auth tokenIsRenewable]) {
            return YES;
        }
        *errorPtr = [ARTErrorInfo createWithCode:ARTStateRequestTokenFailed message:ARTAblyMessageNoMeansToRenewToken];
    }
    return NO;
}

- (BOOL)shouldRetryWithFallback:(NSURLRequest *)request response:(NSHTTPURLResponse *)response error:(NSError *)error {
    if ([request.URL.host isEqualToString:self.options.authUrl.host]) {
        return NO;
    }
    if (response.statusCode >= 500 && response.statusCode <= 504) {
        return YES;
    }
    if (error && (error.domain == NSURLErrorDomain && (
        error.code == -1003 || // Unreachable
        error.code == -1001 // timed out
    ))) {
        return YES;
    }
    return NO;
}

- (NSString *)currentHost {
    if (_prioritizedHost) {
        // Test purpose only
        return _prioritizedHost;
    }
    return self.options.restHost;
}

- (NSString *)prepareBasicAuthorisationHeader:(NSString *)key {
    // Include key Base64 encoded in an Authorization header (RFC7235)
    NSData *keyData = [key dataUsingEncoding:NSUTF8StringEncoding];
    NSString *keyBase64 = [keyData base64EncodedStringWithOptions:0];
    return [NSString stringWithFormat:@"Basic %@", keyBase64];
}

- (NSString *)prepareTokenAuthorisationHeader:(NSString *)token {
    // RSA3b: For REST requests, the token string is *optionally* Base64-encoded
    return [NSString stringWithFormat:@"Bearer %@", token];
}

- (void)timeWithWrapperSDKAgents:(nullable NSStringDictionary *)wrapperSDKAgents
                      completion:(ARTDateTimeCallback)callback {
    if (callback) {
        ARTDateTimeCallback userCallback = callback;
        callback = ^(NSDate *time, NSError *error) {
            art_dispatch_async(self->_userQueue, ^{
                userCallback(time, error);
            });
        };
    }
    art_dispatch_async(_queue, ^{
        [self _timeWithWrapperSDKAgents:wrapperSDKAgents
                             completion:callback];
    });
}

- (NSObject<ARTCancellable> *)_timeWithWrapperSDKAgents:(nullable NSStringDictionary *)wrapperSDKAgents
                                             completion:(ARTDateTimeCallback)callback {
    NSURL *requestUrl = [NSURL URLWithString:@"/time" relativeToURL:self.baseUrl];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:requestUrl];
    request.HTTPMethod = @"GET";
    NSString *accept = [[_encoders.allValues valueForKeyPath:@"mimeType"] componentsJoinedByString:@","];
    [request setValue:accept forHTTPHeaderField:@"Accept"];

    return [self executeRequest:request withAuthOption:ARTAuthenticationOff wrapperSDKAgents:wrapperSDKAgents completion:^(NSHTTPURLResponse *response, NSData *data, NSError *error) {
        if (error) {
            callback(nil, error);
            return;
        }
        NSError *decodeError = nil;
        if (response.statusCode >= 400) {
            ARTErrorInfo *dataError = [self->_encoders[response.MIMEType] decodeErrorInfo:data
                                                                               statusCode:response.statusCode
                                                                                    error:&decodeError];
            callback(nil, dataError ? dataError : decodeError);
        } else {
            NSDate *time = [self->_encoders[response.MIMEType] decodeTime:data error:&decodeError];
            callback(time, decodeError);
        }
    }];
}

- (BOOL)request:(NSString *)method
           path:(NSString *)path
         params:(nullable NSStringDictionary *)params
           body:(nullable id)body
        headers:(nullable NSStringDictionary *)headers
wrapperSDKAgents:(nullable NSStringDictionary *)wrapperSDKAgents
       callback:(ARTHTTPPaginatedCallback)callback
          error:(NSError **)errorPtr {

    if (callback) {
        void (^userCallback)(ARTHTTPPaginatedResponse *, ARTErrorInfo *) = callback;
        callback = ^(ARTHTTPPaginatedResponse *r, ARTErrorInfo *e) {
            art_dispatch_async(self->_userQueue, ^{
                userCallback(r, e);
            });
        };
    }

    if (![[method lowercaseString] isEqualToString:@"get"] &&
        ![[method lowercaseString] isEqualToString:@"post"] &&
        ![[method lowercaseString] isEqualToString:@"patch"] &&
        ![[method lowercaseString] isEqualToString:@"put"] &&
        ![[method lowercaseString] isEqualToString:@"delete"]) {
        if (errorPtr) {
            *errorPtr = [NSError errorWithDomain:ARTAblyErrorDomain
                                            code:ARTCustomRequestErrorInvalidMethod
                                        userInfo:@{NSLocalizedDescriptionKey:@"Method isn't valid."}];
        }
        return NO;
    }

    if (body &&
        ![body isKindOfClass:[NSDictionary class]] &&
        ![body isKindOfClass:[NSArray class]]) {
        if (errorPtr) {
            *errorPtr = [NSError errorWithDomain:ARTAblyErrorDomain
                                            code:ARTCustomRequestErrorInvalidBody
                                        userInfo:@{NSLocalizedDescriptionKey:@"Body should be a Dictionary or an Array."}];
        }
        return NO;
    }

    if ([[path stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] isEqualToString:@""]) {
        if (errorPtr) {
            *errorPtr = [NSError errorWithDomain:ARTAblyErrorDomain
                                            code:ARTCustomRequestErrorInvalidPath
                                        userInfo:@{NSLocalizedDescriptionKey:@"Path cannot be empty."}];
        }
        return NO;
    }

    NSURL *url = [NSURL URLWithString:path relativeToURL:self.baseUrl];
    // Should not happen in iOS 17 and above. See explanation in the "Important" section here:
    // https://developer.apple.com/documentation/foundation/nsurl/1572047-urlwithstring
    if (!url) {
        if (errorPtr) {
            *errorPtr = [NSError errorWithDomain:ARTAblyErrorDomain
                                            code:ARTCustomRequestErrorInvalidPath
                                        userInfo:@{NSLocalizedDescriptionKey:@"Path isn't valid for an URL."}];
        }
        return NO;
    }

    NSURLComponents *components = [[NSURLComponents alloc] initWithURL:url resolvingAgainstBaseURL:YES];
    __block NSMutableArray<NSURLQueryItem *> *queryItems = nil;
    [params enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
        if (!queryItems) {
            queryItems = [NSMutableArray new];
        }
        [queryItems addObject:[NSURLQueryItem queryItemWithName:key value:value]];
    }];
    components.queryItems = queryItems;

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[components URL]];
    request.HTTPMethod = method;

    [headers enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
        [request addValue:value forHTTPHeaderField:key];
    }];

    if (body != nil) {
        NSError *encodeError = nil;
        NSData *bodyData = [self.defaultEncoder encode:body error:&encodeError];

        request.HTTPBody = bodyData;
        [request setValue:[self.defaultEncoder mimeType] forHTTPHeaderField:@"Content-Type"];
        if ([[method lowercaseString] isEqualToString:@"post"]) {
            [request setValue:[NSString stringWithFormat:@"%d", (unsigned int)bodyData.length] forHTTPHeaderField:@"Content-Length"];
        }
    }

    [request setAcceptHeader:self.defaultEncoder encoders:self.encoders];

    ARTLogDebug(self.logger, @"request %@ %@", method, path);
    art_dispatch_async(_queue, ^{
        [ARTHTTPPaginatedResponse executePaginated:self withRequest:request wrapperSDKAgents:wrapperSDKAgents logger:self.logger callback:callback];
    });
    return YES;
}

- (NSObject<ARTCancellable> *)internetIsUp:(void (^)(BOOL isUp)) cb {
    NSURL *requestUrl = [NSURL URLWithString:@"https://internet-up.ably-realtime.com/is-the-internet-up.txt"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:requestUrl];
    request.HTTPMethod = @"GET";

    return [_httpExecutor executeRequest:request completion:^(NSHTTPURLResponse *response, NSData *data, NSError *error) {
        if (error) {
            cb(NO);
            return;
        }
        NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        cb(response.statusCode == 200 && str && [str isEqualToString:@"yes\n"]);
    }];
}

- (BOOL)statsWithWrapperSDKAgents:(nullable NSStringDictionary *)wrapperSDKAgents
                       completion:(ARTPaginatedStatsCallback)callback {
    return [self stats:[[ARTStatsQuery alloc] init] wrapperSDKAgents:wrapperSDKAgents callback:callback error:nil];
}

- (BOOL)stats:(ARTStatsQuery *)query wrapperSDKAgents:(nullable NSStringDictionary *)wrapperSDKAgents callback:(ARTPaginatedStatsCallback)callback error:(NSError **)errorPtr {
    if (callback) {
        ARTPaginatedStatsCallback userCallback = callback;
        callback = ^(ARTPaginatedResult<ARTStats *> *r, ARTErrorInfo *e) {
            art_dispatch_async(self->_userQueue, ^{
                userCallback(r, e);
            });
        };
    }

    if (query.limit > 1000) {
        if (errorPtr) {
            *errorPtr = [NSError errorWithDomain:ARTAblyErrorDomain
                                            code:ARTDataQueryErrorLimit
                                        userInfo:@{NSLocalizedDescriptionKey:@"Limit supports up to 1000 results only"}];
        }
        return NO;
    }
    if ([query.start compare:query.end] == NSOrderedDescending) {
        if (errorPtr) {
            *errorPtr = [NSError errorWithDomain:ARTAblyErrorDomain
                                            code:ARTDataQueryErrorTimestampRange
                                        userInfo:@{NSLocalizedDescriptionKey:@"Start must be equal to or less than end"}];
        }
        return NO;
    }

    NSURLComponents *requestUrl = [NSURLComponents componentsWithString:@"/stats"];
    NSError *error = nil;
    requestUrl.queryItems = [query asQueryItems:&error];
    if (error) {
        if (errorPtr) {
            *errorPtr = error;
        }
        return NO;
    }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[requestUrl URLRelativeToURL:self.baseUrl]];

    // Override X-Ably-Version header to use protocol version 2 for stats
    [request setValue:@"2" forHTTPHeaderField:@"X-Ably-Version"];

    ARTPaginatedResultResponseProcessor responseProcessor = ^(NSHTTPURLResponse *response, NSData *data, NSError **errorPtr) {
        return [self.encoders[response.MIMEType] decodeStats:data error:errorPtr];
    };

art_dispatch_async(_queue, ^{
    [ARTPaginatedResult executePaginated:self withRequest:request andResponseProcessor:responseProcessor wrapperSDKAgents:wrapperSDKAgents logger:self.logger callback:callback];
});
    return YES;
}

- (id<ARTEncoder>)defaultEncoder {
    return self.encoders[self.defaultEncoding];
}

- (NSURL *)getBaseUrl {
    NSURLComponents *components = [_options restUrlComponents];
    NSString *prioritizedHost = self.prioritizedHost; // Important to use the property, not the variable; it's atomic!
    if (prioritizedHost) {
        components.host = prioritizedHost;
    }
    return components.URL;
}

- (void)setCurrentFallbackHost:(NSString *)value {
    if (value == nil) {
        _fallbackRetryExpiration = nil;
    }

    if ([_currentFallbackHost isEqual:value]) {
        return;
    }

    _currentFallbackHost = value;

    id<ARTContinuousClockInstant> const now = [self.timeProvider continuousClockNow];
    _fallbackRetryExpiration = [now addingDuration:_options.fallbackRetryTimeout];
}

#if TARGET_OS_IOS
- (ARTLocalDevice *)device {
    __block ARTLocalDevice *ret;
    art_dispatch_sync(_queue, ^{
        ret = [self device_nosync];
    });
    return ret;
}

- (ARTLocalDevice *)device_nosync {
    if (_options.testOptions.disableLocalDevice) {
        [NSException raise:NSInternalInconsistencyException
                    format:@"device_nosync invoked on a client configured with disableLocalDevice"];
    }
    __block ARTLocalDevice *ret;
    art_dispatch_sync([ARTHttpClientInternal deviceAccessQueue], ^{
        ret = [self sharedDevice_onlyCallOnDeviceAccessQueue];
    });
    return ret;
}

+ (dispatch_queue_t)deviceAccessQueue {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("io.ably.deviceAccess", DISPATCH_QUEUE_SERIAL);
    });

    return queue;
}

static BOOL sharedDeviceNeedsLoading_onlyAccessOnDeviceAccessQueue = YES;

- (ARTLocalDevice *)sharedDevice_onlyCallOnDeviceAccessQueue {
    // The device is shared in a static variable because it's a reflection
    // of what's persisted. Having a device instance per ARTHttpClient instance
    // could leave some instances in a stale state, if, through another
    // instance, the persisted state is changed.
    //
    // As a side effect, the first instance "wins" at setting the device's
    // client ID.

    static id device;
    if (sharedDeviceNeedsLoading_onlyAccessOnDeviceAccessQueue) {
        device = [ARTLocalDevice deviceWithStorage:self.storage logger:self.logger];
        sharedDeviceNeedsLoading_onlyAccessOnDeviceAccessQueue = NO;
    }
    return device;
}

- (void)setupLocalDevice_nosync {
    ARTLocalDevice *device = [self device_nosync];
    NSString *clientId = self.auth.clientId_nosync;
    art_dispatch_sync([ARTHttpClientInternal deviceAccessQueue], ^{
        [device setupDetailsWithClientId:clientId];
    });
}

- (void)resetLocalDevice_nosync {
    ARTLocalDevice *device = [self device_nosync];
    art_dispatch_sync([ARTHttpClientInternal deviceAccessQueue], ^{
        [device resetDetails];
    });
}

- (void)resetDeviceSingleton {
    art_dispatch_sync([ARTHttpClientInternal deviceAccessQueue], ^{
        sharedDeviceNeedsLoading_onlyAccessOnDeviceAccessQueue = YES;
    });
}

- (void)setAndPersistAPNSDeviceTokenData:(NSData *)deviceTokenData tokenType:(NSString *)tokenType {
    NSString *deviceToken = deviceTokenData.deviceTokenString;
    ARTLogInfo(self.logger, @"ARTHttpClient: device token: %@ of type: `%@`", deviceToken, tokenType);

    NSString *currentDeviceToken = [ARTLocalDevice apnsDeviceTokenOfType:tokenType fromStorage:self.storage];
    if ([currentDeviceToken isEqualToString:deviceToken]) {
        // Already stored.
        return;
    }

    [self.device_nosync setAndPersistAPNSDeviceToken:deviceToken tokenType:tokenType];
    ARTLogDebug(self.logger, @"ARTHttpClient: device token stored");

    [self.push getActivationMachine:^(ARTPushActivationStateMachine *_Nullable stateMachine) {
        [stateMachine sendEvent:[ARTPushActivationEventGotPushDeviceDetails new]];
    }];
}

#endif

@end

@implementation NSData (APNS)

- (NSString *)deviceTokenString {
    NSUInteger dataLength = self.length;
    const unsigned char *dataBuffer = self.bytes;
    NSMutableString *hexString = [NSMutableString stringWithCapacity:(dataLength * 2)];
    for (int i = 0; i < dataLength; ++i) {
        [hexString appendFormat:@"%02x", dataBuffer[i]];
    }
    return [hexString copy];
}

@end
