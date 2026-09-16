#import <Foundation/Foundation.h>

#import <AblyPubSubDevice/ARTTypes.h>
#import <AblyPubSubDevice/ARTChannelProtocol.h>
#import <AblyPubSubDevice/ARTPresenceMessage.h>
#import <AblyPubSubDevice/ARTEventEmitter.h>
#import <AblyPubSubDevice/ARTRealtimePresence.h>
#import <AblyPubSubDevice/ARTRealtimeChannelOptions.h>
#import <AblyPubSubDevice/ARTDataQuery.h>

NS_ASSUME_NONNULL_BEGIN

@class ARTRealtimePresence;
@class ARTRealtimeAnnotations;
@class ARTRealtimeChannelOptions;
@class ARTChannelProperties;
#if TARGET_OS_IPHONE
@class ARTPushChannel;
#endif

/**
 The protocol upon which the `ARTRealtimeChannel` is implemented. Also embeds `ARTEventEmitter`.
 */
@protocol ARTRealtimeChannelProtocol <ARTChannelProtocol>

/**
 * The current `ARTRealtimeChannelState` of the channel.
 */
@property (readonly) ARTRealtimeChannelState state;

/**
 * The `ARTChannelMode` flags associated with the channel.
 */
@property (readonly) ARTChannelMode modes;

/**
 * An `ARTChannelProperties` object.
 */
@property (readonly) ARTChannelProperties *properties;

/**
 * An `ARTErrorInfo` object describing the last error which occurred on the channel, if any.
 */
@property (readonly, nullable) ARTErrorInfo *errorReason;

/// :nodoc: TODO: docstring
@property (readonly, nullable, getter=getOptions) ARTRealtimeChannelOptions *options;

/**
 * A shortcut for the `-[ARTRealtimeChannelProtocol attach:]` method.
 */
- (void)attach;

/**
 * Attach to this channel ensuring the channel is created in the Ably system and all messages published on the channel are received by any channel listeners registered using `-[ARTRealtimeChannelProtocol subscribe:]`. Any resulting channel state change will be emitted to any listeners registered using the `-[ARTEventEmitter on:]` or `-[ARTEventEmitter once:]` methods. A callback may optionally be passed in to this call to be notified of success or failure of the operation. As a convenience, `attach:` is called implicitly if `-[ARTRealtimeChannelProtocol subscribe:]` is called on the channel or `-[ARTRealtimePresenceProtocol subscribe:]` is called on the `ARTRealtimePresence` object for this channel, unless you've set the `ARTRealtimeChannelOptions.attachOnSubscribe` channel option to `false`. It is also called implicitly if `-[ARTRealtimePresenceProtocol enter:]` is called on the `ARTRealtimePresence` object for this channel.
 *
 * @param callback A success or failure callback function.
 */
- (void)attach:(nullable ARTCallback)callback;

/**
 * A shortcut for the `-[ARTRealtimeChannelProtocol detach:]` method.
 */
- (void)detach;

/**
 * Detach from this channel. Any resulting channel state change is emitted to any listeners registered using the `-[ARTEventEmitter on:]` or `-[ARTEventEmitter once:]` methods. A callback may optionally be passed in to this call to be notified of success or failure of the operation. Once all clients globally have detached from the channel, the channel will be released in the Ably service within two minutes.
 *
 * @param callback A success or failure callback function.
 */
- (void)detach:(nullable ARTCallback)callback;

/**
 * Registers a listener for messages on this channel. The caller supplies a listener function, which is called each time one or more messages arrives on the channel.
 *
 * @param callback An event listener function.
 *
 * @return An `ARTEventListener` object.
 *
 * @see See `subscribeWithAttachCallback:` for more details.
 */
- (ARTEventListener *_Nullable)subscribe:(ARTMessageCallback)callback;

/**
 * Registers a listener for messages on this channel. The caller supplies a listener function, which is called each time one or more messages arrives on the channel.
 * An attach callback may optionally be passed in to this call to be notified of success or failure of the channel `-[ARTRealtimeChannelProtocol attach]` operation. It will not be called if the `ARTRealtimeChannelOptions.attachOnSubscribe` channel option is set to `false`.
 *
 * @param onAttach An attach callback function.
 * @param callback An event listener function.
 *
 * @return An `ARTEventListener` object.
 */
- (ARTEventListener *_Nullable)subscribeWithAttachCallback:(nullable ARTCallback)onAttach callback:(ARTMessageCallback)callback;

/**
 * Registers a listener for messages with a given event `name` on this channel. The caller supplies a listener function, which is called each time one or more matching messages arrives on the channel.
 *
 * @param name The event name.
 * @param callback An event listener function.
 *
 * @return An `ARTEventListener` object.
 *
 * @see See `subscribeWithAttachCallback:` for more details.
*/
- (ARTEventListener *_Nullable)subscribe:(NSString *)name callback:(ARTMessageCallback)callback;

