#import <Foundation/Foundation.h>

#import <AblyPubSubDevice/ARTStatus.h>
#import <AblyPubSubDevice/ARTEventEmitter.h>

@class ARTStatus;
@class ARTHttpResponse;
@class ARTErrorInfo;
@class ARTMessage;
@class ARTAnnotation;
@class ARTPresenceMessage;
@class ARTTokenParams;
@class ARTTokenRequest;
@class ARTTokenDetails;
@class ARTHTTPPaginatedResponse;
@class ARTPaginatedResult<ItemType>;
@class ARTStats;
@class ARTPushChannelSubscription;
@class ARTDeviceDetails;
@class ARTUpdateDeleteResult;
@class ARTPublishResult;
@protocol ARTTokenDetailsCompatible;

/// :nodoc:
typedef NSDictionary<NSString *, id> ARTJsonObject;

/// :nodoc:
typedef NSString ARTDeviceId;

/// :nodoc:
typedef NSString ARTDeviceSecret;

/// :nodoc:
typedef NSData ARTDeviceToken;

/// :nodoc:
typedef ARTJsonObject ARTPushRecipient;

/// :nodoc:
NS_SWIFT_SENDABLE
typedef NS_ENUM(NSUInteger, ARTAuthentication) {
    ARTAuthenticationOff,
    ARTAuthenticationOn,
    ARTAuthenticationUseBasic,
    ARTAuthenticationNewToken,
    ARTAuthenticationTokenRetry
};

/// :nodoc:
NS_SWIFT_SENDABLE
typedef NS_ENUM(NSUInteger, ARTAuthMethod) {
    ARTAuthMethodBasic,
    ARTAuthMethodToken
};

/**
 * Describes the realtime `ARTConnection` object states.
 */
NS_SWIFT_SENDABLE
typedef NS_ENUM(NSUInteger, ARTRealtimeConnectionState) {
    /**
         * A connection with this state has been initialized but no connection has yet been attempted.
         */
    ARTRealtimeInitialized,
    /**
         * A connection attempt has been initiated. The connecting state is entered as soon as the library has completed initialization, and is reentered each time connection is re-attempted following disconnection.
         */
    ARTRealtimeConnecting,
    /**
         * A connection exists and is active.
         */
    ARTRealtimeConnected,
    /**
         * A temporary failure condition. No current connection exists because there is no network connectivity or no host is available. The disconnected state is entered if an established connection is dropped, or if a connection attempt was unsuccessful. In the disconnected state the library will periodically attempt to open a new connection (approximately every 15 seconds), anticipating that the connection will be re-established soon and thus connection and channel continuity will be possible. In this state, developers can continue to publish messages as they are automatically placed in a local queue, to be sent as soon as a connection is reestablished. Messages published by other clients while this client is disconnected will be delivered to it upon reconnection, so long as the connection was resumed within 2 minutes. After 2 minutes have elapsed, recovery is no longer possible and the connection will move to the `ARTRealtimeSuspended` state.
         */
    ARTRealtimeDisconnected,
    /**
         * A long term failure condition. No current connection exists because there is no network connectivity or no host is available. The suspended state is entered after a failed connection attempt if there has then been no connection for a period of two minutes. In the suspended state, the library will periodically attempt to open a new connection every 30 seconds. Developers are unable to publish messages in this state. A new connection attempt can also be triggered by an explicit call to `-[ARTConnectionProtocol connect]`. Once the connection has been re-established, channels will be automatically re-attached. The client has been disconnected for too long for them to resume from where they left off, so if it wants to catch up on messages published by other clients while it was disconnected, it needs to use the [History API](https://ably.com/docs/realtime/history).
         */
    ARTRealtimeSuspended,
    /**
         * An explicit request by the developer to close the connection has been sent to the Ably service. If a reply is not received from Ably within a short period of time, the connection is forcibly terminated and the connection state becomes `ARTRealtimeClosed`.
         */
    ARTRealtimeClosing,
    /**
         * The connection has been explicitly closed by the client. In the closed state, no reconnection attempts are made automatically by the library, and clients may not publish messages. No connection state is preserved by the service or by the library. A new connection attempt can be triggered by an explicit call to `-[ARTConnectionProtocol connect]`, which results in a new connection.
         */
    ARTRealtimeClosed,
    /**
         * This state is entered if the client library encounters a failure condition that it cannot recover from. This may be a fatal connection error received from the Ably service, for example an attempt to connect with an incorrect API key, or a local terminal error, for example the token in use has expired and the library does not have any way to renew it. In the failed state, no reconnection attempts are made automatically by the library, and clients may not publish messages. A new connection attempt can be triggered by an explicit call to `-[ARTConnectionProtocol connect]`.
         */
    ARTRealtimeFailed
};

