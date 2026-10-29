#import <AblyPubSubDevice/ARTDataQuery.h>
#import "ARTRealtimeChannel+Private.h"

@class ARTErrorInfo;

NS_ASSUME_NONNULL_BEGIN

@interface ARTDataQuery (Private)

// Raises `NSInvalidArgumentException` if `limit` is greater than 1,000, or if `start` is later than `end`.
- (void)validate;

// Returns nil and sets `errorPtr` if the query can't be sent in the realtime channel's current state.
- (nullable NSMutableArray /* <NSURLQueryItem *> */ *)asQueryItems:(ARTErrorInfo *_Nullable *_Nullable)errorPtr;

@end

@interface ARTRealtimeHistoryQuery ()

@property (readwrite) ARTRealtimeChannelInternal *realtimeChannel;

@end

NS_ASSUME_NONNULL_END
