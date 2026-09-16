//
//  ARTRealtimeChannel+Private.h
//
//

#import "ARTChannel.h"
#import "ARTHttpChannel+Private.h"
#import <AblyPubSubDevice/ARTRealtimeChannel.h>
#import <AblyPubSubDevice/ARTEventEmitter.h>
#import "ARTMessageSendStatus.h"
#import "ARTRealtime+Private.h"
#import "ARTQueuedDealloc.h"
#import "ARTPushChannel+Private.h"

#ifdef ABLY_SUPPORTS_PLUGINS
@import _AblyPluginSupportPrivate;
#endif

@class ARTProtocolMessage;
@class ARTPublishResult;
@class ARTRealtimePresenceInternal;
@class ARTRealtimeAnnotationsInternal;
@class ARTChannelStateChangeParams;
@class ARTAttachRequestParams;

NS_ASSUME_NONNULL_BEGIN

#ifdef ABLY_SUPPORTS_PLUGINS
@interface ARTRealtimeChannel () <APPublicRealtimeChannel>
@end
#endif

#ifdef ABLY_SUPPORTS_PLUGINS
@interface ARTRealtimeChannelInternal : ARTChannel <APRealtimeChannel>
#else
@interface ARTRealtimeChannelInternal : ARTChannel
#endif

@property (readonly) ARTRealtimePresenceInternal *presence;
@property (readonly) ARTRealtimeAnnotationsInternal *annotations;

#if TARGET_OS_IPHONE
@property (readonly) ARTPushChannelInternal *push;
#endif

@property (readwrite, nonatomic) ARTRealtimeChannelState state;
@property (readwrite, nonatomic) ARTChannelMode modes;
@property (readonly, nonatomic, nullable) ARTErrorInfo *errorReason;
@property (readonly, nullable, getter=getOptions_nosync) ARTRealtimeChannelOptions *options_nosync;
@property (nonatomic, readonly) NSString *connectionId;

- (ARTRealtimeChannelState)state_nosync;
- (ARTChannelMode)modes_nosync;
- (ARTErrorInfo *)errorReason_nosync;
- (NSString * _Nullable)clientId_nosync;
- (ARTChannelProperties *)properties_nosync;
- (BOOL)canBeReattached;
- (BOOL)shouldAttach;
- (BOOL)isAnnotationSubscribeGranted;

@property (readonly, weak, nonatomic) ARTRealtimeInternal *realtime; // weak because realtime owns self
@property (readonly, nonatomic) ARTHttpChannelInternal *restChannel;
@property (readwrite, nonatomic, nullable) NSString *attachSerial;
@property (readwrite, nonatomic, nullable) NSString *channelSerial; // CP2b
@property (readonly, nullable, getter=getClientId) NSString *clientId;
@property (readonly, nonatomic) ARTEventEmitter<ARTEvent *, ARTChannelStateChange *> *internalEventEmitter;
@property (readonly, nonatomic) ARTEventEmitter<ARTEvent *, ARTChannelStateChange *> *statesEventEmitter;
@property (readonly, nonatomic) ARTEventEmitter<id<ARTEventIdentification>, ARTMessage *> *messagesEventEmitter;

@property (readwrite, nonatomic) BOOL attachResume;

- (instancetype)initWithRealtime:(ARTRealtimeInternal *)realtime andName:(NSString *)name withOptions:(ARTRealtimeChannelOptions *)options logger:(ARTInternalLog *)logger;

- (void)proceedAttachDetachWithParams:(ARTAttachRequestParams *)params;

- (void)_attach:(nullable ARTCallback)callback;
- (void)_detach:(nullable ARTCallback)callback;

- (void)_unsubscribe;
- (void)off_nosync;

@property (nonatomic) dispatch_queue_t queue;

@property (readonly) ARTChannelProperties *properties;

@property (readonly, nullable, getter=getOptions) ARTRealtimeChannelOptions *options;

- (void)attach;

- (void)attach:(nullable ARTCallback)callback;

- (void)detach;

- (void)detach:(nullable ARTCallback)callback;

- (ARTEventListener *_Nullable)subscribe:(ARTMessageCallback)callback;

- (ARTEventListener *_Nullable)subscribeWithAttachCallback:(nullable ARTCallback)onAttach callback:(ARTMessageCallback)callback;

