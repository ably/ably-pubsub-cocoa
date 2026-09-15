#import <Foundation/Foundation.h>

#import <AblyPubSubDevice/ARTTypes.h>
#import <AblyPubSubDevice/ARTPresenceMessage.h>
#import <AblyPubSubDevice/ARTPaginatedResult.h>

NS_ASSUME_NONNULL_BEGIN

/// :nodoc:
@interface ARTPresence : NSObject

- (void)history:(ARTPaginatedPresenceCallback)callback;

@end

NS_ASSUME_NONNULL_END