/// :nodoc:
NSString *_Nonnull ARTRealtimeConnectionStateToStr(ARTRealtimeConnectionState state);

/**
 * Describes the events emitted by a `ARTConnection` object. An event is either an `ARTRealtimeConnectionEventUpdate` or an `ARTRealtimeConnectionState`.
 */
NS_SWIFT_SENDABLE
typedef NS_ENUM(NSUInteger, ARTRealtimeConnectionEvent) {
    ARTRealtimeConnectionEventInitialized,
    ARTRealtimeConnectionEventConnecting,
    ARTRealtimeConnectionEventConnected,
    ARTRealtimeConnectionEventDisconnected,
    ARTRealtimeConnectionEventSuspended,
    ARTRealtimeConnectionEventClosing,
    ARTRealtimeConnectionEventClosed,
    ARTRealtimeConnectionEventFailed,
    /**
         * An event for changes to connection conditions for which the `ARTRealtimeConnectionState` does not change.
         */
    ARTRealtimeConnectionEventUpdate
};

/// :nodoc:
NSString *_Nonnull ARTRealtimeConnectionEventToStr(ARTRealtimeConnectionEvent event);

/**
 * Describes the possible states of an `ARTRealtimeChannel` object.
 */
NS_SWIFT_SENDABLE
typedef NS_ENUM(NSUInteger, ARTRealtimeChannelState) {
    /**
         * The channel has been initialized but no attach has yet been attempted.
         */
    ARTRealtimeChannelInitialized,
    /**
         * An attach has been initiated by sending a request to Ably. This is a transient state, followed either by a transition to `ARTRealtimeChannelAttached`, `ARTRealtimeChannelSuspended`, or `ARTRealtimeChannelFailed`.
         */
    ARTRealtimeChannelAttaching,
    /**
         * The attach has succeeded. In the attached state a client may publish and subscribe to messages, or be present on the channel.
         */
    ARTRealtimeChannelAttached,
    /**
         * A detach has been initiated on an `ARTRealtimeChannelAttached` channel by sending a request to Ably. This is a transient state, followed either by a transition to `ARTRealtimeChannelDetached` or `ARTRealtimeChannelFailed`.
         */
    ARTRealtimeChannelDetaching,
    /**
         * The channel, having previously been `ARTRealtimeChannelAttached`, has been detached by the user.
         */
    ARTRealtimeChannelDetached,
    /**
         * The channel, having previously been `ARTRealtimeChannelAttached`, has lost continuity, usually due to the client being disconnected from Ably for longer than two minutes. It will automatically attempt to reattach as soon as connectivity is restored.
         */
    ARTRealtimeChannelSuspended,
    /**
         * An indefinite failure condition. This state is entered if a channel error has been received from the Ably service, such as an attempt to attach without the necessary access rights.
         */
    ARTRealtimeChannelFailed
};

/// :nodoc:
NSString *_Nonnull ARTRealtimeChannelStateToStr(ARTRealtimeChannelState state);

/**
 * Describes the events emitted by an `ARTRealtimeChannel` object. An event is either an `ARTChannelEventUpdate` or a `ARTRealtimeChannelState`.
 */
NS_SWIFT_SENDABLE
typedef NS_ENUM(NSUInteger, ARTChannelEvent) {
    ARTChannelEventInitialized,
    ARTChannelEventAttaching,
    ARTChannelEventAttached,
    ARTChannelEventDetaching,
    ARTChannelEventDetached,
    ARTChannelEventSuspended,
    ARTChannelEventFailed,
    /**
         * An event for changes to channel conditions that do not result in a change in `ARTRealtimeChannelState`.
         */
    ARTChannelEventUpdate
};

