#import <AblyPubSubDevice/ARTRealtimeAnnotations.h>
#import "ARTRealtimeChannel+Private.h"

NS_ASSUME_NONNULL_BEGIN

@interface ARTRealtimeAnnotationsInternal : NSObject<ARTRealtimeAnnotationsProtocol>

@property (readonly, nonatomic) ARTEventEmitter<ARTEvent *, ARTAnnotation *> *eventEmitter;
@property (readonly, weak, nonatomic) ARTPubSubClientInternal *realtime; // weak because realtime owns self

- (instancetype)initWithChannel:(ARTRealtimeChannelInternal *)channel logger:(ARTInternalLog *)logger;

- (void)onMessage:(ARTProtocolMessage *)message;

@property (nonatomic) dispatch_queue_t queue;

@end

@interface ARTRealtimeAnnotations ()

@property (nonatomic, readonly) ARTRealtimeAnnotationsInternal *internal;

- (instancetype)initWithInternal:(ARTRealtimeAnnotationsInternal *)internal queuedDealloc:(ARTQueuedDealloc *)dealloc;

@end

NS_ASSUME_NONNULL_END
