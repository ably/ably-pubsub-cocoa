#import "ARTLocalDeviceStorage.h"
#import <Security/Security.h>
#import "ARTAtomicFileStorage.h"
#import "ARTInternalLog.h"
#import "ARTLocalDevice+Private.h"
#import "ARTPushActivationStateMachine+Private.h"

static NSString *const ARTLocalDeviceStorageDirectoryName = @"Ably";
static NSString *const ARTLocalDeviceStorageFileName = @"LocalDevice.plist";

static NSString *const ARTLegacyAPNSDeviceTokenKey = @"ARTAPNSDeviceToken";

NSString *const ARTMigratedFromLegacyStorageKey = @"ARTMigratedFromLegacyStorage";

@implementation ARTLocalDeviceStorage {
    ARTInternalLog *_logger;
    BOOL _logValues;

    ARTAtomicFileStorage *_store;
    NSMutableDictionary<NSString *, id> *_cache;

    NSRecursiveLock *_lock;
    NSInteger _batchDepth;
    BOOL _isModified;

    ARTLegacyKeychainSecretReader _legacyKeychainReader;
}

#pragma mark - Init

- (instancetype)initWithLogger:(nullable ARTInternalLog *)logger logValues:(BOOL)logValues {
    return [self initWithBaseDirectoryURL:[ARTLocalDeviceStorage defaultBaseDirectoryURL]
                                   logger:logger
                                logValues:logValues];
}

+ (instancetype)newWithLogger:(nullable ARTInternalLog *)logger logValues:(BOOL)logValues {
    return [[self alloc] initWithLogger:logger logValues:logValues];
}

- (instancetype)initWithBaseDirectoryURL:(NSURL *)baseDirectoryURL
                                  logger:(nullable ARTInternalLog *)logger
                               logValues:(BOOL)logValues {
    return [self initWithBaseDirectoryURL:baseDirectoryURL
                                   logger:logger
                                logValues:logValues
                     legacyKeychainReader:nil];
}

- (instancetype)initWithBaseDirectoryURL:(NSURL *)baseDirectoryURL
                                  logger:(nullable ARTInternalLog *)logger
                               logValues:(BOOL)logValues
                    legacyKeychainReader:(nullable ARTLegacyKeychainSecretReader)legacyKeychainReader {
    if (self = [super init]) {
        _logger = logger;
        _logValues = logValues;
        _lock = [[NSRecursiveLock alloc] init];
        _lock.name = @"io.ably.ARTLocalDeviceStorage";
        _legacyKeychainReader = [legacyKeychainReader copy];

        NSURL *fileURL = [baseDirectoryURL URLByAppendingPathComponent:ARTLocalDeviceStorageFileName];
        _store = [[ARTAtomicFileStorage alloc] initWithFileURL:fileURL logger:logger];
        _cache = [[_store load] mutableCopy];

        // Technically the RSH8a1 check-and-discard should happen lazily when the
        // LocalDevice is first required; for simplicity we are instead
        // performing it eagerly at storage init (and thus at client init).
        // We'll address this later if it turns out to cause problems; tracking
        // in https://github.com/ably/ably-pubsub-cocoa/issues/2214.
        [self migrateLegacyDataIfNeeded];
    }
    return self;
}

+ (NSURL *)defaultBaseDirectoryURL {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *error = nil;
    NSURL *appSupport = [fm URLForDirectory:NSApplicationSupportDirectory
                                   inDomain:NSUserDomainMask
                          appropriateForURL:nil
                                     create:YES
                                      error:&error];
    if (appSupport == nil) {
        // Fall back to the temp directory if Application Support is somehow
        // unavailable — the SDK won't persist anything across launches in that
        // case, but at least won't crash.
        appSupport = [NSURL fileURLWithPath:NSTemporaryDirectory()];
    }
    return [appSupport URLByAppendingPathComponent:ARTLocalDeviceStorageDirectoryName];
}

#pragma mark - Logging helpers

- (id)valueToLogForValue:(id)value {
    if (!_logValues) {
        return @"(retracted)";
    }
    if ([value isKindOfClass:[NSData class]]) {
        // `NSData`'s default `description` is a hex-ish dump that's
        // awkward to read or paste back for inspection. Render as
        // base64 with a prefix that makes the encoding explicit.
        return [NSString stringWithFormat:@"<NSData base64:%@>", [(NSData *)value base64EncodedStringWithOptions:0]];
    }
    return value;
}

