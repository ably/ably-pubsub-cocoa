#import <Foundation/Foundation.h>

#import <AblyPubSubDevice/ARTAuthOptions.h>
#import <AblyPubSubDevice/ARTLog.h>

@class ARTPlugin;
@class ARTStringifiable;
@protocol ARTPushRegistererDelegate;

NS_ASSUME_NONNULL_BEGIN

/// A key for the `ARTClientOptions.plugins` property.
typedef NSString *ARTPluginName NS_TYPED_EXTENSIBLE_ENUM;
/// Set this key in `ARTClientOptions.plugins` to `AblyLiveObjects.Plugin.self` after adding this package's `AblyLiveObjects` product to your target and importing the `AblyLiveObjects` module, in order to enable LiveObjects functionality.
extern const ARTPluginName ARTPluginNameLiveObjects;

/**
 * Passes additional client-specific properties to the REST `-[ARTHttpClientProtocol initWithOptions:]` or the Realtime `-[ARTRealtimeProtocol initWithOptions:]`.
 */
@interface ARTClientOptions : ARTAuthOptions

/**
 * Enables a non-default Ably host to be specified. For development environments only. The default value is `rest.ably.io`.
 */
@property (readwrite, nonatomic) NSString *restHost;

/**
 * Enables a non-default Ably host to be specified for realtime connections. For development environments only. The default value is `realtime.ably.io`.
 */
@property (readwrite, nonatomic) NSString *realtimeHost;

/**
 * Enables a non-default Ably port to be specified. For development environments only. The default value is 80.
 */
@property (nonatomic) NSInteger port;

/**
 * Enables a non-default Ably TLS port to be specified. For development environments only. The default value is 443.
 */
@property (nonatomic) NSInteger tlsPort;

/**
 * Enables a [custom environment](https://ably.com/docs/platform-customization) to be used with the Ably service.
 */
@property (readwrite, nonatomic, nullable) NSString *environment;

/**
 * When `false`, the client will use an insecure connection. The default is `true`, meaning a TLS connection will be used to connect to Ably.
 */
@property (nonatomic) BOOL tls;

/**
 * Controls the log output of the library. This is an object to handle each line of log output.
 */
@property (nonatomic, readwrite) ARTLog *logHandler;

/**
 * Controls the verbosity of the logs output from the library. Levels include `ARTLogLevelVerbose`, `ARTLogLevelDebug`, `ARTLogLevelInfo`, `ARTLogLevelWarn` and `ARTLogLevelError`.
 */
@property (nonatomic) ARTLogLevel logLevel;

/**
 * If `false`, this disables the default behavior whereby the library queues messages on a connection in the disconnected or connecting states. The default behavior enables applications to submit messages immediately upon instantiating the library without having to wait for the connection to be established. Applications may use this option to disable queueing if they wish to have application-level control over the queueing. The default is `true`.
 */
@property (readwrite, nonatomic) BOOL queueMessages;

/**
 * If `false`, prevents messages originating from this connection being echoed back on the same connection. The default is `true`.
 */
@property (readwrite, nonatomic) BOOL echoMessages;

/**
 * When `true`, the more efficient MsgPack binary encoding is used. When `false`, JSON text encoding is used. The default is `true`.
 */
@property (readwrite, nonatomic) BOOL useBinaryProtocol;

/**
 * When `true`, the client connects to Ably as soon as it is instantiated. You can set this to `false` and explicitly connect to Ably using the `-[ARTConnectionProtocol connect]` method. The default is `true`.
 */
@property (readwrite, nonatomic) BOOL autoConnect;

/**
 * Enables a connection to inherit the state of a previous connection that may have existed under a different instance of the Realtime library. This might happen upon the app restart where a recovery key string can be explicitly provided to the `-[ARTRealtimeProtocol initWithOptions:]` initializer. See [connection state recovery](https://ably.com/docs/realtime/connection/#connection-state-recovery) for further information.
 */
@property (nullable, readwrite, copy, nonatomic) NSString *recover;

/// :nodoc:
@property (readwrite, nonatomic) BOOL pushFullWait;

/**
 * A client ID, used for identifying this client when publishing messages or for presence purposes. The `clientId` can be any non-empty string, except it cannot contain a `*`. This option is primarily intended to be used in situations where the library is instantiated with a key. Note that a `clientId` may also be implicit in a token used to instantiate the library. An error will be raised if a `clientId` specified here conflicts with the `clientId` implicit in the token.
 */
@property (readwrite, nonatomic, nullable) NSString *clientId;

/**
 * When a `ARTTokenParams` object is provided, it overrides the client library defaults when issuing new Ably Tokens or Ably `ARTTokenRequest`s.
 */
@property (readwrite, nonatomic, nullable) ARTTokenParams *defaultTokenParams;

/**
 * If the connection is still in the `ARTRealtimeConnectionState.ARTRealtimeDisconnected` state after this delay, the client library will attempt to reconnect automatically. The default is 15 seconds.
 */
@property (readwrite, nonatomic) NSTimeInterval disconnectedRetryTimeout;

