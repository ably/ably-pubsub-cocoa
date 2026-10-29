#import <Foundation/Foundation.h>

#import <AblyPubSubDevice/ARTDataQuery.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Describes the interval unit over which statistics are gathered.
 */
NS_SWIFT_SENDABLE
typedef NS_ENUM(NSUInteger, ARTStatsGranularity) {
    /**
     * Interval unit over which statistics are gathered as minutes.
     */
    ARTStatsGranularityMinute,
    /**
     * Interval unit over which statistics are gathered as hours.
     */
    ARTStatsGranularityHour,
    /**
     * Interval unit over which statistics are gathered as days.
     */
    ARTStatsGranularityDay,
    /**
     * Interval unit over which statistics are gathered as months.
     */
    ARTStatsGranularityMonth
} NS_SWIFT_NAME(StatsGranularity);

/**
 This object is used for providing parameters into `ARTStats`'s methods with paginated results.
 */
NS_SWIFT_NAME(StatsQuery)
@interface ARTStatsQuery : ARTDataQuery

/**
 * `ARTStatsGranularity.ARTStatsGranularityMinute`, `ARTStatsGranularity.ARTStatsGranularityHour`, `ARTStatsGranularity.ARTStatsGranularityDay` or `ARTStatsGranularity.ARTStatsGranularityMonth`. Based on the unit selected, the given `start` or `end` times are rounded down to the start of the relevant interval depending on the unit granularity of the query.
 */
@property (nonatomic) ARTStatsGranularity unit;

@end

/**
 * Contains application statistics for a specified time interval and time period.
 */
NS_SWIFT_NAME(Stats)
@interface ARTStats : NSObject

/**
 * The UTC time at which the time period covered begins. If `unit` is set to `minute` this will be in the format `YYYY-mm-dd:HH:MM`, if `hour` it will be `YYYY-mm-dd:HH`, if `day` it will be `YYYY-mm-dd:00` and if `month` it will be `YYYY-mm-01:00`.
 */
@property (readonly, nonatomic) NSString *intervalId;

/**
 * The `intervalId` as an `NSDate` object.
 */
@property (readonly, nonatomic) NSDate *intervalTime;

/**
 * The length of the interval the stats span.
 */
@property (readonly, nonatomic) ARTStatsGranularity unit;

/**
 * For entries that are still in progress, such as the current month, the last sub-interval included in this entry, in the format `yyyy-mm-dd:hh:mm`.
 */
@property (nullable, readonly, nonatomic) NSString *inProgress;

/**
 * The statistics for this time interval, keyed by the name of each statistic, for example `messages.inbound.realtime.messages.count`. See the JSON schema at `schema` for the names.
 */
@property (readonly, nonatomic) NSDictionary<NSString *, NSNumber *> *entries;

/**
 * The URI of the JSON schema that describes the `entries`.
 */
@property (readonly, nonatomic) NSString *schema;

/**
 * The ID of the Ably application the statistics are for.
 */
@property (readonly, nonatomic) NSString *appId;

/// :nodoc:
- (instancetype)init NS_UNAVAILABLE;

/// :nodoc:
- (instancetype)initWithIntervalId:(NSString *)intervalId
                              unit:(ARTStatsGranularity)unit
                        inProgress:(nullable NSString *)inProgress
                           entries:(NSDictionary<NSString *, NSNumber *> *)entries
                            schema:(NSString *)schema
                             appId:(NSString *)appId;

@end

NS_ASSUME_NONNULL_END
