#import <Foundation/Foundation.h>

#import <AblyPubSubDevice/ARTTypes.h>
#import <AblyPubSubDevice/ARTHttpChannels.h>
#import <AblyPubSubDevice/ARTLocalDevice.h>

@protocol ARTHTTPExecuting;

@class ARTHttpChannels;
@class ARTClientOptions;
@class ARTAuth;
@class ARTPush;
@class ARTCancellable;
@class ARTStatsQuery;
@class ARTHTTPPaginatedResponse;

NS_ASSUME_NONNULL_BEGIN

/**
 This protocol contains the non-initializer instance methods provided by the `ARTHttpClient` client class.
 */
@protocol ARTHttpClientInstanceMethodsProtocol <NSObject>

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
- (BOOL)stats:(nullable ARTStatsQuery *)query
     callback:(ARTPaginatedStatsCallback)callback
        error:(NSError *_Nullable *_Nullable)errorPtr;

#if TARGET_OS_IOS
/**
 * Retrieves an `ARTLocalDevice` object that represents the current state of the device as a target for push notifications.
 */
@property (readonly) ARTLocalDevice *device;
#endif

@end

/**
 The protocol upon which the top level object `ARTHttpClient` is implemented.
 */
@protocol ARTHttpClientProtocol <ARTHttpClientInstanceMethodsProtocol>

/// :nodoc:
- (instancetype)init NS_UNAVAILABLE;

/**
 * Construct an `ARTHttpClient` object using an Ably `ARTClientOptions` object.
 *
 * @param options A `ARTClientOptions` object to configure the client connection to Ably.
 */
- (instancetype)initWithOptions:(ARTClientOptions *)options;

/**
 * Constructs a `ARTHttpClient` object using an Ably API key.
 * @param key The Ably API key used to validate the client.
 */
- (instancetype)initWithKey:(NSString *)key;

/**
 * Constructs a `ARTHttpClient` object using an Ably token string.
 * @param token The Ably token string used to validate the client.
 */
- (instancetype)initWithToken:(NSString *)token;

@end

/**
 * A client that offers a simple stateless API to interact directly with Ably's REST API.
 */
NS_SWIFT_SENDABLE
@interface ARTHttpClient : NSObject <ARTHttpClientProtocol>

/**
 * An `ARTChannels` object.
 */
@property (readonly) ARTHttpChannels *channels;

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
