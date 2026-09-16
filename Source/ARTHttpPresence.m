#import "ARTHttpPresence+Private.h"

#import "ARTPresence+Private.h"
#import "ARTHttpClient+Private.h"
#import "ARTHttpChannel+Private.h"
#import "ARTPaginatedResult+Private.h"
#import "ARTDataQuery+Private.h"
#import "ARTJsonEncoder.h"
#import "ARTNSArray+ARTFunctional.h"
#import "ARTChannel+Private.h"
#import "ARTBaseMessage+Private.h"
#import "ARTInternalLog.h"
#import "ARTGCD.h"

#import "ARTChannel.h"
#import "ARTDataQuery.h"

@implementation ARTPresenceQuery

- (instancetype)init {
    return [self initWithClientId:nil connectionId:nil];
}

- (instancetype)initWithClientId:(NSString *)clientId connectionId:(NSString *)connectionId {
    return [self initWithLimit:100 clientId:clientId connectionId:connectionId];
}

- (instancetype)initWithLimit:(NSUInteger)limit clientId:(NSString *)clientId connectionId:(NSString *)connectionId {
    self = [super init];
    if (self) {
        _limit = limit;
        _clientId = clientId;
        _connectionId = connectionId;
    }
    return self;
}

- (NSMutableArray *)asQueryItems {
    NSMutableArray *items = [NSMutableArray array];

    if (self.clientId) {
        [items addObject:[NSURLQueryItem queryItemWithName:@"clientId" value:self.clientId]];
    }
    if (self.connectionId) {
        [items addObject:[NSURLQueryItem queryItemWithName:@"connectionId" value:self.connectionId]];
    }

    [items addObject:[NSURLQueryItem queryItemWithName:@"limit" value:[NSString stringWithFormat:@"%lu", (unsigned long)self.limit]]];

    return items;
}

@end

@implementation ARTHttpPresence {
    ARTQueuedDealloc *_dealloc;
}

- (instancetype)initWithInternal:(ARTHttpPresenceInternal *)internal queuedDealloc:(ARTQueuedDealloc *)dealloc {
    self = [super init];
    if (self) {
        _internal = internal;
        _dealloc = dealloc;
    }
    return self;
}

- (void)get:(ARTPaginatedPresenceCallback)callback {
    [_internal get:callback];
}

- (BOOL)get:(ARTPaginatedPresenceCallback)callback error:(NSError *_Nullable *_Nullable)errorPtr {
    return [_internal get:callback error:errorPtr];
}

- (BOOL)get:(ARTPresenceQuery *)query callback:(ARTPaginatedPresenceCallback)callback error:(NSError *_Nullable *_Nullable)errorPtr {
    return [_internal get:query callback:callback error:errorPtr];
}

- (BOOL)history:(nullable ARTDataQuery *)query callback:(ARTPaginatedPresenceCallback)callback error:(NSError *_Nullable *_Nullable)errorPtr {
    return [_internal history:query wrapperSDKAgents:nil callback:callback error:errorPtr];
}

- (void)history:(ARTPaginatedPresenceCallback)callback {
    [_internal historyWithWrapperSDKAgents:nil completion:callback];
}

@end

NS_ASSUME_NONNULL_BEGIN

@interface ARTHttpPresenceInternal ()

@property (nonatomic, readonly) ARTInternalLog *logger;

@end

NS_ASSUME_NONNULL_END

@implementation ARTHttpPresenceInternal {
    __weak ARTHttpChannelInternal *_channel; // weak because channel owns self
    dispatch_queue_t _userQueue;
    dispatch_queue_t _queue;
}

- (instancetype)initWithChannel:(ARTHttpChannelInternal *)channel logger:(ARTInternalLog *)logger {
    if (self = [super init]) {
        _channel = channel;
        _userQueue = channel.rest.userQueue;
        _queue = channel.rest.queue;
        _logger = logger;
    }
    return self;
}

- (void)get:(ARTPaginatedPresenceCallback)callback {
    [self get:[[ARTPresenceQuery alloc] init] callback:callback error:nil];
}

- (BOOL)get:(ARTPaginatedPresenceCallback)callback error:(NSError **)errorPtr {
    return [self get:[[ARTPresenceQuery alloc] init] callback:callback error:errorPtr];
}

