#import "ARTDataQuery+Private.h"
#import "ARTRealtimeChannel+Private.h"

@implementation ARTDataQuery

- (instancetype)init {
    if (self = [super init]) {
        _limit = 100;
        _direction = ARTQueryDirectionBackwards;
    }

    return self;
}

static NSString *queryDirectionToString(ARTQueryDirection direction) {
    switch (direction) {
        case ARTQueryDirectionForwards:
            return @"forwards";
        case ARTQueryDirectionBackwards:
        default:
            return @"backwards";
    }
}

- (void)validate {
    if (self.limit > 1000) {
        [NSException raise:NSInvalidArgumentException format:@"Limit supports up to 1000 results only"];
    }
    if (self.start && self.end && [self.start compare:self.end] == NSOrderedDescending) {
        [NSException raise:NSInvalidArgumentException format:@"Start must be equal to or less than end"];
    }
}

- (NSMutableArray *)asQueryItems:(ARTErrorInfo *_Nullable *_Nullable)errorPtr {
    NSMutableArray *items = [NSMutableArray array];

    if (self.start) {
        [items addObject:[NSURLQueryItem queryItemWithName:@"start" value:[NSString stringWithFormat:@"%llu", dateToMilliseconds(self.start)]]];
    }
    if (self.end) {
        [items addObject:[NSURLQueryItem queryItemWithName:@"end" value:[NSString stringWithFormat:@"%llu", dateToMilliseconds(self.end)]]];
    }

    [items addObject:[NSURLQueryItem queryItemWithName:@"limit" value:[NSString stringWithFormat:@"%hu", self.limit]]];
    [items addObject:[NSURLQueryItem queryItemWithName:@"direction" value:queryDirectionToString(self.direction)]];

    return items;
}

@end

@implementation ARTRealtimeHistoryQuery

- (NSMutableArray *)asQueryItems:(ARTErrorInfo *_Nullable *_Nullable)errorPtr {
    NSMutableArray *items = [super asQueryItems:errorPtr];
    if (!items) {
        return nil;
    }
    if (self.untilAttach) {
        NSAssert(self.realtimeChannel, @"ARTRealtimeHistoryQuery used from outside ARTRealtimeChannel.history");
        if (self.realtimeChannel.state_nosync != ARTRealtimeChannelAttached) { // RTL10b
            if (errorPtr) {
                *errorPtr = [ARTErrorInfo createWithCode:ARTErrorBadRequest
                                                  status:400
                                                 message:[NSString stringWithFormat:@"untilAttach requires the channel to be attached, but it is %@", ARTRealtimeChannelStateToStr(self.realtimeChannel.state_nosync)]];
            }
            return nil;
        }
        [items addObject:[NSURLQueryItem queryItemWithName:@"fromSerial" value:self.realtimeChannel.attachSerial]];
    }
    return items;
}

@end
