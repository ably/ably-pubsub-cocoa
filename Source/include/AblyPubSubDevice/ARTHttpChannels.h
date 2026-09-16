#import <AblyPubSubDevice/ARTChannels.h>
#import <AblyPubSubDevice/ARTHttpChannel.h>
#import <AblyPubSubDevice/ARTHttpClient.h>

NS_ASSUME_NONNULL_BEGIN

/// :nodoc:
@protocol ARTHttpChannelsProtocol

// We copy this from the parent class and replace ChannelType by ARTHttpChannel * because
// Swift ignores Objective-C generics and thinks this is returning an id, failing to compile.
// Thus, we can't make ARTHttpChannels inherit from ARTChannels; we have to compose them instead.
- (BOOL)exists:(NSString *)name;
- (void)release:(NSString *)name;

@end

/// :nodoc:
NS_SWIFT_SENDABLE
@interface ARTHttpChannels : NSObject<ARTHttpChannelsProtocol>

- (ARTHttpChannel *)get:(NSString *)name;
- (ARTHttpChannel *)get:(NSString *)name options:(ARTChannelOptions *)options;

/**
 * Iterates through the existing channels.
 *
 * @return Each iteration returns an `ARTHttpChannel` object.
 */
- (id<NSFastEnumeration>)iterate;

@end

NS_ASSUME_NONNULL_END
