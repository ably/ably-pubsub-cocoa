#import "ARTCrypto+Private.h"
#import "ARTInternalLog.h"

#import <CommonCrypto/CommonCrypto.h>
#import "ARTStatus.h"

#define ART_CBC_BLOCK_LENGTH (16)

@interface ARTCipherParams ()

- (BOOL)ccAlgorithm:(CCAlgorithm *)algorithm error:(NSError **)error;

@end

@interface ARTCbcCipher ()

@property CCAlgorithm algorithm;

@end

@implementation NSString (ARTCipherKeyCompatible)

- (NSData *)toData {
    NSString *key = self;
    key = [key stringByReplacingOccurrencesOfString:@"-" withString:@"+"];
    key = [key stringByReplacingOccurrencesOfString:@"_" withString:@"/"];
    return [[NSData alloc] initWithBase64EncodedString:key options:0];
}

@end

@implementation NSData (ARTCipherKeyCompatible)

- (NSData *)toData {
    return self;
}

@end

@implementation ARTCipherParams

- (instancetype)initWithAlgorithm:(NSString *)algorithm key:(id<ARTCipherKeyCompatible>)key {
    NSData *keyData = [key toData];
    return [self initWithAlgorithm:algorithm key:keyData iv:nil];
}

- (instancetype)initWithAlgorithm:(NSString *)algorithm key:(id<ARTCipherKeyCompatible>)key iv:(NSData *)iv {
    self = [super init];
    if (self) {
        _algorithm = algorithm;
        _key = [key toData];
        _keyLength = [_key length] * 8;
        _iv = iv;

        CCAlgorithm ccAlgorithm;
        NSError *error = nil;
        if (![self ccAlgorithm:&ccAlgorithm error:&error]) {
            [ARTException raise:NSInvalidArgumentException format:@"%@", error.userInfo[NSLocalizedFailureReasonErrorKey]];
        }
    }
    return self;
}

- (NSString *)getMode {
    return @"CBC";
}

- (BOOL)ccAlgorithm:(CCAlgorithm *)algorithm error:(NSError **)error {
    NSString *errorMsg;
    if (NSOrderedSame == [self.algorithm compare:@"AES" options:NSCaseInsensitiveSearch]) {
        if (self.iv != nil && [self.iv length] != ART_CBC_BLOCK_LENGTH) {
            errorMsg = [NSString stringWithFormat:@"iv length expected to be %d, got %d instead", ART_CBC_BLOCK_LENGTH, (int)[self.iv length]];
        } else if (self.keyLength != 128 && self.keyLength != 256) {
            errorMsg = [NSString stringWithFormat:@"invalid key length for AES algorithm: %d", (int)self.keyLength];
        } else {
            *algorithm = kCCAlgorithmAES;
        }
    } else if (NSOrderedSame == [self.algorithm compare:@"DES" options:NSCaseInsensitiveSearch]) {
        *algorithm = kCCAlgorithmDES;
    } else if (NSOrderedSame == [self.algorithm compare:@"3DES" options:NSCaseInsensitiveSearch]) {
        *algorithm = kCCAlgorithm3DES;
    } else if (NSOrderedSame == [self.algorithm compare:@"CAST" options:NSCaseInsensitiveSearch]) {
        *algorithm = kCCAlgorithmCAST;
    } else if (NSOrderedSame == [self.algorithm compare:@"RC4" options:NSCaseInsensitiveSearch]) {
        *algorithm = kCCAlgorithmRC4;
    } else if (NSOrderedSame == [self.algorithm compare:@"RC2" options:NSCaseInsensitiveSearch]) {
        *algorithm = kCCAlgorithmRC2;
    } else {
        errorMsg = [NSString stringWithFormat:@"unknown algorithm: %@", self.algorithm];
    }

    if (errorMsg) {
        if (error) *error = [NSError errorWithDomain:ARTAblyErrorDomain code:0 userInfo:@{NSLocalizedFailureReasonErrorKey: errorMsg}];
        return NO;
    }

    return YES;
}

- (ARTCipherParams *)toCipherParams {
    return self;
}

@end

@implementation NSDictionary (ARTCipherParamsCompatible)

