@import Foundation;
#import <AblyPubSubDevice/ARTTypes.h>
#import "ARTStatus.h"

@class ARTErrorInfo;
@class ARTRetryAttempt;

NS_ASSUME_NONNULL_BEGIN

/**
 Provides parameters for a request to perform an operation that may cause an `ARTRealtimeChannelInternal` instance to emit a connection state change.

 `ARTRealtimeChannelInternal` will incorporate some of this data into the `ARTChannelStateChange` object that it emits as a result of the connection state change.
 */
NS_SWIFT_NAME(ChannelStateChangeParams)
@interface ARTChannelStateChangeParams: NSObject

/**
 A state that some operations will use when failing pending presence operations.
 */
@property (nonatomic, readonly) ARTState state;

/**
 Information about the error that triggered this state change, if any.
 */
@property (nullable, nonatomic, readonly) ARTErrorInfo *errorInfo;

/**
 Whether the `ARTRealtimeChannelInternal` instance should update its `errorReason` property.
 */
@property (nonatomic, readonly) BOOL storeErrorInfo;

@property (nullable, nonatomic, readonly) ARTRetryAttempt *retryAttempt;

/**
 The `resumed` value of the `ARTProtocolMessage` that triggered this state change.
 */
@property (nonatomic) BOOL resumed;

- (instancetype)init NS_UNAVAILABLE;

/**
 Creates an `ARTChannelStateChangeParams` instance whose `errorInfo` is `nil`, and whose `storeErrorInfo` is `NO`.
 */
- (instancetype)initWithState:(ARTState)state;

/**
 Creates an `ARTChannelStateChangeParams` instance with the given `errorInfo`, whose `storeErrorInfo` is `YES`.
 */
- (instancetype)initWithState:(ARTState)state
                    errorInfo:(nullable ARTErrorInfo *)errorInfo;

- (instancetype)initWithState:(ARTState)state
                    errorInfo:(nullable ARTErrorInfo *)errorInfo
               storeErrorInfo:(BOOL)storeErrorInfo;

- (instancetype)initWithState:(ARTState)state
                    errorInfo:(nullable ARTErrorInfo *)errorInfo
               storeErrorInfo:(BOOL)storeErrorInfo
                 retryAttempt:(nullable ARTRetryAttempt *)retryAttempt NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
