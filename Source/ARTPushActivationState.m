#import "ARTPushActivationState.h"
#import "ARTPushActivationStateMachine+Private.h"
#import "ARTPushActivationEvent.h"
#import "ARTLocalDevice+Private.h"
#import "ARTDeviceStorage.h"
#import "ARTDevicePushDetails.h"
#import "ARTInternalLog.h"
#import "ARTHttpClient+Private.h"
#import "ARTAuth+Private.h"
#import "ARTHttp.h"
#import "ARTTypes+Private.h"

NS_ASSUME_NONNULL_BEGIN

@interface ARTPushActivationState ()

@property (nonatomic, readonly) ARTInternalLog *logger;

@end

NS_ASSUME_NONNULL_END

@implementation ARTPushActivationState

- (instancetype)initWithMachine:(ARTPushActivationStateMachine *)machine logger:(ARTInternalLog *)logger {
    if (self = [super init]) {
        _machine = machine;
        _logger = logger;
    }
    return self;
}

+ (instancetype)newWithMachine:(ARTPushActivationStateMachine *)machine logger:(ARTInternalLog *)logger {
    return [[self alloc] initWithMachine:machine logger:logger];
}

- (void)logEventTransition:(ARTPushActivationEvent *)event file:(const char *)file line:(NSUInteger)line {
    ARTLogDebug(self.logger, @"ARTPush Activation: %@ state: handling %@ event", NSStringFromClass(self.class), NSStringFromClass(event.class));
}

- (ARTPushActivationState *)transition:(ARTPushActivationEvent *)event {
    NSAssert(false, @"-[%s:%d %s] should always be overriden; class %@ doesn't.", __FILE__, __LINE__, __FUNCTION__, NSStringFromClass(self.class));
    return nil;
}

- (id)copyWithZone:(NSZone *)zone {
    // Implement NSCopying by retaining the original instead of creating a new copy when the class and its contents are immutable.
    return self;
}

