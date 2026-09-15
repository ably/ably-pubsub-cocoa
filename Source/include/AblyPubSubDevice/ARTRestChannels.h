#import <AblyPubSubDevice/ARTChannels.h>
#import <AblyPubSubDevice/ARTRestChannel.h>
#import <AblyPubSubDevice/ARTRest.h>

NS_ASSUME_NONNULL_BEGIN

/// :nodoc:
@protocol ARTRestChannelsProtocol

// We copy this from the parent class and replace ChannelType by ARTRestChannel * because
// Swift ignores Objective-C generics and thinks this is returning an id, failing to compile.
// Thus, we can't make ARTRestChannels inherit from ARTChannels; we have to compose them instead.
- (BOOL)exists:(NSString *)name;
- (void)release:(NSString *)name;

@end

/// :nodoc:
NS_SWIFT_SENDABLE
@interface ARTRestChannels : NSObject<ARTRestChannelsProtocol>

- (ARTRestChannel *)get:(NSString *)name;
- (ARTRestChannel *)get:(NSString *)name options:(ARTChannelOptions *)options;

/**
 * Iterates through the existing channels.
 *
 * @return Each iteration returns an `ARTRestChannel` object.
 */
- (id<NSFastEnumeration>)iterate;

@end

NS_ASSUME_NONNULL_END
