#import <Foundation/Foundation.h>

@class ARTErrorInfo;

NS_ASSUME_NONNULL_BEGIN

/**
 * Contains the details of the push registration of a device.
 */
NS_SWIFT_SENDABLE
@interface ARTDevicePushDetails : NSObject

/**
 * A JSON object of key-value pairs that contains of the push transport and address.
 */
@property (nonatomic, readonly) NSMutableDictionary<NSString *, NSObject *> *recipient;

/**
 * The current state of the push registration.
 */
@property (nullable, nonatomic, readonly) NSString *state;

/**
 * An `ARTErrorInfo` object describing the most recent error when the `state` is `Failing` or `Failed`.
 */
@property (nullable, nonatomic, readonly) ARTErrorInfo *errorReason;

/// :nodoc:
- (instancetype)init;

@end

NS_ASSUME_NONNULL_END
