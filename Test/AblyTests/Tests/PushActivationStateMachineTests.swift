#if os(iOS)
import AblyPubSubDevice
import AblyTesting
import Nimble
import XCTest

private var rest: ARTRest!
private var httpExecutor: MockHTTPExecutor!
private var storage: MockDeviceStorage!
private var initialStateMachine: ARTPushActivationStateMachine!

private let expectedFormFactor = "phone"
private let expectedPlatform = "ios"
private let expectedPushRecipient: [String: [String: AnyHashable]] = ["recipient": ["transportType": "apns"]]

private var stateMachine: ARTPushActivationStateMachine!

class PushActivationStateMachineTests: XCTestCase {
    // XCTest invokes this method before executing the first test in the test suite. We use it to ensure that the global variables are initialized at the same moment, and in the same order, as they would have been when we used the Quick testing framework.
    override class var defaultTestSuite: XCTestSuite {
        _ = rest
        _ = httpExecutor
        _ = storage
        _ = initialStateMachine
        _ = expectedFormFactor
        _ = expectedPlatform
        _ = expectedPushRecipient
        _ = stateMachine

        return super.defaultTestSuite
    }

    override func setUp() {
        super.setUp()

        // Start from a clean on-disk device storage
        AblyTests.clearOnDiskDeviceStorage()

        rest = ARTRest(key: "xxxx:xxxx")
        httpExecutor = MockHTTPExecutor()
        rest.internal.httpExecutor = httpExecutor
        storage = MockDeviceStorage()
        rest.internal.storage = storage
        initialStateMachine = ARTPushActivationStateMachine(rest: rest.internal, delegate: StateMachineDelegate(), logger: .init(core: MockInternalLogCore()))
        rest.internal.resetDeviceSingleton()
    }

    func test__002__Activation_state_machine__should_set_NotActivated_state_as_current_state_when_disk_is_empty() {
        expect(initialStateMachine.current).to(beAKindOf(ARTPushActivationStateNotActivated.self))
    }