/// :nodoc:
NSString *_Nonnull ARTChannelEventToStr(ARTChannelEvent event);


/// :nodoc:
NS_SWIFT_SENDABLE
typedef NS_ENUM(NSInteger, ARTDataQueryError) {
    ARTDataQueryErrorLimit = 1,
    ARTDataQueryErrorTimestampRange = 2,
    ARTDataQueryErrorMissingRequiredFields = 3,
    ARTDataQueryErrorInvalidParameters = 4,
    ARTDataQueryErrorDeviceInactive = 5,
};

/// :nodoc:
NS_SWIFT_SENDABLE
typedef NS_ENUM(NSInteger, ARTRealtimeHistoryError) {
    ARTRealtimeHistoryErrorNotAttached = ARTDataQueryErrorTimestampRange + 1
};

/// :nodoc:
NS_SWIFT_SENDABLE
typedef NS_ENUM(NSInteger, ARTCustomRequestError) {
    ARTCustomRequestErrorInvalidMethod = 1,
    ARTCustomRequestErrorInvalidBody = 2,
    ARTCustomRequestErrorInvalidPath = 3,
};

NS_ASSUME_NONNULL_BEGIN

/// :nodoc:
/// Decompose API key
NSArray<NSString *> *decomposeKey(NSString *key);

/// :nodoc:
NSString *encodeBase64(NSString *value);

/// :nodoc:
NSString *decodeBase64(NSString *base64);

/// :nodoc:
uint64_t dateToMilliseconds(NSDate *date);

/// :nodoc:
uint64_t timeIntervalToMilliseconds(NSTimeInterval seconds);

/// :nodoc:
NSTimeInterval millisecondsToTimeInterval(uint64_t msecs);

/// :nodoc:
NSString *generateNonce(void);

/// :nodoc:
@protocol ARTCancellable
- (void)cancel;
@end

/**
 * Contains `ARTRealtimeConnectionState` change information emitted by the `ARTConnection` object.
 */
NS_SWIFT_SENDABLE
@interface ARTConnectionStateChange : NSObject

/// :nodoc:
- (instancetype)initWithCurrent:(ARTRealtimeConnectionState)current
                       previous:(ARTRealtimeConnectionState)previous
                          event:(ARTRealtimeConnectionEvent)event
                         reason:(ARTErrorInfo *_Nullable)reason;

/// :nodoc:
- (instancetype)initWithCurrent:(ARTRealtimeConnectionState)current
                       previous:(ARTRealtimeConnectionState)previous
                          event:(ARTRealtimeConnectionEvent)event
                         reason:(ARTErrorInfo *_Nullable)reason
                        retryIn:(NSTimeInterval)retryIn;

/**
 * The new `ARTRealtimeConnectionState`.
 */
@property (readonly, nonatomic) ARTRealtimeConnectionState current;
/**
 * The previous `ARTRealtimeConnectionState`. For the `ARTRealtimeConnectionEvent.ARTRealtimeConnectionEventUpdate` event, this is equal to the `current` state.
 */
@property (readonly, nonatomic) ARTRealtimeConnectionState previous;
/**
 * The event that triggered this `ARTRealtimeConnectionState` change.
 */
@property (readonly, nonatomic) ARTRealtimeConnectionEvent event;

/**
 * An `ARTErrorInfo` object containing any information relating to the transition.
 */
@property (readonly, nonatomic, nullable) ARTErrorInfo *reason;

/**
 * Duration in milliseconds, after which the client retries a connection where applicable.
 */
@property (readonly, nonatomic) NSTimeInterval retryIn;

@end

/**
 * Contains state change information emitted by an `ARTRealtimeChannel` object.
 */
NS_SWIFT_SENDABLE
@interface ARTChannelStateChange : NSObject

/// :nodoc:
- (instancetype)initWithCurrent:(ARTRealtimeChannelState)current
                       previous:(ARTRealtimeChannelState)previous
                          event:(ARTChannelEvent)event
                         reason:(ARTErrorInfo *_Nullable)reason;

