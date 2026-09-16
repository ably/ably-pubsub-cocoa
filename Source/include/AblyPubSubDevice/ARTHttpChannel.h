#import <Foundation/Foundation.h>

#import <AblyPubSubDevice/ARTChannelProtocol.h>

@class ARTHttpClient;
@class ARTHttpPresence;
@class ARTHttpAnnotations;
@class ARTPushChannel;

NS_ASSUME_NONNULL_BEGIN

/**
 The protocol upon which the `ARTHttpChannel` is implemented.
 */
NS_SWIFT_NAME(HttpChannelProtocol)
@protocol ARTHttpChannelProtocol <ARTChannelProtocol>

/// :nodoc: TODO: docstring
@property (readonly, nullable) ARTChannelOptions *options;

/**
 * Retrieves a `ARTPaginatedResult` object, containing an array of historical `ARTMessage` objects for the channel. If the channel is configured to persist messages, then messages can be retrieved from history for up to 72 hours in the past. If not, messages can only be retrieved from history for up to two minutes in the past.
 *
 * @param query An `ARTDataQuery` object.
 * @param callback A callback for retriving an `ARTPaginatedResult` object with an array of `ARTMessage` objects.
 * @param errorPtr A reference to the `NSError` object where an error information will be saved in case of failure.
 *
 * @return In case of failure returns `false` and the error information can be retrived via the `error` parameter.
 */
- (BOOL)history:(nullable ARTDataQuery *)query callback:(ARTPaginatedMessagesCallback)callback error:(NSError *_Nullable *_Nullable)errorPtr;

/**
 * Retrieves a `ARTChannelDetails` object for the channel, which includes status and occupancy metrics.
 *
 * @param callback A callback for receiving the `ARTChannelDetails` object.
 */
- (void)status:(ARTChannelDetailsCallback)callback;

/**
 * Sets the `ARTChannelOptions` for the channel.
 *
 * @param options A `ARTChannelOptions` object.
 */
- (void)setOptions:(ARTChannelOptions *_Nullable)options;

@end

/**
 * Enables messages to be published and historic messages to be retrieved for a channel.
 */
NS_SWIFT_SENDABLE
NS_SWIFT_NAME(HttpChannel)
@interface ARTHttpChannel : NSObject <ARTHttpChannelProtocol>

/**
 * A `ARTHttpPresence` object.
 */
@property (readonly) ARTHttpPresence *presence;

/**
 * An `ARTHttpAnnotations` object.
 */
@property (readonly) ARTHttpAnnotations *annotations;

/**
 * A `ARTPushChannel` object.
 */
@property (readonly) ARTPushChannel *push;

@end

NS_ASSUME_NONNULL_END
