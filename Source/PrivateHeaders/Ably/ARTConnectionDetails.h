#import <Foundation/Foundation.h>

@class ARTProtocolMessage;

/**
 * Contains any constraints a client should adhere to and provides additional metadata about a `ARTConnection`, such as if a request to `-[ARTChannelProtocol publish:callback:]` a message that exceeds the maximum message size should be rejected immediately without communicating with Ably.
 */
NS_SWIFT_SENDABLE
@interface ARTConnectionDetails : NSObject

NS_ASSUME_NONNULL_BEGIN

/**
 * Contains the client ID assigned to the token. If `clientId` is `nil` or omitted, then the client is prohibited from assuming a `clientId` in any operations, however if `clientId` is a wildcard string `*`, then the client is permitted to assume any `clientId`. Any other string value for `clientId` implies that the `clientId` is both enforced and assumed for all operations from this client.
 */
@property (readonly, getter=getClientId, nullable) NSString *clientId;

/**
 * The connection secret key string that is used to resume a connection and its state.
 */
@property (readonly, getter=getConnectionKey, nullable) NSString *connectionKey;

/**
 * The maximum message size is an attribute of an Ably account and enforced by Ably servers. `maxMessageSize` indicates the maximum message size allowed by the Ably account this connection is using. Overrides `ARTClientOptions.maxMessageSize`.
 */
@property (readonly, nonatomic) NSInteger maxMessageSize;

/**
 * Overrides `ARTClientOptions.maxFrameSize`.
 */
@property (readonly, nonatomic) NSInteger maxFrameSize;

/**
 * The maximum allowable number of requests per second from a client or Ably. In the case of a realtime connection, this restriction applies to the number of messages sent, whereas in the case of REST, it is the total number of REST requests per second.
 */
@property (readonly, nonatomic) NSInteger maxInboundRate;

/**
 * The duration that Ably will persist the connection state for when a Realtime client is abruptly disconnected.
 * @see `+[ARTDefault connectionStateTtl]`
 */
@property (readonly, nonatomic) NSTimeInterval connectionStateTtl;

/**
 * A unique identifier for the front-end server that the client has connected to. This server ID is only used for the purposes of debugging.
 */
@property (readonly, nonatomic, nullable) NSString *serverId;

/**
 * The maximum length of time in milliseconds that the server will allow no activity to occur in the server to client direction. After such a period of inactivity, the server will send a `HEARTBEAT` or transport-level ping to the client. If the value is `0`, the server will allow arbitrarily-long levels of inactivity.
 */
@property (readonly, nonatomic) NSTimeInterval maxIdleInterval;

/// If the `objectsGCGracePeriod` is present in the `ConnectionDetails`, this contains an `NSNumber` wrapping an `NSTimeInterval` containing its value in seconds.
@property (readonly, nonatomic, nullable) NSNumber *objectsGCGracePeriod;

/// The site code of the server that the client is connected to (CD2j).
@property (nullable, readonly, nonatomic) NSString *siteCode;

- (instancetype)initWithClientId:(NSString *_Nullable)clientId
                   connectionKey:(NSString *_Nullable)connectionKey
                  maxMessageSize:(NSInteger)maxMessageSize
                    maxFrameSize:(NSInteger)maxFrameSize
                  maxInboundRate:(NSInteger)maxInboundRate
              connectionStateTtl:(NSTimeInterval)connectionStateTtl
                        serverId:(NSString *)serverId
                 maxIdleInterval:(NSTimeInterval)maxIdleInterval
            objectsGCGracePeriod:(nullable NSNumber *)objectsGCGracePeriod
                        siteCode:(nullable NSString *)siteCode;

NS_ASSUME_NONNULL_END

@end
