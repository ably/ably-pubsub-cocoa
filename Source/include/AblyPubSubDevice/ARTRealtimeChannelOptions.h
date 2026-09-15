#import <Foundation/Foundation.h>

#import <AblyPubSubDevice/ARTChannelOptions.h>

/**
 * Describes the possible flags used to configure client capabilities, using `ARTChannelOptions`.
 */
NS_SWIFT_SENDABLE
typedef NS_OPTIONS(NSUInteger, ARTChannelMode) {
    /**
     * The client can enter the presence set.
     */
    ARTChannelModePresence = 1 << 16,
    /**
     * The client can publish messages.
     */
    ARTChannelModePublish = 1 << 17,
    /**
     * The client can subscribe to messages.
     */
    ARTChannelModeSubscribe = 1 << 18,
    /**
     * The client can receive presence messages.
     */
    ARTChannelModePresenceSubscribe = 1 << 19,
    /**
     * The client can publish annotations to messages.
     */
    ARTChannelModeAnnotationPublish = 1 << 21,
    /**
     * The client can receive annotations for messages.
     */
    ARTChannelModeAnnotationSubscribe = 1 << 22,
    /**
     * The client can receive object messages.
     */
    ARTChannelModeObjectSubscribe = 1 << 24,
    /**
     * The client can publish object messages.
     */
    ARTChannelModeObjectPublish = 1 << 25
};

NS_ASSUME_NONNULL_BEGIN

/**
 * Passes additional properties to an `ARTRealtimeChannel` object, such as encryption, an `ARTChannelMode` and channel parameters.
 */
@interface ARTRealtimeChannelOptions : ARTChannelOptions

/**
 * [Channel Parameters](https://ably.com/docs/realtime/channels/channel-parameters/overview) that configure the behavior of the channel.
 */
@property (nonatomic, nullable) NSStringDictionary *params;

/**
 * An array of `ARTChannelMode` objects.
 */
@property (nonatomic) ARTChannelMode modes;

/**
 * A boolean which determines whether calling `subscribe` on a `ARTRealtimeChannel` or `ARTRealtimePresense` object should trigger an implicit attach (for realtime client libraries only). Defaults to true.
 */
@property (nonatomic) BOOL attachOnSubscribe;

@end

NS_ASSUME_NONNULL_END