/**
 * Registers a listener for messages with a given event `name` on this channel. The caller supplies a listener function, which is called each time one or more matching messages arrives on the channel. A callback may optionally be passed in to this call to be notified of success or failure of the channel `-[ARTRealtimeChannelProtocol attach]` operation. It will not be called if the `ARTRealtimeChannelOptions.attachOnSubscribe` channel option is set to `false`.
 *
 * @param name The event name.
 * @param callback An event listener function.
 *
 * @return An `ARTEventListener` object.
 */
- (ARTEventListener *_Nullable)subscribe:(NSString *)name onAttach:(nullable ARTCallback)onAttach callback:(ARTMessageCallback)callback;

/**
 * Deregisters all listeners to messages on this channel. This removes all earlier subscriptions.
 */
- (void)unsubscribe;

/**
 * Deregisters the given listener (for any/all event names). This removes an earlier subscription.
 *
 * @param listener An event listener object to unsubscribe.
 */
- (void)unsubscribe:(ARTEventListener *_Nullable)listener;

/**
 * Deregisters the given listener for the specified event name. This removes an earlier event-specific subscription.
 *
 * @param name The event name.
 * @param listener An event listener object to unsubscribe.
 */
- (void)unsubscribe:(NSString *)name listener:(ARTEventListener *_Nullable)listener;

/**
 * Retrieves an `ARTPaginatedResult` object, containing an array of historical `ARTMessage` objects for the channel. If the channel is configured to persist messages, then messages can be retrieved from history for up to 72 hours in the past. If not, messages can only be retrieved from history for up to two minutes in the past.
 *
 * @param query An `ARTRealtimeHistoryQuery` object.
 * @param callback A callback for retriving an `ARTPaginatedResult` object with an array of `ARTMessage` objects.
 * @param errorPtr A reference to the `NSError` object where an error information will be saved in case of failure.
 *
 * @return In case of failure returns `false` and the error information can be retrived via the `error` parameter.
 */
- (BOOL)history:(ARTRealtimeHistoryQuery *_Nullable)query callback:(ARTPaginatedMessagesCallback)callback error:(NSError *_Nullable *_Nullable)errorPtr;

/**
 * Sets the `ARTRealtimeChannelOptions` for the channel. An optional callback may be provided to notify of the success or failure of the operation.
 *
 * @param options An `ARTRealtimeChannelOptions` object.
 * @param callback A success or failure callback function.
 */
- (void)setOptions:(ARTRealtimeChannelOptions *_Nullable)options callback:(nullable ARTCallback)callback;

#pragma mark ARTEventEmitter

/**
 * `ARTRealtimeChannel` implements `ARTEventEmitter` and emits `ARTChannelEvent` events, where a `ARTChannelEvent` is either a `ARTRealtimeChannelState` or an `ARTChannelEventUpdate`.
 */
ART_EMBED_INTERFACE_EVENT_EMITTER(ARTChannelEvent, ARTChannelStateChange *)

@end

/**
 * Describes the properties of the channel state.
 */
@interface ARTChannelProperties : NSObject
/**
 * Starts unset when a channel is instantiated, then updated with the `channelSerial` from each `ARTChannelEventAttached` event that matches the channel. Used as the value for `ARTRealtimeHistoryQuery.untilAttach`.
 */
@property (nonatomic, readonly, nullable) NSString *attachSerial; // CP2a
/**
 * Updated by the framework whenever there is some activity on the channel (user message received, presence updated or a channel attached).
 */
@property (nonatomic, readonly, nullable) NSString *channelSerial; // CP2b

// Exposed for mocking/testing purposes in conjuction with `ARTRealtimeChannelProtocol`.
- (instancetype)initWithAttachSerial:(nullable NSString *)attachSerial channelSerial:(nullable NSString *)channelSerial;

@end

/**
 * Enables messages to be published and subscribed to. Also enables historic messages to be retrieved and provides access to the `ARTRealtimePresence` object of a channel.
 * Also implements `ARTEventEmitter` interface and emits `ARTChannelEvent` events, where a `ARTChannelEvent` is either a `ARTRealtimeChannelState` or an `ARTChannelEvent.ARTChannelEventUpdate`.
 */
NS_SWIFT_SENDABLE
@interface ARTRealtimeChannel : NSObject <ARTRealtimeChannelProtocol>

/**
 * An `ARTRealtimePresence` object.
 */
@property (readonly) ARTRealtimePresence *presence;

/**
 * An `ARTRealtimeAnnotations` object.
 */
@property (readonly) ARTRealtimeAnnotations *annotations;

#if TARGET_OS_IPHONE
/**
 * An `ARTPushChannel` object.
 */
@property (readonly) ARTPushChannel *push;
#endif

@end

#pragma mark - ARTEvent

/// :nodoc:
@interface ARTEvent (ChannelEvent)
- (instancetype)initWithChannelEvent:(ARTChannelEvent)value;
+ (instancetype)newWithChannelEvent:(ARTChannelEvent)value;
@end

NS_ASSUME_NONNULL_END
