import AblyPubSubDevice
import AblyPubSubDevice.Private
import Nimble
import XCTest
import AblyTestingObjC

func countChannels(_ channels: RealtimeChannels) -> Int {
    var i = 0
    for _ in channels {
        i += 1
    }
    return i
}

private let customTtlInterval: TimeInterval = 0.1
private let customIdleInterval: TimeInterval = 0.1
private let expectedHostOrder = [3, 4, 0, 2, 1]
private let shuffleArrayInExpectedHostOrder = { (array: NSMutableArray) in
    let arranged = expectedHostOrder.reversed().map { array[$0] }
    for (i, element) in arranged.enumerated() {
        array[i] = element
    }
}
private func testUsesAlternativeHostOnResponse(_ caseTest: FakeNetworkResponse, channelName: String) {
    let options = ClientOptions(key: "xxxx:xxxx")
    options.autoConnect = false
    options.disconnectedRetryTimeout = 1.0
    options.testOptions.realtimeRequestTimeout = 1.0
    let transportFactory = TestProxyTransportFactory()
    options.testOptions.transportFactory = transportFactory
    let client = PubSubClient(options: options)
    defer { client.dispose(); client.close() }
    client.channels.get(channelName)

    transportFactory.fakeNetworkResponse = caseTest

    var urlConnections = [URL]()
    transportFactory.networkConnectEvent = { transport, url in
        if client.internal.transport !== transport {
            return
        }
        urlConnections.append(url)
    }

    waitUntil(timeout: testTimeout) { done in
        let partialDone = AblyTests.splitDone(2, done: done)
        // default host with the fake response or wss://main.[a-e].fallback.ably-realtime.com: when a timeout occurs
        client.connection.on(.disconnected) { _ in
            partialDone()
        }
        client.connect()
    }

    XCTAssertEqual(urlConnections.count, 2)
    XCTAssertTrue(NSRegularExpression.match(urlConnections.at(0)?.absoluteString, pattern: "//main.realtime.ably.net"))
    XCTAssertTrue(NSRegularExpression.match(urlConnections.at(1)?.absoluteString, pattern: "//main.[a-e].fallback.ably-realtime.com"))
}

private func testMovesToDisconnectedWithNetworkingError(_ error: Error, for test: Test) throws {
    let options = try AblyTests.commonAppSetup(for: test)
    options.autoConnect = false
    options.testOptions.transportFactory = TestProxyTransportFactory()
    let client = AblyTests.newRealtime(options).client
    defer {
        client.dispose()
        client.close()
    }

    waitUntil(timeout: testTimeout) { done in
        client.connection.once(.connected) { _ in
            done()
        }
        client.connect()
    }

    var _transport: ARTWebSocketTransport?
    AblyTests.queue.sync {
        _transport = client.internal.transport as? ARTWebSocketTransport
    }

    guard let wsTransport = _transport else {
        fail("expected WS transport")
        return
    }

    waitUntil(timeout: testTimeout) { done in
        client.connection.once(.disconnected) { _ in
            done()
        }
        wsTransport.webSocket(wsTransport.websocket!, didFailWithError: error)
    }
}

private var internetConnectionNotAvailableTestsClient: PubSubClient!
private let fixtures: [String: Any] = try! JSONUtility.jsonObject(
    data: try! Data(contentsOf: URL(fileURLWithPath: pathForTestResource(testResourcesPath + "messages-encoding.json")))
)!

private func expectDataToMatch(_ message: Message, _ fixtureMessage: Any) {
    let dictionaryValue = fixtureMessage as! [String: Any]

    switch dictionaryValue["expectedType"] as! String {
    case "string":
        XCTAssertEqual(message.data as? NSString, dictionaryValue["expectedValue"] as? NSString)
    case "jsonObject":
        if let data = message.data as? NSDictionary {
            XCTAssertEqual(data, dictionaryValue["expectedValue"] as? NSDictionary)
        } else {
            fail("expected NSDictionary")
        }
    case "jsonArray":
        if let data = message.data as? NSArray {
            XCTAssertEqual(data, dictionaryValue["expectedValue"] as? NSArray)
        } else {
            fail("expected NSArray")
        }
    case "binary":
        XCTAssertEqual(message.data as? NSData, (dictionaryValue["expectedHexValue"] as! String).dataFromHexadecimalString()! as NSData?)
    default:
        fail("unhandled: \(dictionaryValue["expectedType"] as! String)")
    }
}

private var jsonOptions: ClientOptions!
private var msgpackOptions: ClientOptions!

private func setupDependencies(for test: Test) throws {
    if jsonOptions == nil {
        jsonOptions = try AblyTests.commonAppSetup(for: test)
        jsonOptions.useBinaryProtocol = false
        // Keep the same key and channel prefix
        msgpackOptions = (jsonOptions.copy() as! ClientOptions)
        msgpackOptions.useBinaryProtocol = true
    }
}

class RealtimeClientConnectionTests: XCTestCase {
    // XCTest invokes this method before executing the first test in the test suite. We use it to ensure that the global variables are initialized at the same moment, and in the same order, as they would have been when we used the Quick testing framework.
    override class var defaultTestSuite: XCTestSuite {
        _ = customTtlInterval
        _ = customIdleInterval
        _ = expectedHostOrder
        _ = internetConnectionNotAvailableTestsClient
        _ = fixtures
        _ = jsonOptions
        _ = msgpackOptions

        return super.defaultTestSuite
    }

    // CD2c

