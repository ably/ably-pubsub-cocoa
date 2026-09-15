@import Foundation;
#import <AblyPubSubDevice/ARTMessageVersion.h>

@class ARTMessageOperation;

NS_ASSUME_NONNULL_BEGIN

@interface ARTMessageVersion ()

// Serialize the MessageVersion object
- (void)writeToDictionary:(NSMutableDictionary<NSString *, id> *)dictionary;

// Deserialize a MessageVersion object from a NSDictionary object
+ (instancetype)createFromDictionary:(NSDictionary<NSString *, id> *)jsonObject;

/// Creates a MessageVersion from a MessageOperation. Used for populating the `ARTMessage.version` that gets sent over the wire when the user performs a message edit operation.
- (instancetype)initWithOperation:(ARTMessageOperation *)operation;

@end

NS_ASSUME_NONNULL_END
