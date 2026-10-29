@import Foundation;
#import <AblyPubSubDevice/ARTTypes.h>

@class ARTRetryAttempt;
@class ARTInternalLog;
@protocol ARTDeviceStorage;

NS_ASSUME_NONNULL_BEGIN

@interface ARTConnectionStateChange ()

/**
 The retry attempt that triggered this connection state change, if any.

 Intended for tests that wish to make assertions about the exact value of retry delays.
 */
@property (nonatomic, readonly, nullable) ARTRetryAttempt *retryAttempt;

- (instancetype)initWithCurrent:(ARTRealtimeConnectionState)current
                       previous:(ARTRealtimeConnectionState)previous
                          event:(ARTRealtimeConnectionEvent)event
                         reason:(nullable ARTErrorInfo *)reason
                        retryIn:(NSTimeInterval)retryIn
                   retryAttempt:(nullable ARTRetryAttempt *)retryAttempt;

@end

@interface ARTChannelStateChange ()

/**
 The retry attempt that triggered this channel state change, if any.

 Intended for tests that wish to make assertions about the exact value of retry delays.
 */
@property (nonatomic, readonly, nullable) ARTRetryAttempt *retryAttempt;

- (instancetype)initWithCurrent:(ARTRealtimeChannelState)current
                       previous:(ARTRealtimeChannelState)previous
                          event:(ARTChannelEvent)event
                         reason:(nullable ARTErrorInfo *)reason
                        resumed:(BOOL)resumed
                   retryAttempt:(nullable ARTRetryAttempt *)retryAttempt;

@end

@interface NSObject (ARTArchive)
- (nullable NSData *)art_archiveWithLogger:(nullable ARTInternalLog *)logger;
+ (nullable id)art_unarchiveFromData:(NSData *)data withLogger:(nullable ARTInternalLog *)logger;
+ (nullable id)art_unarchiveFromStorage:(id<ARTDeviceStorage>)storage
                                    key:(NSString *)key
                             withLogger:(nullable ARTInternalLog *)logger;
@end

NS_ASSUME_NONNULL_END
