#import "ARTPush+Private.h"
#import "ARTDeviceDetails.h"
#import "ARTDevicePushDetails.h"
#import "ARTHttpClient+Private.h"
#import "ARTJsonEncoder.h"
#import "ARTJsonLikeEncoder.h"
#import "ARTEventEmitter.h"
#if TARGET_OS_IOS
#import <UIKit/UIKit.h>
#import "ARTPushActivationStateMachine+Private.h"
#endif
#import "ARTPushAdmin.h"
#import "ARTPushActivationEvent.h"
#import "ARTClientOptions+Private.h"
#import "ARTPushAdmin+Private.h"
#import "ARTLocalDevice+Private.h"
#import "ARTDeviceStorage.h"
#import "ARTRealtimeClient+Private.h"
#import "ARTInternalLog.h"
#import "ARTGCD.h"

@implementation ARTPush {
    ARTQueuedDealloc *_dealloc;
}

- (instancetype)initWithInternal:(ARTPushInternal *)internal queuedDealloc:(ARTQueuedDealloc *)dealloc {
    self = [super init];
    if (self) {
        _internal = internal;
        _dealloc = dealloc;
    }
    return self;
}

- (ARTPushAdmin *)admin {
    return [[ARTPushAdmin alloc] initWithInternal:_internal.admin queuedDealloc:_dealloc];
}

#if TARGET_OS_IOS

+ (void)didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken realtime:(ARTRealtimeClient *)realtime; {
    return [ARTPushInternal didRegisterForRemoteNotificationsWithDeviceToken:deviceToken realtime:realtime];
}

+ (void)didFailToRegisterForRemoteNotificationsWithError:(NSError *)error realtime:(ARTRealtimeClient *)realtime; {
    return [ARTPushInternal didFailToRegisterForRemoteNotificationsWithError:error realtime:realtime];
}

+ (void)didRegisterForLocationNotificationsWithDeviceToken:(NSData *)deviceToken realtime:(ARTRealtimeClient *)realtime; {
    return [ARTPushInternal didRegisterForLocationNotificationsWithDeviceToken:deviceToken realtime:realtime];
}

+ (void)didFailToRegisterForLocationNotificationsWithError:(NSError *)error realtime:(ARTRealtimeClient *)realtime; {
    return [ARTPushInternal didFailToRegisterForLocationNotificationsWithError:error realtime:realtime];
}

- (void)registerPushToStartToken:(NSData *)token {
    [_internal registerPushToStartToken:token];
}

- (void)activate {
    [_internal activate];
}

- (void)deactivate {
    [_internal deactivate];
}

#endif

@end

@implementation ARTPushInternal {
    __weak ARTHttpClientInternal *_rest; // weak because rest owns self
    ARTInternalLog *_logger;
    dispatch_queue_t _queue;
    ARTPushActivationStateMachine *_activationMachine;
    NSLock *_activationMachineLock;
}

- (instancetype)initWithRest:(ARTHttpClientInternal *)rest logger:(ARTInternalLog *)logger {
    if (self = [super init]) {
        _rest = rest;
        _logger = logger;
        _queue = rest.queue;
        _admin = [[ARTPushAdminInternal alloc] initWithRest:rest logger:logger];
        _activationMachine = nil;
        _activationMachineLock = [[NSLock alloc] init];
        _activationMachineLock.name = @"ActivationMachineLock";
    }
    return self;
}

#if TARGET_OS_IOS

