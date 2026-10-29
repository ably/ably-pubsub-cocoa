#import <Foundation/Foundation.h>

#import <AblyPubSubDevice/ARTTypes.h>
#import <AblyPubSubDevice/ARTClientOptions.h>

@class ARTTokenRequest;

NS_ASSUME_NONNULL_BEGIN

/**
 * Defines the properties of an Ably Token.
 */
NS_SWIFT_NAME(TokenParams)
@interface ARTTokenParams : NSObject<NSCopying>

/**
 * Requested time to live for the token in milliseconds. The default is 60 minutes.
 */
@property (nonatomic, nullable) NSNumber *ttl;

/**
 * The capabilities associated with this Ably Token. The capabilities value is a JSON-encoded representation of the resource paths and associated operations. Read more about capabilities in the [capabilities docs](https://ably.com/docs/core-features/authentication/#capabilities-explained).
 */
@property (nonatomic, copy, nullable) NSString *capability;

/**
 * A client ID, used for identifying this client when publishing messages or for presence purposes. The `clientId` can be any non-empty string, except it cannot contain a `*`. This option is primarily intended to be used in situations where the library is instantiated with a key. Note that a `clientId` may also be implicit in a token used to instantiate the library. An error is raised if a `clientId` specified here conflicts with the `clientId` implicit in the token. Find out more about [identified clients](https://ably.com/docs/core-features/authentication#identified-clients).
 */
@property (nullable, nonatomic, copy, readwrite) NSString *clientId;

/**
 * The timestamp of this request as `NSDate` object. Timestamps, in conjunction with the `nonce`, are used to prevent requests from being replayed. `timestamp` is a "one-time" value, and is valid in a request, but is not validly a member of any default token params such as `ARTClientOptions.defaultTokenParams`.
 */
@property (nullable, nonatomic, copy, readwrite) NSDate *timestamp;

/**
 * A cryptographically secure random string of at least 16 characters, used to ensure the `ARTTokenRequest` cannot be reused.
 */
@property (nullable, nonatomic, readonly) NSString *nonce;

/// :nodoc:
- (instancetype)init;

/// :nodoc:
- (instancetype)initWithClientId:(NSString *_Nullable)clientId;

/// :nodoc:
- (instancetype)initWithClientId:(NSString *_Nullable)clientId nonce:(NSString *_Nullable)nonce;

/// :nodoc:
- (instancetype)initWithOptions:(ARTClientOptions *)options;

/// :nodoc:
- (instancetype)initWithTokenParams:(ARTTokenParams *)tokenParams;

/// :nodoc:
- (NSMutableArray<NSURLQueryItem *> *)toArray;

/// :nodoc:
- (NSArray<NSURLQueryItem *> *)toArrayWithUnion:(NSArray *)items;

/// :nodoc:
- (NSStringDictionary *)toDictionaryWithUnion:(NSArray<NSURLQueryItem *> *)items;

@end

NS_ASSUME_NONNULL_END
