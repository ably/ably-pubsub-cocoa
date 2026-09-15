#import <Foundation/Foundation.h>

#import <AblyPubSubDevice/ARTTypes.h>

NS_ASSUME_NONNULL_BEGIN

/// :nodoc:
NS_SWIFT_SENDABLE
typedef NS_ENUM(NSUInteger, ARTQueryDirection) {
    ARTQueryDirectionForwards,
    ARTQueryDirectionBackwards
};

/**
 This object is used for providing parameters into methods with paginated results.
 */
@interface ARTDataQuery : NSObject

/**
 * The time from which the data items are retrieved.
 */
@property (nonatomic, nullable) NSDate *start;

/**
 * The time until the data items are retrieved.
 */
@property (nonatomic, nullable) NSDate *end;

/**
 * An upper limit on the number of the data items returned. The default is 100, and the maximum is 1000.
 */
@property (nonatomic) uint16_t limit;

/**
 * The order for which the data is returned in. Valid values are `ARTQueryDirectionBackwards` which orders items from most recent to oldest, or `ARTQueryDirectionForwards` which orders items from oldest to most recent. The default is `ARTQueryDirectionBackwards`.
 */
@property (nonatomic) ARTQueryDirection direction;

@end

/**
 This object is used for providing parameters into `ARTRealtimePresence`'s methods with paginated results.
 */
@interface ARTRealtimeHistoryQuery : ARTDataQuery

/**
 * When `true`, ensures message history is up until the point of the channel being attached. See [continuous history](https://ably.com/docs/realtime/history#continuous-history) for more info. Requires the `direction` to be `ARTQueryDirectionBackwards`. If the channel is not attached, or if `direction` is set to `ARTQueryDirectionForwards`, this option results in an error.
 */
@property (nonatomic) BOOL untilAttach;

@end

NS_ASSUME_NONNULL_END
