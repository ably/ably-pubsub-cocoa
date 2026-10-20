#import <Foundation/Foundation.h>

@class ARTHttpClient;
@class ARTHttpChannel;
@class ARTChannelOptions;

/**
 * Creates and destroys `ARTHttpChannel` and `ARTRealtimeChannel` objects.
 */
NS_SWIFT_SENDABLE
NS_SWIFT_NAME(Channels)
@interface ARTChannels<ChannelType> : NSObject

/**
 * Checks if a channel has been previously retrieved using the `-[ARTChannels get:]` method.
 *
 * @param name The channel name.
 *
 * @return `true` if the channel exists, otherwise `false`.
 */
- (BOOL)exists:(NSString *)name;

/**
 * Creates a new `ARTHttpChannel` or `ARTRealtimeChannel` object, or returns the existing channel object.
 *
 * @param name The channel name.
 *
 * @return A `ARTHttpChannel` or `ARTRealtimeChannel` object.
 */
- (ChannelType)get:(NSString *)name;

/**
 * Creates a new `ARTHttpChannel` or `ARTRealtimeChannel` object, with the specified `ARTChannelOptions`, or returns the existing channel object.
 *
 * @param name The channel name.
 * @param options An `ARTChannelOptions` object.
 *
 * @return A `ARTHttpChannel` or `ARTRealtimeChannel` object.
 */
- (ChannelType)get:(NSString *)name options:(ARTChannelOptions *)options;

/**
 * Releases an `ARTHttpChannel` or an `ARTRealtimeChannel` object by deleting it. It also removes any listeners associated with the channel.
 * A realtime channel can only be released when it is in the `ARTRealtimeChannelState.ARTRealtimeChannelInitialized`, `ARTRealtimeChannelState.ARTRealtimeChannelDetached`, or `ARTRealtimeChannelState.ARTRealtimeChannelFailed` state.
 *
 * @param name The channel name.
 */
- (void)release:(NSString *)name;

/// :nodoc:
- (id<NSFastEnumeration>)copyIntoIteratorWithMapper:(id (^)(ChannelType))mapper;

@end
