#import <Foundation/Foundation.h>

#import <AblyPubSubDevice/ARTTypes.h>
#import "ARTStringifiable.h"

@class ARTHttpClient;
@class ARTChannelOptions;
@class ARTMessage;
@class ARTMessageOperation;
@class ARTBaseMessage;
@class ARTPaginatedResult<ItemType>;
@class ARTDataQuery;
@class ARTLocalDevice;

NS_ASSUME_NONNULL_BEGIN

/**
 The protocol upon which `ARTHttpChannelProtocol` and `ARTRealtimeChannelProtocol` are based.
 */
NS_SWIFT_NAME(ChannelProtocol)
@protocol ARTChannelProtocol

/**
 * The channel name.
 */
@property (readonly) NSString *name;

/**
 * Publishes a single message to the channel with the given event name and payload. When publish is called with this client library, it won't attempt to implicitly attach to the channel, so long as [transient publishing](https://ably.com/docs/realtime/channels#transient-publish) is available in the library. Otherwise, the client will implicitly attach.
 *
 * @param name The name of the message.
 * @param data The payload of the message.
 */
- (void)publish:(nullable NSString *)name data:(nullable id)data;

/**
 * Publishes a single message to the channel with the given event name and payload. A callback may optionally be passed in to this call to be notified of success or failure of the operation. When publish is called with this client library, it won't attempt to implicitly attach to the channel, so long as [transient publishing](https://ably.com/docs/realtime/channels#transient-publish) is available in the library. Otherwise, the client will implicitly attach.
 *
 * @param name The name of the message.
 * @param data The payload of the message.
 * @param callback A success or failure callback function.
 */
- (void)publish:(nullable NSString *)name data:(nullable id)data callback:(nullable ARTCallback)callback;

/**
 * Publishes a single message to the channel with the given event name and payload. A callback may optionally be passed in to this call to be notified of success or failure of the operation. When publish is called with this client library, it won't attempt to implicitly attach to the channel, so long as [transient publishing](https://ably.com/docs/realtime/channels#transient-publish) is available in the library. Otherwise, the client will implicitly attach.
 *
 * @param name The name of the message.
 * @param data The payload of the message.
 * @param resultCallback A success or failure callback function. On success, receives an `ARTPublishResult` containing the serial of the published message.
 */
- (void)publish:(nullable NSString *)name data:(nullable id)data resultCallback:(nullable ARTPublishResultCallback)resultCallback;

/**
 * Publishes a single message to the channel with the given event name, payload, and `clientId`. When publish is called with this client library, it won't attempt to implicitly attach to the channel, so long as [transient publishing](https://ably.com/docs/realtime/channels#transient-publish) is available in the library. Otherwise, the client will implicitly attach.
 *
 * @param name The name of the message.
 * @param data The payload of the message.
 * @param clientId The ``ARTMessage/clientId`` of the message.
 */
- (void)publish:(nullable NSString *)name data:(nullable id)data clientId:(NSString *)clientId;

/**
 * Publishes a single message to the channel with the given event name, payload, and `clientId`. A callback may optionally be passed in to this call to be notified of success or failure of the operation. When publish is called with this client library, it won't attempt to implicitly attach to the channel, so long as [transient publishing](https://ably.com/docs/realtime/channels#transient-publish) is available in the library. Otherwise, the client will implicitly attach.
 *
 * @param name The name of the message.
 * @param data The payload of the message.
 * @param clientId The ``ARTMessage/clientId`` of the message.
 * @param callback A success or failure callback function.
 */
- (void)publish:(nullable NSString *)name data:(nullable id)data clientId:(NSString *)clientId callback:(nullable ARTCallback)callback;

/**
 * Publishes a single message to the channel with the given event name, payload, and `extras`. When publish is called with this client library, it won't attempt to implicitly attach to the channel, so long as [transient publishing](https://ably.com/docs/realtime/channels#transient-publish) is available in the library. Otherwise, the client will implicitly attach.
 *
 * @param name The name of the message.
 * @param data The payload of the message.
 * @param extras The ``ARTMessage/extras`` of the message.
 */
- (void)publish:(nullable NSString *)name data:(nullable id)data extras:(nullable id<ARTJsonCompatible>)extras;

/**
 * Publishes a single message to the channel with the given event name, payload, and `extras`. A callback may optionally be passed in to this call to be notified of success or failure of the operation. When publish is called with this client library, it won't attempt to implicitly attach to the channel, so long as [transient publishing](https://ably.com/docs/realtime/channels#transient-publish) is available in the library. Otherwise, the client will implicitly attach.
 *
 * @param name The name of the message.
 * @param data The payload of the message.
 * @param extras The ``ARTMessage/extras`` of the message.
 * @param callback A success or failure callback function.
 */
- (void)publish:(nullable NSString *)name data:(nullable id)data extras:(nullable id<ARTJsonCompatible>)extras callback:(nullable ARTCallback)callback;

/**
 * Publishes a single message to the channel with the given event name, payload, `clientId`, and `extras`. When publish is called with this client library, it won't attempt to implicitly attach to the channel, so long as [transient publishing](https://ably.com/docs/realtime/channels#transient-publish) is available in the library. Otherwise, the client will implicitly attach.
 *
 * @param name The name of the message.
 * @param data The payload of the message.
 * @param clientId The ``ARTMessage/clientId`` of the message.
 * @param extras The ``ARTMessage/extras`` of the message.
 */
- (void)publish:(nullable NSString *)name data:(nullable id)data clientId:(NSString *)clientId extras:(nullable id<ARTJsonCompatible>)extras;

