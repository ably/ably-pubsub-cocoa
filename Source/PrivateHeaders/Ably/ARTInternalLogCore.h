@import Foundation;
#import <AblyPubSubDevice/ARTLog.h>

@protocol ARTVersion2Log;
@class ARTClientOptions;

NS_ASSUME_NONNULL_BEGIN

/**
 `ARTInternalLogCore` is the type underlying `ARTInternalLog`, and defines the logging functionality available to components of the SDK.

 It's responsible for receiving log messages from SDK components, performing additional processing on these messages, and forwarding the result to an object conforming to the `ARTVersion2Log` protocol.

 This protocol exists to give internal SDK components access to a rich and useful logging interface, whilst minimising the complexity (and hence the implementation burden for users of the SDK) of the `ARTVersion2Log` protocol. It also allows us to evolve the logging interface used internally without introducing breaking changes for users of the SDK.

 The initial interface of `ARTInternalLogCore` more or less mirrors that of the `ARTLog` class, for compatibility with existing internal SDK code. However, it will evolve as we gather requirements for the information logged by the SDK — see issues #1623 and #1624.
 */
NS_SWIFT_NAME(InternalLogCore)
@protocol ARTInternalLogCore <NSObject>

/**
 - Parameters:
   - fileName: The absolute path of the file from which the log message was emitted (for example, as returned by the `__FILE__` macro).
 */
- (void)log:(NSString *)message withLevel:(ARTLogLevel)level file:(const char *)fileName line:(NSInteger)line;

@property (nonatomic) ARTLogLevel logLevel;

@end

/**
 The implementation of `ARTInternalLogCore` that should be used in non-test code.
 */
NS_SWIFT_NAME(DefaultInternalLogCore)
@interface ARTDefaultInternalLogCore: NSObject<ARTInternalLogCore>

/**
 Creates a logger which forwards its generated messages to the given logger.
 */
- (instancetype)initWithLogger:(id<ARTVersion2Log>)logger NS_DESIGNATED_INITIALIZER;
/**
 A convenience initializer which creates a logger initialized with an instance of `ARTLogAdapter` which wraps the given client options' `logHandler`.

 Also, if the client options' `logLevel` is anything other than `ARTLogLevelNone`, this initializer will set the client options' `logHandler`'s `logLevel` such that it matches the client options' `logLevel`. (We offer no judgement here on whether this is the right thing to do or the right place to do it; this is pre-existing behaviour simply moved from elsewhere in the codebase.)
 */
- (instancetype)initWithClientOptions:(ARTClientOptions *)clientOptions;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
