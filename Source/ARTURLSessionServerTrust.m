#import "ARTURLSessionServerTrust.h"
#import "ARTGCD.h"

@interface ARTURLSessionServerTrust() {
    NSURLSession *_session;
    dispatch_queue_t _queue;
}

@end

@implementation ARTURLSessionServerTrust

- (instancetype)init:(dispatch_queue_t)queue {
    if (self = [super init]) {
        _queue = queue;
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        config.TLSMinimumSupportedProtocolVersion = tls_protocol_version_TLSv12;
        _session = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:nil];
    }
    return self;
}

- (dispatch_queue_t)queue {
    return _queue;
}

- (void)finishTasksAndInvalidate {
    [_session finishTasksAndInvalidate];
}

- (NSObject<ARTCancellable> *)get:(NSURLRequest *)request completion:(ARTURLRequestCallback)callback {
    NSURLSessionDataTask *task = [_session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        art_dispatch_async(self->_queue, ^{
            callback((NSHTTPURLResponse *)response, data, error);
        });
    }];
    [task resume];
    return task;
}

@end
