#import <Foundation/Foundation.h>

#import <AblyPubSubDevice/ARTTypes.h>

@class ARTRealtimeClient;
@class ARTEventEmitter;
@class ARTConnectionRecoveryKey;

NS_ASSUME_NONNULL_BEGIN

/**
 The protocol upon which the `ARTConnection` is implemented. Also embeds `ARTEventEmitter`.
 */
NS_SWIFT_NAME(ConnectionProtocol)
@protocol ARTConnectionProtocol <NSObject>

/**
 * A unique public identifier for this connection, used to identify this member.
 */
@property (nullable, readonly) NSString *id;

/**
 * A unique private connection key used to recover or resume a connection, assigned by Ably. When recovering a connection explicitly, the `recoveryKey` is used in the recover client options as it contains both the key and the last message serial. This private connection key can also be used by other REST clients to publish on behalf of this client. See the [publishing over REST on behalf of a realtime client docs](https://ably.com/docs/rest/channels#publish-on-behalf) for more info.
 */
@property (nullable, readonly) NSString *key;

/**
 * The maximum message size is an attribute of an Ably account and enforced by Ably servers. `maxMessageSize` indicates the maximum message size allowed by the Ably account this connection is using. Overrides the default value of `+[ARTDefault maxMessageSize]`.
 */
@property (readonly) NSInteger maxMessageSize;

/**
 * The current `ARTRealtimeConnectionState` of the connection.
 */
@property (readonly) ARTRealtimeConnectionState state;

/**
 * An `ARTErrorInfo` object describing the last error received if a connection failure occurs.
 */
@property (nullable, readonly) ARTErrorInfo *errorReason;

/**
 * The recovery key string can be used by another client to recover this connection's state in the recover client options property. See [connection state recover options](https://ably.com/docs/realtime/connection#connection-state-recover-options) for more information.
 * This will return `nil` if connection is in `CLOSED`, `CLOSING`, `FAILED`, or `SUSPENDED` states, or when it does not have a connection `key` (for example, it has not yet become connected).
 */
- (nullable NSString *)createRecoveryKey;

/**
 * Explicitly calling `connect` is unnecessary unless the `ARTClientOptions.autoConnect` is `false`. Unless already connected or connecting, this method causes the connection to open, entering the `ARTRealtimeConnectionState.ARTRealtimeConnecting` state.
 */
- (void)connect;

/**
 * Causes the connection to close, entering the `ARTRealtimeConnectionState.ARTRealtimeClosing` state. Once closed, the library does not attempt to re-establish the connection without an explicit call to `-[ARTConnectionProtocol connect]`.
 */
- (void)close;

/**
 * When connected, sends a heartbeat ping to the Ably server and executes the callback with an error if any. This can be useful for measuring true round-trip latency to the connected Ably server.
 *
 * @param callback A success or failure callback function.
 */
- (void)ping:(ARTCallback)callback;

#pragma mark ARTEventEmitter

/**
 * Embeds an `ARTEventEmitter` object.
 */
ART_EMBED_INTERFACE_EVENT_EMITTER(ARTRealtimeConnectionEvent, ARTConnectionStateChange *)

@end

/**
 * Enables the management of a connection to Ably.
 *
 * @see See `ARTConnectionProtocol` for details.
 */
NS_SWIFT_SENDABLE
NS_SWIFT_NAME(Connection)
@interface ARTConnection: NSObject <ARTConnectionProtocol>

@end

#pragma mark - ARTEvent

/// :nodoc:
@interface ARTEvent (ConnectionEvent)
- (instancetype)initWithConnectionEvent:(ARTRealtimeConnectionEvent)value;
+ (instancetype)newWithConnectionEvent:(ARTRealtimeConnectionEvent)value;
@end

NS_ASSUME_NONNULL_END
