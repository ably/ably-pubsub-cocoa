import AblyPubSubDevice
import AblyPubSubDevice.Private
import Nimble
import XCTest
import AblyTestingObjC

private let attachResumeExpectedValues: [RealtimeChannelState: Bool] = [
    .initialized: false,
    .attached: true,
    .detaching: false,
    .failed: false,
]
private var rtl6c2TestsClient: PubSubClient!
private var rtl6c2TestsChannel: RealtimeChannel!

private func rtl16c2TestsPublish(_ done: @escaping () -> Void) {
    rtl6c2TestsChannel.publish(nil, data: "message") { error in
        XCTAssertNil(error)
        XCTAssertEqual(rtl6c2TestsClient.connection.state, RealtimeConnectionState.connected)
        done()
    }
}

private var options: ClientOptions!
private var rtl6c4TestsClient: PubSubClient!
private var rtl6c4TestsChannel: RealtimeChannel!

private let previousConnectionStateTtl = Default.connectionStateTtl()

private func setupDependencies(for test: Test) throws {
    if options == nil {
        options = try AblyTests.commonAppSetup(for: test)
        options.suspendedRetryTimeout = 0.3
        options.autoConnect = false
    }
}

private func rtl6c4TestsPublish(_ done: @escaping () -> Void) {
    rtl6c4TestsChannel.publish(nil, data: "message") { error in
        XCTAssertNotNil(error)
        done()
    }
}

/*
 This test makes a deep assumption about the content of these two files,
 specifically the format of the first message in the items array.
 */
private func testHandlesDecodingErrorInFixture(_ cryptoFixtureFileName: String, for test: Test, channelName: String) throws {
    let options = try AblyTests.commonAppSetup(for: test)
    options.autoConnect = false
    options.logHandler = Log(capturingOutput: true)
    options.testOptions.transportFactory = TestProxyTransportFactory()
    let client = PubSubClient(options: options)
    client.connect()
    defer { client.dispose(); client.close() }

    let (keyData, ivData, messages) = AblyTests.loadCryptoTestData(cryptoFixtureFileName)
    let testMessage = messages[0]

    let cipherParams = CipherParams(algorithm: "aes", key: keyData as CipherKeyCompatible, iv: ivData)
    let channelOptions = RealtimeChannelOptions(cipher: cipherParams)
    let channel = client.channels.get(channelName, options: channelOptions)

    let transport = client.internal.transport as! TestProxyTransport

    transport.setListenerBeforeProcessingOutgoingMessage { protocolMessage in
        if protocolMessage.action == .message {
            XCTAssertEqual(protocolMessage.messages![0].data as? String, testMessage.encrypted.data)
            XCTAssertEqual(protocolMessage.messages![0].encoding, testMessage.encrypted.encoding)
        }
    }

    transport.setBeforeIncomingMessageModifier { protocolMessage in
        if protocolMessage.action == .message {
            XCTAssertEqual(protocolMessage.messages![0].data as? NSObject, AblyTests.base64ToData(testMessage.encrypted.data) as NSObject?)
            XCTAssertEqual(protocolMessage.messages![0].encoding, "utf-8/cipher+aes-\(cryptoFixtureFileName.suffix(3))-cbc")

            // Force an error decoding a message
            protocolMessage.messages![0].encoding = "bad_encoding_type"
        }
        return protocolMessage
    }

    waitUntil(timeout: testTimeout) { done in
        let partlyDone = AblyTests.splitDone(2, done: done)

        channel.subscribe(testMessage.encoded.name) { message in
            XCTAssertEqual(message.data as? NSObject, AblyTests.base64ToData(testMessage.encrypted.data) as NSObject?)

            let logs = options.logHandler.captured
            let line = logs.reduce("") { $0 + "; " + $1.toString() } // Reduce in one line

            expect(line).to(contain("Failed to decode data: unknown encoding: 'bad_encoding_type'"))

            partlyDone()
        }

        channel.on(.update) { stateChange in
            guard let error = stateChange.reason else {
                return
            }
            expect(error.message).to(contain("Failed to decode data: unknown encoding: 'bad_encoding_type'"))
            XCTAssertTrue(error === channel.errorReason)
            partlyDone()
        }

        channel.publish(testMessage.encoded.name, data: testMessage.encoded.data)
    }
}

private func testWithUntilAttach(_ untilAttach: Bool, for test: Test, channelName: String) throws {
    let options = try AblyTests.commonAppSetup(for: test)
    let client = PubSubClient(options: options)
    defer { client.dispose(); client.close() }
    let channel = client.channels.get(channelName)

    let testHTTPExecutor = TestProxyHTTPExecutor(logger: .init(clientOptions: options))
    client.internal.rest.httpExecutor = testHTTPExecutor

    let query = RealtimeHistoryQuery()
    query.untilAttach = untilAttach

    channel.attach()
    expect(channel.state).toEventually(equal(RealtimeChannelState.attached), timeout: testTimeout)

    waitUntil(timeout: testTimeout) { done in
        channel.history(query) { _, errorInfo in
            XCTAssertNil(errorInfo)
            done()
        }
    }

    let queryString = testHTTPExecutor.requests.last!.url!.query

    if query.untilAttach {
        expect(queryString).to(contain("fromSerial=\(channel.properties.attachSerial!)"))
    } else {
        expect(queryString).toNot(contain("fromSerial"))
    }
}

class RealtimeClientChannelTests: XCTestCase {
    // XCTest invokes this method before executing the first test in the test suite. We use it to ensure that the global variables are initialized at the same moment, and in the same order, as they would have been when we used the Quick testing framework.
    override class var defaultTestSuite: XCTestSuite {
        _ = attachResumeExpectedValues
        _ = rtl6c2TestsClient
        _ = rtl6c2TestsChannel
        _ = options
        _ = rtl6c4TestsClient
        _ = rtl6c4TestsChannel
        _ = previousConnectionStateTtl

        return super.defaultTestSuite
    }

    // RTL1
    func test__001__Channel__should_process_all_incoming_messages_and_presence_messages_as_soon_as_a_Channel_becomes_attached() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client1 = AblyTests.newRealtime(options).client
        defer { client1.dispose(); client1.close() }

        let roomName = test.uniqueChannelName(prefix: "room")

        let channel1 = client1.channels.get(roomName)

        waitUntil(timeout: testTimeout) { done in
            channel1.presence.enterClient("Client 1", data: nil) { errorInfo in
                XCTAssertNil(errorInfo)
                done()
            }
        }

        options.clientId = "Client 2"
        let client2 = AblyTests.newRealtime(options).client
        defer { client2.dispose(); client2.close() }
        let channel2 = client2.channels.get(roomName)

        channel2.subscribe("Client 1") { message in
            XCTAssertEqual(message.data as? String, "message")
        }

        waitUntil(timeout: testTimeout) { done in
            channel2.on(.attached) { _ in
                XCTAssertEqual(channel2.state, RealtimeChannelState.attached)
                done()
            }
            channel2.attach()

            XCTAssertFalse(channel2.presence.syncComplete)
            XCTAssertEqual(channel1.internal.presence.members.count, 1)
            XCTAssertEqual(channel2.internal.presence.members.count, 0)
        }

        expect(channel2.presence.syncComplete).toEventually(beTrue(), timeout: testTimeout)

        XCTAssertEqual(channel1.internal.presence.members.count, 1)
        expect(channel2.internal.presence.members).toEventually(haveCount(1), timeout: testTimeout)

        waitUntil(timeout: testTimeout) { done in
            channel1.publish("message", data: nil) { errorInfo in
                XCTAssertNil(errorInfo)
                done()
            }
        }

        waitUntil(timeout: testTimeout) { done in
            channel2.presence.enter(nil) { errorInfo in
                XCTAssertNil(errorInfo)
                done()
            }
        }

        expect(channel1.internal.presence.members).toEventually(haveCount(2), timeout: testTimeout)
        expect(channel1.internal.presence.members.keys).to(allPass { $0.hasPrefix("\(channel1.internal.connectionId):Client") || $0.hasPrefix("\(channel2.internal.connectionId):Client") })
        expect(channel1.internal.presence.members.values).to(allPass { $0.action == .present })

