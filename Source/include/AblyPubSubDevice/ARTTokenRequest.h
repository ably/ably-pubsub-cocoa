#import <Foundation/Foundation.h>

#import <AblyPubSubDevice/ARTTypes.h>
#import <AblyPubSubDevice/ARTTokenParams.h>
#import <AblyPubSubDevice/ARTAuthOptions.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Contains the properties of a request for a token to Ably. Tokens are generated using `-[ARTAuthProtocol requestToken:]`.
 */
NS_SWIFT_NAME(TokenRequest)
@interface ARTTokenRequest : NSObject

/**
 * The name of the key against which this request is made. The key name is public, whereas the key secret is private.
 */
@property (nonatomic, readonly, copy) NSString *keyName;

/**
 * The client ID to associate with the requested Ably Token. When provided, the Ably Token may only be used to perform operations on behalf of that client ID.
 */
@property (nullable, nonatomic, copy, readwrite) NSString *clientId;

/**
 * A cryptographically secure random string of at least 16 characters, used to ensure the `ARTTokenRequest` cannot be reused.
 */
@property (nonatomic, readonly, copy) NSString *nonce;

/**
 * The Message Authentication Code for this request.
 */
@property (nonatomic, readonly, copy) NSString *mac;

/**
 * Capability of the requested Ably Token. If the Ably `ARTTokenRequest` is successful, the capability of the returned Ably Token will be the intersection of this capability with the capability of the issuing key. The capabilities value is a JSON-encoded representation of the resource paths and associated operations. Read more about capabilities in the [capabilities docs](https://ably.com/docs/realtime/authentication).
 */
@property (nonatomic, copy, nullable) NSString *capability;

/**
 * Requested time to live for the Ably Token in milliseconds. If the Ably `ARTTokenRequest` is successful, the TTL of the returned Ably Token is less than or equal to this value, depending on application settings and the attributes of the issuing key. The default is 60 minutes.
 */
@property (nonatomic, nullable) NSNumber *ttl;

/**
 * The timestamp of this request as `NSDate` object.
 */
@property (nonatomic) NSDate *timestamp;

/// :nodoc:
- (instancetype)init UNAVAILABLE_ATTRIBUTE;

/// :nodoc:
- (instancetype)initWithTokenParams:(ARTTokenParams *)tokenParams keyName:(NSString *)keyName nonce:(NSString *)nonce mac:(NSString *)mac;

/**
 * A static factory method to create an `ARTTokenRequest` object from a deserialized `TokenRequest`-like object or a JSON stringified `ARTTokenRequest` object. This method is provided to minimize bugs as a result of differing types by platform for fields such as `timestamp` or `ttl`. For example, in Ruby `ttl` in the `TokenRequest` object is exposed in seconds as that is idiomatic for the language, yet when serialized to JSON using `to_json` it is automatically converted to the Ably standard which is milliseconds. By using the `fromJson` method when constructing a `TokenRequest` object, Ably ensures that all fields are consistently serialized and deserialized across platforms.
 *
 * @param json A deserialized `TokenRequest`-like object or a JSON stringified `TokenRequest` object to create an `ARTTokenRequest`.
 * @param errorPtr A reference to the `NSError` object where an error information will be saved in case of failure.
 *
 * @return An Ably token request object.
 */
+ (ARTTokenRequest *_Nullable)fromJson:(id<ARTJsonCompatible>)json error:(NSError *_Nullable *_Nullable)errorPtr;

@end

@interface ARTTokenRequest (ARTTokenDetailsCompatible) <ARTTokenDetailsCompatible>
@end

NS_ASSUME_NONNULL_END
