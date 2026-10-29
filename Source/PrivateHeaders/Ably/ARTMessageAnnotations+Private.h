@import Foundation;
#import <AblyPubSubDevice/ARTMessageAnnotations.h>

NS_ASSUME_NONNULL_BEGIN

@interface ARTMessageAnnotations ()

// Serialize the MessageAnnotations object
- (void)writeToDictionary:(NSMutableDictionary<NSString *, id> *)dictionary;

// Deserialize a MessageAnnotations object from a NSDictionary object. A missing summary, or one that is not a JSON object, becomes an empty summary. A nil dictionary gives an empty summary too.
+ (instancetype)createFromDictionary:(nullable NSDictionary<NSString *, id> *)jsonObject;

@end

NS_ASSUME_NONNULL_END
