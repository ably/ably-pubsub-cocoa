#import <AblyPubSubDevice/ARTRestChannels.h>
#import "ARTQueuedDealloc.h"
#import "ARTRestChannel+Private.h"

@class ARTRestChannel;
@class ARTRestInternal;

NS_ASSUME_NONNULL_BEGIN

@interface ARTRestChannelsInternal : NSObject

- (ARTRestChannelInternal *)get:(NSString *)name;
- (ARTRestChannelInternal *)get:(NSString *)name options:(ARTChannelOptions *)options;
- (id<NSFastEnumeration>)copyIntoIteratorWithMapper:(ARTRestChannel *(^)(ARTRestChannelInternal *))mapper;

- (instancetype)initWithRest:(ARTRestInternal *)rest logger:(ARTInternalLog *)logger;
- (ARTRestChannelInternal *)_getChannel:(NSString *)name options:(ARTChannelOptions * _Nullable)options addPrefix:(BOOL)addPrefix;

- (BOOL)exists:(NSString *)name;
- (void)release:(NSString *)name;

@end

@interface ARTRestChannels ()

@property (nonatomic, readonly) ARTRestChannelsInternal *internal;

- (instancetype)initWithInternal:(ARTRestChannelsInternal *)internal queuedDealloc:(ARTQueuedDealloc *)dealloc;

@end

NS_ASSUME_NONNULL_END
