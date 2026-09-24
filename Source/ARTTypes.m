#import "ARTTypes.h"
#import "ARTTypes+Private.h"
#import "ARTInternalLog.h"
#import "ARTDeviceStorage.h"

// MARK: Global helper functions

NSArray<NSString *> *decomposeKey(NSString *key) {
    return [key componentsSeparatedByString:@":"];
}

NSString *encodeBase64(NSString *value) {
    return [[value dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
}

NSString *decodeBase64(NSString *base64) {
    NSData *data = [[NSData alloc] initWithBase64EncodedString:base64 options:0];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

uint64_t dateToMilliseconds(NSDate *date) {
    return (uint64_t)(date.timeIntervalSince1970 * 1000);
}

uint64_t timeIntervalToMilliseconds(NSTimeInterval seconds) {
    return (uint64_t)(seconds * 1000);
}

NSTimeInterval millisecondsToTimeInterval(uint64_t msecs) {
    return ((NSTimeInterval)msecs) / 1000;
}

NSString *generateNonce(void) {
    // Generate two random numbers up to 8 digits long and concatenate them to produce a 16 digit random number
    NSUInteger r1 = arc4random_uniform(100000000);
    NSUInteger r2 = arc4random_uniform(100000000);
    return [NSString stringWithFormat:@"%08lu%08lu", (long)r1, (long)r2];
}

#pragma mark - ARTConnectionStateChange

@implementation ARTConnectionStateChange

- (instancetype)initWithCurrent:(ARTRealtimeConnectionState)current previous:(ARTRealtimeConnectionState)previous event:(ARTRealtimeConnectionEvent)event reason:(ARTErrorInfo *)reason {
    return [self initWithCurrent:current previous:previous event:event reason:reason retryIn:(NSTimeInterval)0];
}

- (instancetype)initWithCurrent:(ARTRealtimeConnectionState)current previous:(ARTRealtimeConnectionState)previous event:(ARTRealtimeConnectionEvent)event reason:(ARTErrorInfo *)reason retryIn:(NSTimeInterval)retryIn {
    return [self initWithCurrent:current previous:previous event:event reason:reason retryIn:retryIn retryAttempt:nil];
}

- (instancetype)initWithCurrent:(ARTRealtimeConnectionState)current previous:(ARTRealtimeConnectionState)previous event:(ARTRealtimeConnectionEvent)event reason:(ARTErrorInfo *)reason retryIn:(NSTimeInterval)retryIn retryAttempt:(ARTRetryAttempt *)retryAttempt {
    self = [self init];
    if (self) {
        _current = current;
        _previous = previous;
        _event = event;
        _reason = reason;
        _retryIn = retryIn;
        _retryAttempt = retryAttempt;
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"%@ - \n\t event: %@; \n\t current: %@; \n\t previous: %@; \n\t reason: %@; \n\t retryIn: %f; \n\t retryAttempt: %@; \n", [super description], ARTRealtimeConnectionEventToStr(_event), ARTRealtimeConnectionStateToStr(_current), ARTRealtimeConnectionStateToStr(_previous), _reason, _retryIn, _retryAttempt];
}

- (void)setRetryIn:(NSTimeInterval)retryIn {
    _retryIn = retryIn;
}

@end

NSString *ARTRealtimeConnectionStateToStr(ARTRealtimeConnectionState state) {
    switch(state) {
        case ARTRealtimeInitialized:
            return @"Initialized"; //0
        case ARTRealtimeConnecting:
            return @"Connecting"; //1
        case ARTRealtimeConnected:
            return @"Connected"; //2
        case ARTRealtimeDisconnected:
            return @"Disconnected"; //3
        case ARTRealtimeSuspended:
            return @"Suspended"; //4
        case ARTRealtimeClosing:
            return @"Closing"; //5
        case ARTRealtimeClosed:
            return @"Closed"; //6
        case ARTRealtimeFailed:
            return @"Failed"; //7
    }
}

NSString *ARTRealtimeConnectionEventToStr(ARTRealtimeConnectionEvent event) {
    switch(event) {
        case ARTRealtimeConnectionEventInitialized:
            return @"Initialized"; //0
        case ARTRealtimeConnectionEventConnecting:
            return @"Connecting"; //1
        case ARTRealtimeConnectionEventConnected:
            return @"Connected"; //2
        case ARTRealtimeConnectionEventDisconnected:
            return @"Disconnected"; //3
        case ARTRealtimeConnectionEventSuspended:
            return @"Suspended"; //4
        case ARTRealtimeConnectionEventClosing:
            return @"Closing"; //5
        case ARTRealtimeConnectionEventClosed:
            return @"Closed"; //6
        case ARTRealtimeConnectionEventFailed:
            return @"Failed"; //7
        case ARTRealtimeConnectionEventUpdate:
            return @"Update"; //8
    }
}

#pragma mark - ARTChannelStateChange

@implementation ARTChannelStateChange

- (instancetype)initWithCurrent:(ARTRealtimeChannelState)current previous:(ARTRealtimeChannelState)previous event:(ARTChannelEvent)event reason:(ARTErrorInfo *)reason {
    return [self initWithCurrent:current previous:previous event:event reason:reason resumed:NO];
}

- (instancetype)initWithCurrent:(ARTRealtimeChannelState)current previous:(ARTRealtimeChannelState)previous event:(ARTChannelEvent)event reason:(ARTErrorInfo *)reason resumed:(BOOL)resumed {
    return [self initWithCurrent:current previous:previous event:event reason:reason resumed:resumed retryAttempt:nil];
}

- (instancetype)initWithCurrent:(ARTRealtimeChannelState)current previous:(ARTRealtimeChannelState)previous event:(ARTChannelEvent)event reason:(ARTErrorInfo *)reason resumed:(BOOL)resumed retryAttempt:(ARTRetryAttempt *)retryAttempt {
    self = [self init];
    if (self) {
        _current = current;
        _previous = previous;
        _event = event;
        _reason = reason;
        _resumed = resumed;
        _retryAttempt = retryAttempt;
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"%@ - \n\t current: %@; \n\t previous: %@; \n\t event: %@; \n\t reason: %@; \n\t resumed: %d; \n\t retryAttempt: %@; \n", [super description], ARTRealtimeChannelStateToStr(_current), ARTRealtimeChannelStateToStr(_previous), ARTChannelEventToStr(_event), _reason, _resumed, _retryAttempt];
}

@end

#pragma mark - ARTChannelMetrics

@implementation ARTChannelMetrics

- (instancetype)initWithConnections:(NSInteger)connections
                         publishers:(NSInteger)publishers
                        subscribers:(NSInteger)subscribers
                presenceConnections:(NSInteger)presenceConnections
                    presenceMembers:(NSInteger)presenceMembers
                presenceSubscribers:(NSInteger)presenceSubscribers
                   objectPublishers:(NSInteger)objectPublishers
                  objectSubscribers:(NSInteger)objectSubscribers {

    if (self = [super init]) {
        _connections = connections;
        _publishers = publishers;
        _subscribers = subscribers;
        _presenceConnections = presenceConnections;
        _presenceMembers = presenceMembers;
        _presenceSubscribers = presenceSubscribers;
        _objectPublishers = objectPublishers;
        _objectSubscribers = objectSubscribers;
    }
    return self;
}

@end

#pragma mark - ARTChannelOccupancy

@implementation ARTChannelOccupancy

- (instancetype)initWithMetrics:(ARTChannelMetrics *)metrics {
    if (self = [super init]) {
        _metrics = metrics;
    }
    return self;
}

@end

#pragma mark - ARTChannelStatus

@implementation ARTChannelStatus

- (instancetype)initWithOccupancy:(ARTChannelOccupancy *)occupancy active:(BOOL)active {
    if (self = [super init]) {
        _occupancy = occupancy;
        _active = active;
    }
    return self;
}

@end

#pragma mark - ARTChannelDetails

@implementation ARTChannelDetails

- (instancetype)initWithChannelId:(NSString *)channelId status:(ARTChannelStatus *)status {
    if (self = [super init]) {
        _channelId = channelId;
        _status = status;
    }
    return self;
}

@end

#pragma mark - ARTEventIdentification

@implementation NSString (ARTEventIdentification)

- (NSString *)identification {
    return self;
}

@end

#pragma mark - ARTJsonCompatible

@implementation NSString (ARTJsonCompatible)

- (NSDictionary *)toJSON:(NSError *_Nullable *_Nullable)error {
    NSData *data = [self dataUsingEncoding:NSUTF8StringEncoding];
    NSError *jsonError = nil;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
    if (jsonError) {
        if (error) {
            *error = jsonError;
        }
        return nil;
    }
    if (![json isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = [NSError errorWithDomain:ARTAblyErrorDomain code:0 userInfo:@{NSLocalizedFailureReasonErrorKey: [NSString stringWithFormat:@"expected JSON object, got %@", [json class]]}];
        }
        return nil;
    }
    return (NSDictionary *)json;
}

- (NSString *)toJSONString {
    return self;
}

@end

@implementation NSDictionary (ARTJsonCompatible)

- (NSDictionary *)toJSON:(NSError *_Nullable *_Nullable)error {
    if (error) {
        *error = nil;
    }
    return self;
}

- (NSString *)toJSONString {
    NSError *err = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:self options:0 error:&err];
    if (err) {
        return nil;
    }
    NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    return jsonString;
}

@end

@implementation NSURL (ARTLog)

- (NSString *)description {
    return [NSString stringWithFormat:@"%@", self.absoluteString];
}

@end

NSString *ARTRealtimeChannelStateToStr(ARTRealtimeChannelState state) {
    switch (state) {
        case ARTRealtimeChannelInitialized:
            return @"Initialized"; //0
        case ARTRealtimeChannelAttaching:
            return @"Attaching"; //1
        case ARTRealtimeChannelAttached:
            return @"Attached"; //2
        case ARTRealtimeChannelDetaching:
            return @"Detaching"; //3
        case ARTRealtimeChannelDetached:
            return @"Detached"; //4
        case ARTRealtimeChannelSuspended:
            return @"Suspended"; //5
        case ARTRealtimeChannelFailed:
            return @"Failed"; //6
    }
}

NSString *ARTChannelEventToStr(ARTChannelEvent event) {
    switch (event) {
        case ARTChannelEventInitialized:
            return @"Initialized"; //0
        case ARTChannelEventAttaching:
            return @"Attaching"; //1
        case ARTChannelEventAttached:
            return @"Attached"; //2
        case ARTChannelEventDetaching:
            return @"Detaching"; //3
        case ARTChannelEventDetached:
            return @"Detached"; //4
        case ARTChannelEventSuspended:
            return @"Suspended"; //5
        case ARTChannelEventFailed:
            return @"Failed"; //6
        case ARTChannelEventUpdate:
            return @"Update"; //7
    }
}

@implementation NSDictionary (ARTURLQueryItemAdditions)

- (NSArray<NSURLQueryItem *> *)art_asURLQueryItems {
    NSMutableArray<NSURLQueryItem *> *items = [NSMutableArray new];
    for (id key in [self allKeys]) {
        id value = [self valueForKey:key];
        if ([key isKindOfClass:[NSString class]] && [value isKindOfClass:[NSString class]]) {
            [items addObject:[NSURLQueryItem queryItemWithName:key value:value]];
        }
    }
    return items;
}

@end

@implementation NSMutableArray (ARTQueueAdditions)

- (void)art_enqueue:(id)object {
    [self addObject:object];
}

- (id)art_dequeue {
    id item = [self firstObject];
    if (item) {
        [self removeObjectAtIndex:0];
    }
    return item;
}

- (id)art_peek {
    return [self firstObject];
}

@end

#pragma mark - NSString (ARTUtilities)

@implementation NSString (ARTUtilities)

- (NSString *)art_shortString {
    NSRange stringRange = {0, MIN([self length], 1000)}; //1KB
    stringRange = [self rangeOfComposedCharacterSequencesForRange:stringRange];
    return [self substringWithRange:stringRange];
}

- (NSString *)art_base64Encoded {
    return encodeBase64(self);
}

@end

#pragma mark - NSDate (ARTUtilities)

@implementation NSDate (ARTUtilities)

+ (NSDate *)art_dateWithMillisecondsSince1970:(uint64_t)msecs {
    return [NSDate dateWithTimeIntervalSince1970:millisecondsToTimeInterval(msecs)];
}

@end

@interface ARTCancellableFromCallback : NSObject<ARTCancellable>
+(instancetype)new NS_UNAVAILABLE;
-(instancetype)init NS_UNAVAILABLE;
-(instancetype)initWithCallback:(ARTResultCallback)callback;
@property(nonatomic, readonly) ARTResultCallback wrapper;
@end

@implementation ARTCancellableFromCallback {
    id _lock;

    // _callback will be nil once either cancel or invoke has been called on
    // this instance.
    volatile ARTResultCallback _callback;
}

@synthesize wrapper = _wrapper;

-(instancetype)initWithCallback:(const ARTResultCallback)callback {
    if (!callback) {
        [NSException raise:NSInternalInconsistencyException format:@"callback is nil."];
    }
    self = [super init];
    if (!self) {
        return nil;
    }

    _lock = [NSObject new];
    _callback = callback;

    __weak ARTCancellableFromCallback * _cancellable = self;
    _wrapper = ^(const id result, NSError *const error) {
        // _cancellable is a weak self so may, legitimately, be nil now.
        ARTCancellableFromCallback *const cancellable = _cancellable;
        [cancellable invokeWithResult:result error:error];
    };

    return self;
}

-(void)cancel {
    @synchronized (_lock) {
        _callback = nil;
    }
}

-(void)invokeWithResult:(const id)result error:(NSError *const)error {
    ARTResultCallback callback;

    @synchronized (_lock) {
        callback = _callback;
        _callback = nil;
    }

    if (callback) {
        callback(result, error);
    }
}

@end

@implementation NSObject (ARTArchive)

- (nullable NSData *)art_archiveWithLogger:(nullable ARTInternalLog *)logger {
    NSError *error;
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:self requiringSecureCoding:false error:&error];
    if (error) {
        ARTLogError(logger, @"%@ archive failed: %@", [self class], error);
    }
    return data;
}

+ (nullable id)art_unarchiveFromData:(NSData *)data withLogger:(nullable ARTInternalLog *)logger {
    NSSet* allowedTypes = [NSSet setWithArray:@[ [NSArray class], [NSDictionary class], self]];
    NSError *error;
    id result = [NSKeyedUnarchiver unarchivedObjectOfClasses:allowedTypes fromData:data error:&error];
    if (error) {
        ARTLogError(logger, @"%@ unarchive failed: %@", self, error);
    }
    return result;
}

+ (nullable id)art_unarchiveFromStorage:(id<ARTDeviceStorage>)storage
                                    key:(NSString *)key
                             withLogger:(nullable ARTInternalLog *)logger {
    NSData *data = [storage objectForKey:key];
    if (data == nil) {
        ARTLogDebug(logger, @"%@ unarchive skipped: no persisted data for key %@", self, key);
        return nil;
    }
    return [self art_unarchiveFromData:data withLogger:logger];
}

@end

NSObject<ARTCancellable> * artCancellableFromCallback(const ARTResultCallback callback, ARTResultCallback *const wrapper) {
    if (!wrapper) {
        [NSException raise:NSInternalInconsistencyException format:@"wrapper is nil."];
    }

    ARTCancellableFromCallback *const cancellable =
        [[ARTCancellableFromCallback alloc] initWithCallback:callback];
    *wrapper = cancellable.wrapper;
    return cancellable;
}
