//
//  ARTHttpChannel+Private.h
//
//

#import "ARTChannel.h"
#import <AblyPubSubDevice/ARTHttpChannel.h>
#import "ARTHttpPresence+Private.h"
#import "ARTPushChannel+Private.h"
#import "ARTQueuedDealloc.h"

NS_ASSUME_NONNULL_BEGIN

@class ARTHttpClientInternal;
@class ARTHttpAnnotationsInternal;
@class ARTInternalLog;

@interface ARTHttpChannelInternal : ARTChannel

@property (readonly) ARTHttpPresenceInternal *presence;
@property (readonly) ARTHttpAnnotationsInternal *annotations;
@property (readonly) ARTPushChannelInternal *push;

- (instancetype)initWithName:(NSString *)name withOptions:(ARTChannelOptions *)options andRest:(ARTHttpClientInternal *)rest logger:(ARTInternalLog *)logger;

@property (nonatomic, weak) ARTHttpClientInternal *rest; // weak because rest owns self
@property (nonatomic) dispatch_queue_t queue;

@property (readonly, nullable) ARTChannelOptions *options;

- (BOOL)history:(nullable ARTDataQuery *)query wrapperSDKAgents:(nullable NSStringDictionary *)wrapperSDKAgents callback:(ARTPaginatedMessagesCallback)callback error:(NSError *_Nullable *_Nullable)errorPtr;

- (void)status:(ARTChannelDetailsCallback)callback;

- (void)setOptions:(ARTChannelOptions *_Nullable)options;

@end

@interface ARTHttpChannelInternal (Private)

@property (readonly, getter=getBasePath) NSString *basePath;

@end

@interface ARTHttpChannel ()

@property (nonatomic, readonly) ARTHttpChannelInternal *internal;

- (instancetype)initWithInternal:(ARTHttpChannelInternal *)internal queuedDealloc:(ARTQueuedDealloc *)dealloc;

NS_ASSUME_NONNULL_END

@end