/// :nodoc:
- (instancetype)initWithCurrent:(ARTRealtimeChannelState)current
                       previous:(ARTRealtimeChannelState)previous
                          event:(ARTChannelEvent)event
                         reason:(ARTErrorInfo *_Nullable)reason
                        resumed:(BOOL)resumed;

/**
 * The new current `ARTRealtimeChannelState`.
 */
@property (readonly, nonatomic) ARTRealtimeChannelState current;

/**
 * The previous state. For the `ARTChannelEvent.ARTChannelEventUpdate` event, this is equal to the `current` state.
 */
@property (readonly, nonatomic) ARTRealtimeChannelState previous;

/**
 * The event that triggered this `ARTRealtimeChannelState` change.
 */
@property (readonly, nonatomic) ARTChannelEvent event;

/**
 * An `ARTErrorInfo` object containing any information relating to the transition.
 */
@property (readonly, nonatomic, nullable) ARTErrorInfo *reason;

/**
 * Indicates whether message continuity on this channel is preserved, see [Nonfatal channel errors](https://ably.com/docs/realtime/channels#nonfatal-errors) for more info.
 */
@property (readonly, nonatomic) BOOL resumed;

@end

/**
 * Contains the metrics associated with a `ARTRestChannel` or `ARTRealtimeChannel`, such as the number of publishers, subscribers and connections it has.
 */
NS_SWIFT_SENDABLE
@interface ARTChannelMetrics : NSObject

/**
 * The number of realtime connections attached to the channel.
 */
@property (nonatomic, readonly) NSInteger connections;

/**
 * The number of realtime attachments permitted to publish messages to the channel. This requires the `publish` capability and for a client to not have specified a `ARTChannelMode` flag that excludes `ARTChannelMode.ARTChannelModePublish`.
 */
@property (nonatomic, readonly) NSInteger publishers;

/**
 * The number of realtime attachments receiving messages on the channel. This requires the `subscribe` capability and for a client to not have specified a `ARTChannelMode` flag that excludes `ARTChannelMode.ARTChannelModeSubscribe`.
 */
@property (nonatomic, readonly) NSInteger subscribers;

/**
 * The number of realtime connections attached to the channel with permission to enter the presence set, regardless of whether or not they have entered it. This requires the `presence` capability and for a client to not have specified a `ARTChannelMode` flag that excludes `ARTChannelMode.ARTChannelModePresence`.
 */
@property (nonatomic, readonly) NSInteger presenceConnections;

/**
 * The number of members in the presence set of the channel.
 */
@property (nonatomic, readonly) NSInteger presenceMembers;

/**
 * The number of realtime attachments receiving presence messages on the channel. This requires the `subscribe` capability and for a client to not have specified a `ARTChannelMode` flag that excludes `ARTChannelMode.ARTChannelModePresenceSubscribe`.
 */
@property (nonatomic, readonly) NSInteger presenceSubscribers;

/**
 * The number of realtime attachments permitted to publish object messages to the channel. This requires the `object-publish` capability and for a client to have specified an `ARTChannelMode` flag that includes `ARTChannelMode.ARTChannelModeObjectPublish`.
 */
@property (nonatomic, readonly) NSInteger objectPublishers;

/**
 * The number of realtime attachments receiving object messages on the channel. This requires the `object-subscribe` capability and for a client to have specified an `ARTChannelMode` flag that includes `ARTChannelMode.ARTChannelModeObjectSubscribe`.
 */
@property (nonatomic, readonly) NSInteger objectSubscribers;

/// :nodoc:
- (instancetype)initWithConnections:(NSInteger)connections
                         publishers:(NSInteger)publishers
                        subscribers:(NSInteger)subscribers
                presenceConnections:(NSInteger)presenceConnections
                    presenceMembers:(NSInteger)presenceMembers
                presenceSubscribers:(NSInteger)presenceSubscribers
                   objectPublishers:(NSInteger)objectPublishers
                  objectSubscribers:(NSInteger)objectSubscribers;

@end

/**
 * Contains the metrics of a `ARTRestChannel` or `ARTRealtimeChannel` object.
 */
NS_SWIFT_SENDABLE
@interface ARTChannelOccupancy : NSObject

