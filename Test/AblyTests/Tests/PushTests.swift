#if os(iOS)
import AblyPubSubDevice
import AblyTesting
import AblyTestingObjC
import Nimble
import XCTest

private var rest: ARTHttpClient!
private var mockHttpExecutor: MockHTTPExecutor!
private var storage: MockDeviceStorage!
private var stateMachineDelegate: StateMachineDelegate!

class PushTests: XCTestCase {
    enum TestDeviceToken {
        static let tokenBase64 = "HYRXxPSQdt1pnxqtDAvc6PTTLH7N6okiBhYyLClJdmQ="
        static let tokenData = Data(base64Encoded: tokenBase64, options: [])!
        static let tokenString = tokenData.map { String(format: "%02x", $0) }.joined()
    }

    enum TestLocationDeviceToken {
        static let tokenBase64 = "bG9jYXRpb24gZGV2aWNlIHRva2Vu"
        static let tokenData = Data(base64Encoded: tokenBase64, options: [])!
        static let tokenString = tokenData.map { String(format: "%02x", $0) }.joined()
    }

    enum TestPushToStartToken {
        static let tokenBase64 = "cHVzaC10by1zdGFydCB0b2tlbg=="
        static let tokenData = Data(base64Encoded: tokenBase64, options: [])!
        static let tokenString = tokenData.map { String(format: "%02x", $0) }.joined()
    }

    // XCTest invokes this method before executing the first test in the test suite. We use it to ensure that the global variables are initialized at the same moment, and in the same order, as they would have been when we used the Quick testing framework.
    override class var defaultTestSuite: XCTestSuite {
        _ = rest
        _ = mockHttpExecutor
        _ = storage
        _ = stateMachineDelegate

        return super.defaultTestSuite
    }

    override func setUp() {
        super.setUp()

        // Start from a clean on-disk device storage
        AblyTests.clearOnDiskDeviceStorage()

        rest = ARTHttpClient(key: "xxxx:xxxx")
        mockHttpExecutor = MockHTTPExecutor()
        rest.internal.httpExecutor = mockHttpExecutor
        storage = MockDeviceStorage()
        rest.internal.storage = storage
        stateMachineDelegate = StateMachineDelegate()
        rest.push.internal.createActivationStateMachine(withDelegate: stateMachineDelegate!)
        rest.internal.resetDeviceSingleton()
    }

    // RSH2

    // RSH2a
    func test__001__activation__activate_method_should_send_a_CalledActivate_event_to_the_state_machine() {
        defer { rest.push.internal.activationMachine.transitions = nil }
        waitUntil(timeout: testTimeout) { done in
            rest.push.internal.activationMachine.transitions = { event, _, _ in
                if event is ARTPushActivationEventCalledActivate {
                    done()
                }
            }
            rest.push.activate()
        }
    }

    // RSH2b
    func test__002__activation__deactivate_method_should_send_a_CalledDeactivate_event_to_the_state_machine() {
        defer { rest.push.internal.activationMachine.transitions = nil }
        waitUntil(timeout: testTimeout) { done in
            rest.push.internal.activationMachine.transitions = { event, _, _ in
                if event is ARTPushActivationEventCalledDeactivate {
                    done()
                }
            }
            rest.push.deactivate()
        }
    }

    // RSH2c / RSH8g
    func test__003__activation__should_handle_GotPushDeviceDetails_event_when_platform_s_APIs_sends_the_details_for_push_notifications() {
        let stateMachine = rest.push.internal.activationMachine
        let testDeviceToken = "xxxx-xxxx-xxxx-xxxx-xxxx"
        stateMachine.rest.device.setAndPersistAPNSDeviceToken(testDeviceToken)
        let stateMachineDelegate = StateMachineDelegate()
        stateMachine.delegate = stateMachineDelegate
        defer {
            stateMachine.transitions = nil
            stateMachine.delegate = nil
            stateMachine.rest.device.setAndPersistAPNSDeviceToken(nil)
        }
        waitUntil(timeout: testTimeout) { done in
            stateMachine.transitions = { event, _, _ in
                if event is ARTPushActivationEventGotPushDeviceDetails {
                    done()
                }
            }
            rest.push.activate()
        }
    }

