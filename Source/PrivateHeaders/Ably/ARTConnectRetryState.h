@import Foundation;
#import <AblyPubSubDevice/ARTTypes.h>

@class ARTRetryAttempt;
@class ARTInternalLog;
@protocol ARTRetryDelayCalculator;

NS_ASSUME_NONNULL_BEGIN

/**
 Maintains the state that an `ARTRealtime` instance needs in order to determine the duration to wait before retrying a connection. Wraps a sequence of `ARTRetrySequence` objects.
 */
NS_SWIFT_NAME(ConnectRetryState)
@interface ARTConnectRetryState: NSObject

- (instancetype)initWithRetryDelayCalculator:(id<ARTRetryDelayCalculator>)retryDelayCalculator
                                      logger:(ARTInternalLog *)logger
                            logMessagePrefix:(NSString *)logMessagePrefix;
- (instancetype)init NS_UNAVAILABLE;

/**
 Calls `addRetryAttempt` on the current retry sequence.
 */
- (ARTRetryAttempt *)addRetryAttempt;

/**
 Resets the retry sequence when the channel leaves the sequence of `DISCONNECTED` <-> `CONNECTING` state changes.
 */
- (void)connectionWillTransitionToState:(ARTRealtimeConnectionState)state;

@end

NS_ASSUME_NONNULL_END