#pragma mark - ARTDeviceStorage

- (nullable id)objectForKey:(NSString *)key {
    [_lock lock];
    id value = _cache[key];
    if (value == nil) {
        ARTLogDebug(_logger, @"ARTLocalDeviceStorage: read miss for key %@", key);
    }
    else {
        ARTLogDebug(_logger, @"ARTLocalDeviceStorage: read hit for key %@: %@", key, [self valueToLogForValue:value]);
    }
    [_lock unlock];
    return value;
}

- (void)setObject:(nullable id)value forKey:(NSString *)key {
    [_lock lock];
    [self mutateCacheForKey:key value:value];
    if (value == nil) {
        ARTLogDebug(_logger, @"ARTLocalDeviceStorage: deleted key %@", key);
    }
    else {
        ARTLogDebug(_logger, @"ARTLocalDeviceStorage: wrote key %@: %@", key, [self valueToLogForValue:value]);
    }
    [self flushIfNotBatching];
    [_lock unlock];
}

- (void)removeAll {
    [_lock lock];
    if (_cache.count > 0) {
        [_cache removeAllObjects];
        _isModified = YES;
    }
    [self flushIfNotBatching];
    [_lock unlock];
}

- (void)performBatchUpdate:(NS_NOESCAPE void (^)(id<ARTDeviceStorage>))block {
    [_lock lock];
    _batchDepth++;
    @try {
        block(self);
    }
    @finally {
        _batchDepth--;
        if (_batchDepth == 0) {
            [self flushIfModified];
        }
        [_lock unlock];
    }
}

#pragma mark - Internal write helpers

- (void)mutateCacheForKey:(NSString *)key value:(nullable id)value {
    if (value == nil) {
        if (_cache[key] == nil) return; // no-op
        [_cache removeObjectForKey:key];
    }
    else {
        if ([_cache[key] isEqual:value]) return; // no-op
        _cache[key] = value;
    }
    _isModified = YES;
}

- (void)flushIfNotBatching {
    if (_batchDepth > 0) return;
    [self flushIfModified];
}

- (void)flushIfModified {
    if (!_isModified) return;
    NSError *error = nil;
    if (![_store save:_cache error:&error]) {
        ARTLogError(_logger, @"ARTLocalDeviceStorage: persist failed for %@: %@", _store.fileURL.lastPathComponent, error.localizedDescription);
        return;
    }
    _isModified = NO;
    ARTLogDebug(_logger, @"ARTLocalDeviceStorage: flushed %lu keys: (%@) (to %@)", (unsigned long)_cache.count, [_cache.allKeys componentsJoinedByString:@", "], _store.fileURL.lastPathComponent);
}

#pragma mark - Legacy migration

- (void)migrateLegacyDataIfNeeded {
    if ([_store fileExists]) {
        return; // already migrated (or new install with the storage already populated)
    }
    [self migrateLegacyData];
}

