#import <Foundation/Foundation.h>
#import <AblyPubSubDevice/ARTTypes.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Contains version information for a message, including operation metadata.
 */
NS_SWIFT_SENDABLE
NS_SWIFT_NAME(MessageVersion)
@interface ARTMessageVersion : NSObject

/// The serial of the message version.
@property (nullable, readonly, copy, nonatomic) NSString *serial;

/// The timestamp of the message version.
@property (nullable, readonly, copy, nonatomic) NSDate *timestamp;

/// The client ID associated with this version.
@property (nullable, readonly, copy, nonatomic) NSString *clientId;

/// A description of the operation performed.
@property (nullable, readonly, copy, nonatomic) NSString *descriptionText;

/// Metadata associated with the operation.
@property (nullable, readonly, copy, nonatomic) NSDictionary<NSString *, NSString *> *metadata;

/**
 * Initializes an `ARTMessageVersion` with all of its properties. The initializer stores copies of the arguments.
 *
 * @param serial The serial of the message version.
 * @param timestamp The timestamp of the message version.
 * @param clientId The client ID associated with this version.
 * @param descriptionText A description of the operation performed.
 * @param metadata Metadata associated with the operation.
 */
- (instancetype)initWithSerial:(nullable NSString *)serial
                     timestamp:(nullable NSDate *)timestamp
                      clientId:(nullable NSString *)clientId
               descriptionText:(nullable NSString *)descriptionText
                      metadata:(nullable NSDictionary<NSString *, NSString *> *)metadata NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
