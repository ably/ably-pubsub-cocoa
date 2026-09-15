#import <AblyPubSubDevice/ARTRealtimePresence.h>
#import "ARTRealtimeChannel+Private.h"

NS_ASSUME_NONNULL_BEGIN

@interface ARTRealtimePresenceInternal : NSObject

@property (nonatomic, readonly) NSString *connectionId;
@property (readonly, nonatomic) ARTEventEmitter<ARTEvent *, ARTPresenceMessage *> *eventEmitter;

- (instancetype)initWithChannel:(ARTRealtimeChannelInternal *)channel logger:(ARTInternalLog *)logger;
- (void)_unsubscribe;
- (BOOL)syncComplete_nosync;
- (BOOL)syncInProgress_nosync;

- (void)failPendingPresence:(ARTStatus *)status;
- (void)broadcast:(ARTPresenceMessage *)pm;

- (void)onMessage:(ARTProtocolMessage *)message;
- (void)onSync:(ARTProtocolMessage *)message;
- (void)onAttached:(ARTProtocolMessage *)message;

@property (nonatomic) dispatch_queue_t queue;
@property (readonly, nonatomic) NSMutableArray<ARTQueuedMessage *> *pendingPresence;

@property (readonly) BOOL syncComplete;

- (void)get:(ARTPresenceMessagesCallback)callback;

- (void)get:(ARTRealtimePresenceQuery *)query callback:(ARTPresenceMessagesCallback)callback;

- (void)enter:(id _Nullable)data;

- (void)enter:(id _Nullable)data callback:(nullable ARTCallback)callback;

- (void)update:(id _Nullable)data;

- (void)update:(id _Nullable)data callback:(nullable ARTCallback)callback;

- (void)leave:(id _Nullable)data;

- (void)leave:(id _Nullable)data callback:(nullable ARTCallback)callback;

- (void)enterClient:(NSString *)clientId data:(id _Nullable)data;

- (void)enterClient:(NSString *)clientId data:(id _Nullable)data callback:(nullable ARTCallback)callback;

- (void)updateClient:(NSString *)clientId data:(id _Nullable)data;

- (void)updateClient:(NSString *)clientId data:(id _Nullable)data callback:(nullable ARTCallback)callback;

- (void)leaveClient:(NSString *)clientId data:(id _Nullable)data;

- (void)leaveClient:(NSString *)clientId data:(id _Nullable)data callback:(nullable ARTCallback)callback;

- (ARTEventListener *_Nullable)subscribe:(ARTPresenceMessageCallback)callback;

- (ARTEventListener *_Nullable)subscribeWithAttachCallback:(nullable ARTCallback)onAttach callback:(ARTPresenceMessageCallback)callback;

- (ARTEventListener *_Nullable)subscribe:(ARTPresenceAction)action callback:(ARTPresenceMessageCallback)callback;

- (ARTEventListener *_Nullable)subscribe:(ARTPresenceAction)action onAttach:(nullable ARTCallback)onAttach callback:(ARTPresenceMessageCallback)callback;

- (void)unsubscribe;

- (void)unsubscribe:(ARTEventListener *)listener;

- (void)unsubscribe:(ARTPresenceAction)action listener:(ARTEventListener *)listener;

- (void)historyWithWrapperSDKAgents:(nullable NSStringDictionary *)wrapperSDKAgents
                         completion:(ARTPaginatedPresenceCallback)callback;

- (BOOL)history:(ARTRealtimeHistoryQuery *_Nullable)query wrapperSDKAgents:(nullable NSStringDictionary *)wrapperSDKAgents callback:(ARTPaginatedPresenceCallback)callback error:(NSError *_Nullable *_Nullable)errorPtr;

@end

@interface ARTRealtimePresence ()

@property (nonatomic, readonly) ARTRealtimePresenceInternal *internal;

- (instancetype)initWithInternal:(ARTRealtimePresenceInternal *)internal queuedDealloc:(ARTQueuedDealloc *)dealloc;

@end

@interface ARTRealtimePresenceInternal (PresenceMap)

/// List of members.
/// The key is the memberKey and the value is the latest relevant ARTPresenceMessage for that clientId.
@property (readonly, atomic) NSDictionary<NSString *, ARTPresenceMessage *> *members;

/// List of internal members.
/// The key is the clientId and the value is the latest relevant ARTPresenceMessage for that clientId.
@property (readonly, atomic) NSMutableDictionary<NSString *, ARTPresenceMessage *> *internalMembers;

@property (readonly, nonatomic) BOOL syncComplete;
@property (readonly, nonatomic) BOOL syncInProgress;

- (instancetype)init UNAVAILABLE_ATTRIBUTE;
- (instancetype)initWithQueue:(_Nonnull dispatch_queue_t)queue logger:(ARTInternalLog *)logger;

- (void)processMember:(ARTPresenceMessage *)message;
- (void)reset;

- (void)startSync;
- (void)endSync;
- (void)failsSync:(ARTErrorInfo *)error;

- (void)onceSyncEnds:(void (^)(NSArray<ARTPresenceMessage *> *))callback;
- (void)onceSyncFails:(ARTCallback)callback;

- (BOOL)addMember:(ARTPresenceMessage *)message;
- (void)addInternalMember:(ARTPresenceMessage *)message;

- (BOOL)removeMember:(ARTPresenceMessage *)message;
- (void)removeInternalMember:(ARTPresenceMessage *)message;

- (void)cleanUpAbsentMembers;

- (BOOL)member:(ARTPresenceMessage *)msg1 isNewerThan:(ARTPresenceMessage *)msg2 __attribute__((warn_unused_result));

@end

NS_ASSUME_NONNULL_END
