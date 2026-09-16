import AblyPubSubDevice
import Nimble
import XCTest

private let query: StatsQuery = {
    let query = StatsQuery()
    query.unit = .minute
    return query
}()

private let presenceData = buildStringThatExceedMaxMessageSize()
private let clientId = "testMessageSizeClientId"

class RealtimeClientTests: XCTestCase {
    func checkError(_ errorInfo: ErrorInfo?, withAlternative message: String) {
        if let error = errorInfo {
            XCTFail("\(error.code): \(error.message)")
        } else if !message.isEmpty {
            XCTFail(message)
        }
    }

    func checkError(_ errorInfo: ErrorInfo?) {
        checkError(errorInfo, withAlternative: "")
    }

    // XCTest invokes this method before executing the first test in the test suite. We use it to ensure that the global variables are initialized at the same moment, and in the same order, as they would have been when we used the Quick testing framework.
    override class var defaultTestSuite: XCTestSuite {
        _ = query
        _ = presenceData
        _ = clientId

        return super.defaultTestSuite
    }

    enum AblyManager {
        static let sharedClient = RealtimeClient(options: { $0.autoConnect = false; return $0 }(ClientOptions(key: "xxxx:xxxx")))
    }

    // G4
    func test__001__RealtimeClient__All_WebSocket_connections_should_include_the_current_API_version() throws {
        let test = Test()
        let client = AblyTests.newRealtime(try AblyTests.commonAppSetup(for: test)).client
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(test.uniqueChannelName())
        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "message") { error in
                XCTAssertNil(error)
                let transport = client.internal.transport as! TestProxyTransport

                // This test should not directly validate version against Default.version(), as
                // ultimately the version header has been derived from that value.
                expect(transport.lastUrl!.query).to(haveParam("v", withValue: "6"))

                done()
            }
        }
    }

    // RTC1

    func test__013__RealtimeClient__options__should_support_the_same_options_as_the_Rest_client() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test) // Same as Rest
        options.clientId = "client_string"

        let client = RealtimeClient(options: options)
        defer { client.close() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.on { stateChange in
                let state = stateChange.current
                let errorInfo = stateChange.reason
                switch state {
                case .connecting, .closing, .closed:
                    break
                case .failed:
                    self.checkError(errorInfo, withAlternative: "Failed state")
                    done()
                default:
                    XCTAssertEqual(state, RealtimeConnectionState.connected)
                    done()
                }
            }
        }
    }

    // RTC1a
    func test__014__RealtimeClient__options__should_echoMessages_option_be_true_by_default() {
        let options = ClientOptions()
        XCTAssertEqual(options.echoMessages, true)
    }

    // RTC1b
    func test__015__RealtimeClient__options__should_autoConnect_option_be_true_by_default() {
        let options = ClientOptions()
        XCTAssertEqual(options.autoConnect, true)
    }

    // RTC1c
    func test__016__RealtimeClient__options__should_attempt_to_recover_the_connection_state_if_recover_string_is_assigned() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.clientId = "client_string"

        // First connection
        let client = RealtimeClient(options: options)
        defer { client.close() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.on { stateChange in
                let state = stateChange.current
                let errorInfo = stateChange.reason
                switch state {
                case .failed:
                    self.checkError(errorInfo, withAlternative: "Failed state")
                    done()
                case .connected:
                    self.checkError(errorInfo)
                    let recoveryKey = try! ARTConnectionRecoveryKey.fromJsonString(client.connection.createRecoveryKey() ?? "invalid")
                    XCTAssertEqual(recoveryKey.connectionKey, client.internal.connection.key)
                    XCTAssertEqual(recoveryKey.msgSerial, client.internal.msgSerial)
                    options.recover = client.connection.createRecoveryKey()
                    done()
                default:
                    break
                }
            }
        }
        client.connection.off()

        // New connection
        let newClient = RealtimeClient(options: options)
        defer { newClient.close() }

        waitUntil(timeout: testTimeout) { done in
            newClient.connection.on { stateChange in
                let state = stateChange.current
                let errorInfo = stateChange.reason
                switch state {
                case .failed:
                    self.checkError(errorInfo, withAlternative: "Failed state")
                    done()
                case .connected:
                    self.checkError(errorInfo)
                    done()
                default:
                    break
                }
            }
        }
        newClient.connection.off()
    }

    // RTC1d
    func test__017__RealtimeClient__options__should_modify_the_realtime_endpoint_host_if_realtimeHost_is_assigned() {
        let options = ClientOptions(key: "secret:key")
        options.realtimeHost = "fake.ably.io"
        options.autoConnect = false
        let client = RealtimeClient(options: options)
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout.multiplied(by: 3)) { done in
            let partialDone = AblyTests.splitDone(2, done: done)
            client.connection.once(.connecting) { _ in
                guard let webSocketTransport = client.internal.transport as? ARTWebSocketTransport else {
                    fail("Transport should be of type ARTWebSocketTransport"); done()
                    return
                }
                XCTAssertNotNil(webSocketTransport.websocketURL)
                XCTAssertEqual(webSocketTransport.websocketURL?.host, "fake.ably.io")
                partialDone()
            }
            client.connection.once(.disconnected) { _ in
                partialDone()
            }
            client.connect()
        }
    }

    // RTC1e
    func test__018__RealtimeClient__options__should_modify_both_the_REST_and_realtime_endpoint_if_environment_string_is_assigned() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)

        let oldRestHost = options.restHost
        let oldRealtimeHost = options.realtimeHost

        // Change REST and realtime endpoint hosts
        options.environment = "test"

        XCTAssertEqual(options.restHost, "test-rest.ably.io")
        XCTAssertEqual(options.realtimeHost, "test-realtime.ably.io")
        // Extra care
        XCTAssertEqual(oldRestHost, "\(getEnvironment())-rest.ably.io")
        XCTAssertEqual(oldRealtimeHost, "\(getEnvironment())-realtime.ably.io")
    }

    // RTC1f
    func test__019__RealtimeClient__options__url_should_contains_transport_params() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        options.transportParams = [
            "tpBool": .init(bool: true),
            "tpInt": .init(number: .init(value: 12)),
            "tpFloat": .init(number: .init(value: 12.12)),
            "tpString": .init(string: "Lorem ipsum"),
            "v": .init(string: "v12.34"),
        ]

        let client = RealtimeClient(options: options)
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connecting) { _ in
                guard let webSocketTransport = client.internal.transport as? ARTWebSocketTransport else {
                    fail("Transport should be of type ARTWebSocketTransport"); done()
                    return
                }

                if let absoluteString = webSocketTransport.websocketURL?.absoluteString {
                    XCTAssertTrue(absoluteString.contains("tpBool=true"))
                    XCTAssertTrue(absoluteString.contains("tpInt=12"))
                    XCTAssertTrue(absoluteString.contains("tpFloat=12.12"))
                    XCTAssertTrue(absoluteString.contains("tpString=Lorem%20ipsum"))

                    /**
                     Test that replacing query string default values in ClientOptions works properly
                     */
                    XCTAssertEqual(absoluteString.components(separatedBy: "v=").count, 2)
                } else {
                    XCTFail("Expected webSocketTransport.websocketURL?.absoluteString to be non-nil")
                }

                done()
            }
            client.connect()
        }
    }

    // RTC2
    func test__002__RealtimeClient__should_have_access_to_the_underlying_Connection_object() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        let client = RealtimeClient(options: options)
        expect(client.connection).to(beAKindOf(Connection.self))
    }

    // RTC3
    func test__003__RealtimeClient__should_provide_access_to_the_underlying_Channels_object() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false

        let client = RealtimeClient(options: options)
        defer { client.dispose(); client.close() }

        let channelName = test.uniqueChannelName()

        client.channels.get(channelName).subscribe { _ in
            // Attached
        }

        XCTAssertNotNil(client.channels.get(channelName))
    }

    // RTC4
    func test__020__RealtimeClient__Auth_object__should_provide_access_to_the_Auth_object() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = RealtimeClient(options: options)
        defer { client.close() }
        XCTAssertEqual(client.auth.internal.options.key, options.key)
    }

    // RTC4a
    func test__021__RealtimeClient__Auth_object__clientId_may_be_populated_when_the_connection_is_established() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.clientId = "client_string"
        let client = RealtimeClient(options: options)
        defer { client.close() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.on { stateChange in
                let state = stateChange.current
                let errorInfo = stateChange.reason
                switch state {
                case .failed:
                    self.checkError(errorInfo, withAlternative: "Failed state")
                    done()
                case .connected:
                    self.checkError(errorInfo)
                    XCTAssertEqual(client.auth.clientId, options.clientId)
                    done()
                default:
                    break
                }
            }
        }
    }

    // RTC5a
    func test__022__RealtimeClient__stats__should_present_an_async_interface() throws {
        let test = Test()
        let client = RealtimeClient(options: try AblyTests.commonAppSetup(for: test))
        defer { client.close() }
        // Async
        waitUntil(timeout: testTimeout) { done in
            // Proxy from `client.internal.rest.stats`
            expect {
                try client.stats(query, callback: { paginated, _ in
                    XCTAssertNotNil(paginated)
                    done()
                })
            }.toNot(throwError { err in fail("\(err)"); done() })
        }
    }

    // RTC5b
    func test__023__RealtimeClient__stats__should_accept_all_the_same_params_as_RestClient() throws {
        let test = Test()
        let client = RealtimeClient(options: try AblyTests.commonAppSetup(for: test))
        defer { client.close() }
        var paginatedResult: PaginatedResult<AnyObject>?
        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { _ in
                done()
            }
        }

        // Realtime
        expect {
            try client.stats(query, callback: { paginated, error in
                if let e = error {
                    XCTFail(e.localizedDescription)
                }
                paginatedResult = paginated as! PaginatedResult<AnyObject>?
            })
        }.toNot(throwError())
        expect(paginatedResult).toEventuallyNot(beNil(), timeout: testTimeout)
        if paginatedResult == nil {
            return
        }

        // Rest
        waitUntil(timeout: testTimeout) { done in
            expect {
                try client.internal.rest.stats(query, wrapperSDKAgents:nil, callback: { paginated, error in
                    defer { done() }
                    if let e = error {
                        XCTFail(e.localizedDescription)
                        return
                    }
                    guard let paginated = paginated else {
                        XCTFail("both paginated and error are nil")
                        return
                    }
                    XCTAssertEqual(paginated.items.count, paginatedResult!.items.count)
                })
            }.toNot(throwError { err in fail("\(err)"); done() })
        }
    }

    // RTC6a
    func test__024__RealtimeClient__time__should_present_an_async_interface() throws {
        let test = Test()
        let client = RealtimeClient(options: try AblyTests.commonAppSetup(for: test))
        defer { client.close() }
        // Async
        waitUntil(timeout: testTimeout) { done in
            // Proxy from `client.internal.rest.time`
            client.time { date, _ in
                XCTAssertNotNil(date)
                done()
            }
        }
    }

    // RTC7
    func test__004__RealtimeClient__should_use_the_configured_timeouts_specified() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.suspendedRetryTimeout = 6.0

        let client = RealtimeClient(options: options)
        defer { client.close() }

        var start: NSDate?
        var endInterval: UInt?

        waitUntil(timeout: testTimeout.incremented(by: options.suspendedRetryTimeout)) { done in
            client.connection.on { stateChange in
                let state = stateChange.current
                let errorInfo = stateChange.reason
                switch state {
                case .failed:
                    self.checkError(errorInfo, withAlternative: "Failed state")
                    done()
                case .connecting:
                    if let start = start {
                        endInterval = UInt(start.timeIntervalSinceNow * -1)
                        done()
                    }
                case .connected:
                    self.checkError(errorInfo)

                    if start == nil {
                        // Force
                        delay(0) {
                            client.internal.onSuspended()
                        }
                    }
                case .suspended:
                    start = NSDate()
                default:
                    break
                }
            }
        }

        if let secs = endInterval {
            expect(secs).to(beLessThanOrEqualTo(UInt(options.suspendedRetryTimeout)))
        }

        XCTAssertEqual(client.internal.connectionStateTtl, 120 as TimeInterval /* seconds */ )
    }

    // RTC8

    // RTC8a
    func test__025__RealtimeClient__Auth_authorize_should_upgrade_the_connection_with_current_token__in_the_CONNECTED_state_and_auth_authorize_is_called__the_client_must_obtain_a_new_token__send_an_AUTH_ProtocolMessage_with_an_auth_attribute() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        options.useTokenAuth = true
        options.testOptions.transportFactory = TestProxyTransportFactory()
        let client = RealtimeClient(options: options)
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { stateChange in
                XCTAssertNil(stateChange.reason)
                done()
            }
            client.connect()
        }

        guard let firstToken = client.auth.tokenDetails?.token else {
            fail("Client has no token"); return
        }

        guard let transport = client.internal.transport as? TestProxyTransport else {
            fail("TestProxyTransport is not set"); return
        }

        waitUntil(timeout: testTimeout) { done in
            client.auth.authorize(nil, options: nil) { tokenDetails, error in
                XCTAssertNil(error)
                guard let tokenDetails = tokenDetails else {
                    fail("TokenDetails is nil"); done(); return
                }

                let authMessages = transport.protocolMessagesSent.filter { $0.action == .auth }
                XCTAssertEqual(authMessages.count, 1)

                guard let authMessage = authMessages.first else {
                    fail("Missing AUTH protocol message"); done(); return
                }

                XCTAssertNotNil(authMessage.auth)

                guard let accessToken = authMessage.auth?.accessToken else {
                    fail("Missing accessToken from AUTH ProtocolMessage auth attribute"); done(); return
                }

                XCTAssertNotEqual(accessToken, firstToken)
                XCTAssertNotEqual(tokenDetails.token, firstToken)
                XCTAssertEqual(tokenDetails.token, accessToken)

                XCTAssertTrue(client.internal.transport === transport)

                done()
            }
        }
    }

    // RTC8a1 - part 1
    func test__026__RealtimeClient__Auth_authorize_should_upgrade_the_connection_with_current_token__when_the_authentication_token_change_is_successful__then_the_client_should_receive_a_new_CONNECTED_ProtocolMessage() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        let testToken = try getTestToken(for: test)
        options.token = testToken
        options.testOptions.transportFactory = TestProxyTransportFactory()
        let client = RealtimeClient(options: options)
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { stateChange in
                XCTAssertNil(stateChange.reason)
                done()
            }
            client.connect()
        }

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)

            client.connection.once(.connected) { _ in
                fail("Should not receive a CONNECTED event because the connection is already connected"); partialDone()
            }

            client.connection.once(.update) { stateChange in
                XCTAssertEqual(stateChange.previous, RealtimeConnectionState.connected)
                XCTAssertNil(stateChange.reason)

                guard let transport = client.internal.transport as? TestProxyTransport else {
                    fail("TestProxyTransport is not set"); partialDone(); return
                }
                let connectedMessages = transport.protocolMessagesReceived.filter { $0.action == .connected }
                XCTAssertEqual(connectedMessages.count, 2)

                guard let connectedAfterAuth = connectedMessages.last, let connectionDetailsAfterAuth = connectedAfterAuth.connectionDetails else {
                    fail("Missing CONNECTED protocol message after AUTH protocol message"); partialDone(); return
                }

                XCTAssertNil(client.auth.clientId)
                XCTAssertNil(connectionDetailsAfterAuth.clientId)
                XCTAssertEqual(client.connection.key, connectionDetailsAfterAuth.connectionKey)
                partialDone()
            }

            client.auth.authorize(nil, options: nil) { tokenDetails, error in
                XCTAssertNil(error)
                guard let tokenDetails = tokenDetails else {
                    fail("TokenDetails is nil"); partialDone(); return
                }
                XCTAssertNotEqual(tokenDetails.token, testToken)
                partialDone()
            }

            XCTAssertNil(client.connection.errorReason)
        }

        XCTAssertNotEqual(client.auth.tokenDetails?.token, testToken)
    }

    // RTC8a1 - part 2
    func test__027__RealtimeClient__Auth_authorize_should_upgrade_the_connection_with_current_token__performs_an_upgrade_of_capabilities_without_any_loss_of_continuity_or_connectivity_during_the_upgrade_process() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        let testToken = try getTestToken(for: test, capability: "{\"test\":[\"subscribe\"]}")
        options.token = testToken
        options.testOptions.transportFactory = TestProxyTransportFactory()
        let client = RealtimeClient(options: options)
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { stateChange in
                XCTAssertNil(stateChange.reason)
                done()
            }
            client.connect()
        }

        let channel = client.channels.get(test.uniqueChannelName())
        waitUntil(timeout: testTimeout) { done in
            channel.once(.failed) { stateChange in
                guard let error = stateChange.reason else {
                    fail("Error is nil"); done(); return
                }
                XCTAssertTrue(error.code == ErrorCode.operationNotPermittedWithProvidedCapability.rawValue)
                done()
            }
            channel.attach()
        }

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)

            client.connection.once(.update) { stateChange in
                XCTAssertEqual(stateChange.previous, RealtimeConnectionState.connected)
                XCTAssertNil(stateChange.reason)
                partialDone()
            }

            client.connection.once(.connected) { _ in
                fail("Already connected")
            }
            client.connection.once(.disconnected) { _ in
                fail("Lost connectivity")
            }
            client.connection.once(.suspended) { _ in
                fail("Lost continuity")
            }
            client.connection.once(.failed) { _ in
                fail("Should not receive any failure")
            }

            let tokenParams = TokenParams()
            tokenParams.capability = "{\"*\":[\"*\"]}"

            client.auth.authorize(tokenParams, options: nil) { tokenDetails, error in
                XCTAssertNil(error)
                guard let tokenDetails = tokenDetails else {
                    fail("TokenDetails is nil"); partialDone(); return
                }
                XCTAssertNotEqual(tokenDetails.token, testToken)
                XCTAssertEqual(tokenDetails.capability, tokenParams.capability)
                partialDone()
            }
        }

        XCTAssertNotEqual(client.auth.tokenDetails?.token, testToken)

        guard let transport = client.internal.transport as? TestProxyTransport else {
            fail("TestProxyTransport is not set"); return
        }

        expect(transport.protocolMessagesReceived.filter { $0.action == .disconnected }).to(beEmpty())
        // Should have one error: Channel denied access
        XCTAssertEqual(transport.protocolMessagesReceived.filter { $0.action == .error }.count, 1)

        // Retry Channel attach
        waitUntil(timeout: testTimeout) { done in
            channel.once(.failed) { _ in
                fail("Should not reach Failed state"); done()
            }
            channel.once(.attached) { stateChange in
                XCTAssertNil(stateChange.reason)
                done()
            }
            channel.attach()
        }

        XCTAssertNotEqual(client.auth.tokenDetails?.token, testToken)
    }

    // RTC8a1 - part 3
    func test__028__RealtimeClient__Auth_authorize_should_upgrade_the_connection_with_current_token__when_capabilities_are_downgraded__client_should_receive_an_ERROR_ProtocolMessage_with_a_channel_property() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        let testToken = try getTestToken(for: test)
        options.token = testToken
        options.testOptions.transportFactory = TestProxyTransportFactory()
        let client = RealtimeClient(options: options)
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(test.uniqueChannelName())
        waitUntil(timeout: testTimeout) { done in
            client.connect()
            channel.attach { error in
                XCTAssertNil(error)
                done()
            }
        }

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)

            channel.once(.failed) { stateChange in
                guard let error = stateChange.reason else {
                    fail("ErrorInfo is nil"); partialDone(); return
                }
                XCTAssertTrue(error === channel.errorReason)
                XCTAssertEqual(error.code, ErrorCode.operationNotPermittedWithProvidedCapability.intValue)

                guard let transport = client.internal.transport as? TestProxyTransport else {
                    fail("TestProxyTransport is not set"); partialDone(); return
                }

                let errorMessages = transport.protocolMessagesReceived.filter { $0.action == .error }
                XCTAssertEqual(errorMessages.count, 1)

                guard let errorMessage = errorMessages.first else {
                    fail("Missing ERROR protocol message"); partialDone(); return
                }
                expect(errorMessage.channel).to(contain("test"))
                XCTAssertEqual(errorMessage.error?.code, error.code)
                partialDone()
            }

            let tokenParams = TokenParams()
            tokenParams.capability = "{\"test\":[\"subscribe\"]}"

            client.auth.authorize(tokenParams, options: nil) { tokenDetails, error in
                XCTAssertNil(error)
                guard let tokenDetails = tokenDetails else {
                    fail("TokenDetails is nil"); partialDone(); return
                }
                XCTAssertNotEqual(tokenDetails.token, testToken)
                XCTAssertEqual(tokenDetails.capability, tokenParams.capability)
                partialDone()
            }
        }

        XCTAssertNotEqual(client.auth.tokenDetails?.token, testToken)
    }

    // RTC8a2
    func test__029__RealtimeClient__Auth_authorize_should_upgrade_the_connection_with_current_token__when_the_authentication_token_change_fails__client_should_receive_an_ERROR_ProtocolMessage_triggering_the_connection_to_transition_to_the_FAILED_state() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        options.clientId = "ios"
        options.useTokenAuth = true
        options.testOptions.transportFactory = TestProxyTransportFactory()
        let client = RealtimeClient(options: options)
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { stateChange in
                XCTAssertNil(stateChange.reason)
                done()
            }
            client.connect()
        }

        var connectionError: NSError?
        var authError: NSError?

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)

            client.connection.once(.failed) { stateChange in
                XCTAssertEqual(stateChange.previous, RealtimeConnectionState.connected)
                XCTAssertNotNil(stateChange.reason)
                connectionError = stateChange.reason
                partialDone()
            }

            let invalidToken = "xxxxxxxxxxxx"
            let authOptions = AuthOptions()
            authOptions.authCallback = { _, completion in
                completion(invalidToken as TokenDetailsCompatible, nil)
            }

            client.auth.authorize(nil, options: authOptions) { tokenDetails, error in
                guard let error = error as? NSError else {
                    fail("ErrorInfo is nil"); partialDone(); return
                }
                XCTAssertTrue(error.code == ErrorCode.invalidCredential.rawValue) // Invalid accessToken in request: xxxxxxxxxxxx
                XCTAssertEqual(tokenDetails?.token, invalidToken)
                authError = error as NSError?
                partialDone()
            }
        }

        XCTAssertTrue(authError === connectionError)
    }

    func test__030__RealtimeClient__Auth_authorize_should_upgrade_the_connection_with_current_token__authorize_call_should_complete_with_an_error_if_the_request_fails() throws {
        let test = Test()
        let options = try AblyTests.clientOptions(for: test)
        let testToken = try getTestToken(for: test)
        options.token = testToken
        let client = RealtimeClient(options: options)
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { stateChange in
                XCTAssertNil(stateChange.reason)
                done()
            }
        }

        waitUntil(timeout: testTimeout) { done in
            let tokenParams = TokenParams()
            tokenParams.clientId = "john"

            let simulatedError = NSError(domain: ablyErrorDomain, code: 1234, userInfo: nil)

            let authOptions = AuthOptions()
            authOptions.authCallback = { _, completion in
                DispatchQueue.main.async {
                    completion(nil, simulatedError)
                }
            }

            client.auth.authorize(tokenParams, options: authOptions) { tokenDetails, error in
                guard let error = error else {
                    fail("Error is nil"); done(); return
                }
                XCTAssertEqual(error as NSError, simulatedError)
                XCTAssertNil(tokenDetails)
                done()
            }
        }

        XCTAssertEqual(client.connection.state, RealtimeConnectionState.connected)
        XCTAssertEqual(client.auth.tokenDetails?.token, testToken)
    }

    // RTC8a3
    func test__031__RealtimeClient__Auth_authorize_should_upgrade_the_connection_with_current_token__authorize_call_should_be_indicated_as_completed_with_the_new_token_or_error_only_once_realtime_has_responded_to_the_AUTH_with_either_a_CONNECTED_or_ERROR_respectively() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        options.useTokenAuth = true
        options.testOptions.transportFactory = TestProxyTransportFactory()
        let client = RealtimeClient(options: options)
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { stateChange in
                XCTAssertNil(stateChange.reason)
                done()
            }
            client.connect()
        }

        waitUntil(timeout: testTimeout) { done in
            client.auth.authorize(nil, options: nil) { tokenDetails, error in
                XCTAssertNil(error)
                XCTAssertNotNil(tokenDetails)

                guard let transport = client.internal.transport as? TestProxyTransport else {
                    fail("TestProxyTransport is not set"); done(); return
                }

                XCTAssertEqual(transport.protocolMessagesSent.filter { $0.action == .auth }.count, 1)
                XCTAssertEqual(transport.protocolMessagesReceived.filter { $0.action == .connected }.count, 2)
                XCTAssertEqual(transport.protocolMessagesReceived.filter { $0.action == .error }.count, 0)
                done()
            }
        }
    }

    // RTC8b
    func test__032__RealtimeClient__Auth_authorize_should_upgrade_the_connection_with_current_token__when_connection_is_CONNECTING__all_current_connection_attempts_should_be_halted__and_after_obtaining_a_new_token_the_library_should_immediately_initiate_a_connection_attempt_using_the_new_token() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        options.useTokenAuth = true
        options.testOptions.transportFactory = TestProxyTransportFactory()
        let client = RealtimeClient(options: options)
        defer { client.dispose(); client.close() }

        var connections = 0
        let hook1 = TestProxyTransport.testSuite_injectIntoClassMethod(#selector(TestProxyTransport.connect(withToken:))) {
            connections += 1
        }
        defer { hook1?.remove() }

        var connectionsConnected = 0
        let hook2 = client.connection.on(.connected) { _ in
            connectionsConnected += 1
        }
        defer { client.connection.off(hook2) }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connecting) { stateChange in
                XCTAssertNil(stateChange.reason)

                let authOptions = AuthOptions()
                do {
                    authOptions.key = try AblyTests.commonAppSetup(for: test).key
                } catch {
                    fail("commonAppSetup failed: \(error)")
                }

                client.auth.authorize(nil, options: authOptions) { tokenDetails, error in
                    XCTAssertNil(error)
                    guard let tokenDetails = tokenDetails else {
                        fail("TokenDetails is nil"); done(); return
                    }
                    XCTAssertNotNil(tokenDetails.token)
                    XCTAssertEqual(client.connection.state, RealtimeConnectionState.connected)

                    guard let transport = client.internal.transport as? TestProxyTransport else {
                        fail("TestProxyTransport is not set"); done(); return
                    }
                    XCTAssertEqual(transport.protocolMessagesReceived.filter { $0.action == .connected }.count, 1)
                    done()
                }
            }
            client.connect()
        }

        XCTAssertEqual(connections, 2)
        XCTAssertEqual(connectionsConnected, 1)

        expect(client.connection.state).toEventually(equal(RealtimeConnectionState.connected), timeout: testTimeout)
    }

    // RTC8b1 - part 1
    func test__033__RealtimeClient__Auth_authorize_should_upgrade_the_connection_with_current_token__authorize_call_should_complete_with_the_new_token_once_the_connection_has_moved_to_the_CONNECTED_state() throws {
        let test = Test()
        let options = try AblyTests.clientOptions(for: test)
        options.autoConnect = false
        let testToken = try getTestToken(for: test)
        options.token = testToken
        let client = RealtimeClient(options: options)
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            let authOptions = AuthOptions()
            do {
                authOptions.key = try AblyTests.commonAppSetup(for: test).key
            } catch {
                fail("commonAppSetup failed: \(error)")
            }

            client.auth.authorize(nil, options: authOptions) { tokenDetails, error in
                XCTAssertNil(error)
                guard let tokenDetails = tokenDetails else {
                    fail("TokenDetails is nil"); done(); return
                }
                XCTAssertNotEqual(tokenDetails.token, testToken)
                done()
            }
        }

        XCTAssertEqual(client.connection.state, RealtimeConnectionState.connected)
    }

    // RTC8b1 - part 2
    func test__034__RealtimeClient__Auth_authorize_should_upgrade_the_connection_with_current_token__authorize_call_should_complete_with_an_error_if_the_connection_moves_to_the_FAILED_state() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        options.useTokenAuth = true
        options.testOptions.transportFactory = TestProxyTransportFactory()
        let client = RealtimeClient(options: options)
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { stateChange in
                XCTAssertNil(stateChange.reason)
                done()
            }
            client.connect()
        }

        let hook = client.auth.internal.testSuite_injectIntoMethod(after: #selector(client.auth.internal._authorize(_:options:callback:))) {
            guard let transport = client.internal.transport as? TestProxyTransport else {
                fail("TestProxyTransport is not set"); return
            }
            transport.simulateIncomingError()
        }
        defer { hook.remove() }

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)

            client.connection.once(.failed) { stateChange in
                guard let error = stateChange.reason else {
                    fail("ErrorInfo is nil"); partialDone(); return
                }
                expect(error.message).to(contain("Fail test"))
                partialDone()
            }

            client.auth.authorize(nil, options: nil) { tokenDetails, error in
                guard let error = error else {
                    fail("ErrorInfo is nil"); partialDone(); return
                }
                XCTAssertEqual((error as NSError).code, URLError.cancelled.rawValue)
                expect(client.connection.errorReason?.localizedDescription).to(contain("Fail test"))
                XCTAssertNil(tokenDetails)
                partialDone()
            }
        }

        XCTAssertEqual(client.connection.state, RealtimeConnectionState.failed)
    }

    // RTC8b1 - part 3
    func test__035__RealtimeClient__Auth_authorize_should_upgrade_the_connection_with_current_token__authorize_call_should_complete_with_an_error_if_the_connection_moves_to_the_SUSPENDED_state() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        options.useTokenAuth = true
        options.testOptions.transportFactory = TestProxyTransportFactory()
        let client = RealtimeClient(options: options)
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { stateChange in
                XCTAssertNil(stateChange.reason)
                done()
            }
            client.connect()
        }

        let hook = client.auth.internal.testSuite_injectIntoMethod(after: #selector(client.auth.internal._authorize(_:options:callback:))) {
            client.internal.onSuspended()
        }
        defer { hook.remove() }

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)

            client.connection.once(.suspended) { _ in
                partialDone()
            }

            client.auth.authorize(nil, options: nil) { tokenDetails, error in
                guard let error = error else {
                    fail("ErrorInfo is nil"); partialDone(); return
                }
                XCTAssertEqual((error as NSError).code, URLError.cancelled.rawValue)
                XCTAssertNil(tokenDetails)
                partialDone()
            }
        }

        XCTAssertEqual(client.connection.state, RealtimeConnectionState.suspended)
    }

    // RTC8b1 - part 4
    func test__036__RealtimeClient__Auth_authorize_should_upgrade_the_connection_with_current_token__authorize_call_should_complete_with_an_error_if_the_connection_moves_to_the_CLOSED_state() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        options.useTokenAuth = true
        let client = RealtimeClient(options: options)
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { stateChange in
                XCTAssertNil(stateChange.reason)
                done()
            }
            client.connect()
        }

        let hook = client.auth.internal.testSuite_injectIntoMethod(after: #selector(client.auth.internal._authorize(_:options:callback:))) {
            delay(0) {
                client.close()
            }
        }
        defer { hook.remove() }

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)

            client.connection.once(.closed) { _ in
                partialDone()
            }

            client.auth.authorize(nil, options: nil) { tokenDetails, error in
                guard let error = error else {
                    fail("Error is nil"); partialDone(); return
                }
                XCTAssertEqual((error as NSError).code, URLError.cancelled.rawValue)
                XCTAssertNil(tokenDetails)
                partialDone()
            }
        }

        XCTAssertEqual(client.connection.state, RealtimeConnectionState.closed)
    }

    // RTC8c - part 1
    func test__037__RealtimeClient__Auth_authorize_should_upgrade_the_connection_with_current_token__when_the_connection_is_in_the_SUSPENDED_state_when_auth_authorize_is_called__after_obtaining_a_token_the_library_should_move_to_the_CONNECTING_state_and_initiate_a_connection_attempt_using_the_new_token() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        let testToken = try getTestToken(for: test)
        options.token = testToken
        options.testOptions.transportFactory = TestProxyTransportFactory()
        let client = RealtimeClient(options: options)
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { stateChange in
                XCTAssertNil(stateChange.reason)
                done()
            }
            client.connect()
        }

        client.internal.onSuspended()
        expect(client.connection.state).toEventually(equal(RealtimeConnectionState.suspended), timeout: testTimeout)

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(3, done: done)

            client.connection.once(.connecting) { stateChange in
                XCTAssertEqual(stateChange.previous, RealtimeConnectionState.suspended)
                XCTAssertNil(stateChange.reason)
                partialDone()
            }

            client.connection.once(.connected) { stateChange in
                XCTAssertEqual(stateChange.previous, RealtimeConnectionState.connecting)
                XCTAssertNil(stateChange.reason)
                partialDone()
            }

            client.auth.authorize(nil, options: nil) { tokenDetails, error in
                XCTAssertNil(error)
                guard let tokenDetails = tokenDetails else {
                    fail("TokenDetails is nil"); partialDone(); return
                }

                XCTAssertEqual(client.connection.state, RealtimeConnectionState.connected)
                XCTAssertNotEqual(tokenDetails.token, testToken)

                guard let transport = client.internal.transport as? TestProxyTransport else {
                    fail("TestProxyTransport is not set"); partialDone(); return
                }
                XCTAssertEqual(transport.protocolMessagesSent.filter { $0.action == .auth }.count, 0)
                XCTAssertEqual(transport.protocolMessagesReceived.filter { $0.action == .connected }.count, 1) // New transport
                partialDone()
            }
        }
    }

    // RTC8c - part 2
    func test__038__RealtimeClient__Auth_authorize_should_upgrade_the_connection_with_current_token__when_the_connection_is_in_the_CLOSED_state_when_auth_authorize_is_called__after_obtaining_a_token_the_library_should_move_to_the_CONNECTING_state_and_initiate_a_connection_attempt_using_the_new_token() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        let testToken = try getTestToken(for: test)
        options.token = testToken
        options.testOptions.transportFactory = TestProxyTransportFactory()
        let client = RealtimeClient(options: options)
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { stateChange in
                XCTAssertNil(stateChange.reason)
                done()
            }
            client.connect()
        }

        client.close()
        expect(client.connection.state).toEventually(equal(RealtimeConnectionState.closed), timeout: testTimeout)

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(3, done: done)

            client.connection.once(.connecting) { stateChange in
                XCTAssertEqual(stateChange.previous, RealtimeConnectionState.closed)
                XCTAssertNil(stateChange.reason)
                partialDone()
            }

            client.connection.once(.connected) { stateChange in
                XCTAssertEqual(stateChange.previous, RealtimeConnectionState.connecting)
                XCTAssertNil(stateChange.reason)
                partialDone()
            }

            client.auth.authorize(nil, options: nil) { tokenDetails, error in
                XCTAssertNil(error)
                guard let tokenDetails = tokenDetails else {
                    fail("TokenDetails is nil"); partialDone(); return
                }

                XCTAssertEqual(client.connection.state, RealtimeConnectionState.connected)
                XCTAssertNotEqual(tokenDetails.token, testToken)

                guard let transport = client.internal.transport as? TestProxyTransport else {
                    fail("TestProxyTransport is not set"); partialDone(); return
                }
                XCTAssertEqual(transport.protocolMessagesSent.filter { $0.action == .auth }.count, 0)
                XCTAssertEqual(transport.protocolMessagesReceived.filter { $0.action == .connected }.count, 1) // New transport
                partialDone()
            }
        }
    }

    // RTC8c - part 3
    func test__039__RealtimeClient__Auth_authorize_should_upgrade_the_connection_with_current_token__when_the_connection_is_in_the_DISCONNECTED_state_when_auth_authorize_is_called__after_obtaining_a_token_the_library_should_move_to_the_CONNECTING_state_and_initiate_a_connection_attempt_using_the_new_token() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        let testToken = try getTestToken(for: test)
        options.token = testToken
        options.testOptions.transportFactory = TestProxyTransportFactory()
        let client = RealtimeClient(options: options)
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { stateChange in
                XCTAssertNil(stateChange.reason)
                done()
            }
            client.connect()
        }

        client.internal.onDisconnected()
        expect(client.connection.state).toEventually(equal(RealtimeConnectionState.disconnected), timeout: testTimeout)

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(3, done: done)

            client.connection.once(.connecting) { stateChange in
                XCTAssertEqual(stateChange.previous, RealtimeConnectionState.disconnected)
                XCTAssertNil(stateChange.reason)
                partialDone()
            }

            client.connection.once(.connected) { stateChange in
                XCTAssertEqual(stateChange.previous, RealtimeConnectionState.connecting)
                XCTAssertNil(stateChange.reason)
                partialDone()
            }

            client.auth.authorize(nil, options: nil) { tokenDetails, error in
                XCTAssertNil(error)
                guard let tokenDetails = tokenDetails else {
                    fail("TokenDetails is nil"); partialDone(); return
                }

                XCTAssertEqual(client.connection.state, RealtimeConnectionState.connected)
                XCTAssertNotEqual(tokenDetails.token, testToken)

                guard let transport = client.internal.transport as? TestProxyTransport else {
                    fail("TestProxyTransport is not set"); partialDone(); return
                }
                XCTAssertEqual(transport.protocolMessagesSent.filter { $0.action == .auth }.count, 0)
                XCTAssertEqual(transport.protocolMessagesReceived.filter { $0.action == .connected }.count, 1) // New transport
                partialDone()
            }
        }
    }

    // RTC8c - part 4
    func test__040__RealtimeClient__Auth_authorize_should_upgrade_the_connection_with_current_token__when_the_connection_is_in_the_FAILED_state_when_auth_authorize_is_called__after_obtaining_a_token_the_library_should_move_to_the_CONNECTING_state_and_initiate_a_connection_attempt_using_the_new_token() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        let testToken = try getTestToken(for: test)
        options.token = testToken
        options.testOptions.transportFactory = TestProxyTransportFactory()
        let client = RealtimeClient(options: options)
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { stateChange in
                XCTAssertNil(stateChange.reason)
                done()
            }
            client.connect()
        }

        client.internal.onError(AblyTests.newErrorProtocolMessage())
        expect(client.connection.state).toEventually(equal(RealtimeConnectionState.failed), timeout: testTimeout)

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(3, done: done)

            client.connection.once(.connecting) { stateChange in
                XCTAssertEqual(stateChange.previous, RealtimeConnectionState.failed)
                XCTAssertNil(stateChange.reason)
                partialDone()
            }

            client.connection.once(.connected) { stateChange in
                XCTAssertEqual(stateChange.previous, RealtimeConnectionState.connecting)
                XCTAssertNil(stateChange.reason)
                partialDone()
            }

            client.auth.authorize(nil, options: nil) { tokenDetails, error in
                XCTAssertNil(error)
                guard let tokenDetails = tokenDetails else {
                    fail("TokenDetails is nil"); partialDone(); return
                }

                XCTAssertEqual(client.connection.state, RealtimeConnectionState.connected)
                XCTAssertNotEqual(tokenDetails.token, testToken)

                guard let transport = client.internal.transport as? TestProxyTransport else {
                    fail("TestProxyTransport is not set"); partialDone(); return
                }
                XCTAssertEqual(transport.protocolMessagesSent.filter { $0.action == .auth }.count, 0)
                XCTAssertEqual(transport.protocolMessagesReceived.filter { $0.action == .connected }.count, 1) // New transport
                partialDone()
            }
        }
    }

    // https://github.com/ably/ably-cocoa/issues/577
    func test__005__RealtimeClient__background_behaviour() {
        let test = Test()
        waitUntil(timeout: testTimeout) { done in
            URLSession.shared.dataTask(with: URL(string: "https://ably.com")!) { _, _, _ in
                let realtime: RealtimeClient

                do {
                    realtime = .init(options: try AblyTests.commonAppSetup(for: test))
                } catch {
                    XCTFail("commonAppSetup failed: \(error)")
                    return
                }

                realtime.channels.get(test.uniqueChannelName()).attach { error in
                    XCTAssertNil(error)
                    realtime.close()
                    done()
                }
            }.resume()
        }
    }

    func test__006__RealtimeClient__should_accept_acks_with_different_order() throws {
        let test = Test()
        let realtime = AblyTests.newRealtime(try AblyTests.commonAppSetup(for: test)).client
        defer { realtime.dispose(); realtime.close() }
        let channel = realtime.channels.get(test.uniqueChannelName())
        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                XCTAssertNil(error)
                done()
            }
        }
        guard let transport = realtime.internal.transport as? TestProxyTransport else {
            fail("TestProxyTransport is not set"); return
        }

        waitUntil(timeout: testTimeout) { done in
            transport.setListenerBeforeProcessingIncomingMessage { pm in
                if pm.action == .ack, let msgSerial = pm.msgSerial {
                    switch msgSerial.intValue {
                    case 0:
                        pm.msgSerial = 3
                    case 1:
                        pm.msgSerial = 2
                    case 2:
                        pm.msgSerial = 1
                    default:
                        pm.msgSerial = 0
                    }
                }
            }

            let partialDone = AblyTests.splitDone(4, done: done)
            channel.publish("test1", data: nil) { error in
                XCTAssertNil(error)
                partialDone()
            }
            channel.publish("test2", data: nil) { error in
                XCTAssertNil(error)
                partialDone()
            }
            channel.publish("test3", data: nil) { error in
                XCTAssertNil(error)
                partialDone()
            }
            channel.publish("test4", data: nil) { error in
                XCTAssertNil(error)
                partialDone()
            }
        }
    }

    func test__007__RealtimeClient__transport_should_guarantee_the_incoming_message_order() throws {
        let test = Test()
        let realtime = RealtimeClient(options: try AblyTests.commonAppSetup(for: test))
        defer { realtime.dispose(); realtime.close() }
        waitUntil(timeout: testTimeout) { done in
            realtime.connection.on(.connected) { _ in
                done()
            }
        }
        guard let webSocketTransport = realtime.internal.transport as? ARTWebSocketTransport else {
            fail("should be using a WebSocket transport"); return
        }

        var result: [Int] = []
        let expectedOrder = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30]

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(expectedOrder.count, done: done)

            realtime.internal.testSuite_getArgument(from: NSSelectorFromString("ack:"), at: 0) { object in
                guard let value = (object as? ARTProtocolMessage)?.msgSerial?.intValue else {
                    return
                }
                result.append(value)
                partialDone()
            }

            for i in expectedOrder {
                let message = ARTProtocolMessage()
                message.action = .ack
                message.msgSerial = i as NSNumber
                webSocketTransport.webSocket(webSocketTransport.websocket!, didReceiveMessage: message)
            }
        }

        XCTAssertEqual(result, expectedOrder)
    }

    func test__008__RealtimeClient__subscriber_should_receive_messages_in_the_same_order_in_which_they_have_been_sent() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let realtime1 = RealtimeClient(options: options)
        let realtime2 = RealtimeClient(options: options)
        defer {
            realtime1.dispose(); realtime1.close()
            realtime2.dispose(); realtime2.close()
        }

        let channelName = test.uniqueChannelName()
        let subscribeChannel = realtime1.channels.get(channelName)
        let sendChannel = realtime2.channels.get(channelName)

        waitUntil(timeout: testTimeout) { done in
            subscribeChannel.attach { _ in
                done()
            }
        }

        let expectedResults = [Int](1 ... 50)

        waitUntil(timeout: testTimeout) { done in
            var index = 0
            subscribeChannel.subscribe { message in
                let value = expectedResults[index]
                let receivedValue = message.name
                XCTAssertEqual(receivedValue, String(value))
                index += 1
                if receivedValue == String(describing: expectedResults.last!) {
                    done()
                }
            }
            for i in expectedResults {
                sendChannel.publish(String(i), data: nil)
            }
        }
    }

    // Issue https://github.com/ably/ably-cocoa/issues/640
    func test__009__RealtimeClient__should_dispatch_in_user_queue_when_removing_an_observer() {
        let test = Test()
        let channelName = test.uniqueChannelName()
        class Foo {
            private let channelName: String
            init(channelName: String) {
                self.channelName = channelName
                AblyManager.sharedClient.channels.get(channelName).subscribe { _ in
                    // keep reference
                    self.update()
                }
            }

            func update() {}

            deinit {
                AblyManager.sharedClient.channels.get(channelName).unsubscribe()
            }
        }

        var foo: Foo? = Foo(channelName: channelName)
        XCTAssertNotNil(foo)
        foo = nil
        AblyManager.sharedClient.channels.get(channelName).unsubscribe()
    }

    func test__010__RealtimeClient__should_never_register_any_connection_listeners_for_internal_use_with_the_public_EventEmitter() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        let client = RealtimeClient(options: options)
        defer { client.dispose(); client.close() }

        client.connect()
        client.close() // Before it connects; this registers a listener on the internal event emitter.
        XCTAssertEqual(client.connection.state, RealtimeConnectionState.connecting)
        client.connection.off()
        // If we didn't have a separate internal event emitter, the line above would unregister
        // the listener, and the next lines would fail, because we would never move to
        // CLOSED, because we do that on the internal event listener registered when
        // we called close().
        XCTAssertEqual(client.connection.state, RealtimeConnectionState.connecting) // Still connecting...
        expect(client.connection.state).toEventually(equal(RealtimeConnectionState.closed), timeout: testTimeout)
    }

    func test__011__RealtimeClient__should_never_register_any_message_and_channel_listeners_for_internal_use_with_the_public_EventEmitter() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = RealtimeClient(options: options)
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(test.uniqueChannelName())
        waitUntil(timeout: testTimeout) { done in
            channel.attach { _ in
                done()
            }
        }
        if channel.state != .attached {
            fail("Channel is not attached")
            return
        }

        client.internal.onDisconnected()
        XCTAssertEqual(client.connection.state, .disconnected)

        // If we now send a message through the channel, it will be queued and the channel
        // should register a listener in the connection's _internal_ event emitter.
        // If we call client.connection.off(), reconnect, and never get the message ACK,
        // we probably weren't using the internal event emitter but the public one.

        client.connection.off()

        waitUntil(timeout: testTimeout) { done in
            channel.publish("test", data: nil) { err in
                XCTAssertNil(err)
                done()
            }
            client.connect()
        }
    }

    func test__012__RealtimeClient__moves_to_DISCONNECTED_on_an_unexpected_normal_WebSocket_close() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = RealtimeClient(options: options)
        defer { client.dispose(); client.close() }

        let channelName = test.uniqueChannelName()

        var received = false
        client.channels.get(channelName).subscribe { _ in
            received = true
        }

        expect(client.connection.state).toEventually(equal(RealtimeConnectionState.connected), timeout: testTimeout)

        let ws = (client.internal.transport! as! ARTWebSocketTransport).websocket!
        ws.close(withCode: 1000, reason: "test")

        expect(client.connection.state).toEventually(equal(RealtimeConnectionState.disconnected), timeout: testTimeout)
        expect(client.connection.state).toEventually(equal(RealtimeConnectionState.connected), timeout: testTimeout)

        client.channels.get(channelName).publish(nil, data: "test")

        expect(received).toEventually(beTrue(), timeout: testTimeout)
    }

    // RSL1i

    func test__041__If_the_total_size_of_message_s__exceeds_the_maxMessageSize__the_client_library_should_reject_the_publish_and_indicate_an_error() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = RealtimeClient(options: options)
        let channel = client.channels.get(test.uniqueChannelName())
        let messages = buildMessagesThatExceedMaxMessageSize()
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout, action: { done in
            // Wait for connected so that maxMessageSize is loaded from connection details
            client.connection.once(.connected) { _ in
                channel.publish(messages, callback: { err in
                    XCTAssertEqual(err?.code, ErrorCode.maxMessageLengthExceeded.intValue)
                    done()
                })
            }
        })
    }

    func test__042__If_the_total_size_of_message_s__exceeds_the_maxMessageSize__the_client_library_should_reject_also_presence_messages__enter_() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.clientId = clientId
        let client = RealtimeClient(options: options)
        let channel = client.channels.get(test.uniqueChannelName())
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout, action: { done in
            client.connection.once(.connected) { _ in
                channel.presence.enter(presenceData, callback: { err in
                    XCTAssertEqual(err?.code, ErrorCode.maxMessageLengthExceeded.intValue)
                    done()
                })
            }
        })
    }

    func test__043__If_the_total_size_of_message_s__exceeds_the_maxMessageSize__the_client_library_should_reject_also_presence_messages__leave_() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.clientId = clientId
        let client = RealtimeClient(options: options)
        let channel = client.channels.get(test.uniqueChannelName())
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout, action: { done in
            client.connection.once(.connected) { _ in
                channel.presence.leave(presenceData, callback: { err in
                    XCTAssertEqual(err?.code, ErrorCode.maxMessageLengthExceeded.intValue)
                    done()
                })
            }
        })
    }

    func test__044__If_the_total_size_of_message_s__exceeds_the_maxMessageSize__the_client_library_should_reject_also_presence_messages__update_() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.clientId = clientId
        let client = RealtimeClient(options: options)
        let channel = client.channels.get(test.uniqueChannelName())
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout, action: { done in
            client.connection.once(.connected) { _ in
                channel.presence.update(presenceData, callback: { err in
                    XCTAssertEqual(err?.code, ErrorCode.maxMessageLengthExceeded.intValue)
                    done()
                })
            }
        })
    }

    func test__045__If_the_total_size_of_message_s__exceeds_the_maxMessageSize__the_client_library_should_reject_also_presence_messages__updateClient_() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.clientId = clientId
        let client = RealtimeClient(options: options)
        let channel = client.channels.get(test.uniqueChannelName())
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout, action: { done in
            client.connection.once(.connected) { _ in
                channel.presence.updateClient(clientId, data: presenceData, callback: { err in
                    XCTAssertEqual(err?.code, ErrorCode.maxMessageLengthExceeded.intValue)
                    done()
                })
            }
        })
    }

    func test__046__If_the_total_size_of_message_s__exceeds_the_maxMessageSize__the_client_library_should_reject_also_presence_messages__leaveClient_() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.clientId = clientId
        let client = RealtimeClient(options: options)
        let channel = client.channels.get(test.uniqueChannelName())
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout, action: { done in
            client.connection.once(.connected) { _ in
                channel.presence.leaveClient(clientId, data: presenceData, callback: { err in
                    XCTAssertEqual(err?.code, ErrorCode.maxMessageLengthExceeded.intValue)
                    done()
                })
            }
        })
    }

    // RTC17
    func test_clientId() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        options.token = try getTestToken(for: test, clientId: "tester")
        let realtime = RealtimeClient(options: options)
        defer { realtime.dispose(); realtime.close() }
        XCTAssertNil(realtime.auth.clientId)

        waitUntil(timeout: testTimeout) { done in
            realtime.connection.once(.connecting) { stateChange in
                XCTAssertNil(stateChange.reason)
                XCTAssertNil(realtime.clientId)
            }
            realtime.connection.once(.connected) { stateChange in
                XCTAssertNil(stateChange.reason)
                XCTAssertEqual(realtime.clientId, "tester")
                done()
            }
            realtime.connect()
        }
    }
}
