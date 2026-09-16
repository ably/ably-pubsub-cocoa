#import <AblyPubSubDevice/ARTHttpChannels.h>
#import "ARTQueuedDealloc.h"
#import "ARTHttpChannel+Private.h"

@class ARTHttpChannel;
@class ARTHttpClientInternal;

NS_ASSUME_NONNULL_BEGIN

@interface ARTHttpChannelsInternal : NSObject

- (ARTHttpChannelInternal *)get:(NSString *)name;
- (ARTHttpChannelInternal *)get:(NSString *)name options:(ARTChannelOptions *)options;
- (id<NSFastEnumeration>)copyIntoIteratorWithMapper:(ARTHttpChannel *(^)(ARTHttpChannelInternal *))mapper;

- (instancetype)initWithRest:(ARTHttpClientInternal *)rest logger:(ARTInternalLog *)logger;
- (ARTHttpChannelInternal *)_getChannel:(NSString *)name options:(ARTChannelOptions * _Nullable)options addPrefix:(BOOL)addPrefix;

- (BOOL)exists:(NSString *)name;
- (void)release:(NSString *)name;

@end

@interface ARTHttpChannels ()

@property (nonatomic, readonly) ARTHttpChannelsInternal *internal;

- (instancetype)initWithInternal:(ARTHttpChannelsInternal *)internal queuedDealloc:(ARTQueuedDealloc *)dealloc;

@end

NS_ASSUME_NONNULL_END
