#import <Foundation/Foundation.h>
#import <AblyPubSubDevice/ARTTypes.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Contains annotations summary for a message. The keys of the dict are annotation types, and the values are aggregated summaries for that annotation type.
 */
NS_SWIFT_NAME(MessageAnnotations)
@interface ARTMessageAnnotations : NSObject

/// An annotations summary for the message. The keys of the dict are annotation types, and the values are aggregated summaries for that annotation type.
@property (nonatomic, copy, nullable) ARTJsonObject *summary;

@end

NS_ASSUME_NONNULL_END
