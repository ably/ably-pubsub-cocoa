#import <AblyPubSubDevice/ARTPushAdmin.h>
#import "ARTPushDeviceRegistrations+Private.h"
#import "ARTPushChannelSubscriptions+Private.h"
#import "ARTQueuedDealloc.h"

@class ARTRestInternal;

NS_ASSUME_NONNULL_BEGIN

@interface ARTPushAdminInternal : NSObject

@property (nonatomic, readonly) ARTPushDeviceRegistrationsInternal *deviceRegistrations;
@property (nonatomic, readonly) ARTPushChannelSubscriptionsInternal *channelSubscriptions;

- (instancetype)initWithRest:(ARTRestInternal *)rest logger:(ARTInternalLog *)logger;

- (void)publish:(ARTPushRecipient *)recipient data:(ARTJsonObject *)data wrapperSDKAgents:(nullable NSStringDictionary *)wrapperSDKAgents callback:(nullable ARTCallback)callback;

@end

@interface ARTPushAdmin ()

@property (nonatomic, readonly) ARTPushAdminInternal *internal;

- (instancetype)initWithInternal:(ARTPushAdminInternal *)internal queuedDealloc:(ARTQueuedDealloc *)dealloc;

@end

NS_ASSUME_NONNULL_END
