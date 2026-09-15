#if TARGET_OS_IOS
@import XCTest;
@import AblyPubSubDevice;
@import AblyPubSubDevice.Private;
@import AblyTesting;

@interface _StateMachineDelegate : NSObject <ARTPushRegistererDelegate>
@end

@implementation _StateMachineDelegate
- (void)didActivateAblyPush:(nullable ARTErrorInfo *)error { }
- (void)didDeactivateAblyPush:(nullable ARTErrorInfo *)error { }
@end

@interface ARTArchiveTests : XCTestCase
@end

@implementation ARTArchiveTests

- (void)test_art_unarchivedObjectOfClass_for_state_machine_states {

    ARTRest* rest = [[ARTRest alloc] initWithKey:@"xxxx:xxxx"];
    ARTInternalLog *const logger = [[ARTInternalLog alloc] initWithCore:[[ARTMockInternalLogCore alloc] init]];
    ARTPushActivationStateMachine* stateMachine = [[ARTPushActivationStateMachine alloc] initWithRest:rest.internal delegate:[[_StateMachineDelegate alloc] init] logger:logger];

    NSArray* initialStates = [NSMutableArray arrayWithArray:@[
        [[ARTPushActivationStateNotActivated alloc] initWithMachine:stateMachine logger:logger],
        [[ARTPushActivationStateWaitingForPushDeviceDetails alloc] initWithMachine:stateMachine logger:logger],
        [[ARTPushActivationStateAfterRegistrationSyncFailed alloc] initWithMachine:stateMachine logger:logger]
    ]];

    NSData* data = [initialStates art_archiveWithLogger:nil];

    NSArray* unarchivedStates = [ARTPushActivationState art_unarchiveFromData:data withLogger:nil];

    XCTAssert([unarchivedStates[0] isKindOfClass:[ARTPushActivationStateNotActivated class]]);
    XCTAssert([unarchivedStates[1] isKindOfClass:[ARTPushActivationStateWaitingForPushDeviceDetails class]]);
    XCTAssert([unarchivedStates[2] isKindOfClass:[ARTPushActivationStateAfterRegistrationSyncFailed class]]);
}

@end
#endif
