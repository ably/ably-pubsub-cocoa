#import <Foundation/Foundation.h>

#import <AblyPubSubDevice/ARTTypes.h>
#import <AblyPubSubDevice/ARTRealtimeChannels.h>
#import <AblyPubSubDevice/ARTEventEmitter.h>
#import <AblyPubSubDevice/ARTConnection.h>

@class ARTStatus;
@class ARTMessage;
@class ARTClientOptions;
@class ARTStatsQuery;
@class ARTRealtimeChannel;
@class ARTPresenceMessage;
@class ARTErrorInfo;
@class ARTCipherParams;
@class ARTPresence;
@class ARTPresenceMap;
@class ARTEventEmitter;
@class ARTRealtimeChannel;
@class ARTAuth;
@class ARTPush;
@class ARTProtocolMessage;
@class ARTRealtimeChannels;

NS_ASSUME_NONNULL_BEGIN

/**
 This protocol contains the non-initializer instance methods provided by the `ARTRealtime` client class.
 */
@protocol ARTRealtimeInstanceMethodsProtocol <NSObject>

#if TARGET_OS_IOS
/**
 * Retrieves a `ARTLocalDevice` object that represents the current state of the device as a target for push notifications.
 */
@property (readonly) ARTLocalDevice *device;
#endif

/**
 * A client ID, used for identifying this client when publishing messages or for presence purposes. The `clientId` can be any non-empty string, except it cannot contain a `*`. This option is primarily intended to be used in situations where the library is instantiated with a key. A `clientId` may also be implicit in a token used to instantiate the library; an error will be raised if a `clientId` specified here conflicts with the `clientId` implicit in the token.
 */
@property (readonly, nullable) NSString *clientId;

/**
 * Retrieves the time from the Ably service. Clients that do not have access to a sufficiently well maintained time source and wish to issue Ably `ARTTokenRequest`s with a more accurate timestamp should use the `ARTAuthOptions.queryTime` property instead of this method.
 *
 * @param callback A callback for receiving the time as a `NSDate` object.
 */
- (void)time:(ARTDateTimeCallback)callback;

/**
 * Makes a REST request to a provided path. This is provided as a convenience for developers who wish to use REST API functionality that is either not documented or is not yet included in the public API, without having to directly handle features such as authentication, paging, fallback hosts, MsgPack and JSON support.
 *
 * @param method The request method to use, such as GET, POST.
 * @param path The request path.
 * @param params The parameters to include in the URL query of the request. The parameters depend on the endpoint being queried. See the [REST API reference](https://ably.com/docs/api/rest-api) for the available parameters of each endpoint.
 * @param body The JSON body of the request.
 * @param headers Additional HTTP headers to include in the request.
 * @param callback A callback for retriving `ARTHttpPaginatedResponse` object returned by the HTTP request, containing an empty or JSON-encodable object.
 * @param errorPtr A reference to the `NSError` object where an error information will be saved in case of failure.

 * @return In case of failure returns `false` and the error information can be retrived via the `error` parameter.
 */
- (BOOL)request:(NSString *)method
           path:(NSString *)path
         params:(nullable NSStringDictionary *)params
           body:(nullable id)body
        headers:(nullable NSStringDictionary *)headers
       callback:(ARTHTTPPaginatedCallback)callback
          error:(NSError *_Nullable *_Nullable)errorPtr;

/// :nodoc: TODO: docstring
- (void)ping:(ARTCallback)cb;

/// :nodoc: TODO: docstring
- (BOOL)stats:(ARTPaginatedStatsCallback)callback;

/**
 * Queries the REST `/stats` API and retrieves your application's usage statistics. Returns a `ARTPaginatedResult` object, containing an array of `ARTStats` objects. See the [Stats docs](https://ably.com/docs/general/statistics).
 *
 * @param query An `ARTStatsQuery` object.
 * @param callback A callback for retriving an `ARTPaginatedResult` object with an array of `ARTStats` objects.
 * @param errorPtr A reference to the `NSError` object where an error information will be saved in case of failure.
 *
 * @return In case of failure returns `false` and the error information can be retrived via the `error` parameter.
 */
- (BOOL)stats:(nullable ARTStatsQuery *)query callback:(ARTPaginatedStatsCallback)callback error:(NSError *_Nullable *_Nullable)errorPtr;

/**
 * Calls `-[ARTConnectionProtocol connect]` and causes the connection to open, entering the connecting state. Explicitly calling `connect` is unnecessary unless the `ARTClientOptions.autoConnect` property is disabled.
 */
- (void)connect;

/**
 * Calls `-[ARTConnectionProtocol close]` and causes the connection to close, entering the closing state. Once closed, the library will not attempt to re-establish the connection without an explicit call to `connect`.
 */
- (void)close;

@end

/**
 The protocol upon which the top level object `ARTRealtime` is implemented.
 */
@protocol ARTRealtimeProtocol <ARTRealtimeInstanceMethodsProtocol>

/// :nodoc:
- (instancetype)init NS_UNAVAILABLE;

/**
 * Constructs an `ARTRealtime` object using an Ably `ARTClientOptions` object.
 *
 * @param options An `ARTClientOptions` object.
 */
- (instancetype)initWithOptions:(ARTClientOptions *)options;

/**
 * Constructs an `ARTRealtime` object using an Ably API key.
 *
 * @param key The Ably API key used to validate the client.
 */
- (instancetype)initWithKey:(NSString *)key;

/**
 * Constructs an `ARTRealtime` object using an Ably token string.
 *
 * @param token The Ably token string used to validate the client.
 */
- (instancetype)initWithToken:(NSString *)token;

@end

/**
 * A client that extends the functionality of the `ARTRest` and provides additional realtime-specific features.
 */
NS_SWIFT_SENDABLE
@interface ARTRealtime : NSObject <ARTRealtimeProtocol>

/**
 * An `ARTConnection` object.
 */
@property (readonly) ARTConnection *connection;
/**
 * An `ARTChannels` object.
 */
@property (readonly) ARTRealtimeChannels *channels;
/**
 * An `ARTPush` object.
 */
@property (readonly) ARTPush *push;
/**
 * An `ARTAuth` object.
 */
@property (readonly) ARTAuth *auth;

/// :nodoc:
+ (instancetype)createWithOptions:(ARTClientOptions *)options NS_SWIFT_UNAVAILABLE("Use instance initializer instead");

/// :nodoc:
+ (instancetype)createWithKey:(NSString *)key NS_SWIFT_UNAVAILABLE("Use instance initializer instead");

/// :nodoc:
+ (instancetype)createWithToken:(NSString *)tokenId NS_SWIFT_UNAVAILABLE("Use instance initializer instead");

@end

NS_ASSUME_NONNULL_END
