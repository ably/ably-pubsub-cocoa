#import <AblyPubSubDevice/ARTAuth.h>
#import <AblyPubSubDevice/ARTEventEmitter.h>
#import "ARTQueuedDealloc.h"

@class ARTHttpClientInternal;
@class ARTInternalLog;

typedef NS_ENUM(NSUInteger, ARTAuthorizationState) {
    ARTAuthorizationSucceeded, //ItemType: nil
    ARTAuthorizationFailed, //ItemType: NSError
    ARTAuthorizationCancelled, //ItemType: nil
};

NS_ASSUME_NONNULL_BEGIN

@interface ARTAuthInternal : NSObject

@property (nullable, readonly) NSString *clientId;
@property (nullable, nonatomic, readonly) ARTTokenDetails *tokenDetails;

- (void)requestToken:(nullable ARTTokenParams *)tokenParams
         withOptions:(nullable ARTAuthOptions *)authOptions
            callback:(ARTTokenDetailsCallback)callback;

- (void)requestToken:(ARTTokenDetailsCallback)callback;

- (void)authorize:(nullable ARTTokenParams *)tokenParams
          options:(nullable ARTAuthOptions *)authOptions
         callback:(ARTTokenDetailsCallback)callback;

- (void)authorize:(ARTTokenDetailsCallback)callback;

- (void)createTokenRequest:(nullable ARTTokenParams *)tokenParams
                   options:(nullable ARTAuthOptions *)options
                  callback:(void (^)(ARTTokenRequest *_Nullable tokenRequest, NSError *_Nullable error))callback;

- (void)createTokenRequest:(void (^)(ARTTokenRequest *_Nullable tokenRequest, NSError *_Nullable error))callback;

/// Provides the implementation for `-[ARTPluginAPI nosync_fetchServerTimeForClient:completion:]`. See documentation for that method in `APPluginAPIProtocol`.
- (void)fetchServerTimeWithCompletion:(void (^ _Nullable)(NSDate *_Nullable serverTime, ARTErrorInfo *_Nullable error))completion;

@end

/// Messages related to the ARTAuth
@protocol ARTAuthDelegate <NSObject>
- (void)auth:(ARTAuthInternal *)auth didAuthorize:(ARTTokenDetails *)tokenDetails completion:(void (^)(ARTAuthorizationState, ARTErrorInfo *_Nullable))completion;
@end

@interface ARTAuthInternal ()

@property (readonly, nonatomic) dispatch_queue_t queue;

- (NSString *)clientId_nosync;

@property (nonatomic, readonly) ARTClientOptions *options;
@property (nonatomic, readonly) ARTAuthMethod method;
@property (readonly) BOOL isTokenAuth;

@property (nullable, nonatomic, readonly) NSNumber *timeOffset;

@property (nullable, weak) id<ARTAuthDelegate> delegate; // weak because delegates outlive their counterpart
@property (readonly) BOOL authorizing;
@property (readonly) BOOL authorizing_nosync;

- (nullable NSObject<ARTCancellable> *)_authorize:(nullable ARTTokenParams *)tokenParams
                                          options:(nullable ARTAuthOptions *)authOptions
                                         callback:(ARTTokenDetailsCallback)callback;

- (void)cancelAuthorization:(nullable ARTErrorInfo *)error;

- (nullable NSObject<ARTCancellable> *)_requestToken:(ARTTokenParams *_Nullable)tokenParams
                                         withOptions:(ARTAuthOptions *_Nullable)authOptions
                                            callback:(ARTTokenDetailsCallback)callback;

@end

@interface ARTAuthInternal (Private)

- (instancetype)init:(ARTHttpClientInternal *)rest withOptions:(ARTClientOptions *)options logger:(ARTInternalLog *)logger;

- (ARTAuthOptions *)mergeOptions:(ARTAuthOptions *)customOptions;
- (ARTTokenParams *)mergeParams:(ARTTokenParams *)customParams;

- (NSURL *)buildURL:(ARTAuthOptions *)options withParams:(ARTTokenParams *)params;
- (NSMutableURLRequest *)buildRequest:(nullable ARTAuthOptions *)options withParams:(nullable ARTTokenParams *)params;

// Execute the received ARTTokenRequest
- (nullable NSObject<ARTCancellable> *)executeTokenRequest:(ARTTokenRequest *)tokenRequest callback:(void (^)(ARTTokenDetails *_Nullable tokenDetails, NSError *_Nullable error))callback;

// CONNECTED ProtocolMessage may contain a clientId
- (void)setProtocolClientId:(NSString *)clientId;

// Discard the cached local clock offset
- (void)discardTimeOffset;

// Configured options does have a means to renew the token automatically.
- (BOOL)canRenewTokenAutomatically:(ARTAuthOptions *)options;

/// Does the client have a means to renew the token automatically.
- (BOOL)tokenIsRenewable;

/// Does the client have a valid token (i.e. not expired).
- (BOOL)tokenRemainsValid;

// Private TokenDetails setter for testing only
- (void)setTokenDetails:(nullable ARTTokenDetails *)tokenDetails;

// Private TimeOffset setter for testing only
- (void)setTimeOffset:(NSTimeInterval)offset;
- (void)clearTimeOffset;

- (NSString *_Nullable)clientId;

- (NSString *_Nullable)appId;

@end

@interface ARTAuth ()

@property (nonatomic, readonly) ARTAuthInternal *internal;

- (instancetype)initWithInternal:(ARTAuthInternal *)internal queuedDealloc:(ARTQueuedDealloc *)dealloc;
- (void)internalAsync:(void (^)(ARTAuthInternal *))use;

@end

NS_ASSUME_NONNULL_END
