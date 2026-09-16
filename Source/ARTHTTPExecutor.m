#import "ARTHTTPExecutor+Private.h"
#import "ARTURLSessionServerTrust.h"
#import "ARTConstants.h"
#import "ARTInternalLog.h"

@interface ARTHTTPExecutor ()

@property (readonly, nonatomic) id<ARTURLSession> urlSession;

@end

Class configuredUrlSessionClass = nil;

#pragma mark - ARTHTTPExecutor

@implementation ARTHTTPExecutor {
    ARTInternalLog *_logger;
}

+ (void)setURLSessionClass:(const Class)urlSessionClass {
    configuredUrlSessionClass = urlSessionClass;
}

- (instancetype)initWithQueue:(dispatch_queue_t)queue logger:(ARTInternalLog *)logger {
    self = [super init];
    if (self) {
        const Class urlSessionClass = configuredUrlSessionClass ? configuredUrlSessionClass : [ARTURLSessionServerTrust class];
        _urlSession = [[urlSessionClass alloc] init:queue];
        _logger = logger;
    }
    return self;
}

- (ARTInternalLog *)logger {
    return _logger;
}

- (dispatch_queue_t)queue {
    return _urlSession.queue;
}

- (void)dealloc {
    [_urlSession finishTasksAndInvalidate];
}

- (NSObject<ARTCancellable> *)executeRequest:(NSMutableURLRequest *)request completion:(ARTURLRequestCallback)callback {
    ARTLogDebug(self.logger, @"--> %@ %@\n  Body: %@\n  Headers: %@", request.HTTPMethod, request.URL.absoluteString, [self debugDescriptionOfBodyWithData:request.HTTPBody], request.allHTTPHeaderFields);

    return [_urlSession get:request completion:^(NSHTTPURLResponse *response, NSData *data, NSError *error) {
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (error) {
            ARTLogError(self.logger, @"<-- %@ %@: error %@", request.HTTPMethod, request.URL.absoluteString, error);
        } else {
            ARTLogDebug(self.logger, @"<-- %@ %@: statusCode %ld\n  Data: %@\n  Headers: %@\n", request.HTTPMethod, request.URL.absoluteString, (long)httpResponse.statusCode, [self debugDescriptionOfBodyWithData:data], httpResponse.allHeaderFields);
            NSString *headerErrorMessage = httpResponse.allHeaderFields[ARTHttpHeaderFieldErrorMessageKey];
            if (headerErrorMessage && ![headerErrorMessage isEqualToString:@""]) {
                ARTLogWarn(self.logger, @"%@", headerErrorMessage);
            }
        }
        callback(httpResponse, data, error);
    }];
}

- (NSString *)debugDescriptionOfBodyWithData:(NSData *)data {
    if (self.logger.logLevel <= ARTLogLevelDebug) {
        NSString *requestBodyStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (!requestBodyStr) {
            requestBodyStr = [data base64EncodedStringWithOptions:NSDataBase64EncodingEndLineWithCarriageReturn];
        }
        return requestBodyStr;
    }
    return nil;
}

@end
