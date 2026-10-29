#import "ARTLog+Private.h"
#import "ARTNSDate+ARTUtil.h"
#import "ARTGCD.h"
#import "ARTSystemTimeProvider.h"
#import "ARTTimeProvider.h"
#import "ARTStatus.h"

static const char *logLevelName(ARTLogLevel level) {
    switch(level) {
        case ARTLogLevelNone:
            return "";
        case ARTLogLevelVerbose:
            return "VERBOSE";
        case ARTLogLevelDebug:
            return "DEBUG";
        case ARTLogLevelInfo:
            return "INFO";
        case ARTLogLevelWarn:
            return "WARN";
        case ARTLogLevelError:
            return "ERROR";
        default:
            return NULL;
    }
}

@implementation ARTLogLine

- (id)initWithDate:(NSDate *)date level:(ARTLogLevel)level message:(NSString *)message {
    self = [self init];
    if (self) {
        _date = date;
        _level = level;
        _message = message;
    }
    return self;
}

- (NSString *)toString {
    return [NSString stringWithFormat:@"%s: %@", logLevelName(self.level), self.message];
}

- (NSString *)description {
    return [self toString];
}

#pragma mark - NSCoding

- (id)initWithCoder:(NSCoder *)decoder {
    self = [super init];
    if (!self) {
        return nil;
    }
    _date = [decoder decodeObjectForKey:@"date"];
    _level = [[decoder decodeObjectForKey:@"level"] unsignedIntValue];
    _message = [decoder decodeObjectForKey:@"message"];
    return self;
}

- (void)encodeWithCoder:(NSCoder *)encoder {
    [encoder encodeObject:self.date forKey:@"date"];
    [encoder encodeObject:[NSNumber numberWithUnsignedInteger:self.level] forKey:@"level"];
    [encoder encodeObject:self.message forKey:@"message"];
}

@end

@implementation ARTLog {
    NSMutableArray<ARTLogLine *> *_captured;
    NSMutableArray<ARTLogLine *> *_history;
    NSUInteger _historyLines;
    dispatch_queue_t _queue;
    id<ARTTimeProvider> _timeProvider;
}

- (instancetype)init {
    return [self initCapturingOutput:true];
}

- (instancetype)initCapturingOutput:(BOOL)capturing {
    return [self initCapturingOutput:true historyLines:100];
}

- (instancetype)initCapturingOutput:(BOOL)capturing historyLines:(NSUInteger)historyLines {
    if (self = [super init]) {
        // Default
        self->_logLevel = ARTLogLevelWarn;
        if (capturing) {
            self->_captured = [[NSMutableArray alloc] init];
        }
        _history = [[NSMutableArray alloc] init];
        _historyLines = historyLines;
        // Note that we don't provide the ability to mock the time provider used for log timestamps; doing so is more likely to cause confusion to those reading log messages than it is to be useful.
        _queue = dispatch_queue_create("io.ably.log", DISPATCH_QUEUE_SERIAL);
        _timeProvider = [[ARTSystemTimeProvider alloc] init];
    }
    return self;
}

- (void)log:(NSString *const)message withLevel:(const ARTLogLevel)level {
    art_dispatch_sync(_queue, ^{
        ARTLogLine *logLine = [[ARTLogLine alloc] initWithDate:[self->_timeProvider wallClockNow] level:level message:message];
        if (level >= self.logLevel) {
            NSLog(@"%@", [logLine toString]);
            if (self->_captured) {
                [self->_captured addObject:logLine];
            }
        }
        if (self->_historyLines > 0) {
            [self->_history insertObject:logLine atIndex:0];
            if (self->_history.count > self->_historyLines) {
                [self->_history removeLastObject];
            }
        }
    });
}

- (void)logWithError:(ARTErrorInfo *)error {
    [self log:error.message withLevel:ARTLogLevelError];
}

- (NSArray<ARTLogLine *> *)history {
    return _history;
}

- (NSArray *)captured {
    if (!_captured) {
        [ARTException raise:NSInternalInconsistencyException format:@"tried to get captured output in non-capturing instance; use initCapturingOutput:true if you want captured output."];
    }
    return _captured;
}

- (ARTLog *)verboseMode {
    self.logLevel = ARTLogLevelVerbose;
    return self;
}

- (ARTLog *)debugMode {
    self.logLevel = ARTLogLevelDebug;
    return self;
}

- (ARTLog *)warnMode {
    self.logLevel = ARTLogLevelWarn;
    return self;
}

- (ARTLog *)infoMode {
    self.logLevel = ARTLogLevelInfo;
    return self;
}

- (ARTLog *)errorMode {
    self.logLevel = ARTLogLevelError;
    return self;
}

- (void)verbose:(NSString *)format, ... {
    if (self.logLevel <= ARTLogLevelVerbose) {
        va_list args;
        va_start(args, format);
        [self log:[[NSString alloc] initWithFormat:format arguments:args]
        withLevel:ARTLogLevelVerbose];
        va_end(args);
    }
}


- (void)verbose:(const char *)fileName line:(NSUInteger)line message:(NSString *)message, ... {
    if (self.logLevel <= ARTLogLevelVerbose) {
        va_list args;
        va_start(args, message);
        [self log:[[NSString alloc] initWithFormat:[NSString stringWithFormat:@"(%@:%lu) %@", [[NSString stringWithUTF8String:fileName] lastPathComponent], (unsigned long)line, message] arguments:args]
        withLevel:ARTLogLevelVerbose];
        va_end(args);
    }
}

- (void)debug:(NSString *)format, ... {
    if (self.logLevel <= ARTLogLevelDebug) {
        va_list args;
        va_start(args, format);
        [self log:[[NSString alloc] initWithFormat:format arguments:args]
        withLevel:ARTLogLevelDebug];
        va_end(args);
    }
}

- (void)debug:(const char *)fileName line:(NSUInteger)line message:(NSString *)message, ... {
    if (self.logLevel <= ARTLogLevelDebug) {
        va_list args;
        va_start(args, message);
        [self log:[[NSString alloc] initWithFormat:[NSString stringWithFormat:@"(%@:%lu) %@", [[NSString stringWithUTF8String:fileName] lastPathComponent], (unsigned long)line, message] arguments:args]
        withLevel:ARTLogLevelDebug];
        va_end(args);
    }
}

- (void)info:(NSString *)format, ... {
    if (self.logLevel <= ARTLogLevelInfo) {
        va_list args;
        va_start(args, format);
        [self log:[[NSString alloc] initWithFormat:format arguments:args]
        withLevel:ARTLogLevelInfo];
        va_end(args);
    }
}

- (void)warn:(NSString *)format, ... {
    if (self.logLevel <= ARTLogLevelWarn) {
        va_list args;
        va_start(args, format);
        [self log:[[NSString alloc] initWithFormat:format arguments:args]
        withLevel:ARTLogLevelWarn];
        va_end(args);
    }
}

- (void)error:(NSString *)format, ... {
    if (self.logLevel <= ARTLogLevelError) {
        va_list args;
        va_start(args, format);
        [self log:[[NSString alloc] initWithFormat:format arguments:args]
        withLevel:ARTLogLevelError];
        va_end(args);
    }
}

@end
