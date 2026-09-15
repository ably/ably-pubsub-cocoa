#import "ARTRest+Private.h"
#import "ARTEncoder.h"
#import <AblyPubSubDevice/ARTTokenDetails.h>
#import <AblyPubSubDevice/ARTTokenRequest.h>
#import <AblyPubSubDevice/ARTAuthDetails.h>
#import <AblyPubSubDevice/ARTStats.h>

@class ARTPublishResult;
@class ARTPublishResultSerial;
@protocol ARTTimeProvider;

NS_ASSUME_NONNULL_BEGIN

@protocol ARTJsonLikeEncoderDelegate <NSObject>

- (NSString *)mimeType;
- (ARTEncoderFormat)format;
- (NSString *)formatAsString;

- (nullable id)decode:(NSData *)data error:(NSError * _Nullable __autoreleasing * _Nullable)error;
- (nullable NSData *)encode:(id)obj error:(NSError * _Nullable __autoreleasing * _Nullable)error;

@end

@interface ARTJsonLikeEncoder : NSObject <ARTEncoder>

@property (nonatomic, nullable) id<ARTJsonLikeEncoderDelegate> delegate;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithDelegate:(id<ARTJsonLikeEncoderDelegate>)delegate timeProvider:(id<ARTTimeProvider>)timeProvider;
- (instancetype)initWithRest:(ARTRestInternal *)rest delegate:(nullable id<ARTJsonLikeEncoderDelegate>)delegate logger:(ARTInternalLog *)logger;

@end

@interface ARTJsonLikeEncoder ()

- (nullable ARTMessage *)messageFromDictionary:(NSDictionary *)input protocolMessage:(nullable ARTProtocolMessage *)protocolMessage;
- (nullable NSArray *)messagesFromArray:(NSArray *)input protocolMessage:(nullable ARTProtocolMessage *)protocolMessage;

- (nullable ARTAnnotation *)annotationFromDictionary:(NSDictionary *)input;
- (nullable NSArray *)annotationsFromArray:(NSArray *)input;

- (nullable ARTPresenceMessage *)presenceMessageFromDictionary:(NSDictionary *)input;
- (nullable NSArray *)presenceMessagesFromArray:(NSArray *)input;

- (NSDictionary *)messageToDictionary:(ARTMessage *)message;
- (NSArray *)messagesToArray:(NSArray *)messages;

- (NSDictionary *)annotationToDictionary:(ARTAnnotation *)annotation;
- (NSArray *)annotationsToArray:(NSArray *)annotations;

- (NSDictionary *)presenceMessageToDictionary:(ARTPresenceMessage *)message;
- (NSArray *)presenceMessagesToArray:(NSArray *)messages;

- (NSDictionary *)protocolMessageToDictionary:(ARTProtocolMessage *)message;
- (nullable ARTProtocolMessage *)protocolMessageFromDictionary:(NSDictionary *)input;

- (NSDictionary *)tokenRequestToDictionary:(ARTTokenRequest *)tokenRequest;

- (NSDictionary *)authDetailsToDictionary:(ARTAuthDetails *)authDetails;
- (nullable ARTAuthDetails *)authDetailsFromDictionary:(NSDictionary *)input;

- (nullable ARTPublishResultSerial *)publishResultSerialFromValue:(id)input;
- (nullable NSArray<ARTPublishResultSerial *> *)publishResultSerialsFromArray:(NSArray *)input;
- (nullable ARTPublishResult *)publishResultFromDictionary:(NSDictionary *)input;
- (nullable NSArray<ARTPublishResult *> *)publishResultsFromArray:(NSArray *)input;

- (id)publishResultSerialToValue:(ARTPublishResultSerial *)serial;
- (NSArray *)publishResultSerialsToArray:(NSArray<ARTPublishResultSerial *> *)serials;
- (NSDictionary *)publishResultToDictionary:(ARTPublishResult *)publishResult;
- (NSArray *)publishResultsToArray:(NSArray<ARTPublishResult *> *)publishResults;

- (nullable NSArray *)statsFromArray:(NSArray *)input;
- (nullable ARTStats *)statsFromDictionary:(NSDictionary *)input;
- (nullable ARTStatsMessageTypes *)statsMessageTypesFromDictionary:(NSDictionary *)input;
- (nullable ARTStatsMessageCount *)statsMessageCountFromDictionary:(NSDictionary *)input;
- (nullable ARTStatsMessageTraffic *)statsMessageTrafficFromDictionary:(NSDictionary *)input;
- (nullable ARTStatsConnectionTypes *)statsConnectionTypesFromDictionary:(NSDictionary *)input;
- (nullable ARTStatsResourceCount *)statsResourceCountFromDictionary:(NSDictionary *)input;
- (nullable ARTStatsRequestCount *)statsRequestCountFromDictionary:(NSDictionary *)input;

- (void)writeData:(id)data encoding:(NSString *)encoding toDictionary:(NSMutableDictionary *)output;

- (nullable NSDictionary *)decodeDictionary:(NSData *)data error:(NSError **)error;
- (nullable NSArray *)decodeArray:(NSData *)data error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