    // RSH2d / RSH8h
    func test__004__activation__sends_GettingPushDeviceDetailsFailed_when_push_registration_fails() {
        let stateMachine = rest.push.internal.activationMachine
        defer { stateMachine.transitions = nil }
        waitUntil(timeout: testTimeout) { done in
            stateMachine.transitions = { event, _, _ in
                if event is ARTPushActivationEventGettingPushDeviceDetailsFailed {
                    done()
                }
            }
            rest.push.activate()

            let error = NSError(domain: ARTAblyErrorDomain, code: 42, userInfo: nil)
            ARTPushInternal.didFailToRegisterForRemoteNotificationsWithError(error, rest: rest)
        }
    }

    // https://github.com/ably/ably-cocoa/issues/877
    func test__005__activation__should_update_LocalDevice_clientId_when_it_s_null_with_auth_clientId() throws {
        let test = Test()
        let expectedClientId = "foo"
        let options = try AblyTests.clientOptions(for: test)

        options.authCallback = { _, completion in
            getTestTokenDetails(for: test, clientId: expectedClientId, completion: { result in
                guard case .success(let tokenDetails) = result else {
                    fail("TokenDetails are missing"); return
                }
                XCTAssertEqual(tokenDetails.clientId, expectedClientId)
                completion(tokenDetails, nil)
            })
        }

        let rest = ARTHttpClient(options: options)
        let mockHttpExecutor = MockHTTPExecutor()
        rest.internal.httpExecutor = mockHttpExecutor
        let storage = MockDeviceStorage()
        rest.internal.storage = storage

        rest.internal.resetDeviceSingleton()

        var capturedStateMachine: ARTPushActivationStateMachine?
        waitUntil(timeout: testTimeout) { done in
            rest.push.internal.getActivationMachine { machine in
                capturedStateMachine = machine
                done()
            }
        }
        let stateMachine = try XCTUnwrap(capturedStateMachine, "waitUntil timed out before stateMachine was set")

        let testDeviceToken = "xxxx-xxxx-xxxx-xxxx-xxxx"
        stateMachine.rest.device.setAndPersistAPNSDeviceToken(testDeviceToken)
        let stateMachineDelegate = StateMachineDelegate()
        stateMachine.delegate = stateMachineDelegate
        defer {
            stateMachine.transitions = nil
            stateMachine.delegate = nil
            stateMachine.rest.device.setAndPersistAPNSDeviceToken(nil)
        }

        XCTAssertNil(rest.device.clientId)
        XCTAssertNil(rest.auth.clientId)

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)
            stateMachine.transitions = { event, _, _ in
                if event is ARTPushActivationEventGotPushDeviceDetails {
                    partialDone()
                } else if event is ARTPushActivationEventGotDeviceRegistration {
                    stateMachine.transitions = nil
                    partialDone()
                }
            }
            rest.push.activate()
        }

        XCTAssertEqual(rest.device.clientId, expectedClientId)
        XCTAssertEqual(rest.auth.clientId, expectedClientId)

        let registerRequest = mockHttpExecutor.requests.filter { req in
            req.httpMethod == "POST" && req.url?.path == "/push/deviceRegistrations"
        }.first

        switch extractBodyAsMsgPack(registerRequest) {
        case let .failure(error):
            fail(error)
        case let .success(httpBody):
            guard let requestedClientId = httpBody.unbox["clientId"] as? String else {
                fail("No clientId field in HTTPBody"); return
            }
            XCTAssertEqual(requestedClientId, expectedClientId)
        }
    }

    // https://github.com/ably/ably-cocoa/issues/889
    func test__006__activation__should_store_the_device_token_data_as_string() {
        let expectedDeviceToken = TestDeviceToken.tokenString
        let expectedLocationDeviceToken = TestLocationDeviceToken.tokenString
        defer { rest.push.internal.activationMachine.transitions = nil }
        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)
            rest.push.internal.activationMachine.onEvent = { event, _ in
                if event is ARTPushActivationEventGotPushDeviceDetails {
                    partialDone()
                }
            }
            ARTPushInternal.didRegisterForRemoteNotifications(withDeviceToken: TestDeviceToken.tokenData, rest: rest)
            ARTPushInternal.didRegisterForLocationNotifications(withDeviceToken: TestLocationDeviceToken.tokenData, rest: rest)
        }
        let expectedDeviceTokenKey = "ARTAPNSDeviceToken-default" // ARTAPNSDeviceTokenKeyOfType(nil)
        expect(storage.keysWritten.keys).to(contain([expectedDeviceTokenKey]))
        XCTAssertEqual(storage.keysWritten.at(expectedDeviceTokenKey)?.value as? String, expectedDeviceToken)

        let expectedLocationDeviceTokenKey = "ARTAPNSDeviceToken-location" // ARTAPNSDeviceTokenKeyOfType("location")
        expect(storage.keysWritten.keys).to(contain([expectedLocationDeviceTokenKey]))
        XCTAssertEqual(storage.keysWritten.at(expectedLocationDeviceTokenKey)?.value as? String, expectedLocationDeviceToken)
    }

    // https://github.com/ably/ably-cocoa/issues/888
    func test__007__activation__should_not_sync_the_local_device_dispatched_in_internal_queue() {
        XCTAssertNil(tryInObjC {
            ARTPushInternal.didRegisterForRemoteNotifications(withDeviceToken: TestDeviceToken.tokenData, rest: rest)
        })
    }

    // Live Activity push-to-start token

    // registerPushToStartToken stores the token under the push-to-start token type and
    // sends a GotPushDeviceDetails event to the state machine (which, on an already-activated
    // device, syncs the recipient to Ably via a PATCH).
    func test__100__push_to_start__registerPushToStartToken_stores_token_and_sends_GotPushDeviceDetails() {
        defer { rest.push.internal.activationMachine.onEvent = nil }
        waitUntil(timeout: testTimeout) { done in
            rest.push.internal.activationMachine.onEvent = { event, _ in
                if event is ARTPushActivationEventGotPushDeviceDetails {
                    done()
                }
            }
            rest.push.registerPushToStartToken(TestPushToStartToken.tokenData)
        }
        let expectedTokenKey = "ARTAPNSDeviceToken-pushToStart" // ARTAPNSDeviceTokenKeyOfType("pushToStart")
        expect(storage.keysWritten.keys).to(contain([expectedTokenKey]))
        XCTAssertEqual(storage.keysWritten.at(expectedTokenKey)?.value as? String, TestPushToStartToken.tokenString)
    }

    // RSH8
    func test__008__LocalDevice__has_a_device_method_that_returns_a_LocalDevice() {
        let _: ARTLocalDevice = ARTHttpClient(key: "fake:key").device
        let _: ARTLocalDevice = ARTRealtimeClient(key: "fake:key").device
    }

    // RSH8a
    func test__009__LocalDevice__the_device_is_lazily_populated_from_the_persisted_state() {
        let testToken = "testDeviceToken"
        let testIdentity = ARTDeviceIdentityTokenDetails(
            token: "123456",
            issued: Date(),
            expires: Date.distantFuture,
            capability: "",
            clientId: "client1"
        )

        let rest = ARTHttpClient(key: "fake:key")
        rest.internal.storage = storage

        storage.simulateOnNextRead(string: "testId", for: ARTDeviceIdKey)
        storage.simulateOnNextRead(string: "testSecret", for: ARTDeviceSecretKey)
        storage.simulateOnNextRead(string: testToken, for: ARTAPNSDeviceTokenKey)
        storage.simulateOnNextRead(data: testIdentity.art_archive(withLogger: nil)!, for: ARTDeviceIdentityTokenKey)

        let device = rest.device

        XCTAssertEqual(device.id, "testId")
        XCTAssertEqual(device.secret, "testSecret")
        XCTAssertEqual(device.clientId, "client1")
        XCTAssertEqual(device.apnsDeviceToken(), testToken)
        XCTAssertEqual(device.identityTokenDetails?.token, testIdentity.token)
    }

    // RSH8d

    func test__012__LocalDevice__when_using_token_authentication__new_clientID_is_set() {
        let options = ARTClientOptions(key: "fake:key")
        options.autoConnect = false
        options.authCallback = { _, callback in
            delay(0.1) {
                callback(ARTTokenDetails(token: "fake:token", expires: nil, issued: nil, capability: nil, clientId: "testClient"), nil)
            }
        }

        let realtime = ARTRealtimeClient(options: options)
        let storage = MockDeviceStorage()
        realtime.internal.rest.storage = storage

        XCTAssertNil(realtime.device.clientId)
        XCTAssertNil(storage.keysWritten[ARTClientIdKey] as? String)

        waitUntil(timeout: testTimeout) { done in
            realtime.auth.authorize { _, _ in
                done()
            }
        }

        XCTAssertEqual(realtime.device.clientId, "testClient")
        XCTAssertEqual(storage.keysWritten[ARTClientIdKey] as? String, "testClient")
    }

    // RSH8d

    func test__013__LocalDevice__when_getting_a_client_ID_from_CONNECTED_message__new_clientID_is_set() {
        let options = ARTClientOptions(key: "fake:key")
        options.autoConnect = false
        options.testOptions.transportFactory = TestProxyTransportFactory()

        let realtime = ARTRealtimeClient(options: options)
        let storage = MockDeviceStorage()
        realtime.internal.rest.storage = storage

        XCTAssertNil(realtime.device.clientId)
        XCTAssertNil(storage.keysWritten[ARTClientIdKey] as? String)

        waitUntil(timeout: testTimeout) { done in
            realtime.connection.once(.connected) { _ in
                done()
            }
            realtime.connect()

            let transport = realtime.internal.transport as! TestProxyTransport
            transport.actionsIgnored += [.error]
            transport.simulateTransportSuccess(clientId: "testClient")
        }

        XCTAssertEqual(realtime.device.clientId, "testClient")
        XCTAssertEqual(storage.keysWritten[ARTClientIdKey] as? String, "testClient")
    }

    // RSH8e
    func test__010__LocalDevice__authentication_on_registered_device_sends_a_GotPushDeviceDetails_with_new_clientID() throws {
        let testDeviceToken = "testDeviceToken"
        let testDeviceIdentity = ARTDeviceIdentityTokenDetails(
            token: "123456",
            issued: Date(),
            expires: Date.distantFuture,
            capability: "",
            clientId: ""
        )
        let expectedClient = "testClient"

        let options = ARTClientOptions(key: "fake:key")
        options.autoConnect = false
        options.authCallback = { _, callback in
            delay(0.1) {
                callback(ARTTokenDetails(token: "fake:token", expires: nil, issued: nil, capability: nil, clientId: expectedClient), nil)
            }
        }

        let realtime = ARTRealtimeClient(options: options)
        let mockHttpExecutor = MockHTTPExecutor()
        realtime.internal.rest.httpExecutor = mockHttpExecutor

        let logger = InternalLog(core: MockInternalLogCore())
        let storage = MockDeviceStorage(
            startWith: ARTPushActivationStateWaitingForNewPushDeviceDetails(
                machine: ARTPushActivationStateMachine(rest: rest.internal, delegate: StateMachineDelegate(), logger: logger),
                logger: logger
            )
        )
        realtime.internal.rest.storage = storage

        // Per RSH8a1 the load path discards everything when `id` or
        // `deviceSecret` can't be loaded, so to exercise the identity-token
        // path we must simulate a consistent (id, secret, token) triple. This
        // must be seeded BEFORE the device is loaded — creating the state
        // machine below initialises the LocalDevice (RSH3h) — and we reset the
        // shared device singleton so it reloads from this storage rather than
        // one cached by `setUp`.
        storage.simulateOnNextRead(string: "testId", for: ARTDeviceIdKey)
        storage.simulateOnNextRead(string: "testSecret", for: ARTDeviceSecretKey)
        storage.simulateOnNextRead(string: testDeviceToken, for: ARTAPNSDeviceTokenKey)
        storage.simulateOnNextRead(data: testDeviceIdentity.art_archive(withLogger: nil)!, for: ARTDeviceIdentityTokenKey)
        realtime.internal.rest.resetDeviceSingleton()

        var capturedStateMachine: ARTPushActivationStateMachine?
        waitUntil(timeout: testTimeout) { done in
            realtime.internal.rest.push.getActivationMachine { machine in
                capturedStateMachine = machine
                done()
            }
        }
        let stateMachine = try XCTUnwrap(capturedStateMachine, "waitUntil timed out before stateMachine was set")
        let delegate = StateMachineDelegate()
        stateMachine.delegate = delegate

        XCTAssertEqual(realtime.device.clientId, testDeviceIdentity.clientId)

        waitUntil(timeout: testTimeout) { done in
            stateMachine.transitions = { event, _, _ in
                if event is ARTPushActivationEventGotPushDeviceDetails {
                    done()
                }
            }
            realtime.auth.authorize { _, _ in }
        }

        XCTAssertEqual(realtime.device.clientId, expectedClient)

        let expectation = XCTestExpectation(description: "Consecutive Authorization")
        expectation.isInverted = true
        stateMachine.transitions = { event, _, _ in
            if event is ARTPushActivationEventGotPushDeviceDetails {
                fail("GotPushDeviceDetails should only be emitted when clientId is different from the present identified client")
            }
        }
        realtime.auth.authorize { _, _ in }
        wait(for: [expectation], timeout: 3.0)

        XCTAssertEqual(mockHttpExecutor.requests.filter { $0.url?.pathComponents.contains("deviceRegistrations") == true }.count, 1)
        XCTAssertEqual(realtime.device.clientId, expectedClient)
    }

    // RSH8f
    func test__011__LocalDevice__sets_device_s_client_ID_from_registration_response() {
        let expectedClientId = "testClientId"

        let stateMachineDelegate = StateMachineDelegateCustomCallbacks()
        stateMachineDelegate.onPushCustomRegisterIdentity = { _, _ in
            ARTDeviceIdentityTokenDetails(
                token: "123456",
                issued: Date(),
                expires: Date.distantFuture,
                capability: "",
                clientId: expectedClientId
            )
        }
        let storage = MockDeviceStorage()
        rest.internal.storage = storage
        rest.push.internal.activationMachine.delegate = stateMachineDelegate

        XCTAssertNil(rest.device.clientId)
        XCTAssertNil(storage.keysWritten[ARTClientIdKey] as? String)

        waitUntil(timeout: testTimeout) { done in
            stateMachineDelegate.onDidActivateAblyPush = { _ in
                done()
            }

            rest.push.activate()

            ARTPushInternal.didRegisterForRemoteNotifications(withDeviceToken: "testDeviceToken".data(using: .utf8)!, rest: rest)
        }

        XCTAssertEqual(rest.device.clientId, expectedClientId)
        XCTAssertEqual(storage.keysWritten[ARTClientIdKey] as? String, expectedClientId)
    }

    func test__014__Registerer_Delegate_option__a_successful_activation_should_call_the_correct_registerer_delegate_method() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.key = "xxxx:xxxx"
        let pushRegistererDelegate = StateMachineDelegate()
        options.pushRegistererDelegate = pushRegistererDelegate
        let rest = ARTHttpClient(options: options)
        waitUntil(timeout: testTimeout) { done in
            pushRegistererDelegate.onDidActivateAblyPush = { error in
                XCTAssertNil(error)
                done()
            }
            pushRegistererDelegate.onDidDeactivateAblyPush = { _ in
                fail("should not be called")
            }
            rest.internal.httpExecutor = MockHTTPExecutor()
            rest.push.activate()
            ARTPushInternal.didRegisterForRemoteNotifications(withDeviceToken: TestDeviceToken.tokenData, rest: rest)
        }
    }

    func test__015__Registerer_Delegate_option__registerer_delegate_should_not_hold_a_strong_instance_reference() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.key = "xxxx:xxxx"
        var pushRegistererDelegate: StateMachineDelegate? = StateMachineDelegate()
        options.pushRegistererDelegate = pushRegistererDelegate
        let rest = ARTHttpClient(options: options)
        XCTAssertNotNil(rest.internal.options.pushRegistererDelegate)
        pushRegistererDelegate = nil
        XCTAssertNil(rest.internal.options.pushRegistererDelegate)
    }

    func test__016__activate_should_call_registerForAPNS_while_transition_from_not_activated() {
        var registerForAPNSMethodWasCalled = false

        let hook = rest.push.internal.activationMachine.testSuite_injectIntoMethod(after: NSSelectorFromString("registerForAPNS")) {
            registerForAPNSMethodWasCalled = true
        }

        defer {
            hook.remove()
            rest.push.internal.activationMachine.transitions = nil
        }
        waitUntil(timeout: testTimeout) { done in
            rest.push.internal.activationMachine.transitions = { event, _, _ in
                if event is ARTPushActivationEventCalledActivate {
                    done()
                }
            }
            rest.push.activate()
        }
        XCTAssertTrue(registerForAPNSMethodWasCalled)
    }

    // RSH8i

    func test__017__LocalDevice__must_verify_the_validity_of_saved_push_details_and_update_if_needed_on_the_Ably_server_by_triggering_GotPushDeviceDetails() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.key = "xxxx:xxxx"
        let rest = ARTHttpClient(options: options)
        let mockHttpExecutor = MockHTTPExecutor()
        rest.internal.httpExecutor = mockHttpExecutor
        let storage = MockDeviceStorage()
        rest.internal.storage = storage

        rest.internal.resetDeviceSingleton()

        var capturedStateMachine: ARTPushActivationStateMachine?
        waitUntil(timeout: testTimeout) { done in
            rest.push.internal.getActivationMachine { machine in
                capturedStateMachine = machine
                done()
            }
        }
        let stateMachine = try XCTUnwrap(capturedStateMachine, "waitUntil timed out before stateMachine was set")

        let testDeviceToken = "xxxx-xxxx-xxxx-xxxx-xxxx"
        stateMachine.rest.device.setAndPersistAPNSDeviceToken(testDeviceToken)
        defer { stateMachine.rest.device.setAndPersistAPNSDeviceToken(nil) }

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(4, done: done)
            stateMachine.transitions = { event, _, _ in
                if event is ARTPushActivationEventGotPushDeviceDetails {
                    partialDone()
                }
                else if event is ARTPushActivationEventGotDeviceRegistration {
                    partialDone()
                    ARTPushInternal.didRegisterForRemoteNotifications(withDeviceToken: TestDeviceToken.tokenData, rest: rest)
                }
                else if event is ARTPushActivationEventRegistrationSynced {
                    stateMachine.transitions = nil
                    partialDone()
                }
            }
            rest.push.activate()
        }

        let registerRequest = mockHttpExecutor.requests.filter { req in
            req.httpMethod == "POST" && req.url!.path == "/push/deviceRegistrations"
        }.first

        switch extractBodyAsMsgPack(registerRequest) {
        case let .failure(error):
            fail(error)
        case let .success(httpBody):
            guard let pushDict = httpBody.unbox["push"] as? NSDictionary else {
                fail("No clientId field in HTTPBody"); return
            }
            let expectedTokenString = pushDict.value(forKeyPath: "recipient.apnsDeviceTokens.default") as? String
            XCTAssertEqual(expectedTokenString, testDeviceToken)
        }

        let updateRequest = mockHttpExecutor.requests.filter { req in
            req.httpMethod == "PATCH" && req.url!.path.hasPrefix("/push/deviceRegistrations/")
        }.first

        switch extractBodyAsMsgPack(updateRequest) {
        case let .failure(error):
            fail(error)
        case let .success(httpBody):
            guard let pushDict = httpBody.unbox["push"] as? NSDictionary else {
                fail("No `push` field in HTTPBody"); return
            }
            let expectedTokenString = pushDict.value(forKeyPath: "recipient.apnsDeviceTokens.default") as? String
            XCTAssertEqual(expectedTokenString, TestDeviceToken.tokenString)
        }
    }

    func test__018__LocalDevice__when_alternative_device_token_available_update_push_details_on_the_Ably_server_by_triggering_GotPushDeviceDetails() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.key = "xxxx:xxxx"
        let pushRegistererDelegate = StateMachineDelegate()
        options.pushRegistererDelegate = pushRegistererDelegate
        let rest = ARTHttpClient(options: options)
        let mockHttpExecutor = MockHTTPExecutor()
        rest.internal.httpExecutor = mockHttpExecutor
        let storage = MockDeviceStorage()
        rest.internal.storage = storage

        rest.internal.resetDeviceSingleton()

        let testDeviceToken = "xxxx-xxxx-xxxx-xxxx-xxxx"
        rest.device.setAndPersistAPNSDeviceToken(testDeviceToken)
        defer { rest.device.setAndPersistAPNSDeviceToken(nil) }

        func requestLocationDeviceToken() {
            ARTPushInternal.didRegisterForLocationNotifications(withDeviceToken: TestLocationDeviceToken.tokenData, rest: rest)
        }

        waitUntil(timeout: testTimeout) { done in
            pushRegistererDelegate.onDidActivateAblyPush = { error in
                XCTAssertNil(error)
                requestLocationDeviceToken()
            }
            pushRegistererDelegate.onDidUpdateAblyPush = { _ in
                done()
            }
            rest.push.activate()
        }

        let registerRequest = mockHttpExecutor.requests.filter { req in
            req.httpMethod == "POST" && req.url!.path == "/push/deviceRegistrations"
        }.first

        switch extractBodyAsMsgPack(registerRequest) {
        case let .failure(error):
            fail(error)
        case let .success(httpBody):
            guard let pushDict = httpBody.unbox["push"] as? NSDictionary else {
                fail("No `push` field in HTTPBody"); return
            }
            let expectedTokenString = pushDict.value(forKeyPath: "recipient.apnsDeviceTokens.default") as? String
            XCTAssertEqual(expectedTokenString, testDeviceToken)
        }

        let updateRequest = mockHttpExecutor.requests.filter { req in
            req.httpMethod == "PATCH" && req.url!.path.hasPrefix("/push/deviceRegistrations/")
        }.first

        switch extractBodyAsMsgPack(updateRequest) {
        case let .failure(error):
            fail(error)
        case let .success(httpBody):
            guard let pushDict = httpBody.unbox["push"] as? NSDictionary else {
                fail("No `push` field in HTTPBody"); return
            }
            let expectedDefaultTokenString = pushDict.value(forKeyPath: "recipient.apnsDeviceTokens.default") as? String
            XCTAssertEqual(expectedDefaultTokenString, testDeviceToken)
            let expectedLocationTokenString = pushDict.value(forKeyPath: "recipient.apnsDeviceTokens.location") as? String
            XCTAssertEqual(expectedLocationTokenString, TestLocationDeviceToken.tokenString)
        }
    }
}
#endif
