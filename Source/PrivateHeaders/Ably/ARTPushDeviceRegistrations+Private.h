#import <AblyPubSubDevice/ARTPushDeviceRegistrations.h>
#import "ARTQueuedDealloc.h"

@class ARTRestInternal;
@class ARTInternalLog;

NS_ASSUME_NONNULL_BEGIN

@interface ARTPushDeviceRegistrationsInternal : NSObject

- (instancetype)initWithRest:(ARTRestInternal *)rest logger:(ARTInternalLog *)logger;

- (void)save:(ARTDeviceDetails *)deviceDetails wrapperSDKAgents:(nullable NSStringDictionary *)wrapperSDKAgents callback:(ARTCallback)callback;

- (void)get:(ARTDeviceId *)deviceId wrapperSDKAgents:(nullable NSStringDictionary *)wrapperSDKAgents callback:(void (^)(ARTDeviceDetails *_Nullable,  ARTErrorInfo *_Nullable))callback;

- (void)list:(NSStringDictionary *)params wrapperSDKAgents:(nullable NSStringDictionary *)wrapperSDKAgents callback:(ARTPaginatedDeviceDetailsCallback)callback;

- (void)remove:(NSString *)deviceId wrapperSDKAgents:(nullable NSStringDictionary *)wrapperSDKAgents callback:(ARTCallback)callback;

- (void)removeWhere:(NSStringDictionary *)params wrapperSDKAgents:(nullable NSStringDictionary *)wrapperSDKAgents callback:(ARTCallback)callback;

@end

@interface ARTPushDeviceRegistrations ()

@property (nonatomic, readonly) ARTPushDeviceRegistrationsInternal *internal;

- (instancetype)initWithInternal:(ARTPushDeviceRegistrationsInternal *)internal queuedDealloc:(ARTQueuedDealloc *)dealloc;

@end

NS_ASSUME_NONNULL_END
