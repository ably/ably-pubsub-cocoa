@import Foundation;
#import <AblyPubSubDevice/ARTOutboundAnnotation.h>
#import <AblyPubSubDevice/ARTAnnotation.h>
#import "ARTDataEncoder.h"

NS_ASSUME_NONNULL_BEGIN

/// The fields that the SDK sets on an annotation when it publishes one. A user-created annotation has none of them.
@interface ARTOutboundAnnotation ()

/// RSAN1c1, RSAN2a
@property (readonly, nonatomic) ARTAnnotationAction action;

/// RSAN1c2
@property (nullable, readonly, nonatomic) NSString *messageSerial;

/// RSAN1c3
@property (nullable, readonly, nonatomic) NSString *encoding;

/// Returns a copy of this annotation with the given id, action and message serial, ready to be published.
- (instancetype)annotationForPublishingWithId:(nullable NSString *)annotationId
                                       action:(ARTAnnotationAction)action
                                messageSerial:(NSString *)messageSerial;

- (id)encodeDataWithEncoder:(ARTDataEncoder *)encoder error:(NSError *__nullable*__nullable)error;

- (NSInteger)annotationSize;

@end

NS_ASSUME_NONNULL_END
