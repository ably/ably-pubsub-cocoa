#import <Foundation/Foundation.h>

#import <AblyPubSubDevice/ARTTypes.h>
#import <AblyPubSubDevice/ARTStatus.h>

NS_ASSUME_NONNULL_BEGIN

/// :nodoc:
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
@protocol ARTCipherParamsCompatible <NSObject>
- (ARTCipherParams *)toCipherParams;
@end

/// :nodoc:
@interface NSDictionary (ARTCipherParamsCompatible) <ARTCipherParamsCompatible>
- (ARTCipherParams *)toCipherParams;
@end

/**
 * Sets the properties to configure encryption for an `ARTHttpChannel` or `ARTRealtimeChannel` object.
 */
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
 * Contains the properties required to configure the encryption of `ARTMessage` payloads.
 */
@interface ARTCrypto : NSObject
/**
 * Returns an `ARTCipherParams` object, using the default values for any fields not supplied by the `cipherParams` dictionary.
 *
 * @param cipherParams An `ARTCipherParams`-like dictionary object.
 *
 * @return An `ARTCipherParams` object, using the default values for any fields not supplied.
 */
+ (ARTCipherParams *)getDefaultParams:(NSDictionary *)cipherParams;

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
