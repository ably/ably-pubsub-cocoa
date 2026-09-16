#import <Foundation/Foundation.h>

#import <AblyPubSubDevice/ARTTypes.h>

@class ARTHttpClient;
@class ARTClientOptions;
@class ARTAuthOptions;
@class ARTTokenParams;
@class ARTTokenDetails;
@class ARTTokenRequest;

NS_ASSUME_NONNULL_BEGIN

/**
 The protocol upon which the `ARTAuth` is implemented.
 */
NS_SWIFT_NAME(AuthProtocol)
@protocol ARTAuthProtocol

/**
 * A client ID, used for identifying this client when publishing messages or for presence purposes. The `clientId` can be any non-empty string, except it cannot contain a `*`. This option is primarily intended to be used in situations where the library is instantiated with a key. Note that a `clientId` may also be implicit in a token used to instantiate the library. An error is raised if a `clientId` specified here conflicts with the `clientId` implicit in the token. Find out more about [identified clients](https://ably.com/docs/core-features/authentication#identified-clients).
 */
@property (nullable, readonly) NSString *clientId;

/// :nodoc:
@property (nullable, readonly) ARTTokenDetails *tokenDetails;

/// :nodoc:
- (instancetype)init NS_UNAVAILABLE;

/**
 * Calls the `requestToken` REST API endpoint to obtain an Ably Token according to the specified `ARTTokenParams` and `ARTAuthOptions`. Both `ARTTokenParams` and `ARTAuthOptions` are optional. When omitted or `nil`, the default token parameters and authentication options for the client library are used, as specified in the `ARTClientOptions` when the client library was instantiated, or later updated with an explicit `-[ARTAuthProtocol authorize:]` request. Values passed in are used instead of, rather than being merged with, the default values. To understand why an Ably `ARTTokenRequest` may be issued to clients in favor of a token, see [Token Authentication explained](https://ably.com/docs/core-features/authentication/#token-authentication).
 *
 * @param tokenParams An `ARTTokenParams` object.
 * @param authOptions An `ARTAuthOptions` object.
 * @param callback A callback for receiving an `ARTTokenDetails` object.
 */
- (void)requestToken:(nullable ARTTokenParams *)tokenParams
         withOptions:(nullable ARTAuthOptions *)authOptions
            callback:(ARTTokenDetailsCallback)callback;

/**
 * See `-[ARTAuthProtocol requestToken:withOptions:callback:]` for details.
 *
 * @param callback A callback for receiving an `ARTTokenDetails` object.
 */
- (void)requestToken:(ARTTokenDetailsCallback)callback;

/**
 * Instructs the library to get a new token immediately. When using the realtime client, it upgrades the current realtime connection to use the new token, or if not connected, initiates a connection to Ably, once the new token has been obtained. Also stores any `ARTTokenParams` and `ARTAuthOptions` passed in as the new defaults, to be used for all subsequent implicit or explicit token requests. Any `ARTTokenParams` and `ARTAuthOptions` objects passed in entirely replace, as opposed to being merged with, the current client library saved values.
 *
 * @param tokenParams An `ARTTokenParams` object.
 * @param authOptions An `ARTAuthOptions` object.
 * @param callback A callback for receiving an `ARTTokenDetails` object.
 */
- (void)authorize:(nullable ARTTokenParams *)tokenParams
          options:(nullable ARTAuthOptions *)authOptions
         callback:(ARTTokenDetailsCallback)callback;

/**
 * See `-[ARTAuthProtocol authorize:options:callback:]` for details.
 *
 * @param callback A callback for receiving an `ARTTokenDetails` object.
 */
- (void)authorize:(ARTTokenDetailsCallback)callback;

/**
 * Creates and signs an Ably `ARTTokenRequest` based on the specified (or if none specified, the client library stored) `ARTTokenParams` and `ARTAuthOptions`. Note this can only be used when the API `key` value is available locally. Otherwise, the Ably `ARTTokenRequest` must be obtained from the key owner. Use this to generate an Ably `ARTTokenRequest` in order to implement an Ably Token request callback for use by other clients. Both `ARTTokenParams` and `ARTAuthOptions` are optional. When omitted or `nil`, the default token parameters and authentication options for the client library are used, as specified in the `ARTClientOptions` when the client library was instantiated, or later updated with an explicit `-[ARTAuthProtocol authorize:]` request. Values passed in are used instead of, rather than being merged with, the default values. To understand why an Ably `ARTTokenRequest` may be issued to clients in favor of a token, see [Token Authentication explained](https://ably.com/docs/core-features/authentication/#token-authentication).
 *
 * @param tokenParams An `ARTTokenParams` object.
 * @param options An `ARTAuthOptions` object.
 * @param callback A callback for receiving an `ARTTokenRequest` object.
 */
- (void)createTokenRequest:(nullable ARTTokenParams *)tokenParams
                   options:(nullable ARTAuthOptions *)options
                  callback:(void (^)(ARTTokenRequest *_Nullable tokenRequest, NSError *_Nullable error))callback;

/**
 * See `-[ARTAuthProtocol createTokenRequest:options:callback:]` for details.
 *
 * @param callback A callback for receiving an `ARTTokenRequest` object.
 */
- (void)createTokenRequest:(void (^)(ARTTokenRequest *_Nullable tokenRequest, NSError *_Nullable error))callback;

@end

/**
 * Creates Ably `ARTTokenRequest` objects and obtains Ably Tokens from Ably to subsequently issue to less trusted clients.
 *
 * @see See `ARTAuthProtocol` for details.
 */
NS_SWIFT_SENDABLE
NS_SWIFT_NAME(Auth)
@interface ARTAuth : NSObject <ARTAuthProtocol>

@end

NS_ASSUME_NONNULL_END
