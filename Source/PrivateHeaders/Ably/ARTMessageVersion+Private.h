@import Foundation;
#import <AblyPubSubDevice/ARTMessageVersion.h>

@class ARTMessageOperation;

NS_ASSUME_NONNULL_BEGIN

@interface ARTMessageVersion ()

// Serialize the MessageVersion object
- (void)writeToDictionary:(NSMutableDictionary<NSString *, id> *)dictionary;

// Deserialize a MessageVersion object from a NSDictionary object. A missing serial or timestamp takes the given default. A nil dictionary gives a version that holds only the defaults.
+ (instancetype)createFromDictionary:(nullable NSDictionary<NSString *, id> *)jsonObject
                       defaultSerial:(nullable NSString *)defaultSerial
                    defaultTimestamp:(nullable NSDate *)defaultTimestamp;

/// Creates a MessageVersion from a MessageOperation. Used for populating the `ARTMessage.version` that gets sent over the wire when the user performs a message edit operation.
- (instancetype)initWithOperation:(ARTMessageOperation *)operation;

@end

NS_ASSUME_NONNULL_END
