#import "ARTPush.h"
#import "ARTDevicePushDetails.h"
#import "ARTDevicePushDetails+Private.h"

@implementation ARTDevicePushDetails

- (instancetype)init {
    if (self = [super init]) {
        _recipient = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    ARTDevicePushDetails *push = [[[self class] allocWithZone:zone] init];

    push.recipient = [self.recipient copy];
    push.state = self.state;
    push.errorReason = [self.errorReason copy];

    return push;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"%@ - \n\t recipient: %@; \n\t state: %@; \n\t errorReason: %@;", [super description], self.recipient, ARTDevicePushStateToWireValue(self.state) ?: @"unknown", self.errorReason];
}

@end

ARTDevicePushState ARTDevicePushStateFromWireValue(NSString *value) {
    if ([value isEqualToString:@"active"]) {
        return ARTDevicePushStateActive;
    }
    if ([value isEqualToString:@"failing"]) {
        return ARTDevicePushStateFailing;
    }
    if ([value isEqualToString:@"failed"]) {
        return ARTDevicePushStateFailed;
    }
    return ARTDevicePushStateUnknown;
}

NSString *ARTDevicePushStateToWireValue(ARTDevicePushState state) {
    switch (state) {
        case ARTDevicePushStateActive:
            return @"active";
        case ARTDevicePushStateFailing:
            return @"failing";
        case ARTDevicePushStateFailed:
            return @"failed";
        case ARTDevicePushStateUnknown:
            return nil;
    }
    return nil;
}
