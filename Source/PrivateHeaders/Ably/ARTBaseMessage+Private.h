@import Foundation;
#import <AblyPubSubDevice/ARTBaseMessage.h>
#import "ARTDataEncoder.h"
#import <AblyPubSubDevice/ARTStatus.h>

NS_ASSUME_NONNULL_BEGIN

@interface ARTBaseMessage ()

@property (nonatomic, readonly) BOOL isIdEmpty;

- (id __nonnull)decodeWithEncoder:(ARTDataEncoder*)encoder error:(NSError *__nullable*__nullable)error;
- (id __nonnull)encodeWithEncoder:(ARTDataEncoder*)encoder error:(NSError *__nullable*__nullable)error;

@end

NS_ASSUME_NONNULL_END
