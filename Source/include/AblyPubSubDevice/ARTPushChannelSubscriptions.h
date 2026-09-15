#import <Foundation/Foundation.h>
#import <AblyPubSubDevice/ARTTypes.h>

@class ARTPushChannelSubscription;
@class ARTPaginatedResult;
@class ARTRest;

NS_ASSUME_NONNULL_BEGIN

/**
 The protocol upon which the `ARTPushChannelSubscriptions` is implemented.
 */
@protocol ARTPushChannelSubscriptionsProtocol

/// :nodoc:
- (instancetype)init NS_UNAVAILABLE;

/**
 * Subscribes a device, or a group of devices sharing the same `clientId` to push notifications on a channel.
 *
 * @param channelSubscription An `ARTPushChannelSubscription` object.
 * @param callback A success or failure callback function.
 */
- (void)save:(ARTPushChannelSubscription *)channelSubscription callback:(ARTCallback)callback;

/**
 * Retrieves all channels with at least one device subscribed to push notifications. Returns a `ARTPaginatedResult` object, containing an array of channel names.
 *
 * @param callback A callback for retriving an `ARTPaginatedResult` object with an array of channel names.
 */
- (void)listChannels:(ARTPaginatedTextCallback)callback;

/**
 * Retrieves all push channel subscriptions matching the filter `params` provided. Returns a `ARTPaginatedResult` object, containing an array of `ARTPushChannelSubscription` objects.
 *
 * @param params An object containing key-value pairs to filter subscriptions by. Can contain `channel`, `clientId`, `deviceId` and a `limit` on the number of devices returned, up to 1,000.
 *
 * @param callback A callback for retriving an `ARTPaginatedResult` object with an array of `ARTPushChannelSubscription` objects.
 */
- (void)list:(NSStringDictionary *)params callback:(ARTPaginatedPushChannelCallback)callback;

/**
 * Unsubscribes a device, or a group of devices sharing the same `clientId` from receiving push notifications on a channel.
 *
 * @param subscription An `ARTPushChannelSubscription` object.
 * @param callback A success or failure callback function.
 */
- (void)remove:(ARTPushChannelSubscription *)subscription callback:(ARTCallback)callback;

/**
 * Unsubscribes all devices from receiving push notifications on a channel that match the filter `params` provided.
 *
 * @param params An object containing key-value pairs to filter subscriptions by. Can contain `channel`, and optionally either `clientId` or `deviceId`.
 * @param callback A success or failure callback function.
 */
- (void)removeWhere:(NSStringDictionary *)params callback:(ARTCallback)callback;

@end

/**
 * Enables device push channel subscriptions.
 *
 * @see See `ARTPushChannelSubscriptionsProtocol` for details.
 */
NS_SWIFT_SENDABLE
@interface ARTPushChannelSubscriptions : NSObject <ARTPushChannelSubscriptionsProtocol>

@end

NS_ASSUME_NONNULL_END
