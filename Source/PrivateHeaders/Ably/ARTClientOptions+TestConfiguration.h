@import Foundation;
#import <AblyPubSubDevice/ARTClientOptions.h>

@class ARTTestClientOptions;

NS_ASSUME_NONNULL_BEGIN

/**
 Provides an interface for injecting additional configuration into `ARTHttpClient` or `ARTRealtime` instances.

 This is for anything that test code wishes to be able to configure but which should not be part of the public API of these classes.
 */
@interface ARTClientOptions ()

/**
 Defaults to a new instance of `ARTTestClientOptions` (whose properties all have their default values).
 */
@property (nonatomic, copy) ARTTestClientOptions *testOptions;

@end

NS_ASSUME_NONNULL_END