    func test__003__Activation_state_machine__should_read_the_current_state_from_disk() {
        let storage = MockDeviceStorage(startWith: ARTPushActivationStateWaitingForDeviceRegistration(machine: initialStateMachine, logger: .init(core: MockInternalLogCore())))
        rest.internal.storage = storage
        let stateMachine = ARTPushActivationStateMachine(rest: rest.internal, delegate: StateMachineDelegate(), logger: .init(core: MockInternalLogCore()))
        expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateWaitingForDeviceRegistration.self))
        XCTAssertEqual(storage.keysRead.count, 4) // 2 for state + 2 device key/secret
        XCTAssertEqual(storage.keysRead.filter { $0.hasSuffix("CurrentState") }.count, 1)
        XCTAssertEqual(storage.keysWritten.count, 2) // generated key/secret
    }

    func test__004__Activation_state_machine__AfterRegistrationUpdateFailed_state_from_persistence_gets_migrated_to_AfterRegistrationSyncFailed() {
        let stateEncodedFromOldVersionBase64 = "YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRBcmNoaXZlctEICVRyb290gAGjCwwPVSRudWxs0Q0OViRjbGFzc4AC0hAREhNaJGNsYXNzbmFtZVgkY2xhc3Nlc18QM0FSVFB1c2hBY3RpdmF0aW9uU3RhdGVBZnRlclJlZ2lzdHJhdGlvblVwZGF0ZUZhaWxlZKQUFRYXXxAzQVJUUHVzaEFjdGl2YXRpb25TdGF0ZUFmdGVyUmVnaXN0cmF0aW9uVXBkYXRlRmFpbGVkXxAgQVJUUHVzaEFjdGl2YXRpb25QZXJzaXN0ZW50U3RhdGVfEBZBUlRQdXNoQWN0aXZhdGlvblN0YXRlWE5TT2JqZWN0AAgAEQAaACQAKQAyADcASQBMAFEAUwBXAF0AYABnAGkAbgB5AIIAuAC9APMBFgEvAAAAAAAAAgEAAAAAAAAAGAAAAAAAAAAAAAAAAAAAATg="
        let stateEncodedFromOldVersion = Data(base64Encoded: stateEncodedFromOldVersionBase64, options: .init())!

        let storage = MockDeviceStorage()
        storage.simulateOnNextRead(data: stateEncodedFromOldVersion, for: ARTPushActivationCurrentStateKey)
        rest.internal.storage = storage
        let stateMachine = ARTPushActivationStateMachine(rest: rest.internal, delegate: StateMachineDelegate(), logger: .init(core: MockInternalLogCore()))
        expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateAfterRegistrationSyncFailed.self))
    }

    // RSH3a

    func beforeEach__Activation_state_machine__State_NotActivated() {
        storage = MockDeviceStorage(startWith: ARTPushActivationStateNotActivated(machine: initialStateMachine, logger: .init(core: MockInternalLogCore())))
        rest.internal.storage = storage
        stateMachine = ARTPushActivationStateMachine(rest: rest.internal, delegate: StateMachineDelegate(), logger: .init(core: MockInternalLogCore()))
    }

    // RSH3a1
    func test__007__Activation_state_machine__State_NotActivated__on_Event_CalledDeactivate__should_transition_to_NotActivated() {
        beforeEach__Activation_state_machine__State_NotActivated()

        var deactivatedCallbackCalled = false
        let hook = stateMachine.testSuite_injectIntoMethod(after: NSSelectorFromString("callDeactivatedCallback:")) {
            deactivatedCallbackCalled = true
        }
        defer { hook.remove() }

        stateMachine.send(ARTPushActivationEventCalledDeactivate())

        expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateNotActivated.self))
        XCTAssertTrue(deactivatedCallbackCalled)
    }

    // RSH3a2

    // RSH3a2a
    func reusableTestsWrapper__Activation_state_machine__State_NotActivated__on_Event_CalledActivate__reusableTestsRsh3a2a(testCase: TestCase_ReusableTestsRsh3a2a) throws {
        // RSH3a2a
        try reusableTestsRsh3a2a(testCase: testCase, beforeEach: beforeEach__Activation_state_machine__State_NotActivated)
    }

    func test__011__Activation_state_machine__State_NotActivated__on_Event_CalledActivate__the_local_device_has_id_and_deviceIdentityToken__emits_a_SyncRegistrationFailed_event_with_code_61002_if_client_IDs_don_t_match() throws {
        try reusableTestsWrapper__Activation_state_machine__State_NotActivated__on_Event_CalledActivate__reusableTestsRsh3a2a(testCase: .the_local_device_has_id_and_deviceIdentityToken__emits_a_SyncRegistrationFailed_event_with_code_61002_if_client_IDs_don_t_match)
    }

    func test__012__Activation_state_machine__State_NotActivated__on_Event_CalledActivate__the_local_device_has_id_and_deviceIdentityToken__the_local_DeviceDetails_matches_the_instance_s_client_ID__calls_registerCallback__transitions_to_WaitingForRegistrationSync() throws {
        try reusableTestsWrapper__Activation_state_machine__State_NotActivated__on_Event_CalledActivate__reusableTestsRsh3a2a(testCase: .the_local_device_has_id_and_deviceIdentityToken__the_local_DeviceDetails_matches_the_instance_s_client_ID__calls_registerCallback__transitions_to_WaitingForRegistrationSync)
    }

    func test__013__Activation_state_machine__State_NotActivated__on_Event_CalledActivate__the_local_device_has_id_and_deviceIdentityToken__the_local_DeviceDetails_matches_the_instance_s_client_ID__PUTs_device_registration__transitions_to_WaitingForRegistrationSync() throws {
        try reusableTestsWrapper__Activation_state_machine__State_NotActivated__on_Event_CalledActivate__reusableTestsRsh3a2a(testCase: .the_local_device_has_id_and_deviceIdentityToken__the_local_DeviceDetails_matches_the_instance_s_client_ID__PUTs_device_registration__transitions_to_WaitingForRegistrationSync)
    }

    // RSH3a2b

    func test__014__Activation_state_machine__State_NotActivated__on_Event_CalledActivate__local_device__should_have_a_generated_id() {
        beforeEach__Activation_state_machine__State_NotActivated()

        let options = ARTClientOptions(key: "xxxx:xxxx")
        let rest = ARTRest(options: options)
        rest.internal.storage = storage
        let stateMachine = ARTPushActivationStateMachine(rest: rest.internal, delegate: StateMachineDelegate(), logger: .init(core: MockInternalLogCore()))

        stateMachine.send(ARTPushActivationEventCalledActivate())

        XCTAssertEqual(rest.device.id.count, 36)
    }

    func test__015__Activation_state_machine__State_NotActivated__on_Event_CalledActivate__local_device__should_have_a_generated_secret() throws {
        beforeEach__Activation_state_machine__State_NotActivated()

        let options = ARTClientOptions(key: "xxxx:xxxx")
        let rest = ARTRest(options: options)
        rest.internal.storage = storage
        let stateMachine = ARTPushActivationStateMachine(rest: rest.internal, delegate: StateMachineDelegate(), logger: .init(core: MockInternalLogCore()))

        stateMachine.send(ARTPushActivationEventCalledActivate())

        let secret = try XCTUnwrap(rest.device.secret, "Device Secret should be available in storage")
        let data = try XCTUnwrap(Data(base64Encoded: secret), "Device Secret should be encoded with Base64")

        XCTAssertEqual(data.count, 32) // 32 bytes digest
    }

    // RSH8b
    func test__016__Activation_state_machine__State_NotActivated__on_Event_CalledActivate__local_device__should_have_a_clientID_if_the_client_is_identified() {
        beforeEach__Activation_state_machine__State_NotActivated()

        let options = ARTClientOptions(key: "xxxx:xxxx")
        options.clientId = "deviceClient"
        let rest = ARTRest(options: options)
        rest.internal.storage = storage

        let stateMachine = ARTPushActivationStateMachine(rest: rest.internal, delegate: StateMachineDelegate(), logger: .init(core: MockInternalLogCore()))

        XCTAssertNil(rest.device.clientId)

        stateMachine.send(ARTPushActivationEventCalledActivate())

        XCTAssertNotNil(rest.device.id)
        XCTAssertNotNil(rest.device.secret)
        XCTAssertEqual(rest.device.clientId, "deviceClient")
    }

    // RSH3a2c
    func test__009__Activation_state_machine__State_NotActivated__on_Event_CalledActivate__if_the_local_device_has_the_necessary_push_details_should_send_event_GotPushDeviceDetails() {
        beforeEach__Activation_state_machine__State_NotActivated()

        let delegate = StateMachineDelegate()
        stateMachine.delegate = delegate

        let testDeviceToken = "xxxx-xxxx-xxxx-xxxx-xxxx"
        stateMachine.rest.device.setAndPersistAPNSDeviceToken(testDeviceToken)
        defer { stateMachine.rest.device.setAndPersistAPNSDeviceToken(nil) }

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)
            stateMachine.transitions = { event, _, _ in
                if event is ARTPushActivationEventCalledActivate {
                    partialDone()
                }
                if event is ARTPushActivationEventGotPushDeviceDetails {
                    partialDone()
                }
            }
            stateMachine.send(ARTPushActivationEventCalledActivate())
        }
    }

    // RSH3a2d
    func test__010__Activation_state_machine__State_NotActivated__on_Event_CalledActivate__none_of_them_then_should_transition_to_WaitingForPushDeviceDetails() {
        beforeEach__Activation_state_machine__State_NotActivated()

        stateMachine.send(ARTPushActivationEventCalledActivate())
        expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateWaitingForPushDeviceDetails.self))
    }

    // RSH3a3
    func test__008__Activation_state_machine__State_NotActivated__on_Event_GotPushDeviceDetails() {
        beforeEach__Activation_state_machine__State_NotActivated()

        stateMachine.send(ARTPushActivationEventGotPushDeviceDetails())

        expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateNotActivated.self))
        XCTAssertEqual(stateMachine.pendingEvents.count, 0)
    }

    // RSH3b

    func beforeEach__Activation_state_machine__State_WaitingForPushDeviceDetails() {
        storage = MockDeviceStorage(startWith: ARTPushActivationStateWaitingForPushDeviceDetails(machine: initialStateMachine, logger: .init(core: MockInternalLogCore())))
        rest.internal.storage = storage
        stateMachine = ARTPushActivationStateMachine(rest: rest.internal, delegate: StateMachineDelegate(), logger: .init(core: MockInternalLogCore()))
        rest.internal.resetDeviceSingleton()
    }

    // RSH3b1
    func test__017__Activation_state_machine__State_WaitingForPushDeviceDetails__on_Event_CalledActivate() {
        beforeEach__Activation_state_machine__State_WaitingForPushDeviceDetails()

        stateMachine.send(ARTPushActivationEventCalledActivate())
        expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateWaitingForPushDeviceDetails.self))
    }

    // RSH3b2
    func test__018__Activation_state_machine__State_WaitingForPushDeviceDetails__on_Event_CalledDeactivate() {
        beforeEach__Activation_state_machine__State_WaitingForPushDeviceDetails()

        var deactivatedCallbackCalled = false
        let hook = stateMachine.testSuite_injectIntoMethod(after: NSSelectorFromString("callDeactivatedCallback:")) {
            deactivatedCallbackCalled = true
        }
        defer { hook.remove() }

        stateMachine.send(ARTPushActivationEventCalledDeactivate())
        expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateNotActivated.self))
        XCTAssertTrue(deactivatedCallbackCalled)
    }

    // RSH3b3

    // RSH3b3a, RSH3b3c
    func test__022__Activation_state_machine__State_WaitingForPushDeviceDetails__on_Event_GotPushDeviceDetails__should_use_custom_registerCallback_and_fire_GotDeviceRegistration_event() {
        beforeEach__Activation_state_machine__State_WaitingForPushDeviceDetails()

        expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateWaitingForPushDeviceDetails.self))

        let delegate = StateMachineDelegateCustomCallbacks()
        stateMachine.delegate = delegate

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(3, done: done)
            stateMachine.transitions = { event, _, currentState in
                if event is ARTPushActivationEventGotPushDeviceDetails {
                    expect(currentState).to(beAKindOf(ARTPushActivationStateWaitingForDeviceRegistration.self))
                    partialDone()
                } else if event is ARTPushActivationEventGotDeviceRegistration {
                    stateMachine.transitions = nil
                    partialDone()
                }
            }
            delegate.onPushCustomRegister = { error, deviceDetails in
                XCTAssertNil(error)
                XCTAssertTrue(deviceDetails === rest.device)
                partialDone()
                return nil
            }
            stateMachine.send(ARTPushActivationEventGotPushDeviceDetails())
        }

        expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateWaitingForNewPushDeviceDetails.self))
        XCTAssertEqual(httpExecutor.requests.count, 0)
    }

    // RSH3b3c
    func test__023__Activation_state_machine__State_WaitingForPushDeviceDetails__on_Event_GotPushDeviceDetails__should_use_custom_registerCallback_and_fire_GettingDeviceRegistrationFailed_event() {
        beforeEach__Activation_state_machine__State_WaitingForPushDeviceDetails()

        expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateWaitingForPushDeviceDetails.self))

        let delegate = StateMachineDelegateCustomCallbacks()
        stateMachine.delegate = delegate

        waitUntil(timeout: testTimeout) { done in
            let simulatedError = NSError(domain: ARTAblyErrorDomain, code: 1234, userInfo: nil)
            let partialDone = AblyTests.splitDone(3, done: done)
            stateMachine.transitions = { event, _, currentState in
                if event is ARTPushActivationEventGotPushDeviceDetails {
                    expect(currentState).to(beAKindOf(ARTPushActivationStateWaitingForDeviceRegistration.self))
                    partialDone()
                } else if let event = event as? ARTPushActivationEventGettingDeviceRegistrationFailed {
                    XCTAssertEqual(event.error.domain, ARTAblyErrorDomain)
                    XCTAssertEqual(event.error.code, simulatedError.code)
                    stateMachine.transitions = nil
                    partialDone()
                }
            }
            delegate.onPushCustomRegister = { error, deviceDetails in
                XCTAssertNil(error)
                XCTAssertTrue(deviceDetails === rest.device)
                partialDone()
                return simulatedError
            }
            stateMachine.send(ARTPushActivationEventGotPushDeviceDetails())
        }

        expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateNotActivated.self))
        XCTAssertEqual(httpExecutor.requests.count, 0)
    }

    // RSH3b3b, RSH3b3c
    func test__024__Activation_state_machine__State_WaitingForPushDeviceDetails__on_Event_GotPushDeviceDetails__should_fire_GotDeviceRegistration_event() throws {
        beforeEach__Activation_state_machine__State_WaitingForPushDeviceDetails()

        expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateWaitingForPushDeviceDetails.self))

        let delegate = StateMachineDelegate()
        stateMachine.delegate = delegate

        var setAndPersistIdentityTokenDetailsCalled = false
        let hookDevice = stateMachine.rest.device.testSuite_injectIntoMethod(after: NSSelectorFromString("setAndPersistIdentityTokenDetails:")) {
            setAndPersistIdentityTokenDetailsCalled = true
        }
        defer { hookDevice.remove() }

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)
            stateMachine.transitions = { event, _, currentState in
                if event is ARTPushActivationEventGotPushDeviceDetails {
                    expect(currentState).to(beAKindOf(ARTPushActivationStateWaitingForDeviceRegistration.self))
                    partialDone()
                } else if event is ARTPushActivationEventGotDeviceRegistration {
                    stateMachine.transitions = nil
                    partialDone()
                }
            }
            stateMachine.send(ARTPushActivationEventGotPushDeviceDetails())
        }

        expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateWaitingForNewPushDeviceDetails.self))
        XCTAssertTrue(setAndPersistIdentityTokenDetailsCalled)
        XCTAssertEqual(httpExecutor.requests.count, 1)
        let requests = httpExecutor.requests.compactMap { $0.url?.path }.filter { $0 == "/push/deviceRegistrations" }
        XCTAssertEqual(requests.count, 1)

        let request = try XCTUnwrap(httpExecutor.requests.first, "Should have a \"/push/deviceRegistrations\" request")
        let url = try XCTUnwrap(request.url, "Request should have a \"/push/deviceRegistrations\" URL")
        let rawBody = try XCTUnwrap(request.httpBody, "Request should have a body")
        let decodedBody = try XCTUnwrap(try stateMachine.rest.defaultEncoder.decode(rawBody), "Decode request body failed")
        let body = try XCTUnwrap(decodedBody as? NSDictionary, "Request body is invalid")

        XCTAssertEqual(url.host, rest.internal.options.restUrl().host)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(body.value(forKey: "id") as? String, rest.device.id)
        XCTAssertEqual(body.value(forKey: "deviceSecret") as? String, rest.device.secret)
        XCTAssertEqual(body.value(forKey: "push") as? [String: [String: AnyHashable]], expectedPushRecipient)
        XCTAssertEqual(body.value(forKey: "formFactor") as? String, expectedFormFactor)
        XCTAssertEqual(body.value(forKey: "platform") as? String, expectedPlatform)
    }

    // RSH3b3c
    func test__025__Activation_state_machine__State_WaitingForPushDeviceDetails__on_Event_GotPushDeviceDetails__should_fire_GettingDeviceRegistrationFailed_event() throws {
        beforeEach__Activation_state_machine__State_WaitingForPushDeviceDetails()

        expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateWaitingForPushDeviceDetails.self))

        let delegate = StateMachineDelegate()
        stateMachine.delegate = delegate

        let simulatedError = NSError(domain: ARTAblyErrorDomain, code: 1234, userInfo: nil)
        httpExecutor.simulateIncomingErrorOnNextRequest(simulatedError)

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)
            stateMachine.transitions = { event, _, currentState in
                if event is ARTPushActivationEventGotPushDeviceDetails {
                    expect(currentState).to(beAKindOf(ARTPushActivationStateWaitingForDeviceRegistration.self))
                    partialDone()
                } else if let event = event as? ARTPushActivationEventGettingDeviceRegistrationFailed {
                    XCTAssertEqual(event.error.domain, ARTAblyErrorDomain)
                    XCTAssertEqual(event.error.code, simulatedError.code)
                    stateMachine.transitions = nil
                    partialDone()
                }
            }
            stateMachine.send(ARTPushActivationEventGotPushDeviceDetails())
        }

        expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateNotActivated.self))
        XCTAssertEqual(httpExecutor.requests.count, 1)
        let requests = httpExecutor.requests.compactMap { $0.url?.path }.filter { $0 == "/push/deviceRegistrations" }
        XCTAssertEqual(requests.count, 1)

        let request = try XCTUnwrap(httpExecutor.requests.first, "Should have a \"/push/deviceRegistrations\" request")
        let _ = try XCTUnwrap(request.url, "Request should have a \"/push/deviceRegistrations\" URL")
        let rawBody = try XCTUnwrap(request.httpBody, "Request should have a body")
        let decodedBody = try XCTUnwrap(try stateMachine.rest.defaultEncoder.decode(rawBody), "Decode request body failed")
        let body = try XCTUnwrap(decodedBody as? NSDictionary, "Request body is invalid")

        XCTAssertEqual(body.value(forKey: "id") as? String, rest.device.id)
        XCTAssertEqual(body.value(forKey: "push") as? [String: [String: AnyHashable]], expectedPushRecipient)
        XCTAssertEqual(body.value(forKey: "formFactor") as? String, expectedFormFactor)
        XCTAssertEqual(body.value(forKey: "platform") as? String, expectedPlatform)
    }

    // RSH3b3d
    func test__026__Activation_state_machine__State_WaitingForPushDeviceDetails__on_Event_GotPushDeviceDetails__should_transition_to_WaitingForDeviceRegistration() {
        beforeEach__Activation_state_machine__State_WaitingForPushDeviceDetails()

        expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateWaitingForPushDeviceDetails.self))

        let delegate = StateMachineDelegate()
        stateMachine.delegate = delegate

        var setAndPersistIdentityTokenDetailsCalled = false
        let hookDevice = stateMachine.rest.device.testSuite_injectIntoMethod(after: NSSelectorFromString("setAndPersistIdentityTokenDetails:")) {
            setAndPersistIdentityTokenDetailsCalled = true
        }
        defer { hookDevice.remove() }

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)
            stateMachine.transitions = { event, _, currentState in
                if event is ARTPushActivationEventGotPushDeviceDetails {
                    expect(currentState).to(beAKindOf(ARTPushActivationStateWaitingForDeviceRegistration.self))
                    partialDone()
                } else if event is ARTPushActivationEventGotDeviceRegistration {
                    stateMachine.transitions = nil
                    partialDone()
                }
            }
            stateMachine.send(ARTPushActivationEventGotPushDeviceDetails())
        }

        XCTAssertTrue(setAndPersistIdentityTokenDetailsCalled)
    }

    // RSH3b4
    func test__019__Activation_state_machine__State_WaitingForPushDeviceDetails__on_Event_GettingPushDeviceDetailsFailed() {
        beforeEach__Activation_state_machine__State_WaitingForPushDeviceDetails()

        let expectedError = ARTErrorInfo(domain: ARTAblyErrorDomain, code: 1234, userInfo: nil)

        let delegate = StateMachineDelegate()
        stateMachine.delegate = delegate

        waitUntil(timeout: testTimeout) { done in
            delegate.onDidActivateAblyPush = { error in
                XCTAssertEqual(error, expectedError)
                done()
            }
            stateMachine.send(ARTPushActivationEventGettingPushDeviceDetailsFailed(error: expectedError))
        }

        expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateNotActivated.self))
    }

    // https://github.com/ably/ably-cocoa/issues/966
    func test__020__Activation_state_machine__State_WaitingForPushDeviceDetails__when_initializing_from_persistent_state_with_a_deviceToken__GotPushDeviceDetails_should_be_re_emitted() {
        beforeEach__Activation_state_machine__State_WaitingForPushDeviceDetails()

        storage = MockDeviceStorage(startWith: ARTPushActivationStateWaitingForPushDeviceDetails(machine: initialStateMachine, logger: .init(core: MockInternalLogCore())))
        rest.internal.storage = storage
        rest.device.setAndPersistAPNSDeviceToken("foo")
        defer { rest.device.setAndPersistAPNSDeviceToken(nil) }

        var registered = false

        let delegate = StateMachineDelegateCustomCallbacks()
        stateMachine = ARTPushActivationStateMachine(rest: rest.internal, delegate: delegate, logger: .init(core: MockInternalLogCore()))
        delegate.onPushCustomRegister = { _, _ in
            registered = true
            return nil
        }

        expect(registered).toEventually(beTrue())
    }

    // RSH3c

    func beforeEach__Activation_state_machine__State_WaitingForDeviceRegistration() {
        storage = MockDeviceStorage(startWith: ARTPushActivationStateWaitingForDeviceRegistration(machine: initialStateMachine, logger: .init(core: MockInternalLogCore())))
        rest.internal.storage = storage
        stateMachine = ARTPushActivationStateMachine(rest: rest.internal, delegate: StateMachineDelegate(), logger: .init(core: MockInternalLogCore()))
        rest.internal.setupLocalDevice_nosync()
    }

    // RSH3c1
    func test__027__Activation_state_machine__State_WaitingForDeviceRegistration__on_Event_CalledActivate() {
        beforeEach__Activation_state_machine__State_WaitingForDeviceRegistration()

        stateMachine.send(ARTPushActivationEventCalledActivate())
        expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateWaitingForDeviceRegistration.self))
    }

    // RSH3c2 / RSH8c
    func test__028__Activation_state_machine__State_WaitingForDeviceRegistration__on_Event_GotDeviceRegistration() {
        beforeEach__Activation_state_machine__State_WaitingForDeviceRegistration()

        rest.internal.resetDeviceSingleton()

        var activatedCallbackCalled = false
        let hook = stateMachine.testSuite_injectIntoMethod(after: NSSelectorFromString("callActivatedCallback:")) {
            activatedCallbackCalled = true
        }
        defer { hook.remove() }

        var setAndPersistIdentityTokenDetailsCalled = false
        let hookDevice = stateMachine.rest.device.testSuite_injectIntoMethod(after: NSSelectorFromString("setAndPersistIdentityTokenDetails:")) {
            setAndPersistIdentityTokenDetailsCalled = true
        }
        defer { hookDevice.remove() }

        let testIdentityTokenDetails = ARTDeviceIdentityTokenDetails(
            token: "123456",
            issued: Date(),
            expires: Date.distantFuture,
            capability: "",
            clientId: ""
        )

        stateMachine.send(ARTPushActivationEventGotDeviceRegistration(identityTokenDetails: testIdentityTokenDetails))
        expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateWaitingForNewPushDeviceDetails.self))
        XCTAssertTrue(activatedCallbackCalled)
        XCTAssertTrue(setAndPersistIdentityTokenDetailsCalled)
        expect(storage.keysWritten.keys).to(contain(["ARTDeviceId", "ARTDeviceSecret", "ARTDeviceIdentityToken"]))
    }

    // RSH3c3
    func test__029__Activation_state_machine__State_WaitingForDeviceRegistration__on_Event_GettingDeviceRegistrationFailed() {
        beforeEach__Activation_state_machine__State_WaitingForDeviceRegistration()

        let expectedError = ARTErrorInfo(domain: ARTAblyErrorDomain, code: 1234, userInfo: nil)

        var activatedCallbackCalled = false
        let hook = stateMachine.testSuite_getArgument(from: NSSelectorFromString("callActivatedCallback:"), at: 0, callback: { arg0 in
            activatedCallbackCalled = true
            guard let error = arg0 as? ARTErrorInfo else {
                fail("Error is missing"); return
            }
            XCTAssertEqual(error, expectedError)
        })
        defer { hook.remove() }

        stateMachine.send(ARTPushActivationEventGettingDeviceRegistrationFailed(error: expectedError))
        expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateNotActivated.self))
        XCTAssertTrue(activatedCallbackCalled)
    }

    // RSH3d

    func beforeEach__Activation_state_machine__State_WaitingForNewPushDeviceDetails() {
        storage = MockDeviceStorage(startWith: ARTPushActivationStateWaitingForNewPushDeviceDetails(machine: initialStateMachine, logger: .init(core: MockInternalLogCore())))
        rest.internal.storage = storage
        stateMachine = ARTPushActivationStateMachine(rest: rest.internal, delegate: StateMachineDelegate(), logger: .init(core: MockInternalLogCore()))
        rest.internal.setupLocalDevice_nosync()
    }

    // RSH3d1
    func test__030__Activation_state_machine__State_WaitingForNewPushDeviceDetails__on_Event_CalledActivate() {
        beforeEach__Activation_state_machine__State_WaitingForNewPushDeviceDetails()

        var activatedCallbackCalled = false
        let hook = stateMachine.testSuite_injectIntoMethod(after: NSSelectorFromString("callActivatedCallback:")) {
            activatedCallbackCalled = true
        }
        defer { hook.remove() }

        stateMachine.send(ARTPushActivationEventCalledActivate())
        expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateWaitingForNewPushDeviceDetails.self))
        XCTAssertTrue(activatedCallbackCalled)
    }

    // RSH3d2

    func reusableTestsWrapper__Activation_state_machine__State_WaitingForNewPushDeviceDetails__on_Event_CalledDeactivate__reusableTestsRsh3d2(testCase: TestCase_ReusableTestsRsh3d2) throws {
        try reusableTestsRsh3d2(testCase: testCase, beforeEach: beforeEach__Activation_state_machine__State_WaitingForNewPushDeviceDetails)
    }

    func test__031__Activation_state_machine__State_WaitingForNewPushDeviceDetails__on_Event_CalledDeactivate__should_use_custom_deregisterCallback_and_fire_Deregistered_event() throws {
        try reusableTestsWrapper__Activation_state_machine__State_WaitingForNewPushDeviceDetails__on_Event_CalledDeactivate__reusableTestsRsh3d2(testCase: .should_use_custom_deregisterCallback_and_fire_Deregistered_event)
    }

    func test__032__Activation_state_machine__State_WaitingForNewPushDeviceDetails__on_Event_CalledDeactivate__should_use_custom_deregisterCallback_and_fire_DeregistrationFailed_event() throws {
        try reusableTestsWrapper__Activation_state_machine__State_WaitingForNewPushDeviceDetails__on_Event_CalledDeactivate__reusableTestsRsh3d2(testCase: .should_use_custom_deregisterCallback_and_fire_DeregistrationFailed_event)
    }

    func test__033__Activation_state_machine__State_WaitingForNewPushDeviceDetails__on_Event_CalledDeactivate__should_fire_Deregistered_event_and_include_DeviceSecret_HTTP_header() throws {
        try reusableTestsWrapper__Activation_state_machine__State_WaitingForNewPushDeviceDetails__on_Event_CalledDeactivate__reusableTestsRsh3d2(testCase: .should_fire_Deregistered_event_and_include_DeviceSecret_HTTP_header)
    }

    func test__034__Activation_state_machine__State_WaitingForNewPushDeviceDetails__on_Event_CalledDeactivate__should_fire_Deregistered_event_and_include_DeviceIdentityToken_HTTP_header() throws {
        try reusableTestsWrapper__Activation_state_machine__State_WaitingForNewPushDeviceDetails__on_Event_CalledDeactivate__reusableTestsRsh3d2(testCase: .should_fire_Deregistered_event_and_include_DeviceIdentityToken_HTTP_header)
    }

    func test__035__Activation_state_machine__State_WaitingForNewPushDeviceDetails__on_Event_CalledDeactivate__should_fire_DeregistrationFailed_event() throws {
        try reusableTestsWrapper__Activation_state_machine__State_WaitingForNewPushDeviceDetails__on_Event_CalledDeactivate__reusableTestsRsh3d2(testCase: .should_fire_DeregistrationFailed_event)
    }

    // A push-to-start token added to an already-activated device (as done by
    // -[ARTPush registerPushToStartToken:]) is synced to Ably via a PATCH whose
    // recipient carries the token under the "pushToStart" apnsDeviceTokens key.
    func test__100__Activation_state_machine__State_WaitingForNewPushDeviceDetails__on_Event_GotPushDeviceDetails__with_push_to_start_token__PATCHes_recipient() throws {
        beforeEach__Activation_state_machine__State_WaitingForNewPushDeviceDetails()

        let expectedToken = "70757368-746f-2d73-7461-7274"
        stateMachine.rest.device.setAndPersistAPNSDeviceToken(expectedToken, tokenType: ARTAPNSDevicePushToStartTokenType)
        defer { stateMachine.rest.device.setAndPersistAPNSDeviceToken(nil, tokenType: ARTAPNSDevicePushToStartTokenType) }

        waitUntil(timeout: testTimeout) { done in
            stateMachine.transitions = { event, _, _ in
                if event is ARTPushActivationEventRegistrationSynced {
                    stateMachine.transitions = nil
                    done()
                }
            }
            stateMachine.send(ARTPushActivationEventGotPushDeviceDetails())
        }

        let request = try XCTUnwrap(httpExecutor.requests.first { req in
            req.httpMethod == "PATCH" && req.url?.path.hasPrefix("/push/deviceRegistrations/") == true
        }, "Should have a PATCH \"/push/deviceRegistrations/{id}\" request")
        let rawBody = try XCTUnwrap(request.httpBody, "Request should have a body")
        let decodedBody = try XCTUnwrap(try stateMachine.rest.defaultEncoder.decode(rawBody), "Decode request body failed")
        let body = try XCTUnwrap(decodedBody as? NSDictionary, "Request body is invalid")
        let push = try XCTUnwrap(body.value(forKey: "push") as? [String: Any], "Body should have a push")
        let recipient = try XCTUnwrap(push["recipient"] as? [String: Any], "push should have a recipient")
        let apnsDeviceTokens = try XCTUnwrap(recipient["apnsDeviceTokens"] as? [String: String], "recipient should have apnsDeviceTokens")
        XCTAssertEqual(apnsDeviceTokens["pushToStart"], expectedToken)
    }

    enum TestCase_ReusableTestsTestStateWaitingForRegistrationSyncThrough {
        case on_Event_CalledActivate
        case on_Event_RegistrationSynced
        case on_Event_SyncRegistrationFailed
    }

    // RSH3e
    func reusableTestsTestStateWaitingForRegistrationSyncThrough(_ fromEvent: ARTPushActivationEvent, testCase: TestCase_ReusableTestsTestStateWaitingForRegistrationSyncThrough, beforeEach contextBeforeEach: (() -> Void)? = nil, afterEach contextAfterEach: (() -> Void)? = nil) {
        func beforeEach() {
            contextBeforeEach?()

            storage = MockDeviceStorage(startWith: ARTPushActivationStateWaitingForRegistrationSync(machine: initialStateMachine, logger: .init(core: MockInternalLogCore()), from: fromEvent))
            rest.internal.storage = storage
            stateMachine = ARTPushActivationStateMachine(rest: rest.internal, delegate: StateMachineDelegate(), logger: .init(core: MockInternalLogCore()))
            (stateMachine.current as! ARTPushActivationStateWaitingForRegistrationSync).fromEvent = fromEvent
        }

        // RSH3e1
        func test__on_Event_CalledActivate() {
            beforeEach()

            var activatedCallbackCalled = false
            let hook = stateMachine.testSuite_injectIntoMethod(after: NSSelectorFromString("callActivatedCallback:")) {
                activatedCallbackCalled = true
            }
            defer { hook.remove() }

            stateMachine.send(ARTPushActivationEventCalledActivate())
            expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateWaitingForRegistrationSync.self))
            if !fromEvent.isKind(of: ARTPushActivationEventCalledActivate.self) { XCTAssertTrue(activatedCallbackCalled)
                XCTAssertEqual(stateMachine.pendingEvents.count, 0)
            } else {
                XCTAssertFalse(activatedCallbackCalled)
                XCTAssertEqual(stateMachine.pendingEvents.count, 1)
            }

            contextAfterEach?()
        }

        // RSH3e2
        func test__on_Event_RegistrationSynced() {
            beforeEach()

            var setAndPersistIdentityTokenDetailsCalled = false
            let hookDevice = stateMachine.rest.device.testSuite_injectIntoMethod(after: NSSelectorFromString("setAndPersistIdentityTokenDetails:")) {
                setAndPersistIdentityTokenDetailsCalled = true
            }
            defer { hookDevice.remove() }

            let delegate = StateMachineDelegate()
            stateMachine.delegate = delegate

            var activateCallbackCalled = false
            delegate.onDidActivateAblyPush = { error in
                XCTAssertNil(error)
                activateCallbackCalled = true
            }

            var updatedCallbackCalled = false
            delegate.onDidUpdateAblyPush = { error in
                XCTAssertNil(error)
                updatedCallbackCalled = true
            }

            let testIdentityTokenDetails = ARTDeviceIdentityTokenDetails(
                token: "123456",
                issued: Date(),
                expires: Date.distantFuture,
                capability: "",
                clientId: ""
            )

            stateMachine.send(ARTPushActivationEventRegistrationSynced(identityTokenDetails: testIdentityTokenDetails))
            expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateWaitingForNewPushDeviceDetails.self))
            XCTAssertTrue(setAndPersistIdentityTokenDetailsCalled)

            // RSH3e2c
            expect(updatedCallbackCalled).toEventually(equal(!(fromEvent is ARTPushActivationEventCalledActivate)), timeout: testTimeout)
            // RSH3e2b
            expect(activateCallbackCalled).toEventually(equal(fromEvent is ARTPushActivationEventCalledActivate), timeout: testTimeout)

            contextAfterEach?()
        }

        // RSH3e3
        func test__on_Event_SyncRegistrationFailed() {
            beforeEach()

            let expectedError = ARTErrorInfo(domain: ARTAblyErrorDomain, code: 1234, userInfo: nil)

            var updatedCallbackCalled = false
            let hook = stateMachine.testSuite_getArgument(from: NSSelectorFromString("callUpdatedCallback:"), at: 0, callback: { arg0 in
                updatedCallbackCalled = true
                guard let error = arg0 as? ARTErrorInfo else {
                    fail("Error is missing"); return
                }
                XCTAssertEqual(error, expectedError)
            })
            defer { hook.remove() }

            let delegate = StateMachineDelegate()
            stateMachine.delegate = delegate

            var activateCallbackCalled = false
            delegate.onDidActivateAblyPush = { error in
                XCTAssertEqual(error, expectedError)
                activateCallbackCalled = true
            }

            stateMachine.send(ARTPushActivationEventSyncRegistrationFailed(error: expectedError))
            expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateAfterRegistrationSyncFailed.self))

            // RSH3e3a
            expect(updatedCallbackCalled).toEventually(equal(!(fromEvent is ARTPushActivationEventCalledActivate)), timeout: testTimeout)
            // RSH3e3c
            expect(activateCallbackCalled).toEventually(equal(fromEvent is ARTPushActivationEventCalledActivate), timeout: testTimeout)

            contextAfterEach?()
        }

        switch testCase {
        case .on_Event_CalledActivate:
            test__on_Event_CalledActivate()
        case .on_Event_RegistrationSynced:
            test__on_Event_RegistrationSynced()
        case .on_Event_SyncRegistrationFailed:
            test__on_Event_SyncRegistrationFailed()
        }
    }

    func reusableTestsWrapper__Activation_state_machine__State_WaitingForRegistrationSync_through_ARTPushActivationEventCalledActivate__reusableTestsTestStateWaitingForRegistrationSyncThrough(testCase: TestCase_ReusableTestsTestStateWaitingForRegistrationSyncThrough) {
        reusableTestsTestStateWaitingForRegistrationSyncThrough(ARTPushActivationEventCalledActivate(), testCase: testCase)
    }

    func test__036__Activation_state_machine__State_WaitingForRegistrationSync_through_ARTPushActivationEventCalledActivate__on_Event_CalledActivate() {
        reusableTestsWrapper__Activation_state_machine__State_WaitingForRegistrationSync_through_ARTPushActivationEventCalledActivate__reusableTestsTestStateWaitingForRegistrationSyncThrough(testCase: .on_Event_CalledActivate)
    }

    func test__037__Activation_state_machine__State_WaitingForRegistrationSync_through_ARTPushActivationEventCalledActivate__on_Event_RegistrationSynced() {
        reusableTestsWrapper__Activation_state_machine__State_WaitingForRegistrationSync_through_ARTPushActivationEventCalledActivate__reusableTestsTestStateWaitingForRegistrationSyncThrough(testCase: .on_Event_RegistrationSynced)
    }

    func test__038__Activation_state_machine__State_WaitingForRegistrationSync_through_ARTPushActivationEventCalledActivate__on_Event_SyncRegistrationFailed() {
        reusableTestsWrapper__Activation_state_machine__State_WaitingForRegistrationSync_through_ARTPushActivationEventCalledActivate__reusableTestsTestStateWaitingForRegistrationSyncThrough(testCase: .on_Event_SyncRegistrationFailed)
    }

    func reusableTestsWrapper__Activation_state_machine__State_WaitingForRegistrationSync_through_ARTPushActivationEventGotPushDeviceDetails__reusableTestsTestStateWaitingForRegistrationSyncThrough(testCase: TestCase_ReusableTestsTestStateWaitingForRegistrationSyncThrough) {
        reusableTestsTestStateWaitingForRegistrationSyncThrough(ARTPushActivationEventGotPushDeviceDetails(), testCase: testCase)
    }

    func test__039__Activation_state_machine__State_WaitingForRegistrationSync_through_ARTPushActivationEventGotPushDeviceDetails__on_Event_CalledActivate() {
        reusableTestsWrapper__Activation_state_machine__State_WaitingForRegistrationSync_through_ARTPushActivationEventGotPushDeviceDetails__reusableTestsTestStateWaitingForRegistrationSyncThrough(testCase: .on_Event_CalledActivate)
    }

    func test__040__Activation_state_machine__State_WaitingForRegistrationSync_through_ARTPushActivationEventGotPushDeviceDetails__on_Event_RegistrationSynced() {
        reusableTestsWrapper__Activation_state_machine__State_WaitingForRegistrationSync_through_ARTPushActivationEventGotPushDeviceDetails__reusableTestsTestStateWaitingForRegistrationSyncThrough(testCase: .on_Event_RegistrationSynced)
    }

    func test__041__Activation_state_machine__State_WaitingForRegistrationSync_through_ARTPushActivationEventGotPushDeviceDetails__on_Event_SyncRegistrationFailed() {
        reusableTestsWrapper__Activation_state_machine__State_WaitingForRegistrationSync_through_ARTPushActivationEventGotPushDeviceDetails__reusableTestsTestStateWaitingForRegistrationSyncThrough(testCase: .on_Event_SyncRegistrationFailed)
    }

    // RSH3f

    func beforeEach__Activation_state_machine__State_AfterRegistrationSyncFailed() {
        storage = MockDeviceStorage(startWith: ARTPushActivationStateAfterRegistrationSyncFailed(machine: initialStateMachine, logger: .init(core: MockInternalLogCore())))
        rest.internal.storage = storage
        stateMachine = ARTPushActivationStateMachine(rest: rest.internal, delegate: StateMachineDelegate(), logger: .init(core: MockInternalLogCore()))
    }

    // RSH3f1

    func reusableTestsWrapper__Activation_state_machine__State_AfterRegistrationSyncFailed__on_Event_CalledActivate__reusableTestsRsh3a2a(testCase: TestCase_ReusableTestsRsh3a2a) throws {
        try reusableTestsRsh3a2a(testCase: testCase, beforeEach: beforeEach__Activation_state_machine__State_AfterRegistrationSyncFailed)
    }

    func test__042__Activation_state_machine__State_AfterRegistrationSyncFailed__on_Event_CalledActivate__the_local_device_has_id_and_deviceIdentityToken__emits_a_SyncRegistrationFailed_event_with_code_61002_if_client_IDs_don_t_match() throws {
        try reusableTestsWrapper__Activation_state_machine__State_AfterRegistrationSyncFailed__on_Event_CalledActivate__reusableTestsRsh3a2a(testCase: .the_local_device_has_id_and_deviceIdentityToken__emits_a_SyncRegistrationFailed_event_with_code_61002_if_client_IDs_don_t_match)
    }

    func test__043__Activation_state_machine__State_AfterRegistrationSyncFailed__on_Event_CalledActivate__the_local_device_has_id_and_deviceIdentityToken__the_local_DeviceDetails_matches_the_instance_s_client_ID__calls_registerCallback__transitions_to_WaitingForRegistrationSync() throws {
        try reusableTestsWrapper__Activation_state_machine__State_AfterRegistrationSyncFailed__on_Event_CalledActivate__reusableTestsRsh3a2a(testCase: .the_local_device_has_id_and_deviceIdentityToken__the_local_DeviceDetails_matches_the_instance_s_client_ID__calls_registerCallback__transitions_to_WaitingForRegistrationSync)
    }

    func test__044__Activation_state_machine__State_AfterRegistrationSyncFailed__on_Event_CalledActivate__the_local_device_has_id_and_deviceIdentityToken__the_local_DeviceDetails_matches_the_instance_s_client_ID__PUTs_device_registration__transitions_to_WaitingForRegistrationSync() throws {
        try reusableTestsWrapper__Activation_state_machine__State_AfterRegistrationSyncFailed__on_Event_CalledActivate__reusableTestsRsh3a2a(testCase: .the_local_device_has_id_and_deviceIdentityToken__the_local_DeviceDetails_matches_the_instance_s_client_ID__PUTs_device_registration__transitions_to_WaitingForRegistrationSync)
    }

    // RSH3f1

    func reusableTestsWrapper__Activation_state_machine__State_AfterRegistrationSyncFailed__on_Event_GotPushDeviceDetails__reusableTestsRsh3a2a(testCase: TestCase_ReusableTestsRsh3a2a) throws {
        try reusableTestsRsh3a2a(testCase: testCase, beforeEach: beforeEach__Activation_state_machine__State_AfterRegistrationSyncFailed)
    }

    func test__045__Activation_state_machine__State_AfterRegistrationSyncFailed__on_Event_GotPushDeviceDetails__the_local_device_has_id_and_deviceIdentityToken__emits_a_SyncRegistrationFailed_event_with_code_61002_if_client_IDs_don_t_match() throws {
        try reusableTestsWrapper__Activation_state_machine__State_AfterRegistrationSyncFailed__on_Event_GotPushDeviceDetails__reusableTestsRsh3a2a(testCase: .the_local_device_has_id_and_deviceIdentityToken__emits_a_SyncRegistrationFailed_event_with_code_61002_if_client_IDs_don_t_match)
    }

    func test__046__Activation_state_machine__State_AfterRegistrationSyncFailed__on_Event_GotPushDeviceDetails__the_local_device_has_id_and_deviceIdentityToken__the_local_DeviceDetails_matches_the_instance_s_client_ID__calls_registerCallback__transitions_to_WaitingForRegistrationSync() throws {
        try reusableTestsWrapper__Activation_state_machine__State_AfterRegistrationSyncFailed__on_Event_GotPushDeviceDetails__reusableTestsRsh3a2a(testCase: .the_local_device_has_id_and_deviceIdentityToken__the_local_DeviceDetails_matches_the_instance_s_client_ID__calls_registerCallback__transitions_to_WaitingForRegistrationSync)
    }

    func test__047__Activation_state_machine__State_AfterRegistrationSyncFailed__on_Event_GotPushDeviceDetails__the_local_device_has_id_and_deviceIdentityToken__the_local_DeviceDetails_matches_the_instance_s_client_ID__PUTs_device_registration__transitions_to_WaitingForRegistrationSync() throws {
        try reusableTestsWrapper__Activation_state_machine__State_AfterRegistrationSyncFailed__on_Event_GotPushDeviceDetails__reusableTestsRsh3a2a(testCase: .the_local_device_has_id_and_deviceIdentityToken__the_local_DeviceDetails_matches_the_instance_s_client_ID__PUTs_device_registration__transitions_to_WaitingForRegistrationSync)
    }

    // RSH3f2

    func reusableTestsWrapper__Activation_state_machine__State_AfterRegistrationSyncFailed__on_Event_CalledDeactivate__reusableTestsRsh3d2(testCase: TestCase_ReusableTestsRsh3d2) throws {
        try reusableTestsRsh3d2(testCase: testCase, beforeEach: beforeEach__Activation_state_machine__State_AfterRegistrationSyncFailed)
    }

    func test__048__Activation_state_machine__State_AfterRegistrationSyncFailed__on_Event_CalledDeactivate__should_use_custom_deregisterCallback_and_fire_Deregistered_event() throws {
        try reusableTestsWrapper__Activation_state_machine__State_AfterRegistrationSyncFailed__on_Event_CalledDeactivate__reusableTestsRsh3d2(testCase: .should_use_custom_deregisterCallback_and_fire_Deregistered_event)
    }

    func test__049__Activation_state_machine__State_AfterRegistrationSyncFailed__on_Event_CalledDeactivate__should_use_custom_deregisterCallback_and_fire_DeregistrationFailed_event() throws {
        try reusableTestsWrapper__Activation_state_machine__State_AfterRegistrationSyncFailed__on_Event_CalledDeactivate__reusableTestsRsh3d2(testCase: .should_use_custom_deregisterCallback_and_fire_DeregistrationFailed_event)
    }

    func test__050__Activation_state_machine__State_AfterRegistrationSyncFailed__on_Event_CalledDeactivate__should_fire_Deregistered_event_and_include_DeviceSecret_HTTP_header() throws {
        try reusableTestsWrapper__Activation_state_machine__State_AfterRegistrationSyncFailed__on_Event_CalledDeactivate__reusableTestsRsh3d2(testCase: .should_fire_Deregistered_event_and_include_DeviceSecret_HTTP_header)
    }

    func test__051__Activation_state_machine__State_AfterRegistrationSyncFailed__on_Event_CalledDeactivate__should_fire_Deregistered_event_and_include_DeviceIdentityToken_HTTP_header() throws {
        try reusableTestsWrapper__Activation_state_machine__State_AfterRegistrationSyncFailed__on_Event_CalledDeactivate__reusableTestsRsh3d2(testCase: .should_fire_Deregistered_event_and_include_DeviceIdentityToken_HTTP_header)
    }

    func test__052__Activation_state_machine__State_AfterRegistrationSyncFailed__on_Event_CalledDeactivate__should_fire_DeregistrationFailed_event() throws {
        try reusableTestsWrapper__Activation_state_machine__State_AfterRegistrationSyncFailed__on_Event_CalledDeactivate__reusableTestsRsh3d2(testCase: .should_fire_DeregistrationFailed_event)
    }

    // RSH3g

    func beforeEach__Activation_state_machine__State_WaitingForDeregistration() {
        storage = MockDeviceStorage(startWith: ARTPushActivationStateWaitingForDeregistration(machine: initialStateMachine, logger: .init(core: MockInternalLogCore())))
        rest.internal.storage = storage
        stateMachine = ARTPushActivationStateMachine(rest: rest.internal, delegate: StateMachineDelegate(), logger: .init(core: MockInternalLogCore()))
    }

    // RSH3g1
    func test__053__Activation_state_machine__State_WaitingForDeregistration__on_Event_CalledDeactivate() {
        beforeEach__Activation_state_machine__State_WaitingForDeregistration()

        stateMachine.send(ARTPushActivationEventCalledDeactivate())
        expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateWaitingForDeregistration.self))
    }

    // RSH3g2
    func test__054__Activation_state_machine__State_WaitingForDeregistration__on_Event_Deregistered() {
        storage = MockDeviceStorage(startWith: ARTPushActivationStateWaitingForDeregistration(machine: initialStateMachine, logger: .init(core: MockInternalLogCore())))

        let options = ARTClientOptions(key: "xxxx:xxxx")
        options.clientId = "client1"
        let rest = ARTRest(options: options)
        rest.internal.storage = storage
        stateMachine = ARTPushActivationStateMachine(rest: rest.internal, delegate: StateMachineDelegate(), logger: .init(core: MockInternalLogCore()))

        rest.internal.setupLocalDevice_nosync()

        XCTAssertEqual(stateMachine.rest.device.clientId, "client1")

        var deactivatedCallbackCalled = false
        let hook = stateMachine.testSuite_injectIntoMethod(after: NSSelectorFromString("callDeactivatedCallback:")) {
            deactivatedCallbackCalled = true
        }
        defer { hook.remove() }

        var resetDetailsCalled = false
        let hookDevice = stateMachine.rest.device.testSuite_injectIntoMethod(after: NSSelectorFromString("resetDetails")) {
            resetDetailsCalled = true
        }
        defer { hookDevice.remove() }

        stateMachine.send(ARTPushActivationEventDeregistered())
        expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateNotActivated.self))
        XCTAssertTrue(deactivatedCallbackCalled)
        XCTAssertTrue(resetDetailsCalled)

        // RSH3g2a
        XCTAssertNil(stateMachine.rest.device.identityTokenDetails)
        XCTAssertNil(stateMachine.rest.device.clientId)
        XCTAssertNil(stateMachine.rest.device.push.recipient["push"])

        XCTAssertNil(storage.object(forKey: ARTDeviceIdentityTokenKey))
        XCTAssertNil(ARTLocalDevice.apnsDeviceToken(ofType: ARTAPNSDeviceDefaultTokenType, from: storage))
        XCTAssertNil(ARTLocalDevice.apnsDeviceToken(ofType: ARTAPNSDeviceLocationTokenType, from: storage))

        // Should be replaced with `nil` checks after issue https://github.com/ably/specification/issues/180 resolved
        XCTAssertNotNil(stateMachine.rest.device.id)
        XCTAssertNotNil(stateMachine.rest.device.secret)
        XCTAssertEqual(storage.keysWritten[ARTDeviceIdKey] as? String, stateMachine.rest.device.id)
        XCTAssertEqual(storage.keysWritten[ARTDeviceSecretKey] as? String, stateMachine.rest.device.secret)
    }

    // RSH3g3
    func test__055__Activation_state_machine__State_WaitingForDeregistration__on_Event_DeregistrationFailed() {
        beforeEach__Activation_state_machine__State_WaitingForDeregistration()

        let expectedError = ARTErrorInfo(domain: ARTAblyErrorDomain, code: 1234, userInfo: nil)

        var deactivatedCallbackCalled = false
        let hook = stateMachine.testSuite_getArgument(from: NSSelectorFromString("callDeactivatedCallback:"), at: 0, callback: { arg0 in
            deactivatedCallbackCalled = true
            guard let error = arg0 as? ARTErrorInfo else {
                fail("Error is missing"); return
            }
            XCTAssertEqual(error, expectedError)
        })
        defer { hook.remove() }

        stateMachine.send(ARTPushActivationEventDeregistrationFailed(error: expectedError))
        expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateWaitingForDeregistration.self))
        XCTAssertTrue(deactivatedCallbackCalled)
    }

    // RSH8b, RSH3a2b, RSH3g2a
    func test__056__Activation_state_machine__should_be_possible_to_activate_and_deactivate_and_then_activate_again_with_different_clientId() {
        beforeEach__Activation_state_machine__State_NotActivated()

        let options1 = ARTClientOptions(key: "xxxx:xxxx")
        options1.clientId = "client1"
        let rest1 = ARTRest(options: options1)
        httpExecutor = MockHTTPExecutor()
        rest1.internal.httpExecutor = httpExecutor
        rest1.internal.storage = storage

        let stateMachineDelegate = StateMachineDelegate()
        let stateMachine1 = ARTPushActivationStateMachine(rest: rest1.internal, delegate: stateMachineDelegate, logger: .init(core: MockInternalLogCore()))

        let testDeviceToken = "xxxx-xxxx-xxxx-xxxx-xxxx"
        stateMachine1.rest.device.setAndPersistAPNSDeviceToken(testDeviceToken)
        defer { stateMachine1.rest.device.setAndPersistAPNSDeviceToken(nil) }

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(3, done: done)
            stateMachine1.transitions = { event, _, _ in
                if event is ARTPushActivationEventCalledActivate {
                    XCTAssertEqual(rest1.internal.device_nosync.clientId, "client1")
                    partialDone()
                }
                if event is ARTPushActivationEventGotPushDeviceDetails {
                    partialDone()
                    stateMachine1.send(ARTPushActivationEventCalledDeactivate())
                }
                if event is ARTPushActivationEventCalledDeactivate {
                    partialDone()
                }
            }
            stateMachine1.send(ARTPushActivationEventCalledActivate())
        }

        XCTAssertNil(rest1.device.clientId) // after deactivation, RSH3g2a

        let options2 = ARTClientOptions(key: "xxxx:xxxx")
        options2.clientId = "client2"
        let rest2 = ARTRest(options: options2)
        rest2.internal.storage = storage
        rest2.internal.httpExecutor = httpExecutor

        XCTAssertNil(rest2.device.clientId)

        let stateMachine2 = ARTPushActivationStateMachine(rest: rest2.internal, delegate: stateMachineDelegate, logger: .init(core: MockInternalLogCore()))
        stateMachine2.send(ARTPushActivationEventCalledActivate())

        XCTAssertEqual(rest2.device.clientId, "client2")
        XCTAssertTrue(rest1.device === rest2.device)
    }

    // RSH4
    func test__005__Activation_state_machine__should_queue_event_that_has_no_transition_defined_for_it() throws {
        // Start with WaitingForDeregistration state
        let storage = MockDeviceStorage(startWith: ARTPushActivationStateWaitingForDeregistration(machine: initialStateMachine, logger: .init(core: MockInternalLogCore())))
        rest.internal.storage = storage
        let stateMachine = ARTPushActivationStateMachine(rest: rest.internal, delegate: StateMachineDelegate(), logger: .init(core: MockInternalLogCore()))

        stateMachine.transitions = { _, _, _ in
            fail("Should not handle the CalledActivate event because it should be queued")
        }

        stateMachine.send(ARTPushActivationEventCalledActivate())

        expect(stateMachine.pendingEvents).toEventually(haveCount(1), timeout: testTimeout)
        stateMachine.transitions = nil

        let pendingEvent = try XCTUnwrap(stateMachine.pendingEvents.first, "Pending event is missing")
        expect(pendingEvent).to(beAKindOf(ARTPushActivationEventCalledActivate.self))

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)
            stateMachine.transitions = { event, previousState, currentState in
                if previousState is ARTPushActivationStateWaitingForDeregistration, currentState is ARTPushActivationStateNotActivated {
                    // Handle Deregistered event
                    partialDone()
                } else if event is ARTPushActivationEventDeregistered, previousState is ARTPushActivationStateNotActivated, currentState is ARTPushActivationStateWaitingForPushDeviceDetails {
                    // Consume queued CalledActivate event
                    partialDone()
                }
            }
            stateMachine.send(ARTPushActivationEventDeregistered())
            expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateWaitingForPushDeviceDetails.self))
        }
        stateMachine.transitions = nil

        expect(stateMachine.pendingEvents).to(beEmpty())
    }

    // RSH5
    func test__006__Activation_state_machine__event_handling_sould_be_atomic_and_sequential() {
        let storage = MockDeviceStorage(startWith: ARTPushActivationStateWaitingForDeregistration(machine: initialStateMachine, logger: .init(core: MockInternalLogCore())))
        rest.internal.storage = storage
        let stateMachine = ARTPushActivationStateMachine(rest: rest.internal, delegate: StateMachineDelegate(), logger: .init(core: MockInternalLogCore()))
        stateMachine.send(ARTPushActivationEventCalledActivate())
        DispatchQueue(label: "QueueA").sync {
            stateMachine.send(ARTPushActivationEventDeregistered())
        }
        expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateWaitingForPushDeviceDetails.self))
    }

    func test__001__should_remove_identityTokenDetails_from_cache_and_storage() {
        let storage = MockDeviceStorage()
        rest.internal.storage = storage
        rest.device.setAndPersistIdentityTokenDetails(nil)
        rest.internal.resetDeviceSingleton()
        XCTAssertNil(rest.device.identityTokenDetails)
        XCTAssertEqual(rest.device.isRegistered(), false)
        XCTAssertNil(storage.object(forKey: ARTDeviceIdentityTokenKey))
    }

    enum TestCase_ReusableTestsRsh3a2a {
        case the_local_device_has_id_and_deviceIdentityToken__emits_a_SyncRegistrationFailed_event_with_code_61002_if_client_IDs_don_t_match
        case the_local_device_has_id_and_deviceIdentityToken__the_local_DeviceDetails_matches_the_instance_s_client_ID__calls_registerCallback__transitions_to_WaitingForRegistrationSync
        case the_local_device_has_id_and_deviceIdentityToken__the_local_DeviceDetails_matches_the_instance_s_client_ID__PUTs_device_registration__transitions_to_WaitingForRegistrationSync
    }

    func reusableTestsRsh3a2a(testCase: TestCase_ReusableTestsRsh3a2a, beforeEach contextBeforeEach: (() -> Void)? = nil, afterEach contextAfterEach: (() -> Void)? = nil) throws {
        let testDeviceId = "aaaa"

        // RSH3a2a1
        func test__the_local_device_has_id_and_deviceIdentityToken__emits_a_SyncRegistrationFailed_event_with_code_61002_if_client_IDs_don_t_match() {
            contextBeforeEach?()

            let options = ARTClientOptions(key: "xxxx:xxxx")
            options.clientId = "deviceClient"
            let rest = ARTRest(options: options)
            rest.internal.storage = storage
            rest.internal.setupLocalDevice_nosync()

            XCTAssertEqual(rest.device.clientId, "deviceClient")

            let newOptions = ARTClientOptions(key: "xxxx:xxxx")
            newOptions.clientId = "instanceClient"
            let newRest = ARTRest(options: newOptions)
            newRest.internal.storage = storage
            let stateMachine = ARTPushActivationStateMachine(rest: newRest.internal, delegate: StateMachineDelegate(), logger: .init(core: MockInternalLogCore()))

            storage.simulateOnNextRead(string: testDeviceId, for: ARTDeviceIdKey)

            let testDeviceIdentityTokenDetails = ARTDeviceIdentityTokenDetails(token: "xxxx-xxxx-xxx", issued: Date(), expires: Date.distantFuture, capability: "", clientId: "deviceClient")
            stateMachine.rest.device.setAndPersistIdentityTokenDetails(testDeviceIdentityTokenDetails)
            defer { stateMachine.rest.device.setAndPersistIdentityTokenDetails(nil) }

            waitUntil(timeout: testTimeout) { done in
                stateMachine.transitions = { event, _, _ in
                    if let event = event as? ARTPushActivationEventSyncRegistrationFailed {
                        XCTAssertEqual(event.error.code, 61002)
                        done()
                    }
                }
                stateMachine.send(ARTPushActivationEventCalledActivate())
            }

            contextAfterEach?()
        }

        func beforeEach__the_local_device_has_id_and_deviceIdentityToken__the_local_DeviceDetails_matches_the_instance_s_client_ID() {
            contextBeforeEach?()

            storage.simulateOnNextRead(string: testDeviceId, for: ARTDeviceIdKey)

            let testDeviceIdentityTokenDetails = ARTDeviceIdentityTokenDetails(token: "xxxx-xxxx-xxx", issued: Date(), expires: Date.distantFuture, capability: "", clientId: "")
            stateMachine.rest.device.setAndPersistIdentityTokenDetails(testDeviceIdentityTokenDetails)
        }

        func afterEach__the_local_device_has_id_and_deviceIdentityToken__the_local_DeviceDetails_matches_the_instance_s_client_ID() {
            stateMachine.rest.device.setAndPersistIdentityTokenDetails(nil)
            contextAfterEach?()
        }

        // RSH3a2a2, RSH3a2a4
        func test__the_local_device_has_id_and_deviceIdentityToken__the_local_DeviceDetails_matches_the_instance_s_client_ID__calls_registerCallback__transitions_to_WaitingForRegistrationSync() {
            beforeEach__the_local_device_has_id_and_deviceIdentityToken__the_local_DeviceDetails_matches_the_instance_s_client_ID()

            let delegate = StateMachineDelegateCustomCallbacks()
            stateMachine.delegate = delegate

            waitUntil(timeout: testTimeout) { done in
                let partialDone = AblyTests.splitDone(3, done: done)
                stateMachine.transitions = { event, _, currentState in
                    if event is ARTPushActivationEventCalledActivate {
                        expect(currentState).to(beAKindOf(ARTPushActivationStateWaitingForRegistrationSync.self))
                        partialDone()
                    } else if event is ARTPushActivationEventRegistrationSynced {
                        stateMachine.transitions = nil
                        partialDone()
                    }
                }
                delegate.onPushCustomRegister = { error, deviceDetails in
                    XCTAssertNil(error)
                    XCTAssertTrue(deviceDetails === rest.device)
                    partialDone()
                    return nil
                }
                stateMachine.send(ARTPushActivationEventCalledActivate())
            }

            XCTAssertEqual(httpExecutor.requests.count, 0)

            afterEach__the_local_device_has_id_and_deviceIdentityToken__the_local_DeviceDetails_matches_the_instance_s_client_ID()
        }

        // RSH3a2a3, RSH3a2a4, RSH3b3c
        func test__the_local_device_has_id_and_deviceIdentityToken__the_local_DeviceDetails_matches_the_instance_s_client_ID__PUTs_device_registration__transitions_to_WaitingForRegistrationSync() throws {
            beforeEach__the_local_device_has_id_and_deviceIdentityToken__the_local_DeviceDetails_matches_the_instance_s_client_ID()

            let delegate = StateMachineDelegate()
            stateMachine.delegate = delegate

            waitUntil(timeout: testTimeout) { done in
                let partialDone = AblyTests.splitDone(2, done: done)
                stateMachine.transitions = { event, _, currentState in
                    if event is ARTPushActivationEventCalledActivate {
                        expect(currentState).to(beAKindOf(ARTPushActivationStateWaitingForRegistrationSync.self))
                        partialDone()
                    } else if event is ARTPushActivationEventRegistrationSynced || event is ARTPushActivationEventSyncRegistrationFailed {
                        stateMachine.transitions = nil
                        partialDone()
                    }
                }
                stateMachine.send(ARTPushActivationEventCalledActivate())
            }

            let requests = httpExecutor.requests.compactMap { $0.url?.path }.filter { $0 == "/push/deviceRegistrations/\(rest.device.id)" }
            XCTAssertEqual(requests.count, 1)

            let request = try XCTUnwrap(httpExecutor.requests.first, "Should have a \"/push/deviceRegistrations\" request")
            let url = try XCTUnwrap(request.url, "Request should have a \"/push/deviceRegistrations\" URL")
            let rawBody = try XCTUnwrap(request.httpBody, "Request should have a body")
            let decodedBody = try XCTUnwrap(try stateMachine.rest.defaultEncoder.decode(rawBody), "Decode request body failed")
            let body = try XCTUnwrap(decodedBody as? NSDictionary, "Request body is invalid")

            XCTAssertEqual(url.host, rest.internal.options.restUrl().host)
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertEqual(body.value(forKey: "id") as? String, rest.device.id)
            XCTAssertEqual(body.value(forKey: "push") as? [String: [String: AnyHashable]], expectedPushRecipient)
            XCTAssertEqual(body.value(forKey: "formFactor") as? String, expectedFormFactor)
            XCTAssertEqual(body.value(forKey: "platform") as? String, expectedPlatform)

            afterEach__the_local_device_has_id_and_deviceIdentityToken__the_local_DeviceDetails_matches_the_instance_s_client_ID()
        }

        switch testCase {
        case .the_local_device_has_id_and_deviceIdentityToken__emits_a_SyncRegistrationFailed_event_with_code_61002_if_client_IDs_don_t_match:
            test__the_local_device_has_id_and_deviceIdentityToken__emits_a_SyncRegistrationFailed_event_with_code_61002_if_client_IDs_don_t_match()
        case .the_local_device_has_id_and_deviceIdentityToken__the_local_DeviceDetails_matches_the_instance_s_client_ID__calls_registerCallback__transitions_to_WaitingForRegistrationSync:
            test__the_local_device_has_id_and_deviceIdentityToken__the_local_DeviceDetails_matches_the_instance_s_client_ID__calls_registerCallback__transitions_to_WaitingForRegistrationSync()
        case .the_local_device_has_id_and_deviceIdentityToken__the_local_DeviceDetails_matches_the_instance_s_client_ID__PUTs_device_registration__transitions_to_WaitingForRegistrationSync:
            try test__the_local_device_has_id_and_deviceIdentityToken__the_local_DeviceDetails_matches_the_instance_s_client_ID__PUTs_device_registration__transitions_to_WaitingForRegistrationSync()
        }
    }

    enum TestCase_ReusableTestsRsh3d2 {
        case should_use_custom_deregisterCallback_and_fire_Deregistered_event
        case should_use_custom_deregisterCallback_and_fire_DeregistrationFailed_event
        case should_fire_Deregistered_event_and_include_DeviceSecret_HTTP_header
        case should_fire_Deregistered_event_and_include_DeviceIdentityToken_HTTP_header
        case should_fire_DeregistrationFailed_event
    }

    func reusableTestsRsh3d2(testCase: TestCase_ReusableTestsRsh3d2, beforeEach contextBeforeEach: (() -> Void)? = nil, afterEach contextAfterEach: (() -> Void)? = nil) throws {
        // RSH3d2a, RSH3d2c, RSH3d2d
        func test__should_use_custom_deregisterCallback_and_fire_Deregistered_event() {
            contextBeforeEach?()

            let delegate = StateMachineDelegateCustomCallbacks()
            stateMachine.delegate = delegate

            waitUntil(timeout: testTimeout) { done in
                let partialDone = AblyTests.splitDone(3, done: done)
                stateMachine.transitions = { event, _, currentState in
                    if event is ARTPushActivationEventCalledDeactivate {
                        // RSH3d2d
                        expect(currentState).to(beAKindOf(ARTPushActivationStateWaitingForDeregistration.self))
                        partialDone()
                    } else if event is ARTPushActivationEventDeregistered {
                        stateMachine.transitions = nil
                        partialDone()
                    }
                }
                delegate.onPushCustomDeregister = { error, deviceId in
                    XCTAssertNil(error)
                    XCTAssertEqual(deviceId, rest.device.id)
                    partialDone()
                    return nil
                }
                stateMachine.send(ARTPushActivationEventCalledDeactivate())
            }

            expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateNotActivated.self))
            XCTAssertEqual(httpExecutor.requests.count, 0)

            contextAfterEach?()
        }

        // RSH3d2c
        func test__should_use_custom_deregisterCallback_and_fire_DeregistrationFailed_event() {
            contextBeforeEach?()

            let delegate = StateMachineDelegateCustomCallbacks()
            stateMachine.delegate = delegate

            waitUntil(timeout: testTimeout) { done in
                let simulatedError = NSError(domain: ARTAblyErrorDomain, code: 1234, userInfo: nil)
                let partialDone = AblyTests.splitDone(3, done: done)
                stateMachine.transitions = { event, _, currentState in
                    if event is ARTPushActivationEventCalledDeactivate {
                        expect(currentState).to(beAKindOf(ARTPushActivationStateWaitingForDeregistration.self))
                        partialDone()
                    } else if let event = event as? ARTPushActivationEventDeregistrationFailed {
                        XCTAssertEqual(event.error.domain, ARTAblyErrorDomain)
                        XCTAssertEqual(event.error.code, simulatedError.code)
                        stateMachine.transitions = nil
                        partialDone()
                    }
                }
                delegate.onPushCustomDeregister = { error, deviceId in
                    XCTAssertNil(error)
                    XCTAssertEqual(deviceId, rest.device.id)
                    partialDone()
                    return simulatedError
                }
                stateMachine.send(ARTPushActivationEventCalledDeactivate())
            }

            expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateWaitingForDeregistration.self))
            XCTAssertEqual(httpExecutor.requests.count, 0)

            contextAfterEach?()
        }

        // RSH3d2b, RSH3d2c, RSH3d2d
        func test__should_fire_Deregistered_event_and_include_DeviceSecret_HTTP_header() throws {
            contextBeforeEach?()

            rest.internal.setupLocalDevice_nosync()

            let delegate = StateMachineDelegate()
            stateMachine.delegate = delegate

            let deviceId = rest.device.id
            let deviceSecret = rest.device.secret

            waitUntil(timeout: testTimeout) { done in
                let partialDone = AblyTests.splitDone(2, done: done)
                stateMachine.transitions = { event, _, currentState in
                    if event is ARTPushActivationEventCalledDeactivate {
                        // RSH3d2d
                        expect(currentState).to(beAKindOf(ARTPushActivationStateWaitingForDeregistration.self))
                        partialDone()
                    } else if event is ARTPushActivationEventDeregistered {
                        stateMachine.transitions = nil
                        partialDone()
                    }
                }
                stateMachine.send(ARTPushActivationEventCalledDeactivate())
            }

            expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateNotActivated.self))
            XCTAssertEqual(httpExecutor.requests.count, 1)
            let requests = httpExecutor.requests.compactMap { $0.url?.path }.filter { $0 == "/push/deviceRegistrations/\(deviceId)" }
            XCTAssertEqual(requests.count, 1)

            let request = try XCTUnwrap(httpExecutor.requests.first, "Should have a \"/push/deviceRegistrations\" request")
            let url = try XCTUnwrap(request.url, "Request should have a \"/push/deviceRegistrations\" URL")

            XCTAssertEqual(url.host, rest.internal.options.restUrl().host)
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertNotNil(request.allHTTPHeaderFields?["Authorization"])
            let deviceAuthorization = request.allHTTPHeaderFields?["X-Ably-DeviceSecret"]
            XCTAssertEqual(deviceAuthorization, deviceSecret)

            contextAfterEach?()
        }

        // RSH3d2b, RSH3d2c, RSH3d2d
        func test__should_fire_Deregistered_event_and_include_DeviceIdentityToken_HTTP_header() throws {
            contextBeforeEach?()

            rest.internal.setupLocalDevice_nosync()

            let delegate = StateMachineDelegate()
            stateMachine.delegate = delegate

            let testIdentityTokenDetails = ARTDeviceIdentityTokenDetails(
                token: "123456",
                issued: Date(),
                expires: Date.distantFuture,
                capability: "",
                clientId: ""
            )

            XCTAssertNil(rest.device.identityTokenDetails)
            rest.device.setAndPersistIdentityTokenDetails(testIdentityTokenDetails)
            defer { rest.device.setAndPersistIdentityTokenDetails(nil) }
            XCTAssertNotNil(rest.device.identityTokenDetails)

            let deviceId = rest.device.id

            waitUntil(timeout: testTimeout) { done in
                let partialDone = AblyTests.splitDone(2, done: done)
                stateMachine.transitions = { event, _, currentState in
                    if event is ARTPushActivationEventCalledDeactivate {
                        // RSH3d2d
                        expect(currentState).to(beAKindOf(ARTPushActivationStateWaitingForDeregistration.self))
                        partialDone()
                    } else if event is ARTPushActivationEventDeregistered {
                        stateMachine.transitions = nil
                        partialDone()
                    }
                }
                stateMachine.send(ARTPushActivationEventCalledDeactivate())
            }

            expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateNotActivated.self))
            XCTAssertEqual(httpExecutor.requests.count, 1)
            let requests = httpExecutor.requests.compactMap { $0.url?.path }.filter { $0 == "/push/deviceRegistrations/\(deviceId)" }
            XCTAssertEqual(requests.count, 1)

            let request = try XCTUnwrap(httpExecutor.requests.first, "Should have a \"/push/deviceRegistrations\" request")
            let url = try XCTUnwrap(request.url, "Request should have a \"/push/deviceRegistrations\" URL")

            XCTAssertEqual(url.host, rest.internal.options.restUrl().host)
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertNil(rest.device.identityTokenDetails)
            XCTAssertNotNil(request.allHTTPHeaderFields?["Authorization"])
            let deviceAuthorization = request.allHTTPHeaderFields?["X-Ably-DeviceToken"]
            XCTAssertEqual(deviceAuthorization, testIdentityTokenDetails.token.base64Encoded())

            contextAfterEach?()
        }

        // RSH3d2c
        func test__should_fire_DeregistrationFailed_event() throws {
            contextBeforeEach?()

            rest.internal.setupLocalDevice_nosync()

            let delegate = StateMachineDelegate()
            stateMachine.delegate = delegate

            let simulatedError = NSError(domain: ARTAblyErrorDomain, code: 1234, userInfo: nil)
            httpExecutor.simulateIncomingErrorOnNextRequest(simulatedError)

            waitUntil(timeout: testTimeout) { done in
                let partialDone = AblyTests.splitDone(2, done: done)
                stateMachine.transitions = { event, _, currentState in
                    if event is ARTPushActivationEventCalledDeactivate {
                        expect(currentState).to(beAKindOf(ARTPushActivationStateWaitingForDeregistration.self))
                        partialDone()
                    } else if let event = event as? ARTPushActivationEventDeregistrationFailed {
                        XCTAssertEqual(event.error.domain, ARTAblyErrorDomain)
                        XCTAssertEqual(event.error.code, simulatedError.code)
                        stateMachine.transitions = nil
                        partialDone()
                    }
                }
                stateMachine.send(ARTPushActivationEventCalledDeactivate())
            }

            expect(stateMachine.current).to(beAKindOf(ARTPushActivationStateWaitingForDeregistration.self))
            XCTAssertEqual(httpExecutor.requests.count, 1)
            let requests = httpExecutor.requests.compactMap { $0.url?.path }.filter { $0 == "/push/deviceRegistrations/\(rest.device.id)" }
            XCTAssertEqual(requests.count, 1)

            let request = try XCTUnwrap(httpExecutor.requests.first, "Should have a \"/push/deviceRegistrations\" request")
            let url = try XCTUnwrap(request.url, "Request should have a \"/push/deviceRegistrations\" URL")

            XCTAssertEqual(url.host, rest.internal.options.restUrl().host)
            XCTAssertEqual(request.httpMethod, "DELETE")

            contextAfterEach?()
        }

        switch testCase {
        case .should_use_custom_deregisterCallback_and_fire_Deregistered_event:
            test__should_use_custom_deregisterCallback_and_fire_Deregistered_event()
        case .should_use_custom_deregisterCallback_and_fire_DeregistrationFailed_event:
            test__should_use_custom_deregisterCallback_and_fire_DeregistrationFailed_event()
        case .should_fire_Deregistered_event_and_include_DeviceSecret_HTTP_header:
            try test__should_fire_Deregistered_event_and_include_DeviceSecret_HTTP_header()
        case .should_fire_Deregistered_event_and_include_DeviceIdentityToken_HTTP_header:
            try test__should_fire_Deregistered_event_and_include_DeviceIdentityToken_HTTP_header()
        case .should_fire_DeregistrationFailed_event:
            try test__should_fire_DeregistrationFailed_event()
        }
    }
}

