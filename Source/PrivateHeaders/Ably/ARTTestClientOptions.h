@import Foundation;

@protocol ARTRealtimeTransportFactory;
@protocol ARTJitterCoefficientGenerator;
@protocol ARTTimeProvider;
@protocol ARTHTTPExecutor;

NS_ASSUME_NONNULL_BEGIN

/**
 Provides an interface for injecting additional configuration into `ARTHttpClient` or `ARTRealtime` instances.

 This is for anything that test code wishes to be able to configure but which should not be part of the public API of these classes. It can also be used for exposing additional debugging options to be used in Ably-authored applications.
 */
@interface ARTTestClientOptions: NSObject <NSCopying>

/**
 Initial value is `nil`.
 */
@property (nullable, nonatomic, copy) NSString *channelNamePrefix;

/**
 Initial value is `ARTDefault.realtimeRequestTimeout`.
 */
@property (nonatomic) NSTimeInterval realtimeRequestTimeout;

/**
 Initial value is `ARTFallback_shuffleArray`.
 */
@property (nonatomic) void (^shuffleArray)(NSMutableArray *);

/**
 Initial value is an instance of `ARTDefaultRealtimeTransportFactory`.
 */
@property (nonatomic) id<ARTRealtimeTransportFactory> transportFactory;

/**
 RTN20c helper.
 This property is used to provide a way for the test code to simulate the case where a reconnection attempt results in a different outcome to the original connection attempt. Initial value is `nil`.
 */
@property (readwrite, nonatomic) NSString *reconnectionRealtimeHost;

/**
 Initial value is an instance of `ARTDefaultJitterCoefficientGenerator`.
 */
@property (nonatomic) id<ARTJitterCoefficientGenerator> jitterCoefficientGenerator;

/**
 The unified time-provider abstraction consumed by all of ably-cocoa's time-dependent internal code. Tests (currently only the UTS tests) install a fake-time implementation here to control wall-clock, continuous-clock, and scheduler behaviour. Initial value is an instance of `ARTSystemTimeProvider`.
 */
@property (nonatomic) id<ARTTimeProvider> timeProvider;

/**
 The class used to instantiate the `ARTReachability` implementation that `ARTRealtime` uses to monitor network state. Tests install a no-op or controllable implementation here. Initial value is `ARTOSReachability`.
 */
@property (nonatomic) Class reachabilityClass;

/**
 An `ARTHTTPExecutor` that `ARTHttpClientInternal` uses for all of its HTTP requests instead of creating its own. Tests install a mock here so that requests are intercepted rather than sent over the network. When `nil` (the initial value), the rest client creates its own `ARTHttp`.
 */
@property (nullable, nonatomic) id<ARTHTTPExecutor> httpExecutor;

/**
 When `YES`, `ARTLocalDeviceStorage` log lines include the fetched or
 written value itself. Off by default because persisted values include
 the device secret and the identity token. Initial value is `NO`.
 */
@property (nonatomic) BOOL logLocalDeviceStorageValues;

/**
 When `YES`, the client must not access any of the cross-client shared state related to the local device or push activation state machine. The use case is a multi-client demo app (e.g. one with a client under test alongside a diagnostic client) where all side-effects on this shared state should be performed by a single specific client, so that the corresponding log entries appear in that client's logs.

 Enforcement is layered:

 - Persisted state: an `ARTDeviceStorage` is installed that raises on every read and write. This is the backstop for any code path that attempts to touch storage.

 - In-memory shared state: the `ARTLocalDevice` that `ARTHttpClientInternal` exposes via `device_nosync` lives in a process-wide static and may already be cached by another client, so reading it would not necessarily hit storage. `device_nosync` therefore has an explicit guard that raises when this flag is set.

 - Side effects of unrelated flows (e.g. auth propagating a clientId via `ARTAuth.setLocalDeviceClientId_nosync`) silently no-op rather than raise, since raising would break the unrelated flow.

 Other public APIs deliberately about local device or push need not add their own guards — it's acceptable to throw an exception from these APIs.

 Initial value is `NO`.
 */
@property (nonatomic) BOOL disableLocalDevice;

@end

NS_ASSUME_NONNULL_END
