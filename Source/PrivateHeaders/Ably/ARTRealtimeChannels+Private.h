//
//  ARTRealtimeChannels+Private.h
//
//

#import <AblyPubSubDevice/ARTRealtimeChannels.h>
#import "ARTRealtimeClient+Private.h"
#import "ARTQueuedDealloc.h"

@class ARTRealtimeChannelInternal;

NS_ASSUME_NONNULL_BEGIN

@interface ARTRealtimeChannelsInternal : NSObject

- (ARTRealtimeChannelInternal *)get:(NSString *)name;
- (ARTRealtimeChannelInternal *)get:(NSString *)name options:(ARTRealtimeChannelOptions *)options;
- (id<NSFastEnumeration>)copyIntoIteratorWithMapper:(ARTRealtimeChannel *(^)(ARTRealtimeChannelInternal *))mapper;

- (instancetype)initWithRealtime:(ARTRealtimeClientInternal *)realtime logger:(ARTInternalLog *)logger;

@property (readonly, getter=getNosyncIterable) id<NSFastEnumeration> nosyncIterable;
@property (nonatomic, readonly, getter=getCollection) NSMutableDictionary<NSString *, ARTRealtimeChannelInternal *> *collection;
- (ARTRealtimeChannelInternal *)_getChannel:(NSString *)name options:(ARTChannelOptions * _Nullable)options addPrefix:(BOOL)addPrefix;

@property (nonatomic) dispatch_queue_t queue;

- (BOOL)exists:(NSString *)name;
- (void)release:(NSString *)name callback:(nullable ARTCallback)errorInfo;
- (void)release:(NSString *)name;

@end

@interface ARTRealtimeChannels ()

@property (nonatomic, readonly) ARTRealtimeChannelsInternal *internal;
@property (nonatomic, readonly) ARTRealtimeClientInternal *realtimeInternal;

- (instancetype)initWithInternal:(ARTRealtimeChannelsInternal *)internal realtimeInternal:(ARTRealtimeClientInternal *)realtimeInternal queuedDealloc:(ARTQueuedDealloc *)dealloc;

@end

NS_ASSUME_NONNULL_END
