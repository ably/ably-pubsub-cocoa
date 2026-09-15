#import <AblyPubSubDevice/ARTPresence.h>
#import "ARTChannel.h"

@interface ARTPresenceQuery ()

- (NSMutableArray<NSURLQueryItem *> *)asQueryItems;

@end

@interface ARTPresence ()

@property (readonly, getter=getChannel) ARTChannel *channel;

- (instancetype)initWithChannel:(ARTChannel *)channel;

@end
