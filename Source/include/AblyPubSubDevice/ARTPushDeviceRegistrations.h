#import <Foundation/Foundation.h>
#import <AblyPubSubDevice/ARTTypes.h>

@class ARTDeviceDetails;
@class ARTPaginatedResult;

NS_ASSUME_NONNULL_BEGIN

/**
 The protocol upon which the `ARTPushDeviceRegistrations` is implemented.
 */
@protocol ARTPushDeviceRegistrationsProtocol

/// :nodoc:
- (instancetype)init NS_UNAVAILABLE;

/**
 * Registers or updates a `ARTDeviceDetails` object with Ably.
 *
 * @param deviceDetails The `ARTDeviceDetails` object to create or update.
 * @param callback A success or failure callback function.
 */
- (void)save:(ARTDeviceDetails *)deviceDetails callback:(ARTCallback)callback;

/**
 * Retrieves the `ARTDeviceDetails` of a device registered to receive push notifications using its `deviceId`.
 *
 * @param deviceId The unique ID of the device.
 * @param callback A callback for receiving the `ARTDeviceDetails` object.
 */
- (void)get:(ARTDeviceId *)deviceId callback:(void (^)(ARTDeviceDetails *_Nullable,  ARTErrorInfo *_Nullable))callback;

/**
 * Retrieves all devices matching the filter `params` provided. Returns a `ARTPaginatedResult` object, containing an array of `ARTDeviceDetails` objects.
 *
 * @param params An object containing key-value pairs to filter devices by. Can contain `clientId`, `deviceId` and a `limit` on the number of devices returned, up to 1,000.
 * @param callback A callback for retriving an `ARTPaginatedResult` object with an array of `ARTDeviceDetails` objects.
 */
- (void)list:(NSStringDictionary *)params callback:(ARTPaginatedDeviceDetailsCallback)callback;

/**
 * Removes a device registered to receive push notifications from Ably using its `deviceId`.
 *
 * @param deviceId The unique ID of the device.
 * @param callback A success or failure callback function.
 */
- (void)remove:(NSString *)deviceId callback:(ARTCallback)callback;

/**
 * Removes all devices registered to receive push notifications from Ably matching the filter `params` provided.
 *
 * @param params An object containing key-value pairs to filter devices by. Can contain `clientId` and `deviceId`.
 * @param callback A success or failure callback function.
 */
- (void)removeWhere:(NSStringDictionary *)params callback:(ARTCallback)callback;

@end

/**
 * Enables the management of push notification registrations with Ably.
 *
 * @see See `ARTPushDeviceRegistrationsProtocol` for details.
 */
NS_SWIFT_SENDABLE
@interface ARTPushDeviceRegistrations : NSObject <ARTPushDeviceRegistrationsProtocol>

@end

NS_ASSUME_NONNULL_END
