#import <Foundation/Foundation.h>
#import <AblyPubSubDevice/ARTTypes.h>
#import "ARTMessageSendStatus.h"

@class ARTProtocolMessage;

NS_ASSUME_NONNULL_BEGIN

@interface ARTQueuedMessage : NSObject

@property (readonly, nonatomic) ARTProtocolMessage *msg;
@property (readonly, nonatomic) NSMutableArray *sentCallbacks;
@property (readonly, nonatomic) NSMutableArray *ackCallbacks;

- (instancetype)initWithProtocolMessage:(ARTProtocolMessage *)msg sentCallback:(nullable ARTCallback)sentCallback ackCallback:(nullable ARTMessageSendCallback)ackCallback;

- (ARTCallback)sentCallback;
- (ARTMessageSendCallback)ackCallback;

@end

NS_ASSUME_NONNULL_END
