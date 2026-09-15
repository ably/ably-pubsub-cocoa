#import <AblyPubSubDevice/ARTRealtime.h>
#import <AblyPubSubDevice/ARTEventEmitter.h>
#import <AblyPubSubDevice/ARTTypes.h>
#import "ARTMessageSendStatus.h"
#import "ARTQueuedMessage.h"
#import "ARTPendingMessage.h"
#import "ARTProtocolMessage.h"
#import "ARTReachability.h"

#import "ARTRealtimeTransport.h"
#import "ARTAuth+Private.h"
#import "ARTRest+Private.h"

#ifdef ABLY_SUPPORTS_PLUGINS
@import _AblyPluginSupportPrivate;
#endif

@class ARTRestInternal;
@class ARTErrorInfo;
@class ARTProtocolMessage;
@class ARTConnectionInternal;
@class ARTRealtimeChannelsInternal;

NS_ASSUME_NONNULL_BEGIN

@interface ARTRealtime ()

@property (nonatomic, readonly) ARTRealtimeInternal *internal;

- (void)internalAsync:(void (^)(ARTRealtimeInternal *))use;
- (void)internalSync:(void (^)(ARTRealtimeInternal *))use;

@end

#ifdef ABLY_SUPPORTS_PLUGINS
@interface ARTRealtimeInternal : NSObject <APRealtimeClient>
#else
@interface ARTRealtimeInternal : NSObject
#endif

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithOptions:(ARTClientOptions *)options;
- (instancetype)initWithKey:(NSString *)key;
- (instancetype)initWithToken:(NSString *)token;

@property (nonatomic, readonly) ARTConnectionInternal *connection;
@property (nonatomic, readonly) ARTRealtimeChannelsInternal *channels;
@property (readonly) ARTAuthInternal *auth;
@property (readonly) ARTPushInternal *push;
#if TARGET_OS_IOS
@property (nonnull, nonatomic, readonly, getter=device) ARTLocalDevice *device;
#endif
@property (readonly, nullable, getter=clientId) NSString *clientId;

@property (readonly, nonatomic) dispatch_queue_t queue;

/// The `connectionDetails` from the latest `CONNECTED` `ProtocolMessage` that we received (`nil` if it did not contain a `connectionDetails`).
///
/// Provides the implementation for `-[ARTPluginAPI nosync_latestConnectionDetailsForClient:]`. See documentation for that method in `APPluginAPIProtocol`.
@property (nullable, readonly, nonatomic) ARTConnectionDetails *latestConnectionDetails;

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

- (void)ping:(ARTCallback)cb;

- (BOOL)statsWithWrapperSDKAgents:(nullable NSStringDictionary *)wrapperSDKAgents
                         callback:(ARTPaginatedStatsCallback)callback;

- (BOOL)stats:(nullable ARTStatsQuery *)query wrapperSDKAgents:(nullable NSStringDictionary *)wrapperSDKAgents callback:(ARTPaginatedStatsCallback)callback error:(NSError *_Nullable *_Nullable)errorPtr;

- (void)connect;

- (void)close;

@end

@interface ARTRealtimeInternal () <ARTRealtimeTransportDelegate, ARTAuthDelegate>

@property (readonly, nonatomic) ARTEventEmitter<ARTEvent *, ARTConnectionStateChange *> *internalEventEmitter;
@property (readonly, nonatomic) ARTEventEmitter<ARTEvent *, NSNull *> *connectedEventEmitter;

@property (readonly, nonatomic) NSMutableArray<void (^)(ARTRealtimeConnectionState, ARTErrorInfo *_Nullable)> *pendingAuthorizations;

// State properties
- (BOOL)shouldSendEvents;

// Message sending
- (void)sendQueuedMessages;
- (void)failQueuedMessages:(ARTStatus *)error;

@end

/// ARTRealtimeInternal private methods that are used for internal testing.
@interface ARTRealtimeInternal ()

@property (readwrite, nonatomic) ARTRestInternal *rest;
@property (readonly, nullable) id<ARTRealtimeTransport> transport;
@property (readonly, nonatomic, nonnull) id<ARTReachability> reachability;
@property (nonatomic) NSTimeInterval connectionStateTtl;
@property (nonatomic) NSTimeInterval maxIdleInterval;

/// Current protocol `msgSerial`. Starts at zero.
@property (readwrite, nonatomic) int64_t msgSerial;

/// List of queued messages on a connection in the disconnected or connecting states.
@property (readwrite, nonatomic) NSMutableArray<ARTQueuedMessage *> *queuedMessages;

/// List of pending messages waiting for ACK/NACK action to confirm the success receipt and acceptance.
@property (readwrite, nonatomic) NSMutableArray<ARTPendingMessage *> *pendingMessages;

/// First `msgSerial` pending message.
@property (readwrite, nonatomic) int64_t pendingMessageStartSerial;

/// Client is trying to resume the last connection
@property (readwrite, nonatomic) BOOL resuming;

@property (readonly, getter=getClientOptions) ARTClientOptions *options;

/// Alter the behavior defined in RTN15a, that is trying to immediately reconnect after a disconnection
@property (readwrite, nonatomic) NSTimeInterval immediateReconnectionDelay;

@end

@interface ARTRealtimeInternal (Private)

- (BOOL)isActive;

// Transport Events
- (void)onHeartbeat;
- (void)onConnected:(ARTProtocolMessage *)message;
- (void)onDisconnected;
- (void)onClosed;
- (void)onSuspended;
- (void)onError:(ARTProtocolMessage *)message;
- (void)onAck:(ARTProtocolMessage *)message;
- (void)onNack:(ARTProtocolMessage *)message;
- (void)onChannelMessage:(ARTProtocolMessage *)message;

- (void)setReachabilityClass:(Class _Nullable)reachabilityClass;
- (void)transportReconnectWithExistingParameters;

// Message sending

/// Submits a `ProtocolMessage` for delivery to Ably, with possible queueing and retries.
///
/// Note that this method is used internally for various kinds of messages: those that do not require an `ACK` (e.g. `ATTACH`), which should only be sent when they can be sent immediately, and those which require an `ACK` (e.g. `MESSAGE`), which can be queued to be sent later. In the case of messages that require an `ACK`, it implements the connection behaviour described in RTL6c (the RTL6c channel state checks must be performed separately by the channel).
///
/// It behaves as follows:
///
/// - If the connection can send the message immediately, it will be sent immediately.
/// - If the connection cannot send the message immediately, then the behaviour depends on whether the message has an `action` that expects to receive an `ACK` from Ably:
///    - If the message expects an `ACK`, then this method follows the channel message publishing behaviour described in RTL6c:
///      - If the connection can queue the message to be sent later, then it will accept the message per RTL6c2.
///      - If the connection cannot queue the message (due to some combination of connection state and the `queueMessages` client option), then the callbacks will be immediately called with an error per RTL6c4.
///    - If the message does not expect an `ACK`, then the message will be silently dropped (i.e. it is the responsibility of callers to not submit messages to the connection in this scenario).
- (void)send:(ARTProtocolMessage *)msg sentCallback:(nullable ARTCallback)sentCallback ackCallback:(nullable ARTMessageSendCallback)ackCallback;

- (void)send:(ARTProtocolMessage *)msg reuseMsgSerial:(BOOL)reuseMsgSerial sentCallback:(nullable ARTCallback)sentCallback ackCallback:(nullable ARTMessageSendCallback)ackCallback;

@end

NS_ASSUME_NONNULL_END
