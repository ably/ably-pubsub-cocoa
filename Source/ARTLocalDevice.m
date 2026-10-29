#import "ARTLocalDevice+Private.h"
#import "ARTDeviceDetails+Private.h"
#import "ARTDevicePushDetails.h"
#import "ARTPush.h"
#import "ARTEncoder.h"
#import "ARTDeviceStorage.h"
#import "ARTDeviceIdentityTokenDetails+Private.h"
#import "ARTCrypto+Private.h"
#import "ARTInternalLog.h"
#import "ARTTypes+Private.h"
#import "ARTPushActivationStateMachine+Private.h"

NSString *const ARTDevicePlatform = @"ios";

#if TARGET_OS_IOS
#import <UIKit/UIKit.h>
NSString *const ARTDeviceFormFactor = @"phone";
#elif TARGET_OS_TV
NSString *const ARTDeviceFormFactor = @"tv";
#elif TARGET_OS_WATCH
NSString *const ARTDeviceFormFactor = @"watch";
#elif TARGET_OS_SIMULATOR
NSString *const ARTDeviceFormFactor = @"simulator";
#elif TARGET_OS_MAC
NSString *const ARTDeviceFormFactor = @"desktop";
#else
NSString *const ARTDeviceFormFactor = @"embedded";
#endif

NSString *const ARTDevicePushTransportType = @"apns";

NSString *const ARTDeviceIdKey = @"ARTDeviceId";
NSString *const ARTDeviceSecretKey = @"ARTDeviceSecret";
NSString *const ARTDeviceIdentityTokenKey = @"ARTDeviceIdentityToken";
NSString *const ARTAPNSDeviceTokenKey = @"ARTAPNSDeviceToken";
NSString *const ARTClientIdKey = @"ARTClientId";

NSString *const ARTAPNSDeviceDefaultTokenType = @"default";
NSString *const ARTAPNSDeviceLocationTokenType = @"location";
NSString *const ARTAPNSDevicePushToStartTokenType = @"pushToStart";

NSString* ARTAPNSDeviceTokenKeyOfType(NSString *tokenType) {
    return [ARTAPNSDeviceTokenKey stringByAppendingFormat:@"-%@", tokenType ?: ARTAPNSDeviceDefaultTokenType];
}

@interface ARTLocalDevice ()

@property (nullable, nonatomic, readonly) ARTInternalLog *logger;

@end

@implementation ARTLocalDevice

- (instancetype)initWithStorage:(id<ARTDeviceStorage>)storage logger:(nullable ARTInternalLog *)logger {
    if (self = [super init]) {
        self.storage = storage;
        _logger = logger;
    }
    return self;
}

// RSH8b helper. Only generates a new (id, deviceSecret) pair and persists it.
// Decision about when generation should happen and what else to clear belongs to the caller.
// If `writer` is omitted, device's storage is used (for standalone calls).
- (void)generateAndPersistPairOfDeviceIdAndSecretForStorage:(id<ARTDeviceStorage>)writer {
    NSString *newId = [self.class generateId];
    NSString *newSecret = [self.class generateSecret];
    self.id = newId;
    self.secret = newSecret;
    // The inner batch makes the helper safe to call standalone: id and
    // secret reach disk together rather than as two separate flushes. When
    // a caller is already inside its own batch (e.g. `resetDetails`) the
    // nested batch is just a counter bump — the outer batch still owns the
    // single flush.
    [(writer ?: _storage) performBatchUpdate:^(id<ARTDeviceStorage> writer) {
        [writer setObject:newId forKey:ARTDeviceIdKey];
        [writer setObject:newSecret forKey:ARTDeviceSecretKey];
    }];
}

+ (instancetype)deviceWithStorage:(id<ARTDeviceStorage>)storage logger:(nullable ARTInternalLog *)logger {
    ARTLocalDevice *device = [[ARTLocalDevice alloc] initWithStorage:storage logger:logger];
    device.platform = ARTDevicePlatform;
    // TODO: Set this based on the UIDevice's userInterfaceIdiom (https://github.com/ably/ably-pubsub-cocoa/issues/2132)
    device.formFactor = ARTDeviceFormFactor;
    device.push.recipient[@"transportType"] = ARTDevicePushTransportType;

    NSString *deviceId = [storage objectForKey:ARTDeviceIdKey];
    NSString *deviceSecret = [storage objectForKey:ARTDeviceSecretKey];

    // RSH8a
    if (deviceId && deviceSecret) {
        device.id = deviceId;
        device.secret = deviceSecret;

        ARTDeviceIdentityTokenDetails *identityTokenDetails = [ARTDeviceIdentityTokenDetails art_unarchiveFromStorage:storage
                                                                                                                  key:ARTDeviceIdentityTokenKey
                                                                                                           withLogger:logger];
        device->_identityTokenDetails = identityTokenDetails;

        NSString *clientId = [storage objectForKey:ARTClientIdKey];
        if (clientId == nil && identityTokenDetails.clientId != nil) {
            clientId = identityTokenDetails.clientId; // Older versions of the SDK did not persist clientId, so as a fallback when loading data persisted by these versions we use the clientId of the stored identity token
            [storage setObject:clientId forKey:ARTClientIdKey];
        }
        device.clientId = clientId;

        NSArray *supportedTokenTypes = @[
            ARTAPNSDeviceDefaultTokenType,
            ARTAPNSDeviceLocationTokenType,
            ARTAPNSDevicePushToStartTokenType
        ];

        for (NSString *tokenType in supportedTokenTypes) {
            NSString *token = [ARTLocalDevice apnsDeviceTokenOfType:tokenType fromStorage:storage];
            [device setAPNSDeviceToken:token tokenType:tokenType];
        }
    }
    else {
        // RSH8b, RSH8k2
        ARTLogDebug(logger, @"LocalDevice: generating a fresh id+secret pair");
        [device generateAndPersistPairOfDeviceIdAndSecretForStorage:nil];
    }
    return device;
}