class StateMachineDelegate: NSObject, ARTPushRegistererDelegate {
    var onDidActivateAblyPush: ((ARTErrorInfo?) -> Void)?
    var onDidUpdateAblyPush: ((ARTErrorInfo?) -> Void)?
    var onDidDeactivateAblyPush: ((ARTErrorInfo?) -> Void)?
    var onDidAblyPushRegistrationFail: ((ARTErrorInfo?) -> Void)?

    func didActivateAblyPush(_ error: ARTErrorInfo?) {
        onDidActivateAblyPush?(error)
    }

    func didUpdateAblyPush(_ error: ARTErrorInfo?) {
        onDidUpdateAblyPush?(error)
    }

    func didDeactivateAblyPush(_ error: ARTErrorInfo?) {
        onDidDeactivateAblyPush?(error)
    }

    func didAblyPushRegistrationFail(_ error: ARTErrorInfo?) {
        onDidAblyPushRegistrationFail?(error)
    }
}

typealias ARTDeviceId = String

class StateMachineDelegateCustomCallbacks: StateMachineDelegate {
    var onPushCustomRegister: ((ARTErrorInfo?, ARTDeviceDetails?) -> NSError?)?
    var onPushCustomRegisterIdentity: ((ARTErrorInfo?, ARTDeviceDetails?) throws -> ARTDeviceIdentityTokenDetails)?
    var onPushCustomDeregister: ((ARTErrorInfo?, ARTDeviceId?) -> NSError?)?

    func ablyPushCustomRegister(_ error: ARTErrorInfo?, deviceDetails: ARTDeviceDetails?, callback: @escaping (ARTDeviceIdentityTokenDetails?, ARTErrorInfo?) -> Void) {
        var registerError: NSError?
        var identity: ARTDeviceIdentityTokenDetails?
        if let register = onPushCustomRegister {
            registerError = register(error, deviceDetails)
            identity = ARTDeviceIdentityTokenDetails(token: "123456", issued: Date(), expires: Date.distantFuture, capability: "", clientId: "")
        } else {
            do {
                identity = try onPushCustomRegisterIdentity!(error, deviceDetails)
            } catch {
                registerError = error as NSError
            }
        }
        delay(0) {
            callback(identity, registerError == nil ? nil : ARTErrorInfo.create(from: registerError!))
        }
    }

    func ablyPushCustomDeregister(_ error: ARTErrorInfo?, deviceId: String?, callback: ((ARTErrorInfo?) -> Void)? = nil) {
        let error = onPushCustomDeregister?(error, deviceId)
        delay(0) {
            callback?(error == nil ? nil : ARTErrorInfo.create(from: error!))
        }
    }
}
#endif
