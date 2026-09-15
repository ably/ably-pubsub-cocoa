#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Represents the message serial of a message published to Ably, as contained in an `ARTPublishResult`.
 */
NS_SWIFT_SENDABLE
@interface ARTPublishResultSerial : NSObject

/**
 * The message serial of the published message, or `nil` if the message was discarded due to a configured conflation rule.
 */
@property (nullable, readonly, nonatomic) NSString *value;

- (instancetype)init NS_UNAVAILABLE;

/**
 * Initializes a new ARTPublishResultSerial with the given value.
 * @param value The message serial, or nil if the message was discarded.
 */
- (instancetype)initWithValue:(nullable NSString *)value;

@end

NS_ASSUME_NONNULL_END
