@import Foundation;
#import <AblyPubSubDevice/ARTAnnotation.h>
#import "ARTDataEncoder.h"

NS_ASSUME_NONNULL_BEGIN

@interface ARTAnnotation ()

@property (nonatomic, readonly) BOOL isIdEmpty;

- (id)decodeDataWithEncoder:(ARTDataEncoder *)encoder error:(NSError *__nullable*__nullable)error;

@end

NS_ASSUME_NONNULL_END