/**
 * When the connection enters the `ARTRealtimeConnectionState.ARTRealtimeSuspended` state, after this delay, if the state is still `ARTRealtimeConnectionState.ARTRealtimeSuspended`, the client library attempts to reconnect automatically. The default is 30 seconds.
 */
@property (readwrite, nonatomic) NSTimeInterval suspendedRetryTimeout;

/**
 * When a channel becomes `ARTRealtimeChannelState.ARTRealtimeChannelSuspended` following a server initiated `ARTRealtimeChannelState.ARTRealtimeChannelDetached`, after this delay, if the channel is still `ARTRealtimeChannelState.ARTRealtimeChannelSuspended` and the connection is `ARTRealtimeConnectionState.ARTRealtimeConnected`, the client library will attempt to re-attach the channel automatically. The default is 15 seconds.
 */
@property (readwrite, nonatomic) NSTimeInterval channelRetryTimeout;

/**
 * Timeout for opening a connection to Ably to initiate an HTTP request. The default is 4 seconds.
 */
@property (readwrite, nonatomic) NSTimeInterval httpOpenTimeout;

/**
 * Timeout for a client performing a complete HTTP request to Ably, including the connection phase. The default is 10 seconds.
 */
@property (readwrite, nonatomic) NSTimeInterval httpRequestTimeout;

/**
 * The maximum time before HTTP requests are retried against the default endpoint. The default is 600 seconds.
 */
@property (readwrite, nonatomic) NSTimeInterval fallbackRetryTimeout;

/**
 * The maximum number of fallback hosts to use as a fallback when an HTTP request to the primary host is unreachable or indicates that it is unserviceable. The default value is 3.
 */
@property (readwrite, nonatomic) NSUInteger httpMaxRetryCount;

/**
 * The maximum elapsed time in which fallback host retries for HTTP requests will be attempted. The default is 15 seconds.
 */
@property (readwrite, nonatomic) NSTimeInterval httpMaxRetryDuration;

/**
 * An array of fallback hosts to be used in the case of an error necessitating the use of an alternative host. If you have been provided a set of custom fallback hosts by Ably, please specify them here.
 */
@property (nullable, nonatomic, copy) NSArray<NSString *> *fallbackHosts;

/**
 The queue to which all calls to user-provided callbacks will be dispatched
 asynchronously. It will be used as target queue for an internal, serial queue.

 It defaults to the main queue.
 */
@property (readwrite, nonatomic) dispatch_queue_t dispatchQueue;

/**
 The queue to which all internal concurrent operations will be dispatched.
 It must be a serial queue. It shouldn't be the same queue as dispatchQueue.

 It defaults to a newly created serial queue.
 */
@property (readwrite, nonatomic) dispatch_queue_t internalDispatchQueue;

/**
 * When `true`, enables idempotent publishing by assigning a unique message ID client-side, allowing the Ably servers to discard automatic publish retries following a failure such as a network fault. The default is `true`.
 */
@property (readwrite, nonatomic) BOOL idempotentRestPublishing;

/**
 * When `true`, every REST request to Ably should include a random string in the `request_id` query string parameter. The random string should be a url-safe base64-encoding sequence of at least 9 bytes, obtained from a source of randomness. This request ID must remain the same if a request is retried to a fallback host. Any log messages associated with the request should include the request ID. If the request fails, the request ID must be included in the `ARTErrorInfo` returned to the user. The default is `false`.
 */
@property (readwrite, nonatomic) BOOL addRequestIds;

/**
 * A set of key-value pairs that can be used to pass in arbitrary connection parameters, such as [`heartbeatInterval`](https://ably.com/docs/realtime/connection#heartbeats) or [`remainPresentFor`](https://ably.com/docs/realtime/presence#unstable-connections).
 */
@property (nonatomic, copy, nullable) NSDictionary<NSString *, ARTStringifiable *> *transportParams;

/**
 The object that processes Push activation/deactivation-related actions.
 */
@property (nullable, weak, nonatomic) id<ARTPushRegistererDelegate, NSObject> pushRegistererDelegate;

/// :nodoc:
- (BOOL)isBasicAuth;

/// :nodoc:
- (NSURL *)restUrl;

/// :nodoc:
- (NSURL *)realtimeUrl;

/**
 * A set of additional entries for the Ably agent header. Each entry can be a key string or set of key-value pairs. This should only be used by Ably-authored SDKs. If an agent does not have a version, represent this by using the `ARTClientInformationAgentNotVersioned` pointer as the version.
 */
@property (nonatomic, copy, nullable) NSDictionary<NSString *, NSString *> *agents;

/// A set of plugins that provide additional functionality to the client.
///
/// Currently supported keys:
///
/// - `ARTPluginNameLiveObjects`: Allows you to use LiveObjects functionality. Add this package's `AblyLiveObjects` product to your target, import the `AblyLiveObjects` module, and set the value for this key to `AblyLiveObjects.Plugin.self`. Use a channel's `object` property to access its LiveObjects functionality.
@property (nonatomic, copy, nullable) NSDictionary<ARTPluginName, id> *plugins;

@end

NS_ASSUME_NONNULL_END
