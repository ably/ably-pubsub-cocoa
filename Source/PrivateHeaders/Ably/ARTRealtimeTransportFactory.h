@import Foundation;

@class ARTHttpClientInternal;
@class ARTClientOptions;
@class ARTInternalLog;
@protocol ARTRealtimeTransport;

NS_ASSUME_NONNULL_BEGIN

/**
 A factory for creating an `ARTRealtimeTransport` instance.
 */
NS_SWIFT_NAME(RealtimeTransportFactory)
@protocol ARTRealtimeTransportFactory

- (id<ARTRealtimeTransport>)transportWithRest:(ARTHttpClientInternal *)rest
                                      options:(ARTClientOptions *)options
                                    resumeKey:(nullable NSString *)resumeKey
                                       logger:(ARTInternalLog *)logger;

@end

/**
 The implementation of `ARTRealtimeTransportFactory` that should be used in non-test code.
 */
NS_SWIFT_NAME(DefaultRealtimeTransportFactory)
@interface ARTDefaultRealtimeTransportFactory: NSObject<ARTRealtimeTransportFactory>
@end

NS_ASSUME_NONNULL_END
