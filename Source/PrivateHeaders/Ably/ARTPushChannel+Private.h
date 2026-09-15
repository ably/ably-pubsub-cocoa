#import <AblyPubSubDevice/ARTPushChannel.h>
#import "ARTQueuedDealloc.h"

@class ARTChannel;
@class ARTRestInternal;
@class ARTInternalLog;

NS_ASSUME_NONNULL_BEGIN

@interface ARTPushChannelInternal : NSObject

- (instancetype)init:(ARTRestInternal *)rest withChannel:(ARTChannel *)channel logger:(ARTInternalLog *)logger;

- (void)subscribeDeviceWithWrapperSDKAgents:(nullable NSStringDictionary *)wrapperSDKAgents;

- (void)subscribeDeviceWithWrapperSDKAgents:(nullable NSStringDictionary *)wrapperSDKAgents
                                 completion:(nullable ARTCallback)callback;

- (void)subscribeClientWithWrapperSDKAgents:(nullable NSStringDictionary *)wrapperSDKAgents;

- (void)subscribeClientWithWrapperSDKAgents:(nullable NSStringDictionary *)wrapperSDKAgents
                                 completion:(nullable ARTCallback)callback;

- (void)unsubscribeDeviceWithWrapperSDKAgents:(nullable NSStringDictionary *)wrapperSDKAgents;

- (void)unsubscribeDeviceWithWrapperSDKAgents:(nullable NSStringDictionary *)wrapperSDKAgents
                                   completion:(nullable ARTCallback)callback;

- (void)unsubscribeClientWithWrapperSDKAgents:(nullable NSStringDictionary *)wrapperSDKAgents;

- (void)unsubscribeClientWithWrapperSDKAgents:(nullable NSStringDictionary *)wrapperSDKAgents
                                   completion:(nullable ARTCallback)callback;

- (BOOL)listSubscriptions:(NSStringDictionary *)params
         wrapperSDKAgents:(nullable NSStringDictionary *)wrapperSDKAgents
                 callback:(ARTPaginatedPushChannelCallback)callback
                    error:(NSError *_Nullable *_Nullable)errorPtr;

@end

@interface ARTPushChannel ()

@property (nonatomic, readonly) ARTPushChannelInternal *internal;

- (instancetype)initWithInternal:(ARTPushChannelInternal *)internal queuedDealloc:(ARTQueuedDealloc *)dealloc;

@end

NS_ASSUME_NONNULL_END
