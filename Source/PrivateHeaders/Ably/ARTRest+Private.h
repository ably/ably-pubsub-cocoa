#import <AblyPubSubDevice/ARTRest.h>
#import "ARTHttp.h"
#import "ARTRestChannels+Private.h"
#import "ARTPush+Private.h"

@protocol ARTEncoder;
@protocol ARTHTTPExecutor;
@protocol ARTDeviceStorage;
@class ARTInternalLog;
@class ARTRealtimeInternal;
@class ARTAuthInternal;
@protocol ARTContinuousClockInstant;
@protocol ARTTimeProvider;

NS_ASSUME_NONNULL_BEGIN

/// ARTRest private methods that are used internally and for internal testing
@interface ARTRestInternal : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithOptions:(ARTClientOptions *)options;
- (instancetype)initWithKey:(NSString *)key;
- (instancetype)initWithToken:(NSString *)token;

@property (nonatomic, readonly) ARTRestChannelsInternal *channels;
@property (nonatomic, readonly) ARTAuthInternal *auth;
@property (nonatomic, readonly) ARTPushInternal *push;
#if TARGET_OS_IOS
@property (nonnull, nonatomic, readonly, getter=device) ARTLocalDevice *device;
@property (nonnull, nonatomic, readonly, getter=device_nosync) ARTLocalDevice *device_nosync;
@property (nonatomic) id<ARTDeviceStorage> storage;
#endif

@property (nonatomic, readonly) ARTClientOptions *options;
@property (nonatomic, weak, nullable) ARTRealtimeInternal *realtime; // weak because realtime owns self
@property (readonly, nonatomic) id<ARTEncoder> defaultEncoder;
@property (readonly, nonatomic) NSString *defaultEncoding; //Content-Type
@property (readonly, nonatomic) NSDictionary<NSString *, id<ARTEncoder>> *encoders;

// Must be atomic!
@property (readwrite, atomic, nullable) NSString *prioritizedHost;

@property (nonatomic) id<ARTHTTPExecutor> httpExecutor;
@property (nonatomic, readonly, getter=getBaseUrl) NSURL *baseUrl;
@property (nullable, nonatomic, copy) NSString *currentFallbackHost;
@property (nullable, readonly, nonatomic) id<ARTContinuousClockInstant> fallbackRetryExpiration;

@property (nonatomic) dispatch_queue_t queue;
@property (nonatomic) dispatch_queue_t userQueue;

@property (nonatomic, readonly) id<ARTTimeProvider> timeProvider;

/**
 Provides access to the instance's logger. As the name says, this property should only be used in the following cases:

 - When writing class methods meeting the following criteria:
   - they wish to perform logging
   - they do not accept a logger parameter
   - their signature is already locked since they are part of the public API of the library
   - they have access to an ARTRest instance

 - When writing tests which wish to perform actions on this instance's logger (for making assertions about how the logger was set up).
 */
@property (nonatomic, readonly) ARTInternalLog *logger_onlyForUseInClassMethodsAndTests;

// MARK: Not accessible by tests
@property (readonly, nonatomic) ARTHttp *http;
@property (readwrite, nonatomic) int fallbackCount;

- (instancetype)initWithOptions:(ARTClientOptions *)options realtime:(ARTRealtimeInternal *_Nullable)realtime logger:(ARTInternalLog *)logger;

- (nullable NSObject<ARTCancellable> *)_timeWithWrapperSDKAgents:(nullable NSStringDictionary *)wrapperSDKAgents
                                                      completion:(ARTDateTimeCallback)callback;

// MARK: ARTHTTPExecutor

- (nullable NSObject<ARTCancellable> *)executeRequest:(NSURLRequest *)request
                                     wrapperSDKAgents:(nullable NSDictionary<NSString *, NSString *> *)wrapperSDKAgents
                                           completion:(nullable ARTURLRequestCallback)callback;

// MARK: Internal

- (nullable NSObject<ARTCancellable> *)executeRequest:(NSMutableURLRequest *)request
                                       withAuthOption:(ARTAuthentication)authOption
                                     wrapperSDKAgents:(nullable NSDictionary<NSString *, NSString *> *)wrapperSDKAgents
                                           completion:(ARTURLRequestCallback)callback;

- (nullable NSObject<ARTCancellable> *)internetIsUp:(void (^)(BOOL isUp))cb;

#if TARGET_OS_IOS
- (void)setupLocalDevice_nosync;
- (void)resetLocalDevice_nosync;

// This is only intended to be called from test code.
- (void)resetDeviceSingleton;

- (void)setAndPersistAPNSDeviceTokenData:(NSData *)deviceTokenData tokenType:(NSString *)tokenType;
#endif

- (void)timeWithWrapperSDKAgents:(nullable NSStringDictionary *)wrapperSDKAgents
                      completion:(ARTDateTimeCallback)callback;

- (BOOL)request:(NSString *)method
           path:(NSString *)path
         params:(nullable NSStringDictionary *)params
           body:(nullable id)body
        headers:(nullable NSStringDictionary *)headers
wrapperSDKAgents:(nullable NSStringDictionary *)wrapperSDKAgents
       callback:(ARTHTTPPaginatedCallback)callback
          error:(NSError *_Nullable *_Nullable)errorPtr;

- (BOOL)statsWithWrapperSDKAgents:(nullable NSStringDictionary *)wrapperSDKAgents
                       completion:(ARTPaginatedStatsCallback)callback;

- (BOOL)stats:(nullable ARTStatsQuery *)query
wrapperSDKAgents:(nullable NSStringDictionary *)wrapperSDKAgents
     callback:(ARTPaginatedStatsCallback)callback
        error:(NSError *_Nullable *_Nullable)errorPtr;

@end

@interface ARTRest ()

@property (nonatomic, readonly) ARTRestInternal *internal;

- (void)internalAsync:(void (^)(ARTRestInternal *))use;

@end

@interface NSData (APNS)

- (NSString *)deviceTokenString;

@end

NS_ASSUME_NONNULL_END
