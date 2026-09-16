#import <AblyPubSubDevice/ARTChannels.h>

@class ARTHttpChannel;
@class ARTChannelOptions;

NS_ASSUME_NONNULL_BEGIN

@protocol ARTChannelsDelegate <NSObject>

- (id)makeChannel:(NSString *)channel options:(nullable ARTChannelOptions *)options;

@end

@interface ARTChannels<ChannelType> ()

@property (nonatomic, readonly) NSMutableDictionary<NSString *, ChannelType> *channels;
@property (readonly, getter=getNosyncIterable) id<NSFastEnumeration> nosyncIterable;
@property (nonatomic, readonly) NSString *prefix;

- (NSString *)addPrefix:(NSString *)name;

- (BOOL)_exists:(NSString *)name;
- (ChannelType)_get:(NSString *)name;
- (ChannelType)_getChannel:(NSString *)name options:(ARTChannelOptions * _Nullable)options addPrefix:(BOOL)addPrefix;
- (void)_release:(NSString *)name;

- (instancetype)initWithDelegate:(id<ARTChannelsDelegate>)delegate dispatchQueue:(dispatch_queue_t)queue prefix:(nullable NSString *)prefix;

@end

NS_ASSUME_NONNULL_END
