#import <Foundation/Foundation.h>

#import <AblyPubSubDevice/ARTTypes.h>
#import <AblyPubSubDevice/ARTErrorInfo.h>

NS_ASSUME_NONNULL_BEGIN

/// :nodoc:
NS_SWIFT_NAME(CipherKeyCompatible)
@protocol ARTCipherKeyCompatible <NSObject>
- (NSData *)toData;
@end

/// :nodoc:
@interface NSString (ARTCipherKeyCompatible) <ARTCipherKeyCompatible>
- (NSData *)toData;
@end

/// :nodoc:
@interface NSData (ARTCipherKeyCompatible) <ARTCipherKeyCompatible>
- (NSData *)toData;
@end

@class ARTCipherParams;

/// :nodoc:
NS_SWIFT_NAME(CipherParamsCompatible)
@protocol ARTCipherParamsCompatible <NSObject>
- (ARTCipherParams *)toCipherParams;
@end

/**
 * Sets the properties to configure encryption for an `ARTHttpChannel` or `ARTRealtimeChannel` object.
 */
NS_SWIFT_NAME(CipherParams)
@interface ARTCipherParams : NSObject <ARTCipherParamsCompatible>

/**
 * The algorithm to use for encryption. Only `AES` is supported and is the default value.
 */
@property (readonly, nonatomic) NSString *algorithm;

/**
 * The private key used to encrypt and decrypt payloads.
 */
@property (readonly, nonatomic) NSData *key;

/**
 * The length of the key in bits; for example 128 or 256.
 */
@property (readonly, nonatomic) NSUInteger keyLength;

/**
 * The cipher mode. Only `CBC` is supported and is the default value.
 */
@property (readonly, getter=getMode) NSString *mode;

/// :nodoc:
- (instancetype)init UNAVAILABLE_ATTRIBUTE;

/// :nodoc:
- (instancetype)initWithAlgorithm:(NSString *)algorithm key:(id<ARTCipherKeyCompatible>)key;

/// :nodoc:
- (ARTCipherParams *)toCipherParams;

@end

/**
 * Contains the properties used to generate an `ARTCipherParams` object.
 *
 * Pass it to `+[ARTCrypto getDefaultParams:]`, or directly as the `cipher` of an `ARTChannelOptions` or `ARTRealtimeChannelOptions` object.
 */
NS_SWIFT_SENDABLE
NS_SWIFT_NAME(CipherParamOptions)
@interface ARTCipherParamOptions : NSObject <ARTCipherParamsCompatible>

/**
 * The algorithm to use for encryption. Only `AES` is supported. If `nil`, `AES` is used.
 */
@property (nullable, readonly, copy, nonatomic) NSString *algorithm;

/**
 * The private key used to encrypt and decrypt payloads, as binary `NSData` or a base64-encoded `NSString`.
 */
@property (readonly, nonatomic) id<ARTCipherKeyCompatible> key;

/**
 * The length of the key in bits; for example 128 or 256. If `0`, the length is calculated from the key.
 */
@property (readonly, nonatomic) NSUInteger keyLength;

/**
 * The cipher mode. Only `CBC` is supported. If `nil`, `CBC` is used.
 */
@property (nullable, readonly, copy, nonatomic) NSString *mode;

/**
 * Creates an options object with a key only, using the default values for all other fields.
 *
 * @param key The private key used to encrypt and decrypt payloads, as binary `NSData` or a base64-encoded `NSString`.
 */
- (instancetype)initWithKey:(id<ARTCipherKeyCompatible>)key;

/**
 * Creates an options object. The initializer stores copies of its arguments.
 *
 * @param key The private key used to encrypt and decrypt payloads, as binary `NSData` or a base64-encoded `NSString`.
 * @param algorithm The algorithm to use for encryption, or `nil` for the default, `AES`.
 * @param keyLength The length of the key in bits, or `0` to calculate it from the key.
 * @param mode The cipher mode, or `nil` for the default, `CBC`.
 */
- (instancetype)initWithKey:(id<ARTCipherKeyCompatible>)key
                  algorithm:(nullable NSString *)algorithm
                  keyLength:(NSUInteger)keyLength
                       mode:(nullable NSString *)mode NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/// :nodoc:
- (ARTCipherParams *)toCipherParams;

@end

/**
 * Contains the properties required to configure the encryption of `ARTMessage` payloads.
 */
NS_SWIFT_NAME(Crypto)
@interface ARTCrypto : NSObject
/**
 * Returns an `ARTCipherParams` object, using the default values for any fields not supplied by the `ARTCipherParamOptions` object.
 *
 * Raises `NSInvalidArgumentException` if the options are invalid or inconsistent, for example if the key's length is not valid for the algorithm, or does not match `keyLength`.
 *
 * @param options An `ARTCipherParamOptions` object.
 *
 * @return An `ARTCipherParams` object, using the default values for any fields not supplied.
 */
+ (ARTCipherParams *)getDefaultParams:(ARTCipherParamOptions *)options;

/**
 * Generates a random key to be used in the encryption of the channel.
 *
 * @param length The length of the key, in bits, to be generated.
 *
 * @return The key as a binary `NSData`.
 */
+ (NSData *)generateRandomKey:(NSUInteger)length;

/**
 * Generates a random key to be used in the encryption of the channel.
 * Here the default key length of the default algorithm is used: for `AES` this is 256 bits.
 *
 * @return The key as a binary `NSData`.
 */
+ (NSData *)generateRandomKey;

@end

NS_ASSUME_NONNULL_END
