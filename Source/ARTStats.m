#import "ARTStats.h"
#import "ARTDataQuery+Private.h"
#import "ARTStatus.h"

@implementation ARTStatsQuery

- (instancetype)init {
    if (self = [super init]) {
        _unit = ARTStatsGranularityMinute;
    }

    return self;
}

static NSString *statsUnitToString(ARTStatsGranularity unit) {
    switch (unit) {
        case ARTStatsGranularityMonth:
            return @"month";
        case ARTStatsGranularityDay:
            return @"day";
        case ARTStatsGranularityHour:
            return @"hour";
        case ARTStatsGranularityMinute:
        default:
            return @"minute";
    }
}

- (NSMutableArray *)asQueryItems:(ARTErrorInfo *_Nullable *_Nullable)errorPtr {
    NSMutableArray *items = [super asQueryItems:errorPtr];
    if (!items) {
        return nil;
    }
    [items addObject:[NSURLQueryItem queryItemWithName:@"unit" value:statsUnitToString(self.unit)]];
    return items;
}

@end

@implementation ARTStats

- (instancetype)initWithIntervalId:(NSString *)intervalId
                              unit:(ARTStatsGranularity)unit
                        inProgress:(NSString *)inProgress
                           entries:(NSDictionary<NSString *, NSNumber *> *)entries
                            schema:(NSString *)schema
                             appId:(NSString *)appId {
    if (self = [super init]) {
        _intervalId = [intervalId copy];
        _unit = unit;
        _inProgress = [inProgress copy];
        _entries = [entries copy];
        _schema = [schema copy];
        _appId = [appId copy];
    }
    return self;
}

// TS12p
- (NSDate *)intervalTime {
    for (NSString *format in @[@"yyyy-MM-dd:HH:mm", @"yyyy-MM-dd:HH", @"yyyy-MM-dd", @"yyyy-MM"]) {
        if (format.length == self.intervalId.length) {
            NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
            // A fixed locale, so that the device's calendar, such as the Buddhist one, can't change the year
            formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
            formatter.dateFormat = format;
            formatter.timeZone = [NSTimeZone timeZoneWithName:@"UTC"];
            return [formatter dateFromString:self.intervalId];
        }
    }
    @throw [ARTException exceptionWithName:NSInvalidArgumentException reason:@"invalid intervalId" userInfo:nil];
}

@end