/**
 * A `ARTChannelMetrics` object.
 */
@property (nonatomic, readonly) ARTChannelMetrics *metrics;

/// :nodoc:
- (instancetype)initWithMetrics:(ARTChannelMetrics *)metrics;

@end

/**
 * Contains the status of a `ARTRestChannel` or `ARTRealtimeChannel` object such as whether it is active and its `ARTChannelOccupancy`.
 */
NS_SWIFT_SENDABLE
@interface ARTChannelStatus : NSObject

/**
 * If `true`, the channel is active, otherwise `false`.
 */
@property (nonatomic, readonly) BOOL active;

/**
 * A `ARTChannelOccupancy` object.
 */
@property (nonatomic, readonly) ARTChannelOccupancy *occupancy;

/// :nodoc:
- (instancetype)initWithOccupancy:(ARTChannelOccupancy *)occupancy active:(BOOL)active;

@end

/**
 * Contains the details of a `ARTRestChannel` or `ARTRealtimeChannel` object such as its ID and `ARTChannelStatus`.
 */
NS_SWIFT_SENDABLE
@interface ARTChannelDetails : NSObject

/**
 * The identifier of the channel.
 */
@property (nonatomic, readonly) NSString *channelId;

/**
 * A `ARTChannelStatus` object.
 */
@property (nonatomic, readonly) ARTChannelStatus *status;

/// :nodoc:
- (instancetype)initWithChannelId:(NSString *)channelId status:(ARTChannelStatus *)status;

@end

/// :nodoc:
@protocol ARTJsonCompatible <NSObject>
- (NSDictionary *_Nullable)toJSON:(NSError *_Nullable *_Nullable)error;
- (NSString *_Nullable)toJSONString;
@end

/// :nodoc:
@interface NSString (ARTEventIdentification) <ARTEventIdentification>
@end

/// :nodoc:
@interface NSString (ARTJsonCompatible) <ARTJsonCompatible>
@end

/// :nodoc:
@interface NSString (ARTUtilities)
- (NSString *)art_shortString NS_SWIFT_NAME(shortString());
- (NSString *)art_base64Encoded NS_SWIFT_NAME(base64Encoded());
@end

/// :nodoc:
@interface NSDate (ARTUtilities)
+ (NSDate *)art_dateWithMillisecondsSince1970:(uint64_t)msecs NS_SWIFT_NAME(date(withMillisecondsSince1970:));
@end

/// :nodoc:
@interface NSDictionary (ARTJsonCompatible) <ARTJsonCompatible>
@end

/// :nodoc:
@interface NSURL (ARTLog)
@end

/// :nodoc:
@interface NSDictionary (ARTURLQueryItemAdditions)
@property (nonatomic, readonly) NSArray<NSURLQueryItem *> *art_asURLQueryItems;
@end

/// :nodoc:
@interface NSMutableArray (ARTQueueAdditions)
- (void)art_enqueue:(id)object;
- (nullable id)art_dequeue;
- (nullable id)art_peek;
@end

/// :nodoc:
@interface NSURLSessionTask (ARTCancellable) <ARTCancellable>
@end

/// :nodoc:
typedef NSDictionary<NSString *, NSString *> NSStringDictionary;

// Below are the typedefs of completion handlers to improve readability and maintainability in properties and method parameters.
// Either result/response or error can be nil but not both.

/// :nodoc:
typedef void (^ARTCallback)(ARTErrorInfo *_Nullable error);

/// :nodoc:
typedef void (^ARTResultCallback)(id _Nullable result, NSError *_Nullable error);

/// :nodoc:
typedef void (^ARTDateTimeCallback)(NSDate *_Nullable result, NSError *_Nullable error);

/// :nodoc:
typedef void (^ARTMessageCallback)(ARTMessage *message);

/// :nodoc:
typedef void (^ARTMessageErrorCallback)(ARTMessage *_Nullable message, ARTErrorInfo *_Nullable error);

/// :nodoc:
typedef void (^ARTChannelStateCallback)(ARTChannelStateChange *stateChange);

/// :nodoc:
typedef void (^ARTConnectionStateCallback)(ARTConnectionStateChange *stateChange);

