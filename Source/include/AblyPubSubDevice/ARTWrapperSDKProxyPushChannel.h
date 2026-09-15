#import <Foundation/Foundation.h>
#import <AblyPubSubDevice/ARTPushChannel.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * An object which wraps an instance of `ARTPushChannel` and provides a similar API. It allows Ably-authored wrapper SDKs to send analytics information so that Ably can track the usage of the wrapper SDK.
 *
 * - Important: This class should only be used by Ably-authored SDKs.
 */
NS_SWIFT_SENDABLE
@interface ARTWrapperSDKProxyPushChannel : NSObject <ARTPushChannelProtocol>

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
