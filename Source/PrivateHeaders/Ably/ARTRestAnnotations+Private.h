#import <AblyPubSubDevice/ARTRestAnnotations.h>
#import "ARTQueuedDealloc.h"

NS_ASSUME_NONNULL_BEGIN

@class ARTRestChannelInternal;
@class ARTInternalLog;

@interface ARTRestAnnotationsInternal : NSObject<ARTRestAnnotationsProtocol>

- (instancetype)initWithChannel:(ARTRestChannelInternal *)channel logger:(ARTInternalLog *)logger;

@end

@interface ARTRestAnnotations ()

@property (nonatomic, readonly) ARTRestAnnotationsInternal *internal;

- (instancetype)initWithInternal:(ARTRestAnnotationsInternal *)internal queuedDealloc:(ARTQueuedDealloc *)dealloc;

@end

NS_ASSUME_NONNULL_END
