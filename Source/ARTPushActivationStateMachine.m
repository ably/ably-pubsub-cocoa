#import "ARTPushActivationStateMachine+Private.h"
#import "ARTPush.h"
#import "ARTPushActivationEvent.h"
#import "ARTPushActivationState.h"
#import "ARTHttpClient+Private.h"
#import "ARTInternalLog.h"
#import "ARTJsonEncoder.h"
#import "ARTJsonLikeEncoder.h"
#import "ARTTypes.h"
#import "ARTTypes+Private.h"
#import "ARTLocalDevice+Private.h"
#import "ARTDeviceStorage.h"
#import "ARTDevicePushDetails.h"
#import "ARTDeviceIdentityTokenDetails.h"
#import "ARTNSMutableRequest+ARTPush.h"
#import "ARTAuth+Private.h"
#import "ARTGCD.h"

// These keys are referenced by `ARTLocalDeviceStorage` (built on all
// platforms) for key routing, so the symbols must be defined regardless of
// `TARGET_OS_IOS`. The rest of the state machine is iOS-only.
NSString *const ARTPushActivationCurrentStateKey = @"ARTPushActivationCurrentState";
NSString *const ARTPushActivationPendingEventsKey = @"ARTPushActivationPendingEvents";

#if TARGET_OS_IOS

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ARTPushActivationStateMachine ()

@property (nonatomic, readonly) ARTInternalLog *logger;

@end

NS_ASSUME_NONNULL_END

@implementation ARTPushActivationStateMachine {
    ARTPushActivationEvent *_lastHandledEvent;
    ARTPushActivationState *_current;
    dispatch_queue_t _queue;
    dispatch_queue_t _userQueue;
    NSMutableArray<ARTPushActivationEvent *> *_pendingEvents;
    id<ARTDeviceStorage> _storage;
}

- (instancetype)initWithRest:(ARTHttpClientInternal *const)rest
                    delegate:(const id<ARTPushRegistererDelegate, NSObject>)delegate
                      logger:(ARTInternalLog *)logger {
    if (self = [super init]) {
        _rest = rest;
        _delegate = delegate;
        _queue = _rest.queue;
        _userQueue = _rest.userQueue;
        _logger = logger;

        // RSH3h: ensure to initialise the device _before_ the state fields are initialised
        ARTLocalDevice *localDevice = rest.device_nosync;
        _storage = localDevice.storage;

        // Unarchiving
        _current = [ARTPushActivationState art_unarchiveFromStorage:_storage
                                                                key:ARTPushActivationCurrentStateKey
                                                         withLogger:logger];
        if (!_current) {
            _current = [[ARTPushActivationStateNotActivated alloc] initWithMachine:self logger:logger];
        } else {
            if ([_current isKindOfClass:[ARTPushActivationDeprecatedPersistentState class]]) {
                _current = [((ARTPushActivationDeprecatedPersistentState *) _current) migrate];
            }
            _current.machine = self;
        }
        _pendingEvents = [ARTPushActivationEvent art_unarchiveFromStorage:_storage
                                                                      key:ARTPushActivationPendingEventsKey
                                                               withLogger:logger];
        if (!_pendingEvents) {
            _pendingEvents = [NSMutableArray array];
        }

        // Due to bug #966, old versions of the library might have led us to an illegal
        // persisted state: we have a deviceToken, but the persisted push state is WaitingForPushDeviceDetails.
        // So we need to re-emit the GotPushDeviceDetails event that led us there.
        if ([_current isKindOfClass:[ARTPushActivationStateWaitingForPushDeviceDetails class]] && localDevice.apnsDeviceToken != nil) {
            ARTLogDebug(logger, @"ARTPush: re-emitting stored device details for stuck state machine");
            [self handleEvent:[ARTPushActivationEventGotPushDeviceDetails new]];
        }
    }
    return self;
}

- (NSArray<ARTPushActivationEvent *> *)pendingEvents {
    __block NSArray<ARTPushActivationEvent *> *ret;
    art_dispatch_sync(_queue, ^{
        ret = [self->_pendingEvents copy];
    });
    return ret;
}