    func test__016__Connection__ConnectionDetails__maxMessageSize_overrides_the_default_maxMessageSize() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        options.testOptions.transportFactory = TestProxyTransportFactory()
        let client = PubSubClient(options: options)
        let defaultMaxMessageSize = Default.maxMessageSize()
        // Sandbox apps have a 16384 limit
        XCTAssertEqual(defaultMaxMessageSize, 16384)
        defer {
            Default.setMaxMessageSize(defaultMaxMessageSize)
            client.dispose()
            client.close()
        }
        // Setting different value to check override below
        Default.setMaxMessageSize(1)

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { _ in
                let transport = client.internal.transport as! TestProxyTransport
                let maxMessageSize = transport.protocolMessagesReceived.filter { $0.action == .connected }[0].connectionDetails?.maxMessageSize
                XCTAssertEqual(maxMessageSize, defaultMaxMessageSize)
                XCTAssertEqual(client.connection.maxMessageSize, maxMessageSize)
                done()
            }
            client.connect()
        }
    }

    // RTN2

    func test__017__Connection__url__should_connect_to_the_default_host() {
        let options = ClientOptions(key: "keytest:secret")
        options.autoConnect = false
        options.testOptions.transportFactory = TestProxyTransportFactory()

        let client = PubSubClient(options: options)
        client.connect()
        defer { client.dispose(); client.close() }

        if let transport = client.internal.transport as? TestProxyTransport, let url = transport.lastUrl {
            XCTAssertEqual(url.host, "main.realtime.ably.net")
        } else {
            XCTFail("MockTransport isn't working")
        }
    }

    func test__018__Connection__url__should_connect_with_query_string_params() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        options.testOptions.transportFactory = TestProxyTransportFactory()

        let client = PubSubClient(options: options)
        client.connect()
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.on { stateChange in
                let state = stateChange.current
                let errorInfo = stateChange.reason
                switch state {
                case .failed:
                    AblyTests.checkError(errorInfo, withAlternative: "Failed state")
                    done()
                case .connected:
                    if let transport = client.internal.transport as? TestProxyTransport, let query = transport.lastUrl?.query {
                        expect(query).to(haveParam("key", withValue: options.key ?? ""))
                        expect(query).to(haveParam("echo", withValue: "true"))
                        expect(query).to(haveParam("format", withValue: "msgpack"))
                    } else {
                        XCTFail("MockTransport isn't working")
                    }
                    done()
                default:
                    break
                }
            }
        }
    }

    func test__019__Connection__url__should_connect_with_query_string_params_including_clientId() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.clientId = "client_string"
        options.useTokenAuth = true
        options.autoConnect = false
        options.echoMessages = false
        options.testOptions.transportFactory = TestProxyTransportFactory()

        let client = PubSubClient(options: options)
        client.connect()
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.on { stateChange in
                let state = stateChange.current
                let errorInfo = stateChange.reason
                switch state {
                case .failed:
                    AblyTests.checkError(errorInfo, withAlternative: "Failed state")
                    done()
                case .connected:
                    if let transport = client.internal.transport as? TestProxyTransport, let query = transport.lastUrl?.query {
                        expect(query).to(haveParam("accessToken", withValue: client.auth.tokenDetails?.token ?? ""))
                        expect(query).to(haveParam("echo", withValue: "false"))
                        expect(query).to(haveParam("format", withValue: "msgpack"))
                        expect(query).to(haveParam("clientId", withValue: "client_string"))
                    } else {
                        XCTFail("MockTransport isn't working")
                    }
                    done()
                default:
                    break
                }
            }
        }
    }

    // RTN3
    func test__001__Connection__should_connect_automatically() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        var connected = false

        // Default
        XCTAssertTrue(options.autoConnect, "autoConnect should be true by default")

        let client = PubSubClient(options: options)
        defer { client.dispose(); client.close() }
        // The only way to control this functionality is with the options flag
        client.connection.on { stateChange in
            let state = stateChange.current
            let error = stateChange.reason
            XCTAssertNil(error)
            switch state {
            case .connected:
                connected = true
            default:
                break
            }
        }
        expect(connected).toEventually(beTrue(), timeout: DispatchTimeInterval.seconds(10), description: "Can't connect automatically")
    }

    func test__002__Connection__should_connect_manually() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false

        let client = PubSubClient(options: options)
        defer { client.dispose(); client.close() }
        var waiting = true

        waitUntil(timeout: testTimeout) { done in
            client.connection.on { stateChange in
                let state = stateChange.current
                let error = stateChange.reason
                XCTAssertNil(error)
                switch state {
                case .connected:
                    if waiting {
                        XCTFail("Expected to be disconnected")
                    }
                    done()
                default:
                    break
                }
            }
            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + DispatchTimeInterval.seconds(2)) {
                waiting = false
                client.connect()
            }
        }
    }

    // RTN2f
    func test__003__Connection__API_version_param_must_be_included_in_all_connections() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        let client = PubSubClient(options: options)
        defer { client.dispose(); client.close() }
        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connecting) { _ in
                guard let webSocketTransport = client.internal.transport as? ARTWebSocketTransport else {
                    fail("Transport should be of type ARTWebSocketTransport"); done()
                    return
                }
                XCTAssertNotNil(webSocketTransport.websocketURL)

                // This test should not directly validate version against Default.version(), as
                // ultimately the version header has been derived from that value.
                expect(webSocketTransport.websocketURL?.query).to(haveParam("v", withValue: "6"))

                done()
            }
            client.connect()
        }
    }

    // RTN2g (Deprecated in favor of RCS7d)

    // RSC7d
    func test__004__Connection__Library_and_version_param__agent__should_include_the__Ably_Agent__header_value() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        options.testOptions.transportFactory = TestProxyTransportFactory()

        let client = PubSubClient(options: options)
        client.connect()

        waitUntil(timeout: testTimeout) { done in
            client.connection.on { stateChange in
                let state = stateChange.current
                let errorInfo = stateChange.reason
                switch state {
                case .failed:
                    AblyTests.checkError(errorInfo, withAlternative: "Failed state")
                    done()
                case .connected:
                    if let transport = client.internal.transport as? TestProxyTransport, let query = transport.lastUrl?.query {
                        expect(query).to(haveParam("agent", hasPrefix: "ably-pubsub-cocoa/2.0.0"))
                    } else {
                        XCTFail("MockTransport isn't working")
                    }
                    done()
                default:
                    break
                }
            }
        }
        client.close()
    }

    // RTN4

    // RTN4a
    func test__020__Connection__event_emitter__should_emit_events_for_state_changes() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false

        let client = PubSubClient(options: options)
        defer { client.dispose(); client.close() }
        let connection = client.connection
        var events: [RealtimeConnectionState] = []

        waitUntil(timeout: testTimeout) { done in
            var alreadyDisconnected = false
            var alreadyClosed = false

            connection.on { stateChange in
                let state = stateChange.current
                let errorInfo = stateChange.reason
                switch state {
                case .connecting:
                    if !alreadyDisconnected {
                        events += [state]
                    }
                case .connected:
                    if alreadyClosed {
                        delay(0) {
                            client.internal.onSuspended()
                        }
                    } else if alreadyDisconnected {
                        client.close()
                    } else {
                        events += [state]
                        delay(0) {
                            client.internal.onDisconnected()
                        }
                    }
                case .disconnected:
                    events += [state]
                    alreadyDisconnected = true
                case .suspended:
                    events += [state]
                    client.internal.onError(AblyTests.newErrorProtocolMessage())
                case .closing:
                    events += [state]
                case .closed:
                    events += [state]
                    alreadyClosed = true
                    client.connect()
                case .failed:
                    events += [state]
                    XCTAssertNotNil(errorInfo, "Error is nil")
                    connection.off()
                    done()
                default:
                    break
                }
            }
            events += [connection.state]
            connection.connect()
        }

        if events.count != 8 {
            fail("Missing some states, got \(events)")
            return
        }

        XCTAssertEqual(events[0].rawValue, RealtimeConnectionState.initialized.rawValue, "Should be INITIALIZED state")
        XCTAssertEqual(events[1].rawValue, RealtimeConnectionState.connecting.rawValue, "Should be CONNECTING state")
        XCTAssertEqual(events[2].rawValue, RealtimeConnectionState.connected.rawValue, "Should be CONNECTED state")
        XCTAssertEqual(events[3].rawValue, RealtimeConnectionState.disconnected.rawValue, "Should be DISCONNECTED state")
        XCTAssertEqual(events[4].rawValue, RealtimeConnectionState.closing.rawValue, "Should be CLOSING state")
        XCTAssertEqual(events[5].rawValue, RealtimeConnectionState.closed.rawValue, "Should be CLOSED state")
        XCTAssertEqual(events[6].rawValue, RealtimeConnectionState.suspended.rawValue, "Should be SUSPENDED state")
        XCTAssertEqual(events[7].rawValue, RealtimeConnectionState.failed.rawValue, "Should be FAILED state")
    }

    // RTN4h
    func test__021__Connection__event_emitter__should_never_emit_a_ConnectionState_event_for_a_state_equal_to_the_previous_state() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = PubSubClient(options: options)
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { stateChange in
                XCTAssertNil(stateChange.reason)
                done()
            }
        }

        client.connection.once(.connected) { _ in
            fail("Should not emit a Connected state")
        }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.update) { stateChange in
                XCTAssertNil(stateChange.reason)
                XCTAssertEqual(client.connection.state, RealtimeConnectionState.connected)
                XCTAssertEqual(stateChange.current, RealtimeConnectionState.connected)
                XCTAssertEqual(stateChange.current, stateChange.previous)
                done()
            }

            let authMessage = ARTProtocolMessage()
            authMessage.action = .auth
            client.internal.transport?.receive(authMessage)
        }
    }

    func test__021b__Connection__event_emitter__should_never_emit_a_ConnectionState_event_for_a_state_equal_to_the_previous_state_CONNECTING() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false

        let client = PubSubClient(options: options)
        defer { client.dispose(); client.close() }

        var events: [RealtimeConnectionState] = []

        waitUntil(timeout: testTimeout) { done in
            client.connection.on { stateChange in
                XCTAssertNil(stateChange.reason)
                let state = stateChange.current
                switch state {
                case .connecting:
                    events += [state]
                case .connected:
                    done()
                default:
                    break
                }
            }
            client.connect()
            client.connect()
        }
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].rawValue, RealtimeConnectionState.connecting.rawValue, "Should be CONNECTING state")
    }

    // RTN4b
    func test__022__Connection__event_emitter__should_emit_states_on_a_new_connection() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false

        let client = PubSubClient(options: options)
        defer { client.dispose(); client.close() }
        let connection = client.connection
        var events: [RealtimeConnectionState] = []

        waitUntil(timeout: testTimeout) { done in
            connection.on { stateChange in
                let state = stateChange.current
                let error = stateChange.reason
                XCTAssertNil(error)
                switch state {
                case .connecting:
                    events += [state]
                case .connected:
                    events += [state]
                    done()
                default:
                    break
                }
            }
            connection.connect()
        }

        expect(events).to(haveCount(2), description: "Missing CONNECTING or CONNECTED state")

        if events.count != 2 {
            return
        }

        XCTAssertEqual(events[0].rawValue, RealtimeConnectionState.connecting.rawValue, "Should be CONNECTING state")
        XCTAssertEqual(events[1].rawValue, RealtimeConnectionState.connected.rawValue, "Should be CONNECTED state")
    }

    // RTN4c
    func test__023__Connection__event_emitter__should_emit_states_when_connection_is_closed() throws {
        let test = Test()
        let client = PubSubClient(options: try AblyTests.commonAppSetup(for: test))
        let connection = client.connection
        defer { client.dispose(); client.close() }
        var events: [RealtimeConnectionState] = []

        waitUntil(timeout: testTimeout) { done in
            connection.on { stateChange in
                let state = stateChange.current
                let error = stateChange.reason
                XCTAssertNil(error)
                switch state {
                case .connected:
                    connection.close()
                case .closing:
                    events += [state]
                case .closed:
                    events += [state]
                    done()
                default:
                    break
                }
            }
        }

        expect(events).to(haveCount(2), description: "Missing CLOSING or CLOSED state")

        if events.count != 2 {
            return
        }

        XCTAssertEqual(events[0].rawValue, RealtimeConnectionState.closing.rawValue, "Should be CLOSING state")
        XCTAssertEqual(events[1].rawValue, RealtimeConnectionState.closed.rawValue, "Should be CLOSED state")
    }

    // RTN4d
    func test__024__Connection__event_emitter__should_have_the_current_state() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        let client = PubSubClient(options: options)
        defer { client.dispose(); client.close() }
        let connection = client.connection
        XCTAssertEqual(connection.state.rawValue, RealtimeConnectionState.initialized.rawValue, "Missing INITIALIZED state")

        waitUntil(timeout: testTimeout) { done in
            connection.on { stateChange in
                let state = stateChange.current
                let error = stateChange.reason
                XCTAssertNil(error)
                switch state {
                case .connecting:
                    XCTAssertEqual(connection.state.rawValue, RealtimeConnectionState.connecting.rawValue, "Missing CONNECTING state")
                case .connected:
                    XCTAssertEqual(connection.state.rawValue, RealtimeConnectionState.connected.rawValue, "Missing CONNECTED state")
                    done()
                default:
                    break
                }
            }
            client.connect()
        }
    }

    // RTN4e
    func test__025__Connection__event_emitter__should_have_a_ConnectionStateChange_as_first_argument_for_every_connection_state_change() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        let client = PubSubClient(options: options)
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(RealtimeConnectionEvent.connected) { stateChange in
                expect(stateChange).to(beAKindOf(ConnectionStateChange.self))
                XCTAssertEqual(stateChange.current, RealtimeConnectionState.connected)
                XCTAssertEqual(stateChange.previous, RealtimeConnectionState.connecting)
                done()
            }
            client.connect()
        }
    }

    // RTN4f
    func test__026__Connection__event_emitter__should_have_the_reason_which_contains_an_ErrorInfo() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = PubSubClient(options: options)
        defer { client.dispose(); client.close() }
        let connection = client.connection

        var errorInfo: ErrorInfo?
        waitUntil(timeout: testTimeout) { done in
            connection.on { stateChange in
                let state = stateChange.current
                let reason = stateChange.reason
                switch state {
                case .connected:
                    XCTAssertEqual(stateChange.event, RealtimeConnectionEvent.connected)
                    client.internal.onError(AblyTests.newErrorProtocolMessage())
                case .failed:
                    XCTAssertEqual(stateChange.event, RealtimeConnectionEvent.failed)
                    errorInfo = reason
                    done()
                default:
                    break
                }
            }
        }

        XCTAssertNotNil(errorInfo)
    }

    // RTN4f
    func test__027__Connection__event_emitter__any_state_change_triggered_by_a_ProtocolMessage_that_contains_an_Error_member_should_populate_the_Reason_property() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.useTokenAuth = true
        let client = AblyTests.newRealtime(options).client
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { stateChange in
                XCTAssertNil(stateChange.reason)
                done()
            }
        }

        guard let transport = client.internal.transport as? TestProxyTransport else {
            fail("TestProxyTransport is not set"); return
        }
        guard let originalConnectedMessage = transport.protocolMessagesReceived.filter({ $0.action == .connected }).first else {
            fail("First CONNECTED message not received"); return
        }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.update) { stateChange in
                guard let error = stateChange.reason else {
                    fail("Reason error is nil"); done(); return
                }
                XCTAssertEqual(error.code, 1234)
                XCTAssertEqual(error.message, "fabricated error")
                XCTAssertEqual(stateChange.event, RealtimeConnectionEvent.update)
                done()
            }

            let connectedMessageWithError = originalConnectedMessage
            connectedMessageWithError.error = ErrorInfo.create(withCode: 1234, message: "fabricated error")
            client.internal.transport?.receive(connectedMessageWithError)
        }
    }

    // RTN5
    func test__005__Connection__basic_operations_should_work_simultaneously() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.echoMessages = false
        var disposable = [PubSubClient]()
        let numClients = 50
        let numMessages = 5
        let channelName = "chat"
        let testTimeout = DispatchTimeInterval.seconds(60)

        defer {
            for client in disposable {
                client.dispose()
                client.close()
            }
        }

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(numClients, done: done)
            for _ in 1 ... numClients {
                let client = PubSubClient(options: options)
                disposable.append(client)
                let channel = client.channels.get(channelName)
                channel.attach { error in
                    if let error = error {
                        fail(error.message); done()
                    }
                    partialDone()
                }
            }
        }

        var messagesReceived = 0
        waitUntil(timeout: testTimeout) { done in
            // Sends numMessages messages from different clients to the same channel
            // numMessages messages for numClients clients = numMessages*numClients total messages
            // echo is off, so we need to subtract one message per publish
            let messagesExpected = numMessages * numClients - 1 * numMessages
            var messagesSent = 0
            for client in disposable {
                let channel = client.channels.get(channelName)
                XCTAssertEqual(channel.state, RealtimeChannelState.attached)

                channel.subscribe { message in
                    XCTAssertEqual(message.data as? String, "message_string")
                    messagesReceived += 1
                    if messagesReceived == messagesExpected {
                        done()
                    }
                }

                if messagesSent < numMessages {
                    channel.publish(nil, data: "message_string", callback: nil)
                    messagesSent += 1
                }
            }
        }

        XCTAssertEqual(disposable.count, numClients)
        XCTAssertEqual(countChannels(disposable.first!.channels), 1)
        XCTAssertEqual(countChannels(disposable.last!.channels), 1)
    }

    // RTN6
    func test__006__Connection__should_have_an_opened_websocket_connection_and_received_a_CONNECTED_ProtocolMessage() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        options.testOptions.transportFactory = TestProxyTransportFactory()
        let client = PubSubClient(options: options)
        client.connect()
        defer {
            client.dispose()
            client.close()
        }

        waitUntil(timeout: testTimeout) { done in
            client.connection.on { stateChange in
                let state = stateChange.current
                let error = stateChange.reason
                XCTAssertNil(error)
                if state == .connected, error == nil {
                    done()
                }
            }
        }

        if let webSocketTransport = client.internal.transport as? ARTWebSocketTransport {
            XCTAssertEqual(webSocketTransport.state, ARTRealtimeTransportState.opened)
        } else {
            XCTFail("WebSocket is not the default transport")
        }

        if let transport = client.internal.transport as? TestProxyTransport {
            // CONNECTED ProtocolMessage
            expect(transport.protocolMessagesReceived.map { $0.action }).to(contain(ARTProtocolMessageAction.connected))
        } else {
            XCTFail("MockTransport is not working")
        }
    }

    // RTN7

    // RTN7a

    func test__028__Connection__ACK_and_NACK__should_expect_either_an_ACK_or_NACK_to_confirm__successful_receipt_and_acceptance_of_message() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        options.clientId = "client_string"
        options.testOptions.transportFactory = TestProxyTransportFactory()
        let client = PubSubClient(options: options)
        client.connect()
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            publishFirstTestMessage(client, channelName: test.uniqueChannelName(), completion: { error in
                XCTAssertNil(error)
                done()
            })
        }

        let transport = client.internal.transport as! TestProxyTransport

        guard let publishedMessage = transport.protocolMessagesSent.filter({ $0.action == .message }).last else {
            XCTFail("No MESSAGE action was sent"); return
        }

        guard let receivedAck = transport.protocolMessagesReceived.filter({ $0.action == .ack }).last else {
            XCTFail("No ACK action was received"); return
        }

        XCTAssertEqual(publishedMessage.msgSerial, receivedAck.msgSerial)
    }

    func test__029__Connection__ACK_and_NACK__should_expect_either_an_ACK_or_NACK_to_confirm__successful_receipt_and_acceptance_of_presence() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        options.clientId = "client_string"
        options.testOptions.transportFactory = TestProxyTransportFactory()
        let client = PubSubClient(options: options)
        client.connect()
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.on { stateChange in
                let state = stateChange.current
                let error = stateChange.reason
                XCTAssertNil(error)
                if state == .connected {
                    let channel = client.channels.get(test.uniqueChannelName())
                    channel.attach { error in
                        XCTAssertNil(error)
                        channel.presence.enterClient("client_string", data: nil, callback: { errorInfo in
                            XCTAssertNil(errorInfo)
                            done()
                        })
                    }
                }
            }
        }

        let transport = client.internal.transport as! TestProxyTransport

        guard let publishedMessage = transport.protocolMessagesSent.filter({ $0.action == .presence }).last else {
            XCTFail("No PRESENCE action was sent"); return
        }

        guard let receivedAck = transport.protocolMessagesReceived.filter({ $0.action == .ack }).last else {
            XCTFail("No ACK action was received"); return
        }

        XCTAssertEqual(publishedMessage.msgSerial, receivedAck.msgSerial)
    }

    func test__030__Connection__ACK_and_NACK__should_expect_either_an_ACK_or_NACK_to_confirm__message_failure() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)

        let channelName = test.uniqueChannelName()
        options.token = try getTestToken(for: test, key: options.key, capability: "{ \"\(options.testOptions.channelNamePrefix!)-\(channelName)\":[\"subscribe\"] }")
        options.autoConnect = false
        options.testOptions.transportFactory = TestProxyTransportFactory()
        let client = PubSubClient(options: options)
        client.connect()
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            publishFirstTestMessage(client, channelName: channelName, completion: { error in
                XCTAssertNotNil(error)
                done()
            })
        }

        let transport = client.internal.transport as! TestProxyTransport

        guard let publishedMessage = transport.protocolMessagesSent.filter({ $0.action == .message }).last else {
            XCTFail("No MESSAGE action was sent"); return
        }

        guard let receivedNack = transport.protocolMessagesReceived.filter({ $0.action == .nack }).last else {
            XCTFail("No NACK action was received"); return
        }

        XCTAssertEqual(publishedMessage.msgSerial, receivedNack.msgSerial)
    }

    func test__031__Connection__ACK_and_NACK__should_expect_either_an_ACK_or_NACK_to_confirm__presence_failure() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        options.clientId = "client_string"
        options.testOptions.transportFactory = TestProxyTransportFactory()
        let client = PubSubClient(options: options)
        client.connect()
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.on { stateChange in
                let state = stateChange.current
                let error = stateChange.reason
                XCTAssertNil(error)
                if state == .connected {
                    let channel = client.channels.get(test.uniqueChannelName())
                    channel.attach { error in
                        XCTAssertNil(error)
                        channel.presence.enterClient("invalid", data: nil, callback: { errorInfo in
                            XCTAssertNotNil(errorInfo)
                            done()
                        })
                    }
                }
            }
        }

        let transport = client.internal.transport as! TestProxyTransport

        guard let publishedMessage = transport.protocolMessagesSent.filter({ $0.action == .presence }).last else {
            XCTFail("No PRESENCE action was sent"); return
        }

        guard let receivedNack = transport.protocolMessagesReceived.filter({ $0.action == .nack }).last else {
            XCTFail("No NACK action was received"); return
        }

        XCTAssertEqual(publishedMessage.msgSerial, receivedNack.msgSerial)
    }

    // RTN7b

    func test__032__Connection__ACK_and_NACK__ProtocolMessage__should_contain_unique_serially_incrementing_msgSerial_along_with_the_count() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        options.clientId = "client_string"
        options.testOptions.transportFactory = TestProxyTransportFactory()
        let client = PubSubClient(options: options)
        client.connect()
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(test.uniqueChannelName())
        channel.attach()

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "message") { errorInfo in
                XCTAssertNil(errorInfo)
                done()
            }
        }

        struct TotalMessages {
            static let expected = 5
            var succeeded = 0
        }

        var totalMessages = TotalMessages()

        for index in 1 ... TotalMessages.expected {
            channel.publish(nil, data: "message\(index)") { errorInfo in
                if errorInfo == nil {
                    totalMessages.succeeded += 1
                }
            }
        }
        expect(totalMessages.succeeded).toEventually(equal(TotalMessages.expected), timeout: testTimeout)

        waitUntil(timeout: testTimeout) { done in
            channel.presence.enterClient("invalid", data: nil, callback: { errorInfo in
                XCTAssertNotNil(errorInfo)
                done()
            })
        }

        let transport = client.internal.transport as! TestProxyTransport
        let acks = transport.protocolMessagesReceived.filter { $0.action == .ack }
        let nacks = transport.protocolMessagesReceived.filter { $0.action == .nack }

        if acks.count != 2 {
            fail("Received invalid number of ACK responses: \(acks.count)")
            return
        }

        XCTAssertEqual(acks[0].msgSerial, 0)
        XCTAssertEqual(acks[0].count, 1)

        // Messages covered in a single ACK response
        XCTAssertEqual(acks[1].msgSerial, 1)
        XCTAssertEqual(Int(acks[1].count), TotalMessages.expected)

        if nacks.count != 1 {
            fail("Received invalid number of NACK responses: \(nacks.count)")
            return
        }

        XCTAssertEqual(nacks[0].msgSerial, 6)
        XCTAssertEqual(nacks[0].count, 1)
    }

    func test__033__Connection__ACK_and_NACK__ProtocolMessage__should_continue_incrementing_msgSerial_serially_if_the_connection_resumes_successfully() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.clientId = "tester"
        options.tokenDetails = try getTestTokenDetails(for: test, key: options.key!, clientId: options.clientId, ttl: 5.0)
        let client = AblyTests.newRealtime(options).client
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(test.uniqueChannelName())
        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "message") { error in
                XCTAssertNil(error)
                done()
            }
        }

        guard let initialConnectionId = client.connection.id else {
            fail("Connection ID is empty"); return
        }

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(4, done: done)
            (1 ... 3).forEach { index in
                channel.publish(nil, data: "message\(index)") { error in
                    if error == nil {
                        partialDone()
                    }
                }
            }
            channel.presence.enterClient("invalid", data: nil) { error in
                XCTAssertNotNil(error)
                partialDone()
            }
        }

        XCTAssertEqual(client.internal.msgSerial, 5)

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.disconnected) { stateChange in
                XCTAssertNotNil(stateChange.reason)
                // Token expired
                done()
            }
        }

        // Reconnected and resumed
        XCTAssertEqual(client.connection.id, initialConnectionId)
        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(4, done: done)
            (1 ... 3).forEach { index in
                channel.publish(nil, data: "message\(index)") { error in
                    if error == nil {
                        partialDone()
                    }
                }
            }
            channel.presence.enterClient("invalid", data: nil) { error in
                XCTAssertNotNil(error)
                partialDone()
            }
        }

        guard let reconnectedTransport = client.internal.transport as? TestProxyTransport else {
            fail("TestProxyTransport is not set"); return
        }
        let acks = reconnectedTransport.protocolMessagesReceived.filter { $0.action == .ack }
        let nacks = reconnectedTransport.protocolMessagesReceived.filter { $0.action == .nack }

        if acks.count != 1 {
            fail("Received invalid number of ACK responses: \(acks.count)")
            return
        }
        // Messages covered in a single ACK response
        XCTAssertEqual(acks[0].msgSerial, 5) // [0] 1st publish + [1,2,3] publish + [4] enter with invalid client + [5,6,7] queued messages
        XCTAssertEqual(acks[0].count, 3)

        if nacks.count != 1 {
            fail("Received invalid number of NACK responses: \(nacks.count)")
            return
        }
        XCTAssertEqual(nacks[0].msgSerial, 8)
        XCTAssertEqual(nacks[0].count, 1)

        XCTAssertEqual(client.internal.msgSerial, 9)
    }

    func test__034__Connection__ACK_and_NACK__ProtocolMessage__should_reset_msgSerial_serially_if_the_connection_does_not_resume() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.clientId = "tester"
        let client = AblyTests.newRealtime(options).client
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(test.uniqueChannelName())
        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "message") { error in
                XCTAssertNil(error)
                done()
            }
        }

        guard let initialConnectionId = client.connection.id else {
            fail("Connection ID is empty"); return
        }

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(4, done: done)
            (1 ... 3).forEach { index in
                channel.publish(nil, data: "message\(index)") { error in
                    if error == nil {
                        partialDone()
                    }
                }
            }
            channel.presence.enterClient("invalid", data: nil) { error in
                XCTAssertEqual(error?.code, ErrorCode.invalidClientId.intValue)
                partialDone()
            }
        }

        XCTAssertEqual(client.internal.msgSerial, 5)

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)
            client.connection.once(.disconnected) { _ in
                partialDone()
            }
            client.connection.once(.connected) { _ in
                partialDone()
            }
            client.simulateLostConnectionAndState()
        }

        // Reconnected but not resumed
        XCTAssertNotEqual(client.connection.id, initialConnectionId)
        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(4, done: done)
            (1 ... 3).forEach { index in
                channel.publish(nil, data: "message\(index)") { error in
                    if error == nil {
                        partialDone()
                    }
                }
            }
            channel.presence.enterClient("invalid", data: nil) { error in
                XCTAssertEqual(error?.code, ErrorCode.invalidClientId.intValue)
                partialDone()
            }
        }

        guard let reconnectedTransport = client.internal.transport as? TestProxyTransport else {
            fail("TestProxyTransport is not set"); return
        }
        let acks = reconnectedTransport.protocolMessagesReceived.filter { $0.action == .ack }
        let nacks = reconnectedTransport.protocolMessagesReceived.filter { $0.action == .nack }

        // The server is free to roll up multiple acks into one or not
        if acks.count < 1 {
            fail("Received invalid number of ACK responses: \(acks.count)")
            return
        }
        XCTAssertEqual(acks[0].msgSerial, 0)
        XCTAssertEqual(acks.reduce(0) { $0 + $1.count }, 3)

        if nacks.count != 1 {
            fail("Received invalid number of NACK responses: \(nacks.count)")
            return
        }
        XCTAssertEqual(nacks[0].msgSerial, 3)
        XCTAssertEqual(nacks[0].count, 1)

        XCTAssertEqual(client.internal.msgSerial, 4)
    }

    // RTN7c

    func test__035__Connection__ACK_and_NACK__should_trigger_the_failure_callback_for_the_remaining_pending_messages_if__connection_is_closed() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        options.clientId = "client_string"
        options.testOptions.transportFactory = TestProxyTransportFactory()
        let client = PubSubClient(options: options)
        client.connect()
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(test.uniqueChannelName())
        let transport = client.internal.transport as! TestProxyTransport
        transport.actionsIgnored += [.ack, .nack]

        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                XCTAssertNil(error)
                channel.publish(nil, data: "message", callback: { error in
                    guard let error = error else {
                        fail("Error is nil"); done(); return
                    }
                    expect(error.message).to(contain("connection broken before receiving publishing acknowledgment"))
                    done()
                })
                // Wait until the message is pushed to Ably first
                delay(1.0) {
                    client.close()
                }
            }
        }

        // This verifies that the pending message as been released and the publish callback is called only once!
        waitUntil(timeout: testTimeout) { done in
            delay(1.0) {
                done()
            }
        }
    }

    func test__036__Connection__ACK_and_NACK__should_trigger_the_failure_callback_for_the_remaining_pending_messages_if__connection_state_enters_FAILED() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        options.clientId = "client_string"
        options.testOptions.transportFactory = TestProxyTransportFactory()
        let client = PubSubClient(options: options)
        client.connect()
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(test.uniqueChannelName())
        let transport = client.internal.transport as! TestProxyTransport
        transport.actionsIgnored += [.ack, .nack]

        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                XCTAssertNil(error)
                channel.publish(nil, data: "message", callback: { errorInfo in
                    XCTAssertNotNil(errorInfo)
                    done()
                })
                // Wait until the message is pushed to Ably first
                delay(1.0) {
                    transport.simulateIncomingError()
                }
            }
        }
    }

    // RTN8

    // RTN8a
    func test__038__Connection__connection_id__should_be_null_until_connected() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = PubSubClient(options: options)
        let connection = client.connection
        defer {
            client.dispose()
            client.close()
        }

        XCTAssertNil(connection.id)

        waitUntil(timeout: testTimeout) { done in
            connection.on { stateChange in
                let state = stateChange.current
                let errorInfo = stateChange.reason
                XCTAssertNil(errorInfo)
                if state == .connected {
                    XCTAssertNotNil(connection.id)
                    done()
                } else if state == .connecting {
                    XCTAssertNil(connection.id)
                }
            }
        }
    }

    // RTN8b
    func test__039__Connection__connection_id__should_have_unique_IDs() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        var disposable = [PubSubClient]()
        defer {
            for client in disposable {
                client.dispose()
                client.close()
            }
        }
        var ids = [String]()
        let max = 25
        let sync = NSLock()

        waitUntil(timeout: testTimeout) { done in
            for _ in 1 ... max {
                disposable.append(PubSubClient(options: options))
                let currentConnection = disposable.last!.connection
                currentConnection.on { stateChange in
                    let state = stateChange.current
                    let error = stateChange.reason
                    XCTAssertNil(error)
                    if state == .connected {
                        guard let connectionId = currentConnection.id else {
                            fail("connectionId is nil on CONNECTED")
                            done()
                            return
                        }
                        expect(ids).toNot(contain(connectionId))

                        sync.lock()
                        ids.append(connectionId)
                        if ids.count == max {
                            done()
                        }
                        sync.unlock()

                        currentConnection.off()
                        currentConnection.close()
                    }
                }
            }
        }

        XCTAssertEqual(ids.count, max)
    }

    // RTN8c, RTN9c (connection's `id` and `key` respectively)

    func test__139__Connection__connection_id_and_key__should_be_nil_when_sdk_is_in_CLOSING_and_CLOSED_states() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = PubSubClient(options: options)
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(3, done: done)

            client.connection.on { stateChange in
                expect(stateChange.reason).to(beNil())
                if stateChange.current == .connected {
                    expect(client.connection.id).toNot(beNil())
                    expect(client.connection.key).toNot(beNil())
                    client.internal.close()
                    partialDone()
                }
                else if stateChange.current == .closing {
                    expect(client.connection.id).to(beNil())
                    expect(client.connection.key).to(beNil())
                    partialDone()
                }
                else if stateChange.current == .closed {
                    expect(client.connection.id).to(beNil())
                    expect(client.connection.key).to(beNil())
                    partialDone()
                }
            }
        }
    }

    func test__140__Connection__connection_id_and_key__should_be_nil_when_sdk_is_in_SUSPENDED_state() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = PubSubClient(options: options)
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)

            client.connection.on { stateChange in
                expect(stateChange.reason).to(beNil())
                if stateChange.current == .connected {
                    expect(client.connection.id).toNot(beNil())
                    expect(client.connection.key).toNot(beNil())
                    client.internal.onSuspended()
                    partialDone()
                }
                else if stateChange.current == .suspended {
                    expect(client.connection.id).to(beNil())
                    expect(client.connection.key).to(beNil())
                    partialDone()
                }
            }
        }
    }

    func test__141__Connection__connection_id_and_key__should_be_nil_when_sdk_is_in_FAILED_state() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = PubSubClient(options: options)
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)

            client.connection.on { stateChange in
                expect(stateChange.reason).to(beNil())
                if stateChange.current == .connected {
                    expect(client.connection.id).toNot(beNil())
                    expect(client.connection.key).toNot(beNil())
                    client.internal.onError(ARTProtocolMessage())
                    partialDone()
                }
                else if stateChange.current == .failed {
                    expect(client.connection.id).to(beNil())
                    expect(client.connection.key).to(beNil())
                    partialDone()
                }
            }
        }
    }

    // RTN9

    // RTN9a
    func test__040__Connection__connection_key__should_be_null_until_connected() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = PubSubClient(options: options)
        defer {
            client.dispose()
            client.close()
        }
        let connection = client.connection

        XCTAssertNil(connection.key)

        waitUntil(timeout: testTimeout) { done in
            connection.on { stateChange in
                let state = stateChange.current
                let errorInfo = stateChange.reason
                XCTAssertNil(errorInfo)
                if state == .connected {
                    XCTAssertNotNil(connection.id)
                    done()
                } else if state == .connecting {
                    XCTAssertNil(connection.key)
                }
            }
        }
    }

    // RTN9b
    func test__041__Connection__connection_key__should_have_unique_connection_keys() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        var disposable = [PubSubClient]()
        defer {
            for client in disposable {
                client.dispose()
                client.close()
            }
        }
        var keys = [String]()
        let max = 25

        waitUntil(timeout: testTimeout) { done in
            for _ in 1 ... max {
                disposable.append(PubSubClient(options: options))
                let currentConnection = disposable.last!.connection
                currentConnection.on { stateChange in
                    let state = stateChange.current
                    let error = stateChange.reason
                    XCTAssertNil(error)
                    if state == .connected {
                        guard let connectionKey = currentConnection.key else {
                            fail("connectionKey is nil on CONNECTED")
                            done()
                            return
                        }
                        expect(keys).toNot(contain(connectionKey))
                        keys.append(connectionKey)

                        if keys.count == max {
                            done()
                        }

                        currentConnection.off()
                        currentConnection.close()
                    }
                }
            }
        }

        XCTAssertEqual(keys.count, max)
    }

    // RTN11b
    func test__007__Connection__should_make_a_new_connection_with_a_new_transport_instance_if_the_state_is_CLOSING() throws {
        let test = Test()
        let client = PubSubClient(options: try AblyTests.commonAppSetup(for: test))
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { _ in
                done()
            }
        }

        weak var oldTransport: ARTRealtimeTransport?
        weak var newTransport: ARTRealtimeTransport?

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)

            client.connection.once(.closing) { _ in
                oldTransport = client.internal.transport
                client.connect()
                newTransport = client.internal.transport
                expect(newTransport).toNot(beIdenticalTo(oldTransport))
                partialDone()
            }

            client.connection.once(.connected) { stateChange in
                XCTAssertNil(stateChange.reason)
                XCTAssertNil(client.connection.errorReason)
                partialDone()
            }

            client.close()
        }

        XCTAssertNotNil(newTransport)
    }

    // RTN11b
    func test__008__Connection__it_should_make_sure_that__when_the_CLOSED_ProtocolMessage_arrives_for_the_old_connection__it_doesn_t_affect_the_new_one() throws {
        let test = Test()
        let client = AblyTests.newRealtime(try AblyTests.commonAppSetup(for: test)).client
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { _ in
                done()
            }
        }

        var oldTransport: ARTRealtimeTransport? // retain
        weak var newTransport: ARTRealtimeTransport?

        autoreleasepool {
            waitUntil(timeout: testTimeout) { done in
                let partialDone = AblyTests.splitDone(3, done: done)

                client.connection.once(.closing) { _ in
                    client.internalSync { _internal in
                        oldTransport = _internal.transport
                    }
                    // Old connection must complete the close request
                    weak var oldTestProxyTransport = oldTransport as? TestProxyTransport
                    oldTestProxyTransport?.setBeforeIncomingMessageModifier { protocolMessage in
                        if protocolMessage.action == .closed {
                            partialDone()
                        }
                        return protocolMessage
                    }

                    client.connect()

                    client.internalSync { _internal in
                        newTransport = _internal.transport
                    }

                    expect(newTransport).toNot(beIdenticalTo(oldTransport))
                    XCTAssertNotNil(newTransport)
                    XCTAssertNotNil(oldTransport)
                    partialDone()
                }

                client.connection.once(.closed) { _ in
                    fail("New connection should not receive the old connection event")
                }

                client.connection.once(.connected) { _ in
                    partialDone()
                }

                client.close()
            }

            oldTransport = nil
        }

        XCTAssertNotNil(newTransport)
        XCTAssertNil(oldTransport)
    }

    // RTN12

    // RTN12f
    func test__045__Connection__close__if_CONNECTING__do_the_operation_once_CONNECTED() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        let client = PubSubClient(options: options)
        defer { client.dispose() }

        client.connect()
        var lastStateChange: ConnectionStateChange?
        client.connection.on { stateChange in
            lastStateChange = stateChange
        }

        client.close()
        XCTAssertNil(lastStateChange)

        expect(lastStateChange).toEventuallyNot(beNil(), timeout: testTimeout)
        expect(lastStateChange!.current).toEventually(equal(RealtimeConnectionState.closed), timeout: testTimeout)
    }

    // RTN12a
    func test__046__Connection__close__if_CONNECTED__should_send_a_CLOSE_action__change_state_to_CLOSING_and_receive_a_CLOSED_action() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        options.testOptions.transportFactory = TestProxyTransportFactory()
        let client = PubSubClient(options: options)
        client.connect()
        defer {
            client.dispose()
        }

        let transport = client.internal.transport as! TestProxyTransport
        var states: [RealtimeConnectionState] = []

        waitUntil(timeout: testTimeout) { done in
            client.connection.on { stateChange in
                let state = stateChange.current
                let error = stateChange.reason
                XCTAssertNil(error)
                switch state {
                case .connected:
                    client.close()
                case .closing:
                    XCTAssertEqual(transport.protocolMessagesSent.filter { $0.action == .close }.count, 1)
                    states += [state]
                case .closed:
                    XCTAssertEqual(transport.protocolMessagesReceived.filter { $0.action == .closed }.count, 1)
                    states += [state]
                    done()
                default:
                    break
                }
            }
        }

        if states.count != 2 {
            fail("Invalid number of connection states. Expected CLOSING and CLOSE states")
            return
        }
        XCTAssertEqual(states[0], RealtimeConnectionState.closing)
        XCTAssertEqual(states[1], RealtimeConnectionState.closed)
    }

    // RTN12b
    func test__047__Connection__close__should_transition_to_CLOSED_action_when_the_close_process_timeouts() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        options.testOptions.transportFactory = TestProxyTransportFactory()
        let client = PubSubClient(options: options)
        client.connect()
        defer {
            client.dispose()
            client.close()
        }

        let transport = client.internal.transport as! TestProxyTransport
        transport.actionsIgnored += [.closed]

        var states: [RealtimeConnectionState] = []
        var start: NSDate?
        var end: NSDate?

        client.connection.on { stateChange in
            let state = stateChange.current
            let error = stateChange.reason
            XCTAssertNil(error)
            switch state {
            case .connected:
                client.close()
            case .closing:
                start = NSDate()
                states += [state]
            case .closed:
                end = NSDate()
                states += [state]
            case .disconnected:
                states += [state]
            default:
                break
            }
        }

        expect(start).toEventuallyNot(beNil(), timeout: testTimeout)
        expect(end).toEventuallyNot(beNil(), timeout: DispatchTimeInterval.milliseconds(Int(1000.0 * Default.realtimeRequestTimeout())))

        if states.count != 2 {
            fail("Invalid number of connection states. Expected CLOSING and CLOSE states")
            return
        }

        XCTAssertEqual(states[0], RealtimeConnectionState.closing)
        XCTAssertEqual(states[1], RealtimeConnectionState.closed)
    }

    // RTN12c
    func test__048__Connection__close__transitions_to_the_CLOSING_state_and_then_to_the_CLOSED_state_if_the_transport_is_abruptly_closed() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        options.testOptions.transportFactory = TestProxyTransportFactory()
        let client = PubSubClient(options: options)
        client.connect()
        defer {
            client.dispose()
            client.close()
        }

        let transport = client.internal.transport as! TestProxyTransport
        var states: [RealtimeConnectionState] = []

        waitUntil(timeout: testTimeout) { done in
            client.connection.on { stateChange in
                let state = stateChange.current
                let error = stateChange.reason
                XCTAssertNil(error)
                switch state {
                case .connected:
                    states += [state]
                    client.close()
                case .closing:
                    states += [state]
                    transport.simulateIncomingAbruptlyClose()
                case .closed:
                    states += [state]
                    done()
                case .disconnected, .suspended, .failed:
                    states += [state]
                default:
                    break
                }
            }
        }

        if states.count != 3 {
            fail("Invalid number of connection states. Expected CONNECTED, CLOSING and CLOSE states (got \(states.map { $0.rawValue }))")
            return
        }

        XCTAssertEqual(states[0], RealtimeConnectionState.connected)
        XCTAssertEqual(states[1], RealtimeConnectionState.closing)
        XCTAssertEqual(states[2], RealtimeConnectionState.closed)
    }

    // RTN12d
    func test__049__Connection__close__if_DISCONNECTED__aborts_the_retry_and_moves_immediately_to_CLOSED() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.disconnectedRetryTimeout = 1.0
        let client = PubSubClient(options: options)
        defer {
            client.close()
            client.dispose()
        }

        expect(client.connection.state).toEventually(equal(RealtimeConnectionState.connected), timeout: testTimeout)

        client.internal.onDisconnected()
        expect(client.connection.state).toEventually(equal(RealtimeConnectionState.disconnected), timeout: testTimeout)

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)
            client.connection.once { stateChange in
                XCTAssertEqual(stateChange.current, RealtimeConnectionState.closed)
                partialDone()
            }

            client.close()

            delay(options.disconnectedRetryTimeout + 0.5) {
                // Make sure the retry doesn't happen.
                XCTAssertEqual(client.connection.state, RealtimeConnectionState.closed)
                partialDone()
            }
        }
    }

    // RTN12e
    func test__050__Connection__close__if_SUSPENDED__aborts_the_retry_and_moves_immediately_to_CLOSED() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.suspendedRetryTimeout = 1.0
        let client = PubSubClient(options: options)
        defer {
            client.close()
            client.dispose()
        }

        expect(client.connection.state).toEventually(equal(RealtimeConnectionState.connected), timeout: testTimeout)

        client.internal.onSuspended()
        expect(client.connection.state).toEventually(equal(RealtimeConnectionState.suspended), timeout: testTimeout)

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)
            client.connection.once { stateChange in
                XCTAssertEqual(stateChange.current, RealtimeConnectionState.closed)
                partialDone()
            }

            client.close()

            delay(options.suspendedRetryTimeout + 0.5) {
                // Make sure the retry doesn't happen.
                XCTAssertEqual(client.connection.state, RealtimeConnectionState.closed)
                partialDone()
            }
        }
    }

    // RTN13

    // RTN13b
    func test__051__Connection__ping__fails_if_in_the_INITIALIZED__SUSPENDED__CLOSING__CLOSED_or_FAILED_state() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.suspendedRetryTimeout = 0.1
        options.autoConnect = false
        let client = PubSubClient(options: options)
        defer {
            client.close()
            client.dispose()
        }

        var error: ErrorInfo?
        func ping() {
            error = nil
            waitUntil(timeout: testTimeout) { done in
                client.ping { e in
                    error = e
                    done()
                }
            }
        }

        XCTAssertEqual(client.connection.state, RealtimeConnectionState.initialized)
        ping()
        XCTAssertNotNil(error)

        client.connect()
        expect(client.connection.state).toEventually(equal(RealtimeConnectionState.connected), timeout: testTimeout)
        client.internal.onSuspended()

        XCTAssertEqual(client.connection.state, RealtimeConnectionState.suspended)
        ping()
        XCTAssertNotNil(error)

        expect(client.connection.state).toEventually(equal(RealtimeConnectionState.connected), timeout: testTimeout)
        client.close()

        XCTAssertEqual(client.connection.state, RealtimeConnectionState.closing)
        ping()
        XCTAssertNotNil(error)

        expect(client.connection.state).toEventually(equal(RealtimeConnectionState.closed), timeout: testTimeout)
        ping()
        XCTAssertNotNil(error)

        client.internal.onError(AblyTests.newErrorProtocolMessage())

        XCTAssertEqual(client.connection.state, RealtimeConnectionState.failed)
        ping()
        XCTAssertNotNil(error)
    }

    // RTN13a
    func test__052__Connection__ping__should_send_a_ProtocolMessage_with_action_HEARTBEAT_and_expects_a_HEARTBEAT_message_in_response() throws {
        let test = Test()
        let client = AblyTests.newRealtime(try AblyTests.commonAppSetup(for: test)).client
        defer { client.dispose(); client.close() }
        waitUntil(timeout: testTimeout) { done in
            client.ping { error in
                XCTAssertNil(error)
                let transport = client.internal.transport as! TestProxyTransport
                XCTAssertEqual(transport.protocolMessagesSent.filter { $0.action == .heartbeat }.count, 1)
                XCTAssertEqual(transport.protocolMessagesReceived.filter { $0.action == .heartbeat }.count, 1)
                done()
            }
        }
    }

    // RTN13c
    func test__053__Connection__ping__should_fail_if_a_HEARTBEAT_ProtocolMessage_is_not_received_within_the_default_realtime_request_timeout() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let realtimeRequestTimeout = 3.0
        options.testOptions.realtimeRequestTimeout = realtimeRequestTimeout
        let client = AblyTests.newRealtime(options).client
        defer { client.dispose(); client.close() }
        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { _ in
                done()
            }
        }
        guard let transport = client.internal.transport as? TestProxyTransport else {
            fail("TestProxyTransport is not set"); return
        }

        transport.actionsIgnored += [.heartbeat]

        waitUntil(timeout: testTimeout) { done in
            let start = NSDate()
            transport.ignoreSends = true

            client.ping { error in
                guard let error = error else {
                    fail("expected error"); done(); return
                }
                let end = NSDate()
                XCTAssertTrue(error.code == ErrorCode.connectionTimedOut.rawValue)
                expect(end.timeIntervalSince(start as Date)).to(beCloseTo(realtimeRequestTimeout, within: 1.5))
                done()
            }
        }
    }

    // RTN14a
    func test__009__Connection__should_enter_FAILED_state_when_API_key_is_invalid() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.key = String(options.key!.reversed())
        options.autoConnect = false
        let client = PubSubClient(options: options)
        defer {
            client.dispose()
            client.close()
        }

        waitUntil(timeout: testTimeout) { done in
            client.connection.on { stateChange in
                let state = stateChange.current
                let errorInfo = stateChange.reason
                switch state {
                case .failed:
                    XCTAssertNotNil(errorInfo)
                    done()
                default:
                    break
                }
            }
            client.connect()
        }
    }

    // RTN14b

    func test__054__Connection__connection_request_fails__on_DISCONNECTED_after_CONNECTED__should_not_emit_error_with_a_renewable_token() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        options.authCallback = { tokenParams, callback in
            getTestTokenDetails(for: test, key: options.key, capability: tokenParams.capability, ttl: tokenParams.ttl as! TimeInterval?, completion: callback)
        }
        let tokenTtl = 3.0
        options.token = try getTestToken(for: test, key: options.key, ttl: tokenTtl)
        options.testOptions.transportFactory = TestProxyTransportFactory()

        let client = PubSubClient(options: options)
        defer {
            client.dispose()
            client.close()
        }

        waitUntil(timeout: testTimeout) { done in
            // Let the token expire
            client.connection.once(.disconnected) { stateChange in
                guard let reason = stateChange.reason else {
                    fail("Token error is missing"); done(); return
                }
                XCTAssertEqual(reason.code, ErrorCode.tokenExpired.intValue)

                client.connection.on { stateChange in
                    let state = stateChange.current
                    let errorInfo = stateChange.reason
                    switch state {
                    case .connected:
                        XCTAssertNil(errorInfo)
                        // New token
                        XCTAssertNotEqual(client.auth.tokenDetails!.token, options.token)
                        done()
                    case .failed, .suspended:
                        fail("Should not emit error (\(String(describing: errorInfo)))")
                        done()
                    default:
                        break
                    }
                }
            }
            client.connect()
        }
    }

    func test__055__Connection__connection_request_fails__on_token_error_while_CONNECTING__reissues_token_and_reconnects() throws {
        let test = Test()
        var authCallbackCalled = 0

        var tokenTTL = 1.0

        let options = try AblyTests.commonAppSetup(for: test)
        options.authCallback = { _, callback in
            authCallbackCalled += 1
            getTestTokenDetails(for: test, ttl: tokenTTL) { token, err in
                // Let the token expire
                delay(2.0) {
                    callback(token, err)
                }
                // Next time, tokenTTL will be longer so that it doesn't expire right away
                tokenTTL = 60
            }
        }
        options.autoConnect = false

        let realtime = PubSubClient(options: options)
        defer { realtime.close() }

        var hookToken: AspectToken?
        waitUntil(timeout: testTimeout.multiplied(by: 2)) { done in
            let partialDone = AblyTests.splitDone(2, done: done)
            realtime.connection.once(.connected) { stateChange in
                XCTAssertNil(stateChange.reason)
                partialDone()
            }
            hookToken = realtime.internal.testSuite_getArgument(from: NSSelectorFromString("onError:"), at: 0) { arg0 in
                guard let message = arg0 as? ARTProtocolMessage, let error = message.error else {
                    fail("Expecting a protocol message with Token error"); partialDone(); return
                }
                XCTAssertEqual(error.code, ErrorCode.tokenExpired.intValue)
                partialDone()
            }
            realtime.connect()
        }
        hookToken?.remove()

        // First token issue, and then reissue on token error.
        XCTAssertEqual(authCallbackCalled, 2)
    }

    func test__056__Connection__connection_request_fails__should_transition_to_disconnected_when_the_token_renewal_fails() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        options.testOptions.transportFactory = TestProxyTransportFactory()
        let tokenTtl = 3.0
        let tokenDetails = try getTestTokenDetails(for: test, key: options.key, capability: nil, ttl: tokenTtl)
        options.token = tokenDetails.token
        options.authCallback = { _, callback in
            delay(0) {
                callback(tokenDetails, nil) // Return the same expired token again.
            }
        }

        let client = PubSubClient(options: options)
        defer {
            client.dispose()
            client.close()
        }

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)
            client.connection.once(.connected) { stateChange in
                XCTAssertNil(stateChange.reason)
                partialDone()
            }
            client.connection.once(.disconnected) { stateChange in
                guard let reason = stateChange.reason else {
                    fail("Reason is nil"); done(); return
                }
                XCTAssertEqual(reason.code, ErrorCode.tokenExpired.intValue) // Key/token status changed (expire)
                XCTAssertEqual(reason.statusCode, 401)
                partialDone()
            }
            client.connect()
        }
    }

    func test__057__Connection__connection_request_fails__should_transition_to_Failed_state_because_the_token_is_invalid_and_not_renewable() throws {
        let test = Test()
        let options = try AblyTests.clientOptions(for: test)
        options.autoConnect = false
        let tokenTtl = 1.0
        options.token = try getTestToken(for: test, ttl: tokenTtl)
        options.testOptions.transportFactory = TestProxyTransportFactory()

        // Let the token expire
        waitUntil(timeout: testTimeout) { done in
            delay(tokenTtl + AblyTests.tokenExpiryTolerance) {
                done()
            }
        }

        let client = PubSubClient(options: options)
        defer {
            client.dispose()
            client.close()
        }

        var capturedTransport: TestProxyTransport?

        waitUntil(timeout: testTimeout) { done in
            client.connection.on { stateChange in
                let state = stateChange.current
                let errorInfo = stateChange.reason
                switch state {
                case .connected:
                    fail("Should not be connected")
                    done()
                case .failed, .disconnected, .suspended:
                    guard let errorInfo = errorInfo else {
                        fail("ErrorInfo is nil"); done(); return
                    }
                    XCTAssertEqual(errorInfo.code, ErrorCode.tokenExpired.intValue)
                    done()
                default:
                    break
                }
            }
            client.connect()
            capturedTransport = (client.internal.transport as! TestProxyTransport)
        }
        let transport = try XCTUnwrap(capturedTransport, "waitUntil timed out before transport was set")

        let failures = transport.protocolMessagesReceived.filter { $0.action == .error }

        if failures.count != 1 {
            fail("Should have only one connection request fail")
            return
        }

        XCTAssertEqual(failures[0].error!.code, ErrorCode.tokenExpired.intValue)
    }

    // RTN14c
    func test__058__Connection__connection_request_fails__connection_attempt_should_fail_if_not_connected_within_the_default_realtime_request_timeout() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.endpoint = "10.255.255.1" // non-routable IP address
        options.autoConnect = false
        let realtimeRequestTimeout = 0.5
        options.testOptions.realtimeRequestTimeout = realtimeRequestTimeout

        let client = PubSubClient(options: options)
        defer { client.dispose(); client.close() }
        var start, end: NSDate?
        waitUntil(timeout: testTimeout) { done in
            client.connection.on(.disconnected) { stateChange in
                end = NSDate()
                expect(stateChange.reason!.message).to(contain("timed out"))
                XCTAssertTrue(client.connection.errorReason! === stateChange.reason)
                done()
            }
            client.connect()
            start = NSDate()
        }
        if let start = start, let end = end {
            expect(end.timeIntervalSince(start as Date)).to(beCloseTo(realtimeRequestTimeout, within: 1.5))
        } else {
            fail("Start date or end date are empty")
        }
    }

    func testRTN14dAndRTB1(
        test: Test,
        useFallbacks: Bool = false,
        extraTimeNeededToObserveEachRetry: TimeInterval = 0,
        modifyOptions: (ClientOptions) -> Void,
        checkError: (ErrorInfo) -> Void
    ) throws {
        let options = try AblyTests.commonAppSetup(for: test)
        options.disconnectedRetryTimeout = 1.0
        options.autoConnect = false

        let jitterCoefficients = StaticJitterCoefficients()
        let mockJitterCoefficientGenerator = MockJitterCoefficientGenerator(coefficients: jitterCoefficients)
        options.testOptions.jitterCoefficientGenerator = mockJitterCoefficientGenerator

        modifyOptions(options)

        let numberOfRetriesToWaitFor = 5 // arbitrarily chosen, large enough for us to have confidence that a sequence of retries is occurring, with the correct retry delays

        let backoffJitterRetryDelays = Array(
            AblyTests.expectedRetryDelays(
                forTimeout: options.disconnectedRetryTimeout,
                jitterCoefficients: jitterCoefficients
            ).prefix(numberOfRetriesToWaitFor + 1 /* The +1 can be removed after #1782 is fixed; see note below */)
        )

        var expectedRetryDelays = [TimeInterval]()

        if useFallbacks {
            // https://ably-real-time.slack.com/archives/CURL4U2FP/p1742211172312389?thread_ts=1741387920.007779&cid=CURL4U2FP
            /* Owen Pearson:
             * > backoff + jitter is used to determine the time until the client attempts a connection sequence
             * > where a connection sequence is: try primary host -> if primary host doesn't work, try fallbacks a-e
             * > so when a client is disconnected unexpectedly, the client should immediately try the connection sequence,
             * > then if that fails it uses backoff + jitter to calculate when it will attempt another connection
             */
            expectedRetryDelays = Array(repeating: 0.1,
                                        count: backoffJitterRetryDelays.count * 6) // 6 = 1 + 5: primary host + a-e fallbacks
            var j = 0
            for i in 1..<expectedRetryDelays.count {
                if i % 6 == 0 {
                    expectedRetryDelays[i] = backoffJitterRetryDelays[j]
                    j += 1
                }
            }
        } else {
            expectedRetryDelays = backoffJitterRetryDelays
        }

        let timesNeededToObserveRetries = expectedRetryDelays.map { retryDelay in
            extraTimeNeededToObserveEachRetry
            + retryDelay // waiting for retry to occur
            + 0.2 // some extra tolerance, arbitrarily chosen
        }
        let timeNeededToObserveRetries = timesNeededToObserveRetries.prefix(expectedRetryDelays.count).reduce(0, +)

        let connectionStateTtl = timeNeededToObserveRetries + 1.0 // i.e. make sure that we don't become suspended before we've observed as many retries as we wish to

        let previousConnectionStateTtl = Default.connectionStateTtl()
        defer { Default.setConnectionStateTtl(previousConnectionStateTtl) }
        Default.setConnectionStateTtl(connectionStateTtl)

        let client = PubSubClient(options: options)
        defer {
            client.connection.off()
            client.close()
        }

        struct ObservedStateChange {
            var observedAt: Date
            var stateChange: ConnectionStateChange
        }
        let retrySequenceDataGatherer = DataGatherer(description: "Observe emitted state changes") { submit in
            var observedStateChanges: [ObservedStateChange] = []

            client.connection.on { stateChange in
                observedStateChanges.append(.init(observedAt: .init(), stateChange: stateChange))

                if (stateChange.current == .suspended) {
                    submit(observedStateChanges)
                }
            }
        }

        client.connect()

        let observedStateChanges = try retrySequenceDataGatherer.waitForData(timeout: testTimeout.multiplied(by: 3))

        // We expect to get INITIALIZED -> CONNECTING, and then, repeated: CONNECTING -> DISCONNECTED, DISCONNECTED -> CONNECTING, and then finally CONNECTING -> SUSPENDED.

        let expectedNumberOfObservedStateChanges = 2 * (numberOfRetriesToWaitFor + 1)
        // Once #1782 is fixed, this can be changed to an equality check instead — see note below
        XCTAssertGreaterThanOrEqual(observedStateChanges.count, expectedNumberOfObservedStateChanges)
        guard observedStateChanges.count >= expectedNumberOfObservedStateChanges else {
            return
        }

        var firstObservedStateChangeToDisconnected: ObservedStateChange? = nil

        for retryNumber in 1 ... numberOfRetriesToWaitFor {
            let observedStateChangesStartIndexForThisRetry = 1 + 2 * (retryNumber - 1)

            let expectedRetryDelay = expectedRetryDelays[retryNumber - 1]

            let firstObservedStateChange = observedStateChanges[observedStateChangesStartIndexForThisRetry]
            XCTAssertEqual(firstObservedStateChange.stateChange.previous, .connecting)
            XCTAssertEqual(firstObservedStateChange.stateChange.current, .disconnected)
            checkError(firstObservedStateChange.stateChange.reason!)
            XCTAssertEqual(firstObservedStateChange.stateChange.retryIn, expectedRetryDelay)

            if (firstObservedStateChangeToDisconnected == nil) {
                firstObservedStateChangeToDisconnected = firstObservedStateChange
            }

            let secondObservedStateChange = observedStateChanges[observedStateChangesStartIndexForThisRetry + 1]
            XCTAssertEqual(secondObservedStateChange.stateChange.previous, .disconnected)
            XCTAssertEqual(secondObservedStateChange.stateChange.current, .connecting)
        }

        let finalStateChange = observedStateChanges.last!
        XCTAssertEqual(finalStateChange.stateChange.current, .suspended)

        /* The below `expect` _should_ just be:

           expect(end.timeIntervalSince(firstObservedStateChangeToDisconnected!.observedAt)).to(beCloseTo(connectionStateTtl, within: 0.1))

           but we have to account for the fact that, due to bug #1782, the connection will sometimes (in a manner that we can't predict) perform an extra retry before transitioning to SUSPENDED. Once #1782 is fixed, the expectation should be changed to the above.
         */
        let timeTakenByPotentialExcessRetry = timesNeededToObserveRetries[expectedRetryDelays.count - 1]

        let tolerance = 1.0 // arbitrarily chosen, but rather high due to multiple internet checks during the lengthy sequence
        expect(finalStateChange.observedAt.timeIntervalSince(firstObservedStateChangeToDisconnected!.observedAt))
            .to(beGreaterThan(connectionStateTtl - tolerance))
            .to(beLessThan(connectionStateTtl + timeTakenByPotentialExcessRetry + tolerance))
    }

    // RTN14d, RTB1
    func test__059__Connection__connection_request_fails__connection_attempt_fails_for_any_recoverable_reason__for_example_a_timeout() throws {
        let test = Test()

        let realtimeRequestTimeout = 0.1

        try testRTN14dAndRTB1(test: test,
                              extraTimeNeededToObserveEachRetry: realtimeRequestTimeout, // waiting for connect to time out
                              modifyOptions: { options in
            options.testOptions.realtimeRequestTimeout = realtimeRequestTimeout
            options.authCallback = { _, _ in
                // Ignore `completion` closure to force a time out
            }
        }, checkError: { error in
            XCTAssertTrue(error.code == ErrorCode.authConfiguredProviderFailure.rawValue) // timed out
        })
    }

    // RTN14d, RTB1
    func test__059b__Connection__connection_request_fails__connection_attempt_fails_for_any_recoverable_reason__for_example_an_hostUnreachable_transport_error() throws {
        let test = Test()

        try testRTN14dAndRTB1(test: test,
                              useFallbacks: true,
                              modifyOptions: { options in
            let transportFactory = TestProxyTransportFactory()
            transportFactory.fakeNetworkResponse = .hostUnreachable
            options.testOptions.transportFactory = transportFactory
        }, checkError: { error in
            XCTAssertTrue(error.message.contains("host unreachable"))
        })
    }

    // RTN14e
    func test__060__Connection__connection_request_fails__connection_state_has_been_in_the_DISCONNECTED_state_for_more_than_the_default_connectionStateTtl_should_change_the_state_to_SUSPENDED() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.disconnectedRetryTimeout = 0.1
        options.suspendedRetryTimeout = 0.5
        options.autoConnect = false
        options.testOptions.realtimeRequestTimeout = 0.1

        options.authCallback = { _, _ in
            // Force a timeout
        }

        let client = PubSubClient(options: options)
        defer { client.dispose(); client.close() }

        let ttlHookToken = client.overrideConnectionStateTTL(0.3)
        defer { ttlHookToken.remove() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.on(.suspended) { _ in
                expect(client.connection.errorReason!.message).to(contain("timed out"))

                let start = NSDate()
                client.connection.once(.connecting) { _ in
                    let end = NSDate()
                    expect(end.timeIntervalSince(start as Date)).to(beCloseTo(options.suspendedRetryTimeout, within: 0.5))
                    done()
                }
            }
            client.connect()
        }
    }

    // RTN14e - https://github.com/ably/ably-cocoa/issues/913
    func test__061__Connection__connection_request_fails__should_change_the_state_to_SUSPENDED_when_the_connection_state_has_been_in_the_DISCONNECTED_state_for_more_than_the_connectionStateTtl() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.disconnectedRetryTimeout = 0.5
        options.suspendedRetryTimeout = 2.0
        options.autoConnect = false
        let transportFactory = TestProxyTransportFactory()
        options.testOptions.transportFactory = transportFactory

        let jitterCoefficients = StaticJitterCoefficients()
        let mockJitterCoefficientGenerator = MockJitterCoefficientGenerator(coefficients: jitterCoefficients)
        options.testOptions.jitterCoefficientGenerator = mockJitterCoefficientGenerator

        let client = PubSubClient(options: options)
        client.internal.setReachabilityClass(TestReachability.self)
        defer {
            client.simulateRestoreInternetConnection(transportFactory: transportFactory)
            client.dispose()
            client.close()
        }

        let connectionStateTTL = 3.0
        let ttlHookToken = client.overrideConnectionStateTTL(connectionStateTTL)
        defer { ttlHookToken.remove() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { stateChange in
                XCTAssertNil(stateChange.reason)
                done()
            }
            client.connect()
        }

        var events: [RealtimeConnectionState] = []
        client.connection.on { stateChange in
            events.append(stateChange.current)
        }
        client.simulateNoInternetConnection(transportFactory: transportFactory)

        let expectedNumberOfDisconnectedRetries = {
            let expectedRetryDelays = AblyTests.expectedRetryDelays(
                forTimeout: options.disconnectedRetryTimeout,
                jitterCoefficients: jitterCoefficients
            )

            var retryDelaySum = 0.0
            var expectedNumberOfRetries = 0
            for retryDelay in expectedRetryDelays {
                retryDelaySum += retryDelay
                expectedNumberOfRetries += 1
                if (retryDelaySum >= connectionStateTTL) {
                    break
                }
            }

            return expectedNumberOfRetries
        }()

        expect(events).toEventually(equal(
            Array(repeating: [.disconnected, .connecting], count: expectedNumberOfDisconnectedRetries).flatMap { $0 }
            + [
                .suspended,
                .connecting,
                .suspended,
            ]
        ), timeout: testTimeout)

        events.removeAll()
        client.simulateRestoreInternetConnection(after: 7.0, transportFactory: transportFactory)

        expect(events).toEventually(equal([
            .connecting, // 2.0 - 1
            .suspended,
            .connecting, // 4.0 - 2
            .suspended,
            .connecting, // 6.0 - 3
            .suspended,
            .connecting,
            .connected,
        ]), timeout: testTimeout)

        client.connection.off()

        XCTAssertNil(client.connection.errorReason)
        XCTAssertEqual(client.connection.state, .connected)
    }

    func test__062__Connection__connection_request_fails__on_CLOSE_the_connection_should_stop_connection_retries() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        // to avoid waiting for the default 15s before trying a reconnection
        options.disconnectedRetryTimeout = 0.1
        options.suspendedRetryTimeout = 0.5
        options.autoConnect = false
        options.testOptions.realtimeRequestTimeout = 0.1
        let expectedTime: TimeInterval = 1.0

        options.authCallback = { _, _ in
            // Force a timeout
        }

        let previousConnectionStateTtl = Default.connectionStateTtl()
        defer { Default.setConnectionStateTtl(previousConnectionStateTtl) }
        Default.setConnectionStateTtl(expectedTime)

        let client = PubSubClient(options: options)
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.on(.suspended) { _ in
                expect(client.connection.errorReason!.message).to(contain("timed out"))

                let start = NSDate()
                client.connection.once(.connecting) { _ in
                    let end = NSDate()
                    expect(end.timeIntervalSince(start as Date)).to(beCloseTo(options.suspendedRetryTimeout, within: 0.5))
                    done()
                }
            }
            client.connect()
        }

        client.close()

        // Check if the connection gets closed
        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connecting) { _ in
                fail("Should be closing the connection"); done()
            }
            delay(2.0) {
                done()
            }
        }
    }

    // RTN15

    // RTN15a
    func test__064__Connection__connection_failures_once_CONNECTED__if_a_Connection_transport_is_disconnected_unexpectedly_or_if_a_token_expires__then_the_Connection_manager_will_immediately_attempt_to_reconnect() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        let client = PubSubClient(options: options)
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { _ in
                // Simulate interruption shortly
                delay(1.0) {
                    client.internal.onDisconnected()
                }
            }
            client.connection.on(.disconnected) { _ in
                let disconnectedTime = Date()
                client.connection.on(.connected) { _ in
                    let reconnectedTime = Date()
                    // test that reconnection happens within 10 seconds,
                    // so that we are sure it doesn't wait for the default 15s
                    expect(reconnectedTime.timeIntervalSince(disconnectedTime)).to(beCloseTo(0, within: 10))
                    done()
                }
            }
            client.connect()
        }
    }

    // RTN15b

    // RTN15b1
    func test__067__Connection__connection_failures_once_CONNECTED__reconnects_to_the_websocket_endpoint_with_additional_querystring_params__resume_is_the_private_connection_key_from_the_most_recent_CONNECTED_ProtocolMessage_received() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = AblyTests.newRealtime(options).client
        defer { client.dispose(); client.close() }

        expect(client.connection.state).toEventually(equal(RealtimeConnectionState.connected), timeout: testTimeout)
        let expectedConnectionKey = client.connection.key!
        client.internal.onDisconnected()

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { _ in
                let transport = client.internal.transport as! TestProxyTransport
                let query = transport.lastUrl!.query
                expect(query).to(haveParam("resume", withValue: expectedConnectionKey))
                done()
            }
        }
    }

    // RTN15c

    // RTN15c6 (attaching)
    func test__068a__Connection__connection_failures_once_CONNECTED__System_s_response_to_a_resume_request__CONNECTED_ProtocolMessage_with_the_same_connectionId_as_the_current_client__and_no_error() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = AblyTests.newRealtime(options).client
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(test.uniqueChannelName())
        channel.attach()

        XCTAssertTrue(client.waitUntilConnected())
        let expectedConnectionId = client.connection.id

        let transport = client.internal.transport as! TestProxyTransport
        XCTAssertEqual((transport.protocolMessagesSent.filter { $0.action == .attach }).count, 1)

        client.internal.onDisconnected()

        channel.publish(nil, data: "queued message")
        expect(client.internal.queuedMessages).toEventually(haveCount(1), timeout: testTimeout)

        XCTAssertEqual(channel.state, RealtimeChannelState.attaching, "Channel should be still attaching.")
        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { stateChange in
                let transport = client.internal.transport as! TestProxyTransport
                let connectedPM = transport.protocolMessagesReceived.filter { $0.action == .connected }[0]
                XCTAssertEqual(connectedPM.connectionId, expectedConnectionId)
                XCTAssertNil(stateChange.reason)
                XCTAssertEqual((transport.protocolMessagesSent.filter { $0.action == .attach }).count, 1)
                XCTAssertEqual(channel.state, RealtimeChannelState.attaching, "Channel should be attaching now.")
                done()
            }
        }

        expect(client.internal.queuedMessages).toEventually(haveCount(0), timeout: testTimeout) // RTL6c2
    }

    // RTN15c6 (attached, detaching)
    func test__068b__Connection__connection_failures_once_CONNECTED__System_s_response_to_a_resume_request__CONNECTED_ProtocolMessage_with_the_same_connectionId_as_the_current_client__and_no_error() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = AblyTests.newRealtime(options).client
        defer { client.dispose(); client.close() }
        let channel1 = client.channels.get(test.uniqueChannelName())
        let channel2 = client.channels.get(test.uniqueChannelName(prefix: "second_"))
        channel1.attach()
        channel2.attach()

        XCTAssertTrue(client.waitUntilConnected())
        expect(channel1.state).toEventually(equal(RealtimeChannelState.attached), timeout: testTimeout)
        expect(channel2.state).toEventually(equal(RealtimeChannelState.attached), timeout: testTimeout)
        let expectedConnectionId = client.connection.id

        let transport = client.internal.transport as! TestProxyTransport
        XCTAssertEqual((transport.protocolMessagesSent.filter { $0.action == .attach }).count, 2, "Should contain 2 attach messages.") // for channel 1 and 2

        channel2.detach()
        XCTAssertEqual(channel2.state, RealtimeChannelState.detaching)

        client.internal.onDisconnected()

        channel1.publish(nil, data: "queued message")
        expect(client.internal.queuedMessages).toEventually(haveCount(1), timeout: testTimeout)

        XCTAssertEqual(channel1.state, RealtimeChannelState.attached, "Channel should be still attached.")
        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { stateChange in
                let transport = client.internal.transport as! TestProxyTransport
                let connectedPM = transport.protocolMessagesReceived.filter { $0.action == .connected }[0]
                XCTAssertEqual(connectedPM.connectionId, expectedConnectionId)
                XCTAssertNil(stateChange.reason)
                XCTAssertEqual((transport.protocolMessagesSent.filter { $0.action == .attach }).count, 1)
                XCTAssertEqual(channel1.state, RealtimeChannelState.attaching, "Channel should be attaching now.")
                XCTAssertNotEqual(channel2.state, RealtimeChannelState.attaching, "Channel 2 should not be attaching.")
                done()
            }
        }

        expect(client.internal.queuedMessages).toEventually(haveCount(0), timeout: testTimeout) // RTL6c2
    }

    // RTN15c6 (suspended)
    func test__068c__Connection__connection_failures_once_CONNECTED__System_s_response_to_a_resume_request__CONNECTED_ProtocolMessage_with_the_same_connectionId_as_the_current_client__and_no_error() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = AblyTests.newRealtime(options).client
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(test.uniqueChannelName())
        channel.attach()

        XCTAssertTrue(client.waitUntilConnected())
        let expectedConnectionId = client.connection.id

        let transport = client.internal.transport as! TestProxyTransport
        transport.actionsIgnored += [.attached]
        XCTAssertEqual((transport.protocolMessagesSent.filter { $0.action == .attach }).count, 1)

        XCTAssertEqual(channel.state, RealtimeChannelState.attaching)
        expect(channel.state).toEventually(equal(RealtimeChannelState.suspended), timeout: testTimeout)

        client.internal.onDisconnected()

        channel.publish(nil, data: "queued message")
        XCTAssertEqual(client.internal.queuedMessages.count, 0) // should fail message immidiatly if channel is suspended

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { stateChange in
                let transport = client.internal.transport as! TestProxyTransport
                let connectedPM = transport.protocolMessagesReceived.filter { $0.action == .connected }[0]
                XCTAssertEqual(connectedPM.connectionId, expectedConnectionId)
                XCTAssertNil(stateChange.reason)
                XCTAssertEqual((transport.protocolMessagesSent.filter { $0.action == .attach }).count, 1)
                XCTAssertEqual(channel.state, RealtimeChannelState.attaching, "Channel should be attaching now.")
                done()
            }
        }
        expect(channel.state).toEventually(equal(RealtimeChannelState.attached), timeout: testTimeout)
    }

    // RTN15c7
    func test__069__Connection__connection_failures_once_CONNECTED__System_s_response_to_a_resume_request__CONNECTED_ProtocolMessage_with_the_different_connectionId_than_the_current_client_and_an_non_fatal_error() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = AblyTests.newRealtime(options).client
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(test.uniqueChannelName())

        XCTAssertTrue(client.waitUntilConnected())

        let expectedConnectionId = client.connection.id
        client.internalAsync { _internal in
            _internal.onDisconnected()
        }

        channel.attach()
        channel.publish(nil, data: "queued message")
        expect(client.internal.queuedMessages).toEventually(haveCount(1), timeout: testTimeout)

        client.connection.once(.connecting) { _ in
            client.internalSync { _internal in
                let transport = _internal.transport as! TestProxyTransport
                transport.setBeforeIncomingMessageModifier { protocolMessage in
                    if protocolMessage.action == .connected {
                        protocolMessage.error = .create(withCode: 0, message: "Injected error")
                    } else if protocolMessage.action == .attached {
                        protocolMessage.error = .create(withCode: 0, message: "Channel injected error")
                    }
                    protocolMessage.connectionId = "nonsense"
                    return protocolMessage
                }
            }
        }

        expect(client.internal.msgSerial).to(equal(0))

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)
            client.connection.once(.connected) { stateChange in
                XCTAssertEqual(stateChange.reason?.message, "Injected error")
                XCTAssertTrue(client.connection.errorReason === stateChange.reason)
                let transport = client.internal.transport as! TestProxyTransport
                let connectedPM = transport.protocolMessagesReceived.filter { $0.action == .connected }[0]
                XCTAssertNotEqual(connectedPM.connectionId, expectedConnectionId)
                XCTAssertNotEqual(client.connection.id, expectedConnectionId)
                XCTAssertEqual((transport.protocolMessagesSent.filter { $0.action == .attach }).count, 1)
                partialDone()
            }
            channel.once(.attached) { stateChange in
                guard let error = stateChange.reason else {
                    fail("Reason error is nil"); done(); return
                }
                XCTAssertEqual(error.message, "Channel injected error")
                XCTAssertTrue(channel.errorReason === error)
                partialDone()
            }
        }

        expect(client.internal.queuedMessages).toEventually(haveCount(0), timeout: testTimeout)
    }

    // RTN15c4
    func test__071__Connection__connection_failures_once_CONNECTED__System_s_response_to_a_resume_request__ERROR_ProtocolMessage_indicating_a_fatal_error_in_the_connection() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = AblyTests.newRealtime(options).client
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(test.uniqueChannelName())

        expect(client.connection.state).toEventually(equal(RealtimeConnectionState.connected), timeout: testTimeout)

        client.internal.onDisconnected()

        let protocolError = AblyTests.newErrorProtocolMessage()
        client.connection.once(.connecting) { _ in
            // Resuming
            guard let transport = client.internal.transport as? TestProxyTransport else {
                fail("TestProxyTransport is not set"); return
            }
            transport.actionsIgnored += [.connected]
            client.internal.onError(protocolError)
        }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.failed) { stateChange in
                XCTAssertTrue(stateChange.reason === protocolError.error)
                XCTAssertTrue(client.connection.errorReason === protocolError.error)
                done()
            }
        }
        XCTAssertEqual(channel.state, RealtimeChannelState.failed)
        XCTAssertTrue(channel.errorReason === protocolError.error)
    }

    func test__072__Connection__connection_failures_once_CONNECTED__System_s_response_to_a_resume_request__should_resume_the_connection_after_an_auth_renewal() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.tokenDetails = try getTestTokenDetails(for: test, ttl: 5.0)
        let client = AblyTests.newRealtime(options).client
        defer { client.dispose(); client.close() }
        let restOptions = try AblyTests.clientOptions(for: test, key: options.key!)
        restOptions.testOptions.channelNamePrefix = options.testOptions.channelNamePrefix
        let rest = HttpClient(options: restOptions)

        let channelName = test.uniqueChannelName()
        let channel = client.channels.get(channelName)
        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                XCTAssertNil(error)
                done()
            }
        }

        let initialConnectionId = client.connection.id

        guard let _ = client.internal.transport as? TestProxyTransport else {
            fail("TestProxyTransport is not set"); return
        }

        channel.once(.detached) { _ in
            fail("Should not detach channels")
        }
        defer { channel.off() }

        waitUntil(timeout: testTimeout) { done in
            // Wait for token to expire
            client.connection.once(.disconnected) { stateChange in
                guard let error = stateChange.reason else {
                    fail("Error is nil"); done(); return
                }
                XCTAssertEqual(error.code, ErrorCode.tokenExpired.intValue)
                done()
            }
        }

        waitUntil(timeout: testTimeout) { done in
            // Wait for connection resume
            client.connection.once(.connected) { stateChange in
                XCTAssertNil(stateChange.reason)
                done()
            }
        }

        guard let secondTransport = client.internal.transport as? TestProxyTransport else {
            fail("TestProxyTransport is not set"); return
        }

        let connectedMessages = secondTransport.protocolMessagesReceived.filter { $0.action == .connected }
        XCTAssertEqual(connectedMessages.count, 1) // New transport connected
        guard let receivedConnectionId = connectedMessages.first?.connectionId else {
            fail("ConnectionID is nil"); return
        }
        XCTAssertEqual(client.connection.id, receivedConnectionId)
        XCTAssertEqual(client.connection.id, initialConnectionId)

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)
            let expectedMessage = Message(name: "ios", data: "message1")

            channel.subscribe { message in
                XCTAssertEqual(message.name, expectedMessage.name)
                XCTAssertEqual(message.data as? String, expectedMessage.data as? String)
                partialDone()
            }

            rest.channels.get(channelName).publish([expectedMessage]) { error in
                XCTAssertNil(error)
                partialDone()
            }
        }
    }

    // RTN15d
    func test__065__Connection__connection_failures_once_CONNECTED__should_recover_from_disconnection_and_messages_should_be_delivered_once_the_connection_is_resumed() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)

        let client1 = PubSubClient(options: options)
        defer { client1.close() }

        let channelName = test.uniqueChannelName()
        let channel1 = client1.channels.get(channelName)

        let client2 = PubSubClient(options: options)
        defer { client2.close() }
        let channel2 = client2.channels.get(channelName)

        let expectedMessages = ["message X", "message Y"]
        var receivedMessages = [String]()

        waitUntil(timeout: testTimeout) { done in
            channel1.subscribe(attachCallback: { errorInfo in
                XCTAssertNil(errorInfo)
                done()
            }, callback: { message in
                receivedMessages.append(message.data as! String)
            })
        }

        client1.internal.onDisconnected()

        channel2.publish(expectedMessages.map { Message(name: nil, data: $0) }) { errorInfo in
            XCTAssertNil(errorInfo)
        }

        waitUntil(timeout: testTimeout) { done in
            client1.connection.once(.connecting) { _ in
                expect(receivedMessages).to(beEmpty())
                done()
            }
        }

        expect(client1.connection.state).toEventually(equal(RealtimeConnectionState.connected), timeout: testTimeout)
        expect(receivedMessages).toEventually(equal(expectedMessages), timeout: testTimeout)
    }

    // RTN15e

    func test__073__Connection__connection_failures_once_CONNECTED__when_a_connection_is_resumed__the_connection_key_may_change_and_will_be_provided_in_the_first_CONNECTED_ProtocolMessage_connectionDetails() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        options.testOptions.transportFactory = TestProxyTransportFactory()

        let client = PubSubClient(options: options)
        client.connect()
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(test.uniqueChannelName())

        channel.attach()
        expect(channel.state).toEventually(equal(RealtimeChannelState.attached), timeout: testTimeout)

        client.internal.onDisconnected()

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connecting) { _ in
                client.connection.internal.setKey("key_to_be_replaced")
                done()
            }
        }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { _ in
                let transport = client.internal.transport as! TestProxyTransport
                let firstConnectionDetails = transport.protocolMessagesReceived.filter { $0.action == .connected }[0].connectionDetails
                XCTAssertNotNil(firstConnectionDetails!.connectionKey)
                XCTAssertEqual(client.connection.key, firstConnectionDetails!.connectionKey)
                done()
            }
        }
    }

    // RTN19a
    func test__066__Connection__connection_failures_once_CONNECTED__ACK_and_NACK_responses_for_published_messages_can_only_ever_be_received_on_the_transport_connection_on_which_those_messages_were_sent() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = AblyTests.newRealtime(options).client
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(test.uniqueChannelName())

        var resumed = false
        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { _ in
                done()
            }
        }

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)

            guard let transport1 = client.internal.transport as? TestProxyTransport else {
                fail("TestProxyTransport not setup"); done(); return
            }

            var sentPendingMessage: Message?
            channel.publish(nil, data: "message") { _ in
                if resumed {
                    guard let transport2 = client.internal.transport as? TestProxyTransport else {
                        fail("TestProxyTransport not setup"); done(); return
                    }
                    XCTAssertEqual(transport2.protocolMessagesReceived.filter { $0.action == .ack }.count, 1)

                    guard let _ = transport1.protocolMessagesSent.filter({ $0.action == .message }).first?.messages?.first else {
                        fail("Message that has been re-sent isn't available"); done(); return
                    }
                    guard let sentTransportMessage2 = transport2.protocolMessagesSent.filter({ $0.action == .message }).first?.messages?.first else {
                        fail("Message that has been re-sent isn't available"); done(); return
                    }

                    expect(transport1).toNot(beIdenticalTo(transport2))
                    XCTAssertTrue(sentPendingMessage === sentTransportMessage2)

                    partialDone()
                } else {
                    fail("Shouldn't be called")
                }
            }
            AblyTests.queue.async {
                client.internal.onDisconnected()
            }
            client.connection.once(.connected) { _ in
                resumed = true
            }
            client.internal.testSuite_injectIntoMethod(before: Selector(("resendPendingMessagesWithResumed:"))) {
                XCTAssertEqual(client.internal.pendingMessages.count, 1)
                let pm: ARTProtocolMessage? = (client.internal.pendingMessages.firstObject as? ARTPendingMessage)?.msg
                sentPendingMessage = pm?.messages?[0]
            }
            client.internal.testSuite_injectIntoMethod(after: Selector(("resendPendingMessagesWithResumed:"))) {
                partialDone()
            }
        }
    }

    // RTN15g RTN15g1
    func test__074__Connection__connection_failures_once_CONNECTED__when_connection__ttl_plus_idle_interval__period_has_passed_since_last_activity__uses_a_new_connection() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = AblyTests.newRealtime(options).client
        // We want this to be > than the sum of customTtlInterval and customIdleInterval
        client.internal.immediateReconnectionDelay = 5.0 + customTtlInterval + customIdleInterval
        client.connect()
        defer { client.close() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { _ in
                XCTAssertNotNil(client.connection.id)
                let connectionId = client.connection.id!
                client.internal.connectionStateTtl = customTtlInterval
                client.internal.maxIdleInterval = customIdleInterval
                client.connection.once(.disconnected) { _ in
                    let disconnectedAt = Date()
                    XCTAssertEqual(client.internal.connectionStateTtl, customTtlInterval)
                    XCTAssertEqual(client.internal.maxIdleInterval, customIdleInterval)
                    client.connection.once(.connecting) { _ in
                        let reconnectionInterval = Date().timeIntervalSince(disconnectedAt)
                        expect(reconnectionInterval).to(beGreaterThan(client.internal.connectionStateTtl + client.internal.maxIdleInterval))
                        client.connection.once(.connected) { _ in
                            XCTAssertNotEqual(client.connection.id, connectionId)
                            done()
                        }
                    }
                }
                client.internal.onDisconnected()
            }
        }
    }

    // RTN15g3
    func test__075__Connection__connection_failures_once_CONNECTED__when_connection__ttl_plus_idle_interval__period_has_passed_since_last_activity__reattaches_to_the_same_channels_after_a_new_connection_has_been_established() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = AblyTests.newRealtime(options).client
        // We want this to be > than the sum of customTtlInterval and customIdleInterval
        client.internal.immediateReconnectionDelay = 5.0 + customTtlInterval + customIdleInterval
        defer { client.close() }
        let channelName = test.uniqueChannelName()
        let channel = client.channels.get(channelName)

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { _ in
                let connectionId = client.connection.id!
                client.internal.connectionStateTtl = customTtlInterval
                client.internal.maxIdleInterval = customIdleInterval
                channel.attach { error in
                    if let error = error {
                        fail(error.message)
                    }
                    XCTAssertEqual(channel.state, RealtimeChannelState.attached)
                    client.internal.onDisconnected()
                }
                client.connection.once(.disconnected) { _ in
                    client.connection.once(.connecting) { _ in
                        client.connection.once(.connected) { _ in
                            XCTAssertNotEqual(client.connection.id, connectionId)
                            channel.once(.attached) { stateChange in
                                done()
                            }
                        }
                    }
                }
            }
            client.connect()
        }
    }

    // RTN15g2
    func test__076__Connection__connection_failures_once_CONNECTED__when_connection__ttl_plus_idle_interval__period_has_NOT_passed_since_last_activity__uses_the_same_connection() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = AblyTests.newRealtime(options).client
        client.connect()
        defer { client.close() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { _ in
                XCTAssertNotNil(client.connection.id)
                let connectionId = client.connection.id!
                client.connection.once(.disconnected) { _ in
                    let disconnectedAt = Date()
                    client.connection.once(.connecting) { _ in
                        let reconnectionInterval = Date().timeIntervalSince(disconnectedAt)
                        expect(reconnectionInterval).to(beLessThan(client.internal.connectionStateTtl + client.internal.maxIdleInterval))
                        client.connection.once(.connected) { _ in
                            XCTAssertEqual(client.connection.id, connectionId)
                            done()
                        }
                    }
                }
                client.internal.onDisconnected()
            }
        }
    }

    // RTN15h

    func test__077__Connection__connection_failures_once_CONNECTED__DISCONNECTED_message_contains_a_token_error__if_the_token_is_renewable_then_error_should_not_be_emitted() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        options.authCallback = { tokenParams, callback in
            getTestTokenDetails(for: test, key: options.key, capability: tokenParams.capability, ttl: TimeInterval(60 * 60), completion: callback)
        }
        let tokenTtl = 2.0
        options.token = try getTestToken(for: test, key: options.key, ttl: tokenTtl)
        options.testOptions.transportFactory = TestProxyTransportFactory()

        let client = PubSubClient(options: options)
        defer {
            client.dispose()
            client.close()
        }

        client.connect()
        expect(client.connection.state).toEventually(equal(RealtimeConnectionState.connected), timeout: testTimeout)
        let firstTransport = client.internal.transport as? TestProxyTransport

        waitUntil(timeout: testTimeout) { done in
            // Wait for token to expire
            client.connection.once(.disconnected) { stateChange in
                guard let error = stateChange.reason else {
                    fail("Error is nil"); done(); return
                }
                XCTAssertEqual(error.code, ErrorCode.tokenExpired.intValue)
                done()
            }
        }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { stateChange in
                XCTAssertNil(stateChange.reason)
                done()
            }
        }
        XCTAssertNil(client.connection.errorReason)

        // New connection
        XCTAssertNotNil(client.internal.transport)
        expect(client.internal.transport).toNot(beIdenticalTo(firstTransport))

        waitUntil(timeout: testTimeout) { done in
            client.ping { error in
                XCTAssertNil(error)
                XCTAssertEqual((client.internal.transport as! TestProxyTransport).protocolMessagesReceived.filter { $0.action == .connected }.count, 1)
                done()
            }
        }
    }

    // RTN15h1
    func test__078__Connection__connection_failures_once_CONNECTED__DISCONNECTED_message_contains_a_token_error__and_the_library_does_not_have_a_means_to_renew_the_token__the_connection_will_transition_to_the_FAILED_state() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        let key = options.key
        // set the key to nil so that the client can't sign further token requests
        options.key = nil
        let tokenTtl = 3.0
        let tokenDetails = try getTestTokenDetails(for: test, key: key, ttl: tokenTtl)
        options.token = tokenDetails.token
        let client = PubSubClient(options: options)
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.failed) { stateChange in
                XCTAssertEqual(stateChange.previous, RealtimeConnectionState.connected)
                XCTAssertEqual(stateChange.reason?.code, ErrorCode.tokenExpired.intValue)
                done()
            }
            client.connect()
        }
    }

    // A client that can't renew its token disconnects when Ably asks it to reauthenticate (RTN22), and its next connection attempt fails at once.
    // That attempt used to crash: it activated reachability for the transport that the failure had already released.
    func test__078b__Connection__connection_failures_once_CONNECTED__reconnecting_without_a_means_to_renew_the_token_does_not_crash() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        let key = options.key
        // set the key to nil so that the client can't sign further token requests
        options.key = nil
        options.token = try getTestToken(for: test, key: key, ttl: 60.0)
        options.testOptions.transportFactory = TestProxyTransportFactory()
        let client = ARTRealtime(options: options)
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { _ in
                done()
            }
            client.connect()
        }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.disconnected) { _ in
                client.connection.once(.connecting) { _ in
                    done()
                }
            }
            let authMessage = ARTProtocolMessage()
            authMessage.action = .auth
            client.internal.transport?.receive(authMessage)
        }
    }

    // RTN15h2
    func test__079__Connection__connection_failures_once_CONNECTED__DISCONNECTED_message_contains_a_token_error__should_transition_to_disconnected_when_the_token_renewal_fails_and_the_error_should_be_emitted() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        let tokenTtl = 3.0
        let tokenDetails = try getTestTokenDetails(for: test, key: options.key, capability: nil, ttl: tokenTtl)
        options.token = tokenDetails.token
        options.authCallback = { _, callback in
            delay(0.1) {
                callback(tokenDetails, nil) // Return the same expired token again.
            }
        }
        options.testOptions.transportFactory = TestProxyTransportFactory()

        let client = PubSubClient(options: options)
        defer {
            client.dispose()
            client.close()
        }

        waitUntil(timeout: testTimeout) { done in
            // Wait for token to expire
            client.connection.once(.disconnected) { stateChange in
                XCTAssertEqual(stateChange.previous, RealtimeConnectionState.connected)
                guard let error = stateChange.reason else {
                    fail("Error is nil"); done(); return
                }
                XCTAssertEqual(error.code, ErrorCode.tokenExpired.intValue)

                // Renewal will lead to another disconnection
                client.connection.once(.disconnected) { stateChange in
                    guard let error = stateChange.reason else {
                        fail("Error is nil"); done(); return
                    }
                    XCTAssertEqual(error.code, ErrorCode.tokenExpired.intValue)
                    XCTAssertTrue(client.connection.errorReason === error)
                    done()
                }
            }

            client.connect()
        }
    }

    // RTN16

    // RTN16i
    func test__080__Connection__Connection_recovery__connection_state_should_recover_explicitly_with_a_recover_key() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)

        let clientSend = PubSubClient(options: options)
        defer { clientSend.close() }

        let channelName = test.uniqueChannelName()
        let channelSend = clientSend.channels.get(channelName)

        let clientReceive = PubSubClient(options: options)
        defer { clientReceive.close() }
        let channelReceive = clientReceive.channels.get(channelName)

        waitUntil(timeout: testTimeout) { done in
            channelReceive.subscribe(attachCallback: { error in
                XCTAssertNil(error)
                channelSend.publish(nil, data: "message") { error in
                    XCTAssertNil(error)
                }
            }, callback: { message in
                XCTAssertEqual(message.data as? String, "message")
                done()
            })
        }

        options.recover = clientReceive.connection.createRecoveryKey()
        clientReceive.internal.onError(AblyTests.newErrorProtocolMessage())

        waitUntil(timeout: testTimeout) { done in
            channelSend.publish(nil, data: "queue a message") { error in
                XCTAssertNil(error)
                done()
            }
        }

        let clientRecover = PubSubClient(options: options)
        defer { clientRecover.close() }
        let channelRecover = clientRecover.channels.get(channelName)

        waitUntil(timeout: testTimeout) { done in
            channelRecover.subscribe { message in
                XCTAssertEqual(message.data as? String, "queue a message")
                done()
            }
        }
    }

    // RTN16d
    func test__082__Connection__Connection_recovery__when_a_connection_is_successfully_recovered__Connection_id_will_be_identical_to_the_id_of_the_connection_that_was_recovered_and_Connection_key_will_always_be_updated_to_the_ConnectionDetails_connectionKey_provided_in_the_first_CONNECTED_ProtocolMessage() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let clientOriginal = PubSubClient(options: options)
        defer { clientOriginal.close() }

        expect(clientOriginal.connection.state).toEventually(equal(RealtimeConnectionState.connected), timeout: testTimeout)

        let expectedConnectionId = clientOriginal.connection.id

        options.recover = clientOriginal.connection.createRecoveryKey()
        clientOriginal.internal.onError(AblyTests.newErrorProtocolMessage())

        let clientRecover = AblyTests.newRealtime(options).client
        defer { clientRecover.close() }

        waitUntil(timeout: testTimeout) { done in
            clientRecover.connection.once(.connected) { _ in
                let transport = clientRecover.internal.transport as! TestProxyTransport
                let firstConnectionDetails = transport.protocolMessagesReceived.filter { $0.action == .connected }.first!.connectionDetails
                XCTAssertNotNil(firstConnectionDetails!.connectionKey)
                XCTAssertEqual(clientRecover.connection.id, expectedConnectionId)
                XCTAssertEqual(clientRecover.connection.key, firstConnectionDetails!.connectionKey)
                done()
            }
        }
    }

    // RTN16g
    func test__110__Connection__Connection_recovery__connection_recovery_key_is_correctly_constructed_from_defined_parts() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = AblyTests.newRealtime(options).client
        defer { client.dispose(); client.close() }

        let firstChannelName = test.uniqueChannelName()
        let secondChannelName = test.uniqueChannelName()
        let thirdChannelName = test.uniqueChannelName()
        var firstChannelSerial: String?
        var secondChannelSerial: String?
        var thirdChannelSerial: String?

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(5, done: done)
            client.connection.once(.connected) { stateChange in
                let firstChannel = client.channels.get(firstChannelName)
                firstChannel.on(.attached) {_ in
                    firstChannelSerial = firstChannel.internal.channelSerial
                    partialDone()
                }
                let secondChannel = client.channels.get(secondChannelName)
                secondChannel.on(.attached) {_ in
                    secondChannelSerial = secondChannel.internal.channelSerial
                    secondChannel.publish(nil, data: "message") { error in
                        expect(error).to(beNil())
                        partialDone()
                    }
                    partialDone()
                }
                let thirdChannel = client.channels.get(thirdChannelName)
                thirdChannel.on(.attached) {_ in
                    thirdChannelSerial = thirdChannel.internal.channelSerial
                    partialDone()
                }
                firstChannel.attach()
                secondChannel.attach()
                thirdChannel.attach()
                partialDone()
            }
        }

        let thirdChannel = client.channels.get(thirdChannelName)
        thirdChannel.detach()

        guard let recoveryKeyString = client.connection.createRecoveryKey() else {
            fail("recoveryKeyString shouldn't be null")
            return
        }

        let recoveryKey = try! ARTConnectionRecoveryKey.fromJsonString(recoveryKeyString)
        expect(recoveryKey).toNot(beNil())
        expect(recoveryKey.connectionKey).to(equal(client.connection.key))
        expect(recoveryKey.channelSerials.count).to(equal(2))

        XCTAssertNil(recoveryKey.channelSerials.first(where: { $0.key == thirdChannelSerial }))

        recoveryKey.channelSerials.keys.forEach { key in
            let serial = recoveryKey.channelSerials[key]
            expect(serial).toNot(beNil())
            if key == firstChannelName {
                expect(serial).to(equal(firstChannelSerial))
            } else if key == secondChannelName {
                expect(serial).to(equal(secondChannelSerial))
            }
        }
        expect(recoveryKey.msgSerial).to(equal(client.internal.msgSerial))
    }

    // RTN16g1
    func test__111__Connection__Connection_recovery__connection_recovery_key_is_properly_serializing_any_unicode_channel_name() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = AblyTests.newRealtime(options).client
        defer { client.dispose(); client.close() }

        let sanskritChannelName = "channel_खगौघाङचिच्छौजाझाञ्ज्ञोऽटौठीडडण्ढणः।"
        let koreanChannelName = "channel_키스의고유조건은"
        var firstChannelSerial: String?
        var secondChannelSerial: String?

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(4, done: done)
            client.connection.once(.connected) { stateChange in
                let firstChannel = client.channels.get(sanskritChannelName)
                firstChannel.on(.attached) {_ in
                    firstChannelSerial = firstChannel.internal.channelSerial
                    partialDone()
                }
                let secondChannel = client.channels.get(koreanChannelName)
                secondChannel.on(.attached) {_ in
                    secondChannelSerial = secondChannel.internal.channelSerial

                    secondChannel.publish(nil, data: "message") { error in
                        expect(error).to(beNil())
                        partialDone()
                    }
                    partialDone()
                }
                firstChannel.attach()
                secondChannel.attach()
                partialDone()
            }
        }

        guard let recoveryKeyString = client.connection.createRecoveryKey() else {
            fail("recoveryKeyString shouldn't be null")
            return
        }

        let recoveryKey = try! ARTConnectionRecoveryKey.fromJsonString(recoveryKeyString)
        expect(recoveryKey).toNot(beNil())
        expect(recoveryKey.connectionKey).to(equal(client.connection.key))
        expect(recoveryKey.channelSerials.count).to(equal(2))
        recoveryKey.channelSerials.keys.forEach { key in
            let serial = recoveryKey.channelSerials[key]
            expect(serial).toNot(beNil())
            if key == sanskritChannelName{
                expect(serial).to(equal(firstChannelSerial))
            } else if key == koreanChannelName {
                expect(serial).to(equal(secondChannelSerial))
            }
        }
        expect(recoveryKey.msgSerial).to(equal(client.internal.msgSerial))
    }

    // RTN16g2 - closing, closed
    func test__112__Connection__Connection_recovery__connection_recovery_key_is_null_when_connection_is_in_invalid_state() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = AblyTests.newRealtime(options).client
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)
            client.connection.once(.connected) { stateChange in
                expect(client.connection.createRecoveryKey()).notTo(beNil())
                client.internal.close()
            }
            client.connection.once(.closing) { stateChange in
                expect(client.connection.createRecoveryKey()).to(beNil())
                partialDone()
            }
            client.connection.once(.closed) { stateChange in
                expect(client.connection.createRecoveryKey()).to(beNil())
                partialDone()
            }
        }
    }

    // RTN16g2 - suspended
    func test__113__Connection__Connection_recovery__connection_recovery_key_is_null_when_connection_is_in_suspended_state() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = AblyTests.newRealtime(options).client
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { stateChange in
                expect(client.connection.createRecoveryKey()).notTo(beNil())
                client.internal.onSuspended()
            }
            client.connection.once(.suspended) { stateChange in
                expect(client.connection.createRecoveryKey()).to(beNil())
                done()
            }
        }
    }

    // RTN16g2 - failed
    func test__114__Connection__Connection_recovery__connection_recovery_key_is_null_when_connection_is_in_failed_state() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = AblyTests.newRealtime(options).client
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { stateChange in
                expect(client.connection.createRecoveryKey()).notTo(beNil())
                client.internal.onError(ARTProtocolMessage())
            }
            client.connection.once(.failed) { stateChange in
                expect(client.connection.createRecoveryKey()).to(beNil())
                done()
            }
        }
    }

    // RTN16f
    func test__085__Connection__Connection_recovery__should_set_internal_message_serial_to_component_in_recovery_key() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = AblyTests.newRealtime(options).client
        defer { client.dispose(); client.close() }

        var capturedRecoveryKey: ARTConnectionRecoveryKey?

        waitUntil(timeout: testTimeout) { done in
            publishFirstTestMessage(client, channelName: test.uniqueChannelName(), completion: { error in
                XCTAssertNil(error)
                guard let recoveryKeyString = client.connection.createRecoveryKey() else {
                    XCTFail("createRecoveryKey() returned nil")
                    done()
                    return
                }
                capturedRecoveryKey = try? ARTConnectionRecoveryKey.fromJsonString(recoveryKeyString)
                XCTAssertEqual(capturedRecoveryKey?.msgSerial, client.internal.msgSerial)
                options.recover = recoveryKeyString
                done()
            })
        }
        let recoveryKey = try XCTUnwrap(capturedRecoveryKey, "waitUntil timed out before recoveryKey was set")
        let recoverClient = AblyTests.newRealtime(options).client
        expect(recoverClient.internal.msgSerial).to(equal(recoveryKey.msgSerial))
    }

    // RTN16j
    func test__086__Connection__Connection_recovery__library_should_create_channel_with_corresponding_serial_in_given_recovery_key() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)

        let client = AblyTests.newRealtime(options).client
        defer { client.dispose(); client.close() }

        let channelName = test.uniqueChannelName()
        var expectedChannelSerial: String?
        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)
            client.connection.once(.connected) { stateChange in
                let channel = client.channels.get(channelName)
                channel.on(.attached) { _ in
                    expectedChannelSerial = channel.internal.channelSerial
                    partialDone()
                }
                channel.attach()
                partialDone()
            }
        }

        let recoverOptions = options
        recoverOptions.recover = client.connection.createRecoveryKey()

        let recoveredClient = AblyTests.newRealtime(recoverOptions).client
        defer { recoveredClient.dispose(); recoveredClient.close() }
        expect(recoveredClient.connection.state).toEventually(equal(.connected), timeout: testTimeout)

        XCTAssertTrue(recoveredClient.channels.exists(channelName))
        let recoveredChannel = recoveredClient.channels.get(channelName)
        expect(recoveredChannel.internal.channelSerial).to(equal(expectedChannelSerial))
    }

    // RTN16k
    func test__090__Connection__Connection_recovery__library_provides_additional_querystring_when_recover_is_provided() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false

        let client = AblyTests.newRealtime(options).client
        defer { client.dispose(); client.close() }

        func recoverQueryPart(_ query: String) -> String? {
            let parts = query.components(separatedBy: "&")
            let recoverPart = parts.filter({ part in
                part.contains("recover")
            }).first
            return recoverPart
        }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connecting) {_ in
                guard let webSocketTransport = client.internal.transport as? ARTWebSocketTransport else {
                    fail("Transport should be of type ARTWebSocketTransport"); done()
                    return
                }
                expect(webSocketTransport.websocketURL?.query).toNot(beNil())
                let recoverPart = recoverQueryPart(webSocketTransport.websocketURL!.query!)
                expect(recoverPart).to(beNil())
            }
            client.connection.once(.connected) { stateChange in
                done()
            }
            client.connect()
        }

        let recoverOptions = options
        recoverOptions.recover = client.connection.createRecoveryKey()
        recoverOptions.autoConnect = false
        let recoverClient = AblyTests.newRealtime(recoverOptions).client
        defer { recoverClient.dispose(); recoverClient.close() }

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(3, done: done)
            recoverClient.connection.once(.connecting) {_ in
                guard let webSocketTransport = recoverClient.internal.transport as? ARTWebSocketTransport else {
                    fail("Transport should be of type ARTWebSocketTransport"); done()
                    return
                }
                expect(webSocketTransport.websocketURL?.query).toNot(beNil())
                let recoverPart = recoverQueryPart(webSocketTransport.websocketURL!.query!)
                expect(recoverPart).toNot(beNil())
                let recoverValue = recoverPart?
                    .components(separatedBy: "=")[1]
                expect(recoverValue).to(equal(client.connection.key))
                partialDone()
            }
            recoverClient.connection.once(.connected) {_ in
                recoverClient.connection.off()
                recoverClient.internal.onDisconnected()
                partialDone()
                recoverClient.connection.once(.connecting) {_ in
                    guard let webSocketTransport = recoverClient.internal.transport as? ARTWebSocketTransport else {
                        fail("Transport should be of type ARTWebSocketTransport"); done()
                        return
                    }
                    expect(webSocketTransport.websocketURL?.query).toNot(beNil())
                    let recoverPart = recoverQueryPart(webSocketTransport.websocketURL!.query!)
                    expect(recoverPart).to(beNil())
                    partialDone()
                }
            }
            recoverClient.connect()
        }
    }

    // RTN16l for (RTN15c5 + RTN15h1)
    func test__200a__Connection__Connection_recovery__failures_system_response_to_unrecoverable_token_error() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = AblyTests.newRealtime(options).client
        expect(client.internal.connection.state).toEventually(equal(.connected), timeout: testTimeout)

        let recoverOptions = try AblyTests.commonAppSetup(for: test)
        recoverOptions.recover = client.connection.createRecoveryKey()

        let key = recoverOptions.key
        // set the key to nil so that the client can't sign further token requests
        recoverOptions.key = nil
        let tokenDetails = try getTestTokenDetails(for: test, key: key, ttl: 30.0)
        recoverOptions.token = tokenDetails.token

        let recoverClient = AblyTests.newRealtime(recoverOptions).client
        defer { recoverClient.dispose(); recoverClient.close() }

        let transport = recoverClient.internal.transport as! TestProxyTransport
        transport.emulateTokenRevokationBeforeConnected()

        waitUntil(timeout: testTimeout) { done in
            recoverClient.connection.once(.failed) { stateChange in
                XCTAssertEqual(stateChange.previous, RealtimeConnectionState.connecting)
                XCTAssertEqual(recoverClient.connection.errorReason?.code, ErrorCode.tokenRevoked.intValue)
                done()
            }
            recoverClient.connection.once(.connecting) { stateChange in
                XCTFail("Should not attempt to connect")
            }
        }
    }

    // RTN16l for (RTN15c5 + RTN15h2 success)
    func test__200b__Connection__Connection_recovery__failures_system_response_to_unrecoverable_token_error() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = AblyTests.newRealtime(options).client
        expect(client.internal.connection.state).toEventually(equal(.connected), timeout: testTimeout)

        let recoverOptions = try AblyTests.commonAppSetup(for: test)
        recoverOptions.recover = client.connection.createRecoveryKey()

        let tokenDetails = try getTestTokenDetails(for: test, key: recoverOptions.key, ttl: 30.0)
        recoverOptions.token = tokenDetails.token

        let recoverClient = AblyTests.newRealtime(recoverOptions).client
        defer { recoverClient.dispose(); recoverClient.close() }

        let transport = recoverClient.internal.transport as! TestProxyTransport
        transport.emulateTokenRevokationBeforeConnected()

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)
            recoverClient.connection.once(.disconnected) { stateChange in
                XCTAssertEqual(stateChange.previous, RealtimeConnectionState.connecting)
                partialDone()
            }
            recoverClient.connection.once(.connected) { stateChange in
                partialDone()
            }
        }
    }

    // RTN16l for (RTN15c5 + RTN15h2 failure)
    func test__200c__Connection__Connection_recovery__failures_system_response_to_unrecoverable_token_error() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = AblyTests.newRealtime(options).client
        expect(client.internal.connection.state).toEventually(equal(.connected), timeout: testTimeout)

        let recoverOptions = try AblyTests.commonAppSetup(for: test)
        recoverOptions.recover = client.connection.createRecoveryKey()

        let tokenDetails = try getTestTokenDetails(for: test, key: recoverOptions.key, ttl: 30.0)
        recoverOptions.token = tokenDetails.token

        let recoverClient = AblyTests.newRealtime(recoverOptions, onTransportCreated: { transport in
            (transport as! TestProxyTransport).emulateTokenRevokationBeforeConnected()
        }).client
        defer { recoverClient.dispose(); recoverClient.close() }

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)
            recoverClient.connection.once(.disconnected) { stateChange in
                partialDone()
                XCTAssertNil(recoverClient.connection.errorReason)
                recoverClient.connection.once(.disconnected) { stateChange in
                    XCTAssertEqual(recoverClient.connection.errorReason?.code, ErrorCode.tokenRevoked.intValue)
                    partialDone()
                }
            }
            recoverClient.connection.on(.connected) { _ in
                XCTFail("Should not be connected")
            }
        }
    }

    // RTN16l for (RTN15c7)
    func test__201__Connection__Connection_recovery__failures_once_CONNECTED__System_s_response_to_a_resume_request__CONNECTED_ProtocolMessage_with_the_different_connectionId_than_the_current_client_and_an_non_fatal_error() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = AblyTests.newRealtime(options).client
        defer { client.dispose(); client.close() }

        expect(client.connection.state).toEventually(equal(RealtimeConnectionState.connected), timeout: testTimeout)

        let expectedConnectionId = client.connection.id

        let recoverOptions = try AblyTests.commonAppSetup(for: test)
        recoverOptions.recover = client.connection.createRecoveryKey()
        recoverOptions.autoConnect = false
        let recoverClient = AblyTests.newRealtime(recoverOptions).client
        defer { recoverClient.dispose(); recoverClient.close() }

        waitUntil(timeout: testTimeout) { done in

            recoverClient.connection.once(.connecting) { _ in
                let transport = recoverClient.internal.transport as! TestProxyTransport
                transport.setBeforeIncomingMessageModifier { protocolMessage in
                    protocolMessage.connectionId = "nonsense"
                    protocolMessage.error = .create(withCode: 0, message: "Injected error")
                    return protocolMessage
                }
            }

            recoverClient.connection.once(.connected) { stateChange in
                expect(stateChange.reason?.message).to(equal("Injected error"))
                expect(recoverClient.connection.errorReason).to(beIdenticalTo(stateChange.reason))
                let transport = recoverClient.internal.transport as! TestProxyTransport

                let connectedPM = transport.protocolMessagesReceived.filter { $0.action == .connected }[0]
                expect(connectedPM.connectionId).toNot(equal(expectedConnectionId))
                expect(recoverClient.connection.id).toNot(equal(expectedConnectionId))
                done()
            }

            recoverClient.connect()
        }
    }

    // RTN16l (for RTN15c4)
    func test__202__Connection__Connection_recovery__failures_with_any_other_fatal_error_in_the_connection() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = AblyTests.newRealtime(options).client
        expect(client.internal.connection.state).toEventually(equal(.connected), timeout: testTimeout)

        let recoverOptions = try AblyTests.commonAppSetup(for: test)
        recoverOptions.recover = client.connection.createRecoveryKey()
        recoverOptions.autoConnect = false

        let tokenDetails = try getTestTokenDetails(for: test, key: recoverOptions.key, ttl: 30.0)
        recoverOptions.token = tokenDetails.token

        let recoverClient = AblyTests.newRealtime(recoverOptions).client
        defer { recoverClient.dispose(); recoverClient.close() }

        waitUntil(timeout: testTimeout) { done in
            recoverClient.connection.once(.connecting) { _ in
                let transport = recoverClient.internal.transport as! TestProxyTransport
                transport.setBeforeIncomingMessageModifier { protocolMessage in
                    if protocolMessage.action == .connected {
                        protocolMessage.action = .error
                        protocolMessage.error = .create(withCode: ErrorCode.rateLimitExceededFatal.intValue, status: 403, message: "Fatal error")
                    }
                    return protocolMessage
                }
            }
            recoverClient.connection.on(.failed) { _ in
                XCTAssertEqual(recoverClient.connection.errorReason?.code, ErrorCode.rateLimitExceededFatal.intValue)
                done()
            }
            recoverClient.connection.on(.connected) { _ in
                XCTFail("Should not be connected")
            }
            recoverClient.connection.on(.disconnected) { _ in
                XCTFail("Should not be disconnected")
            }
            recoverClient.connect()
        }
    }

    // RTN17

    // RTN17g, REC2c2
    func test__086a__Connection__Host_Fallback__failing_connections_with_custom_endpoint_should_result_in_an_error_immediately() {
        let test = Test()
        let options = ClientOptions(key: "xxxx:xxxx")
        options.endpoint = "\(UUID()).com" // a hostname endpoint has no fallback hosts
        XCTAssertNil(options.fallbackHosts)
        options.autoConnect = false
        options.queueMessages = false

        let testEnvironment = AblyTests.newRealtime(options)
        let client = testEnvironment.client
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(test.uniqueChannelName())

        testEnvironment.transportFactory.fakeNetworkResponse = .hostUnreachable

        var urlConnections = [URL]()
        testEnvironment.transportFactory.networkConnectEvent = { transport, url in
            if client.internal.transport !== transport {
                return
            }
            urlConnections.append(url)
        }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.disconnected) { stateChange in
                XCTAssertEqual(stateChange.previous, RealtimeConnectionState.connecting)
                XCTAssertEqual(stateChange.current, RealtimeConnectionState.disconnected)
                guard let reason = stateChange.reason else {
                    fail("Reason is empty"); done(); return
                }
                expect(reason.message).to(contain("host unreachable"))
                done()
            }
            client.connect()
        }

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "message") { error in
                XCTAssertEqual(error?.code, 2)
                expect(error?.message).to(contain("host unreachable"))
                expect(error?.reason).to(contain(".FakeNetworkResponse"))
                done()
            }
        }

        XCTAssertEqual(urlConnections.count, 1)
    }

    // RTN17b1 (port)
    func test__086b__Connection__Host_Fallback__failing_connections_with_custom_port_should_result_in_an_error_immediately() {
        let test = Test()
        let options = ClientOptions(key: "xxxx:xxxx")
        options.port = 12345
        XCTAssertNil(options.fallbackHosts)
        options.autoConnect = false
        options.queueMessages = false

        let testEnvironment = AblyTests.newRealtime(options)
        let client = testEnvironment.client
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(test.uniqueChannelName())

        testEnvironment.transportFactory.fakeNetworkResponse = .hostUnreachable

        var urlConnections = [URL]()
        testEnvironment.transportFactory.networkConnectEvent = { transport, url in
            if client.internal.transport !== transport {
                return
            }
            urlConnections.append(url)
        }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.disconnected) { stateChange in
                XCTAssertEqual(stateChange.previous, RealtimeConnectionState.connecting)
                XCTAssertEqual(stateChange.current, RealtimeConnectionState.disconnected)
                guard let reason = stateChange.reason else {
                    fail("Reason is empty"); done(); return
                }
                expect(reason.message).to(contain("host unreachable"))
                done()
            }
            client.connect()
        }

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "message") { error in
                XCTAssertEqual(error?.code, 2)
                expect(error?.message).to(contain("host unreachable"))
                expect(error?.reason).to(contain(".FakeNetworkResponse"))
                done()
            }
        }

        XCTAssertEqual(urlConnections.count, 1)
    }

    // RTN17b1 (tlsPort)
    func test__086c__Connection__Host_Fallback__failing_connections_with_custom_tlsPort_should_result_in_an_error_immediately() {
        let test = Test()
        let options = ClientOptions(key: "xxxx:xxxx")
        options.tlsPort = 12345
        XCTAssertNil(options.fallbackHosts)
        options.autoConnect = false
        options.queueMessages = false

        let testEnvironment = AblyTests.newRealtime(options)
        let client = testEnvironment.client
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(test.uniqueChannelName())

        testEnvironment.transportFactory.fakeNetworkResponse = .hostUnreachable

        var urlConnections = [URL]()
        testEnvironment.transportFactory.networkConnectEvent = { transport, url in
            if client.internal.transport !== transport {
                return
            }
            urlConnections.append(url)
        }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.disconnected) { stateChange in
                XCTAssertEqual(stateChange.previous, RealtimeConnectionState.connecting)
                XCTAssertEqual(stateChange.current, RealtimeConnectionState.disconnected)
                guard let reason = stateChange.reason else {
                    fail("Reason is empty"); done(); return
                }
                expect(reason.message).to(contain("host unreachable"))
                done()
            }
            client.connect()
        }

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "message") { error in
                XCTAssertEqual(error?.code, 2)
                expect(error?.message).to(contain("host unreachable"))
                expect(error?.reason).to(contain(".FakeNetworkResponse"))
                done()
            }
        }

        XCTAssertEqual(urlConnections.count, 1)
    }

    // RTN17g, REC2c2
    func test__087__Connection__Host_Fallback__failing_connections_with_custom_endpoint_should_result_in_time_outs() {
        let test = Test()
        let options = ClientOptions(key: "xxxx:xxxx")
        options.endpoint = "\(UUID()).com" // a hostname endpoint has no fallback hosts
        options.testOptions.realtimeRequestTimeout = 1.0
        XCTAssertNil(options.fallbackHosts)
        options.autoConnect = false

        let testEnvironment = AblyTests.newRealtime(options)
        let client = testEnvironment.client
        defer { client.dispose(); client.close() }
        client.channels.get(test.uniqueChannelName())

        testEnvironment.transportFactory.fakeNetworkResponse = .hostUnreachable

        var urlConnections = [URL]()
        testEnvironment.transportFactory.networkConnectEvent = { transport, url in
            if client.internal.transport !== transport {
                return
            }
            urlConnections.append(url)
        }

        waitUntil(timeout: testTimeout) { done in
            client.connection.on(.disconnected) { stateChange in
                XCTAssertEqual(stateChange.previous, RealtimeConnectionState.connecting)
                XCTAssertEqual(stateChange.current, RealtimeConnectionState.disconnected)
                guard let reason = stateChange.reason else {
                    fail("Reason is empty"); done(); return
                }
                expect(reason.message).to(contain("host unreachable"))
                done()
            }
            client.connect()
        }

        XCTAssertEqual(urlConnections.count, 1)
    }

    // REC2a2, RTN17h
    func test__089__Connection__Host_Fallback__applies_when_an_array_of_ClientOptions_fallbackHosts_is_provided() {
        let test = Test()
        let options = ClientOptions(key: "xxxx:xxxx")
        options.autoConnect = false
        options.disconnectedRetryTimeout = 1.0
        options.fallbackHosts = ["f.ably-realtime.com", "g.ably-realtime.com", "h.ably-realtime.com", "i.ably-realtime.com", "j.ably-realtime.com"]
        options.testOptions.realtimeRequestTimeout = 1.0
        let transportFactory = TestProxyTransportFactory()
        options.testOptions.transportFactory = transportFactory
        let client = PubSubClient(options: options)
        defer { client.dispose(); client.close() }
        client.channels.get(test.uniqueChannelName())

        transportFactory.fakeNetworkResponse = .hostUnreachable

        var urlConnections = [URL]()
        transportFactory.networkConnectEvent = { transport, url in
            if client.internal.transport !== transport {
                return
            }
            urlConnections.append(url)
        }

        let allHostsCount = options.fallbackHosts!.count + 1 // + default host

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(allHostsCount, done: done)
            // wss://main.[a-e].fallback.ably-realtime.com: when a timeout occurs
            client.connection.on(.disconnected) { _ in
                partialDone()
            }
            client.connect()
        }

        XCTAssertTrue(urlConnections.count == allHostsCount)
        XCTAssertTrue(NSRegularExpression.match(urlConnections.at(0)?.absoluteString, pattern: "//main.realtime.ably.net"))
        for connection in urlConnections[1..<allHostsCount] {
            XCTAssertTrue(NSRegularExpression.match(connection.absoluteString, pattern: "//[f-j].ably-realtime.com"))
        }
    }

    // RTN17f

    func test__097__Connection__Host_Fallback__should_use_an_alternative_host_when___hostUnreachable() {
        let test = Test()
        testUsesAlternativeHostOnResponse(.hostUnreachable, channelName: test.uniqueChannelName())
    }

    func test__098__Connection__Host_Fallback__should_use_an_alternative_host_when___requestTimeout() {
        let test = Test()
        testUsesAlternativeHostOnResponse(.requestTimeout(timeout: 0.1), channelName: test.uniqueChannelName())
    }

    func test__099__Connection__Host_Fallback__should_use_an_alternative_host_when___hostInternalError_code__501() {
        let test = Test()
        testUsesAlternativeHostOnResponse(.hostInternalError(code: 501), channelName: test.uniqueChannelName())
    }

    func test__100__Connection__Host_Fallback__should_move_to_disconnected_when_there_s_no_internet__with_NSPOSIXErrorDomain_with_code_57() throws {
        let test = Test()
        try testMovesToDisconnectedWithNetworkingError(NSError(domain: "NSPOSIXErrorDomain", code: 57, userInfo: [NSLocalizedDescriptionKey: "shouldn't matter"]), for: test)
    }

    func test__101__Connection__Host_Fallback__should_move_to_disconnected_when_there_s_no_internet__with_NSPOSIXErrorDomain_with_code_50() throws {
        let test = Test()
        try testMovesToDisconnectedWithNetworkingError(NSError(domain: "NSPOSIXErrorDomain", code: 50, userInfo: [NSLocalizedDescriptionKey: "shouldn't matter"]), for: test)
    }

    func test__102__Connection__Host_Fallback__should_move_to_disconnected_when_there_s_no_internet__with_any_kCFErrorDomainCFNetwork() throws {
        let test = Test()
        try testMovesToDisconnectedWithNetworkingError(NSError(domain: "kCFErrorDomainCFNetwork", code: 1337, userInfo: [NSLocalizedDescriptionKey: "shouldn't matter"]), for: test)
    }

    func test__090__Connection__Host_Fallback__should_not_use_an_alternative_host_when_the_client_receives_a_bad_request() throws {
        let options = ClientOptions(key: "xxxx:xxxx")
        options.autoConnect = false
        options.disconnectedRetryTimeout = 1.0 // so that the test doesn't have to wait a long time to observe a retry
        options.testOptions.realtimeRequestTimeout = 1.0
        let transportFactory = TestProxyTransportFactory()
        options.testOptions.transportFactory = transportFactory
        let client = PubSubClient(options: options)

        transportFactory.fakeNetworkResponse = .host400BadRequest

        let dataGatherer = DataGatherer(description: "Observe emitted state changes and transport connection attempts") { submit in
            var stateChanges: [ConnectionStateChange] = []
            var urlConnections = [URL]()

            client.connection.on { stateChange in
                stateChanges.append(stateChange)
                if (stateChanges.count == 3) {
                    submit((stateChanges: stateChanges, urlConnections: urlConnections))
                }
            }

            transportFactory.networkConnectEvent = { transport, url in
                if client.internal.transport !== transport {
                    return
                }
                urlConnections.append(url)
            }
        }

        client.connect()
        defer { client.dispose(); client.close() }

        let data = try dataGatherer.waitForData(timeout: testTimeout)

        // We expect the first connection attempt to fail due to the .fakeNetworkResponse configured above. This error does not meet the criteria for trying a fallback host, and so should not provoke the use of a fallback host. Hence the connection should transition to DISCONNECTED, and then subsequently retry, transitioning back to CONNECTING. We should see that there were two connection attempts, both to the primary host.

        XCTAssertEqual(data.stateChanges.map(\.current), [.connecting, .disconnected, .connecting])
        XCTAssertEqual(data.urlConnections.count, 2)
        XCTAssertTrue(data.urlConnections.allSatisfy { url in NSRegularExpression.match(url.absoluteString, pattern: "//main.realtime.ably.net") })
    }

    // RTN17i
    private func _test__091__Connection__Host_Fallback__every_connection_is_first_attempted_to_the_primary_host(endpoint: String?, test: Test) {
        let options = ClientOptions(key: "xxxx:xxxx")
        options.endpoint = endpoint
        options.autoConnect = false
        options.disconnectedRetryTimeout = 1.0
        options.testOptions.realtimeRequestTimeout = 1.0
        let transportFactory = TestProxyTransportFactory()
        options.testOptions.transportFactory = transportFactory
        let client = PubSubClient(options: options)
        defer { client.dispose(); client.close() }
        client.channels.get(test.uniqueChannelName())

        transportFactory.fakeNetworkResponse = .hostUnreachable

        var urlConnections = [URL]()
        transportFactory.networkConnectEvent = { transport, url in
            if client.internal.transport !== transport {
                return
            }
            urlConnections.append(url)
            transportFactory.fakeNetworkResponse = nil
        }

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)
            // default host with the fake response or wss://main.[a-e].fallback.ably-realtime.com: when a timeout occurs
            client.connection.on(.disconnected) { _ in
                partialDone()
            }
            // wss://main.[a-e].fallback.ably-realtime.com: when a 401 occurs because of the `xxxx:xxxx` key
            client.connection.on(.failed) { stateChange in
                guard let error = stateChange.reason else {
                    fail("Error is nil"); done(); return
                }
                // This is because, at time of writing, the production environment is handling connections using both frontend (which returns invalidCredential) and frontdoor (which returns invalidCredentials). So we need to handle both cases at least for now (unlike other tests, which use sandbox which is 100% using frontdoor).
                XCTAssertTrue(error.code == ErrorCode.invalidCredential.rawValue || error.code == ErrorCode.invalidCredentials.rawValue)
                partialDone()
            }
            client.connect()
        }

        XCTAssertTrue(urlConnections.count >= 2) // amount depends on how soon fallback receives `.failed` above, it's often `.disconnected` instead
        XCTAssertEqual(urlConnections.at(0)?.host, options.primaryDomain)
        XCTAssertTrue(options.endpointFallbackHosts.contains(urlConnections.at(1)?.host ?? ""))
    }

    func test__091__Connection__Host_Fallback__every_connection_is_first_attempted_to_the_primary_host_default_endpoint() {
        let test = Test()
        _test__091__Connection__Host_Fallback__every_connection_is_first_attempted_to_the_primary_host(endpoint: nil, test: test)
    }

    func test__091__Connection__Host_Fallback__every_connection_is_first_attempted_to_the_primary_host_nonprod_endpoint() {
        let test = Test()
        _test__091__Connection__Host_Fallback__every_connection_is_first_attempted_to_the_primary_host(endpoint: getEndpoint(), test: test)
    }

    // RTN17j
    func _test__092__Connection__Host_Fallback__should_retry_hosts_in_random_order_after_checkin_if_an_internet_connection_is_available(endpoint: String?, test: Test) {
        let options = ClientOptions(key: "xxxx:xxxx")
        options.autoConnect = false
        options.disconnectedRetryTimeout = 1.0
        options.endpoint = endpoint
        options.testOptions.realtimeRequestTimeout = 5.0
        options.testOptions.shuffleArray = shuffleArrayInExpectedHostOrder
        let transportFactory = TestProxyTransportFactory()
        options.testOptions.transportFactory = transportFactory
        let client = PubSubClient(options: options)
        defer { client.dispose(); client.close() }
        client.channels.get(test.uniqueChannelName())

        let testHttpExecutor = TestProxyHTTPExecutor(logger: .init(clientOptions: options))
        client.internal.rest.httpExecutor = testHttpExecutor

        transportFactory.fakeNetworkResponse = .hostUnreachable

        let extractHostname = { (url: URL) -> String? in
            url.host.flatMap { options.endpointFallbackHosts.contains($0) ? $0 : nil }
        }

        var urls = [URL]()
        let expectedFallbackHosts = Array(expectedHostOrder.map { options.endpointFallbackHosts[$0] })

        transportFactory.networkConnectEvent = { transport, url in
            if client.internal.transport !== transport {
                return
            }
            DispatchQueue.main.async {
                urls.append(url)
            }
        }

        testHttpExecutor.setListenerAfterRequest { request in
            urls.append(request.url!)
        }

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(expectedFallbackHosts.count + 1, done: done)
            // wss://main.[a-e].fallback.ably-realtime.com: when a timeout occurs
            client.connection.on(.disconnected) { _ in
                partialDone()
            }
            client.connect()
        }

        var resultFallbackHosts = [String]()
        var gotInternetIsUpCheck = false
        for url in urls {
            if NSRegularExpression.match(url.absoluteString, pattern: "//internet-up.ably-realtime.com/is-the-internet-up.txt") {
                gotInternetIsUpCheck = true
            } else if let fallbackHost = extractHostname(url) {
                if Optional(fallbackHost) == resultFallbackHosts.last {
                    continue
                }
                // Host changed; should've had an internet check before.
                XCTAssertTrue(gotInternetIsUpCheck)
                gotInternetIsUpCheck = false
                resultFallbackHosts.append(fallbackHost)
            }
        }

        XCTAssertEqual(resultFallbackHosts, expectedFallbackHosts)
    }

    func test__092__Connection__Host_Fallback__should_retry_hosts_in_random_order_after_checkin_if_an_internet_connection_is_available_default_endpoint() {
        let test = Test()
        _test__092__Connection__Host_Fallback__should_retry_hosts_in_random_order_after_checkin_if_an_internet_connection_is_available(endpoint: nil, test: test)
    }

    func test__092__Connection__Host_Fallback__should_retry_hosts_in_random_order_after_checkin_if_an_internet_connection_is_available_nonprod_endpoint() {
        let test = Test()
        _test__092__Connection__Host_Fallback__should_retry_hosts_in_random_order_after_checkin_if_an_internet_connection_is_available(endpoint: getEndpoint(), test: test)
    }

    // RTN17j
    func test__093__Connection__Host_Fallback__doesn_t_try_fallback_host_if_Internet_connection_check_fails() {
        let test = Test()
        let options = ClientOptions(key: "xxxx:xxxx")
        options.autoConnect = false
        options.testOptions.realtimeRequestTimeout = 1.0
        let transportFactory = TestProxyTransportFactory()
        options.testOptions.transportFactory = transportFactory
        let client = PubSubClient(options: options)
        defer { client.dispose(); client.close() }
        client.channels.get(test.uniqueChannelName())

        let internalLog = InternalLog(clientOptions: options)
        let mockHTTP = MockHTTP(logger: internalLog)
        let testHttpExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: internalLog)
        client.internal.rest.httpExecutor = testHttpExecutor

        transportFactory.fakeNetworkResponse = .hostUnreachable

        let extractHostname = { (url: URL) in
            NSRegularExpression.extract(url.absoluteString, pattern: "main.[a-e].fallback.ably-realtime.com")
        }

        transportFactory.networkConnectEvent = { transport, url in
            if client.internal.transport !== transport {
                return
            }
            if extractHostname(url) != nil {
                fail("shouldn't try fallback host after failed connectivity check")
            }
        }

        mockHTTP.setNetworkState(network: .hostInternalError(code: 500), forHost: "internet-up.ably-realtime.com")

        waitUntil(timeout: testTimeout) { done in
            // wss://main.[a-e].fallback.ably-realtime.com: when a timeout occurs
            client.connection.once(.disconnected) { _ in
                done()
            }
            // wss://main.[a-e].fallback.ably-realtime.com: when a 401 occurs because of the `xxxx:xxxx` key
            client.connection.once(.failed) { _ in
                done()
            }
            client.connect()
        }
    }

    private func checkInternetIsUp(options: ClientOptions, responseBody: String) -> (isUp: Bool, requestedURL: URL?) {
        options.autoConnect = false
        let client = PubSubClient(options: options)
        defer { client.dispose(); client.close() }

        let internalLog = InternalLog(clientOptions: options)
        let mockHTTP = MockHTTP(logger: internalLog)
        mockHTTP.setSuccessResponse(data: responseBody.data(using: .utf8), contentType: "text/plain")
        let testHttpExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: internalLog)
        client.internal.rest.httpExecutor = testHttpExecutor

        var isUp = false
        waitUntil(timeout: testTimeout) { done in
            client.internal.rest.internetIsUp { result in
                isUp = result
                done()
            }
        }
        return (isUp, testHttpExecutor.requests.first?.url)
    }

    // REC3a
    func test__093b__Connection__Host_Fallback__connectivity_check_requests_the_default_URL() {
        let result = checkInternetIsUp(options: ClientOptions(key: "xxxx:xxxx"), responseBody: "yes\n")

        XCTAssertTrue(result.isUp)
        XCTAssertEqual(result.requestedURL, URL(string: "https://internet-up.ably-realtime.com/is-the-internet-up.txt"))
    }

    // REC3b, RTN17j
    func test__093c__Connection__Host_Fallback__connectivity_check_requests_ClientOptions_connectivityCheckUrl() {
        let options = ClientOptions(key: "xxxx:xxxx")
        let customURL = URL(string: "https://connectivity.example.test/check")!
        options.connectivityCheckUrl = customURL

        // A body without a trailing newline still counts as "yes".
        let result = checkInternetIsUp(options: options, responseBody: "yes")

        XCTAssertTrue(result.isUp)
        XCTAssertEqual(result.requestedURL, customURL)
    }

    // RTN17j
    func test__093d__Connection__Host_Fallback__connectivity_check_fails_unless_the_body_is_yes() {
        let options = ClientOptions(key: "xxxx:xxxx")
        options.connectivityCheckUrl = URL(string: "https://connectivity.example.test/check")!

        let result = checkInternetIsUp(options: options, responseBody: "no")

        XCTAssertFalse(result.isUp)
    }

    func test__094__Connection__Host_Fallback__should_retry_custom_fallback_hosts_in_random_order_after_checkin_if_an_internet_connection_is_available() {
        let test = Test()
        let hostPrefixes = Array("fghij")
        let expectedFallbackHosts = Array(expectedHostOrder.map { "\(hostPrefixes[$0]).ably-realtime.com" })

        let options = ClientOptions(key: "xxxx:xxxx")
        options.autoConnect = false
        options.disconnectedRetryTimeout = 1.0
        options.fallbackHosts = expectedFallbackHosts.sorted() // will be picked "randomly" as of expectedHostOrder
        options.testOptions.realtimeRequestTimeout = 5.0
        options.testOptions.shuffleArray = shuffleArrayInExpectedHostOrder
        let transportFactory = TestProxyTransportFactory()
        options.testOptions.transportFactory = transportFactory
        let client = PubSubClient(options: options)
        defer { client.dispose(); client.close() }
        client.channels.get(test.uniqueChannelName())

        let testHttpExecutor = TestProxyHTTPExecutor(logger: .init(clientOptions: options))
        client.internal.rest.httpExecutor = testHttpExecutor

        transportFactory.fakeNetworkResponse = .hostUnreachable

        let extractHostname = { (url: URL) in
            NSRegularExpression.extract(url.absoluteString, pattern: "[\(hostPrefixes.first!)-\(hostPrefixes.last!)].ably-realtime.com")
        }

        var urls = [URL]()

        transportFactory.networkConnectEvent = { transport, url in
            if client.internal.transport !== transport {
                return
            }
            DispatchQueue.main.async {
                urls.append(url)
            }
        }

        testHttpExecutor.setListenerAfterRequest { request in
            urls.append(request.url!)
        }

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(expectedFallbackHosts.count + 1, done: done)
            // wss://main.[a-e].fallback.ably-realtime.com: when a timeout occurs
            client.connection.on(.disconnected) { _ in
                partialDone()
            }
            client.connect()
        }

        var resultFallbackHosts = [String]()
        var gotInternetIsUpCheck = false
        for url in urls {
            if NSRegularExpression.match(url.absoluteString, pattern: "//internet-up.ably-realtime.com/is-the-internet-up.txt") {
                gotInternetIsUpCheck = true
            } else if let fallbackHost = extractHostname(url) {
                if Optional(fallbackHost) == resultFallbackHosts.last {
                    continue
                }
                // Host changed; should've had an internet check before.
                XCTAssertTrue(gotInternetIsUpCheck)
                gotInternetIsUpCheck = false
                resultFallbackHosts.append(fallbackHost)
            }
        }

        XCTAssertEqual(resultFallbackHosts, expectedFallbackHosts)
    }

    // TO3k6, RTN17g, RTN14d
    func test__095__Connection__Host_Fallback__won_t_use_fallback_hosts_feature_if_an_empty_array_is_provided() {
        let options = ClientOptions(key: "xxxx:xxxx")
        options.autoConnect = false
        options.fallbackHosts = []
        let transportFactory = TestProxyTransportFactory()
        options.testOptions.transportFactory = transportFactory
        let client = PubSubClient(options: options)
        defer { client.dispose(); client.close() }

        let testHttpExecutor = TestProxyHTTPExecutor(logger: .init(clientOptions: options))
        client.internal.rest.httpExecutor = testHttpExecutor

        transportFactory.fakeNetworkResponse = .hostUnreachable

        var urlConnections = [URL]()
        transportFactory.networkConnectEvent = { transport, url in
            if client.internal.transport !== transport {
                return
            }
            urlConnections.append(url)
        }

        // An empty array turns fallbacks off, so the failed attempt is retried later instead of failing the connection.
        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.failed) { stateChange in
                fail("Connection should not fail: \(String(describing: stateChange.reason))")
                done()
            }
            client.connection.once(.disconnected) { _ in
                done()
            }
            client.connect()
        }

        XCTAssertEqual(client.connection.state, .disconnected)
        XCTAssertEqual(urlConnections.map(\.host), [options.primaryDomain])
        XCTAssertFalse(testHttpExecutor.requests.contains { $0.url?.host == "internet-up.ably-realtime.com" })
    }

    // RTN17e
    func test__096__Connection__Host_Fallback__client_is_connected_to_a_fallback_host_endpoint_should_do_HTTP_requests_to_the_same_data_centre() {
        let options = ClientOptions(key: "xxxx:xxxx")
        options.autoConnect = false
        let transportFactory = TestProxyTransportFactory()
        options.testOptions.transportFactory = transportFactory
        let client = PubSubClient(options: options)

        let testHttpExecutor = TestProxyHTTPExecutor(logger: .init(clientOptions: options))
        client.internal.rest.httpExecutor = testHttpExecutor

        transportFactory.fakeNetworkResponse = .hostUnreachable

        var urlConnections = [URL]()
        transportFactory.networkConnectEvent = { transport, url in
            if client.internal.transport !== transport {
                return
            }
            urlConnections.append(url)
            if urlConnections.count == 2 {
                transportFactory.fakeNetworkResponse = nil
                (client.internal.transport as! TestProxyTransport).simulateTransportSuccess()
            }
        }

        client.connect()
        // Because we're faking the CONNECTED state, we can't client.close() or it
        // will actually try to use the connection believing it's ready and throw an
        // exception because it's really not.

        expect(urlConnections).toEventually(haveCount(2), timeout: testTimeout)

        XCTAssertTrue(NSRegularExpression.match(urlConnections.at(1)?.absoluteString, pattern: "//main.[a-e].fallback.ably-realtime.com"))

        waitUntil(timeout: testTimeout) { done in
            client.time { _, _ in
                done()
            }
        }

        let timeRequestUrls = testHttpExecutor.requests.compactMap { $0.url?.host }.filter { !$0.hasPrefix("internet-up") }
        XCTAssertEqual(timeRequestUrls.last, urlConnections.at(1)?.host)
    }

    // RTN19
    func test__010__Connection__attributes_within_ConnectionDetails_should_be_used_as_defaults() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        let realtime = AblyTests.newRealtime(options).client
        defer { realtime.close() }

        waitUntil(timeout: testTimeout) { done in
            realtime.connection.once(.connecting) { stateChange in
                XCTAssertNil(stateChange.reason)

                let transport = realtime.internal.transport as! TestProxyTransport
                transport.setBeforeIncomingMessageModifier { protocolMessage in
                    if protocolMessage.action == .connected {
                        protocolMessage.connectionDetails!.clientId = "john"
                        protocolMessage.connectionDetails!.connectionKey = "123"
                    }
                    return protocolMessage
                }
            }
            realtime.connection.once(.connected) { stateChange in
                XCTAssertNil(stateChange.reason)

                let transport = realtime.internal.transport as! TestProxyTransport
                let connectedProtocolMessage = transport.protocolMessagesReceived.filter { $0.action == .connected }[0]

                XCTAssertEqual(realtime.auth.clientId, connectedProtocolMessage.connectionDetails!.clientId)
                XCTAssertEqual(realtime.connection.key, connectedProtocolMessage.connectionDetails!.connectionKey)
                done()
            }
            realtime.connect()
        }

        let transport = realtime.internal.transport as! TestProxyTransport
        let connectedProtocolMessage = transport.protocolMessagesReceived.filter { $0.action == .connected }[0]
        XCTAssertEqual(realtime.auth.clientId, connectedProtocolMessage.connectionDetails!.clientId)
        XCTAssertEqual(realtime.connection.key, connectedProtocolMessage.connectionDetails!.connectionKey)
    }

    // RTN19a1
    func test__103a__Connection__Transport_disconnected_side_effects__should_resend_any_ProtocolMessage_by_processing_connection_wide_pending_messages() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = AblyTests.newRealtime(options).client
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(test.uniqueChannelName())
        let transport = client.internal.transport as! TestProxyTransport

        waitUntil(timeout: testTimeout) { done in
            channel.attach { _ in done() }
        }

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "message") { error in
                XCTAssertNil(error)
                guard let newTransport = client.internal.transport as? TestProxyTransport else {
                    fail("Transport is nil"); done(); return
                }
                expect(newTransport).toNot(beIdenticalTo(transport))
                XCTAssertEqual(transport.protocolMessagesSent.filter { $0.action == .message }.count, 1)
                XCTAssertEqual(transport.protocolMessagesReceived.filter { $0.action == .connected }.count, 1)
                XCTAssertEqual(newTransport.protocolMessagesSent.filter { $0.action == .message }.count, 1)
                XCTAssertEqual(newTransport.protocolMessagesReceived.filter { $0.action == .connected }.count, 1)
                done()
            }
            client.connection.once(.disconnected) { _ in
                expect(client.internal.pendingMessages).to(haveCount(1))
            }
            client.internal.onDisconnected()
        }
    }

    // RTN19a2 (for resume success)
    func test__103b__Connection__Transport_disconnected_side_effects_message_serial_for_pending_message_must_remain_the_same_that_is_awaiting_a_ACK_NACK() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = AblyTests.newRealtime(options).client

        defer { client.dispose(); client.close() }
        let channel = client.channels.get(test.uniqueChannelName())
        let transport = client.internal.transport as! TestProxyTransport

        var connectionId: String?

        waitUntil(timeout: testTimeout) { done in
            channel.attach { _ in
                let connectedPM = transport.protocolMessagesReceived.filter { $0.action == .connected }[0]
                connectionId = connectedPM.connectionId
                done()
            }
        }

        waitUntil(timeout: testTimeout) { done in
            // send messages to increase msgSerial above zero
            let partialDone = AblyTests.splitDone(2, done: done)
            channel.publish(nil, data: "First message") { error in
                XCTAssertNil(error)
                let msgSerial = transport.protocolMessagesSent.filter { $0.action == .message }[0].msgSerial
                XCTAssertEqual(msgSerial, 0)
                partialDone()
            }
            channel.publish(nil, data: "Second message") { error in
                XCTAssertNil(error)
                let msgSerial = transport.protocolMessagesSent.filter { $0.action == .message }[1].msgSerial
                XCTAssertEqual(msgSerial, 1)
                partialDone()
            }
        }

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "Third message") { error in
                expect(error).to(beNil())
                guard let newTransport = client.internal.transport as? TestProxyTransport else {
                    fail("Transport is nil"); done(); return
                }
                expect(newTransport).toNot(beIdenticalTo(transport))

                let msgSerial1 = transport.protocolMessagesSent.filter { $0.action == .message }[2].msgSerial
                let msgSerial2 = newTransport.protocolMessagesSent.filter { $0.action == .message }[0].msgSerial
                XCTAssertEqual(msgSerial1, 2)
                XCTAssertEqual(msgSerial2, 2)

                done()
            }

            client.connection.once(.connected) { stateChange in
                // Ensure same connection id and no error
                let transport = client.internal.transport as! TestProxyTransport
                let connectedPM = transport.protocolMessagesReceived.filter { $0.action == .connected }[0]
                XCTAssertNil(connectedPM.error)
                XCTAssertEqual(connectedPM.connectionId, connectionId)
            }
            client.internal.onDisconnected()
        }
    }

    // RTN19a2 (for resume failure)
    func test__103c__Connection__Transport_disconnected_side_effects_message_must_be_assigned_a_new_msgSerial_from_the_internal_msgSerial() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = AblyTests.newRealtime(options).client

        defer { client.dispose(); client.close() }
        let channel = client.channels.get(test.uniqueChannelName())
        let transport = client.internal.transport as! TestProxyTransport

        var connectionId: String?

        waitUntil(timeout: testTimeout) { done in
            channel.attach { _ in
                let connectedPM = transport.protocolMessagesReceived.filter { $0.action == .connected }[0]
                connectionId = connectedPM.connectionId
                done()
            }
        }

        waitUntil(timeout: testTimeout) { done in
            // send messages to increase msgSerial above zero
            let partialDone = AblyTests.splitDone(2, done: done)
            channel.publish(nil, data: "First message") { error in
                XCTAssertNil(error)
                let msgSerial = transport.protocolMessagesSent.filter { $0.action == .message }[0].msgSerial
                XCTAssertEqual(msgSerial, 0)
                partialDone()
            }
            channel.publish(nil, data: "Second message") { error in
                XCTAssertNil(error)
                let msgSerial = transport.protocolMessagesSent.filter { $0.action == .message }[1].msgSerial
                XCTAssertEqual(msgSerial, 1)
                partialDone()
            }
        }

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "Third message") { error in
                expect(error).to(beNil())
                guard let newTransport = client.internal.transport as? TestProxyTransport else {
                    fail("Transport is nil"); done(); return
                }
                expect(newTransport).toNot(beIdenticalTo(transport))

                let msgSerial1 = transport.protocolMessagesSent.filter { $0.action == .message }[2].msgSerial
                let msgSerial2 = newTransport.protocolMessagesSent.filter { $0.action == .message }[0].msgSerial
                XCTAssertEqual(msgSerial1, 0)
                XCTAssertEqual(msgSerial2, 0)

                done()
            }

            client.connection.once(.connected) { stateChange in
                // Ensure different connection id and error
                let transport = client.internal.transport as! TestProxyTransport
                let connectedPM = transport.protocolMessagesReceived.filter { $0.action == .connected }[0]
                XCTAssertNotNil(connectedPM.error)
                XCTAssertNotEqual(connectedPM.connectionId, connectionId)
            }
            client.simulateLostConnectionAndState()
        }
    }

    // RTN19b
    func test__104__Connection__Transport_disconnected_side_effects__should_resend_the_ATTACH_message_if_there_are_any_pending_channels() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = AblyTests.newRealtime(options).client
        defer { client.dispose(); client.close() }

        expect(client.connection.state).toEventually(equal(RealtimeConnectionState.connected), timeout: testTimeout)

        guard let transport = client.internal.transport as? TestProxyTransport else {
            fail("TestProxyTransport is not setup"); return
        }

        let channel = client.channels.get(test.uniqueChannelName())
        waitUntil(timeout: testTimeout) { done in
            transport.ignoreSends = true
            channel.attach { error in
                XCTAssertNil(error)
                guard let newTransport = client.internal.transport as? TestProxyTransport else {
                    fail("Transport is nil"); done(); return
                }
                XCTAssertEqual(transport.protocolMessagesReceived.filter { $0.action == .connected }.count, 1)
                XCTAssertEqual(newTransport.protocolMessagesReceived.filter { $0.action == .connected }.count, 1)
                XCTAssertEqual(transport.protocolMessagesSent.filter { $0.action == .attach }.count, 0)
                XCTAssertEqual(transport.protocolMessagesSentIgnored.filter { $0.action == .attach }.count, 1)
                XCTAssertEqual(newTransport.protocolMessagesSent.filter { $0.action == .attach }.count, 1)
                expect(transport).toNot(beIdenticalTo(newTransport))
                done()
            }
            XCTAssertEqual(channel.state, RealtimeChannelState.attaching)
            transport.ignoreSends = false
            AblyTests.queue.async {
                client.internal.onDisconnected()
            }
        }
    }

    // RTN19b
    func skipped__test__105__Connection__Transport_disconnected_side_effects__should_resent_the_DETACH_message_if_there_are_any_pending_channels() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = AblyTests.newRealtime(options).client
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(test.uniqueChannelName())
        let transport = client.internal.transport as! TestProxyTransport

        expect(client.connection.state).toEventually(equal(RealtimeConnectionState.connected), timeout: testTimeout)

        waitUntil(timeout: testTimeout) { done in
            channel.attach { _ in done() }
        }

        waitUntil(timeout: testTimeout) { done in
            transport.ignoreSends = true
            channel.detach { error in
                XCTAssertNil(error)
                guard let newTransport = client.internal.transport as? TestProxyTransport else {
                    fail("Transport is nil"); done(); return
                }
                XCTAssertEqual(transport.protocolMessagesReceived.filter { $0.action == .connected }.count, 1)
                XCTAssertEqual(newTransport.protocolMessagesReceived.filter { $0.action == .connected }.count, 1)
                XCTAssertEqual(transport.protocolMessagesSent.filter { $0.action == .detach }.count, 0)
                XCTAssertEqual(transport.protocolMessagesSentIgnored.filter { $0.action == .detach }.count, 1)
                XCTAssertEqual(newTransport.protocolMessagesSent.filter { $0.action == .detach }.count, 1)
                done()
            }
            XCTAssertEqual(channel.state, RealtimeChannelState.detaching)
            transport.ignoreSends = false
            client.internal.onDisconnected()
        }
    }

    // RTN20

    // RTN20a

    func beforeEach__Connection__Operating_System_events_for_network_internet_connectivity_changes__should_immediately_change_the_state_to_DISCONNECTED_if_the_operating_system_indicates_that_the_underlying_internet_connection_is_no_longer_available(for test: Test) throws {
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        internetConnectionNotAvailableTestsClient = PubSubClient(options: options)
        internetConnectionNotAvailableTestsClient.internal.setReachabilityClass(TestReachability.self)
    }

    func afterEach__Connection__Operating_System_events_for_network_internet_connectivity_changes__should_immediately_change_the_state_to_DISCONNECTED_if_the_operating_system_indicates_that_the_underlying_internet_connection_is_no_longer_available() {
        internetConnectionNotAvailableTestsClient.dispose()
        internetConnectionNotAvailableTestsClient.close()
    }

    func test__109__Connection__Operating_System_events_for_network_internet_connectivity_changes__should_immediately_change_the_state_to_DISCONNECTED_if_the_operating_system_indicates_that_the_underlying_internet_connection_is_no_longer_available__when_CONNECTING() throws {
        let test = Test()
        try beforeEach__Connection__Operating_System_events_for_network_internet_connectivity_changes__should_immediately_change_the_state_to_DISCONNECTED_if_the_operating_system_indicates_that_the_underlying_internet_connection_is_no_longer_available(for: test)

        waitUntil(timeout: testTimeout) { done in
            internetConnectionNotAvailableTestsClient.connection.on { stateChange in
                switch stateChange.current {
                case .connecting:
                    XCTAssertNil(stateChange.reason)
                    guard let reachability = internetConnectionNotAvailableTestsClient.internal.reachability as? TestReachability else {
                        fail("expected test reachability")
                        done(); return
                    }
                    XCTAssertEqual(reachability.host, internetConnectionNotAvailableTestsClient.internal.options.primaryDomain)
                    reachability.simulate(false)
                case .disconnected:
                    guard let reason = stateChange.reason else {
                        fail("expected error reason")
                        done(); return
                    }
                    XCTAssertEqual(reason.code, -1003)
                    done()
                default:
                    break
                }
            }
            internetConnectionNotAvailableTestsClient.connect()
        }

        afterEach__Connection__Operating_System_events_for_network_internet_connectivity_changes__should_immediately_change_the_state_to_DISCONNECTED_if_the_operating_system_indicates_that_the_underlying_internet_connection_is_no_longer_available()
    }

    func test__110__Connection__Operating_System_events_for_network_internet_connectivity_changes__should_immediately_change_the_state_to_DISCONNECTED_if_the_operating_system_indicates_that_the_underlying_internet_connection_is_no_longer_available__when_CONNECTED() throws {
        let test = Test()
        try beforeEach__Connection__Operating_System_events_for_network_internet_connectivity_changes__should_immediately_change_the_state_to_DISCONNECTED_if_the_operating_system_indicates_that_the_underlying_internet_connection_is_no_longer_available(for: test)

        waitUntil(timeout: testTimeout) { done in
            internetConnectionNotAvailableTestsClient.connection.on { stateChange in
                switch stateChange.current {
                case .connected:
                    XCTAssertNil(stateChange.reason)
                    guard let reachability = internetConnectionNotAvailableTestsClient.internal.reachability as? TestReachability else {
                        fail("expected test reachability")
                        done(); return
                    }
                    XCTAssertEqual(reachability.host, internetConnectionNotAvailableTestsClient.internal.options.primaryDomain)
                    reachability.simulate(false)
                case .disconnected:
                    guard let reason = stateChange.reason else {
                        fail("expected error reason")
                        done(); return
                    }
                    XCTAssertEqual(reason.code, -1003)
                    done()
                default:
                    break
                }
            }
            internetConnectionNotAvailableTestsClient.connect()
        }

        afterEach__Connection__Operating_System_events_for_network_internet_connectivity_changes__should_immediately_change_the_state_to_DISCONNECTED_if_the_operating_system_indicates_that_the_underlying_internet_connection_is_no_longer_available()
    }

    // RTN20b
    func test__106__Connection__Operating_System_events_for_network_internet_connectivity_changes__should_immediately_attempt_to_connect_if_the_operating_system_indicates_that_the_underlying_internet_connection_is_now_available_when_DISCONNECTED_or_SUSPENDED() throws {
        let test = Test()
        var client: PubSubClient!
        let options = try AblyTests.commonAppSetup(for: test)
        // Ensure it won't reconnect because of timeouts.
        options.disconnectedRetryTimeout = testTimeout.incremented(by: 10).toTimeInterval()
        options.suspendedRetryTimeout = testTimeout.incremented(by: 10).toTimeInterval()
        options.autoConnect = false
        client = PubSubClient(options: options)
        client.internal.setReachabilityClass(TestReachability.self)
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.on { stateChange in
                switch stateChange.current {
                case .connecting:
                    if stateChange.previous == .disconnected {
                        client.internal.onSuspended()
                    } else if stateChange.previous == .suspended {
                        done()
                    }
                case .connected:
                    client.internal.onDisconnected()
                case .disconnected, .suspended:
                    guard let reachability = client.internal.reachability as? TestReachability else {
                        fail("expected test reachability")
                        done(); return
                    }
                    XCTAssertEqual(reachability.host, client.internal.options.primaryDomain)
                    reachability.simulate(true)
                default:
                    break
                }
            }
            client.connect()
        }
    }

    // RTN20c
    func test__106_b__Connection__Operating_System_events_for_network_internet_connectivity_changes__should_restart_the_pending_connection_attempt_if_the_operating_system_indicates_that_the_underlying_internet_connection_is_now_available_when_CONNECTING() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let realtimeHost = options.primaryDomain
        options.endpoint = "10.255.255.1" // non-routable IP address
        options.autoConnect = false
        options.testOptions.reconnectionRealtimeHost = realtimeHost
        let client = PubSubClient(options: options)
        client.internal.setReachabilityClass(TestReachability.self)
        defer { client.dispose(); client.close() }

        var reconnectMethodCallCount = 0
        let hook = client.internal.testSuite_injectIntoMethod(after: #selector(client.internal.transportReconnectWithExistingParameters)) {
            reconnectMethodCallCount += 1
        }
        defer { hook.remove() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connecting) { _ in
                guard let reachability = client.internal.reachability as? TestReachability else {
                    XCTFail("expected test reachability"); return
                }
                // Simulate initial reachability call as `false` because:
                // a) address is non-routable
                // b) it will be called by the system once reachability callback is set (during transition to CONNECTING)
                reachability.simulate(false)
                XCTAssertEqual(client.connection.state, RealtimeConnectionState.disconnected)
                client.connect()
                XCTAssertEqual(client.connection.state, RealtimeConnectionState.connecting)
                reachability.simulate(true)
                XCTAssertEqual(client.connection.state, RealtimeConnectionState.connecting)
            }
            client.connection.once(.connected) { stateChange in
                XCTAssertEqual(reconnectMethodCallCount, 1)
                done()
            }
            client.connect()
        }

        // Now check that reconnect will not happen if reachability haven't reported "unreachable" before

        let options2 = try AblyTests.commonAppSetup(for: test)
        options2.autoConnect = false
        let client2 = PubSubClient(options: options2)
        client2.internal.setReachabilityClass(TestReachability.self)
        defer { client2.dispose(); client2.close() }

        reconnectMethodCallCount = 0
        let hook2 = client2.internal.testSuite_injectIntoMethod(after: #selector(client2.internal.transportReconnectWithExistingParameters)) {
            reconnectMethodCallCount += 1
        }
        defer { hook2.remove() }

        waitUntil(timeout: testTimeout) { done in
            client2.connection.once(.connecting) { _ in
                guard let reachability = client2.internal.reachability as? TestReachability else {
                    XCTFail("expected test reachability"); return
                }
                reachability.simulate(true)
                XCTAssertEqual(client2.connection.state, RealtimeConnectionState.connecting)
            }
            client2.connection.once(.connected) { stateChange in
                XCTAssertEqual(reconnectMethodCallCount, 0)
                done()
            }
            client2.connect()
        }
    }

    // RTN22
    func test__107__Connection__Operating_System_events_for_network_internet_connectivity_changes__Ably_can_request_that_a_connected_client_re_authenticates_by_sending_the_client_an_AUTH_ProtocolMessage() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        options.useTokenAuth = true
        options.testOptions.transportFactory = TestProxyTransportFactory()
        let client = PubSubClient(options: options)
        defer { client.dispose(); client.close() }

        let channelName = test.uniqueChannelName()
        let channel = client.channels.get(channelName)

        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                XCTAssertNil(error)
                done()
            }
            client.connect()
        }

        guard let initialConnectionId = client.connection.id else {
            fail("ConnectionId is nil"); return
        }

        guard let initialToken = client.auth.tokenDetails?.token else {
            fail("Initial token is nil"); return
        }

        guard let transport = client.internal.transport as? TestProxyTransport else {
            fail("TestProxyTransport is not set"); return
        }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.update) { stateChange in
                XCTAssertNil(stateChange.reason)
                XCTAssertNotEqual(initialToken, client.auth.tokenDetails?.token)
                done()
            }

            let authMessage = ARTProtocolMessage()
            authMessage.action = .auth
            client.internal.transport?.receive(authMessage)
        }

        XCTAssertEqual(client.connection.id, initialConnectionId)
        XCTAssertTrue(client.internal.transport === transport)

        let authMessages = transport.protocolMessagesSent.filter { $0.action == .auth }
        XCTAssertEqual(authMessages.count, 1)

        guard let authMessage = authMessages.first else {
            fail("Missing AUTH protocol message"); return
        }

        XCTAssertNotNil(authMessage.auth)

        guard (authMessage.auth?.accessToken) != nil else {
            fail("Missing accessToken from AUTH ProtocolMessage auth attribute"); return
        }

        let restOptions = try AblyTests.clientOptions(for: test, key: options.key!)
        restOptions.testOptions.channelNamePrefix = options.testOptions.channelNamePrefix
        let rest = HttpClient(options: restOptions)

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)
            let expectedMessage = Message(name: "ios", data: "message1")

            channel.subscribe { message in
                XCTAssertEqual(message.name, expectedMessage.name)
                XCTAssertEqual(message.data as? String, expectedMessage.data as? String)
                partialDone()
            }

            rest.channels.get(channelName).publish([expectedMessage]) { error in
                XCTAssertNil(error)
                partialDone()
            }
        }

        channel.off()
    }

    // RTN22a
    func test__108__Connection__Operating_System_events_for_network_internet_connectivity_changes__re_authenticate_and_resume_the_connection_when_the_client_is_forcibly_disconnected_following_a_DISCONNECTED_message_containing_an_error_code_greater_than_or_equal_to_40140_and_less_than_40150() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.token = try getTestToken(for: test, key: options.key!, ttl: 5.0)
        let client = PubSubClient(options: options)
        defer { client.dispose(); client.close() }

        let channelName = test.uniqueChannelName()
        let channel = client.channels.get(channelName)

        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                XCTAssertNil(error)
                done()
            }
        }

        guard let initialConnectionId = client.connection.id else {
            fail("ConnectionId is nil"); return
        }

        guard let initialToken = client.auth.tokenDetails?.token else {
            fail("Initial token is nil"); return
        }

        channel.once(.detached) { _ in
            fail("Should not detach channels")
        }

        var authorizeMethodCallCount = 0
        let hook = client.auth.internal.testSuite_injectIntoMethod(after: #selector(client.auth.internal._authorize(_:options:callback:))) {
            authorizeMethodCallCount += 1
        }
        defer { hook.remove() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.disconnected) { stateChange in
                guard let error = stateChange.reason else {
                    fail("Error is nil"); done(); return
                }
                XCTAssertEqual(error.code, ErrorCode.tokenExpired.intValue)
                done()
            }
        }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { stateChange in
                XCTAssertNil(stateChange.reason)
                XCTAssertNotEqual(initialToken, client.auth.tokenDetails?.token)
                done()
            }
        }

        XCTAssertEqual(client.connection.id, initialConnectionId)
        XCTAssertEqual(authorizeMethodCallCount, 1)

        let restOptions = try AblyTests.clientOptions(for: test, key: options.key!)
        restOptions.testOptions.channelNamePrefix = options.testOptions.channelNamePrefix
        let rest = HttpClient(options: restOptions)

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)
            let expectedMessage = Message(name: "ios", data: "message1")

            channel.subscribe { message in
                XCTAssertEqual(message.name, expectedMessage.name)
                XCTAssertEqual(message.data as? String, expectedMessage.data as? String)
                partialDone()
            }

            rest.channels.get(channelName).publish([expectedMessage]) { error in
                XCTAssertNil(error)
                partialDone()
            }
        }

        channel.off()
    }

    // RTN23a
    func test__011__Connection__should_disconnect_the_transport_when_no_activity_exist() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        // This needs to be sufficiently long such that we can expect to receive a CONNECTED ProtocolMessage within this duration after starting a connection attempt (there's no "correct" value since it depends on network conditions, but 1.5s seemed to work locally and in CI at time of writing). But we also don't want it to be longer than necessary since that would impact test execution time.
        let realtimeRequestTimeout = 1.5
        options.testOptions.realtimeRequestTimeout = realtimeRequestTimeout
        let client = AblyTests.newRealtime(options).client
        defer { client.dispose(); client.close() }

        var expectedInactivityTimeout: TimeInterval?
        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)

            guard let transport = client.internal.transport as? TestProxyTransport else {
                fail("TestProxyTransport is not set"); partialDone(); return
            }

            var noActivityHasStartedAt: Date?
            transport.setBeforeIncomingMessageModifier { protocolMessage in
                if protocolMessage.action == .connected, let connectionDetails = protocolMessage.connectionDetails {
                    connectionDetails.setMaxIdleInterval(3)
                    expectedInactivityTimeout = connectionDetails.maxIdleInterval + realtimeRequestTimeout
                    // Force no activity
                    transport.ignoreWebSocket = true
                    noActivityHasStartedAt = Date()
                    transport.setBeforeIncomingMessageModifier(nil)
                    partialDone()
                }
                return protocolMessage
            }

            client.connection.on(.disconnected) { stateChange in
                let now = Date()

                XCTAssertEqual(stateChange.previous, RealtimeConnectionState.connected)

                guard let noActivityHasStartedAt = noActivityHasStartedAt else {
                    fail("No activity date is missing"); partialDone(); return
                }
                guard let expectedInactivityTimeout = expectedInactivityTimeout else {
                    fail("Expected inactivity timeout is missing"); partialDone(); return
                }

                expect(now.timeIntervalSince(noActivityHasStartedAt)).to(beCloseTo(expectedInactivityTimeout, within: 1.0))

                guard let reason = stateChange.reason else {
                    fail("ConnectionStateChange reason is missing"); partialDone(); return
                }
                guard let errorReason = client.connection.errorReason else {
                    fail("Connection error is missing"); partialDone(); return
                }

                expect(reason.message).to(contain("Idle timer expired"))
                expect(errorReason.message).to(contain("Idle timer expired"))

                partialDone()
            }
        }

        XCTAssertEqual(expectedInactivityTimeout, 4.5)
        XCTAssertEqual(client.internal.maxIdleInterval, 3.0)
    }

    // RTN24
    func test__012__Connection__the_client_may_receive_a_CONNECTED_ProtocolMessage_from_Ably_at_any_point_and_should_emit_an_UPDATE_event() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = PubSubClient(options: options)
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { stateChange in
                XCTAssertNil(stateChange.reason)
                done()
            }
        }

        waitUntil(timeout: testTimeout) { done in
            let authMessage = ARTProtocolMessage()
            authMessage.action = ARTProtocolMessageAction.connected
            authMessage.error = ErrorInfo.create(withCode: 1234, message: "fabricated error")

            let listener = client.connection.once(.connected) { _ in
                fail("shouldn't emit CONNECTED")
            }
            client.connection.once(.update) { stateChange in
                XCTAssertEqual(client.connection.state, RealtimeConnectionState.connected)
                XCTAssertEqual(stateChange.current, RealtimeConnectionState.connected)
                XCTAssertEqual(stateChange.current, stateChange.previous)
                XCTAssertTrue(stateChange.reason === authMessage.error)
                delay(0.5) { // Give some time for the other listener to be triggered.
                    client.connection.off(listener)
                    done()
                }
            }

            client.internal.transport?.receive(authMessage)
        }
    }

    // RTN24
    func test__013__Connection__should_set_the_Connection_reason_attribute_based_on_the_Error_member_of_the_CONNECTED_ProtocolMessage() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.useTokenAuth = true
        let client = AblyTests.newRealtime(options).client
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { stateChange in
                XCTAssertNil(stateChange.reason)
                done()
            }
        }

        guard let transport = client.internal.transport as? TestProxyTransport else {
            fail("TestProxyTransport is not set"); return
        }
        guard let originalConnectedMessage = transport.protocolMessagesReceived.filter({ $0.action == .connected }).first else {
            fail("First CONNECTED message not received"); return
        }

        client.connection.once(.connected) { _ in
            fail("Should not emit a Connected state")
        }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.update) { stateChange in
                guard let error = stateChange.reason else {
                    fail("Reason error is nil"); done(); return
                }
                XCTAssertEqual(error.code, 1234)
                XCTAssertEqual(client.connection.errorReason?.code, 1234)
                XCTAssertEqual(client.connection.state, RealtimeConnectionState.connected)
                XCTAssertEqual(stateChange.current, RealtimeConnectionState.connected)
                XCTAssertEqual(stateChange.current, stateChange.previous)
                done()
            }

            let connectedMessageWithError = originalConnectedMessage
            connectedMessageWithError.error = ErrorInfo.create(withCode: 1234, message: "fabricated error")
            client.internal.transport?.receive(connectedMessageWithError)
        }
    }

    // https://github.com/ably/ably-cocoa/issues/454
    func test__014__Connection__should_not_move_to_FAILED_if_received_DISCONNECT_with_an_error() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = PubSubClient(options: options)
        defer {
            client.dispose()
            client.close()
        }

        expect(client.connection.state).toEventually(equal(RealtimeConnectionState.connected), timeout: testTimeout)

        let protoMsg = ARTProtocolMessage()
        protoMsg.action = .disconnect
        protoMsg.error = ErrorInfo.create(withCode: 123, message: "test error")
        client.internal.transport?.receive(protoMsg)

        XCTAssertEqual(client.connection.state, RealtimeConnectionState.disconnected)
        XCTAssertEqual(client.connection.errorReason, protoMsg.error)
    }

    // https://github.com/ably/wiki/issues/22
    func test__111__Connection__with_fixture_messages__should_encode_and_decode_fixture_messages_as_expected() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.useBinaryProtocol = false
        let client = AblyTests.newRealtime(options).client
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(test.uniqueChannelName())
        channel.attach()

        expect(channel.state).toEventually(equal(RealtimeChannelState.attached), timeout: testTimeout)
        if channel.state != .attached {
            return
        }

        let messages = fixtures["messages"] as! [[String: Any]]

        for fixtureMessage in messages {
            var receivedMessage: Message?

            waitUntil(timeout: testTimeout) { done in
                channel.subscribe { message in
                    channel.unsubscribe()
                    receivedMessage = message
                    done()
                }

                let request = NSMutableURLRequest(url: URL(string: "/channels/\(channel.name)/messages")!)
                request.httpMethod = "POST"
                request.httpBody = try! JSONUtility.serialize(fixtureMessage)
                request.allHTTPHeaderFields = [
                    "Accept": "application/json",
                    "Content-Type": "application/json",
                ]
                client.internal.rest.execute(request, withAuthOption: .on, wrapperSDKAgents: nil, completion: { _, _, err in
                    if let err = err {
                        fail("\(err)")
                    }
                })
            }

            guard let message = receivedMessage else {
                continue
            }

            expectDataToMatch(message, fixtureMessage)

            waitUntil(timeout: testTimeout) { done in
                channel.publish([message]) { err in
                    if let err = err {
                        fail("\(err)")
                        done()
                        return
                    }

                    sleep(1) // give realtime some time to store messages so they appear in the GET request below

                    let request = NSMutableURLRequest(url: URL(string: "/channels/\(channel.name)/messages")!)
                    request.httpMethod = "GET"
                    request.allHTTPHeaderFields = ["Accept": "application/json"]
                    client.internal.rest.execute(request, withAuthOption: .on, wrapperSDKAgents: nil, completion: { _, data, err in
                        if let err = err {
                            fail("\(err)")
                            done()
                            return
                        }
                        let messages: [[String: Any]] = try! JSONUtility.jsonObject(data: data)
                        let persistedMessage = messages.first { jsonObject in
                            jsonObject["id"] as? String == message.id
                        }
                        XCTAssertEqual(persistedMessage?["data"] as? String, fixtureMessage["data"] as? String)
                        XCTAssertEqual(persistedMessage?["encoding"] as? String, fixtureMessage["encoding"] as? String)
                        done()
                    })
                }
            }
        }
    }

    func test__112__Connection__with_fixture_messages__should_send_messages_through_raw_JSON_POST_and_retrieve_equal_messages_through_MsgPack_and_JSON() throws {
        let test = Test()
        try setupDependencies(for: test)
        let restPublishClient = HttpClient(options: jsonOptions)
        let realtimeSubscribeClientMsgPack = AblyTests.newRealtime(msgpackOptions).client
        let realtimeSubscribeClientJSON = AblyTests.newRealtime(jsonOptions).client
        defer {
            realtimeSubscribeClientMsgPack.close()
            realtimeSubscribeClientJSON.close()
        }

        let realtimeSubscribeChannelMsgPack = realtimeSubscribeClientMsgPack.channels.get(test.uniqueChannelName())
        let realtimeSubscribeChannelJSON = realtimeSubscribeClientJSON.channels.get(realtimeSubscribeChannelMsgPack.name)

        waitUntil(timeout: testTimeout) { done in
            let partlyDone = AblyTests.splitDone(2, done: done)
            realtimeSubscribeChannelMsgPack.attach { _ in partlyDone() }
            realtimeSubscribeChannelJSON.attach { _ in partlyDone() }
        }

        let messages = fixtures["messages"] as! [[String: Any]]

        for fixtureMessage in messages {
            waitUntil(timeout: testTimeout) { done in
                let partlyDone = AblyTests.splitDone(2, done: done)

                realtimeSubscribeChannelMsgPack.subscribe { message in
                    realtimeSubscribeChannelMsgPack.unsubscribe()
                    expectDataToMatch(message, fixtureMessage)
                    partlyDone()
                }

                realtimeSubscribeChannelJSON.subscribe { message in
                    realtimeSubscribeChannelJSON.unsubscribe()
                    expectDataToMatch(message, fixtureMessage)
                    partlyDone()
                }

                let request = NSMutableURLRequest(url: URL(string: "/channels/\(realtimeSubscribeChannelMsgPack.name)/messages")!)
                request.httpMethod = "POST"
                request.httpBody = try! JSONUtility.serialize(fixtureMessage)
                request.allHTTPHeaderFields = [
                    "Accept": "application/json",
                    "Content-Type": "application/json",
                ]
                restPublishClient.internal.execute(request, withAuthOption: .on, wrapperSDKAgents: nil, completion: { _, _, err in
                    if let err = err {
                        fail("\(err)")
                    }
                })
            }
        }
    }

    func test__113__Connection__with_fixture_messages__should_send_messages_through_MsgPack_and_JSON_and_retrieve_equal_messages_through_raw_JSON_GET() throws {
        let test = Test()
        try setupDependencies(for: test)
        let restPublishClientMsgPack = HttpClient(options: msgpackOptions)
        let restPublishClientJSON = HttpClient(options: jsonOptions)
        let restRetrieveClient = HttpClient(options: jsonOptions)

        let channelName = test.uniqueChannelName()
        let restPublishChannelMsgPack = restPublishClientMsgPack.channels.get(channelName)
        let restPublishChannelJSON = restPublishClientJSON.channels.get(channelName)

        let realtimeClient = AblyTests.newRealtime(jsonOptions).client // client for receiving message for obtaining its id to use it later in filtering
        defer { realtimeClient.dispose(); realtimeClient.close() }
        let realtimeChannel = realtimeClient.channels.get(channelName)
        realtimeChannel.attach()

        expect(realtimeChannel.state).toEventually(equal(RealtimeChannelState.attached), timeout: testTimeout)
        if realtimeChannel.state != .attached {
            return
        }

        let messages = fixtures["messages"] as! [[String: Any]]

        for fixtureMessage in messages {
            var data: AnyObject
            if let expectedType = fixtureMessage["expectedType"] as? String, expectedType == "binary" {
                data = (fixtureMessage["expectedHexValue"] as! String).dataFromHexadecimalString()! as AnyObject
            } else {
                data = fixtureMessage["expectedValue"] as AnyObject
            }

            for restPublishChannel in [restPublishChannelMsgPack, restPublishChannelJSON] {
                var receivedMessage: Message?

                waitUntil(timeout: testTimeout) { done in
                    let partialDone = AblyTests.splitDone(2, done: done)
                    realtimeChannel.subscribe("event") { message in
                        realtimeChannel.unsubscribe()
                        receivedMessage = message
                        partialDone()
                    }
                    restPublishChannel.publish("event", data: data) { err in
                        if let err = err {
                            fail("\(err)")
                            partialDone()
                            return
                        }
                        partialDone()
                    }
                }

                sleep(1) // give realtime some time to store messages so they appear in the GET request below

                waitUntil(timeout: testTimeout) { done in
                    let request = NSMutableURLRequest(url: URL(string: "/channels/\(restPublishChannel.name)/messages")!)
                    request.httpMethod = "GET"
                    request.allHTTPHeaderFields = ["Accept": "application/json"]
                    restRetrieveClient.internal.execute(request, withAuthOption: .on, wrapperSDKAgents: nil, completion: { _, data, err in
                        if let err = err {
                            fail("\(err)")
                            done()
                            return
                        }
                        let messages: [[String: Any]] = try! JSONUtility.jsonObject(data: data)
                        guard let persistedMessage = messages.first(where: { jsonObject in
                            jsonObject["id"] as? String == receivedMessage?.id
                        }) else {
                            XCTFail("Message was not published yet.")
                            return
                        }
                        // In case of string with json data, dictionary objects can be in different order from what they were sent, so I just compare them as ordered characters array which is good enough for the sample data provided in `fixtures`
                        XCTAssertEqual(Array(persistedMessage["data"] as! String).sorted(), Array(fixtureMessage["data"] as! String).sorted())
                        XCTAssertEqual(persistedMessage["encoding"] as? String, fixtureMessage["encoding"] as? String)
                        done()
                    })
                }
            }
        }
    }

    func test__015__Connection__should_abort_reconnection_with_new_token_if_the_server_has_requested_it_to_authorize_and_after_it_the_connection_has_been_closed() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = PubSubClient(options: options)
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { stateChange in
                XCTAssertNil(stateChange.reason)
                done()
            }
        }

        client.auth.internal.options.authCallback = { _, completion in
            getTestTokenDetails(for: test, ttl: 0.1) { tokenDetails, error in
                XCTAssertNil(error)
                guard let tokenDetails = tokenDetails else {
                    fail("TokenDetails is nil"); return
                }
                // Let the token expire
                delay(0.1) {
                    completion(tokenDetails.token as TokenDetailsCompatible?, nil)
                }
            }
        }

        let authMessage = ARTProtocolMessage()
        authMessage.action = .auth
        client.internal.transport?.receive(authMessage)

        client.close()

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.failed) { _ in
                fail("Should not receive error 40142")
            }
            client.connection.once(.connected) { _ in
                fail("Should not connect")
            }
            client.connection.once(.closed) { _ in
                done()
            }
        }
    }
}