- (BOOL)get:(ARTPresenceQuery *)query callback:(ARTPaginatedPresenceCallback)callback error:(NSError **)errorPtr {
    if (callback) {
        ARTPaginatedPresenceCallback userCallback = callback;
        callback = ^(ARTPaginatedResult<ARTPresenceMessage *> *m, ARTErrorInfo *e) {
            art_dispatch_async(self->_userQueue, ^{
                userCallback(m, e);
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

    NSURLComponents *requestUrl = [NSURLComponents componentsWithString:[_channel.basePath stringByAppendingPathComponent:@"presence"]];
    requestUrl.queryItems = [query asQueryItems];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:requestUrl.URL];

    ARTPaginatedResultResponseProcessor responseProcessor = ^(NSHTTPURLResponse *response, NSData *data, NSError **errorPtr) {
        id<ARTEncoder> encoder = [self->_channel.rest.encoders objectForKey:response.MIMEType];
        return [[encoder decodePresenceMessages:data error:errorPtr] artMap:^(ARTPresenceMessage *message) {
            // FIXME: This should be refactored to be done by ART{Json,...}Encoder.
            // The ART{Json,...}Encoder should take a ARTDataEncoder and use it every
            // time it is enc/decoding a message. This also applies for REST and Realtime
            // ARTMessages.
            message = [message decodeWithEncoder:self->_channel.dataEncoder error:nil];
            return message;
        }];
    };

art_dispatch_async(_queue, ^{
    [ARTPaginatedResult executePaginated:self->_channel.rest withRequest:request andResponseProcessor:responseProcessor wrapperSDKAgents:nil logger:self->_logger callback:callback];
});
    return YES;
}

- (void)historyWithWrapperSDKAgents:(nullable NSStringDictionary *)wrapperSDKAgents
                         completion:(ARTPaginatedPresenceCallback)callback {
    [self history:[[ARTDataQuery alloc] init] wrapperSDKAgents:wrapperSDKAgents callback:callback error:nil];
}

- (BOOL)history:(ARTDataQuery *)query wrapperSDKAgents:(nullable NSStringDictionary *)wrapperSDKAgents callback:(ARTPaginatedPresenceCallback)callback error:(NSError **)errorPtr {
    if (callback) {
        void (^userCallback)(ARTPaginatedResult<ARTPresenceMessage *> *result, ARTErrorInfo *error) = callback;
        callback = ^(ARTPaginatedResult<ARTPresenceMessage *> *result, ARTErrorInfo *error) {
            art_dispatch_async(self->_userQueue, ^{
                userCallback(result, error);
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

    NSURLComponents *requestUrl = [NSURLComponents componentsWithString:[_channel.basePath stringByAppendingPathComponent:@"presence/history"]];
    NSError *error = nil;
    requestUrl.queryItems = [query asQueryItems:&error];
    if (error) {
        if (errorPtr) {
            *errorPtr = error;
        }
        return NO;
    }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:requestUrl.URL];

    ARTPaginatedResultResponseProcessor responseProcessor = ^(NSHTTPURLResponse *response, NSData *data, NSError **errorPtr) {
        id<ARTEncoder> encoder = [self->_channel.rest.encoders objectForKey:response.MIMEType];
        return [[encoder decodePresenceMessages:data error:errorPtr] artMap:^(ARTPresenceMessage *message) {
            NSError *decodeError = nil;
            message = [message decodeWithEncoder:self->_channel.dataEncoder error:&decodeError];
            if (decodeError != nil) {
                ARTErrorInfo *errorInfo = [ARTErrorInfo wrap:[ARTErrorInfo createWithCode:ARTErrorUnableToDecodeMessage message:decodeError.localizedFailureReason] prepend:@"Failed to decode data: "];
                ARTLogError(self.logger, @"RS:%p %@", self->_channel.rest, errorInfo.message);
            }
            return message;
        }];
    };

art_dispatch_async(_queue, ^{
    [ARTPaginatedResult executePaginated:self->_channel.rest withRequest:request andResponseProcessor:responseProcessor wrapperSDKAgents:wrapperSDKAgents logger:self->_logger callback:callback];
});
    return YES;
}

@end
