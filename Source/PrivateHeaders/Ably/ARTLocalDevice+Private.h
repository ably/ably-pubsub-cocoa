#import <AblyPubSubDevice/ARTHttpClient.h>

@class ARTInternalLog;
@protocol ARTDeviceStorage;

NS_ASSUME_NONNULL_BEGIN

extern NSString *const ARTDeviceIdKey;
extern NSString *const ARTDeviceSecretKey;
extern NSString *const ARTDeviceIdentityTokenKey;
extern NSString *const ARTAPNSDeviceTokenKey;
extern NSString *const ARTClientIdKey;

extern NSString *const ARTAPNSDeviceDefaultTokenType;
extern NSString *const ARTAPNSDeviceLocationTokenType;
extern NSString *const ARTAPNSDevicePushToStartTokenType;

NSString* ARTAPNSDeviceTokenKeyOfType(NSString * _Nullable tokenType);

@interface ARTLocalDevice ()

@property (nonatomic) id<ARTDeviceStorage> storage;
@property (nullable, nonatomic, readwrite) ARTDeviceSecret *secret;

+ (instancetype)deviceWithStorage:(id<ARTDeviceStorage>)storage logger:(nullable ARTInternalLog *)logger;
- (nullable NSString *)apnsDeviceToken;
- (void)setAndPersistAPNSDeviceToken:(nullable NSString *)deviceToken tokenType:(NSString *)tokenType;
- (void)setAndPersistAPNSDeviceToken:(nullable NSString *)deviceToken;
- (void)setAndPersistIdentityTokenDetails:(nullable ARTDeviceIdentityTokenDetails *)tokenDetails;
- (BOOL)isRegistered;
- (void)resetDetails;
- (void)setupDetailsWithClientId:(nullable NSString *)clientId;

+ (NSString *)generateId;
+ (NSString *)generateSecret;

+ (nullable NSString *)apnsDeviceTokenOfType:(nullable NSString *)tokenType fromStorage:(id<ARTDeviceStorage>)storage;

@end

NS_ASSUME_NONNULL_END
