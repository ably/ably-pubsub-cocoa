#import "ARTPaginatedResult+Private.h"
#import "ARTPaginatedResult+Subclass.h"

#import "ARTHTTPExecutor.h"
#import "ARTAuth.h"
#import "ARTHttpClient+Private.h"
#import "ARTNSMutableURLRequest+ARTPaginated.h"
#import "ARTNSHTTPURLResponse+ARTPaginated.h"
#import "ARTInternalLog.h"
#import "ARTGCD.h"

@implementation ARTPaginatedResult {
    BOOL _initializedViaInit;

    // All of the below instance variables are non-nil if and only if _initializedViaInit is NO
    ARTHttpClientInternal *_Nullable _rest;
    dispatch_queue_t _Nullable _userQueue;
    dispatch_queue_t _Nullable _queue;
    NSMutableURLRequest *_Nullable _relFirst;
    NSMutableURLRequest *_Nullable _relCurrent;
    NSMutableURLRequest *_Nullable _relNext;
    ARTPaginatedResultResponseProcessor _Nullable _responseProcessor;
    ARTQueuedDealloc *_Nullable _dealloc;
}

@synthesize rest = _rest;
@synthesize userQueue = _userQueue;
@synthesize queue = _queue;
@synthesize relFirst = _relFirst;
@synthesize relCurrent = _relCurrent;
@synthesize relNext = _relNext;
@synthesize hasNext = _hasNext;
@synthesize isLast = _isLast;
@synthesize items = _items;

- (instancetype)init {
    if (self = [super init]) {
        _initializedViaInit = YES;
    }

    return self;
}

- (instancetype)initWithItems:(NSArray *)items
                     rest:(ARTHttpClientInternal *)rest
                     relFirst:(NSMutableURLRequest *)relFirst
                   relCurrent:(NSMutableURLRequest *)relCurrent
                      relNext:(NSMutableURLRequest *)relNext
            responseProcessor:(ARTPaginatedResultResponseProcessor)responseProcessor
             wrapperSDKAgents:(nullable NSStringDictionary *)wrapperSDKAgents
                       logger:(ARTInternalLog *)logger {
    if (self = [super init]) {
        _initializedViaInit = NO;

        _items = items;

        _relFirst = relFirst;

        _relCurrent = relCurrent;

        _relNext = relNext;
        _hasNext = !!relNext;
        _isLast = !_hasNext;

        _rest = rest;
        _userQueue = rest.userQueue;
        _queue = rest.queue;
        _responseProcessor = responseProcessor;
        _wrapperSDKAgents = wrapperSDKAgents;
        _logger = logger;

        // ARTPaginatedResult doesn't need a internal counterpart, as other
        // public objects do. It basically acts as a proxy to a
        // strongly-referenced ARTHttpClientInternal, so it can be thought as an
        // alternative public counterpart to ARTHttpClientInternal.
        //
        // So, since it's owned by user code, it should dispatch its release of
        // its ARTHttpClientInternal to the internal queue. We could take the common
        // ARTQueuedDealloc as an argument as other public objects do, but
        // that would just be bookkeeping since we know it will be initialized
        // from the ARTHttpClientInternal we already have access to anyway, so we can
        // make our own.
        _dealloc = [[ARTQueuedDealloc alloc] init:_rest queue:_queue];
    }

    return self;
}

- (void)initializedViaInitCheck {
    if (_initializedViaInit) {
        [NSException raise:NSInternalInconsistencyException format:@"When initializing this class using -init, you need to override this method in a subclass"];
    }
}

- (BOOL)hasNext {
    [self initializedViaInitCheck];
    return _hasNext;
}

- (BOOL)isLast {
    [self initializedViaInitCheck];
    return _isLast;
}

- (NSArray<id> *)items {
    [self initializedViaInitCheck];
    return _items;
}

- (void)first:(void (^)(ARTPaginatedResult<id> *_Nullable result, ARTErrorInfo *_Nullable error))callback {
    [self initializedViaInitCheck];

    if (callback) {
        void (^userCallback)(ARTPaginatedResult<id> *_Nullable result, ARTErrorInfo *_Nullable error) = callback;
        callback = ^(ARTPaginatedResult<id> *_Nullable result, ARTErrorInfo *_Nullable error) {
            art_dispatch_async(self->_userQueue, ^{
                userCallback(result, error);
            });
        };
    }

    [self.class executePaginated:_rest withRequest:_relFirst andResponseProcessor:_responseProcessor wrapperSDKAgents:_wrapperSDKAgents logger:_logger callback:callback];
}

- (void)next:(void (^)(ARTPaginatedResult<id> *_Nullable result, ARTErrorInfo *_Nullable error))callback {
    [self initializedViaInitCheck];

    if (callback) {
        void (^userCallback)(ARTPaginatedResult<id> *_Nullable result, ARTErrorInfo *_Nullable error) = callback;
        callback = ^(ARTPaginatedResult<id> *_Nullable result, ARTErrorInfo *_Nullable error) {
            art_dispatch_async(self->_userQueue, ^{
                userCallback(result, error);
            });
        };
    }

    if (!_relNext) {
        // If there is no next page, we can't make a request, so we answer the callback
        // with a nil PaginatedResult. That's why the callback has the result as nullable
        // anyway. (That, and that it can fail.)
        callback(nil, nil);
        return;
    }
    [self.class executePaginated:_rest withRequest:_relNext andResponseProcessor:_responseProcessor wrapperSDKAgents:_wrapperSDKAgents logger:_logger callback:callback];
}

+ (void)executePaginated:(ARTHttpClientInternal *)rest withRequest:(NSMutableURLRequest *)request andResponseProcessor:(ARTPaginatedResultResponseProcessor)responseProcessor wrapperSDKAgents:(nullable NSStringDictionary *)wrapperSDKAgents logger:(ARTInternalLog *)logger callback:(void (^)(ARTPaginatedResult<id> *_Nullable result, ARTErrorInfo *_Nullable error))callback {
    ARTLogDebug(logger, @"Paginated request: %@", request);

    [rest executeRequest:request withAuthOption:ARTAuthenticationOn wrapperSDKAgents:wrapperSDKAgents completion:^(NSHTTPURLResponse *response, NSData *data, NSError *error) {
        if (error) {
            callback(nil, [ARTErrorInfo createFromNSError:error]);
        } else {
            ARTLogDebug(logger, @"Paginated response: %@", response);
            ARTLogDebug(logger, @"Paginated response data: %@", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);

            NSError *decodeError = nil;
            NSArray *items = responseProcessor(response, data, &decodeError);

            if (decodeError) {
                callback(nil, [ARTErrorInfo createFromNSError:decodeError]);
                return;
            }

            NSDictionary *links = [response extractLinks];

            NSMutableURLRequest *firstRel = [NSMutableURLRequest requestWithPath:links[@"first"] relativeTo:request];
            NSMutableURLRequest *currentRel = [NSMutableURLRequest requestWithPath:links[@"current"] relativeTo:request];
            NSMutableURLRequest *nextRel = [NSMutableURLRequest requestWithPath:links[@"next"] relativeTo:request];

            ARTPaginatedResult *result = [[ARTPaginatedResult alloc] initWithItems:items
                                                                              rest:rest
                                                                          relFirst:firstRel
                                                                        relCurrent:currentRel
                                                                           relNext:nextRel
                                                                 responseProcessor:responseProcessor
                                                                  wrapperSDKAgents:wrapperSDKAgents
                                                                            logger:logger];

            callback(result, nil);
        }
    }];
}

@end