- (void)setupDetailsWithClientId:(NSString *)clientId {
    self.clientId = clientId;
    [_storage setObject:clientId forKey:ARTClientIdKey];
}

- (void)resetDetails {
    [_storage performBatchUpdate:^(id<ARTDeviceStorage> writer) {
        // Wipe everything persisted, then regenerate — all in the same batch,
        // so the id+secret regeneration lands together with the wipe.
        [writer removeAll];
        [self generateAndPersistPairOfDeviceIdAndSecretForStorage:writer];

        // Mirror the persistent clear in the in-memory device state.
        self.clientId = nil;
        _identityTokenDetails = nil;
        [self setAPNSDeviceToken:nil tokenType:ARTAPNSDeviceDefaultTokenType];
        [self setAPNSDeviceToken:nil tokenType:ARTAPNSDeviceLocationTokenType];
        [self setAPNSDeviceToken:nil tokenType:ARTAPNSDevicePushToStartTokenType];
    }];
}

+ (NSString *)generateId {
    return [NSUUID new].UUIDString;
}

+ (NSString *)generateSecret {
    NSData *randomData = [ARTCrypto generateSecureRandomData:32];
    NSData *hash = [ARTCrypto generateHashSHA256:randomData];
    return [hash base64EncodedStringWithOptions:0];
}

+ (NSString *)apnsDeviceTokenOfType:(nullable NSString *)tokenType fromStorage:(id<ARTDeviceStorage>)storage {
    NSString *token = [storage objectForKey:ARTAPNSDeviceTokenKeyOfType(tokenType)];
    if ([tokenType isEqualToString:ARTAPNSDeviceDefaultTokenType] && token == nil) {
        token = [storage objectForKey:ARTAPNSDeviceTokenKey]; // Read legacy token
    }
    return token;
}

- (NSString *)apnsDeviceToken {
    NSDictionary *deviceTokens = (NSDictionary *)self.push.recipient[@"apnsDeviceTokens"];
    return deviceTokens[ARTAPNSDeviceDefaultTokenType];
}

- (void)setAPNSDeviceToken:(NSString *)token tokenType:(NSString *)tokenType {
    NSMutableDictionary *deviceTokens = [(self.push.recipient[@"apnsDeviceTokens"] ?: (token != nil ? @{} : nil)) mutableCopy];
    deviceTokens[tokenType] = token;
    self.push.recipient[@"apnsDeviceTokens"] = [deviceTokens copy];
}

- (void)setAndPersistAPNSDeviceToken:(NSString *)token tokenType:(NSString *)tokenType {
    [self.storage setObject:token forKey:ARTAPNSDeviceTokenKeyOfType(tokenType)];
    [self setAPNSDeviceToken:token tokenType:tokenType];
}

- (void)setAndPersistAPNSDeviceToken:(NSString *)token {
    [self setAndPersistAPNSDeviceToken:token tokenType:ARTAPNSDeviceDefaultTokenType];
}

- (void)setAndPersistIdentityTokenDetails:(ARTDeviceIdentityTokenDetails *)tokenDetails {
    NSData *tokenData = [tokenDetails art_archiveWithLogger:self.logger];
    BOOL adoptClientId = (self.clientId == nil && tokenDetails.clientId != nil);
    _identityTokenDetails = tokenDetails;
    if (adoptClientId) {
        self.clientId = tokenDetails.clientId;
    }
    [self.storage performBatchUpdate:^(id<ARTDeviceStorage> writer) {
        [writer setObject:tokenData forKey:ARTDeviceIdentityTokenKey];
        if (adoptClientId) {
            [writer setObject:tokenDetails.clientId forKey:ARTClientIdKey];
        }
    }];
}

- (BOOL)isRegistered {
    return _identityTokenDetails != nil;
}

@end
