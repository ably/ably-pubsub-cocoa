@import Foundation;
#import <AblyPubSubDevice/ARTTypes.h>

@class ARTRetryAttempt;
@class ARTInternalLog;
@protocol ARTRetryDelayCalculator;

NS_ASSUME_NONNULL_BEGIN

/**
 Maintains the state that an `ARTRealtimeChannel` instance needs in order to determine the duration to wait before retrying an attach. Wraps a sequence of `ARTRetrySequence` objects.
 */
NS_SWIFT_NAME(AttachRetryState)
@interface ARTAttachRetryState: NSObject

- (instancetype)initWithRetryDelayCalculator:(id<ARTRetryDelayCalculator>)retryDelayCalculator
                                      logger:(ARTInternalLog *)logger
                            logMessagePrefix:(NSString *)logMessagePrefix;
- (instancetype)init NS_UNAVAILABLE;

/**
 Calls `addRetryAttempt` on the current retry sequence.
 */
- (ARTRetryAttempt *)addRetryAttempt;

/**
 Resets the retry sequence when the channel leaves the sequence of `SUSPENDED` <-> `ATTACHING` state changes.
 */
- (void)channelWillTransitionToState:(ARTRealtimeChannelState)state;

@end

NS_ASSUME_NONNULL_END