- (ARTCipherParams *)toCipherParams {
    return [ARTCrypto getDefaultParams:self];
}

@end

@implementation ARTCbcCipher

- (id)initWithCipherParams:(ARTCipherParams *)cipherParams logger:(ARTInternalLog *)logger {
    self = [super init];
    if (self) {
        _keySpec = cipherParams.key;
        _iv = cipherParams.iv;
        _blockLength = ART_CBC_BLOCK_LENGTH;
        _logger = logger;

        if (![cipherParams ccAlgorithm:&_algorithm error:nil]) {
            return nil;
        }
    }
    return self;
}

-(size_t) keyLength {
    return [self.keySpec length] *8;
}

+ (instancetype)cbcCipherWithParams:(ARTCipherParams *)cipherParams logger:(ARTInternalLog *)logger {
    return [[self alloc] initWithCipherParams:cipherParams logger:logger];
}

- (ARTStatus *)encrypt:(NSData *)plaintext output:(NSData *__autoreleasing *)output {
    NSData *iv = self.iv != nil ? self.iv : [ARTCrypto generateSecureRandomData:self.blockLength];
    NSData *ciphertext = nil;

    // The maximum cipher text is plaintext length + block length. We are also prepending this with the IV so need 2 block lengths in addition to the plaintext length.
    size_t outputBufLen = [plaintext length] + self.blockLength * 2;
    void *buf = malloc(outputBufLen);

    if (!buf) {
        ARTLogError(self.logger, @"ARTCrypto error encrypting");
        return [ARTStatus state:ARTStateError];
    }

    // Copy the iv first
    memcpy(buf, [iv bytes], self.blockLength);

    void *ciphertextBuf = ((char *)buf) + self.blockLength;
    size_t ciphertextBufLen = outputBufLen - self.blockLength;

    const void *key = [self.keySpec bytes];
    size_t keyLen = [self.keySpec length];

    const void *ivBytes = [iv bytes];
    const void *dataIn = [plaintext bytes];
    size_t dataInLen = [plaintext length];

    size_t bytesWritten = 0;
    CCCryptorStatus status = CCCrypt(kCCEncrypt, self.algorithm, kCCOptionPKCS7Padding, key, keyLen, ivBytes, dataIn, dataInLen, ciphertextBuf, ciphertextBufLen, &bytesWritten);

    if (status) {
        ARTLogError(self.logger, @"ARTCrypto error encrypting. Status is %d", status);
        free(ciphertextBuf);
        return [ARTStatus state: ARTStateError];
    }

    ciphertext = [NSData dataWithBytesNoCopy:buf length:(bytesWritten + self.blockLength) freeWhenDone:YES];
    if (nil == ciphertext) {
        ARTLogError(self.logger, @"ARTCrypto error encrypting. cipher text is nil");
        free(buf);
        return [ARTStatus state:ARTStateError];
    }

    *output = ciphertext;

    return [ARTStatus state:ARTStateOk];
}

