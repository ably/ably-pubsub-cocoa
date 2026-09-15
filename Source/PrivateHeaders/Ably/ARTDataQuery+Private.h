#import <AblyPubSubDevice/ARTDataQuery.h>
#import "ARTRealtimeChannel+Private.h"

NS_ASSUME_NONNULL_BEGIN

@interface ARTDataQuery (Private)

- (nullable NSMutableArray /* <NSURLQueryItem *> */ *)asQueryItems:(NSError *_Nullable *)error;

@end

@interface ARTRealtimeHistoryQuery ()

@property (readwrite) ARTRealtimeChannelInternal *realtimeChannel;

@end

NS_ASSUME_NONNULL_END
