#import <AblyPubSubDevice/ARTRealtimeClient.h>

@class ARTWrapperSDKProxyOptions;
@class ARTWrapperSDKProxyRealtime;

NS_ASSUME_NONNULL_BEGIN

@interface ARTRealtimeClient (WrapperSDKProxy)

/**
 Creates a proxy client to be used to supply analytics information for Ably-authored SDKs.

 The proxy client shares the state of the `ARTRealtimeClient` instance on which this method is called.

 - Important: This method should only be called by Ably-authored SDKs.
 */
- (ARTWrapperSDKProxyRealtime *)createWrapperSDKProxyWithOptions:(ARTWrapperSDKProxyOptions *)options;

@end

NS_ASSUME_NONNULL_END
