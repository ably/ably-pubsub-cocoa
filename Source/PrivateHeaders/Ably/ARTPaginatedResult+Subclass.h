@import Foundation;
#import <AblyPubSubDevice/ARTPaginatedResult.h>

NS_ASSUME_NONNULL_BEGIN

@interface ARTPaginatedResult ()

@property (nullable, nonatomic, readonly) NSStringDictionary *wrapperSDKAgents;
@property (nonatomic, readonly) ARTInternalLog *logger;

@end

NS_ASSUME_NONNULL_END
