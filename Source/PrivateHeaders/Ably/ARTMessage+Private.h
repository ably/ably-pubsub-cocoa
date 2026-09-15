#import <AblyPubSubDevice/ARTMessage.h>

NS_ASSUME_NONNULL_BEGIN

@interface ARTMessage ()

/**
 * Whether the `action` property has been set by the internals of the SDK.
 *
 * This property defaults to `NO`, indicating that the `action` property is either the default value or has been set by the user. As described in the documentation for `action`, this means that the SDK should ignore the value of this property. In particular, it should not populate this property when sending this message over the wire.
 *
 * - Note: If we had a separate `WireMessage` type instead of using `ARTMessage` as both our internal and external representation of a message, then we wouldn't need this mechanism. But we don't.
 */
@property (nonatomic) BOOL actionIsInternallySet;

@end

NS_ASSUME_NONNULL_END
