#import <Foundation/Foundation.h>

#import <AblyPubSubDevice/ARTTypes.h>

NS_ASSUME_NONNULL_BEGIN

/// :nodoc:
typedef NS_ENUM(NSUInteger, ARTLogLevel) {
    ARTLogLevelVerbose,
    ARTLogLevelDebug,
    ARTLogLevelInfo,
    ARTLogLevelWarn,
    ARTLogLevelError,
    ARTLogLevelNone
} NS_SWIFT_NAME(LogLevel);

/// :nodoc:
NS_SWIFT_NAME(Log)
@interface ARTLog : NSObject

@property (nonatomic) ARTLogLevel logLevel;

- (void)log:(NSString *)message withLevel:(ARTLogLevel)level;

// This method should be considered obsolete. It is no longer called by the ably-cocoa SDK.
- (void)logWithError:(ARTErrorInfo *)error;

- (ARTLog *)verboseMode;
- (ARTLog *)debugMode;
- (ARTLog *)infoMode;
- (ARTLog *)warnMode;
- (ARTLog *)errorMode;

@end

/// :nodoc:
@interface ARTLog (Shorthand)

// These methods should be considered obsolete. They are no longer called by the ably-cocoa SDK.

- (void)verbose:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);
- (void)verbose:(const char *)fileName line:(NSUInteger)line message:(NSString *)message, ... NS_FORMAT_FUNCTION(3,4);
- (void)debug:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);
- (void)debug:(const char *)fileName line:(NSUInteger)line message:(NSString *)message, ... NS_FORMAT_FUNCTION(3,4);
- (void)info:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);
- (void)warn:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);
- (void)error:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);

@end

NS_ASSUME_NONNULL_END
