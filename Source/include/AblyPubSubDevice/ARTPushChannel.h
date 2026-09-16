#import <Foundation/Foundation.h>
#import <AblyPubSubDevice/ARTPush.h>

@class ARTPushChannelSubscription;
@class ARTPaginatedResult;

NS_ASSUME_NONNULL_BEGIN

/**
 The protocol upon which the `ARTPushChannel` is implemented.
 */
NS_SWIFT_NAME(PushChannelProtocol)
@protocol ARTPushChannelProtocol

/// :nodoc:
- (instancetype)init NS_UNAVAILABLE;

/**
 * Subscribes the device to push notifications for the channel.
 */
- (void)subscribeDevice;

/**
 * Subscribes the device to push notifications for the channel.
 *
 * @param callback A success or failure callback function.
 */
- (void)subscribeDevice:(nullable ARTCallback)callback;

/**
 * Subscribes all devices associated with the current device's `clientId` to push notifications for the channel.
 */
- (void)subscribeClient;

/**
 * Subscribes all devices associated with the current device's `clientId` to push notifications for the channel.
 *
 * @param callback A success or failure callback function.
 */
- (void)subscribeClient:(nullable ARTCallback)callback;

/**
 * Unsubscribes the device from receiving push notifications for the channel.
 */
- (void)unsubscribeDevice;

/**
 * Unsubscribes the device from receiving push notifications for the channel.
 *
 * @param callback A success or failure callback function.
 */
- (void)unsubscribeDevice:(nullable ARTCallback)callback;

/**
 * Unsubscribes all devices associated with the current device's `clientId` from receiving push notifications for the channel.
 */
- (void)unsubscribeClient;

/**
 * Unsubscribes all devices associated with the current device's `clientId` from receiving push notifications for the channel.
 *
 * @param callback A success or failure callback function.
 */
- (void)unsubscribeClient:(nullable ARTCallback)callback;

/**
 * Retrieves all push subscriptions for the channel. Subscriptions can be filtered using a `params` object. Returns a `ARTPaginatedResult` object containing an array of `ARTPushChannelSubscription` objects.
 *
 * @param params An object containing key-value pairs to filter subscriptions by. Can contain `clientId`, `deviceId` or a combination of both if `concatFilters` is set to `true`, and a `limit` on the number of subscriptions returned, up to 1,000.
 * @param callback A callback for retriving an `ARTPaginatedResult` object with an array of `ARTPushChannelSubscription` objects.
 * @param errorPtr A reference to the `NSError` object where an error information will be saved in case of failure.
 *
 * @return In case of failure returns `false` and the error information can be retrived via the `error` parameter.
 */
- (BOOL)listSubscriptions:(NSStringDictionary *)params
                 callback:(ARTPaginatedPushChannelCallback)callback
                    error:(NSError *_Nullable *_Nullable)errorPtr;

@end

/**
 * Enables devices to subscribe to push notifications for a channel.
 *
 * @see See `ARTPushChannelProtocol` for details.
 */
NS_SWIFT_SENDABLE
NS_SWIFT_NAME(PushChannel)
@interface ARTPushChannel : NSObject <ARTPushChannelProtocol>

@end

NS_ASSUME_NONNULL_END
