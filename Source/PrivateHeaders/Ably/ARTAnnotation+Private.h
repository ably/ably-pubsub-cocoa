@import Foundation;
#import <AblyPubSubDevice/ARTAnnotation.h>
#import "ARTDataEncoder.h"

@class ARTProtocolMessage;

NS_ASSUME_NONNULL_BEGIN

@interface ARTAnnotation ()

@property (nonatomic, readonly) BOOL isIdEmpty;

- (id)decodeDataWithEncoder:(ARTDataEncoder *)encoder error:(NSError *__nullable*__nullable)error;

/// Returns a copy of this annotation that takes a missing `id` or `timestamp` from the `ProtocolMessage` that delivered it, where it is at `index` in `annotations`. This matches what `TM2a` and `TM2f` require of messages, and what ably-js does for annotations. Returns `self` if nothing is missing.
- (ARTAnnotation *)annotationByPopulatingFieldsFromProtocolMessage:(ARTProtocolMessage *)protocolMessage index:(NSUInteger)index;

@end

NS_ASSUME_NONNULL_END
