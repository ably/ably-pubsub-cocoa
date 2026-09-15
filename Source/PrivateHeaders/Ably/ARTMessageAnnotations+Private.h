@import Foundation;
#import <AblyPubSubDevice/ARTMessageAnnotations.h>

NS_ASSUME_NONNULL_BEGIN

@interface ARTMessageAnnotations ()

// Serialize the MessageAnnotations object
- (void)writeToDictionary:(NSMutableDictionary<NSString *, id> *)dictionary;

// Deserialize a MessageAnnotations object from a NSDictionary object
+ (instancetype)createFromDictionary:(NSDictionary<NSString *, id> *)jsonObject;

@end

NS_ASSUME_NONNULL_END