#pragma mark - NSCoding

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder {
    self = [super init];
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder {
    // Just to persist the class info, no properties
}

#pragma mark - NSSecureCoding

+ (BOOL)supportsSecureCoding {
    return true;
}

@end

#pragma mark - Persistent State

@implementation ARTPushActivationPersistentState
@end

#pragma mark - Activation States

ARTPushActivationState *validateAndSync(ARTPushActivationStateMachine *machine, ARTPushActivationEvent *event, ARTInternalLog *logger) {
    #if TARGET_OS_IOS
    ARTLocalDevice *const local = machine.rest.device_nosync;

    if (local.identityTokenDetails) {
        // Already registered.
        NSString *const instanceClientId = machine.rest.auth.clientId_nosync;
        if (local.clientId != nil && instanceClientId && ![local.clientId isEqualToString:instanceClientId]) {
            ARTErrorInfo *const error = [ARTErrorInfo createWithCode:61002 message:@"Activation failed: present clientId is not compatible with existing device registration"];
            [machine sendEvent:[ARTPushActivationEventSyncRegistrationFailed newWithError:error]];
        } else {
            [machine syncDevice];
        }

        return [ARTPushActivationStateWaitingForRegistrationSync newWithMachine:machine logger:logger fromEvent:event];
    } else if ([local apnsDeviceToken]) {
        [machine sendEvent:[ARTPushActivationEventGotPushDeviceDetails new]];
    }
    [machine.rest setupLocalDevice_nosync];
    [machine registerForAPNS];
    #endif

    return [ARTPushActivationStateWaitingForPushDeviceDetails newWithMachine:machine logger:logger];
}

@implementation ARTPushActivationStateNotActivated

- (ARTPushActivationState *)transition:(ARTPushActivationEvent *)event {
    [self logEventTransition:event file:__FILE__ line:__LINE__];
    if ([event isKindOfClass:[ARTPushActivationEventCalledDeactivate class]]) {
        #if TARGET_OS_IOS
        ARTLocalDevice *device = self.machine.rest.device_nosync;
        #else
        ARTLocalDevice *device = nil;
        #endif
        // RSH3a1c
        if (device.isRegistered) {
            [self.machine deviceUnregistration:nil];
            return [ARTPushActivationStateWaitingForDeregistration newWithMachine:self.machine logger:self.logger];
        // RSH3a1d
        } else {
            #if TARGET_OS_IOS
            [self.machine.rest resetLocalDevice_nosync];
            #endif
            [self.machine callDeactivatedCallback:nil];
            return self;
        }
    }
    else if ([event isKindOfClass:[ARTPushActivationEventCalledActivate class]]) {
        return validateAndSync(self.machine, event, self.logger);
    }
    else if ([event isKindOfClass:[ARTPushActivationEventGotPushDeviceDetails class]]) {
        return self; // Consuming event (RSH3a3a)
    }
    return nil;
}

@end

@implementation ARTPushActivationStateWaitingForDeviceRegistration

- (ARTPushActivationState *)transition:(ARTPushActivationEvent *)event {
    [self logEventTransition:event file:__FILE__ line:__LINE__];
    if ([event isKindOfClass:[ARTPushActivationEventCalledActivate class]]) {
        return self;
    }
    else if ([event isKindOfClass:[ARTPushActivationEventGotDeviceRegistration class]]) {
        #if TARGET_OS_IOS
        ARTPushActivationEventGotDeviceRegistration *gotDeviceRegistrationEvent = (ARTPushActivationEventGotDeviceRegistration *)event;
        ARTLocalDevice *local = self.machine.rest.device_nosync;
        [local setAndPersistIdentityTokenDetails:gotDeviceRegistrationEvent.identityTokenDetails];
        #endif
        [self.machine callActivatedCallback:nil];
        return [ARTPushActivationStateWaitingForNewPushDeviceDetails newWithMachine:self.machine logger:self.logger];
    }
    else if ([event isKindOfClass:[ARTPushActivationEventGettingDeviceRegistrationFailed class]]) {
        [self.machine callActivatedCallback:[(ARTPushActivationEventGettingDeviceRegistrationFailed *)event error]];
        return [ARTPushActivationStateNotActivated newWithMachine:self.machine logger:self.logger];
    }
    return nil;
}

@end

@implementation ARTPushActivationStateWaitingForPushDeviceDetails

- (ARTPushActivationState *)transition:(ARTPushActivationEvent *)event {
    [self logEventTransition:event file:__FILE__ line:__LINE__];
    if ([event isKindOfClass:[ARTPushActivationEventCalledActivate class]]) {
        return [ARTPushActivationStateWaitingForPushDeviceDetails newWithMachine:self.machine logger:self.logger];
    }
    else if ([event isKindOfClass:[ARTPushActivationEventCalledDeactivate class]]) {
        [self.machine callDeactivatedCallback:nil];
        return [ARTPushActivationStateNotActivated newWithMachine:self.machine logger:self.logger];
    }
    else if ([event isKindOfClass:[ARTPushActivationEventGotPushDeviceDetails class]]) {
        [self.machine deviceRegistration:nil];
        return [ARTPushActivationStateWaitingForDeviceRegistration newWithMachine:self.machine logger:self.logger];
    }
    else if ([event isKindOfClass:[ARTPushActivationEventGettingPushDeviceDetailsFailed class]]) {
        [self.machine callActivatedCallback:((ARTPushActivationEventGettingPushDeviceDetailsFailed *) event).error];
        return [ARTPushActivationStateNotActivated newWithMachine:self.machine logger:self.logger];
    }
    return nil;
}

@end

@implementation ARTPushActivationStateWaitingForNewPushDeviceDetails

- (ARTPushActivationState *)transition:(ARTPushActivationEvent *)event {
    [self logEventTransition:event file:__FILE__ line:__LINE__];
    if ([event isKindOfClass:[ARTPushActivationEventCalledActivate class]]) {
        [self.machine callActivatedCallback:nil];
        return self;
    }
    else if ([event isKindOfClass:[ARTPushActivationEventCalledDeactivate class]]) {
        [self.machine deviceUnregistration:nil];
        return [ARTPushActivationStateWaitingForDeregistration newWithMachine:self.machine logger:self.logger];
    }
    else if ([event isKindOfClass:[ARTPushActivationEventGotPushDeviceDetails class]]) {
        [self.machine deviceUpdateRegistration:nil];
        return [ARTPushActivationStateWaitingForRegistrationSync newWithMachine:self.machine logger:self.logger fromEvent:event];
    }
    return nil;
}

@end

@implementation ARTPushActivationStateWaitingForRegistrationSync {
    ARTPushActivationEvent *_fromEvent;
}

- (instancetype)initWithMachine:(ARTPushActivationStateMachine *)machine logger:(ARTInternalLog *)logger fromEvent:(ARTPushActivationEvent *)event {
    if (self = [super initWithMachine:machine logger:logger]) {
        _fromEvent = event;
    }
    return self;
}

+ (instancetype)newWithMachine:(ARTPushActivationStateMachine *)machine logger:(ARTInternalLog *)logger fromEvent:(ARTPushActivationEvent *)event {
    return [[self alloc] initWithMachine:machine logger:logger fromEvent:event];
}

- (ARTPushActivationState *)transition:(ARTPushActivationEvent *)event {
    [self logEventTransition:event file:__FILE__ line:__LINE__];
    if ([event isKindOfClass:[ARTPushActivationEventCalledActivate class]] && ![_fromEvent isKindOfClass:[ARTPushActivationEventCalledActivate class]]) {
        [self.machine callActivatedCallback:nil];
        return self;
    }
    else if ([event isKindOfClass:[ARTPushActivationEventRegistrationSynced class]]) {
        #if TARGET_OS_IOS
        ARTPushActivationEventRegistrationSynced *registrationUpdatedEvent = (ARTPushActivationEventRegistrationSynced *)event;
        if (registrationUpdatedEvent.identityTokenDetails) {
            ARTLocalDevice *local = self.machine.rest.device_nosync;
            [local setAndPersistIdentityTokenDetails:registrationUpdatedEvent.identityTokenDetails];
        }
        #endif

        if ([_fromEvent isKindOfClass:[ARTPushActivationEventCalledActivate class]]) {
            [self.machine callActivatedCallback:nil];
        } else {
            [self.machine callUpdatedCallback:nil];
        }

        return [ARTPushActivationStateWaitingForNewPushDeviceDetails newWithMachine:self.machine logger:self.logger];
    }
    else if ([event isKindOfClass:[ARTPushActivationEventSyncRegistrationFailed class]]) {
        ARTErrorInfo *const error = [(ARTPushActivationEventSyncRegistrationFailed *)event error];
        if ([_fromEvent isKindOfClass:[ARTPushActivationEventCalledActivate class]]) {
            [self.machine callActivatedCallback:error];
        } else {
            [self.machine callUpdatedCallback:error];
        }

        return [ARTPushActivationStateAfterRegistrationSyncFailed newWithMachine:self.machine logger:self.logger];
    }
    return nil;
}

@end

@implementation ARTPushActivationStateAfterRegistrationSyncFailed

- (ARTPushActivationState *)transition:(ARTPushActivationEvent *)event {
    [self logEventTransition:event file:__FILE__ line:__LINE__];
    if ([event isKindOfClass:[ARTPushActivationEventCalledActivate class]] ||
        [event isKindOfClass:[ARTPushActivationEventGotPushDeviceDetails class]]) {

        return validateAndSync(self.machine, event, self.logger);
    }
    else if ([event isKindOfClass:[ARTPushActivationEventCalledDeactivate class]]) {
        [self.machine deviceUnregistration:nil];
        return [ARTPushActivationStateWaitingForDeregistration newWithMachine:self.machine logger:self.logger];
    }
    return nil;
}

@end

@implementation ARTPushActivationStateWaitingForDeregistration

- (ARTPushActivationState *)transition:(ARTPushActivationEvent *)event {
    [self logEventTransition:event file:__FILE__ line:__LINE__];
    if ([event isKindOfClass:[ARTPushActivationEventCalledDeactivate class]]) {
        return [ARTPushActivationStateWaitingForDeregistration newWithMachine:self.machine logger:self.logger];
    }
    else if ([event isKindOfClass:[ARTPushActivationEventDeregistered class]]) {
        #if TARGET_OS_IOS
        [self.machine.rest resetLocalDevice_nosync];
        #endif
        [self.machine callDeactivatedCallback:nil];
        return [ARTPushActivationStateNotActivated newWithMachine:self.machine logger:self.logger];
    }
    else if ([event isKindOfClass:[ARTPushActivationEventDeregistrationFailed class]]) {
        [self.machine callDeactivatedCallback:[(ARTPushActivationEventDeregistrationFailed *)event error]];
        return [ARTPushActivationStateWaitingForDeregistration newWithMachine:self.machine logger:self.logger];
    }
    return nil;
}

@end

@implementation ARTPushActivationDeprecatedPersistentState

- (ARTPushActivationPersistentState *)migrate {
    NSAssert(false, @"must be implemented by subclass");
    return nil;
}

@end

@implementation ARTPushActivationStateAfterRegistrationUpdateFailed

- (ARTPushActivationPersistentState *)migrate {
    return [[ARTPushActivationStateAfterRegistrationSyncFailed alloc] initWithMachine:self.machine logger:self.logger];
}

@end
