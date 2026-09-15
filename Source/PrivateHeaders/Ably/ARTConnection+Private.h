#import <AblyPubSubDevice/ARTConnection.h>
#import <AblyPubSubDevice/ARTEventEmitter.h>
#import <AblyPubSubDevice/ARTTypes.h>
#import "ARTQueuedDealloc.h"

NS_ASSUME_NONNULL_BEGIN

@class ARTRealtimeInternal;
@class ARTInternalLog;

@interface ARTConnectionRecoveryKey : NSObject

@property (readonly, nonatomic) NSString *connectionKey;
@property (readonly, nonatomic) int64_t msgSerial;
@property (readonly, nonatomic) NSDictionary<NSString *, NSString *> *channelSerials;

- (instancetype)initWithConnectionKey:(NSString *)connectionKey
                            msgSerial:(int64_t)msgSerial
                       channelSerials:(NSDictionary<NSString *, NSString *> *)channelSerials;

- (NSString *)jsonString;
+ (nullable ARTConnectionRecoveryKey *)fromJsonString:(NSString *)json error:(NSError *_Nullable *_Nullable)errorPtr;

@end

@interface ARTConnectionInternal : NSObject

@property (nullable, readonly, nonatomic) NSString *id;
@property (nullable, readonly, nonatomic) NSString *key;
@property (readonly, nonatomic) NSInteger maxMessageSize;
@property (readonly, nonatomic) ARTRealtimeConnectionState state;
@property (nullable, readonly, nonatomic) ARTErrorInfo *errorReason;

- (instancetype)initWithRealtime:(ARTRealtimeInternal *)realtime logger:(ARTInternalLog *)logger;

- (nullable NSString *)id_nosync;
- (nullable NSString *)key_nosync;
- (BOOL)isActive_nosync;
- (ARTRealtimeConnectionState)state_nosync;
- (nullable ARTErrorInfo *)errorReason_nosync;
- (nullable ARTErrorInfo *)error_nosync;
- (nullable NSString *)createRecoveryKey_nosync;

@property (readonly, nonatomic) ARTEventEmitter<ARTEvent *, ARTConnectionStateChange *> *eventEmitter;
@property(weak, nonatomic) ARTRealtimeInternal* realtime; // weak because realtime owns self

- (void)setId:(NSString *_Nullable)newId;
- (void)setKey:(NSString *_Nullable)key;
- (void)setMaxMessageSize:(NSInteger)maxMessageSize;
- (void)setState:(ARTRealtimeConnectionState)state;
- (void)setErrorReason:(ARTErrorInfo *_Nullable)errorReason;

- (void)emit:(ARTRealtimeConnectionEvent)event with:(ARTConnectionStateChange *)data;

@property (readonly, nonatomic) dispatch_queue_t queue;

- (nullable NSString *)createRecoveryKey;

- (void)connect;

- (void)close;

- (void)ping:(ARTCallback)callback;

#pragma mark ARTEventEmitter

/**
 * Embeds an `ARTEventEmitter` object.
 */
ART_EMBED_INTERFACE_EVENT_EMITTER(ARTRealtimeConnectionEvent, ARTConnectionStateChange *)

@end

@interface ARTConnection ()

@property (nonatomic, readonly) ARTConnectionInternal *internal;

- (instancetype)initWithInternal:(ARTConnectionInternal *)internal queuedDealloc:(ARTQueuedDealloc *)dealloc;

@property (readonly) ARTConnectionInternal *internal_nosync;

@end

NS_ASSUME_NONNULL_END
