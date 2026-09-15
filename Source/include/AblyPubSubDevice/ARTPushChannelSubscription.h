#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Contains the subscriptions of a device, or a group of devices sharing the same `clientId`, has to a channel in order to receive push notifications.
 */
@interface ARTPushChannelSubscription : NSObject

/**
 * The unique ID of the device.
 */
@property (nullable, nonatomic, readonly) NSString *deviceId;

/**
 * The ID of the client the device, or devices are associated to.
 */
@property (nullable, nonatomic, readonly) NSString *clientId;

/**
 * The channel the push notification subscription is for.
 */
@property (nonatomic, readonly) NSString *channel;

/// :nodoc:
- (instancetype)init NS_UNAVAILABLE;

/**
 * Creates an `ARTPushChannelSubscription` object for a channel and single device.
 *
 * @param deviceId The unique ID of the device.
 * @param channelName The channel name.
 *
 * @return An `ARTPushChannelSubscription` object.
 */
- (instancetype)initWithDeviceId:(NSString *)deviceId channel:(NSString *)channelName;

/**
 * Creates an `ARTPushChannelSubscription` object for a channel and group of devices sharing the same `clientId`.
 *
 * @param clientId The ID of the client.
 * @param channelName The channel name.
 *
 * @return An `ARTPushChannelSubscription` object.
 */
- (instancetype)initWithClientId:(NSString *)clientId channel:(NSString *)channelName;

@end

NS_ASSUME_NONNULL_END
