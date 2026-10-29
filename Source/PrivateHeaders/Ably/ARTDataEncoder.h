#import <Foundation/Foundation.h>

#import <AblyPubSubDevice/ARTErrorInfo.h>
#import <AblyPubSubDevice/ARTCrypto.h>

@class ARTCipherParams;
@class ARTPlugin;
@class ARTInternalLog;

NS_ASSUME_NONNULL_BEGIN

@interface ARTDataEncoderOutput : NSObject

@property (readonly, nonatomic, nullable) id data;
@property (readonly, nonatomic, nullable) NSString *encoding;
@property (readonly, nonatomic, nullable) ARTErrorInfo *errorInfo;

- initWithData:(id _Nullable)data encoding:(NSString *_Nullable)encoding errorInfo:(ARTErrorInfo *_Nullable)errorInfo;

@end

/**
 * `ARTDataEncoder` is used to:
 *
 * - convert the `data` property of an `ARTMessage` into a format that's suitable to be sent over the wire; that is, to ensure that this `ARTMessage` can be placed inside an `ARTProtocolMessage`
 * - convert the `data` property of an `ARTMessage` contained inside an `ARTProtocolMessage` into something that's suitable to expose to the user of the SDK
 */
@interface ARTDataEncoder : NSObject

- (instancetype)initWithCipherParams:(ARTCipherParams *_Nullable)params logger:(ARTInternalLog *)logger error:(NSError *_Nullable*_Nullable)error;
- (ARTDataEncoderOutput *)encode:(id _Nullable)data;
- (ARTDataEncoderOutput *)decode:(id _Nullable)data encoding:(NSString *_Nullable)encoding;
- (ARTDataEncoderOutput *)decode:(id _Nullable)data identifier:(NSString *)identifier encoding:(NSString *_Nullable)encoding;

@end

@interface NSString (ARTDataEncoder)

+ (NSString *)artAddEncoding:(NSString *)encoding toString:(NSString *_Nullable)s;
- (NSString *)artLastEncoding;
- (nullable NSString *)artRemoveLastEncoding;

@end

NS_ASSUME_NONNULL_END