/// :nodoc:
typedef void (^ARTPresenceMessageCallback)(ARTPresenceMessage *message);

/// :nodoc:
typedef void (^ARTPresenceMessageErrorCallback)(ARTPresenceMessage *message, ARTErrorInfo *_Nullable error);

/// :nodoc:
typedef void (^ARTPresenceMessagesCallback)(NSArray<ARTPresenceMessage *> *_Nullable result, ARTErrorInfo *_Nullable error);

/// :nodoc:
typedef void (^ARTAnnotationCallback)(ARTAnnotation *annotation);

/// :nodoc:
typedef void (^ARTPaginatedAnnotationsCallback)(ARTPaginatedResult<ARTAnnotation *> *_Nullable result, ARTErrorInfo *_Nullable error);

/// :nodoc:
typedef void (^ARTChannelDetailsCallback)(ARTChannelDetails *_Nullable details, ARTErrorInfo *_Nullable error);

/// :nodoc:
typedef void (^ARTStatusCallback)(ARTStatus *status);

/// :nodoc:
typedef void (^ARTURLRequestCallback)(NSHTTPURLResponse *_Nullable result, NSData *_Nullable data, NSError *_Nullable error);

/// :nodoc:
typedef void (NS_SWIFT_SENDABLE ^ARTTokenDetailsCallback)(ARTTokenDetails *_Nullable result, NSError *_Nullable error);

/// :nodoc:
typedef void (NS_SWIFT_SENDABLE ^ARTTokenDetailsCompatibleCallback)(id<ARTTokenDetailsCompatible> _Nullable result, NSError *_Nullable error);

/// :nodoc:
typedef void (NS_SWIFT_SENDABLE ^ARTAuthCallback)(ARTTokenParams *params, ARTTokenDetailsCompatibleCallback callback);

/// :nodoc:
typedef void (^ARTHTTPPaginatedCallback)(ARTHTTPPaginatedResponse *_Nullable response, ARTErrorInfo *_Nullable error);

/// :nodoc:
typedef void (^ARTPaginatedStatsCallback)(ARTPaginatedResult<ARTStats *> *_Nullable result, ARTErrorInfo *_Nullable error);

/// :nodoc:
typedef void (^ARTPaginatedPresenceCallback)(ARTPaginatedResult<ARTPresenceMessage *> *_Nullable result, ARTErrorInfo *_Nullable error);

/// :nodoc:
typedef void (^ARTPaginatedPushChannelCallback)(ARTPaginatedResult<ARTPushChannelSubscription *> *_Nullable result, ARTErrorInfo *_Nullable error);

/// :nodoc:
typedef void (^ARTPaginatedMessagesCallback)(ARTPaginatedResult<ARTMessage *> *_Nullable result, ARTErrorInfo *_Nullable error);

/// :nodoc:
typedef void (^ARTPaginatedDeviceDetailsCallback)(ARTPaginatedResult<ARTDeviceDetails *> *_Nullable result, ARTErrorInfo *_Nullable error);

/// :nodoc:
typedef void (^ARTPaginatedTextCallback)(ARTPaginatedResult<NSString *> *_Nullable result, ARTErrorInfo *_Nullable error);

/// :nodoc:
typedef void (^ARTEditResultCallback)(ARTUpdateDeleteResult *_Nullable result, ARTErrorInfo *_Nullable error);

/// :nodoc:
typedef void (^ARTPublishResultCallback)(ARTPublishResult *_Nullable result, ARTErrorInfo *_Nullable error);

/**
 * :nodoc:
 *
 * Wraps the given callback in an ARTCancellable, offering the following protections:
 *
 * 1) If the cancel method is called on the returned instance then the callback will not be invoked.
 * 2) The callback will only ever be invoked once.
 *
 * To make use of these benefits the caller needs to use the returned wrapper to invoke the callback. The wrapper will only work for as long as the returned instance remains allocated (i.e. has a strong reference to it somewhere).
 */
NSObject<ARTCancellable> * artCancellableFromCallback(ARTResultCallback callback, _Nonnull ARTResultCallback *_Nonnull wrapper);

NS_ASSUME_NONNULL_END
