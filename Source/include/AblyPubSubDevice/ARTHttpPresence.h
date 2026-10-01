#import <Foundation/Foundation.h>

#import <AblyPubSubDevice/ARTPresence.h>
#import <AblyPubSubDevice/ARTDataQuery.h>

@class ARTHttpChannel;

NS_ASSUME_NONNULL_BEGIN

/**
 The protocol upon which the `ARTHttpPresence` is implemented.
 */
NS_SWIFT_NAME(HttpPresenceProtocol)
@protocol ARTHttpPresenceProtocol

/// :nodoc: TODO: docstring
- (void)get:(ARTPaginatedPresenceCallback)callback;

/**
 * Retrieves the current members present on the channel and the metadata for each member, such as their `ARTPresenceAction` and ID. Returns a `ARTPaginatedResult` object, containing an array of `ARTPresenceMessage` objects.
 *
 * Raises `NSInvalidArgumentException` if `query.limit` is greater than 1,000.
 *
 * @param query An `ARTPresenceQuery` object.
 * @param callback A callback for retriving an `ARTPaginatedResult` object with an array of `ARTPresenceMessage` objects.
 */
- (void)get:(ARTPresenceQuery *)query callback:(ARTPaginatedPresenceCallback)callback;

- (void)history:(ARTPaginatedPresenceCallback)callback;

/**
 * Retrieves a `ARTPaginatedResult` object, containing an array of historical `ARTPresenceMessage` objects for the channel. If the channel is configured to persist messages, then presence messages can be retrieved from history for up to 72 hours in the past. If not, presence messages can only be retrieved from history for up to two minutes in the past.
 *
 * Raises `NSInvalidArgumentException` if `query.limit` is greater than 1,000, or if `query.start` is later than `query.end`.
 *
 * @param query An `ARTDataQuery` object.
 * @param callback A callback for retriving an `ARTPaginatedResult` object with an array of `ARTPresenceMessage` objects.
 */
- (void)history:(nullable ARTDataQuery *)query callback:(ARTPaginatedPresenceCallback)callback;

@end

/**
 * Enables the retrieval of the current and historic presence set for a channel.
 *
 * @see See `ARTHttpPresenceProtocol` for details.
 */
NS_SWIFT_SENDABLE
NS_SWIFT_NAME(HttpPresence)
@interface ARTHttpPresence : ARTPresence <ARTHttpPresenceProtocol>
@end

NS_ASSUME_NONNULL_END