/// Reads any legacy data from `NSUserDefaults` + the keychain into the new
/// file. This is where RSH8a1 is enforced against the legacy data: a
/// successful load of both `id` and `deviceSecret` is the gate that lets any
/// of the persisted attributes cross into the new file. If the load fails,
/// every legacy field is discarded together so the device-fetch path
/// generates a fresh (id, secret) pair against an empty file.
///
/// The realistic reason for `legacySecret` to be absent when an `id` exists
/// is that the device hasn't been unlocked since reboot, so the keychain is
/// inaccessible.
///
/// Note that this is the _only_ place where we enforce RSH8a1; the load
/// failures (in particular, a load failure that affects only certain
/// LocalDevice attributes) which that spec point was written to address could
/// only, in practice, occur in the legacy storage.
- (void)migrateLegacyData {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    NSString *legacyDeviceId = [defaults objectForKey:ARTDeviceIdKey];
    NSString *legacyClientId = [defaults objectForKey:ARTClientIdKey];
    id legacyIdentityToken = [defaults objectForKey:ARTDeviceIdentityTokenKey];
    id legacyState = [defaults objectForKey:ARTPushActivationCurrentStateKey];
    id legacyPendingEvents = [defaults objectForKey:ARTPushActivationPendingEventsKey];
    id legacyApnsDefault = [defaults objectForKey:ARTAPNSDeviceTokenKeyOfType(ARTAPNSDeviceDefaultTokenType)];
    id legacyApnsLocation = [defaults objectForKey:ARTAPNSDeviceTokenKeyOfType(ARTAPNSDeviceLocationTokenType)];

    BOOL hasLegacy = (legacyDeviceId || legacyClientId || legacyIdentityToken ||
                      legacyState || legacyPendingEvents || legacyApnsDefault || legacyApnsLocation);
    if (!hasLegacy) {
        return;
    }

    NSString *legacySecret = nil;
    if (legacyDeviceId != nil) {
        OSStatus status = errSecSuccess;
        if (_legacyKeychainReader) {
            legacySecret = _legacyKeychainReader(legacyDeviceId, &status);
        }
        else {
            legacySecret = [self readLegacyKeychainSecretForDevice:legacyDeviceId status:&status];
        }
        // Any failure is treated as the legacy secret being absent.
        if (status != errSecSuccess) {
            ARTLogWarn(_logger, @"ARTLocalDeviceStorage: legacy keychain value is unavailable for device id %@ (status=%d)", legacyDeviceId, (int)status);
        }
    }

    NSMutableDictionary *migrated = [NSMutableDictionary dictionary];

    // RSH8a1: the legacy data crosses into the new file only if id and
    // secret are both loadable. Otherwise we drop everything and let the
    // device-fetch path start clean.
    if (legacyDeviceId != nil && legacySecret != nil) {
        migrated[ARTDeviceIdKey] = legacyDeviceId;
        migrated[ARTDeviceSecretKey] = legacySecret;
        migrated[ARTDeviceIdentityTokenKey] = legacyIdentityToken;
        migrated[ARTClientIdKey] = legacyClientId;

        migrated[ARTAPNSDeviceTokenKeyOfType(ARTAPNSDeviceDefaultTokenType)] = legacyApnsDefault;
        migrated[ARTAPNSDeviceTokenKeyOfType(ARTAPNSDeviceLocationTokenType)] = legacyApnsLocation;

        migrated[ARTPushActivationCurrentStateKey] = legacyState;
        migrated[ARTPushActivationPendingEventsKey] = legacyPendingEvents;

        // Mark the data as migrated so future versions can tell it apart from
        // data generated natively in the new file.
        migrated[ARTMigratedFromLegacyStorageKey] = @YES;
    }
    else {
        ARTLogWarn(_logger, @"ARTLocalDeviceStorage: legacy device data is incomplete; discarding legacy device details and state machine data");
    }

    NSError *saveError = nil;
    if (![_store save:migrated error:&saveError]) {
        ARTLogError(_logger, @"ARTLocalDeviceStorage: failed to write migrated file: %@", saveError.localizedDescription);
        return;
    }
    _cache = [migrated mutableCopy];

    // Log which fields were migrated. Values go through `valueToLogForValue:`
    // so secrets/tokens stay retracted unless value logging is explicitly on.
    NSMutableDictionary *loggableMigrated = [NSMutableDictionary dictionaryWithCapacity:migrated.count];
    for (NSString *key in migrated) {
        loggableMigrated[key] = [self valueToLogForValue:migrated[key]];
    }
    ARTLogInfo(_logger, @"ARTLocalDeviceStorage: migrated %lu legacy fields: %@", (unsigned long)migrated.count, loggableMigrated);
}

#pragma mark - Legacy keychain (read-and-delete only)

- (nullable NSString *)readLegacyKeychainSecretForDevice:(NSString *)deviceId status:(OSStatus *)outStatus {
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: ARTDeviceSecretKey,
        (__bridge id)kSecAttrAccount: deviceId,
        (__bridge id)kSecReturnData: @YES,
        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne,
    };
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (outStatus) *outStatus = status;
    if (status != errSecSuccess) {
        return nil;
    }
    NSData *data = (__bridge_transfer NSData *)result;
    if (data.length == 0) return nil;
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

- (void)deleteLegacyKeychainSecretForDevice:(NSString *)deviceId {
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: ARTDeviceSecretKey,
        (__bridge id)kSecAttrAccount: deviceId,
    };
    OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);
    if (status != errSecSuccess && status != errSecItemNotFound) {
        ARTLogWarn(_logger, @"ARTLocalDeviceStorage: failed to delete legacy keychain secret for device %@ (status=%d)", deviceId, (int)status);
    }
}

@end