/**
 * Publishes a single message to the channel with the given event name, payload, `clientId`, and `extras`. A callback may optionally be passed in to this call to be notified of success or failure of the operation. When publish is called with this client library, it won't attempt to implicitly attach to the channel, so long as [transient publishing](https://ably.com/docs/realtime/channels#transient-publish) is available in the library. Otherwise, the client will implicitly attach.
 *
 * @param name The name of the message.
 * @param data The payload of the message.
 * @param clientId The ``ARTMessage/clientId`` of the message.
 * @param extras The ``ARTMessage/extras`` of the message.
 * @param callback A success or failure callback function.
 */
- (void)publish:(nullable NSString *)name data:(nullable id)data clientId:(NSString *)clientId extras:(nullable id<ARTJsonCompatible>)extras callback:(nullable ARTCallback)callback;

/**
 * Publishes an array of messages to the channel.
 *
 * @param messages An array of `ARTMessage` objects.
 */
- (void)publish:(NSArray<ARTMessage *> *)messages;

/**
 * Publishes an array of messages to the channel. A callback may optionally be passed in to this call to be notified of success or failure of the operation.
 *
 * @param messages An array of `ARTMessage` objects.
 * @param callback A success or failure callback function.
 */
- (void)publish:(NSArray<ARTMessage *> *)messages callback:(nullable ARTCallback)callback;

/**
 * Publishes an array of messages to the channel. A callback may optionally be passed in to this call to be notified of success or failure of the operation.
 *
 * @param messages An array of `ARTMessage` objects.
 * @param resultCallback A success or failure callback function. On success, receives an `ARTPublishResult` containing the serials of the published messages.
 */
- (void)publish:(NSArray<ARTMessage *> *)messages resultCallback:(nullable ARTPublishResultCallback)resultCallback;

/**
 * Publishes an update to existing message with shallow mixin semantics. Non-`nil` `name`, `data`, and `extras` properties in the provided message will replace the corresponding fields in the existing message, while `nil` properties will be left unchanged. Note that this publishes an update, it does not mutate the original message if passed in.
 *
 * @param message An `ARTMessage` object containing a populated `serial` field and the fields to update.
 * @param operation An optional `ARTMessageOperation` object containing metadata about the update operation.
 * @param params Optional parameters sent as part of the request. As Ably adds supported parameters, they will be documented on the [docs pages](https://ably.com/docs).
 * @param callback A success or failure callback function. On success, it receives an `ARTUpdateDeleteResult` object containing the new version of the message.
 */
- (void)updateMessage:(ARTMessage *)message
            operation:(nullable ARTMessageOperation *)operation
               params:(nullable NSDictionary<NSString *, ARTStringifiable *> *)params
             callback:(nullable ARTEditResultCallback)callback;

/**
 * Marks a message as deleted by publishing an update with an action of `ARTMessageActionDelete`. This does not remove the message from the server, and the full message history remains accessible. Uses shallow mixin semantics: non-`nil` `name`, `data`, and `extras` properties in the provided message will replace the corresponding properties in the existing message, while `nil` fields will be left unchanged (meaning that if you for example want the `ARTMessageActionDelete` to have an empty data, you should explicitly set the `data` to an empty object).
 *
 * @param message An `ARTMessage` object containing a populated `serial` field.
 * @param operation An optional `ARTMessageOperation` object containing metadata about the delete operation.
 * @param params Optional parameters sent as part of the request. As Ably adds supported parameters, they will be documented on the [docs pages](https://ably.com/docs).
 * @param callback A success or failure callback function. On success, it receives an `ARTUpdateDeleteResult` object containing the new version of the message.
 */
- (void)deleteMessage:(ARTMessage *)message
            operation:(nullable ARTMessageOperation *)operation
               params:(nullable NSDictionary<NSString *, ARTStringifiable *> *)params
             callback:(nullable ARTEditResultCallback)callback;

/**
 * Appends data to an existing message. The supplied `data` property is appended to the previous message's data, while all other properties (`name`, `extras`) replace the previous values if provided.
 *
 * @param message An `ARTMessage` object containing a populated `serial` field and the data to append.
 * @param operation An optional `ARTMessageOperation` object containing metadata about the append operation.
 * @param params Optional parameters sent as part of the request. As Ably adds supported parameters, they will be documented on the [docs pages](https://ably.com/docs).
 * @param callback A success or failure callback function. On success, it receives an `ARTUpdateDeleteResult` object containing the new version of the message.
 */
- (void)appendMessage:(ARTMessage *)message
            operation:(nullable ARTMessageOperation *)operation
               params:(nullable NSDictionary<NSString *, ARTStringifiable *> *)params
             callback:(nullable ARTEditResultCallback)callback;

/**
 * Retrieves the latest version of a specific message by its serial identifier.
 *
 * @param serial A serial identifier string of the message to retrieve.
 * @param callback A callback which, upon success, will contain a `ARTMessage` object representing the latest version of the message. Upon failure, the callback will contain an `ARTErrorInfo` object which explains the error.
 */
- (void)getMessageWithSerial:(NSString *)serial callback:(ARTMessageErrorCallback)callback;

/**
 * Retrieves all historical versions of a specific message, ordered by version. This includes the original message and all subsequent updates or delete operations.
 *
 * @param serial A serial identifier string of the message whose versions are to be retrieved.
 * @param callback A callback which, upon success, will contain an `ARTPaginatedResult` object containing an array of `ARTMessage` objects representing all versions of the message. Upon failure, the callback will contain an `ARTErrorInfo` object which explains the error.
 */
- (void)getMessageVersionsWithSerial:(NSString *)serial callback:(ARTPaginatedMessagesCallback)callback;

/// :nodoc: TODO: docstring
- (void)history:(ARTPaginatedMessagesCallback)callback;

@end

NS_ASSUME_NONNULL_END
