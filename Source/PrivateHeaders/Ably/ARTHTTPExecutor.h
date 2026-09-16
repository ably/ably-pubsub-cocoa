#import <Foundation/Foundation.h>

#import <AblyPubSubDevice/ARTTypes.h>

@class ARTErrorInfo;
@class ARTClientOptions;
@class ARTInternalLog;

@protocol ARTEncoder;

NS_ASSUME_NONNULL_BEGIN

@protocol ARTHTTPExecuting

- (nullable NSObject<ARTCancellable> *)executeRequest:(NSURLRequest *)request
                                           completion:(nullable ARTURLRequestCallback)callback;

@end

@interface ARTHTTPExecutor : NSObject<ARTHTTPExecuting>

+ (void)setURLSessionClass:(Class)urlSessionClass;

- (instancetype)init UNAVAILABLE_ATTRIBUTE;
- (instancetype)initWithQueue:(dispatch_queue_t)queue logger:(ARTInternalLog *)logger;

@end

NS_ASSUME_NONNULL_END
