#import <AblyPubSubDevice/ARTPresenceMessage.h>

@interface ARTPresenceMessage ()

/**
 Returns whether this presenceMessage is synthesized, i.e. was not actually sent by the connection (usually means a leave event sent 15s after a disconnection). This is useful because synthesized messages cannot be compared for newness by id lexicographically - RTP2b1.
 */
- (BOOL)isSynthesized;

- (NSArray<NSString *> *)parseId;
- (NSInteger)msgSerialFromId;
- (NSInteger)indexFromId;

@end
