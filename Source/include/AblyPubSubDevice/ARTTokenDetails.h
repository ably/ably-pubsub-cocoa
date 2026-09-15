#import <Foundation/Foundation.h>

#import <AblyPubSubDevice/ARTTypes.h>
#import <AblyPubSubDevice/ARTAuthOptions.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Contains an Ably Token and its associated metadata.
 */
@interface ARTTokenDetails : NSObject<NSCopying>

/**
 * The [Ably Token](https://ably.com/docs/core-features/authentication#ably-tokens) itself. A typical Ably Token string appears with the form `xVLyHw.A-pwh7wicf3afTfgiw4k2Ku33kcnSA7z6y8FjuYpe3QaNRTEo4`.
 */
@property (nonatomic, readonly, copy) NSString *token;

/**
 * The timestamp at which this token expires as a `NSDate` object.
 */
@property (nonatomic, readonly, nullable) NSDate *expires;

/**
 * The timestamp at which this token was issued as a `NSDate` object.
 */
@property (nonatomic, readonly, nullable) NSDate *issued;

/**
 * The capabilities associated with this Ably Token. The capabilities value is a JSON-encoded representation of the resource paths and associated operations. Read more about capabilities in the [capabilities docs](https://ably.com/docs/core-features/authentication/#capabilities-explained).
 */
@property (nonatomic, readonly, copy, nullable) NSString *capability;

/**
 * The client ID, if any, bound to this Ably Token. If a client ID is included, then the Ably Token authenticates its bearer as that client ID, and the Ably Token may only be used to perform operations on behalf of that client ID. The client is then considered to be an [identified client](https://ably.com/docs/core-features/authentication#identified-clients).
 */
@property (nonatomic, readonly, copy, nullable) NSString *clientId;

/// :nodoc:
- (instancetype)init UNAVAILABLE_ATTRIBUTE;

/// :nodoc:
- (instancetype)initWithToken:(NSString *)token;

/// :nodoc:
- (instancetype)initWithToken:(NSString *)token expires:(nullable NSDate *)expires issued:(nullable  NSDate *)issued capability:(nullable  NSString *)capability clientId:(nullable NSString *)clientId;

/**
 * A static factory method to create an `ARTTokenDetails` object from a deserialized `TokenDetails`-like object or a JSON stringified `TokenDetails` object. This method is provided to minimize bugs as a result of differing types by platform for fields such as `timestamp` or `ttl`. For example, in Ruby `ttl` in the `TokenDetails` object is exposed in seconds as that is idiomatic for the language, yet when serialized to JSON using `to_json` it is automatically converted to the Ably standard which is milliseconds. By using the `fromJson` method when constructing an `TokenDetails` object, Ably ensures that all fields are consistently serialized and deserialized across platforms.
 *
 * @param json A deserialized `TokenDetails`-like object or a JSON stringified `TokenDetails` object.
 * @param errorPtr A reference to the `NSError` object where an error information will be saved in case of failure.
 *
 * @return An Ably authentication token.
 */
+ (ARTTokenDetails *_Nullable)fromJson:(id<ARTJsonCompatible>)json error:(NSError *_Nullable *_Nullable)errorPtr;

@end

@interface ARTTokenDetails (ARTTokenDetailsCompatible) <ARTTokenDetailsCompatible>
@end

NS_ASSUME_NONNULL_END
