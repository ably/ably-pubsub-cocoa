#import <Foundation/Foundation.h>

#import <AblyPubSubDevice/ARTTypes.h>
#import <AblyPubSubDevice/ARTCrypto.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Passes additional properties to an `ARTHttpChannel` object, such as encryption.
 */
@interface ARTChannelOptions : NSObject <NSCopying>

/**
 * Requests encryption for this channel when not `nil`, and specifies encryption-related parameters (such as algorithm, chaining mode, key length and key). See [an example](https://ably.com/docs/realtime/encryption#getting-started).
 */
@property (nonatomic, nullable) ARTCipherParams *cipher;

/// :nodoc: TODO: docstring
- (instancetype)initWithCipher:(id<ARTCipherParamsCompatible> _Nullable)cipherParams;

/**
 * Creates an options object using a key only.
 *
 * @param key A private key used to encrypt and decrypt payloads.
 *
 * @return An `ARTChannelOptions` object.
 */
- (instancetype)initWithCipherKey:(id<ARTCipherKeyCompatible>)key;

@end

NS_ASSUME_NONNULL_END