        expect(channel2.internal.presence.members).toEventually(haveCount(2), timeout: testTimeout)
        expect(channel2.internal.presence.members.keys).to(allPass { $0.hasPrefix("\(channel1.internal.connectionId):Client") || $0.hasPrefix("\(channel2.internal.connectionId):Client") })
        XCTAssertEqual(channel2.internal.presence.members["\(channel1.internal.connectionId):Client 1"]!.action, PresenceAction.present)
        XCTAssertEqual(channel2.internal.presence.members["\(channel2.internal.connectionId):Client 2"]!.action, PresenceAction.present)
    }

    // RTL2

    // RTL2a
    func test__003__Channel__EventEmitter__channel_states_and_events__should_implement_the_EventEmitter_and_emit_events_for_state_changes() throws {
        let test = Test()
        let client = PubSubClient(options: try AblyTests.commonAppSetup(for: test))
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(test.uniqueChannelName())
        expect(channel.internal.statesEventEmitter).to(beAKindOf(EventEmitter<Event, ChannelStateChange>.self))

        var channelOnMethodCalled = false
        channel.internal.testSuite_injectIntoMethod(after: #selector(EventEmitter<Event, ChannelStateChange>.on(_:))) {
            channelOnMethodCalled = true
        }

        // The `channel.on` should use `statesEventEmitter`
        var statesEventEmitterOnMethodCalled = false
        channel.internal.statesEventEmitter.testSuite_injectIntoMethod(after: #selector(EventEmitter<Event, ChannelStateChange>.on(_:))) {
            statesEventEmitterOnMethodCalled = true
        }

        var emitCounter = 0
        channel.internal.statesEventEmitter.testSuite_injectIntoMethod(after: #selector(EventEmitter<Event, ChannelStateChange>.emit(_:with:))) {
            emitCounter += 1
        }

        var states = [channel.state]
        waitUntil(timeout: testTimeout) { done in
            channel.on { stateChange in
                XCTAssertEqual(stateChange.previous, states.last)
                XCTAssertEqual(channel.state, stateChange.current)
                states += [stateChange.current]

                switch stateChange.current {
                case .attached:
                    XCTAssertEqual(stateChange.event, ChannelEvent.attached)
                    XCTAssertNil(stateChange.reason)
                    channel.detach()
                case .detached:
                    XCTAssertEqual(stateChange.event, ChannelEvent.detached)
                    guard let error = stateChange.reason else {
                        fail("Detach state change reason is nil"); done(); return
                    }
                    expect(error.message).to(contain("channel has detached"))
                    done()
                default:
                    break
                }
            }
            channel.attach()
        }

        XCTAssertTrue(channelOnMethodCalled)
        XCTAssertTrue(statesEventEmitterOnMethodCalled)
        XCTAssertEqual(emitCounter, 4)

        if states.count != 5 {
            fail("Expecting 5 states; got \(states)")
            return
        }

        XCTAssertEqual(states[0].rawValue, RealtimeChannelState.initialized.rawValue, "Should be INITIALIZED state")
        XCTAssertEqual(states[1].rawValue, RealtimeChannelState.attaching.rawValue, "Should be ATTACHING state")
        XCTAssertEqual(states[2].rawValue, RealtimeChannelState.attached.rawValue, "Should be ATTACHED state")
        XCTAssertEqual(states[3].rawValue, RealtimeChannelState.detaching.rawValue, "Should be DETACHING state")
        XCTAssertEqual(states[4].rawValue, RealtimeChannelState.detached.rawValue, "Should be DETACHED state")
    }

    // RTL2a
    func test__004__Channel__EventEmitter__channel_states_and_events__should_implement_the_EventEmitter_and_emit_events_for_FAILED_state_changes() throws {
        let test = Test()
        let options = try AblyTests.clientOptions(for: test)
        options.token = try getTestToken(for: test, capability: "{\"secret\":[\"subscribe\"]}")
        let client = PubSubClient(options: options)
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(test.uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.on { stateChange in
                XCTAssertEqual(channel.state, stateChange.current)
                switch stateChange.current {
                case .attaching:
                    XCTAssertEqual(stateChange.event, ChannelEvent.attaching)
                    XCTAssertNil(stateChange.reason)
                    XCTAssertEqual(stateChange.previous, RealtimeChannelState.initialized)
                case .failed:
                    guard let reason = stateChange.reason else {
                        fail("Reason is nil"); done(); return
                    }
                    XCTAssertEqual(stateChange.event, ChannelEvent.failed)
                    XCTAssertEqual(reason.code, ErrorCode.operationNotPermittedWithProvidedCapability.intValue)
                    XCTAssertEqual(stateChange.previous, RealtimeChannelState.attaching)
                    done()
                default:
                    break
                }
            }
            channel.attach()
        }
    }

    // RTL2a
    func test__005__Channel__EventEmitter__channel_states_and_events__should_implement_the_EventEmitter_and_emit_events_for_SUSPENDED_state_changes() throws {
        let test = Test()
        let client = PubSubClient(options: try AblyTests.commonAppSetup(for: test))
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(test.uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                XCTAssertNil(error)
                done()
            }
        }

        client.simulateSuspended(beforeSuspension: { done in
            channel.once(.suspended) { stateChange in
                XCTAssertNil(stateChange.reason)
                XCTAssertEqual(stateChange.previous, RealtimeChannelState.attached)
                XCTAssertEqual(stateChange.event, ChannelEvent.suspended)
                XCTAssertEqual(channel.state, stateChange.current)
                done()
            }
        })
    }

    // RTL2g
    func test__006__Channel__EventEmitter__channel_states_and_events__can_emit_an_UPDATE_event() throws {
        let test = Test()
        let client = PubSubClient(options: try AblyTests.commonAppSetup(for: test))
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(test.uniqueChannelName())
        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                XCTAssertNil(error)
                done()
            }
        }

        channel.on(.attached) { _ in
            fail("Should not emit Attached again")
        }
        defer {
            channel.off()
        }

        waitUntil(timeout: testTimeout) { done in
            channel.on(.update) { stateChange in
                XCTAssertEqual(channel.state, RealtimeChannelState.attached)
                XCTAssertEqual(stateChange.previous, channel.state)
                XCTAssertEqual(stateChange.current, channel.state)
                XCTAssertEqual(stateChange.event, ChannelEvent.update)
                XCTAssertFalse(stateChange.resumed)
                XCTAssertNil(stateChange.reason)
                done()
            }

            let attachedMessage = ARTProtocolMessage()
            attachedMessage.action = .attached
            attachedMessage.channel = channel.name
            client.internal.transport?.receive(attachedMessage)
        }
    }

    // RTL2g + https://github.com/ably/ably-cocoa/issues/1088
    func test__007__Channel__EventEmitter__channel_states_and_events__should_not_emit_detached_event_on_an_already_detached_channel() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.logLevel = .debug
        let client = PubSubClient(options: options)
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(test.uniqueChannelName())

        channel.on { stateChange in
            XCTAssertNotEqual(stateChange.current, stateChange.previous)
        }
        defer {
            channel.off()
        }

        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                XCTAssertNil(error)
                done()
            }
        }

        waitUntil(timeout: testTimeout) { done in
            channel.detach { error in
                XCTAssertNil(error)
                done()
            }
        }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.closed) { stateChange in
                XCTAssertNil(stateChange.reason)
                done()
            }
            client.close()
        }
    }

    // RTL2b
    func test__008__Channel__EventEmitter__channel_states_and_events__state_attribute_should_be_the_current_state_of_the_channel() throws {
        let test = Test()
        let client = PubSubClient(options: try AblyTests.commonAppSetup(for: test))
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(test.uniqueChannelName())
        XCTAssertEqual(channel.state, RealtimeChannelState.initialized)

        channel.attach()
        XCTAssertEqual(channel.state, RealtimeChannelState.attaching)
        expect(channel.state).toEventually(equal(RealtimeChannelState.attached), timeout: testTimeout)
    }

    // RTL2c
    func test__009__Channel__EventEmitter__channel_states_and_events__should_contain_an_ErrorInfo_object_with_details_when_an_error_occurs() throws {
        let test = Test()
        let client = PubSubClient(options: try AblyTests.commonAppSetup(for: test))
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(test.uniqueChannelName())

        let pmError = AblyTests.newErrorProtocolMessage()
        waitUntil(timeout: testTimeout) { done in
            channel.on(.failed) { stateChange in
                guard let error = stateChange.reason else {
                    fail("Error is nil"); done(); return
                }
                XCTAssertEqual(error, pmError.error)
                XCTAssertEqual(channel.errorReason, pmError.error)
                done()
            }
            AblyTests.queue.async {
                channel.internal.onError(pmError)
            }
        }
    }

    // RTL2d
    func test__010__Channel__EventEmitter__channel_states_and_events__a_ChannelStateChange_is_emitted_as_the_first_argument_for_every_channel_state_change() throws {
        let test = Test()
        let client = PubSubClient(options: try AblyTests.commonAppSetup(for: test))
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(test.uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.on { stateChange in
                XCTAssertNil(stateChange.reason)
                XCTAssertEqual(stateChange.current, channel.state)
                XCTAssertNotEqual(stateChange.previous, channel.state)

                if stateChange.current == .attached {
                    done()
                }
            }
            channel.attach()
        }
        channel.off()

        waitUntil(timeout: testTimeout) { done in
            channel.once(.failed) { stateChange in
                XCTAssertNotNil(stateChange.reason)
                XCTAssertEqual(stateChange.current, RealtimeChannelState.failed)
                XCTAssertEqual(stateChange.previous, RealtimeChannelState.attached)
                done()
            }
            AblyTests.queue.async {
                channel.internal.onError(AblyTests.newErrorProtocolMessage())
            }
        }
    }

    // RTL2f (connection resumption case)
    func test__011a__Channel__EventEmitter__channel_states_and_events__ChannelStateChange_will_contain_a_resumed_boolean_attribute_with_value__true__if_the_bit_flag_RESUMED_was_included() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.tokenDetails = try getTestTokenDetails(for: test, ttl: 5.0)
        let client = PubSubClient(options: options)
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(test.uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(4, done: done)
            channel.on { stateChange in
                switch stateChange.current {
                case .attached:
                    XCTAssertFalse(stateChange.resumed)
                    partialDone()
                default:
                    XCTAssertFalse(stateChange.resumed)
                }
            }
            client.connection.once(.disconnected) { stateChange in
                channel.off()
                guard let error = stateChange.reason else {
                    fail("Error is nil"); done(); return
                }
                XCTAssertEqual(error.code, ErrorCode.tokenExpired.intValue)
                XCTAssertEqual(channel.state, RealtimeChannelState.attached)
                client.connection.once(.connected) { stateChange in
                    XCTAssertEqual(channel.state, RealtimeChannelState.attaching)
                    partialDone()
                }
                channel.on { stateChange in
                    switch stateChange.current {
                    case .attached:
                        XCTAssertTrue(stateChange.resumed)
                        partialDone()
                    default:
                        XCTAssertFalse(stateChange.resumed)
                    }
                }
                partialDone()
            }
            channel.attach()
        }
    }

    // RTL2f (connection recovery case)
    func test__011b__Channel__EventEmitter__channel_states_and_events__ChannelStateChange_will_contain_a_resumed_boolean_attribute_with_value__true__if_the_bit_flag_RESUMED_was_included_for_recovered_connection() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = PubSubClient(options: options)
        defer { client.dispose(); client.close() }

        let channelName = test.uniqueChannelName()
        let channel = client.channels.get(channelName)

        waitUntil(timeout: testTimeout) { done in
            channel.on { stateChange in
                switch stateChange.current {
                case .attached:
                    XCTAssertFalse(stateChange.resumed)
                    done()
                default:
                    XCTAssertFalse(stateChange.resumed)
                }
            }
            channel.attach()
            channel.publish(nil, data: "A message")
        }

        options.recover = client.connection.createRecoveryKey()

        let recoveredClient = PubSubClient(options: options)
        defer { recoveredClient.dispose(); recoveredClient.close() }

        let recoveredChannel = recoveredClient.channels.get(channelName)

        waitUntil(timeout: testTimeout) { done in
            recoveredChannel.on { stateChange in
                switch stateChange.current {
                case .attached:
                    XCTAssertTrue(stateChange.resumed)
                    done()
                default:
                    XCTAssertFalse(stateChange.resumed)
                }
            }
            recoveredChannel.attach()
        }
    }

    // RTL3

    // RTL3a

    func test__017__Channel__connection_state__changes_to_FAILED__ATTACHING_channel_should_transition_to_FAILED() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        options.testOptions.transportFactory = TestProxyTransportFactory()
        let client = PubSubClient(options: options)
        client.connect()
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(test.uniqueChannelName())
        channel.attach()
        let transport = client.internal.transport as! TestProxyTransport
        transport.actionsIgnored += [.attached]

        XCTAssertEqual(channel.state, RealtimeChannelState.attaching)

        waitUntil(timeout: testTimeout) { done in
            let pmError = AblyTests.newErrorProtocolMessage()
            channel.once(.failed) { stateChange in
                guard let error = stateChange.reason else {
                    fail("Reason error is nil"); done(); return
                }
                XCTAssertEqual(error, pmError.error)
                XCTAssertTrue(channel.errorReason === error)
                done()
            }
            client.internal.onError(pmError)
        }

        XCTAssertEqual(channel.state, RealtimeChannelState.failed)
    }

    func test__018__Channel__connection_state__changes_to_FAILED__ATTACHED_channel_should_transition_to_FAILED() throws {
        let test = Test()
        let client = PubSubClient(options: try AblyTests.commonAppSetup(for: test))
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(test.uniqueChannelName())
        channel.attach()
        expect(channel.state).toEventually(equal(RealtimeChannelState.attached), timeout: testTimeout)

        waitUntil(timeout: testTimeout) { done in
            let pmError = AblyTests.newErrorProtocolMessage()
            channel.once(.failed) { stateChange in
                guard let error = stateChange.reason else {
                    fail("Reason error is nil"); done(); return
                }
                XCTAssertEqual(error, pmError.error)
                XCTAssertEqual(channel.errorReason, error)
                done()
            }
            client.internal.onError(pmError)
        }

        XCTAssertEqual(channel.state, RealtimeChannelState.failed)
    }

    func test__019__Channel__connection_state__changes_to_FAILED__channel_being_released_waiting_for_DETACH_shouldn_t_crash__issue__918_() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        options.testOptions.transportFactory = TestProxyTransportFactory()
        let client = PubSubClient(options: options)
        client.connect()
        defer { client.dispose(); client.close() }

        // Force the callback on .release below to be triggered by our
        // forced FAILED message, not by a DETACHED.
        let transport = client.internal.transport as! TestProxyTransport
        transport.actionsIgnored += [.detached]

        var channel0Name = ""
        for i in 0 ..< 100 { // We need a few channels to trigger iterator invalidation.
            let channelName = test.uniqueChannelName(prefix: "channel\(i)")
            if i == 0 { channel0Name = channelName }
            let channel = client.channels.get(channelName)
            channel.attach() // No need to wait; ATTACHING state is good enough.
            expect(channel.state).toEventually(equal(RealtimeChannelState.attaching), timeout: testTimeout)
        }

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)

            client.channels.release(channel0Name) { _ in
                partialDone()
            }

            AblyTests.queue.async {
                let pmError = AblyTests.newErrorProtocolMessage()
                client.internal.onError(pmError)
                partialDone()
            }
        }
    }

    // TO3g
    func test__020__Channel__connection_state__changes_to_FAILED__should_immediately_fail_if_not_in_the_connected_state() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.queueMessages = false
        options.autoConnect = false
        let client = PubSubClient(options: options)
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(test.uniqueChannelName())
        waitUntil(timeout: testTimeout) { done in
            XCTAssertEqual(client.connection.state, .initialized)
            channel.publish(nil, data: "message") { error in
                XCTAssertEqual(error?.code, ErrorCode.invalidTransportHandle.intValue)
                expect(error?.message).to(contain("Invalid operation"))
                done()
            }
        }
        XCTAssertEqual(channel.state, .initialized)
        waitUntil(timeout: testTimeout) { done in
            client.connect()
            XCTAssertEqual(client.connection.state, .connecting)
            channel.publish(nil, data: "message") { error in
                XCTAssertEqual(error?.code, ErrorCode.invalidTransportHandle.intValue)
                expect(error?.message).to(contain("Invalid operation"))
                done()
            }
        }
    }

    // TO3g and https://github.com/ably/ably-cocoa/issues/1004
    func test__021__Channel__connection_state__changes_to_FAILED__should_keep_the_channels_attached_when_client_reconnected_successfully_and_queue_messages_is_disabled() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.queueMessages = false
        options.autoConnect = false
        let transportFactory = TestProxyTransportFactory()
        options.testOptions.transportFactory = transportFactory
        let client = PubSubClient(options: options)
        defer { client.dispose(); client.close() }
        client.internal.setReachabilityClass(TestReachability.self)
        let channel = client.channels.get(test.uniqueChannelName())

        client.connect()
        expect(client.connection.state).toEventually(equal(.connected), timeout: testTimeout)

        channel.attach()
        expect(channel.state).toEventually(equal(.attached), timeout: testTimeout)

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "message") { error in
                XCTAssertNil(error)
                done()
            }
        }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.disconnected) { stateChange in
                expect(stateChange.reason?.message).to(satisfyAnyOf(contain("unreachable host"), contain("network is down")))
                done()
            }
            client.simulateNoInternetConnection(transportFactory: transportFactory)
        }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { stateChange in
                XCTAssertEqual(stateChange.previous, .connecting)
                done()
            }
            client.simulateRestoreInternetConnection(transportFactory: transportFactory)
        }

        channel.off()
        expect(channel.state).toEventually(equal(RealtimeChannelState.attached), timeout: testTimeout)
    }

    // RTL3b

    func test__022__Channel__connection_state__changes_to_CLOSED__ATTACHING_channel_should_transition_to_DETACHED() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        options.testOptions.transportFactory = TestProxyTransportFactory()
        let client = PubSubClient(options: options)
        client.connect()
        defer { client.dispose(); client.close() }
        expect(client.connection.state).toEventually(equal(RealtimeConnectionState.connected), timeout: testTimeout)

        let channel = client.channels.get(test.uniqueChannelName())
        channel.attach()
        let transport = client.internal.transport as! TestProxyTransport
        transport.actionsIgnored += [.attached]

        XCTAssertEqual(channel.state, RealtimeChannelState.attaching)
        client.close()
        XCTAssertEqual(client.connection.state, RealtimeConnectionState.closing)
        expect(channel.state).toEventually(equal(RealtimeChannelState.detached), timeout: testTimeout)
        XCTAssertEqual(client.connection.state, RealtimeConnectionState.closed)
    }

    func test__023__Channel__connection_state__changes_to_CLOSED__ATTACHED_channel_should_transition_to_DETACHED() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = PubSubClient(options: options)
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(test.uniqueChannelName())
        channel.attach()

        expect(channel.state).toEventually(equal(RealtimeChannelState.attached), timeout: testTimeout)
        client.close()
        XCTAssertEqual(client.connection.state, RealtimeConnectionState.closing)
        expect(channel.state).toEventually(equal(RealtimeChannelState.detached), timeout: testTimeout)
        XCTAssertEqual(client.connection.state, RealtimeConnectionState.closed)
    }

    // RTL3c

    func test__024__Channel__connection_state__changes_to_SUSPENDED__ATTACHING_channel_should_transition_to_SUSPENDED() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        options.testOptions.transportFactory = TestProxyTransportFactory()
        let client = PubSubClient(options: options)
        client.connect()
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(test.uniqueChannelName())
        channel.attach()
        let transport = client.internal.transport as! TestProxyTransport
        transport.actionsIgnored += [.attached]

        expect(client.connection.state).toEventually(equal(RealtimeConnectionState.connected), timeout: testTimeout)
        XCTAssertEqual(channel.state, RealtimeChannelState.attaching)
        client.internal.onSuspended()
        XCTAssertEqual(channel.state, RealtimeChannelState.suspended)
    }

    func test__025__Channel__connection_state__changes_to_SUSPENDED__ATTACHED_channel_should_transition_to_SUSPENDED() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = PubSubClient(options: options)
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(test.uniqueChannelName())
        channel.attach()
        expect(channel.state).toEventually(equal(RealtimeChannelState.attached), timeout: testTimeout)
        client.internal.onSuspended()
        XCTAssertEqual(channel.state, RealtimeChannelState.suspended)
    }

    func test__026__Channel__connection_state__changes_to_SUSPENDED__channel_being_released_waiting_for_DETACH_shouldn_t_crash__issue__918_() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        options.testOptions.transportFactory = TestProxyTransportFactory()
        let client = PubSubClient(options: options)
        client.connect()
        defer { client.dispose(); client.close() }

        // Force the callback on .release below to be triggered by our
        // forced SUSPENDED message, not by a DETACHED.
        let transport = client.internal.transport as! TestProxyTransport
        transport.actionsIgnored += [.detached]

        var channel0Name = ""
        for i in 0 ..< 100 { // We need a few channels to trigger iterator invalidation.
            let channelName = test.uniqueChannelName(prefix: "channel\(i)")
            if i == 0 { channel0Name = channelName }
            let channel = client.channels.get(channelName)
            channel.attach() // No need to wait; ATTACHING state is good enough.
            expect(channel.state).toEventually(equal(RealtimeChannelState.attaching), timeout: testTimeout)
        }

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)

            client.channels.release(channel0Name) { _ in
                partialDone()
            }

            AblyTests.queue.async {
                client.internal.onSuspended()
                partialDone()
            }
        }
    }

    // RTL3d
    func test__013__Channel__connection_state__if_the_connection_state_enters_the_CONNECTED_state__then_a_SUSPENDED_channel_will_transition_to_ATTACHING_and_goes_back_to_SUSPNDED_on_timeout() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.testOptions.transportFactory = TestProxyTransportFactory()
        options.suspendedRetryTimeout = 1.0
        options.channelRetryTimeout = 1.0
        options.testOptions.realtimeRequestTimeout = 1.0
        let client = PubSubClient(options: options)
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(test.uniqueChannelName())
        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                XCTAssertNil(error)
                done()
            }
        }

        waitUntil(timeout: testTimeout) { done in
            channel.once(.suspended) { stateChange in
                XCTAssertNil(stateChange.reason)
                done()
            }
            delay(0) {
                client.internal.onSuspended()
            }
        }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { stateChange in
                XCTAssertNil(stateChange.reason)
                done()
            }
        }

        XCTAssertEqual(channel.state, RealtimeChannelState.attaching)

        let transport = client.internal.transport as! TestProxyTransport
        transport.actionsIgnored += [.attached]

        waitUntil(timeout: testTimeout) { done in
            let splitDone = AblyTests.splitDone(2, done: done)
            var wasSuspended = false
            channel.once(.suspended) { stateChange in
                XCTAssertEqual(stateChange.reason?.message.contains("attach timed out"), true)
                transport.actionsIgnored.removeAll()
                wasSuspended = true
                splitDone()
            }
            // make sure the channel will attach eventually (RTL4f)
            channel.once(.attached) { stateChange in
                XCTAssertTrue(wasSuspended)
                XCTAssertNil(stateChange.reason)
                splitDone()
            }
        }
    }

    // RTL3d - https://github.com/ably/ably-cocoa/issues/881
    func test__015__Channel__connection_state__should_attach_successfully_and_remain_attached_after_the_connection_goes_from_SUSPENDED_to_CONNECTED() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.disconnectedRetryTimeout = 0.5
        options.suspendedRetryTimeout = 3.0
        options.channelRetryTimeout = 0.5
        options.autoConnect = false
        let transportFactory = TestProxyTransportFactory()
        options.testOptions.transportFactory = transportFactory

        let client = PubSubClient(options: options)
        client.internal.setReachabilityClass(TestReachability.self)
        defer {
            client.simulateRestoreInternetConnection(transportFactory: transportFactory)
            client.dispose()
            client.close()
        }

        // Move to SUSPENDED
        let ttlHookToken = client.overrideConnectionStateTTL(3.0)
        defer { ttlHookToken.remove() }

        let channel = client.channels.get(test.uniqueChannelName())
        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                XCTAssertNil(error)
                done()
            }
            client.connect()
        }

        let oldConnectionId = client.connection.id

        waitUntil(timeout: testTimeout) { done in
            channel.once(.suspended) { stateChange in
                guard let error = stateChange.reason else {
                    fail("SUSPENDED reason should not be nil"); done(); return
                }
                expect(error.message).to(satisfyAnyOf(contain("network is down"), contain("unreachable host")))
                done()
            }
            client.simulateNoInternetConnection(transportFactory: transportFactory)
        }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { stateChange in
                XCTAssertNotEqual(oldConnectionId, client.connection.id) // didn't resumed
                done()
            }
            client.simulateRestoreInternetConnection(after: 1.0, transportFactory: transportFactory)
        }

        waitUntil(timeout: testTimeout) { done in
            channel.once(.attached) { stateChange in
                XCTAssertNil(stateChange.reason)
                channel.on(.suspended) { _ in
                    fail("Should not reach SUSPENDED state")
                }
                delay(3.0) {
                    // Wait some seconds to see if the channel doesn't change to SUSPENDED again
                    done()
                }
            }
        }
        channel.off()
    }

    // RTL3e
    func test__016__Channel__connection_state__if_the_connection_state_enters_the_DISCONNECTED_state__it_will_have_no_effect_on_the_channel_states() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.token = try getTestToken(for: test, ttl: 5.0)
        let client = PubSubClient(options: options)
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(test.uniqueChannelName())

        channel.once(.detached) { _ in
            fail("Should not reach the DETACHED state")
        }
        defer {
            channel.off()
        }

        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                XCTAssertNil(error)
                done()
            }
        }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.disconnected) { _ in
                XCTAssertEqual(channel.state, RealtimeChannelState.attached)
                done()
            }
        }
    }

    // RTL4

    // RTL4a
    func test__027__Channel__attach__if_already_ATTACHED_or_ATTACHING_nothing_is_done() throws {
        let test = Test()
        let client = PubSubClient(options: try AblyTests.commonAppSetup(for: test))
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(test.uniqueChannelName())

        channel.attach { errorInfo in
            XCTAssertNil(errorInfo)
        }
        XCTAssertEqual(channel.state, RealtimeChannelState.attaching)

        channel.attach { errorInfo in
            XCTAssertNil(errorInfo)
            XCTAssertEqual(channel.state, RealtimeChannelState.attached)
        }

        expect(channel.state).toEventually(equal(RealtimeChannelState.attached), timeout: testTimeout)

        waitUntil(timeout: testTimeout) { done in
            channel.attach { errorInfo in
                XCTAssertNil(errorInfo)
                XCTAssertEqual(channel.state, RealtimeChannelState.attached)
                done()
            }
        }
    }

    // RTL4e
    func test__028__Channel__attach__if_the_user_does_not_have_sufficient_permissions_to_attach__then_the_channel_will_transition_to_FAILED_and_set_the_errorReason() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.token = try getTestToken(for: test, key: options.key!, capability: "{\"restricted\":[\"*\"]}")
        let client = PubSubClient(options: options)
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(test.uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)
            channel.once(.failed) { stateChange in
                XCTAssertEqual(stateChange.reason?.code, ErrorCode.operationNotPermittedWithProvidedCapability.intValue)
                partialDone()
            }
            channel.attach { error in
                guard let error = error else {
                    fail("Error is nil"); partialDone(); return
                }
                XCTAssertEqual(error.code, ErrorCode.operationNotPermittedWithProvidedCapability.intValue)
                partialDone()
            }
        }

        XCTAssertEqual(channel.state, RealtimeChannelState.failed)
        XCTAssertEqual(channel.errorReason?.code, ErrorCode.operationNotPermittedWithProvidedCapability.intValue)
    }

    // RTL4g
    func test__029__Channel__attach__if_the_channel_is_in_the_FAILED_state__the_attach_request_sets_its_errorReason_to_null__and_proceeds_with_a_channel_attach() throws {
        let test = Test()
        let client = PubSubClient(options: try AblyTests.commonAppSetup(for: test))
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(test.uniqueChannelName())

        channel.attach()
        expect(channel.state).toEventually(equal(RealtimeChannelState.attached), timeout: testTimeout)

        let errorMsg = AblyTests.newErrorProtocolMessage()
        errorMsg.channel = channel.name
        client.internal.onError(errorMsg)
        XCTAssertEqual(channel.state, RealtimeChannelState.failed)
        XCTAssertNotNil(channel.errorReason)

        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                XCTAssertNil(error)
                done()
            }
        }

        XCTAssertEqual(channel.state, RealtimeChannelState.attached)
        XCTAssertNil(channel.errorReason)
    }

    // RTL4b

    func test__039__Channel__attach__results_in_an_error_if_the_connection_state_is__CLOSING() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        options.testOptions.transportFactory = TestProxyTransportFactory()
        let client = PubSubClient(options: options)
        client.connect()
        defer { client.dispose(); client.close() }

        expect(client.connection.state).toEventually(equal(RealtimeConnectionState.connected), timeout: testTimeout)
        let transport = client.internal.transport as! TestProxyTransport
        transport.actionsIgnored += [.closed]

        let channel = client.channels.get(test.uniqueChannelName())

        client.close()
        XCTAssertEqual(client.connection.state, RealtimeConnectionState.closing)

        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                XCTAssertNotNil(error)
                done()
            }
        }
    }

    func test__040__Channel__attach__results_in_an_error_if_the_connection_state_is__CLOSED() throws {
        let test = Test()
        let client = PubSubClient(options: try AblyTests.commonAppSetup(for: test))
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(test.uniqueChannelName())

        client.close()
        expect(client.connection.state).toEventually(equal(RealtimeConnectionState.closed), timeout: testTimeout)

        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                XCTAssertNotNil(error)
                done()
            }
        }
    }

    func test__041__Channel__attach__results_in_an_error_if_the_connection_state_is__SUSPENDED() throws {
        let test = Test()
        let client = AblyTests.newRealtime(try AblyTests.commonAppSetup(for: test)).client
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(test.uniqueChannelName())
        client.internal.onSuspended()
        XCTAssertEqual(client.connection.state, RealtimeConnectionState.suspended)
        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                XCTAssertNotNil(error)
                done()
            }
        }
    }

    func test__042__Channel__attach__results_in_an_error_if_the_connection_state_is__FAILED() throws {
        let test = Test()
        let client = PubSubClient(options: try AblyTests.commonAppSetup(for: test))
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(test.uniqueChannelName())
        client.internal.onError(AblyTests.newErrorProtocolMessage())
        XCTAssertEqual(client.connection.state, RealtimeConnectionState.failed)
        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                XCTAssertNotNil(error)
                done()
            }
        }
    }

    // RTL4i

    func test__043__Channel__attach__happens_when_connection_is_CONNECTED_if_it_s_currently__INITIALIZED() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        let client = PubSubClient(options: options)
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(test.uniqueChannelName())
        XCTAssertEqual(client.connection.state, .initialized)
        waitUntil(timeout: testTimeout) { done in
            channel.on(.attached) { stateChange in
                XCTAssertEqual(client.connection.state, .connected)
                XCTAssertNil(stateChange.reason)
                done()
            }
            client.connect()
            channel.attach()
        }
        XCTAssertEqual(channel.state, .attached)
    }

    func test__044__Channel__attach__happens_when_connection_is_CONNECTED_if_it_s_currently__CONNECTING() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        let client = PubSubClient(options: options)
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(test.uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            client.connect()
            XCTAssertEqual(client.connection.state, RealtimeConnectionState.connecting)

            channel.attach { error in
                XCTAssertEqual(client.connection.state, RealtimeConnectionState.connected)
                XCTAssertNil(error)
                done()
            }
        }
    }

    func test__045__Channel__attach__happens_when_connection_is_CONNECTED_if_it_s_currently__DISCONNECTED() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = PubSubClient(options: options)
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(test.uniqueChannelName())

        expect(client.connection.state).toEventually(equal(RealtimeConnectionState.connected), timeout: testTimeout)

        waitUntil(timeout: testTimeout) { done in
            client.internal.onDisconnected()
            XCTAssertEqual(client.connection.state, RealtimeConnectionState.disconnected)

            channel.attach { error in
                XCTAssertEqual(client.connection.state, RealtimeConnectionState.connected)
                XCTAssertNil(error)
                done()
            }
        }
    }

    // RTL4c
    func test__030__Channel__attach__should_send_an_ATTACH_ProtocolMessage__change_state_to_ATTACHING_and_change_state_to_ATTACHED_after_confirmation() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        options.testOptions.transportFactory = TestProxyTransportFactory()
        let client = PubSubClient(options: options)
        client.connect()
        defer { client.dispose(); client.close() }

        expect(client.connection.state).toEventually(equal(RealtimeConnectionState.connected), timeout: testTimeout)
        let transport = client.internal.transport as! TestProxyTransport

        let channel = client.channels.get(test.uniqueChannelName())
        channel.attach()

        XCTAssertEqual(channel.state, RealtimeChannelState.attaching)
        XCTAssertEqual(transport.protocolMessagesSent.filter { $0.action == .attach }.count, 1)

        expect(channel.state).toEventually(equal(RealtimeChannelState.attached), timeout: testTimeout)
        XCTAssertEqual(transport.protocolMessagesReceived.filter { $0.action == .attached }.count, 1)
    }

    // RTL4c1
    func test__202__Channel__attach__protocol_message_channelSerial_must_be_set_to_channelSerial_of_the_most_recent_protocol_message_or_omitted_if_no_previous_protocol_message_received() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        let transportFactory = TestProxyTransportFactory()
        options.testOptions.transportFactory = transportFactory

        let client = PubSubClient(options: options)
        client.internal.setReachabilityClass(TestReachability.self)
        client.connect()
        defer { client.dispose(); client.close() }

        let latestAttachProtocolMessage: () throws -> ARTProtocolMessage = {
            let transport = try XCTUnwrap(client.internal.transport as? TestProxyTransport)
            let protocolAttachMessagesSent = transport.protocolMessagesSent.filter { $0.action == .attach }
            return try XCTUnwrap(protocolAttachMessagesSent.last)
        }

        expect(client.connection.state).toEventually(equal(RealtimeConnectionState.connected), timeout: testTimeout)

        let channel = client.channels.get(test.uniqueChannelName())
        channel.attach()

        expect(channel.state).to(equal(RealtimeChannelState.attaching))

        let firstProtocolAttachMessage = try latestAttachProtocolMessage()
        expect(firstProtocolAttachMessage.channelSerial).to(beNil())
        expect(channel.state).toEventually(equal(RealtimeChannelState.attached), timeout: testTimeout)

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)
            channel.subscribe { message in
                expect(message.data as? String).to(equal("message"))
                partialDone()
            }
            channel.publish(nil, data: "message") { error in
                expect(error).to(beNil())
                partialDone()
            }
        }
        expect(channel.internal.channelSerial).toEventuallyNot(beNil())

        client.simulateNoInternetConnection(transportFactory: transportFactory)
        client.simulateRestoreInternetConnection(after: 0.1, transportFactory: transportFactory)

        expect(client.connection.state).toEventually(equal(RealtimeConnectionState.disconnected), timeout: testTimeout)
        expect(client.connection.state).toEventually(equal(RealtimeConnectionState.connected), timeout: testTimeout)
        expect(channel.state).toEventually(equal(RealtimeChannelState.attached), timeout: testTimeout)

        let secondProtocolAttachMessage = try latestAttachProtocolMessage()
        expect(secondProtocolAttachMessage.channelSerial).to(equal(channel.internal.channelSerial))
    }

    // RTL4e
    func test__031__Channel__attach__should_transition_the_channel_state_to_FAILED_if_the_user_does_not_have_sufficient_permissions() throws {
        let test = Test()
        let options = try AblyTests.clientOptions(for: test)
        options.token = try getTestToken(for: test, capability: "{ \"main\":[\"subscribe\"] }")
        let client = PubSubClient(options: options)
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(test.uniqueChannelName())
        channel.attach()

        waitUntil(timeout: testTimeout) { done in
            channel.once(.failed) { stateChange in
                guard let error = stateChange.reason else {
                    fail("Reason error is nil"); done(); return
                }
                XCTAssertEqual(error.code, ErrorCode.operationNotPermittedWithProvidedCapability.intValue)
                done()
            }
        }

        XCTAssertEqual(channel.errorReason!.code, ErrorCode.operationNotPermittedWithProvidedCapability.intValue)
        XCTAssertEqual(channel.state, RealtimeChannelState.failed)
    }

    // RTL4f
    func test__032__Channel__attach__should_transition_the_channel_state_to_SUSPENDED_if_ATTACHED_ProtocolMessage_is_not_received() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.channelRetryTimeout = 1.0
        options.testOptions.realtimeRequestTimeout = 1.0
        let client = AblyTests.newRealtime(options).client
        defer { client.dispose(); client.close() }

        expect(client.connection.state).toEventually(equal(RealtimeConnectionState.connected), timeout: testTimeout)

        guard let transport = client.internal.transport as? TestProxyTransport else {
            fail("TestProxyTransport is not set"); return
        }
        transport.actionsIgnored += [.attached]

        let channel = client.channels.get(test.uniqueChannelName())
        waitUntil(timeout: testTimeout) { done in
            channel.attach { errorInfo in
                XCTAssertNotNil(errorInfo)
                XCTAssertEqual(errorInfo, channel.errorReason)
                done()
            }
        }
        expect(channel.state).toEventually(equal(RealtimeChannelState.suspended), timeout: testTimeout)
        XCTAssertNotNil(channel.errorReason)

        transport.actionsIgnored = []
        // Automatically re-attached
        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)
            channel.once(.attaching) { stateChange in
                XCTAssertNil(stateChange.reason)
                partialDone()
            }
            channel.once(.attached) { stateChange in
                XCTAssertNil(stateChange.reason)
                partialDone()
            }
        }
    }

    func test__033__Channel__attach__if_called_with_a_callback_should_call_it_once_attached() throws {
        let test = Test()
        let client = PubSubClient(options: try AblyTests.commonAppSetup(for: test))
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(test.uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.attach { errorInfo in
                XCTAssertNil(errorInfo)
                XCTAssertEqual(channel.state, RealtimeChannelState.attached)
                done()
            }
        }
    }

    func test__034__Channel__attach__if_called_with_a_callback_and_already_attaching_should_call_the_callback_once_attached() throws {
        let test = Test()
        let client = PubSubClient(options: try AblyTests.commonAppSetup(for: test))
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(test.uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.attach()
            XCTAssertEqual(channel.state, RealtimeChannelState.attaching)
            channel.attach { errorInfo in
                XCTAssertNil(errorInfo)
                XCTAssertEqual(channel.state, RealtimeChannelState.attached)
                done()
            }
        }
    }

    func test__035__Channel__attach__if_called_with_a_callback_and_already_attached_should_call_the_callback_with_nil_error() throws {
        let test = Test()
        let client = PubSubClient(options: try AblyTests.commonAppSetup(for: test))
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(test.uniqueChannelName())

        channel.attach()
        expect(channel.state).toEventually(equal(RealtimeChannelState.attached), timeout: testTimeout)

        waitUntil(timeout: testTimeout) { done in
            channel.attach { errorInfo in
                XCTAssertNil(errorInfo)
                done()
            }
        }
    }

    // RTL4h
    func test__036__Channel__attach__if_the_channel_is_in_a_pending_state_ATTACHING__do_the_attach_operation_after_the_completion_of_the_pending_request() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = PubSubClient(options: options)
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(test.uniqueChannelName())

        var attachedCount = 0
        channel.on(.attached) { stateChange in
            XCTAssertNil(stateChange.reason)
            attachedCount += 1
        }

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)
            channel.once(.attaching) { stateChange in
                XCTAssertNil(stateChange.reason)
                XCTAssertEqual(stateChange.current, RealtimeChannelState.attaching)
                XCTAssertEqual(stateChange.previous, RealtimeChannelState.initialized)
                channel.attach()
                partialDone()
            }
            channel.once(.attached) { stateChange in
                XCTAssertNil(stateChange.reason)
                partialDone()
            }
            channel.attach()
        }

        expect(attachedCount).toEventually(equal(1), timeout: testTimeout)
    }

    // RTL4h
    func test__037__Channel__attach__if_the_channel_is_in_a_pending_state_DETACHING__do_the_attach_operation_after_the_completion_of_the_pending_request() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = PubSubClient(options: options)
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(test.uniqueChannelName())
        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                XCTAssertNil(error)
                done()
            }
        }

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(4, done: done)
            channel.once(.detaching) { stateChange in
                XCTAssertNil(stateChange.reason)
                XCTAssertEqual(stateChange.current, RealtimeChannelState.detaching)
                XCTAssertEqual(stateChange.previous, RealtimeChannelState.attached)
                channel.attach()
                partialDone()
            }
            channel.once(.detached) { stateChange in
                expect(stateChange.reason?.message).to(contain("channel has detached"))
                XCTAssertEqual(stateChange.current, RealtimeChannelState.detached)
                XCTAssertEqual(stateChange.previous, RealtimeChannelState.detaching)
                partialDone()
            }
            channel.once(.attaching) { stateChange in
                XCTAssertNil(stateChange.reason)
                XCTAssertEqual(stateChange.current, RealtimeChannelState.attaching)
                XCTAssertEqual(stateChange.previous, RealtimeChannelState.detached)
                partialDone()
            }
            channel.once(.attached) { stateChange in
                XCTAssertNil(stateChange.reason)
                XCTAssertEqual(stateChange.current, RealtimeChannelState.attached)
                XCTAssertEqual(stateChange.previous, RealtimeChannelState.attaching)
                partialDone()
            }
            channel.detach()
        }
    }

    func test__038__Channel__attach__a_channel_in_DETACHING_can_actually_move_back_to_ATTACHED_if_it_fails_to_detach() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.testOptions.realtimeRequestTimeout = 1.0
        let client = AblyTests.newRealtime(options).client
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(test.uniqueChannelName())
        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                XCTAssertNil(error)
                done()
            }
        }

        guard let transport = client.internal.transport as? TestProxyTransport else {
            fail("TestProxyTransport is not set"); return
        }

        // Force timeout
        transport.actionsIgnored = [.detached]

        waitUntil(timeout: testTimeout) { done in
            channel.detach { error in
                guard let error = error else {
                    fail("Reason error is nil"); return
                }
                XCTAssertTrue(error.code == ARTState.detachTimedOut.rawValue)
                XCTAssertEqual(channel.state, RealtimeChannelState.attached)
                done()
            }
        }
    }

    // RTL4j

    func test__046__Channel__attach__attach_resume__should_pass_attach_resume_flag_in_attach_message() throws {
        let test = Test()
        let client = AblyTests.newRealtime(try AblyTests.commonAppSetup(for: test)).client
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(test.uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                XCTAssertNil(error)
                done()
            }
        }

        guard let transport = client.internal.transport as? TestProxyTransport else {
            fail("Expecting TestProxyTransport"); return
        }

        let channelOptions = RealtimeChannelOptions()
        channelOptions.modes = [.publish]

        waitUntil(timeout: testTimeout) { done in
            channel.setOptions(channelOptions) { error in
                XCTAssertNil(error)
                done()
            }
        }

        let attachMessages = transport.protocolMessagesSent.filter { $0.action == .attach }
        XCTAssertEqual(attachMessages.count, 2)

        guard let firstAttach = attachMessages.first else {
            fail("First ATTACH message is missing"); return
        }
        XCTAssertEqual(firstAttach.flags, 0)

        guard let lastAttach = attachMessages.last else {
            fail("Last ATTACH message is missing"); return
        }
        expect(lastAttach.flags & Int64(ARTProtocolMessageFlag.attachResume.rawValue)).to(beGreaterThan(0)) // true
    }

    // RTL4j1
    func test__047__Channel__attach__attach_resume__should_have_correct_AttachResume_value() throws {
        let test = Test()
        let client = PubSubClient(options: try AblyTests.commonAppSetup(for: test))
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(test.uniqueChannelName())

        // Initialized
        XCTAssertEqual(channel.internal.attachResume, attachResumeExpectedValues[channel.state])

        waitUntil(timeout: testTimeout) { done in
            channel.once(.failed) { _ in
                done()
            }
            AblyTests.queue.async {
                channel.internal.onError(AblyTests.newErrorProtocolMessage())
            }
        }

        // Failed
        XCTAssertEqual(channel.internal.attachResume, attachResumeExpectedValues[channel.state])

        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                XCTAssertNil(error)
                done()
            }
        }

        // Attached
        XCTAssertEqual(channel.internal.attachResume, attachResumeExpectedValues[channel.state])

        waitUntil(timeout: testTimeout) { done in
            channel.once(.detaching) { _ in
                // Detaching
                XCTAssertEqual(channel.internal.attachResume, attachResumeExpectedValues[channel.state])
                done()
            }
            channel.detach()
        }
    }

    // RTL4j2
    func test__048__Channel__attach__attach_resume__should_encode_correctly_the_AttachResume_flag() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)

        let channelName = test.uniqueChannelName()
        let client = PubSubClient(options: options)
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(channelName)

        waitUntil(timeout: testTimeout) { done in
            channel.publish("test", data: nil) { error in
                XCTAssertNil(error)
                done()
            }
        }

        let channelOptions = RealtimeChannelOptions()
        channelOptions.params = ["rewind": "1"]

        let client1 = PubSubClient(options: options)
        defer { client1.dispose(); client1.close() }
        let channelWithAttachResume = client1.channels.get(channelName, options: channelOptions)
        channelWithAttachResume.internal.attachResume = true
        waitUntil(timeout: testTimeout) { done in
            channelWithAttachResume.subscribe { _ in
                fail("Should not receive the previously-published message")
            }
            channelWithAttachResume.attach { error in
                XCTAssertNil(error)
            }
            delay(2.0) {
                // Wait some seconds to confirm that the message is not received
                done()
            }
        }

        let channelOptions2 = RealtimeChannelOptions()
        channelOptions2.params = ["rewind": "1"]
        channelOptions2.modes = [.subscribe]
        let client2 = PubSubClient(options: options)
        defer { client2.dispose(); client2.close() }
        let channelWithoutAttachResume = client2.channels.get(channelName, options: channelOptions2)
        waitUntil(timeout: testTimeout) { done in
            channelWithoutAttachResume.subscribe { message in
                XCTAssertEqual(message.name, "test")
                done()
            }
            channelWithoutAttachResume.attach()
        }
    }

    // RTL5a
    func test__049__Channel__detach__if_state_is_INITIALIZED_or_DETACHED_nothing_is_done() throws {
        let test = Test()
        let client = PubSubClient(options: try AblyTests.commonAppSetup(for: test))
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(test.uniqueChannelName())

        XCTAssertEqual(channel.state, RealtimeChannelState.initialized)
        channel.detach { errorInfo in
            XCTAssertNil(errorInfo)
        }
        XCTAssertEqual(channel.state, RealtimeChannelState.initialized)

        channel.attach()
        expect(channel.state).toEventually(equal(RealtimeChannelState.attaching), timeout: testTimeout)

        channel.detach { errorInfo in
            XCTAssertNil(errorInfo)
            XCTAssertEqual(channel.state, RealtimeChannelState.detached)
        }

        expect(channel.state).toEventually(equal(RealtimeChannelState.detached), timeout: testTimeout)

        waitUntil(timeout: testTimeout) { done in
            channel.detach { errorInfo in
                XCTAssertNil(errorInfo)
                XCTAssertEqual(channel.state, RealtimeChannelState.detached)
                done()
            }
        }
    }

    // RTL5i
    func test__050__Channel__detach__if_the_channel_is_in_a_pending_state_DETACHING__do_the_detach_operation_after_the_completion_of_the_pending_request() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = PubSubClient(options: options)
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(test.uniqueChannelName())
        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                XCTAssertNil(error)
                done()
            }
        }

        var detachedCount = 0
        channel.on(.detached) { _ in
            detachedCount += 1
        }

        var detachingCount = 0
        channel.on(.detaching) { _ in
            detachingCount += 1
        }

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)
            channel.once(.detaching) { stateChange in
                XCTAssertNil(stateChange.reason)
                XCTAssertEqual(stateChange.current, RealtimeChannelState.detaching)
                XCTAssertEqual(stateChange.previous, RealtimeChannelState.attached)
                channel.detach()
                partialDone()
            }
            channel.once(.detached) { stateChange in
                XCTAssertEqual(stateChange.current, RealtimeChannelState.detached)
                XCTAssertEqual(stateChange.previous, RealtimeChannelState.detaching)
                partialDone()
            }
            channel.detach()
        }

        waitUntil(timeout: testTimeout) { done in
            delay(1.0) {
                XCTAssertEqual(detachedCount, 1)
                XCTAssertEqual(detachingCount, 1)
                done()
            }
        }

        channel.off()
    }

    // RTL5i
    func test__051__Channel__detach__if_the_channel_is_in_a_pending_state_ATTACHING__do_the_detach_operation_after_the_completion_of_the_pending_request() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = PubSubClient(options: options)
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(test.uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(3, done: done)
            channel.once(.attaching) { stateChange in
                XCTAssertNil(stateChange.reason)
                XCTAssertEqual(stateChange.current, RealtimeChannelState.attaching)
                XCTAssertEqual(stateChange.previous, RealtimeChannelState.initialized)
                channel.detach()
                partialDone()
            }
            channel.once(.attached) { stateChange in
                XCTAssertNil(stateChange.reason)
                XCTAssertEqual(stateChange.current, RealtimeChannelState.attached)
                XCTAssertEqual(stateChange.previous, RealtimeChannelState.attaching)
                partialDone()
            }
            channel.once(.detaching) { stateChange in
                XCTAssertNil(stateChange.reason)
                XCTAssertEqual(stateChange.current, RealtimeChannelState.detaching)
                XCTAssertEqual(stateChange.previous, RealtimeChannelState.attached)
                partialDone()
            }
            channel.attach()
        }
    }

    // RTL5b
    func test__052__Channel__detach__results_in_an_error_if_the_connection_state_is_FAILED() throws {
        let test = Test()
        let client = PubSubClient(options: try AblyTests.commonAppSetup(for: test))
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(test.uniqueChannelName())
        client.internal.onError(AblyTests.newErrorProtocolMessage())
        XCTAssertEqual(client.connection.state, RealtimeConnectionState.failed)

        waitUntil(timeout: testTimeout) { done in
            channel.detach { errorInfo in
                XCTAssertEqual(errorInfo!.code, ErrorCode.channelOperationFailed.intValue)
                done()
            }
        }
    }

    // RTL5d
    func test__053__Channel__detach__should_send_a_DETACH_ProtocolMessage__change_state_to_DETACHING_and_change_state_to_DETACHED_after_confirmation() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        options.testOptions.transportFactory = TestProxyTransportFactory()
        let client = PubSubClient(options: options)
        client.connect()
        defer { client.dispose(); client.close() }

        expect(client.connection.state).toEventually(equal(RealtimeConnectionState.connected), timeout: testTimeout)
        let transport = client.internal.transport as! TestProxyTransport

        let channel = client.channels.get(test.uniqueChannelName())
        channel.attach()
        expect(channel.state).toEventually(equal(RealtimeChannelState.attached), timeout: testTimeout)
        channel.detach()

        XCTAssertEqual(channel.state, RealtimeChannelState.detaching)
        XCTAssertEqual(transport.protocolMessagesSent.filter { $0.action == .detach }.count, 1)

        expect(channel.state).toEventually(equal(RealtimeChannelState.detached), timeout: testTimeout)
        XCTAssertEqual(transport.protocolMessagesReceived.filter { $0.action == .detached }.count, 1)
    }

    // RTL5e
    func test__054__Channel__detach__if_called_with_a_callback_should_call_it_once_detached() throws {
        let test = Test()
        let client = PubSubClient(options: try AblyTests.commonAppSetup(for: test))
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(test.uniqueChannelName())

        channel.attach()
        expect(channel.state).toEventually(equal(RealtimeChannelState.attached), timeout: testTimeout)

        waitUntil(timeout: testTimeout) { done in
            channel.detach { errorInfo in
                XCTAssertNil(errorInfo)
                XCTAssertEqual(channel.state, RealtimeChannelState.detached)
                done()
            }
        }
    }

    // RTL5e
    func test__055__Channel__detach__if_called_with_a_callback_and_already_detaching_should_call_the_callback_once_detached() throws {
        let test = Test()
        let client = PubSubClient(options: try AblyTests.commonAppSetup(for: test))
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(test.uniqueChannelName())

        channel.attach()
        expect(channel.state).toEventually(equal(RealtimeChannelState.attached), timeout: testTimeout)

        waitUntil(timeout: testTimeout) { done in
            channel.detach()
            XCTAssertEqual(channel.state, RealtimeChannelState.detaching)
            channel.detach { errorInfo in
                XCTAssertNil(errorInfo)
                XCTAssertEqual(channel.state, RealtimeChannelState.detached)
                done()
            }
        }
    }

    // RTL5e
    func test__056__Channel__detach__if_called_with_a_callback_and_already_detached_should_should_call_the_callback_with_nil_error() throws {
        let test = Test()
        let client = PubSubClient(options: try AblyTests.commonAppSetup(for: test))
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(test.uniqueChannelName())

        channel.attach()
        expect(channel.state).toEventually(equal(RealtimeChannelState.attached), timeout: testTimeout)
        channel.detach()
        expect(channel.state).toEventually(equal(RealtimeChannelState.detached), timeout: testTimeout)

        waitUntil(timeout: testTimeout) { done in
            channel.detach { errorInfo in
                XCTAssertNil(errorInfo)
                done()
            }
        }
    }

    // RTL5f
    func test__057__Channel__detach__if_a_DETACHED_is_not_received_within_the_default_realtime_request_timeout__the_detach_request_should_be_treated_as_though_it_has_failed_and_the_channel_will_return_to_its_previous_state() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        options.testOptions.realtimeRequestTimeout = 1.0
        options.testOptions.transportFactory = TestProxyTransportFactory()
        let client = PubSubClient(options: options)
        client.connect()
        defer { client.dispose(); client.close() }

        expect(client.connection.state).toEventually(equal(RealtimeConnectionState.connected), timeout: testTimeout)
        let transport = client.internal.transport as! TestProxyTransport
        transport.actionsIgnored += [.detached]

        let channel = client.channels.get(test.uniqueChannelName())
        channel.attach()
        expect(channel.state).toEventually(equal(RealtimeChannelState.attached), timeout: testTimeout)

        var callbackCalled = false
        channel.detach { error in
            guard let error = error else {
                fail("Error is nil"); return
            }
            XCTAssertTrue(error.code == ARTState.detachTimedOut.rawValue)
            XCTAssertEqual(error, channel.errorReason)
            callbackCalled = true
        }
        let start = NSDate()
        expect(channel.state).toEventually(equal(RealtimeChannelState.attached), timeout: testTimeout)
        XCTAssertNotNil(channel.errorReason)
        expect(callbackCalled).toEventually(beTrue(), timeout: testTimeout)
        let end = NSDate()
        expect(start.addingTimeInterval(1.0)).to(beCloseTo(end, within: 0.5))
    }

    // RTL5g

    func test__059__Channel__detach__results_in_an_error_if_the_connection_state_is__CLOSING() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        options.testOptions.transportFactory = TestProxyTransportFactory()
        let client = PubSubClient(options: options)
        client.connect()
        defer { client.dispose(); client.close() }

        expect(client.connection.state).toEventually(equal(RealtimeConnectionState.connected), timeout: testTimeout)
        let transport = client.internal.transport as! TestProxyTransport
        transport.actionsIgnored += [.closed]

        let channel = client.channels.get(test.uniqueChannelName())
        channel.attach()
        expect(channel.state).toEventually(equal(RealtimeChannelState.attached), timeout: testTimeout)

        client.close()
        XCTAssertEqual(client.connection.state, RealtimeConnectionState.closing)

        waitUntil(timeout: testTimeout) { done in
            channel.detach { error in
                XCTAssertNotNil(error)
                done()
            }
        }
    }

    func test__060__Channel__detach__results_in_an_error_if_the_connection_state_is__FAILED() throws {
        let test = Test()
        let client = PubSubClient(options: try AblyTests.commonAppSetup(for: test))
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(test.uniqueChannelName())
        channel.attach()
        expect(channel.state).toEventually(equal(RealtimeChannelState.attached), timeout: testTimeout)

        client.internal.onError(AblyTests.newErrorProtocolMessage())
        XCTAssertEqual(client.connection.state, RealtimeConnectionState.failed)
        waitUntil(timeout: testTimeout) { done in
            channel.detach { error in
                XCTAssertNotNil(error)
                done()
            }
        }
    }

    // RTL5h

    func test__061__Channel__detach__happens_when_channel_is_ATTACHED_if_connection_is_currently__INITIALIZED() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        let client = PubSubClient(options: options)
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(test.uniqueChannelName())
        waitUntil(timeout: testTimeout) { done in
            channel.attach()
            XCTAssertEqual(channel.state, RealtimeChannelState.attaching)
            XCTAssertEqual(client.connection.state, RealtimeConnectionState.initialized)

            channel.detach { error in
                XCTAssertNil(error)
                done()
            }

            client.connect()
        }
    }

    func test__062__Channel__detach__happens_when_channel_is_ATTACHED_if_connection_is_currently__CONNECTING() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        let client = PubSubClient(options: options)
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(test.uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            client.connect()
            channel.attach()
            XCTAssertEqual(client.connection.state, RealtimeConnectionState.connecting)
            XCTAssertEqual(channel.state, RealtimeChannelState.attaching)

            channel.detach { error in
                XCTAssertNil(error)
                done()
            }
        }
    }

    func test__063__Channel__detach__happens_when_channel_is_ATTACHED_if_connection_is_currently__DISCONNECTED() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = PubSubClient(options: options)
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(test.uniqueChannelName())

        expect(client.connection.state).toEventually(equal(RealtimeConnectionState.connected), timeout: testTimeout)

        waitUntil(timeout: testTimeout) { done in
            client.internal.onDisconnected()
            channel.attach()
            XCTAssertEqual(client.connection.state, RealtimeConnectionState.disconnected)
            XCTAssertEqual(channel.state, RealtimeChannelState.attaching)

            channel.detach { error in
                XCTAssertEqual(client.connection.state, RealtimeConnectionState.connected)
                XCTAssertNil(error)
                done()
            }
        }
    }

    // RTL5j
    func test__058__Channel__detach__if_the_channel_state_is_SUSPENDED__the__detach__request_transitions_the_channel_immediately_to_the_DETACHED_state() throws {
        let test = Test()
        let client = PubSubClient(options: try AblyTests.commonAppSetup(for: test))
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(test.uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                XCTAssertNil(error)
                done()
            }
        }

        channel.internal.setSuspended(.init(state: .ok))
        XCTAssertEqual(channel.state, RealtimeChannelState.suspended)

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)
            channel.once(.detached) { stateChange in
                XCTAssertNil(stateChange.reason)
                XCTAssertEqual(stateChange.current, RealtimeChannelState.detached)
                XCTAssertEqual(stateChange.previous, RealtimeChannelState.suspended)
                partialDone()
            }
            channel.detach { error in
                XCTAssertNil(error)
                partialDone()
            }
        }

        XCTAssertEqual(channel.state, RealtimeChannelState.detached)
    }

    // RTL6

    // RTL6a
    func test__064__Channel__publish__should_encode_messages_in_the_same_way_as_the_RestChannel() throws {
        let test = Test()
        let data = ["value": 1]

        let channelName = test.uniqueChannelName()

        let rest = HttpClient(options: try AblyTests.commonAppSetup(for: test))
        let restChannel = rest.channels.get(channelName)

        var restEncodedMessage: Message?
        restChannel.internal.testSuite_getReturnValue(from: NSSelectorFromString("encodeMessageIfNeeded:error:")) { value in
            restEncodedMessage = value as? Message
        }

        waitUntil(timeout: testTimeout) { done in
            restChannel.publish(nil, data: data) { errorInfo in
                XCTAssertNil(errorInfo)
                done()
            }
        }

        let realtime = PubSubClient(options: try AblyTests.commonAppSetup(for: test))
        defer { realtime.close() }
        let realtimeChannel = realtime.channels.get(channelName)
        realtimeChannel.attach()
        expect(realtimeChannel.state).toEventually(equal(RealtimeChannelState.attached), timeout: testTimeout)

        var realtimeEncodedMessage: Message?
        realtimeChannel.internal.testSuite_getReturnValue(from: NSSelectorFromString("encodeMessageIfNeeded:error:")) { value in
            realtimeEncodedMessage = value as? Message
        }

        waitUntil(timeout: testTimeout) { done in
            realtimeChannel.publish(nil, data: data) { errorInfo in
                XCTAssertNil(errorInfo)
                done()
            }
        }

        XCTAssertEqual(restEncodedMessage!.data as? NSObject, realtimeEncodedMessage!.data as? NSObject)
        XCTAssertNotNil(restEncodedMessage!.data)
        XCTAssertNotNil(realtimeEncodedMessage!.data)
        XCTAssertEqual(restEncodedMessage!.encoding, realtimeEncodedMessage!.encoding)
        XCTAssertNotNil(restEncodedMessage!.encoding)
        XCTAssertNotNil(realtimeEncodedMessage!.encoding)
    }

    // RTL6b

    func test__067__Channel__publish__should_invoke_callback__when_the_message_is_successfully_delivered() throws {
        let test = Test()
        let client = PubSubClient(options: try AblyTests.commonAppSetup(for: test))
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.on { stateChange in
                let state = stateChange.current
                let error = stateChange.reason
                XCTAssertNil(error)
                if state == .connected {
                    let channel = client.channels.get(test.uniqueChannelName())
                    channel.on { stateChange in
                        if stateChange.current == .attached {
                            channel.publish(nil, data: "message") { errorInfo in
                                XCTAssertNil(errorInfo)
                                done()
                            }
                        }
                    }
                    channel.attach()
                }
            }
        }
    }

    func test__068__Channel__publish__should_invoke_callback__upon_failure() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let channelname = test.uniqueChannelName()
        options.token = try getTestToken(for: test, key: options.key, capability: "{ \"\(options.testOptions.channelNamePrefix!)-\(channelname)\":[\"subscribe\"] }")
        let client = PubSubClient(options: options)
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.on { stateChange in
                let state = stateChange.current
                let error = stateChange.reason
                XCTAssertNil(error)
                if state == .connected {
                    let channel = client.channels.get(channelname)
                    channel.on { stateChange in
                        if stateChange.current == .attached {
                            channel.publish(nil, data: "message") { errorInfo in
                                XCTAssertNotNil(errorInfo)
                                guard let errorInfo = errorInfo else {
                                    XCTFail("ErrorInfo is nil"); done(); return
                                }
                                // Unable to perform channel operation
                                XCTAssertEqual(errorInfo.code, ErrorCode.operationNotPermittedWithProvidedCapability.intValue)
                                done()
                            }
                        }
                    }
                    channel.attach()
                }
            }
        }
    }

    func test__069__Channel__publish__should_invoke_callback__for_all_messages_published() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)

        let channelToSucceedName = test.uniqueChannelName(prefix: "channelToSucceed")
        let channelToFailName = test.uniqueChannelName(prefix: "channelToFail")

        options.token = try getTestToken(for: test, key: options.key, capability: "{ \"\(options.testOptions.channelNamePrefix!)-\(channelToSucceedName)\":[\"subscribe\", \"publish\"], \"\(options.testOptions.channelNamePrefix!)-\(channelToFailName)\":[\"subscribe\"] }")

        let client = PubSubClient(options: options)
        defer { client.dispose(); client.close() }

        struct TotalMessages {
            static let expected = 50
            var succeeded = 0
            var failed = 0
        }

        var totalMessages = TotalMessages()

        let channelToSucceed = client.channels.get(channelToSucceedName)
        channelToSucceed.on { stateChange in
            if stateChange.current == .attached {
                for index in 1 ... TotalMessages.expected {
                    channelToSucceed.publish(nil, data: "message\(index)") { errorInfo in
                        if errorInfo == nil {
                            totalMessages.succeeded += 1
                            XCTAssertEqual(index, totalMessages.succeeded, "Callback was invoked with an invalid sequence")
                        }
                    }
                }
            }
        }
        channelToSucceed.attach()

        let channelToFail = client.channels.get(channelToFailName)
        channelToFail.on { stateChange in
            if stateChange.current == .attached {
                for index in 1 ... TotalMessages.expected {
                    channelToFail.publish(nil, data: "message\(index)") { errorInfo in
                        if errorInfo != nil {
                            totalMessages.failed += 1
                            XCTAssertEqual(index, totalMessages.failed, "Callback was invoked with an invalid sequence")
                        }
                    }
                }
            }
        }
        channelToFail.attach()

        expect(totalMessages.succeeded).toEventually(equal(TotalMessages.expected), timeout: testTimeout)
        expect(totalMessages.failed).toEventually(equal(TotalMessages.expected), timeout: testTimeout)
    }

    // RTL6c

    // RTL6c1

    func test__071__Channel__publish__Connection_state_conditions__if_the_connection_is_CONNECTED_and_the_channel_is__ATTACHED_then_the_messages_should_be_published_immediately() throws {
        let test = Test()
        let client = AblyTests.newRealtime(try AblyTests.commonAppSetup(for: test)).client
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(test.uniqueChannelName())
        channel.attach()

        expect(channel.state).toEventually(equal(RealtimeChannelState.attached), timeout: testTimeout)
        XCTAssertEqual(client.connection.state, RealtimeConnectionState.connected)

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "message") { error in
                XCTAssertNil(error)
                done()
            }
            XCTAssertEqual((client.internal.transport as! TestProxyTransport).protocolMessagesSent.filter { $0.action == .message }.count, 1)
        }
    }

    func test__072__Channel__publish__Connection_state_conditions__if_the_connection_is_CONNECTED_and_the_channel_is__INITIALIZED_then_the_messages_should_be_published_immediately() throws {
        let test = Test()
        let client = AblyTests.newRealtime(try AblyTests.commonAppSetup(for: test)).client
        defer { client.dispose(); client.close() }
        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { _ in
                done()
            }
        }
        let channel = client.channels.get(test.uniqueChannelName())
        XCTAssertEqual(channel.state, RealtimeChannelState.initialized)
        XCTAssertEqual(client.connection.state, RealtimeConnectionState.connected)

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "message") { error in
                XCTAssertNil(error)
                done()
            }
            XCTAssertEqual(client.internal.queuedMessages.count, 0)
            XCTAssertEqual((client.internal.transport as! TestProxyTransport).protocolMessagesSent.filter { $0.action == .message }.count, 1)
        }

        XCTAssertEqual(channel.state, RealtimeChannelState.initialized)
    }

    func test__073__Channel__publish__Connection_state_conditions__if_the_connection_is_CONNECTED_and_the_channel_is__DETACHED_then_the_messages_should_be_published_immediately() throws {
        let test = Test()
        let client = AblyTests.newRealtime(try AblyTests.commonAppSetup(for: test)).client
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(test.uniqueChannelName())
        waitUntil(timeout: testTimeout) { done in
            channel.attach { _ in
                done()
            }
        }
        waitUntil(timeout: testTimeout) { done in
            channel.detach { _ in
                done()
            }
        }
        XCTAssertEqual(channel.state, RealtimeChannelState.detached)
        XCTAssertEqual(client.connection.state, RealtimeConnectionState.connected)

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "message") { error in
                XCTAssertNil(error)
                done()
            }
            XCTAssertEqual((client.internal.transport as! TestProxyTransport).protocolMessagesSent.filter { $0.action == .message }.count, 1)
        }

        XCTAssertEqual(channel.state, RealtimeChannelState.detached)
    }

    func test__074__Channel__publish__Connection_state_conditions__if_the_connection_is_CONNECTED_and_the_channel_is__ATTACHING_then_the_messages_should_be_published_immediately() throws {
        let test = Test()
        let client = AblyTests.newRealtime(try AblyTests.commonAppSetup(for: test)).client
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(test.uniqueChannelName())
        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { _ in
                done()
            }
        }
        channel.attach()
        XCTAssertEqual(channel.state, RealtimeChannelState.attaching)
        guard let transport = client.internal.transport as? TestProxyTransport else {
            fail("Expecting TestProxyTransport"); return
        }
        transport.actionsIgnored += [.attached]

        waitUntil(timeout: testTimeout) { done in
            XCTAssertEqual(channel.state, RealtimeChannelState.attaching)
            channel.publish(nil, data: "message") { error in
                XCTAssertNil(error)
                done()
            }
            XCTAssertEqual(client.internal.queuedMessages.count, 0)
            XCTAssertEqual((client.internal.transport as! TestProxyTransport).protocolMessagesSent.filter { $0.action == .message }.count, 1)
        }

        XCTAssertEqual(channel.state, RealtimeChannelState.attaching)
    }

    func test__075__Channel__publish__Connection_state_conditions__if_the_connection_is_CONNECTED_and_the_channel_is__DETACHING_then_the_messages_should_be_published_immediately() throws {
        let test = Test()
        let client = AblyTests.newRealtime(try AblyTests.commonAppSetup(for: test)).client
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(test.uniqueChannelName())
        waitUntil(timeout: testTimeout) { done in
            channel.attach { _ in
                done()
            }
        }
        XCTAssertEqual(client.connection.state, RealtimeConnectionState.connected)
        channel.detach()
        XCTAssertEqual(channel.state, RealtimeChannelState.detaching)
        guard let transport = client.internal.transport as? TestProxyTransport else {
            fail("Expecting TestProxyTransport"); return
        }
        transport.actionsIgnored += [.detached]

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "message") { error in
                XCTAssertNil(error)
                done()
            }
            XCTAssertEqual((client.internal.transport as! TestProxyTransport).protocolMessagesSent.filter { $0.action == .message }.count, 1)
        }

        XCTAssertEqual(channel.state, RealtimeChannelState.detaching)
    }

    // RTL6c2

    func beforeEach__Channel__publish__Connection_state_conditions__the_message(for test: Test, channelName: String) throws {
        let options = try AblyTests.commonAppSetup(for: test)
        options.useTokenAuth = true
        options.autoConnect = false
        rtl6c2TestsClient = AblyTests.newRealtime(options).client
        rtl6c2TestsChannel = rtl6c2TestsClient.channels.get(channelName)
        XCTAssertTrue(rtl6c2TestsClient.internal.options.queueMessages)
    }

    func afterEach__Channel__publish__Connection_state_conditions__the_message() { rtl6c2TestsClient.close() }

    func test__076__Channel__publish__Connection_state_conditions__the_message__should_be_queued_and_delivered_as_soon_as_the_connection_state_returns_to_CONNECTED_if_the_connection_is__INITIALIZED() throws {
        let test = Test()
        try beforeEach__Channel__publish__Connection_state_conditions__the_message(for: test, channelName: test.uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            XCTAssertEqual(rtl6c2TestsClient.connection.state, RealtimeConnectionState.initialized)
            rtl16c2TestsPublish(done)
            rtl6c2TestsClient.connect()
            XCTAssertEqual(rtl6c2TestsClient.internal.queuedMessages.count, 1)
        }

        afterEach__Channel__publish__Connection_state_conditions__the_message()
    }

    func test__077__Channel__publish__Connection_state_conditions__the_message__should_be_queued_and_delivered_as_soon_as_the_connection_state_returns_to_CONNECTED_if_the_connection_is__CONNECTING() throws {
        let test = Test()
        try beforeEach__Channel__publish__Connection_state_conditions__the_message(for: test, channelName: test.uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            rtl6c2TestsClient.connect()
            XCTAssertEqual(rtl6c2TestsClient.connection.state, RealtimeConnectionState.connecting)
            rtl16c2TestsPublish(done)
            XCTAssertEqual(rtl6c2TestsClient.internal.queuedMessages.count, 1)
        }

        afterEach__Channel__publish__Connection_state_conditions__the_message()
    }

    func test__078__Channel__publish__Connection_state_conditions__the_message__should_be_queued_and_delivered_as_soon_as_the_connection_state_returns_to_CONNECTED_if_the_connection_is__DISCONNECTED() throws {
        let test = Test()
        try beforeEach__Channel__publish__Connection_state_conditions__the_message(for: test, channelName: test.uniqueChannelName())

        rtl6c2TestsClient.connect()
        expect(rtl6c2TestsClient.connection.state).toEventually(equal(RealtimeConnectionState.connected), timeout: testTimeout)
        rtl6c2TestsClient.internal.onDisconnected()

        waitUntil(timeout: testTimeout) { done in
            XCTAssertEqual(rtl6c2TestsClient.connection.state, RealtimeConnectionState.disconnected)
            rtl16c2TestsPublish(done)
            XCTAssertEqual(rtl6c2TestsClient.internal.queuedMessages.count, 1)
        }

        afterEach__Channel__publish__Connection_state_conditions__the_message()
    }

    // RTL6c4

    func beforeEach__Channel__publish__Connection_state_conditions__will_result_in_an_error_if_the(for test: Test, channelName: String) throws {
        try setupDependencies(for: test)
        Default.setConnectionStateTtl(0.3)
        rtl6c4TestsClient = AblyTests.newRealtime(options).client
        rtl6c4TestsChannel = rtl6c4TestsClient.channels.get(channelName)
    }

    func afterEach__Channel__publish__Connection_state_conditions__will_result_in_an_error_if_the() {
        rtl6c4TestsClient.close()
        Default.setConnectionStateTtl(previousConnectionStateTtl)
    }

    func test__082__Channel__publish__Connection_state_conditions__will_result_in_an_error_if_the__connection_is_SUSPENDED() throws {
        let test = Test()
        try beforeEach__Channel__publish__Connection_state_conditions__will_result_in_an_error_if_the(for: test, channelName: test.uniqueChannelName())

        rtl6c4TestsClient.connect()
        expect(rtl6c4TestsClient.connection.state).toEventually(equal(RealtimeConnectionState.connected), timeout: testTimeout)
        rtl6c4TestsClient.internal.onSuspended()
        expect(rtl6c4TestsClient.connection.state).toEventually(equal(RealtimeConnectionState.suspended), timeout: testTimeout)
        waitUntil(timeout: testTimeout) { done in
            rtl6c4TestsPublish(done)
        }

        afterEach__Channel__publish__Connection_state_conditions__will_result_in_an_error_if_the()
    }

    func test__083__Channel__publish__Connection_state_conditions__will_result_in_an_error_if_the__connection_is_CLOSING() throws {
        let test = Test()
        try beforeEach__Channel__publish__Connection_state_conditions__will_result_in_an_error_if_the(for: test, channelName: test.uniqueChannelName())

        rtl6c4TestsClient.connect()
        expect(rtl6c4TestsClient.connection.state).toEventually(equal(RealtimeConnectionState.connected), timeout: testTimeout)
        rtl6c4TestsClient.close()
        XCTAssertEqual(rtl6c4TestsClient.connection.state, RealtimeConnectionState.closing)
        waitUntil(timeout: testTimeout) { done in
            rtl6c4TestsPublish(done)
        }

        afterEach__Channel__publish__Connection_state_conditions__will_result_in_an_error_if_the()
    }

    func test__084__Channel__publish__Connection_state_conditions__will_result_in_an_error_if_the__connection_is_CLOSED() throws {
        let test = Test()
        try beforeEach__Channel__publish__Connection_state_conditions__will_result_in_an_error_if_the(for: test, channelName: test.uniqueChannelName())

        rtl6c4TestsClient.connect()
        expect(rtl6c4TestsClient.connection.state).toEventually(equal(RealtimeConnectionState.connected), timeout: testTimeout)
        rtl6c4TestsClient.close()
        expect(rtl6c4TestsClient.connection.state).toEventually(equal(RealtimeConnectionState.closed), timeout: testTimeout)
        waitUntil(timeout: testTimeout) { done in
            rtl6c4TestsPublish(done)
        }

        afterEach__Channel__publish__Connection_state_conditions__will_result_in_an_error_if_the()
    }

    func test__085__Channel__publish__Connection_state_conditions__will_result_in_an_error_if_the__connection_is_FAILED() throws {
        let test = Test()
        try beforeEach__Channel__publish__Connection_state_conditions__will_result_in_an_error_if_the(for: test, channelName: test.uniqueChannelName())

        rtl6c4TestsClient.connect()
        expect(rtl6c4TestsClient.connection.state).toEventually(equal(RealtimeConnectionState.connected), timeout: testTimeout)
        rtl6c4TestsClient.internal.onError(AblyTests.newErrorProtocolMessage())
        XCTAssertEqual(rtl6c4TestsClient.connection.state, RealtimeConnectionState.failed)
        waitUntil(timeout: testTimeout) { done in
            rtl6c4TestsPublish(done)
        }

        afterEach__Channel__publish__Connection_state_conditions__will_result_in_an_error_if_the()
    }

    func test__086__Channel__publish__Connection_state_conditions__will_result_in_an_error_if_the__channel_is_SUSPENDED() throws {
        let test = Test()
        try beforeEach__Channel__publish__Connection_state_conditions__will_result_in_an_error_if_the(for: test, channelName: test.uniqueChannelName())

        rtl6c4TestsClient.connect()
        rtl6c4TestsChannel.attach()
        expect(rtl6c4TestsChannel.state).toEventually(equal(RealtimeChannelState.attached), timeout: testTimeout)
        rtl6c4TestsChannel.internal.setSuspended(.init(state: .ok))
        expect(rtl6c4TestsChannel.state).toEventually(equal(RealtimeChannelState.suspended), timeout: testTimeout)
        waitUntil(timeout: testTimeout) { done in
            rtl6c4TestsPublish(done)
        }

        afterEach__Channel__publish__Connection_state_conditions__will_result_in_an_error_if_the()
    }

    func test__087__Channel__publish__Connection_state_conditions__will_result_in_an_error_if_the__channel_is_FAILED() throws {
        let test = Test()
        try beforeEach__Channel__publish__Connection_state_conditions__will_result_in_an_error_if_the(for: test, channelName: test.uniqueChannelName())

        rtl6c4TestsClient.connect()
        rtl6c4TestsChannel.attach()
        expect(rtl6c4TestsChannel.state).toEventually(equal(RealtimeChannelState.attached), timeout: testTimeout)
        let protocolError = AblyTests.newErrorProtocolMessage()
        rtl6c4TestsChannel.internal.onError(protocolError)
        expect(rtl6c4TestsChannel.state).toEventually(equal(RealtimeChannelState.failed), timeout: testTimeout)
        waitUntil(timeout: testTimeout) { done in
            rtl6c4TestsPublish(done)
        }

        afterEach__Channel__publish__Connection_state_conditions__will_result_in_an_error_if_the()
    }

    // RTL6c5
    func test__070__Channel__publish__Connection_state_conditions__publish_should_not_trigger_an_implicit_attach() throws {
        let test = Test()
        let client = PubSubClient(options: try AblyTests.commonAppSetup(for: test))
        defer { client.dispose(); client.close() }
        expect(client.connection.state).toEventually(equal(RealtimeConnectionState.connected), timeout: testTimeout)
        let channel = client.channels.get(test.uniqueChannelName())
        waitUntil(timeout: testTimeout) { done in
            let protocolError = AblyTests.newErrorProtocolMessage()
            XCTAssertEqual(channel.state, RealtimeChannelState.initialized)
            channel.publish(nil, data: "message") { error in
                XCTAssertEqual(channel.state, RealtimeChannelState.failed)

                channel.publish(nil, data: "message") { error in
                    XCTAssertEqual(channel.state, RealtimeChannelState.failed)
                    XCTAssertNotNil(error)
                    done()
                }
            }
            XCTAssertEqual(channel.state, RealtimeChannelState.initialized)
            AblyTests.queue.async {
                channel.internal.onError(protocolError)
            }
        }
    }

    // RTL6e

    // RTL6e1
    func test__095__Channel__publish__Unidentified_clients_using_Basic_Auth__should_have_the_provided_clientId_on_received_message_when_it_was_published_with_clientId() throws {
        let test = Test()
        let client = PubSubClient(options: try AblyTests.commonAppSetup(for: test))
        defer { client.dispose(); client.close() }

        XCTAssertNil(client.auth.clientId)

        let channel = client.channels.get(test.uniqueChannelName())

        var resultClientId: String?

        let message = Message(name: nil, data: "message")
        message.clientId = "client_string"

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)
            channel.subscribe { message in
                resultClientId = message.clientId
                partialDone()
            }
            channel.publish([message]) { errorInfo in
                XCTAssertNil(errorInfo)
                partialDone()
            }
        }

        expect(resultClientId).toEventually(equal(message.clientId), timeout: testTimeout)
    }

    // RTL6f
    func test__065__Channel__publish__Message_connectionId_should_match_the_current_Connection_id_for_all_published_messages() throws {
        let test = Test()
        let client = PubSubClient(options: try AblyTests.commonAppSetup(for: test))
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(test.uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.subscribe { message in
                XCTAssertEqual(message.connectionId, client.connection.id)
                done()
            }
            channel.publish(nil, data: "message")
        }
    }

    // RTL6i

    func test__096__Channel__publish__expect_either__an_array_of_Message_objects() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        options.testOptions.transportFactory = TestProxyTransportFactory()
        let client = PubSubClient(options: options)
        client.connect()
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(test.uniqueChannelName())
        typealias JSONObject = NSDictionary

        var result = [JSONObject]()
        channel.subscribe { message in
            result.append(message.data as! JSONObject)
        }

        let messages = [Message(name: nil, data: ["key": 1]), Message(name: nil, data: ["key": 2])]
        channel.publish(messages)

        let transport = client.internal.transport as! TestProxyTransport

        expect(transport.protocolMessagesSent.filter { $0.action == .message }).toEventually(haveCount(1), timeout: testTimeout)
        expect(result).toEventually(equal(messages.map { $0.data as! JSONObject }), timeout: testTimeout)
    }

    func test__097__Channel__publish__expect_either__a_name_string_and_data_payload() throws {
        let test = Test()
        let client = PubSubClient(options: try AblyTests.commonAppSetup(for: test))
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(test.uniqueChannelName())

        let expectedResult = "string_data"
        var result: String?

        channel.subscribe("event") { message in
            result = message.data as? String
        }

        channel.publish("event", data: expectedResult, callback: nil)

        expect(result).toEventually(equal(expectedResult), timeout: testTimeout)
    }

    func test__098__Channel__publish__expect_either__allows_name_to_be_null() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        options.testOptions.transportFactory = TestProxyTransportFactory()
        let client = PubSubClient(options: options)
        client.connect()
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(test.uniqueChannelName())

        expect(client.connection.state).toEventually(equal(RealtimeConnectionState.connected), timeout: testTimeout)
        let expectedObject = ["data": "message", "connectionId": client.connection.id!]

        var resultMessage: Message?
        channel.subscribe { message in
            resultMessage = message
        }

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: expectedObject["data"]) { errorInfo in
                XCTAssertNil(errorInfo)
                done()
            }
        }

        let transport = client.internal.transport as! TestProxyTransport

        let rawProtoMsgsSent: [NSDictionary] = transport.rawDataSent.toMsgPackArray()
        let rawMessagesSent = rawProtoMsgsSent.filter { $0["action"] as! UInt == ARTProtocolMessageAction.message.rawValue }
        let messagesList = rawMessagesSent[0]["messages"] as! NSArray
        let resultObject = messagesList[0] as! [String: String]

        XCTAssertEqual(resultObject, expectedObject)

        expect(resultMessage).toNotEventually(beNil(), timeout: testTimeout)
        XCTAssertNil(resultMessage!.name)
        XCTAssertEqual(resultMessage!.data as? String, expectedObject["data"])
    }

    func test__099__Channel__publish__expect_either__allows_data_to_be_null() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        options.testOptions.transportFactory = TestProxyTransportFactory()
        let client = PubSubClient(options: options)
        client.connect()
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(test.uniqueChannelName())

        expect(client.connection.state).toEventually(equal(RealtimeConnectionState.connected), timeout: testTimeout)
        let expectedObject = ["name": "click", "connectionId": client.connection.id!]

        var resultMessage: Message?
        channel.subscribe(expectedObject["name"]!) { message in
            resultMessage = message
        }

        waitUntil(timeout: testTimeout) { done in
            channel.publish(expectedObject["name"], data: nil) { errorInfo in
                XCTAssertNil(errorInfo)
                done()
            }
        }

        let transport = client.internal.transport as! TestProxyTransport

        let rawProtoMsgsSent: [NSDictionary] = transport.rawDataSent.toMsgPackArray()
        let rawMessagesSent = rawProtoMsgsSent.filter { $0["action"] as! UInt == ARTProtocolMessageAction.message.rawValue }
        let messagesList = rawMessagesSent[0]["messages"] as! NSArray
        let resultObject = messagesList[0] as! NSDictionary

        XCTAssertEqual(resultObject, expectedObject as NSDictionary)

        expect(resultMessage).toNotEventually(beNil(), timeout: testTimeout)
        XCTAssertEqual(resultMessage!.name, expectedObject["name"])
        XCTAssertNil(resultMessage!.data)
    }

    func test__100__Channel__publish__expect_either__allows_name_and_data_to_be_assigned() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        options.testOptions.transportFactory = TestProxyTransportFactory()
        let client = PubSubClient(options: options)
        client.connect()
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(test.uniqueChannelName())

        expect(client.connection.state).toEventually(equal(RealtimeConnectionState.connected), timeout: testTimeout)
        let expectedObject = ["name": "click", "data": "message", "connectionId": client.connection.id!]

        waitUntil(timeout: testTimeout) { done in
            channel.publish(expectedObject["name"], data: expectedObject["data"]) { errorInfo in
                XCTAssertNil(errorInfo)
                done()
            }
        }

        let transport = client.internal.transport as! TestProxyTransport

        let rawProtoMsgsSent: [NSDictionary] = transport.rawDataSent.toMsgPackArray()
        let rawMessagesSent = rawProtoMsgsSent.filter { $0["action"] as! UInt == ARTProtocolMessageAction.message.rawValue }
        let messagesList = rawMessagesSent[0]["messages"] as! NSArray
        let resultObject = messagesList[0] as! NSDictionary

        XCTAssertEqual(resultObject, expectedObject as NSDictionary)
    }

    // RTL6g

    // RTL6g1

    // RTL6g1a & RTL6g1b
    func test__105__Channel__publish__Identified_clients_with_clientId__When_publishing_a_Message_with_clientId_set_to_null__should_be_unnecessary_to_set_clientId_of_the_Message_before_publishing_and_have_clientId_value_set_for_the_Message_when_received() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.clientId = "client_string"
        options.autoConnect = false
        options.testOptions.transportFactory = TestProxyTransportFactory()
        let client = PubSubClient(options: options)
        client.connect()
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(test.uniqueChannelName())

        let message = Message(name: nil, data: "message")
        XCTAssertNil(message.clientId)

        waitUntil(timeout: testTimeout) { done in
            channel.subscribe { message in
                XCTAssertEqual(message.clientId, options.clientId)
                done()
            }
            channel.publish([message])
        }

        let transport = client.internal.transport as! TestProxyTransport

        let messageSent = transport.protocolMessagesSent.filter { $0.action == .message }[0]
        XCTAssertNil(messageSent.messages![0].clientId)

        let messageReceived = transport.protocolMessagesReceived.filter { $0.action == .message }[0]
        XCTAssertEqual(messageReceived.messages![0].clientId, options.clientId)
    }

    // RTL6g2
    func test__101__Channel__publish__Identified_clients_with_clientId__when_publishing_a_Message_with_the_clientId_attribute_value_set_to_the_identified_client_s_clientId() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.clientId = "john"
        let client = PubSubClient(options: options)
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(test.uniqueChannelName())

        let message = Message(name: nil, data: "message", clientId: options.clientId!)
        var resultClientId: String?

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)
            channel.subscribe { message in
                resultClientId = message.clientId
                partialDone()
            }
            channel.publish([message]) { error in
                XCTAssertNil(error)
                partialDone()
            }
        }

        expect(resultClientId).toEventually(equal(message.clientId), timeout: testTimeout)
    }

    // RTL6g3
    func test__102__Channel__publish__Identified_clients_with_clientId__when_publishing_a_Message_with_a_different_clientId_attribute_value_from_the_identified_client_s_clientId__it_should_reject_that_publish_operation_immediately() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.clientId = "john"
        let client = PubSubClient(options: options)
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(test.uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.publish([Message(name: nil, data: "message", clientId: "tester")]) { error in
                XCTAssertEqual(error?.code, Int(ARTState.mismatchedClientId.rawValue))
                done()
            }
        }

        waitUntil(timeout: testTimeout) { done in
            channel.publish([Message(name: nil, data: "message")]) { error in
                XCTAssertNil(error)
                done()
            }
        }
    }

    // RTL6g4
    func test__103__Channel__publish__Identified_clients_with_clientId__message_should_be_published_following_authentication_and_received_back_with_the_clientId_intact() throws {
        let test = Test()
        let options = try AblyTests.clientOptions(for: test)
        options.authCallback = { _, completion in
            getTestTokenDetails(for: test, clientId: "john", completion: completion)
        }
        let client = PubSubClient(options: options)
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(test.uniqueChannelName())
        let message = Message(name: nil, data: "message", clientId: "john")
        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)
            channel.subscribe { received in
                XCTAssertEqual(received.clientId, message.clientId)
                partialDone()
            }
            channel.publish([message]) { error in
                XCTAssertNil(error)
                partialDone()
            }
        }
    }

    // RTL6g4
    func test__104__Channel__publish__Identified_clients_with_clientId__message_should_be_rejected_by_the_Ably_service_and_the_message_error_should_contain_the_server_error() throws {
        let test = Test()
        let options = try AblyTests.clientOptions(for: test)
        options.authCallback = { _, completion in
            getTestTokenDetails(for: test, clientId: "john", completion: completion)
        }
        let client = PubSubClient(options: options)
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(test.uniqueChannelName())
        let message = Message(name: nil, data: "message", clientId: "tester")
        waitUntil(timeout: testTimeout) { done in
            channel.publish([message]) { error in
                XCTAssertEqual(error!.code, ErrorCode.invalidClientId.intValue)
                done()
            }
        }
    }

    // RTL6h
    func test__066__Channel__publish__should_provide_an_optional_argument_that_allows_the_clientId_value_to_be_specified() throws {
        let test = Test()
        let client = PubSubClient(options: try AblyTests.commonAppSetup(for: test))
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(test.uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)
            channel.subscribe { message in
                XCTAssertEqual(message.name, "event")
                XCTAssertEqual(message.data as? NSObject, "data" as NSObject?)
                XCTAssertEqual(message.clientId, "foo")
                partialDone()
            }
            channel.publish("event", data: "data", clientId: "foo") { errorInfo in
                XCTAssertNil(errorInfo)
                partialDone()
            }
        }
    }

    // RTL7

    // RTL7a
    func test__106__Channel__subscribe__with_no_arguments_subscribes_a_listener_to_all_messages() throws {
        let test = Test()
        let client = PubSubClient(options: try AblyTests.commonAppSetup(for: test))
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(test.uniqueChannelName())

        var counter = 0

        channel.subscribe { message in
            XCTAssertEqual(message.data as? String, "message")
            counter += 1
        }

        channel.publish(nil, data: "message")
        channel.publish("eventA", data: "message")
        channel.publish("eventB", data: "message")

        expect(counter).toEventually(equal(3), timeout: testTimeout)
    }

    // RTL7b
    func test__107__Channel__subscribe__with_a_single_name_argument_subscribes_a_listener_to_only_messages_whose_name_member_matches_the_string_name() throws {
        let test = Test()
        let client = PubSubClient(options: try AblyTests.commonAppSetup(for: test))
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(test.uniqueChannelName())

        var counter = 0

        channel.subscribe("eventA") { message in
            XCTAssertEqual(message.name, "eventA")
            XCTAssertEqual(message.data as? String, "message")
            counter += 1
        }

        channel.publish(nil, data: "message")
        channel.publish("eventA", data: "message")
        channel.publish("eventB", data: "message")
        channel.publish("eventA", data: "message")

        expect(counter).toEventually(equal(2), timeout: testTimeout)
    }

    func test__108__Channel__subscribe__with_a_attach_callback_should_subscribe_and_call_the_callback_when_attached() throws {
        let test = Test()
        let client = PubSubClient(options: try AblyTests.commonAppSetup(for: test))
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(test.uniqueChannelName())

        let publishedMessage = Message(name: "foo", data: "bar")

        waitUntil(timeout: testTimeout) { done in
            XCTAssertEqual(channel.state, RealtimeChannelState.initialized)

            channel.subscribe(attachCallback: { errorInfo in
                XCTAssertNil(errorInfo)
                XCTAssertEqual(channel.state, RealtimeChannelState.attached)
                channel.publish([publishedMessage])
            }) { message in
                XCTAssertEqual(message.name, publishedMessage.name)
                XCTAssertEqual(message.data as? NSObject, publishedMessage.data as? NSObject)
                done()
            }

            XCTAssertEqual(channel.state, RealtimeChannelState.attaching)
        }
    }

    // RTL7g
    func test__109__Channel__subscribe__should_implicitly_attach_the_channel_if_options_attachOnSubscribe_is_true() throws {
        let test = Test()
        let client = PubSubClient(options: try AblyTests.commonAppSetup(for: test))
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(test.uniqueChannelName())

        // Initialized
        XCTAssertEqual(channel.state, RealtimeChannelState.initialized)
        channel.subscribe { _ in }
        XCTAssertEqual(channel.state, RealtimeChannelState.attaching)
        expect(channel.state).toEventually(equal(RealtimeChannelState.attached), timeout: testTimeout)

        // Detaching
        channel.detach()
        channel.subscribe { _ in }
        XCTAssertEqual(channel.state, RealtimeChannelState.detaching)
        expect(channel.state).toEventually(equal(RealtimeChannelState.attached), timeout: testTimeout)

        // Detached
        channel.detach()
        expect(channel.state).toEventually(equal(RealtimeChannelState.detached), timeout: testTimeout)
        channel.subscribe { _ in }
        expect(channel.state).toEventually(equal(RealtimeChannelState.attached), timeout: testTimeout)
    }

    // RTL7h
    func test__109b__Channel__subscribe__should_not_implicitly_attach_the_channel_if_options_attachOnSubscribe_is_false() throws {
        let test = Test()
        let client = PubSubClient(options: try AblyTests.commonAppSetup(for: test))
        defer { client.dispose(); client.close() }

        let channelOptions = RealtimeChannelOptions()
        channelOptions.attachOnSubscribe = false
        let channel = client.channels.get(test.uniqueChannelName(), options: channelOptions)

        // Initialized
        XCTAssertEqual(channel.state, RealtimeChannelState.initialized)
        channel.subscribe(attachCallback: { _ in
            fail("Attach callback should not be called.")
        }) { _ in }
        // Make sure that channel stays initialized
        waitUntil(timeout: testTimeout) { done in
            delay(1) {
                XCTAssertEqual(channel.state, RealtimeChannelState.initialized)
                done()
            }
        }
    }

    // RTL7g
    func test__110__Channel__subscribe__should_result_in_an_error_if_channel_is_in_the_FAILED_state_and_options_attachOnSubscribe_is_true() throws {
        let test = Test()
        let client = PubSubClient(options: try AblyTests.commonAppSetup(for: test))
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(test.uniqueChannelName())
        channel.internal.onError(AblyTests.newErrorProtocolMessage())
        XCTAssertEqual(channel.state, RealtimeChannelState.failed)

        waitUntil(timeout: testTimeout) { done in
            channel.subscribe(attachCallback: { errorInfo in
                XCTAssertNotNil(errorInfo)

                channel.subscribe("foo", onAttach: { errorInfo in
                    XCTAssertNotNil(errorInfo)
                    done()
                }) { _ in }
            }) { _ in }
        }
    }

    // RTL7g
    func test__110b__Channel__subscribe__should_not_result_in_an_error_if_channel_is_in_the_FAILED_state_and_options_attachOnSubscribe_is_false() throws {
        let test = Test()
        let client = PubSubClient(options: try AblyTests.commonAppSetup(for: test))
        defer { client.dispose(); client.close() }

        let channelOptions = RealtimeChannelOptions()
        channelOptions.attachOnSubscribe = false
        let channel = client.channels.get(test.uniqueChannelName(), options: channelOptions)

        channel.internal.onError(AblyTests.newErrorProtocolMessage())
        XCTAssertEqual(channel.state, RealtimeChannelState.failed)

        channel.subscribe(attachCallback: { _ in
            fail("Attach callback should not be called.")
        }) { _ in }
        // Make sure that channel stays failed
        waitUntil(timeout: testTimeout) { done in
            delay(1) {
                XCTAssertEqual(channel.state, RealtimeChannelState.failed)
                done()
            }
        }
    }

    // RTL7d

    func test__112__Channel__subscribe__should_deliver_the_message_even_if_there_is_an_error_while_decoding__using_crypto_data_128() throws {
        let test = Test()
        try testHandlesDecodingErrorInFixture("crypto-data-128", for: test, channelName: test.uniqueChannelName())
    }

    func test__113__Channel__subscribe__should_deliver_the_message_even_if_there_is_an_error_while_decoding__using_crypto_data_256() throws {
        let test = Test()
        try testHandlesDecodingErrorInFixture("crypto-data-256", for: test, channelName: test.uniqueChannelName())
    }

    // RTL7e
    func test__114__Channel__subscribe__message_cannot_be_decoded_or_decrypted__should_deliver_with_encoding_attribute_set_indicating_the_residual_encoding_and_error_should_be_emitted() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        options.logHandler = Log(capturingOutput: true)
        options.testOptions.transportFactory = TestProxyTransportFactory()
        let client = PubSubClient(options: options)
        client.connect()
        defer { client.dispose(); client.close() }

        let channelOptions = RealtimeChannelOptions(cipher: ["key": Crypto.generateRandomKey()] as CipherParamsCompatible)
        let channel = client.channels.get(test.uniqueChannelName(), options: channelOptions)

        let expectedMessage = ["key": 1]
        let expectedData = try JSONSerialization.data(withJSONObject: expectedMessage, options: JSONSerialization.WritingOptions(rawValue: 0))

        let transport = client.internal.transport as! TestProxyTransport

        transport.setBeforeIncomingMessageModifier { protocolMessage in
            if protocolMessage.action == .message {
                let messageReceived = protocolMessage.messages![0]
                // Replacement: `json/utf-8/cipher+aes-256-cbc/base64` to `invalid/cipher+aes-256-cbc/base64`
                let newEncoding = "invalid" + messageReceived.encoding!["json/utf-8".endIndex...]
                messageReceived.encoding = newEncoding
            }
            return protocolMessage
        }

        waitUntil(timeout: testTimeout) { done in
            channel.subscribe { message in
                // Last decoding failed: NSData -> JSON object, so...
                XCTAssertEqual(message.data as? NSData, expectedData as NSData?)
                XCTAssertEqual(message.encoding, "invalid")

                let logs = options.logHandler.captured
                let line = logs.reduce("") { $0 + "; " + $1.toString() } // Reduce in one line
                expect(line).to(contain("Failed to decode data: unknown encoding: 'invalid'"))

                expect(channel.errorReason!.message).to(contain("Failed to decode data: unknown encoding: 'invalid'"))

                done()
            }

            channel.publish(nil, data: expectedMessage)
        }
    }

    // RTL7f
    func test__111__Channel__subscribe__should_exist_ensuring_published_messages_are_not_echoed_back_to_the_subscriber_when_echoMessages_is_false() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client1 = PubSubClient(options: options)
        defer { client1.close() }

        options.echoMessages = false
        let client2 = PubSubClient(options: options)
        defer { client2.close() }

        let channelName = test.uniqueChannelName()
        let channel1 = client1.channels.get(channelName)
        let channel2 = client2.channels.get(channelName)

        waitUntil(timeout: testTimeout) { done in
            channel1.attach { err in
                XCTAssertNil(err)
                channel1.subscribe { message in
                    XCTAssertEqual(message.data as? String, "message")
                    delay(1.0) { done() }
                }

                channel2.subscribe { _ in
                    fail("Shouldn't receive the message")
                }

                channel2.publish(nil, data: "message")
            }
        }
    }

    // RTL8

    // RTL8a
    func test__115__Channel__unsubscribe__with_no_arguments_unsubscribes_the_provided_listener_to_all_messages_if_subscribed() throws {
        let test = Test()
        let client = PubSubClient(options: try AblyTests.commonAppSetup(for: test))
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(test.uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            let listener = channel.subscribe { _ in
                fail("Listener shouldn't exist")
                done()
            }

            channel.unsubscribe(listener)

            channel.publish(nil, data: "message") { errorInfo in
                XCTAssertNil(errorInfo)
                done()
            }
        }
    }

    // RTL8b
    func test__116__Channel__unsubscribe__with_a_single_name_argument_unsubscribes_the_provided_listener_if_previously_subscribed_with_a_name_specific_subscription() throws {
        let test = Test()
        let client = PubSubClient(options: try AblyTests.commonAppSetup(for: test))
        defer { client.dispose(); client.close() }

        let channel = client.channels.get(test.uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            let eventAListener = channel.subscribe("eventA") { _ in
                fail("Listener shouldn't exist")
                done()
            }

            channel.unsubscribe("eventA", listener: eventAListener)

            channel.publish("eventA", data: "message") { errorInfo in
                XCTAssertNil(errorInfo)
                done()
            }
        }
    }

    // RTL10

    // RTL10a
    func test__117__Channel__history__should_support_all_the_same_params_as_Rest() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)

        let rest = HttpClient(options: options)

        let realtime = PubSubClient(options: options)
        defer { realtime.close() }

        let channelRest = rest.channels.get(test.uniqueChannelName())
        let channelRealtime = realtime.channels.get(test.uniqueChannelName())

        var restChannelHistoryMethodWasCalled = false

        let hookRest = channelRest.testSuite_injectIntoMethod(after: #selector(HttpChannel.history(_:callback:))) {
            restChannelHistoryMethodWasCalled = true
        }
        defer { hookRest.remove() }

        let hookRealtime = channelRealtime.testSuite_injectIntoMethod(after: #selector(HttpChannel.history(_:callback:))) {
            restChannelHistoryMethodWasCalled = true
        }
        defer { hookRealtime.remove() }

        let queryRealtime = RealtimeHistoryQuery()
        queryRealtime.start = NSDate() as Date
        queryRealtime.end = NSDate() as Date
        queryRealtime.direction = .forwards
        queryRealtime.limit = 50

        let queryRest = queryRealtime as DataQuery

        waitUntil(timeout: testTimeout) { done in
            channelRest.history(queryRest) { _, _ in
                done()
            }
        }
        XCTAssertTrue(restChannelHistoryMethodWasCalled)
        restChannelHistoryMethodWasCalled = false

        waitUntil(timeout: testTimeout) { done in
            channelRealtime.history(queryRealtime) { _, _ in
                done()
            }
        }
        XCTAssertTrue(restChannelHistoryMethodWasCalled)
    }

    // RTL10b

    func test__123__Channel__history__supports_the_param_untilAttach__should_be_false_as_default() {
        let query = RealtimeHistoryQuery()
        XCTAssertEqual(query.untilAttach, false)
    }

    func test__124__Channel__history__supports_the_param_untilAttach__should_invoke_an_error_when_the_untilAttach_is_specified_and_the_channel_is_not_attached() throws {
        let test = Test()
        let client = PubSubClient(options: try AblyTests.commonAppSetup(for: test))
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(test.uniqueChannelName())

        let query = RealtimeHistoryQuery()
        query.untilAttach = true

        waitUntil(timeout: testTimeout) { done in
            channel.history(query) { result, error in
                XCTAssertNil(result)
                XCTAssertEqual(error?.code, ErrorCode.badRequest.intValue)
                XCTAssertEqual(error?.statusCode, 400)
                done()
            }
        }
    }

    func test__125__Channel__history__supports_the_param_untilAttach__where_value_is_true__should_pass_the_querystring_param_fromSerial_with_the_serial_number_assigned_to_the_channel() throws {
        let test = Test()
        try testWithUntilAttach(true, for: test, channelName: test.uniqueChannelName())
    }

    func test__126__Channel__history__supports_the_param_untilAttach__where_value_is_false__should_pass_the_querystring_param_fromSerial_with_the_serial_number_assigned_to_the_channel() throws {
        let test = Test()
        try testWithUntilAttach(true, for: test, channelName: test.uniqueChannelName())
    }

    func test__127__Channel__history__supports_the_param_untilAttach__should_retrieve_messages_prior_to_the_moment_that_the_channel_was_attached() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client1 = PubSubClient(options: options)
        defer { client1.close() }

        options.autoConnect = false
        let client2 = PubSubClient(options: options)
        defer { client2.close() }

        let channelName = test.uniqueChannelName()

        let channel1 = client1.channels.get(channelName)
        channel1.attach()
        expect(channel1.state).toEventually(equal(RealtimeChannelState.attached), timeout: testTimeout)

        var messages = [Message]()
        for i in 0 ..< 20 {
            messages.append(Message(name: nil, data: "message \(i)"))
        }
        waitUntil(timeout: testTimeout) { done in
            channel1.publish(messages) { errorInfo in
                XCTAssertNil(errorInfo)
                done()
            }
        }

        client2.connect()
        let channel2 = client2.channels.get(channelName)
        channel2.attach()
        expect(channel2.state).toEventually(equal(RealtimeChannelState.attached), timeout: testTimeout)

        var counter = 20
        channel2.subscribe { message in
            XCTAssertEqual(message.data as? String, "message \(counter)")
            counter += 1
        }

        messages = [Message]()
        for i in 20 ..< 40 {
            messages.append(Message(name: nil, data: "message \(i)"))
        }
        waitUntil(timeout: testTimeout) { done in
            channel1.publish(messages) { errorInfo in
                XCTAssertNil(errorInfo)
                done()
            }
        }

        let query = RealtimeHistoryQuery()
        query.untilAttach = true

        waitUntil(timeout: testTimeout) { done in
            channel2.history(query) { result, error in
                XCTAssertNil(error)
                guard let result = result else {
                    fail("Result is empty"); done(); return
                }
                XCTAssertEqual(result.items.count, 20)
                XCTAssertFalse(result.hasNext)
                XCTAssertEqual(result.items.first?.data as? String, "message 19")
                XCTAssertEqual(result.items.last?.data as? String, "message 0")
                done()
            }
        }
    }

    // RTL10c
    func test__118__Channel__history__should_return_a_PaginatedResult_page() throws {
        let test = Test()
        let realtime = PubSubClient(options: try AblyTests.commonAppSetup(for: test))
        defer { realtime.close() }
        let channel = realtime.channels.get(test.uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "message") { errorInfo in
                XCTAssertNil(errorInfo)
                done()
            }
        }

        waitUntil(timeout: testTimeout) { done in
            channel.history { result, error in
                XCTAssertNil(error)
                expect(result).to(beAKindOf(PaginatedResult<Message>.self))
                guard let result = result else {
                    fail("Result is empty"); done(); return
                }
                XCTAssertEqual(result.items.count, 1)
                XCTAssertFalse(result.hasNext)
                let messages = result.items
                XCTAssertEqual(messages[0].data as? String, "message")
                done()
            }
        }
    }

    // RTL10d
    func test__119__Channel__history__should_retrieve_all_available_messages() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client1 = PubSubClient(options: options)
        defer { client1.close() }

        let client2 = PubSubClient(options: options)
        defer { client2.close() }

        let channelName = test.uniqueChannelName()

        let channel1 = client1.channels.get(channelName)
        channel1.attach()
        expect(channel1.state).toEventually(equal(RealtimeChannelState.attached), timeout: testTimeout)

        var messages = [Message]()
        for i in 0 ..< 20 {
            messages.append(Message(name: nil, data: "message \(i)"))
        }
        waitUntil(timeout: testTimeout) { done in
            channel1.publish(messages) { errorInfo in
                XCTAssertNil(errorInfo)
                done()
            }
        }

        let channel2 = client2.channels.get(channelName)
        channel2.attach()
        expect(channel2.state).toEventually(equal(RealtimeChannelState.attached), timeout: testTimeout)

        let query = RealtimeHistoryQuery()
        query.limit = 10

        waitUntil(timeout: testTimeout) { done in
            channel2.history(query) { result, _ in
                XCTAssertEqual(result!.items.count, 10)
                XCTAssertTrue(result!.hasNext)
                XCTAssertFalse(result!.isLast)
                XCTAssertEqual((result!.items.first!).data as? String, "message 19")
                XCTAssertEqual((result!.items.last!).data as? String, "message 10")

                result!.next { result, _ in
                    XCTAssertEqual(result!.items.count, 10)
                    XCTAssertFalse(result!.hasNext)
                    XCTAssertTrue(result!.isLast)
                    XCTAssertEqual((result!.items.first!).data as? String, "message 9")
                    XCTAssertEqual((result!.items.last!).data as? String, "message 0")
                    done()
                }
            }
        }
    }

    // RTL12
    func test__120__Channel__history__attached_channel_may_receive_an_additional_ATTACHED_ProtocolMessage() throws {
        let test = Test()
        let client = AblyTests.newRealtime(try AblyTests.commonAppSetup(for: test)).client
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(test.uniqueChannelName())
        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                XCTAssertNil(error)
                done()
            }
        }

        channel.on(.attached) { _ in
            fail("Should not be called")
        }
        defer {
            channel.off()
        }

        var hook: AspectToken?
        waitUntil(timeout: testTimeout) { done in
            let attachedMessage = ARTProtocolMessage()
            attachedMessage.action = .attached
            attachedMessage.channel = channel.name

            /* TODO: ->
             this callback called twice leading to a fail with "waitUntil(..) expects its completion closure to be only called once"
             however sometimes it called once thus succeeding this test!
             https://github.com/ably/ably-cocoa/issues/1281
             */
            hook = channel.internal.testSuite_injectIntoMethod(after: #selector(channel.internal.onChannelMessage(_:))) {
                done()
            }

            // Inject additional ATTACHED action without an error
            client.internal.transport?.receive(attachedMessage)
        }
        hook!.remove()
        XCTAssertNil(channel.errorReason)
        XCTAssertEqual(channel.state, RealtimeChannelState.attached)

        waitUntil(timeout: testTimeout) { done in
            let attachedMessageWithError = AblyTests.newErrorProtocolMessage()
            attachedMessageWithError.action = .attached
            attachedMessageWithError.channel = channel.name

            channel.on { stateChange in
                XCTAssertEqual(stateChange.event, ChannelEvent.update)
                XCTAssertEqual(stateChange.current, RealtimeChannelState.attached)
                XCTAssertEqual(stateChange.previous, RealtimeChannelState.attached)
                XCTAssertTrue(stateChange.reason === attachedMessageWithError.error)
                XCTAssertTrue(stateChange.reason === channel.errorReason)
                XCTAssertFalse(stateChange.resumed)
                done()
            }

            // Inject additional ATTACHED action with an error
            client.internal.transport?.receive(attachedMessageWithError)

            let attachedMessage = ARTProtocolMessage()
            attachedMessage.action = .attached
            attachedMessage.channel = channel.name
            attachedMessage.flags = 4 // resume

            // Inject another ATTACHED action with resume flag, should not generate neither .attached nor .update events
            client.internal.transport?.receive(attachedMessage)
        }
        XCTAssertEqual(channel.state, RealtimeChannelState.attached)
    }

    // RTL13

    // RTL13a
    func test__128__Channel__history__if_the_channel_receives_a_server_initiated_DETACHED_message_when__the_channel_is_in_the_ATTACHED_states__an_attempt_to_reattach_the_channel_should_be_made_immediately_by_sending_a_new_ATTACH_message_and_the_channel_should_transition_to_the_ATTACHING_state_with_the_error_emitted_in_the_ChannelStateChange_event() throws {
        let test = Test()
        let client = AblyTests.newRealtime(try AblyTests.commonAppSetup(for: test)).client
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(test.uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                XCTAssertNil(error)
                done()
            }
        }

        XCTAssertEqual(channel.state, RealtimeChannelState.attached)

        guard let transport = client.internal.transport as? TestProxyTransport else {
            fail("TestProxyTransport is not set"); return
        }

        waitUntil(timeout: testTimeout) { done in
            let detachedMessageWithError = AblyTests.newErrorProtocolMessage()
            detachedMessageWithError.action = .detached
            detachedMessageWithError.channel = channel.name

            channel.once(.attaching) { stateChange in
                guard let error = stateChange.reason else {
                    fail("Reason error is nil"); done(); return
                }
                XCTAssertTrue(error === detachedMessageWithError.error)
                XCTAssertNil(channel.errorReason)
                done()
            }

            transport.receive(detachedMessageWithError)
        }

        XCTAssertEqual(transport.protocolMessagesSent.filter { $0.action == .attach }.count, 2)
    }

    // RTL13a
    func test__129__Channel__history__if_the_channel_receives_a_server_initiated_DETACHED_message_when__the_channel_is_in_the_SUSPENDED_state__an_attempt_to_reattach_the_channel_should_be_made_immediately_by_sending_a_new_ATTACH_message_and_the_channel_should_transition_to_the_ATTACHING_state_with_the_error_emitted_in_the_ChannelStateChange_event() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.testOptions.realtimeRequestTimeout = 1.0
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

        let channel = client.channels.get(test.uniqueChannelName())

        // Timeout
        transport.actionsIgnored += [.attached]

        waitUntil(timeout: testTimeout) { done in
            channel.once(.suspended) { stateChange in
                expect(stateChange.reason?.message).to(contain("timed out"))
                done()
            }
            channel.attach()
        }

        transport.actionsIgnored = []

        waitUntil(timeout: testTimeout) { done in
            let detachedMessageWithError = AblyTests.newErrorProtocolMessage()
            detachedMessageWithError.action = .detached
            detachedMessageWithError.channel = channel.name

            channel.once(.attaching) { stateChange in
                guard let error = stateChange.reason else {
                    fail("Reason error is nil"); done(); return
                }
                XCTAssertTrue(error === detachedMessageWithError.error)
                XCTAssertNil(channel.errorReason)
                done()
            }

            transport.receive(detachedMessageWithError)
        }

        XCTAssertEqual(transport.protocolMessagesSent.filter { $0.action == .attach }.count, 2)
    }

    // RTL13b
    func test__130__Channel__history__if_the_channel_receives_a_server_initiated_DETACHED_message_when__if_the_attempt_to_re_attach_fails_the_channel_will_transition_to_the_SUSPENDED_state_and_the_error_will_be_emitted_in_the_ChannelStateChange_event() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.channelRetryTimeout = 1.0
        options.testOptions.realtimeRequestTimeout = 1.0
        let client = AblyTests.newRealtime(options).client
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(test.uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                XCTAssertNil(error)
                done()
            }
        }

        guard let transport = client.internal.transport as? TestProxyTransport else {
            fail("TestProxyTransport is not set"); return
        }

        transport.actionsIgnored = [.attached]

        let detachedMessageWithError = AblyTests.newErrorProtocolMessage()
        detachedMessageWithError.action = .detached
        detachedMessageWithError.channel = channel.name

        waitUntil(timeout: testTimeout) { done in
            channel.once(.attaching) { stateChange in
                guard let error = stateChange.reason else {
                    fail("Reason error is nil"); done(); return
                }
                XCTAssertTrue(error === detachedMessageWithError.error)
                XCTAssertNil(channel.errorReason)
                done()
            }

            transport.receive(detachedMessageWithError)
        }

        waitUntil(timeout: testTimeout) { done in
            channel.once(.suspended) { stateChange in
                guard let error = stateChange.reason else {
                    fail("Reason error is nil"); done(); return
                }
                XCTAssertTrue(error.code == ARTState.attachTimedOut.rawValue)
                XCTAssertTrue(channel.errorReason === error)
                done()
            }
        }

        let start = NSDate()
        waitUntil(timeout: testTimeout) { done in
            channel.once(.attaching) { _ in
                let end = NSDate()
                expect(start.addingTimeInterval(options.channelRetryTimeout)).to(beCloseTo(end, within: 0.5))
                done()
            }
        }
    }

    // RTL13b
    func test__131__Channel__history__if_the_channel_receives_a_server_initiated_DETACHED_message_when__if_the_channel_was_already_in_the_ATTACHING_state__the_channel_will_transition_to_the_SUSPENDED_state_and_the_error_will_be_emitted_in_the_ChannelStateChange_event() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.channelRetryTimeout = 1.0
        let client = AblyTests.newRealtime(options).client
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(test.uniqueChannelName())

        let detachedMessageWithError = AblyTests.newErrorProtocolMessage()
        detachedMessageWithError.action = .detached
        detachedMessageWithError.channel = channel.name

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)
            channel.once(.attaching) { stateChange in
                XCTAssertNil(stateChange.reason)
                client.internal.transport?.receive(detachedMessageWithError)
                partialDone()
            }
            channel.once(.suspended) { stateChange in
                guard let error = stateChange.reason else {
                    fail("Reason error is nil"); partialDone(); return
                }
                XCTAssertTrue(error === detachedMessageWithError.error)
                XCTAssertNil(channel.errorReason)

                // Check retry
                let start = NSDate()
                channel.once(.attached) { stateChange in
                    let end = NSDate()
                    expect(start).to(beCloseTo(end, within: 1.5))
                    XCTAssertNil(stateChange.reason)
                    partialDone()
                }
            }
            channel.attach()
        }
    }

    // RTL13b, RTB1
    func test__131b__Channel__if_the_channel_receives_a_server_initiated_DETACHED_message_and_if_the_attempt_to_reattach_fails_then_the_channel_will_transition_to_SUSPENDED_state_with_periodic_reattach_with_channelRetryTimeout() throws {
        let test = Test()

        // Given...

        /* ...a Realtime client, configured with a realtimeRequestTimeout of 1 second and a channelRetryTimeout of 1 second...

           ## Motivation for chosen realtimeRequestTimeout value

           As described by (C), in this test we aim to trigger a sequence of attach retries by making each attach attempt time out after realtimeRequestTimeout. Thus, the execution time of this test case will be proportional to the value of retryRequestTimeout. The default value is 20 seconds, which would lead to a very long test execution time, so we reduce it to 1 second.

           ## Motivation for chosen channelRetryTimeout value

           We expect the retries in this sequence to be spaced apart by values in the range of [channelRequestTimeout seconds, 2 * channelRequestTimeout seconds]. The default value of channelRequestTimeout is 15 seconds, so as above, in order to avoid a very long test execution time we reduce it to 1 second.
         */
        let options = try AblyTests.commonAppSetup(for: test)
        options.channelRetryTimeout = 1.0
        options.autoConnect = false
        options.testOptions.realtimeRequestTimeout = 1.0
        options.testOptions.transportFactory = TestProxyTransportFactory()

        let jitterCoefficients = StaticJitterCoefficients()
        let mockJitterCoefficientGenerator = MockJitterCoefficientGenerator(coefficients: jitterCoefficients)
        options.testOptions.jitterCoefficientGenerator = mockJitterCoefficientGenerator

        let client = PubSubClient(options: options)
        client.connect()
        defer { client.dispose(); client.close() }
        expect(client.connection.state).toEventually(equal(RealtimeConnectionState.connected), timeout: testTimeout)

        /* ...whose transport drops all incoming ATTACHED messages...

           ## Motivation

           1. So that the initial attach attempt triggered in (A) doesn't complete, and hence we are sure that when the client receives the DETACHED ProtocolMessage injected in (B), the channel is still in the ATTACHING state, thus satisfying one of the preconditions of RTL13b;
           2. (C) So that none of the client's subsequent re-attach attempts (as described by the "repeated, indefinitely" of RTL13b) succeed, since they will each time out after realtimeRequestTimeout, hence creating conditions for the RTL13b retry sequence to indeed repeat indefinitely
        */
        let transport = client.internal.transport as! TestProxyTransport
        transport.actionsIgnored += [.attached]

        // ...from which we retrieve a channel...
        let channel = client.channels.get(test.uniqueChannelName())

        // ...(A) which we put into the ATTACHING state,
        channel.attach()
        XCTAssertEqual(channel.state, RealtimeChannelState.attaching)

        // When...

        struct ObservedStateChange {
            var observedAt: Date
            var stateChange: ChannelStateChange
        }
        let numberOfRetriesToWaitFor = 5 // arbitrarily-chosen, see (D)
        let retrySequenceDataGatherer = DataGatherer(description: "Observe emitted state changes") { submit in
            var retryNumber = 1
            var observedStateChanges: [ObservedStateChange] = []

            channel.on { stateChange in
                observedStateChanges.append(.init(observedAt: .init(), stateChange: stateChange))

                if (stateChange.current == .attaching) {
                    retryNumber += 1
                }

                if (stateChange.current == .suspended) {
                    if retryNumber > numberOfRetriesToWaitFor {
                        submit(observedStateChanges)
                    }
                }
            }
        }

        // (B) ...the channel receives a DETACHED ProtocolMessage,
        let detachedMessageWithError = AblyTests.newErrorProtocolMessage()
        detachedMessageWithError.action = .detached
        detachedMessageWithError.channel = channel.name
        client.internal.transport?.receive(detachedMessageWithError)

        // Then...

        let expectedRetryDelays = Array(
            AblyTests.expectedRetryDelays(
                forTimeout: options.channelRetryTimeout,
                jitterCoefficients: jitterCoefficients
            ).prefix(numberOfRetriesToWaitFor)
        )
        let timeout = expectedRetryDelays.map { retryDelay in
            options.testOptions.realtimeRequestTimeout // waiting for attach to time out
            + retryDelay // waiting for retry to occur
            + 0.2 // some extra tolerance, arbitrarily chosen
        }.reduce(0, +)
        let observedStateChanges = try retrySequenceDataGatherer.waitForData(timeout: timeout)

        let expectedNumberOfObservedStateChanges = 1 + 2 * numberOfRetriesToWaitFor
        XCTAssertEqual(observedStateChanges.count, expectedNumberOfObservedStateChanges)
        guard observedStateChanges.count == expectedNumberOfObservedStateChanges else {
            return
        }

        // ...the channel emits a state change to the SUSPENDED state...
        let startObservedStateChange = observedStateChanges[0]
        XCTAssertEqual(startObservedStateChange.stateChange.previous, .attaching)
        XCTAssertEqual(startObservedStateChange.stateChange.current, .suspended)
        XCTAssertNotNil(startObservedStateChange.stateChange.reason)

        var previousSuspendedObservedStateChange = startObservedStateChange

        // (D) ...and then, in the following order, we observe the following sequence of events occur numberOfRetriesToWaitFor (a number arbitrarily chosen to give us confidence that this sequence is going to repeat indefinitely) times:
        for retryNumber in 1 ... numberOfRetriesToWaitFor {
            let observedStateChangesStartIndexForThisRetry = 1 + 2 * (retryNumber - 1)

            let expectedRetryDelay = expectedRetryDelays[retryNumber - 1]

            // after a delay (as described by the retry metadata attached to the channel state change, and as approximately measured) matching that defined by RTB1 (with initial retry timeout of channelRetryTimeout), the channel emits a state change to the ATTACHING state...
            let firstObservedStateChange = observedStateChanges[observedStateChangesStartIndexForThisRetry]
            XCTAssertEqual(firstObservedStateChange.stateChange.previous, .suspended)
            XCTAssertEqual(firstObservedStateChange.stateChange.current, .attaching)
            XCTAssertEqual(firstObservedStateChange.stateChange.retryAttempt?.delay, expectedRetryDelay)
            let measuredRetryDelay = firstObservedStateChange.observedAt.timeIntervalSince(previousSuspendedObservedStateChange.observedAt)
            expect(measuredRetryDelay).to(beCloseTo(expectedRetryDelay, within: 0.2 /* arbitrarily-chosen tolerance */))

            // ...and the channel emits a state change to the SUSPENDED state, whose `reason` is non-nil.
            let secondObservedStateChange = observedStateChanges[observedStateChangesStartIndexForThisRetry + 1]
            XCTAssertEqual(secondObservedStateChange.stateChange.previous, .attaching)
            XCTAssertEqual(secondObservedStateChange.stateChange.current, .suspended)
            XCTAssertNotNil(secondObservedStateChange.stateChange.reason)
            previousSuspendedObservedStateChange = secondObservedStateChange
        }
    }

    // RTL13c
    func test__132__Channel__history__if_the_channel_receives_a_server_initiated_DETACHED_message_when__if_the_connection_is_no_longer_CONNECTED__then_the_automatic_attempts_to_re_attach_the_channel_must_be_cancelled() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.channelRetryTimeout = 1.0
        options.testOptions.realtimeRequestTimeout = 1.0
        let client = AblyTests.newRealtime(options).client
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(test.uniqueChannelName())
        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                XCTAssertNil(error)
                done()
            }
        }
        guard let transport = client.internal.transport as? TestProxyTransport else {
            fail("TestProxyTransport is not set"); return
        }

        transport.actionsIgnored = [.attached]
        let detachedMessageWithError = AblyTests.newErrorProtocolMessage()
        detachedMessageWithError.action = .detached
        detachedMessageWithError.channel = channel.name
        waitUntil(timeout: testTimeout) { done in
            channel.once(.attaching) { stateChange in
                guard let error = stateChange.reason else {
                    fail("Reason error is nil"); done(); return
                }
                XCTAssertTrue(error === detachedMessageWithError.error)
                XCTAssertNil(channel.errorReason)
                done()
            }
            transport.receive(detachedMessageWithError)
        }
        waitUntil(timeout: testTimeout) { done in
            channel.once(.suspended) { stateChange in
                guard let error = stateChange.reason else {
                    fail("Reason error is nil"); done(); return
                }
                XCTAssertTrue(error.code == ARTState.attachTimedOut.rawValue)
                XCTAssertTrue(channel.errorReason === error)
                done()
            }
        }

        channel.once(.attaching) { _ in
            fail("Should cancel the re-attach")
        }

        client.simulateSuspended(beforeSuspension: { done in
            channel.once(.suspended) { _ in
                done()
            }
        })
    }

    // RTL14
    func test__121__Channel__history__If_an_ERROR_ProtocolMessage_is_received_for_this_channel_then_the_channel_should_immediately_transition_to_the_FAILED_state__the_errorReason_should_be_set_and_an_error_should_be_emitted_on_the_channel() throws {
        let test = Test()
        let client = PubSubClient(options: try AblyTests.commonAppSetup(for: test))
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(test.uniqueChannelName())
        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                XCTAssertNil(error)
                done()
            }
        }

        waitUntil(timeout: testTimeout) { done in
            let errorProtocolMessage = AblyTests.newErrorProtocolMessage()
            errorProtocolMessage.action = .error
            errorProtocolMessage.channel = channel.name

            channel.once(.failed) { stateChange in
                guard let error = stateChange.reason else {
                    fail("Reason error is nil"); done(); return
                }
                XCTAssertTrue(error === errorProtocolMessage.error)
                XCTAssertTrue(channel.errorReason === error)
                done()
            }

            client.internal.transport?.receive(errorProtocolMessage)
        }

        XCTAssertEqual(channel.state, RealtimeChannelState.failed)
    }

    // RTL15

    // RTL15a/RTL15b
    func test__200__channel_serial_is_updated_whenever_a_protocol_message_with_either_message_presence_or_attached_actions_is_received_in_a_channel() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = AblyTests.newRealtime(options).client
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(test.uniqueChannelName())

        expect(client.connection.state).toEventually(equal(RealtimeConnectionState.connected), timeout: testTimeout)

        let transport = try XCTUnwrap(client.internal.transport as? TestProxyTransport)

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(3, done: done)
            channel.attach { error in
                expect(error).to(beNil())
                guard let attachMessage = transport.protocolMessagesReceived.first(where: { $0.action == .attached }) else {
                    fail("No ATTACHED message was received")
                    partialDone()
                    return
                }
                if attachMessage.channelSerial != nil {
                    expect(attachMessage.channelSerial).to(equal(channel.properties.attachSerial)) // RTL15a
                    expect(attachMessage.channelSerial).to(equal(channel.properties.channelSerial)) // RTL15b
                }
                partialDone()

                channel.subscribe { message in
                    guard let messageMessage = transport.protocolMessagesReceived.first(where: { $0.action == .message }) else {
                        fail("No MESSAGE message was received")
                        partialDone()
                        return
                    }
                    if messageMessage.channelSerial != nil {
                        expect(messageMessage.channelSerial).to(equal(channel.properties.channelSerial)) // RTL15b
                    }
                    channel.presence.enterClient("client1", data: "Hey")
                    partialDone()
                }
                channel.presence.subscribe { _ in
                    // A presence event can also come from a SYNC, for example after a reattach.
                    guard let presenceMessage = transport.protocolMessagesReceived.first(where: { $0.action == .presence }) else {
                        fail("No PRESENCE message was received")
                        partialDone()
                        return
                    }
                    if presenceMessage.channelSerial != nil {
                        expect(presenceMessage.channelSerial).to(equal(channel.properties.channelSerial)) // RTL15b
                    }
                    partialDone()
                }
                channel.publish([Message()])
            }
        }
    }

    // RTL15b
    func test_channelSerial_isUpdatedByObjectProtocolMessage() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = AblyTests.newRealtime(options).client
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(test.uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                XCTAssertNil(error)
                done()
            }
        }

        // Am injecting a fake OBJECT message so that I don't have to deal with the LiveObjects plugin

        let protocolMessage = ARTProtocolMessage()
        protocolMessage.channel = channel.name
        protocolMessage.action = .object
        protocolMessage.channelSerial = "foo"

        let transport = try XCTUnwrap(client.internal.transport as? TestProxyTransport)
        transport.receive(protocolMessage)

        XCTAssertEqual(channel.properties.channelSerial, "foo")
    }

    // RTP5a1
    func test__201__channel_serial_is_cleared_whenever_a_channel_entered_into_detached_suspended_or_failed_state() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = AblyTests.newRealtime(options).client
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(test.uniqueChannelName())

        expect(client.connection.state).toEventually(equal(RealtimeConnectionState.connected), timeout: testTimeout)

        // Case for detached
        channel.attach()
        expect(channel.state).toEventually(equal(RealtimeChannelState.attached), timeout: testTimeout)
        expect(channel.internal.channelSerial).toNot(beNil())

        channel.detach()
        expect(channel.state).toEventually(equal(RealtimeChannelState.detached), timeout: testTimeout)
        expect(channel.internal.channelSerial).to(beNil())

        // Case for suspended
        channel.attach()
        expect(channel.state).toEventually(equal(RealtimeChannelState.attached), timeout: testTimeout)
        expect(channel.internal.channelSerial).toNot(beNil())

        channel.internal.setSuspended(.init(state: .ok))
        expect(channel.state).to(equal(RealtimeChannelState.suspended))
        expect(channel.internal.channelSerial).to(beNil())

        // Case for failed
        channel.attach()
        expect(channel.state).toEventually(equal(RealtimeChannelState.attached), timeout: testTimeout)
        expect(channel.internal.channelSerial).toNot(beNil())

        channel.internal.setFailed(.init(state: .ok))
        expect(channel.state).to(equal(RealtimeChannelState.failed))
        expect(channel.internal.channelSerial).to(beNil())
    }

    // RTL16

    // RTL16a

    func test__133__Channel__history__Channel_options__setOptions__should_send_an_ATTACH_message_with_params___modes_if_the_channel_is_attached() throws {
        let test = Test()
        let client = AblyTests.newRealtime(try AblyTests.commonAppSetup(for: test)).client
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(test.uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                XCTAssertNil(error)
                done()
            }
        }

        guard let transport = client.internal.transport as? TestProxyTransport else {
            fail("Expecting TestProxyTransport"); return
        }

        let channelOptions = RealtimeChannelOptions()
        channelOptions.modes = [.subscribe, .publish]
        channelOptions.params = [
            "delta": "vcdiff",
        ]

        waitUntil(timeout: testTimeout) { done in
            channel.setOptions(channelOptions) { error in
                XCTAssertNil(error)
                done()
            }
        }

        XCTAssertEqual(channel.options?.modes, channelOptions.modes)
        XCTAssertEqual(channel.options?.params, channelOptions.params)

        let attachMessages = transport.protocolMessagesSent.filter { $0.action == .attach }
        XCTAssertEqual(attachMessages.count, 2)
        guard let lastAttach = attachMessages.last else {
            fail("Last ATTACH message is missing"); return
        }
        expect(lastAttach.flags & Int64(ChannelMode.publish.rawValue)).to(beGreaterThan(0)) // true
        expect(lastAttach.flags & Int64(ChannelMode.subscribe.rawValue)).to(beGreaterThan(0)) // true
        XCTAssertEqual(lastAttach.params, channelOptions.params)

        let attachedMessages = transport.protocolMessagesReceived.filter { $0.action == .attached }
        XCTAssertEqual(attachMessages.count, 2)
        guard let lastAttached = attachedMessages.last else {
            fail("Last ATTACH message is missing"); return
        }
        expect(lastAttached.flags & Int64(ChannelMode.publish.rawValue)).to(beGreaterThan(0)) // true
        expect(lastAttached.flags & Int64(ChannelMode.subscribe.rawValue)).to(beGreaterThan(0)) // true
        XCTAssertEqual(lastAttached.params, channelOptions.params)
    }

    func test__134__Channel__history__Channel_options__setOptions__should_send_an_ATTACH_message_with_params___modes_if_the_channel_is_attaching() throws {
        let test = Test()
        let client = AblyTests.newRealtime(try AblyTests.commonAppSetup(for: test)).client
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { _ in
                done()
            }
        }

        guard let transport = client.internal.transport as? TestProxyTransport else {
            fail("Expecting TestProxyTransport"); return
        }

        let channelOptions = RealtimeChannelOptions()
        channelOptions.modes = [.subscribe]
        channelOptions.params = [
            "delta": "vcdiff",
        ]

        let channel = client.channels.get(test.uniqueChannelName())
        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(3, done: done)
            channel.once(.attaching) { _ in
                channel.setOptions(channelOptions) { error in
                    XCTAssertNil(error)
                    partialDone()
                }
            }
            channel.once(.attached) { _ in
                partialDone()
            }
            channel.once(.update) { _ in
                partialDone()
            }
            channel.attach()
        }

        let subscribeFlag = Int64(ChannelMode.subscribe.rawValue)

        let attachMessages = transport.protocolMessagesSent.filter { $0.action == .attach }
        XCTAssertEqual(attachMessages.count, 2)
        guard let lastAttach = attachMessages.last else {
            fail("Last ATTACH message is missing"); return
        }
        XCTAssertEqual(lastAttach.flags & subscribeFlag, subscribeFlag)
        XCTAssertEqual(lastAttach.params, channelOptions.params)

        let attachedMessages = transport.protocolMessagesReceived.filter { $0.action == .attached }
        XCTAssertEqual(attachedMessages.count, 2)
        guard let lastAttached = attachedMessages.last else {
            fail("Last ATTACH message is missing"); return
        }
        XCTAssertEqual(lastAttached.flags & subscribeFlag, subscribeFlag)
        XCTAssertEqual(lastAttached.params, channelOptions.params)
    }

    func test__135__Channel__history__Channel_options__setOptions__should_success_immediately_if_channel_is_not_attaching_or_attached() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        let client = AblyTests.newRealtime(options).client
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(test.uniqueChannelName())

        let channelOptions = RealtimeChannelOptions()
        channelOptions.modes = [.subscribe]
        channelOptions.params = [
            "delta": "vcdiff",
        ]

        channel.setOptions(channelOptions) { error in
            XCTAssertNil(error)
        }

        XCTAssertEqual(channel.state, .initialized)
        XCTAssertEqual(channel.options?.modes, channelOptions.modes)
        XCTAssertEqual(channel.options?.params, channelOptions.params)
    }

    func test__136__Channel__history__Channel_options__setOptions__should_fail_if_the_attach_moves_to_FAILED() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.token = try getTestToken(for: test, capability: "{\"secret\":[\"subscribe\"]}") // access denied
        let client = AblyTests.newRealtime(options).client
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(test.uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { _ in
                done()
            }
        }

        guard let transport = client.internal.transport as? TestProxyTransport else {
            fail("Expecting TestProxyTransport"); return
        }

        let channelOptions = RealtimeChannelOptions()
        channelOptions.modes = [.subscribe]
        channelOptions.params = [
            "delta": "vcdiff",
        ]

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)
            channel.once(.failed) { stateChange in
                XCTAssertEqual(stateChange.reason?.code, ErrorCode.operationNotPermittedWithProvidedCapability.intValue)
                partialDone()
            }
            channel.attach()
            channel.setOptions(channelOptions) { error in
                XCTAssertEqual(error?.code, ErrorCode.operationNotPermittedWithProvidedCapability.intValue)
                partialDone()
            }
        }

        let subscribeFlag = Int64(ChannelMode.subscribe.rawValue)

        let attachMessages = transport.protocolMessagesSent.filter { $0.action == .attach }
        XCTAssertEqual(attachMessages.count, 2)
        guard let lastAttach = attachMessages.last else {
            fail("Last ATTACH message is missing"); return
        }
        XCTAssertEqual(lastAttach.flags & subscribeFlag, subscribeFlag)
        XCTAssertEqual(lastAttach.params, channelOptions.params)

        let attachedMessages = transport.protocolMessagesReceived.filter { $0.action == .attached }
        expect(attachedMessages).to(beEmpty())
    }

    func test__137__Channel__history__Channel_options__setOptions__should_fail_if_the_attach_moves_to_DETACHED() throws {
        let test = Test()
        let client = AblyTests.newRealtime(try AblyTests.commonAppSetup(for: test)).client
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(test.uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { _ in
                done()
            }
        }

        guard let transport = client.internal.transport as? TestProxyTransport else {
            fail("Expecting TestProxyTransport"); return
        }

        let channelOptions = RealtimeChannelOptions()
        channelOptions.modes = [.subscribe]
        channelOptions.params = [
            "delta": "vcdiff",
        ]

        // Convert ATTACHED to DETACHED
        transport.setBeforeIncomingMessageModifier { protocolMessage in
            if protocolMessage.action == .attached {
                protocolMessage.action = .detached
                protocolMessage.error = .create(withCode: ErrorCode.internalError.intValue, status: 500, message: "internal error")
                transport.setBeforeIncomingMessageModifier(nil)
            }
            return protocolMessage
        }

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)
            channel.attach { _ in
                partialDone()
            }
            channel.setOptions(channelOptions) { error in
                XCTAssertEqual(error?.code, ErrorCode.internalError.intValue)
                partialDone()
            }
        }

        let subscribeFlag = Int64(ChannelMode.subscribe.rawValue)

        let attachMessages = transport.protocolMessagesSent.filter { $0.action == .attach }
        XCTAssertEqual(attachMessages.count, 2)
        guard let lastAttach = attachMessages.last else {
            fail("Last ATTACH message is missing"); return
        }
        XCTAssertEqual(lastAttach.flags & subscribeFlag, subscribeFlag)
        XCTAssertEqual(lastAttach.params, channelOptions.params)
    }

    func test__Channel_options__setOptions__shouldUpdateOptionsOfRestChannel() throws {
        let test = Test()
        let client = AblyTests.newRealtime(try AblyTests.commonAppSetup(for: test)).client
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(test.uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { _ in
                done()
            }
        }

        var restChannelSetOptions: ChannelOptions?
        let token = channel.internal.restChannel.testSuite_getArgument(from: #selector(ARTHttpChannelInternal.setOptions_nosync(_:)), at: 0) { arg in
            guard let optionsArg = arg as? ChannelOptions else {
                XCTFail("Expected setOptions: to have been called with a ChannelOptions instance")
                return
            }
            restChannelSetOptions = optionsArg
        }
        defer { token.remove() }

        let channelOptions = RealtimeChannelOptions(cipherKey: Crypto.generateRandomKey() as NSData)

        waitUntil(timeout: testTimeout) { done in
            channel.setOptions(channelOptions) { error in
                XCTAssertNil(error)
                done()
            }
        }

        XCTAssertTrue(restChannelSetOptions === channelOptions)
    }

    // RTL17
    func test__122__Channel__history__should_not_emit_messages_to_subscribers_if_the_channel_is_in_any_state_other_than_ATTACHED() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = PubSubClient(options: options)
        defer { client.close(); client.dispose() }
        let channel = client.channels.get(test.uniqueChannelName())

        let m1 = Message(name: "m1", data: "d1")
        let m2 = Message(name: "m2", data: "d2")

        var subscribeEmittedCount = 0
        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)
            channel.once(.attached) { _ in
                channel.subscribe { message in
                    XCTAssertEqual(channel.state, .attached)
                    XCTAssertEqual(message.name, m1.name)
                    subscribeEmittedCount += 1
                    partialDone()
                }
                channel.publish([m1]) { error in
                    XCTAssertNil(error)
                    partialDone()
                }
            }
            channel.attach()
        }

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)
            channel.subscribe { _ in
                fail("not supposed to receive messages when channel state is \(channel.state)")
            }
            channel.detach()
            channel.publish([m2]) { error in
                XCTAssertNil(error)
                partialDone()
            }
            delay(3.0) {
                // Wait some seconds to see if the channel doesn't emit a message
                partialDone()
            }
        }

        channel.unsubscribe()
        XCTAssertEqual(subscribeEmittedCount, 1)
    }

    func test__138__Channel__crypto__if_configured_for_encryption__channels_encrypt_and_decrypt_messages__data() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        options.testOptions.transportFactory = TestProxyTransportFactory()

        let clientSender = PubSubClient(options: options)
        defer { clientSender.close() }
        clientSender.connect()

        let clientReceiver = PubSubClient(options: options)
        defer { clientReceiver.close() }
        clientReceiver.connect()

        let key = Crypto.generateRandomKey()
        let channelName = test.uniqueChannelName()
        let sender = clientSender.channels.get(channelName, options: RealtimeChannelOptions(cipherKey: key as CipherKeyCompatible))
        let receiver = clientReceiver.channels.get(channelName, options: RealtimeChannelOptions(cipherKey: key as CipherKeyCompatible))

        var received = [Message]()

        waitUntil(timeout: testTimeout) { done in
            receiver.attach { _ in
                receiver.subscribe { message in
                    receiver.unsubscribe()
                    received.append(message)
                    done()
                }

                sender.publish("first", data: "first data")
            }
        }
        if received.count != 1 {
            fail("should have received one message")
            return
        }

        waitUntil(timeout: testTimeout) { done in
            receiver.detach { _ in
                sender.publish("second", data: "second data") { _ in done() }
            }
        }
        if receiver.state != .detached {
            fail("receiver should be detached")
            return
        }

        waitUntil(timeout: testTimeout) { done in
            receiver.attach { _ in
                receiver.subscribe { message in
                    received.append(message)
                    done()
                }
                sender.publish("third", data: "third data")
            }
        }
        if received.count != 2 {
            fail("should've received two messages")
            return
        }

        XCTAssertEqual(received[0].name, "first")
        XCTAssertEqual(received[0].data as? NSString, "first data")
        XCTAssertEqual(received[1].name, "third")
        XCTAssertEqual(received[1].data as? NSString, "third data")

        let senderTransport = clientSender.internal.transport as! TestProxyTransport
        let senderMessages = senderTransport.protocolMessagesSent.filter { $0.action == .message }
        for protocolMessage in senderMessages {
            for message in protocolMessage.messages! {
                XCTAssertNotEqual(message.data! as? String, "\(message.name!) data")
                XCTAssertEqual(message.encoding, "utf-8/cipher+aes-256-cbc/base64")
            }
        }

        let receiverTransport = clientReceiver.internal.transport as! TestProxyTransport
        let receiverMessages = receiverTransport.protocolMessagesReceived.filter { $0.action == .message }
        for protocolMessage in receiverMessages {
            for message in protocolMessage.messages! {
                XCTAssertNotEqual(message.data! as? NSObject, "\(message.name!) data" as NSObject?)
                XCTAssertEqual(message.encoding, "utf-8/cipher+aes-256-cbc")
            }
        }
    }

    // https://github.com/ably/ably-cocoa/issues/614
    func test__002__Channel__should_not_crash_when_an_ATTACH_request_is_responded_with_a_DETACHED() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.testOptions.realtimeRequestTimeout = 1.0
        let client = AblyTests.newRealtime(options).client
        defer { client.dispose(); client.close() }
        let channel = client.channels.get(test.uniqueChannelName())

        guard let transport = client.internal.transport as? TestProxyTransport else {
            fail("TestProxyTransport is not set"); return
        }

        transport.setBeforeIncomingMessageModifier { protocolMessage in
            if protocolMessage.action == .attached {
                protocolMessage.action = .detached
                protocolMessage.error = ErrorInfo.create(withCode: ErrorCode.internalError.intValue, status: 500, message: "fake error message text")
            }
            return protocolMessage
        }

        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                guard let error = error else {
                    fail("Error is nil"); done(); return
                }
                XCTAssertEqual(error.statusCode, 500)
                done()
            }
        }
    }

    // TM2a
    func test__139__message_attributes__if_the_message_does_not_contain_an_id__it_should_be_set_to_protocolMsgId_index() throws {
        let test = Test()
        let client = PubSubClient(options: try AblyTests.commonAppSetup(for: test))
        defer { client.dispose(); client.close() }
        let p = ARTProtocolMessage()
        p.id = "protocolId"
        let m = Message(name: nil, data: "message without ID")
        p.messages = [m]
        let channel = client.channels.get(test.uniqueChannelName())
        waitUntil(timeout: testTimeout) { done in
            channel.attach { _ in
                done()
            }
        }
        waitUntil(timeout: testTimeout) { done in
            channel.subscribe { message in
                XCTAssertEqual(message.id, "protocolId:0")
                done()
            }
            AblyTests.queue.async {
                channel.internal.onMessage(p)
            }
        }
    }

    // TB1
    func test__140__ChannelOptions__options_provided_when_instantiating_a_channel_should_be_frozen() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        let realtime = AblyTests.newRealtime(options).client
        defer { realtime.dispose(); realtime.close() }

        let (keyData, ivData, _) = AblyTests.loadCryptoTestData("crypto-data-128")
        let cipherParams = CipherParams(algorithm: "aes", key: keyData as CipherKeyCompatible, iv: ivData)

        let channelOptions = RealtimeChannelOptions()

        // not frozen
        channelOptions.cipher = cipherParams
        channelOptions.modes = [.publish]
        channelOptions.params = ["rewind": "1"]

        _ = realtime.channels.get(test.uniqueChannelName(), options: channelOptions)

        let exception1 = tryInObjC {
            channelOptions.cipher = cipherParams // frozen
        }
        XCTAssertNotNil(exception1)
        XCTAssertEqual(exception1!.name, NSExceptionName.objectInaccessibleException)

        let exception2 = tryInObjC {
            channelOptions.modes = [.publish] // frozen
        }
        XCTAssertNotNil(exception2)
        XCTAssertEqual(exception2!.name, NSExceptionName.objectInaccessibleException)

        let exception3 = tryInObjC {
            channelOptions.params = ["rewind": "1"] // frozen
        }
        XCTAssertNotNil(exception3)
        XCTAssertEqual(exception3!.name, NSExceptionName.objectInaccessibleException)

        let exception4 = tryInObjC {
            channelOptions.attachOnSubscribe = false // frozen
        }
        XCTAssertNotNil(exception4)
        XCTAssertEqual(exception4!.name, NSExceptionName.objectInaccessibleException)
    }

    func test_Channel_should_ignore_protocol_messages_with_Object_and_ObjectSync_actions_when_LiveObjects_plugin_not_provided() throws {
        // Given: A realtime client that has been created without the LiveObjects plugin
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        options.testOptions.transportFactory = TestProxyTransportFactory()
        let client = PubSubClient(options: options)
        defer { client.dispose(); client.close() }

        // Connect and attach a channel
        client.connect()
        let transport = client.internal.transport as! TestProxyTransport

        let channel = client.channels.get(test.uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                XCTAssertNil(error)
                done()
            }
        }

        // When: A channel receives a ProtocolMessage with action of OBJECT or OBJECT_SYNC

        let objectMessage = ARTProtocolMessage()
        objectMessage.action = .object
        objectMessage.channel = channel.name
        transport.receive(objectMessage)

        let objectSyncMessage = ARTProtocolMessage()
        objectSyncMessage.action = .objectSync
        objectSyncMessage.channel = channel.name
        transport.receive(objectSyncMessage)

        // Then: It does not crash, and is not prevented from receiving subsequent messages on the channel

        // Publish a message and wait for it to be received
        let receivedMessageDataGatherer = DataGatherer<Message>(description: "Subscribe for message") { submit in
            channel.subscribe { message in
                submit(message)
            }
        }

        waitUntil(timeout: testTimeout) { done in
            channel.publish("foo", data: nil) { error in
                XCTAssertNil(error)
                done()
            }
        }

        let receivedMessage = try receivedMessageDataGatherer.waitForData(timeout: testTimeout)
        XCTAssertEqual(receivedMessage.name, "foo")
    }

    // RTL4m
    func test__141__ChannelOptions__on_ATTACHED_should_decode_flags_into_array_of_channel_modes() throws {
        // Given: A realtime channel and a protocol message with channel modes
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        let realtime = AblyTests.newRealtime(options).client
        defer { realtime.dispose(); realtime.close() }

        let channel = realtime.channels.get("test")

        // Then: The modes property should be accessible and initially 0
        XCTAssertEqual(channel.modes, ChannelMode(rawValue: 0))

        // Create a protocol message with channel modes
        let protocolMessage = ARTProtocolMessage()
        protocolMessage.action = ARTProtocolMessageAction.attached
        protocolMessage.channel = "test"
        // adding flags which are not modes
        protocolMessage.flags = Int64(
            ARTProtocolMessageFlag.hasBacklog.rawValue | // not mode
            ARTProtocolMessageFlag.resumed.rawValue | // not mode
            1 << 15 |  // not mode
            ChannelMode.presence.rawValue | // the first mode
            ChannelMode.subscribe.rawValue // mode
        )

        // When: setAttached is called with the protocol message
        channel.internal.setAttached(protocolMessage)

        // Then: The modes property should be set from the protocol message and contain only channel modes
        XCTAssertEqual(channel.modes, [.presence, .subscribe])
    }

    // RTL6j
    func test__142__publish__with_resultCallback__returns_valid_PublishResult_with_message_serials() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let realtime = AblyTests.newRealtime(options).client
        defer { realtime.dispose(); realtime.close() }

        let channel = realtime.channels.get(test.uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.publish("testEvent", data: "testData") { result, error in
                XCTAssertNil(error)
                XCTAssertNotNil(result)
                XCTAssertEqual(result?.serials.count, 1)
                XCTAssertNotNil(result?.serials.first?.value)
                done()
            }
        }
    }
}
