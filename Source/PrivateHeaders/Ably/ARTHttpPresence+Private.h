#import <AblyPubSubDevice/ARTHttpPresence.h>
#import "ARTQueuedDealloc.h"

NS_ASSUME_NONNULL_BEGIN

@class ARTHttpChannelInternal;
@class ARTInternalLog;

@interface ARTHttpPresenceInternal : NSObject

- (instancetype)initWithChannel:(ARTHttpChannelInternal *)channel logger:(ARTInternalLog *)logger;

- (void)get:(ARTPaginatedPresenceCallback)callback;

- (void)get:(ARTPresenceQuery *)query callback:(ARTPaginatedPresenceCallback)callback;

- (void)history:(nullable ARTDataQuery *)query wrapperSDKAgents:(nullable NSStringDictionary *)wrapperSDKAgents callback:(ARTPaginatedPresenceCallback)callback;

- (void)historyWithWrapperSDKAgents:(nullable NSStringDictionary *)wrapperSDKAgents
                         completion:(ARTPaginatedPresenceCallback)callback;

@end

@interface ARTHttpPresence ()

@property (nonatomic, readonly) ARTHttpPresenceInternal *internal;

- (instancetype)initWithInternal:(ARTHttpPresenceInternal *)internal queuedDealloc:(ARTQueuedDealloc *)dealloc;

@end

NS_ASSUME_NONNULL_END
