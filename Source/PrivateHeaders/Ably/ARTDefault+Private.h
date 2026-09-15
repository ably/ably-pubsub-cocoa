#import <AblyPubSubDevice/ARTDefault.h>

extern NSString *const ARTDefaultProduction;

@interface ARTDefault (Private)

+ (void)setConnectionStateTtl:(NSTimeInterval)value;
+ (void)setMaxMessageSize:(NSInteger)value;

+ (NSInteger)maxSandboxMessageSize;
+ (NSInteger)maxProductionMessageSize;

@end
