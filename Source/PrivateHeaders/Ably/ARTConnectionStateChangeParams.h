@import Foundation;

@class ARTErrorInfo;
@class ARTRetryAttempt;

NS_ASSUME_NONNULL_BEGIN

/**
 Provides parameters for a request to perform an operation that may cause an `ARTPubSubClientInternal` instance to emit a connection state change.

 `ARTPubSubClientInternal` will incorporate this data into the `ARTConnectionStateChange` object that it emits as a result of the connection state change.
 */
NS_SWIFT_NAME(ConnectionStateChangeParams)
@interface ARTConnectionStateChangeParams: NSObject

/**
 Information about the error that triggered this state change, if any.
 */
@property (nullable, nonatomic, readonly) ARTErrorInfo *errorInfo;

@property (nullable, nonatomic, readonly) ARTRetryAttempt *retryAttempt;

@property (assign, nonatomic) BOOL resumed;

/**
 Creates an `ARTConnectionStateChangeParams` instance whose `errorInfo` is `nil`.
 */
- (instancetype)init;

- (instancetype)initWithErrorInfo:(nullable ARTErrorInfo *)errorInfo;

- (instancetype)initWithErrorInfo:(nullable ARTErrorInfo *)errorInfo
                     retryAttempt:(nullable ARTRetryAttempt *)retryAttempt NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