- (void)getActivationMachine:(void (^)(ARTPushActivationStateMachine *_Nullable const))block {
    if (!block) {
        [NSException raise:NSInvalidArgumentException
                    format:@"block is nil."];
    }

    if (![_activationMachineLock lockBeforeDate:[NSDate dateWithTimeIntervalSinceNow:60]]) {
        block(nil);
        return;
    }

    void (^callbackWithUnlock)(ARTPushActivationStateMachine *const machine) = ^(ARTPushActivationStateMachine *machine) {
        [self->_activationMachineLock unlock];
        block(machine);
    };

    if (_activationMachine == nil) {
        const id<ARTPushRegistererDelegate, NSObject> delegate = _rest.options.pushRegistererDelegate;
        if (delegate) {
            callbackWithUnlock([self createActivationStateMachineWithDelegate:delegate]);
        }
        else {
            __block id extendedLifetimeRest = _rest;

            if (!extendedLifetimeRest) {
                // My understanding is that this shouldn't be possible: either getActivationMachine is being invoked as a result of a user's interaction with an ARTPush public method, in which case our ARTQueuedDealloc mechanism should have kept _rest alive, or it's being invoked _by_ _rest (upon fetching a token) or it's being invoked by ARTRealtimeClientInternal, which is keeping _rest alive.
                ARTLogWarn(_logger, @"_rest has already been deallocated in getActivationMachine:, skipping creation of machine and calling callback with nil");
                callbackWithUnlock(nil);
                return;
            }

            art_dispatch_async(dispatch_get_main_queue(), ^{
                // -[UIApplication delegate] is an UI API call, so needs to be called from main thread.
                const id legacyDelegate = UIApplication.sharedApplication.delegate;

                // After this dispatch to the main queue, I believe there is no longer any mechanism guaranteed to be keeping _rest alive, hence our extendedLifetimeRest variable, which keeps _rest alive for long enough to ensure that when createActivationStateMachineWithDelegate creates the state machine, it passes it a non-nil _rest, as its initializer's contract requires.

                art_dispatch_async(self->_queue, ^{
                    callbackWithUnlock([self createActivationStateMachineWithDelegate:legacyDelegate]);
                    extendedLifetimeRest = nil;
                });
            });
        }
    }
    else {
        callbackWithUnlock(_activationMachine);
    }
}

- (ARTPushActivationStateMachine *)createActivationStateMachineWithDelegate:(const id<ARTPushRegistererDelegate, NSObject>)delegate {
    if (_activationMachine) {
        [NSException raise:NSInternalInconsistencyException
                    format:@"_activationMachine already set."];
    }

    _activationMachine = [[ARTPushActivationStateMachine alloc] initWithRest:self->_rest delegate:delegate logger:_logger];
    return _activationMachine;
}

- (ARTPushActivationStateMachine *)activationMachine {
    if (![_activationMachineLock tryLock]) {
        [NSException raise:NSInternalInconsistencyException
                    format:@"Failed to immediately acquire lock for internal testing purposes."];
    }

    ARTPushActivationStateMachine *const machine = _activationMachine;
    if (!machine) {
        [NSException raise:NSInternalInconsistencyException
                    format:@"There is no activation machine for internal testing purposes."];
    }

    [_activationMachineLock unlock];

    return machine;
}

+ (void)didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceTokenData restInternal:(ARTHttpClientInternal *)rest {
    ARTLogDebug(rest.logger_onlyForUseInClassMethodsAndTests, @"ARTPush: device token data received: %@", [deviceTokenData base64EncodedStringWithOptions:0]);
    [rest setAndPersistAPNSDeviceTokenData:deviceTokenData tokenType:ARTAPNSDeviceDefaultTokenType];
}

+ (void)didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken realtime:(ARTRealtimeClient *)realtime {
    [realtime internalAsync:^(ARTRealtimeClientInternal *realtime) {
        [ARTPushInternal didRegisterForRemoteNotificationsWithDeviceToken:deviceToken restInternal:realtime.rest];
    }];
}

+ (void)didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken rest:(ARTHttpClient *)rest {
    [rest internalAsync:^(ARTHttpClientInternal *rest) {
        [ARTPushInternal didRegisterForRemoteNotificationsWithDeviceToken:deviceToken restInternal:rest];
    }];
}

+ (void)didFailToRegisterForRemoteNotificationsWithError:(NSError *)error restInternal:(ARTHttpClientInternal *)rest {
    ARTLogError(rest.logger_onlyForUseInClassMethodsAndTests, @"ARTPush: device token not received (%@)", [error localizedDescription]);
    [rest.push getActivationMachine:^(ARTPushActivationStateMachine *_Nullable stateMachine) {
        [stateMachine sendEvent:[ARTPushActivationEventGettingPushDeviceDetailsFailed newWithError:[ARTErrorInfo createFromNSError:error]]];
    }];
}

