#import <AblyPubSubDevice/ARTChannels.h>
#import <AblyPubSubDevice/ARTRealtimeChannel.h>
#import <AblyPubSubDevice/ARTPubSubClient.h>

NS_ASSUME_NONNULL_BEGIN

/// :nodoc:
NS_SWIFT_NAME(RealtimeChannelsProtocol)
@protocol ARTRealtimeChannelsProtocol

// We copy this from the parent class and replace ChannelType by ARTRealtimeChannel * because
// Swift ignores Objective-C generics and thinks this is returning an id, failing to compile.
// Thus, we can't make ARTRealtimeChannels inherit from ARTChannels; we have to compose them instead.
- (BOOL)exists:(NSString *)name;

/**
 * Releases an `ARTRealtimeChannel` object by deleting it, so that it can be garbage collected. It also removes any listeners associated with the channel. Does nothing if no channel with this name exists.
 *
 * A realtime channel can only be released when it is in the `ARTRealtimeChannelState.ARTRealtimeChannelInitialized`, `ARTRealtimeChannelState.ARTRealtimeChannelDetached`, or `ARTRealtimeChannelState.ARTRealtimeChannelFailed` state. In any other state, the channel is left as it is and an error with code `ARTErrorCode.ARTErrorChannelReleaseInvalidState` is returned. Call `-[ARTRealtimeChannelProtocol detach:]` and wait for its callback before releasing the channel.
 *
 * @param name The channel name.
 * @param error On return, the error if the channel could not be released.
 *
 * @return `true` if the channel was released or did not exist, otherwise `false`.
 */
- (BOOL)release:(NSString *)name error:(NSError *_Nullable *_Nullable)error;

@end

/// :nodoc:
NS_SWIFT_SENDABLE
NS_SWIFT_NAME(RealtimeChannels)
@interface ARTRealtimeChannels : NSObject<ARTRealtimeChannelsProtocol>

- (ARTRealtimeChannel *)get:(NSString *)name;
- (ARTRealtimeChannel *)get:(NSString *)name options:(ARTRealtimeChannelOptions *)options;

/**
 * Iterates through the existing channels.
 *
 * @return Each iteration returns an `ARTRealtimeChannel` object.
 */
- (id<NSFastEnumeration>)iterate;

@end

NS_ASSUME_NONNULL_END
