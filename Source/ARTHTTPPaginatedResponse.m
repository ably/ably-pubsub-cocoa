#import "ARTHTTPPaginatedResponse+Private.h"
#import "ARTPaginatedResult+Subclass.h"

#import "ARTHTTPExecutor.h"
#import "ARTAuth.h"
#import "ARTHttpClient+Private.h"
#import "ARTPaginatedResult+Private.h"
#import "ARTNSMutableURLRequest+ARTPaginated.h"
#import "ARTNSHTTPURLResponse+ARTPaginated.h"
#import "ARTEncoder.h"
#import "ARTConstants.h"
#import "ARTInternalLog.h"
#import "ARTGCD.h"

@implementation ARTHTTPPaginatedResponse

- (instancetype)initWithResponse:(NSHTTPURLResponse *)response
                           items:(NSArray *)items
                            rest:(ARTHttpClientInternal *)rest
                        relFirst:(NSMutableURLRequest *)relFirst
                      relCurrent:(NSMutableURLRequest *)relCurrent
                         relNext:(NSMutableURLRequest *)relNext
               responseProcessor:(ARTPaginatedResultResponseProcessor)responseProcessor
                wrapperSDKAgents:(nullable NSDictionary<NSString *,NSString *> *)wrapperSDKAgents
                          logger:(ARTInternalLog *)logger {
    self = [super initWithItems:items rest:rest relFirst:relFirst relCurrent:relCurrent relNext:relNext responseProcessor:responseProcessor wrapperSDKAgents:wrapperSDKAgents logger:logger];
    if (self) {
        _response = response;
    }
    return self;
}

- (NSInteger)statusCode {
    return _response.statusCode;
}

- (BOOL)success {
    return _response.statusCode >= 200 && _response.statusCode < 300;
}

- (NSInteger)errorCode {
    NSString *code = [_response.allHeaderFields valueForKey:ARTHttpHeaderFieldErrorCodeKey];
    return [code integerValue];
}

- (NSString *)errorMessage {
    NSString *message = [_response.allHeaderFields valueForKey:ARTHttpHeaderFieldErrorMessageKey];
    return message;
}

- (NSDictionary<NSString *,NSString *> *)headers {
    return _response.allHeaderFields;
}

- (void)first:(ARTHTTPPaginatedCallback)callback {
    if (callback) {
        void (^userCallback)(ARTHTTPPaginatedResponse *_Nullable result, ARTErrorInfo *_Nullable error) = callback;
        callback = ^(ARTHTTPPaginatedResponse *_Nullable result, ARTErrorInfo *_Nullable error) {
            art_dispatch_async(self.userQueue, ^{
                userCallback(result, error);
            });
        };
    }

    [self.class executePaginated:self.rest withRequest:self.relFirst wrapperSDKAgents:self.wrapperSDKAgents logger:self.logger callback:callback];
}

- (void)next:(ARTHTTPPaginatedCallback)callback {
    if (callback) {
        void (^userCallback)(ARTHTTPPaginatedResponse *_Nullable result, ARTErrorInfo *_Nullable error) = callback;
        callback = ^(ARTHTTPPaginatedResponse *_Nullable result, ARTErrorInfo *_Nullable error) {
            art_dispatch_async(self.userQueue, ^{
                userCallback(result, error);
            });
        };
    }

    if (!self.relNext) {
        // If there is no next page, we can't make a request, so we answer the callback
        // with a nil PaginatedResult. That's why the callback has the result as nullable
        // anyway. (That, and that it can fail.)
        callback(nil, nil);
        return;
    }

    [self.class executePaginated:self.rest withRequest:self.relNext wrapperSDKAgents:self.wrapperSDKAgents logger:self.logger callback:callback];
}

+ (void)executePaginated:(ARTHttpClientInternal *)rest
             withRequest:(NSMutableURLRequest *)request
        wrapperSDKAgents:(nullable NSDictionary<NSString *, NSString *> *)wrapperSDKAgents
                  logger:(ARTInternalLog *)logger
                callback:(ARTHTTPPaginatedCallback)callback {
    ARTLogDebug(logger, @"HTTP Paginated request: %@", request);

    [rest executeRequest:request withAuthOption:ARTAuthenticationOn wrapperSDKAgents:wrapperSDKAgents completion:^(NSHTTPURLResponse *response, NSData *data, NSError *error) {
        if (error && ![error.domain isEqualToString:ARTAblyErrorDomain]) {
            callback(nil, [ARTErrorInfo createFromNSError:error]);
            return;
        }

        ARTLogDebug(logger, @"HTTP Paginated response: %@", response);
        ARTLogDebug(logger, @"HTTP Paginated response data: %@", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);

        NSError *decodeError = nil;

        ARTPaginatedResultResponseProcessor responseProcessor = ^(NSHTTPURLResponse *response, NSData *data, NSError **errorPtr) {
            id<ARTEncoder> encoder = [rest.encoders objectForKey:response.MIMEType];
            return [encoder decodeToArray:data error:errorPtr];
        };
        NSArray *items = error ? @[] : responseProcessor(response, data, &decodeError);

        if (decodeError) {
            callback(nil, [ARTErrorInfo createFromNSError:decodeError]);
            return;
        }

        NSDictionary *links = [response extractLinks];

        NSMutableURLRequest *firstRel = [NSMutableURLRequest requestWithPath:links[@"first"] relativeTo:request];
        NSMutableURLRequest *currentRel = [NSMutableURLRequest requestWithPath:links[@"current"] relativeTo:request];
        NSMutableURLRequest *nextRel = [NSMutableURLRequest requestWithPath:links[@"next"] relativeTo:request];

        ARTHTTPPaginatedResponse *result = [[ARTHTTPPaginatedResponse alloc] initWithResponse:response items:items rest:rest relFirst:firstRel relCurrent:currentRel relNext:nextRel responseProcessor:responseProcessor wrapperSDKAgents:wrapperSDKAgents logger:logger];

        callback(result, nil);
    }];
}

@end
