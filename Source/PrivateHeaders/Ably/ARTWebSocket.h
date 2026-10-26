#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol ARTWebSocketDelegate;
@class ARTInternalLog;

typedef NS_ENUM(NSInteger, ARTWebSocketReadyState) {
    ARTWebSocketReadyStateConnecting   = 0,
    ARTWebSocketReadyStateOpen         = 1,
    ARTWebSocketReadyStateClosing      = 2,
    ARTWebSocketReadyStateClosed       = 3,
};

/**
 This protocol has the subset of ARTSRWebSocket we actually use.
 */
@protocol ARTWebSocket <NSObject>

@property (nonatomic, weak) id <ARTWebSocketDelegate> _Nullable delegate;
@property (nullable, nonatomic) dispatch_queue_t delegateDispatchQueue;
@property (atomic, readonly) ARTWebSocketReadyState readyState;
@property (nullable, nonatomic, readonly) CFHTTPMessageRef receivedHTTPHeaders;

- (void)setDelegateDispatchQueue:(dispatch_queue_t)queue;

- (void)open;
- (void)closeWithCode:(NSInteger)code reason:(nullable NSString *)reason;
- (void)send:(nullable id)message;

@end

/**
 The `ARTWebSocketDelegate` protocol describes the methods that `ARTWebSocket` objects
 call on their delegates to handle status and messsage events.

 This protocol was previously in the SocketRocket library and named ARTSRWebSocketDelegate; all documentation comments have been copied verbatim.
 */
@protocol ARTWebSocketDelegate <NSObject>

@optional

#pragma mark Receive Messages

/**
 Called when any message was received from a web socket.
 This method is suboptimal and might be deprecated in a future release.

 @param webSocket An `ARTWebSocket` object that received a message.
 @param message   Received message. Either a `String` or `NSData`.
 */
- (void)webSocket:(id<ARTWebSocket>)webSocket didReceiveMessage:(id)message;

/**
 Called when a frame was received from a web socket.

 @param webSocket An `ARTWebSocket` object that received a message.
 @param string    Received text in a form of UTF-8 `String`.
 */
- (void)webSocket:(id<ARTWebSocket>)webSocket didReceiveMessageWithString:(NSString *)string;

/**
 Called when a frame was received from a web socket.

 @param webSocket An `ARTWebSocket` object that received a message.
 @param data      Received data in a form of `NSData`.
 */
- (void)webSocket:(id<ARTWebSocket>)webSocket didReceiveMessageWithData:(NSData *)data;

#pragma mark Status & Connection

/**
 Called when a given web socket was open and authenticated.

 @param webSocket An `ARTWebSocket` object that was open.
 */
- (void)webSocketDidOpen:(id<ARTWebSocket>)webSocket;

/**
 Called when a given web socket encountered an error.

 @param webSocket An `ARTWebSocket` object that failed with an error.
 @param error     An instance of `NSError`.
 */
- (void)webSocket:(id<ARTWebSocket>)webSocket didFailWithError:(NSError *)error;

/**
 Called when a given web socket was closed.

 @param webSocket An `ARTWebSocket` object that was closed.
 @param code      Code reported by the server.
 @param reason    Reason in a form of a String that was reported by the server or `nil`.
 @param wasClean  Boolean value indicating whether a socket was closed in a clean state.
 */
- (void)webSocket:(id<ARTWebSocket>)webSocket didCloseWithCode:(NSInteger)code reason:(nullable NSString *)reason wasClean:(BOOL)wasClean;

/**
 Called on receive of a ping message from the server.

 @param webSocket An `ARTWebSocket` object that received a ping frame.
 @param data      Payload that was received or `nil` if there was no payload.
 */
- (void)webSocket:(id<ARTWebSocket>)webSocket didReceivePingWithData:(nullable NSData *)data;

/**
 Called when a pong data was received in response to ping.

 @param webSocket An `ARTWebSocket` object that received a pong frame.
 @param pongData  Payload that was received or `nil` if there was no payload.
 */
- (void)webSocket:(id<ARTWebSocket>)webSocket didReceivePong:(nullable NSData *)pongData;

/**
 Sent before reporting a text frame to be able to configure if it shuold be convert to a UTF-8 String or passed as `NSData`.
 If the method is not implemented - it will always convert text frames to String.

 @param webSocket An `ARTWebSocket` object that received a text frame.

 @return `YES` if text frame should be converted to UTF-8 String, otherwise - `NO`. Default: `YES`.
 */
- (BOOL)webSocketShouldConvertTextFrameToString:(id<ARTWebSocket>)webSocket NS_SWIFT_NAME(webSocketShouldConvertTextFrameToString(_:));

@end

NS_ASSUME_NONNULL_END