- (ARTPushActivationEvent *)lastEvent {
    __block ARTPushActivationEvent *ret;
    art_dispatch_sync(_queue, ^{
        ret = [self lastEvent_nosync];
    });
    return ret;
}

- (ARTPushActivationEvent *)lastEvent_nosync {
    return _lastHandledEvent;
}

- (ARTPushActivationState *)current {
    __block ARTPushActivationState *ret;
    art_dispatch_sync(_queue, ^{
        ret = [self current_nosync];
    });
    return ret;
}

- (ARTPushActivationState *)current_nosync {
    return _current;
}

- (void)sendEvent:(ARTPushActivationEvent *)event {
art_dispatch_async(_queue, ^{
    [self handleEvent:event];
});
}

- (void)handleEvent:(nonnull ARTPushActivationEvent *)event {
    ARTLogDebug(_logger, @"%@: handling event %@ from %@", NSStringFromClass(self.class), NSStringFromClass(event.class), NSStringFromClass(_current.class));
    _lastHandledEvent = event;

    if (self.onEvent) self.onEvent(event, _current);
    ARTPushActivationState *maybeNext = [_current transition:event];

    if (maybeNext == nil) {
        ARTLogDebug(_logger, @"%@: enqueuing event: %@", NSStringFromClass(self.class), NSStringFromClass(event.class));
        [_pendingEvents addObject:event];
        return;
    }
    ARTLogDebug(_logger, @"%@: transition: %@ -> %@", NSStringFromClass(self.class), NSStringFromClass(_current.class), NSStringFromClass(maybeNext.class));
    if (self.transitions) self.transitions(event, _current, maybeNext);
    _current = maybeNext;

    while (true) {
        ARTPushActivationEvent *pending = [_pendingEvents art_peek];
        if (pending == nil) {
            break;
        }
        ARTLogDebug(_logger, @"%@: attempting to consume pending event: %@", NSStringFromClass(self.class), NSStringFromClass(pending.class));
        maybeNext = [_current transition:pending];
        if (maybeNext == nil) {
            break;
        }
        [_pendingEvents art_dequeue]; // consuming event

        ARTLogDebug(_logger, @"%@: transition: %@ -> %@", NSStringFromClass(self.class), NSStringFromClass(_current.class), NSStringFromClass(maybeNext.class));
        if (self.transitions) self.transitions(event, _current, maybeNext);
        _current = maybeNext;
    }

    [self persist];
}

- (void)persist {
    NSData *stateData = nil;
    if ([_current isKindOfClass:[ARTPushActivationPersistentState class]]) {
        stateData = [_current art_archiveWithLogger:_logger];
    }
    NSData *eventsData = [_pendingEvents art_archiveWithLogger:_logger];
    [_storage performBatchUpdate:^(id<ARTDeviceStorage> writer) {
        if (stateData != nil) {
            [writer setObject:stateData forKey:ARTPushActivationCurrentStateKey];
        }
        [writer setObject:eventsData forKey:ARTPushActivationPendingEventsKey];
    }];
}