- (ARTEventListener *_Nullable)subscribe:(NSString *)name callback:(ARTMessageCallback)callback;

- (ARTEventListener *_Nullable)subscribe:(NSString *)name onAttach:(nullable ARTCallback)onAttach callback:(ARTMessageCallback)callback;

- (void)unsubscribe;

- (void)unsubscribe:(ARTEventListener *_Nullable)listener;

- (void)unsubscribe:(NSString *)name listener:(ARTEventListener *_Nullable)listener;

- (void)historyWithWrapperSDKAgents:(nullable NSStringDictionary *)wrapperSDKAgents
                         completion:(ARTPaginatedMessagesCallback)callback;
- (BOOL)history:(ARTRealtimeHistoryQuery *_Nullable)query wrapperSDKAgents:(nullable NSStringDictionary *)wrapperSDKAgents callback:(ARTPaginatedMessagesCallback)callback error:(NSError *_Nullable *_Nullable)errorPtr;

- (void)setOptions:(ARTRealtimeChannelOptions *_Nullable)options callback:(nullable ARTCallback)callback;

#pragma mark ARTEventEmitter

ART_EMBED_INTERFACE_EVENT_EMITTER(ARTChannelEvent, ARTChannelStateChange *)

@end

@interface ARTRealtimeChannelInternal (Private)

- (void)performTransitionToState:(ARTRealtimeChannelState)state withParams:(ARTChannelStateChangeParams *)params;

- (void)onChannelMessage:(ARTProtocolMessage *)message;

/// Attempts to submit a channel message for best-effort delivery to Ably.
///
/// This enables the channel message publishing behaviour described in RTL6c:
///
/// - If the channel's state is neither SUSPENDED nor FAILED then the message will be submitted to the connection for further checks per RTL6c1 and RTL6c2. Note that these checks may cause the connection to immediately reject the message per RTL6c4.
/// - If the channel's state is SUSPENDED or FAILED then the callback will be called immediately with an error per RTL6c4.
- (void)publishProtocolMessage:(ARTProtocolMessage *)pm callback:(ARTMessageSendCallback)cb;

- (void)setAttached:(ARTProtocolMessage *)message;
- (void)setDetached:(ARTProtocolMessage *)message;

- (void)onMessage:(ARTProtocolMessage *)message;
- (void)onPresence:(ARTProtocolMessage *)message;
- (void)onSync:(ARTProtocolMessage *)message;
- (void)onError:(ARTProtocolMessage *)error;

- (void)setSuspended:(ARTChannelStateChangeParams *)params;
- (void)setFailed:(ARTChannelStateChangeParams *)params;

- (void)detachChannel:(ARTChannelStateChangeParams *)params;

- (void)emit:(ARTChannelEvent)event with:(ARTChannelStateChange *)data;

// MARK: - Plugins

/// Provides the implementation for `-[ARTPluginAPI setPluginDataValue:forKey:channel]`. See documentation for that method in `APPluginAPIProtocol`.
- (void)setPluginDataValue:(id)value forKey:(NSString *)key;
/// Provides the implementation for `-[ARTPluginAPI pluginDataValueForKey:channel]`. See documentation for that method in `APPluginAPIProtocol`.
- (nullable id)pluginDataValueForKey:(NSString *)key;

#ifdef ABLY_SUPPORTS_PLUGINS
/// Provides the implementation for `-[ARTPluginAPI sendObjectWithObjectMessages:completion:]`. See documentation for that method in `APPluginAPIProtocol`.
- (void)sendObjectWithObjectMessages:(NSArray<id<APObjectMessageProtocol>> *)objectMessages
                          completion:(void (^)(ARTPublishResult *_Nullable publishResult, ARTErrorInfo *_Nullable error))completion;
#endif

@end

@interface ARTRealtimeChannel ()

@property (nonatomic, readonly) ARTRealtimeChannelInternal *internal;
@property (nonatomic, readonly) ARTRealtimeInternal *realtimeInternal;

- (void)internalAsync:(void (^)(ARTRealtimeChannelInternal *))use;
- (void)internalSync:(void (^)(ARTRealtimeChannelInternal *))use;

- (instancetype)initWithInternal:(ARTRealtimeChannelInternal *)internal realtimeInternal:(ARTRealtimeInternal *)realtimeInternal queuedDealloc:(ARTQueuedDealloc *)dealloc;

@end

NS_ASSUME_NONNULL_END
