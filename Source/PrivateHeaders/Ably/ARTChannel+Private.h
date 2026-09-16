#import "ARTChannel.h"
#import "ARTDataEncoder.h"

NS_ASSUME_NONNULL_BEGIN

@class ARTHttpClientInternal;
@class ARTInternalLog;

@interface ARTChannel()

- (instancetype)initWithName:(NSString *)name andOptions:(ARTChannelOptions *)options rest:(ARTHttpClientInternal *)rest logger:(ARTInternalLog *)logger;

@property (readonly, nullable) ARTChannelOptions *options;

@property (nonatomic, readonly) ARTDataEncoder *dataEncoder;

/// Exposed so that `ARTPluginAPI` can allow plugins to log via this channel.
@property (nonatomic, readonly) ARTInternalLog *logger;

/**
 * Internal method for publishing message on the channel.
 *
 * @param data Can be either:
 *   - A single `ARTMessage` object
 *   - An `NSArray` of `ARTMessage` objects
 *
 * @param callback Callback invoked with the result of the operation (success with ARTPublishResult or error).
 *
 * @discussion Contract - Work already performed on the messages before calling this method:
 *   - Messages have been created from raw parameters (name, data, clientId, extras)
 *   - Data encoding has been applied via `encodeMessageIfNeeded:error:`
 *     (this applies cipher encryption if the channel has cipher params configured)
 *   - Message size validation has been performed via `exceedMaxSize:`
 *   - Encoding errors have been handled and will not reach this method
 *
 * @discussion Contract - Work NOT yet performed (subclass responsibility):
 *   - clientId validation (if required by the transport)
 *   - Channel state checks (e.g., for realtime channels)
 *   - Protocol message creation (for realtime) or REST request construction
 *   - Actual transmission to the server
 *
 * Subclasses (ARTRealtimeChannelInternal, ARTHttpChannelInternal) override this method
 * to implement their specific transport logic.
 */
- (void)internalPostMessages:(id)data callback:(nullable ARTPublishResultCallback)callback;

/**
 * Internal method for sending a mutation request (update, append, delete) for a message.
 *
 * @param message The message to mutate (with action, version, etc. already set).
 * @param params Optional query parameters for the request.
 * @param wrapperSDKAgents Optional wrapper SDK agents for the request.
 * @param callback Callback invoked with the result of the operation (success or error).
 *
 * @discussion Contract - Work already performed on the messages before calling this method:
 *   - Data encoding has been applied per RSL4 via `encodeMessageIfNeeded:error:`
 *     (this applies cipher encryption if the channel has cipher params configured)
 *   - Encoding errors have been handled and will not reach this method
 *
 * @discussion Subclasses (ARTRealtimeChannelInternal, ARTHttpChannelInternal) override this method
 * to implement their specific transport logic for message mutations.
 */
- (void)internalSendEditRequestForMessage:(ARTMessage *)message
                                   params:(nullable NSDictionary<NSString *, ARTStringifiable *> *)params
                         wrapperSDKAgents:(nullable NSStringDictionary *)wrapperSDKAgents
                                 callback:(nullable ARTEditResultCallback)callback;

- (BOOL)exceedMaxSize:(NSArray<ARTBaseMessage *> *)messages;

- (nullable ARTChannelOptions *)options;
- (nullable ARTChannelOptions *)options_nosync;
- (void)setOptions:(ARTChannelOptions *_Nullable)options;
- (void)setOptions_nosync:(ARTChannelOptions *_Nullable)options;

@end

NS_ASSUME_NONNULL_END