- (void)deviceRegistration:(ARTErrorInfo *)error {
    #if TARGET_OS_IOS
    ARTLocalDevice *local = _rest.device_nosync;

    const id<ARTPushRegistererDelegate, NSObject> delegate = self.delegate;

    // Custom register
    if ([delegate respondsToSelector:@selector(ablyPushCustomRegister:deviceDetails:callback:)]) {
        art_dispatch_async(_userQueue, ^{
            [delegate ablyPushCustomRegister:error deviceDetails:local callback:^(ARTDeviceIdentityTokenDetails *identityTokenDetails, ARTErrorInfo *error) {
                if (error) {
                    // Failed
                    [self sendEvent:[ARTPushActivationEventGettingDeviceRegistrationFailed newWithError:error]];
                }
                else if (identityTokenDetails) {
                    // Success
                    [self sendEvent:[ARTPushActivationEventGotDeviceRegistration newWithIdentityTokenDetails:identityTokenDetails]];
                }
                else {
                    ARTErrorInfo *missingIdentityTokenError = [ARTErrorInfo createWithCode:0 message:@"Device Identity Token Details is expected"];
                    [self sendEvent:[ARTPushActivationEventGettingDeviceRegistrationFailed newWithError:missingIdentityTokenError]];
                }
            }];
        });
        return;
    }

    void (^doDeviceRegistration)(void) = ^{
        // Asynchronous HTTP request
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"/push/deviceRegistrations"]];
        request.HTTPMethod = @"POST";
        request.HTTPBody = [[self->_rest defaultEncoder] encodeLocalDevice:local error:nil];
        [request setValue:[[self->_rest defaultEncoder] mimeType] forHTTPHeaderField:@"Content-Type"];

        ARTLogDebug(self->_logger, @"%@: device registration with request %@", NSStringFromClass(self.class), request);
        [self->_rest executeRequest:request withAuthOption:ARTAuthenticationOn wrapperSDKAgents:nil completion:^(NSHTTPURLResponse *response, NSData *data, NSError *error) {
            if (error) {
                ARTLogError(self->_logger, @"%@: device registration failed (%@)", NSStringFromClass(self.class), error.localizedDescription);
                [self sendEvent:[ARTPushActivationEventGettingDeviceRegistrationFailed newWithError:[ARTErrorInfo createFromNSError:error]]];
                return;
            }
            NSError *decodeError = nil;
            ARTDeviceIdentityTokenDetails *identityTokenDetails = [[self->_rest defaultEncoder] decodeDeviceIdentityTokenDetails:data error:&decodeError];
            if (decodeError != nil) {
                ARTLogError(self->_logger, @"%@: decode identity token details failed (%@)", NSStringFromClass(self.class), error.localizedDescription);
                [self sendEvent:[ARTPushActivationEventGettingDeviceRegistrationFailed newWithError:[ARTErrorInfo createFromNSError:decodeError]]];
                return;
            }
            [self sendEvent:[ARTPushActivationEventGotDeviceRegistration newWithIdentityTokenDetails:identityTokenDetails]];
        }];
    };

    if (_rest.auth.method == ARTAuthMethodToken) {
        [_rest.auth authorize:^(ARTTokenDetails *tokenDetails, NSError *error) {
            doDeviceRegistration();
        }];
    }
    else {
        doDeviceRegistration();
    }
    #endif
}

- (void)deviceUpdateRegistration:(ARTErrorInfo *)error {
    #if TARGET_OS_IOS
    ARTLocalDevice *local = _rest.device_nosync;

    const id<ARTPushRegistererDelegate, NSObject> delegate = self.delegate;

    // Custom register
    if ([delegate respondsToSelector:@selector(ablyPushCustomRegister:deviceDetails:callback:)]) {
        art_dispatch_async(_userQueue, ^{
            [delegate ablyPushCustomRegister:error deviceDetails:local callback:^(ARTDeviceIdentityTokenDetails *identityTokenDetails, ARTErrorInfo *error) {
                if (error) {
                    // Failed
                    [self sendEvent:[ARTPushActivationEventSyncRegistrationFailed newWithError:error]];
                }
                else if (identityTokenDetails) {
                    // Success
                    [self sendEvent:[ARTPushActivationEventRegistrationSynced newWithIdentityTokenDetails:identityTokenDetails]];
                }
                else {
                    ARTErrorInfo *missingIdentityTokenError = [ARTErrorInfo createWithCode:0 message:@"Device Identity Token Details is expected"];
                    [self sendEvent:[ARTPushActivationEventSyncRegistrationFailed newWithError:missingIdentityTokenError]];
                }
            }];
        });
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[[NSURL URLWithString:@"/push/deviceRegistrations"] URLByAppendingPathComponent:local.id]];
    request.HTTPMethod = @"PATCH";
    request.HTTPBody = [[_rest defaultEncoder] encode:@{
        @"push": @{
            @"recipient": local.push.recipient
        }
    } error:nil];
    [request setValue:[[_rest defaultEncoder] mimeType] forHTTPHeaderField:@"Content-Type"];
    [request setDeviceAuthentication:local];

    ARTLogDebug(_logger, @"%@: update device with request %@", NSStringFromClass(self.class), request);
    [_rest executeRequest:request withAuthOption:ARTAuthenticationOn wrapperSDKAgents:nil completion:^(NSHTTPURLResponse *response, NSData *data, NSError *error) {
        if (error) {
            ARTLogError(self->_logger, @"%@: update device failed (%@)", NSStringFromClass(self.class), error.localizedDescription);
            [self sendEvent:[ARTPushActivationEventSyncRegistrationFailed newWithError:[ARTErrorInfo createFromNSError:error]]];
            return;
        }
        [self sendEvent:[ARTPushActivationEventRegistrationSynced new]];
    }];
    #endif
}

