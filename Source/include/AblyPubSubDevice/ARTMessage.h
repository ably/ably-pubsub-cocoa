#import <Foundation/Foundation.h>

#import <AblyPubSubDevice/ARTBaseMessage.h>
#import <AblyPubSubDevice/ARTTypes.h>
#import <AblyPubSubDevice/ARTChannelOptions.h>
#import <AblyPubSubDevice/ARTMessageVersion.h>
#import <AblyPubSubDevice/ARTMessageAnnotations.h>

/**
 * The namespace containing the different types of message actions.
 */
NS_SWIFT_SENDABLE
typedef NS_ENUM(NSUInteger, ARTMessageAction) {
    /**
     * Message action for a newly created message.
     */
    ARTMessageActionCreate,
    /**
     * Message action for an updated message.
     */
    ARTMessageActionUpdate,
    /**
     * Message action for a deleted message.
     */
    ARTMessageActionDelete,
    /**
     * A meta-message (a message originating from ably rather than being
     * explicitly published on a channel), containing information such as
     * inband channel occupancy events that has been requested by channel
     * param.
     */
    ARTMessageActionMeta,
    /**
     * Message action for a message containing the latest rolled-up summary of
     * annotations that have been made to this message.
     */
    ARTMessageActionMessageSummary,
    /**
     * Message action for an appended message. The `serial` field identifies
     * the message to which data is being appended. The `data` field is
     * appended to the previous message's data, while all other fields
     * replace the previous values.
     */
    ARTMessageActionAppend,
};

NSString *_Nonnull ARTMessageActionToStr(ARTMessageAction action);

NS_ASSUME_NONNULL_BEGIN

@class ARTMessageVersion;
@class ARTMessageAnnotations;

/**
 * Contains an individual message that is sent to, or received from, Ably.
 */
@interface ARTMessage : ARTBaseMessage

/// The event name, if available
@property (nullable, readwrite, nonatomic) NSString *name;

/// The action type of the message, one of the `ARTMessageAction` enum values.
///
/// - Note: A message that you create via the ``initWithName:data:`` or ``initWithName:data:clientId:`` initializers will have an `action` of ``ARTMessageAction/ARTMessageActionCreate``. However, the value of this property will be ignored when you pass this message to the SDK (e.g. when publishing the message).
@property (readwrite, nonatomic) ARTMessageAction action;

/// This message's unique serial (an identifier that will be the same in all future updates of this message).
@property (nullable, readwrite, nonatomic) NSString *serial;

/// The version information for the message, containing serial, timestamp, and operation metadata.
@property (nullable, readwrite, nonatomic) ARTMessageVersion *version;

/// Contains annotations for the message, including summary data.
@property (nullable, readwrite, nonatomic) ARTMessageAnnotations *annotations;

/**
 * Construct an `ARTMessage` object with an event name and payload.
 *
 * @param name The event name.
 * @param data The message payload.
 */
- (instancetype)initWithName:(nullable NSString *)name data:(id)data;

/**
 * Construct an `ARTMessage` object with an event name, payload, and a unique client ID.
 *
 * @param name The event name.
 * @param data The message payload.
 * @param clientId The client ID of the publisher of this message.
 */
- (instancetype)initWithName:(nullable NSString *)name data:(id)data clientId:(NSString *)clientId;

@end

@interface ARTMessage (Decoding)

/**
 * A static factory method to create an `ARTMessage` object from a deserialized Message-like object encoded using Ably's wire protocol.
 *
 * @param jsonObject A `Message`-like deserialized object.
 * @param options An `ARTChannelOptions` object. If you have an encrypted channel, use this to allow the library to decrypt the data.
 *
 * @return An `ARTMessage` object.
 */
+ (nullable instancetype)fromEncoded:(NSDictionary *)jsonObject
                      channelOptions:(ARTChannelOptions *)options
                               error:(NSError *_Nullable *_Nullable)error;

/**
 * A static factory method to create an array of `ARTMessage` objects from an array of deserialized Message-like object encoded using Ably's wire protocol.
 *
 * @param jsonArray An array of `Message`-like deserialized objects.
 * @param options An `ARTChannelOptions` object. If you have an encrypted channel, use this to allow the library to decrypt the data.
 *
 * @return An array of `ARTMessage` objects.
 */
+ (nullable NSArray<ARTMessage *> *)fromEncodedArray:(NSArray<NSDictionary *> *)jsonArray
                                      channelOptions:(ARTChannelOptions *)options
                                               error:(NSError *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END

