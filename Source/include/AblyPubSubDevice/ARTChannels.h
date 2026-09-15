#import <Foundation/Foundation.h>

@class ARTRest;
@class ARTRestChannel;
@class ARTChannelOptions;

/**
 * Creates and destroys `ARTRestChannel` and `ARTRealtimeChannel` objects.
 */
NS_SWIFT_SENDABLE
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
 * Creates a new `ARTRestChannel` or `ARTRealtimeChannel` object, or returns the existing channel object.
 *
 * @param name The channel name.
 *
 * @return A `ARTRestChannel` or `ARTRealtimeChannel` object.
 */
- (ChannelType)get:(NSString *)name;

/**
 * Creates a new `ARTRestChannel` or `ARTRealtimeChannel` object, with the specified `ARTChannelOptions`, or returns the existing channel object.
 *
 * @param name The channel name.
 * @param options An `ARTChannelOptions` object.
 *
 * @return A `ARTRestChannel` or `ARTRealtimeChannel` object.
 */
- (ChannelType)get:(NSString *)name options:(ARTChannelOptions *)options;

/**
 * Releases an `ARTRestChannel` or an `ARTRealtimeChannel` object by deleting it. It also removes any listeners associated with the channel.
 * An `ARTRealtimeChannel` should only be released when its `ARTRealtimeChannelProtocol.state` is `ARTRealtimeChannelState.ARTRealtimeChannelInitialized`, `ARTRealtimeChannelState.ARTRealtimeChannelDetached`, or `ARTRealtimeChannelState.ARTRealtimeChannelFailed`; releasing an `ARTRealtimeChannel` in any other state is deprecated and will be an error in the next major version.
 *
 * @param name The channel name.
 */
- (void)release:(NSString *)name;

/// :nodoc:
- (id<NSFastEnumeration>)copyIntoIteratorWithMapper:(id (^)(ChannelType))mapper;

@end