- (void)syncDevice {
    #if TARGET_OS_IOS
    ARTLocalDevice *const local = _rest.device_nosync;

    const id<ARTPushRegistererDelegate, NSObject> delegate = self.delegate;

    // Custom register
    if ([delegate respondsToSelector:@selector(ablyPushCustomRegister:deviceDetails:callback:)]) {
        art_dispatch_async(_userQueue, ^{
            [delegate ablyPushCustomRegister:nil deviceDetails:local callback:^(ARTDeviceIdentityTokenDetails *identityTokenDetails, ARTErrorInfo *error) {
                if (error) {
                    // Failed
                    [self sendEvent:[ARTPushActivationEventSyncRegistrationFailed newWithError:error]];
                }
                else if (identityTokenDetails) {
                    // Success
                    [self sendEvent:[ARTPushActivationEventRegistrationSynced newWithIdentityTokenDetails:identityTokenDetails]];
                }
                else {
                    ARTErrorInfo *const missingIdentityTokenError = [ARTErrorInfo createWithCode:0 message:@"Device Identity Token Details is expected"];
                    [self sendEvent:[ARTPushActivationEventSyncRegistrationFailed newWithError:missingIdentityTokenError]];
                }
            }];
        });
        return;
    }

    void (^doDeviceSync)(void) = ^{
        // Asynchronous HTTP request
        NSString *const path = [@"/push/deviceRegistrations" stringByAppendingPathComponent:local.id];
        NSMutableURLRequest *const request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:path]];
        request.HTTPMethod = @"PUT";
        request.HTTPBody = [[self->_rest defaultEncoder] encodeDeviceDetails:local error:nil];
        [request setValue:[[self->_rest defaultEncoder] mimeType] forHTTPHeaderField:@"Content-Type"];
        [request setDeviceAuthentication:local];

        ARTLogDebug(self->_logger, @"%@: sync device with request %@", NSStringFromClass(self.class), request);
        [self->_rest executeRequest:request withAuthOption:ARTAuthenticationOn wrapperSDKAgents:nil completion:^(NSHTTPURLResponse *response, NSData *data, NSError *error) {
            if (error) {
                ARTLogError(self->_logger, @"%@: device registration failed (%@)", NSStringFromClass(self.class), error.localizedDescription);
                [self sendEvent:[ARTPushActivationEventSyncRegistrationFailed newWithError:[ARTErrorInfo createFromNSError:error]]];
                return;
            }
            [self sendEvent:[ARTPushActivationEventRegistrationSynced newWithIdentityTokenDetails:local.identityTokenDetails]];
        }];
    };

    if (_rest.auth.method == ARTAuthMethodToken) {
        [_rest.auth authorize:^(ARTTokenDetails *tokenDetails, NSError *error) {
            doDeviceSync();
        }];
    }
    else {
        doDeviceSync();
    }
    #endif
}

