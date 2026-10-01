#import <Foundation/Foundation.h>
#import <AblyPubSubDevice/ARTTypes.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Contains annotations summary for a message. The keys of the dict are annotation types, and the values are aggregated summaries for that annotation type.
 */
NS_SWIFT_SENDABLE
NS_SWIFT_NAME(MessageAnnotations)
@interface ARTMessageAnnotations : NSObject

/// An annotations summary for the message. The keys of the dict are annotation types, and the values are aggregated summaries for that annotation type.
@property (nullable, readonly, copy, nonatomic) ARTJsonObject *summary;

/**
 * Initializes an `ARTMessageAnnotations` with a summary. The initializer stores a copy of the summary, including any dictionaries and arrays nested inside it.
 *
 * @param summary An annotations summary for the message. The keys of the dict are annotation types, and the values are aggregated summaries for that annotation type.
 */
- (instancetype)initWithSummary:(nullable ARTJsonObject *)summary NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
