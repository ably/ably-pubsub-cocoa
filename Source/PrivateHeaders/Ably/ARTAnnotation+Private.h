@import Foundation;
#import <AblyPubSubDevice/ARTAnnotation.h>
#import "ARTDataEncoder.h"

@class ARTProtocolMessage;
@protocol ARTTimeProvider;

NS_ASSUME_NONNULL_BEGIN

@interface ARTAnnotation ()

@property (nonatomic, readonly) BOOL isIdEmpty;

- (id)decodeDataWithEncoder:(ARTDataEncoder *)encoder error:(NSError *__nullable*__nullable)error;

/// Returns a copy of this annotation that takes a missing `id` or `timestamp` from the `ProtocolMessage` that delivered it, where it is at `index` in `annotations`. This matches what `TM2a` and `TM2f` require of messages, and what ably-js does for annotations. If the `ProtocolMessage` has no `timestamp` either, the annotation takes `timeProvider`'s current wall-clock time, because `timestamp` is nonnull. Returns `self` if nothing is missing.
- (ARTAnnotation *)annotationByPopulatingFieldsFromProtocolMessage:(ARTProtocolMessage *)protocolMessage index:(NSUInteger)index timeProvider:(id<ARTTimeProvider>)timeProvider;

@end

NS_ASSUME_NONNULL_END
