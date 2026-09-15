#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Contains the result of an update or delete message operation.
 */
NS_SWIFT_SENDABLE
@interface ARTUpdateDeleteResult : NSObject

/**
 * The serial of the version of the updated or deleted message. Will be `nil` if the message was superseded by a subsequent update before it could be published.
 */
@property (readonly, nonatomic, nullable) NSString *versionSerial;

- (instancetype)init NS_UNAVAILABLE;

/**
 * Initializes a new `ARTUpdateDeleteResult` with the given version serial.
 *
 * @param versionSerial The version serial string, or `nil`.
 */
- (instancetype)initWithVersionSerial:(nullable NSString *)versionSerial;

@end

NS_ASSUME_NONNULL_END
