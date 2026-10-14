#import <Foundation/Foundation.h>

#import <AblyPubSubDevice/ARTTypes.h>
#import <AblyPubSubDevice/ARTCrypto.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Passes additional properties to an `ARTHttpChannel` object, such as encryption.
 */
NS_SWIFT_NAME(ChannelOptions)
@interface ARTChannelOptions : NSObject <NSCopying>

/**
 * Requests encryption for this channel when not `nil`, and specifies encryption-related parameters (such as algorithm, chaining mode, key length and key). See [an example](https://ably.com/docs/realtime/encryption#getting-started).
 */
@property (nonatomic, nullable) ARTCipherParams *cipher;

/**
 * Creates an options object that requests encryption for the channel.
 *
 * @param cipherParams An `ARTCipherParams` object, or `nil` for no encryption.
 *
 * @return An `ARTChannelOptions` object.
 */
- (instancetype)initWithCipher:(nullable ARTCipherParams *)cipherParams;

/**
 * Creates an options object that requests encryption for the channel, using `+[ARTCrypto getDefaultParams:]` to build the cipher parameters.
 *
 * @param options An `ARTCipherParamOptions` object.
 *
 * @return An `ARTChannelOptions` object.
 */
- (instancetype)initWithCipherOptions:(ARTCipherParamOptions *)options;

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
