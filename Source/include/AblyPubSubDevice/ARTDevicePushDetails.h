#import <Foundation/Foundation.h>

@class ARTErrorInfo;

/**
 * Describes the state of a device's push registration.
 */
NS_SWIFT_SENDABLE
typedef NS_ENUM(NSUInteger, ARTDevicePushState) {
    /**
     * The state is not known. Either Ably has not reported a state, as for a device registration that the SDK has not received from Ably, or it reported one that this version of the SDK does not recognise.
     */
    ARTDevicePushStateUnknown,
    /**
     * The push registration is active.
     */
    ARTDevicePushStateActive,
    /**
     * Delivering push notifications to the device is failing. `errorReason` describes the most recent error.
     */
    ARTDevicePushStateFailing,
    /**
     * Delivering push notifications to the device has failed. `errorReason` describes the most recent error.
     */
    ARTDevicePushStateFailed,
} NS_SWIFT_NAME(DevicePushState);

NS_ASSUME_NONNULL_BEGIN

/**
 * Contains the details of the push registration of a device.
 */
NS_SWIFT_SENDABLE
NS_SWIFT_NAME(DevicePushDetails)
@interface ARTDevicePushDetails : NSObject

/**
 * A JSON object of key-value pairs that contains of the push transport and address.
 */
@property (nonatomic, readonly) NSMutableDictionary<NSString *, NSObject *> *recipient;

/**
 * The current state of the push registration (PCP4). `ARTDevicePushStateUnknown` if Ably did not report a state, or reported one that this version of the SDK does not recognise.
 */
@property (nonatomic, readonly) ARTDevicePushState state;

/**
 * An `ARTErrorInfo` object describing the most recent error when the `state` is `ARTDevicePushStateFailing` or `ARTDevicePushStateFailed`.
 */
@property (nullable, nonatomic, readonly) ARTErrorInfo *errorReason;

/// :nodoc:
- (instancetype)init;

@end

NS_ASSUME_NONNULL_END
