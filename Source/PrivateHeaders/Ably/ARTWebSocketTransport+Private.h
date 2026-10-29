#import "ARTWebSocketTransport.h"
#import "ARTSRWebSocket.h"
#import "ARTEncoder.h"
#import <AblyPubSubDevice/ARTAuth.h>
#import "ARTWebSocket.h"

NS_ASSUME_NONNULL_BEGIN

@interface ARTWebSocketTransport () <ARTWebSocketDelegate>

// From RestClient
@property (readwrite, nonatomic) id<ARTEncoder> encoder;
@property (readonly, nonatomic) ARTInternalLog *logger;
@property (readonly, nonatomic) ARTClientOptions *options;

@property (readwrite, nonatomic, nullable) id<ARTWebSocket> websocket;
@property (readwrite, nonatomic, nullable) NSURL *websocketURL;

- (NSURL *)setupWebSocket:(NSDictionary<NSString *, NSURLQueryItem *> *)params withOptions:(ARTClientOptions *)options resumeKey:(NSString *_Nullable)resumeKey;

- (void)setState:(ARTRealtimeTransportState)state;

/// This is called as a result of a call to `-connectWithToken:` or `-connectWithKey:`. It calls (asynchronously on a queue internal to this transport) `-open` on the underlying `ARTWebSocket`.
///
/// Exposed so that test subclasses can override and replace or wrap in additional logic.
- (void)openWebSocket;

@end

#pragma mark - ARTEvent

@interface ARTEvent (TransportState)
- (instancetype)initWithTransportState:(ARTRealtimeTransportState)value;
+ (instancetype)newWithTransportState:(ARTRealtimeTransportState)value;

@end

NS_ASSUME_NONNULL_END