+ (void)didFailToRegisterForRemoteNotificationsWithError:(NSError *)error realtime:(ARTRealtimeClient *)realtime {
    [realtime internalAsync:^(ARTRealtimeClientInternal *realtime) {
        [ARTPushInternal didFailToRegisterForRemoteNotificationsWithError:error restInternal:realtime.rest];
    }];
}

+ (void)didFailToRegisterForRemoteNotificationsWithError:(NSError *)error rest:(ARTHttpClient *)rest {
    [rest internalAsync:^(ARTHttpClientInternal *rest) {
        [ARTPushInternal didFailToRegisterForRemoteNotificationsWithError:error restInternal:rest];
    }];
}

+ (void)didRegisterForLocationNotificationsWithDeviceToken:(NSData *)deviceTokenData restInternal:(ARTHttpClientInternal *)rest {
    ARTLogDebug(rest.logger_onlyForUseInClassMethodsAndTests, @"ARTPush: location push device token data received: %@", [deviceTokenData base64EncodedStringWithOptions:0]);
    [rest setAndPersistAPNSDeviceTokenData:deviceTokenData tokenType:ARTAPNSDeviceLocationTokenType];
}

+ (void)didRegisterForLocationNotificationsWithDeviceToken:(NSData *)deviceToken realtime:(ARTRealtimeClient *)realtime {
    [realtime internalAsync:^(ARTRealtimeClientInternal *realtime) {
        [ARTPushInternal didRegisterForLocationNotificationsWithDeviceToken:deviceToken restInternal:realtime.rest];
    }];
}

+ (void)didRegisterForLocationNotificationsWithDeviceToken:(NSData *)deviceToken rest:(ARTHttpClient *)rest {
    [rest internalAsync:^(ARTHttpClientInternal *rest) {
        [ARTPushInternal didRegisterForLocationNotificationsWithDeviceToken:deviceToken restInternal:rest];
    }];
}

+ (void)didFailToRegisterForLocationNotificationsWithError:(NSError *)error restInternal:(ARTHttpClientInternal *)rest {
    ARTLogError(rest.logger_onlyForUseInClassMethodsAndTests, @"ARTPush: location push device token not received (%@)", [error localizedDescription]);
    [rest.push getActivationMachine:^(ARTPushActivationStateMachine *_Nullable stateMachine) {
        [stateMachine sendEvent:[ARTPushActivationEventGettingPushDeviceDetailsFailed newWithError:[ARTErrorInfo createFromNSError:error]]];
    }];
}

+ (void)didFailToRegisterForLocationNotificationsWithError:(NSError *)error realtime:(ARTRealtimeClient *)realtime {
    [realtime internalAsync:^(ARTRealtimeClientInternal *realtime) {
        [ARTPushInternal didFailToRegisterForLocationNotificationsWithError:error restInternal:realtime.rest];
    }];
}

+ (void)didFailToRegisterForLocationNotificationsWithError:(NSError *)error rest:(ARTHttpClient *)rest {
    [rest internalAsync:^(ARTHttpClientInternal *rest) {
        [ARTPushInternal didFailToRegisterForLocationNotificationsWithError:error restInternal:rest];
    }];
}

- (void)registerPushToStartToken:(NSData *)token {
    [_rest setAndPersistAPNSDeviceTokenData:token tokenType:ARTAPNSDevicePushToStartTokenType];
}

- (void)activate {
    [self getActivationMachine:^(ARTPushActivationStateMachine *_Nullable stateMachine) {
        [stateMachine sendEvent:[ARTPushActivationEventCalledActivate new]];
    }];
}

- (void)deactivate {
    [self getActivationMachine:^(ARTPushActivationStateMachine *_Nullable stateMachine) {
        [stateMachine sendEvent:[ARTPushActivationEventCalledDeactivate new]];
    }];
}

#endif

@end