- (ARTStatus *)decrypt:(NSData *)ciphertext output:(NSData *__autoreleasing *)output {
    // The first *blockLength* bytes are the iv
    if ([ciphertext length] < self.blockLength) {
        return [ARTStatus state: ARTStateInvalidArgs];;
    }

    NSData *ivData = [ciphertext subdataWithRange:NSMakeRange(0, self.blockLength)];
    NSData *actualCiphertext = [ciphertext subdataWithRange:NSMakeRange(self.blockLength, [ciphertext length] - self.blockLength)];

    CCOptions options = 0;
    const void *key = [self.keySpec bytes];
    size_t keyLength = [self.keySpec length];

    const void *iv = [ivData bytes];
    const void *dataIn = [actualCiphertext bytes];
    size_t dataInLength = [actualCiphertext length];

    // The output will never be more than the input + block length
    size_t outputLength = dataInLength + self.blockLength;
    void *buf = malloc(outputLength);
    size_t bytesWritten = 0;

    if (!buf) {
        ARTLogError(self.logger, @"ARTCrypto error decrypting.");
        return [ARTStatus state:ARTStateError];
    }

    // Decrypt without padding because CCCrypt does not return an error code
    // if the decrypted value is not padded correctly
    CCCryptorStatus status = CCCrypt(kCCDecrypt, self.algorithm, options, key, keyLength, iv, dataIn, dataInLength, buf, outputLength, &bytesWritten);

    if (status) {
        ARTLogError(self.logger, @"ARTCrypto error decrypting. Status is %d", status);
        free(buf);
        return [ARTStatus state:ARTStateError];
    }

    // Check that the decrypted value is padded correctly and determine the unpadded length
    const char *cbuf = (char *)buf;
    int paddingLength = cbuf[bytesWritten - 1];

    if (0 == paddingLength || paddingLength > bytesWritten) {            free(buf);
        return [ARTStatus state:ARTStateCryptoBadPadding];
    }

    for (size_t i=(bytesWritten - 1); i>(bytesWritten - paddingLength); --i) {
        if (paddingLength != cbuf[i-1]) {
            free(buf);
            return [ARTStatus state:ARTStateCryptoBadPadding];
        }
    }

    size_t unpaddedLength = bytesWritten - paddingLength;

    NSData *plaintext = [NSData dataWithBytesNoCopy:buf length:unpaddedLength freeWhenDone:YES];
    if (!plaintext) {
        ARTLogError(self.logger, @"ARTCrypto error decrypting. plain text is nil");
        free(buf);
    }

    *output = plaintext;

    return [ARTStatus state:ARTStateOk];
}

- (NSString *)cipherName {
    NSString *algo = nil;
    switch (self.algorithm) {
        case kCCAlgorithmAES:
            algo = @"aes";
            break;
        case kCCAlgorithmDES:
            algo = @"des";
            break;
        case kCCAlgorithm3DES:
            algo = @"3des";
            break;
        case kCCAlgorithmCAST:
            algo = @"cast";
            break;
        case kCCAlgorithmRC4:
            algo = @"rc4";
            break;
        case kCCAlgorithmRC2:
            algo = @"rc2";
            break;
        default:
            NSAssert(NO, @"Invalid algorithm");
            return nil;
    }
    return [NSString stringWithFormat:@"%@-cbc", algo];
}

@end

@implementation ARTCrypto

+ (NSString *)defaultAlgorithm {
    return @"AES";
}

+ (int)defaultKeyLength {
    return 256;
}

+ (int)defaultBlockLength {
    return 128;
}

+ (NSMutableData *)generateSecureRandomData:(size_t)length {
    void *buf = malloc(length);
    if (!buf) {
        return nil;
    }
    int rc = SecRandomCopyBytes(kSecRandomDefault, length, buf);
    if (rc != 0) {
        free(buf);
        return nil;
    }

    NSMutableData *outputData = [NSMutableData dataWithBytesNoCopy:buf length:length freeWhenDone:YES];
    if (!outputData) {
        free(buf);
    }
    return outputData;
}

+ (NSData *)generateHashSHA256:(NSData *)data {
    u_int8_t digest[CC_SHA256_DIGEST_LENGTH * sizeof(u_int8_t)];
    memset(digest, 0x0, CC_SHA256_DIGEST_LENGTH);
    CC_SHA256([data bytes], (CC_LONG)[data length], digest);
    NSData *hash = [NSData dataWithBytes:digest length:CC_SHA256_DIGEST_LENGTH];
    return hash;
}

+ (ARTCipherParams *)getDefaultParams:(NSDictionary *)cipherParams {
    NSString *algorithm = cipherParams[@"algorithm"];
    if (algorithm == nil) {
        algorithm = [ARTCrypto defaultAlgorithm];
    }
    NSString *key = cipherParams[@"key"];
    if (key == nil) {
        [ARTException raise:NSInvalidArgumentException format:@"missing key parameter"];
    }
    return [[ARTCipherParams alloc] initWithAlgorithm:algorithm key:key];
}

+ (NSData *)generateRandomKey {
    return [self generateRandomKey:[self defaultKeyLength]];
}

+ (NSData *)generateRandomKey:(NSUInteger)length {
    return [self generateSecureRandomData:length / 8];
}

+ (id<ARTChannelCipher>)cipherWithParams:(ARTCipherParams *)params logger:(ARTInternalLog *)logger {
    return [ARTCbcCipher cbcCipherWithParams:params logger:logger];
}

@end
