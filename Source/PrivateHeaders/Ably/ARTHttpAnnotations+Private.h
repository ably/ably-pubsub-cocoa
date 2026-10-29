#import <AblyPubSubDevice/ARTHttpAnnotations.h>
#import "ARTQueuedDealloc.h"

NS_ASSUME_NONNULL_BEGIN

@class ARTHttpChannelInternal;
@class ARTInternalLog;

@interface ARTHttpAnnotationsInternal : NSObject<ARTHttpAnnotationsProtocol>

- (instancetype)initWithChannel:(ARTHttpChannelInternal *)channel logger:(ARTInternalLog *)logger;

@end

@interface ARTHttpAnnotations ()

@property (nonatomic, readonly) ARTHttpAnnotationsInternal *internal;

- (instancetype)initWithInternal:(ARTHttpAnnotationsInternal *)internal queuedDealloc:(ARTQueuedDealloc *)dealloc;

@end

NS_ASSUME_NONNULL_END