- (void)deviceUnregistration:(ARTErrorInfo *)error {
    #if TARGET_OS_IOS
    ARTLocalDevice *local = _rest.device_nosync;

    __block id delegate = self.delegate;

    // Custom register
    SEL customDeregisterMethodSelector = @selector(ablyPushCustomDeregister:deviceId:callback:);
    if ([delegate respondsToSelector:customDeregisterMethodSelector]) {
        art_dispatch_async(_userQueue, ^{
            [delegate ablyPushCustomDeregister:error deviceId:local.id callback:^(ARTErrorInfo *error) {
                if (error) {
                    // RSH3d2c1: ignore unauthorized or invalid credentials errors
                    if (error.statusCode == 401 || error.code == 40005) {
                        [self sendEvent:[ARTPushActivationEventDeregistered new]];
                    } else {
                        [self sendEvent:[ARTPushActivationEventDeregistrationFailed newWithError:error]];
                    }
                }
                else {
                    // Success
                    [self sendEvent:[ARTPushActivationEventDeregistered new]];
                }
            }];
        });
        return;
    }

    // Asynchronous HTTP request
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[[NSURL URLWithString:@"/push/deviceRegistrations"] URLByAppendingPathComponent:local.id]];
    request.HTTPMethod = @"DELETE";
    [request setDeviceAuthentication:local];

    ARTLogDebug(_logger, @"%@: device deregistration with request %@", NSStringFromClass(self.class), request);
    [_rest executeRequest:request withAuthOption:ARTAuthenticationOn wrapperSDKAgents:nil completion:^(NSHTTPURLResponse *response, NSData *data, NSError *error) {
        if (error) {
            // RSH3d2c1: ignore unauthorized or invalid credentials errors
            if (response.statusCode == 401 || error.code == 40005) {
                ARTLogError(self->_logger, @"%@: unauthorized error during deregistration (%@)", NSStringFromClass(self.class), error.localizedDescription);
                [self sendEvent:[ARTPushActivationEventDeregistered new]];
            } else {
                ARTLogError(self->_logger, @"%@: device deregistration failed (%@)", NSStringFromClass(self.class), error.localizedDescription);
                [self sendEvent:[ARTPushActivationEventDeregistrationFailed newWithError:[ARTErrorInfo createFromNSError:error]]];
            }
            return;
        }
        ARTLogDebug(self->_logger, @"successfully deactivate device");
        [self sendEvent:[ARTPushActivationEventDeregistered new]];
    }];
    #endif
}

- (void)callActivatedCallback:(ARTErrorInfo *)error {
    #if TARGET_OS_IOS
    art_dispatch_async(_userQueue, ^{
        const id<ARTPushRegistererDelegate, NSObject> delegate = self.delegate;
        if ([delegate respondsToSelector:@selector(didActivateAblyPush:)]) {
            [delegate didActivateAblyPush:error];
        }
    });
    #endif
}

- (void)callDeactivatedCallback:(ARTErrorInfo *)error {
    #if TARGET_OS_IOS
    art_dispatch_async(_userQueue, ^{
        const id<ARTPushRegistererDelegate, NSObject> delegate = self.delegate;
        if ([delegate respondsToSelector:@selector(didDeactivateAblyPush:)]) {
            [delegate didDeactivateAblyPush:error];
        }
    });
    #endif
}

- (void)callUpdatedCallback:(nullable ARTErrorInfo *)error {
    #if TARGET_OS_IOS
    art_dispatch_async(_userQueue, ^{
        const id<ARTPushRegistererDelegate, NSObject> delegate = self.delegate;
        if ([delegate respondsToSelector:@selector(didUpdateAblyPush:)]) {
            [delegate didUpdateAblyPush:error];
        }
        else if (error && [delegate respondsToSelector:@selector(didAblyPushRegistrationFail:)]) {
            [delegate didAblyPushRegistrationFail:error];
        }
    });
    #endif
}

- (void)registerForAPNS {
    art_dispatch_async(dispatch_get_main_queue(), ^{
        [[UIApplication sharedApplication] registerForRemoteNotifications];
    });
}

@end

#endif
