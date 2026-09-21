import AblyPubSubDevice
import AblyPubSubDevice.Private
import AblyTestingObjC
import Foundation
import Nimble
import XCTest

private var jsonEncoder: ARTJsonLikeEncoder!

private var eventEmitter = ARTInternalEventEmitter<NSString, AnyObject>(queue: AblyTests.queue, timeProvider: SystemTimeProvider())
private var receivedFoo1: Int?
private var receivedFoo2: Int?
private var receivedBar: Int?
private var receivedBarOnce: Int?
private var receivedAll: Int?
private var receivedAllOnce: Int?
private weak var listenerFoo1: EventListener?
private weak var listenerAll: EventListener?
private let data = ["test": "test"]
private let extras = ["push": ["key": "value"]]
private let clientId = "clientId"

class UtilitiesTests: XCTestCase {
    // XCTest invokes this method before executing the first test in the test suite. We use it to ensure that the global variables are initialized at the same moment, and in the same order, as they would have been when we used the Quick testing framework.
    override class var defaultTestSuite: XCTestSuite {
        _ = jsonEncoder
        _ = eventEmitter
        _ = receivedFoo1
        _ = receivedFoo2
        _ = receivedBar
        _ = receivedBarOnce
        _ = receivedAll
        _ = receivedAllOnce
        _ = listenerFoo1
        _ = listenerAll
        _ = data
        _ = extras
        _ = clientId

        return super.defaultTestSuite
    }

    func beforeEach__Utilities__JSON_Encoder() {
        jsonEncoder = ARTJsonLikeEncoder(delegate: ARTJsonEncoder(), timeProvider: SystemTimeProvider())
    }

    func test__001__Utilities__JSON_Encoder__should_decode_a_protocol_message_that_has_an_error_without_a_message() throws {
        beforeEach__Utilities__JSON_Encoder()

        let jsonObject: [String : Any] = [
            "action": 9,
            "error": [
                "code": 40142,
                "statusCode": "401",
            ] as [String : Any],
        ]
        let data = try JSONSerialization.data(withJSONObject: jsonObject, options: [])
        guard let protocolMessage = try? jsonEncoder.decodeProtocolMessage(data) else {
            fail("Decoder has failed"); return
        }
        guard let error = protocolMessage.error else {
            fail("Error is empty"); return
        }
        XCTAssertEqual(error.message, "")
    }

    func test__002__Utilities__JSON_Encoder__should_encode_a_protocol_message_that_has_invalid_data() {
        beforeEach__Utilities__JSON_Encoder()

        let pm = ARTProtocolMessage()
        pm.action = .message
        pm.channel = "foo"
        pm.messages = [Message(name: "status", data: NSDate(), clientId: "user")]
        var result: Data?
        expect { result = try jsonEncoder.encode(pm) }.to(throwError { error in
            let e = error as NSError
            XCTAssertEqual(e.domain, ablyErrorDomain)
            XCTAssertEqual(e.code, Int(ARTClientCodeError.invalidType.rawValue))
            expect(e.localizedDescription).to(contain("Invalid type in JSON write"))
        })
        XCTAssertNil(result)
    }

    func test__003__Utilities__JSON_Encoder__should_decode_data_with_malformed_JSON() {
        beforeEach__Utilities__JSON_Encoder()

        let malformedJSON = "{...}"
        let data = malformedJSON.data(using: String.Encoding.utf8)!
        var result: AnyObject?
        expect { result = try ARTJsonEncoder().decode(data) as AnyObject? }.to(throwError { error in
            let e = error as NSError
            expect(e.localizedDescription).to(contain("data couldn’t be read"))
        })
        XCTAssertNil(result)
    }

    func test__004__Utilities__JSON_Encoder__should_decode_data_with_malformed_MsgPack() {
        beforeEach__Utilities__JSON_Encoder()

        let data = NSData()
        var result: AnyObject?
        expect { result = try ARTMsgPackEncoder().decode(data as Data) as! (Data) as (Data) as AnyObject? }.to(throwError { error in
            XCTAssertNotNil(error)
        })
        XCTAssertNil(result)
    }

    func test__005__Utilities__JSON_Encoder__in_Realtime__should_handle_and_emit_the_invalid_data_error() throws {
        let test = Test()
        beforeEach__Utilities__JSON_Encoder()

        let options = try AblyTests.commonAppSetup(for: test)
        let realtime = PubSubClient(options: options)
        defer { realtime.close() }
        let channel = realtime.channels.get(test.uniqueChannelName())
        waitUntil(timeout: testTimeout) { done in
            channel.publish("test", data: NSDate()) { error in
                guard let error = error else {
                    fail("Error shouldn't be nil"); done(); return
                }
                expect(error.message).to(contain("encoding failed"))
                expect(error.reason).to(contain("must be NSString, NSData, NSArray or NSDictionary"))
                done()
            }
        }
        waitUntil(timeout: testTimeout) { done in
            channel.publish([Message(name: nil, data: NSDate()), Message(name: nil, data: NSDate())]) { error in
                guard let error = error else {
                    fail("Error shouldn't be nil"); done(); return
                }
                expect(error.message).to(contain("encoding failed"))
                expect(error.reason).to(contain("must be NSString, NSData, NSArray or NSDictionary"))
                done()
            }
        }
    }

    func test__006__Utilities__JSON_Encoder__in_Realtime__should_ignore_invalid_transport_message() throws {
        let test = Test()
        beforeEach__Utilities__JSON_Encoder()

        let options = try AblyTests.commonAppSetup(for: test)
        let realtime = PubSubClient(options: options)
        defer { realtime.close() }
        let channel = realtime.channels.get(test.uniqueChannelName())

        // Garbage values (whatever is on the heap)
        let bytes = UnsafeMutablePointer<Int>.allocate(capacity: 1)
        defer { bytes.deallocate() }
        let data = NSData(bytes: bytes, length: MemoryLayout<Int>.size)

        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                XCTAssertNil(error)
                realtime.connection.once { _ in
                    fail("Should not receive any connection change state")
                }
                channel.once { _ in
                    fail("Should not receive any channel change state")
                }
                channel.subscribe { _ in
                    fail("Should not receive any message")
                }
                var result: AnyObject?
                XCTAssertNil(tryInObjC {
                    result = realtime.internal.transport?.receive(with: data as Data)
                })
                XCTAssertNil(result)
                done()
            }
        }

        realtime.connection.off()
        channel.off()
        channel.unsubscribe()
    }

    func test__007__Utilities__JSON_Encoder__in_Rest__should_handle_and_emit_the_invalid_data_error() throws {
        let test = Test()
        beforeEach__Utilities__JSON_Encoder()

        let options = try AblyTests.commonAppSetup(for: test)
        let rest = HttpClient(options: options)
        let channel = rest.channels.get(test.uniqueChannelName())
        waitUntil(timeout: testTimeout) { done in
            channel.publish("test", data: NSDate()) { error in
                guard let error = error else {
                    fail("Error shouldn't be nil"); done(); return
                }
                expect(error.message).to(contain("encoding failed"))
                expect(error.reason).to(contain("must be NSString, NSData, NSArray or NSDictionary"))
                done()
            }
        }
        waitUntil(timeout: testTimeout) { done in
            channel.publish([Message(name: nil, data: NSDate()), Message(name: nil, data: NSDate())]) { error in
                guard let error = error else {
                    fail("Error shouldn't be nil"); done(); return
                }
                expect(error.message).to(contain("encoding failed"))
                expect(error.reason).to(contain("must be NSString, NSData, NSArray or NSDictionary"))
                done()
            }
        }
    }

    func test__008__Utilities__JSON_Encoder__in_Rest__should_ignore_invalid_response_payload() throws {
        let test = Test()
        beforeEach__Utilities__JSON_Encoder()

        let options = try AblyTests.commonAppSetup(for: test)
        let rest = HttpClient(options: options)
        let testHTTPExecutor = TestProxyHTTPExecutor(logger: .init(clientOptions: options))
        rest.internal.httpExecutor = testHTTPExecutor
        let channel = rest.channels.get(test.uniqueChannelName())

        // Garbage values (whatever is on the heap)
        let bytes = UnsafeMutablePointer<Int>.allocate(capacity: 1)
        defer { bytes.deallocate() }
        let data = NSData(bytes: bytes, length: MemoryLayout<Int>.size)

        testHTTPExecutor.simulateIncomingPayloadOnNextRequest(data as Data)
        waitUntil(timeout: testTimeout) { done in
            channel.history { _, error in
                guard let error = error else {
                    fail("Error is nil"); done(); return
                }
                expect(error.reason).to(contain("JSON text did not start with array or object and option to allow fragments not set"))
                done()
            }
        }
    }

    func test__Utilities__JSON_Encoder__should_decode_rest_error_response_with_only_error_field() throws {
        let test = Test()
        beforeEach__Utilities__JSON_Encoder()

        let options = try AblyTests.commonAppSetup(for: test)
        let rest = HttpClient(options: options)
        let testHTTPExecutor = TestProxyHTTPExecutor(logger: .init(clientOptions: options))
        rest.internal.httpExecutor = testHTTPExecutor

        testHTTPExecutor.simulateIncomingServerErrorOnNextRequest(
            40400,
            statusCode: 404,
            description: "Not found",
            data: [
                "err": "Error that shouldn't be parsed"
            ]
        )

        let request = URLRequest(url: URL(string: "https://www.example.com")!)
        waitUntil(timeout: testTimeout) { done in
            rest.internal.execute(request, wrapperSDKAgents:nil, completion: { response, _, error in
                guard let error = error as? ErrorInfo else {
                    fail("Should be ErrorInfo"); done(); return
                }
                XCTAssertTrue(error.code == 40400)
                XCTAssertTrue(error.statusCode == 404)
                XCTAssertTrue(error.message == "HTTP request failed with status code 404")
                done()
            })
        }
    }

    func test__Utilities__JSON_Encoder__should_decode_rest_error_response_with_complete_error_info() throws {
        let test = Test()
        beforeEach__Utilities__JSON_Encoder()

        let options = try AblyTests.commonAppSetup(for: test)
        let rest = HttpClient(options: options)
        let testHTTPExecutor = TestProxyHTTPExecutor(logger: .init(clientOptions: options))
        rest.internal.httpExecutor = testHTTPExecutor

        testHTTPExecutor.simulateIncomingServerErrorOnNextRequest(
            40400,
            statusCode: 404,
            description: "Not found",
            data: [
                "error": [
                    "code": 40400,
                    "message": "Object not found"
                ]
            ]
        )

        let request = URLRequest(url: URL(string: "https://www.example.com")!)
        waitUntil(timeout: testTimeout) { done in
            rest.internal.execute(request, wrapperSDKAgents:nil, completion: { response, _, error in
                guard let error = error as? ErrorInfo else {
                    fail("Should be ErrorInfo"); done(); return
                }
                XCTAssertTrue(error.code == 40400)
                XCTAssertTrue(error.statusCode == 404)
                XCTAssertTrue(error.message == "Object not found")
                done()
            })
        }
    }

    func beforeEach__Utilities__EventEmitter() {
        eventEmitter = ARTInternalEventEmitter(queue: AblyTests.queue, timeProvider: SystemTimeProvider())
        receivedFoo1 = nil
        receivedFoo2 = nil
        receivedBar = nil
        receivedBarOnce = nil
        receivedAll = nil
        listenerFoo1 = eventEmitter.on("foo", callback: { receivedFoo1 = $0 as? Int })
        eventEmitter.on("foo", callback: { receivedFoo2 = $0 as? Int })
        eventEmitter.on("bar", callback: { receivedBar = $0 as? Int })
        eventEmitter.once("bar", callback: { receivedBarOnce = $0 as? Int })
        listenerAll = eventEmitter.on { receivedAll = $0 as? Int }
        eventEmitter.once { receivedAllOnce = $0 as? Int }
    }

    func test__009__Utilities__EventEmitter__should_emit_events_to_all_relevant_listeners() {
        beforeEach__Utilities__EventEmitter()

        eventEmitter.emit("foo", with: 123 as AnyObject?)

        XCTAssertEqual(receivedFoo1, 123)
        XCTAssertEqual(receivedFoo2, 123)
        XCTAssertNil(receivedBar)
        XCTAssertEqual(receivedAll, 123)

        eventEmitter.emit("bar", with: 456 as AnyObject?)

        XCTAssertEqual(receivedFoo1, 123)
        XCTAssertEqual(receivedFoo2, 123)
        XCTAssertEqual(receivedBar, 456)
        XCTAssertEqual(receivedAll, 456)

        eventEmitter.emit("qux", with: 789 as AnyObject?)

        expect(receivedAll).toEventually(equal(789), timeout: testTimeout)
    }

    func test__010__Utilities__EventEmitter__should_only_call_once_listeners_once_for_its_event() {
        beforeEach__Utilities__EventEmitter()

        eventEmitter.emit("foo", with: 123 as AnyObject?)

        XCTAssertNil(receivedBarOnce)
        XCTAssertEqual(receivedAllOnce, 123)

        eventEmitter.emit("bar", with: 456 as AnyObject?)

        XCTAssertEqual(receivedBarOnce, 456)
        XCTAssertEqual(receivedAllOnce, 123)

        eventEmitter.emit("bar", with: 789 as AnyObject?)

        XCTAssertEqual(receivedBarOnce, 456)
        XCTAssertEqual(receivedAllOnce, 123)
    }

    func test__011__Utilities__EventEmitter__calling_off_with_a_single_listener_argument__should_stop_receiving_events_when_calling_off_with_a_single_listener_argument() {
        beforeEach__Utilities__EventEmitter()

        eventEmitter.off(listenerFoo1!)
        eventEmitter.emit("foo", with: 123 as AnyObject?)

        XCTAssertNil(receivedFoo1)
        XCTAssertEqual(receivedFoo2, 123)
        XCTAssertEqual(receivedAll, 123)

        eventEmitter.emit("bar", with: 222 as AnyObject?)

        XCTAssertEqual(receivedFoo2, 123)
        XCTAssertEqual(receivedAll, 222)

        eventEmitter.off(listenerAll!)
        eventEmitter.emit("bar", with: 333 as AnyObject?)

        XCTAssertEqual(receivedAll, 222)
    }

    func test__012__Utilities__EventEmitter__calling_off_with_a_single_listener_argument__should_remove_the_timeout() {
        beforeEach__Utilities__EventEmitter()

        listenerFoo1!.setTimer(0.1, onTimeout: {
            fail("onTimeout callback shouldn't have been called")
        }).startTimer()
        eventEmitter.off(listenerFoo1!)
        waitUntil(timeout: testTimeout) { done in
            AblyTests.queue.asyncAfter(deadline: DispatchTime.now() + 0.3) {
                done()
            }
        }
    }

    func test__013__Utilities__EventEmitter__calling_off_with_listener_and_event_arguments__should_still_receive_events_if_off_doesn_t_match_the_listener_s_criteria() {
        beforeEach__Utilities__EventEmitter()

        eventEmitter.off("foo", listener: listenerAll!)
        eventEmitter.emit("foo", with: 111 as AnyObject?)

        XCTAssertEqual(receivedFoo1, 111)
        XCTAssertEqual(receivedAll, 111)
    }

    func test__014__Utilities__EventEmitter__calling_off_with_listener_and_event_arguments__should_stop_receive_events_if_off_matches_the_listener_s_criteria() {
        beforeEach__Utilities__EventEmitter()

        eventEmitter.off("foo", listener: listenerFoo1!)
        eventEmitter.emit("foo", with: 111 as AnyObject?)

        XCTAssertNil(receivedFoo1)
        XCTAssertEqual(receivedAll, 111)
    }

    func test__015__Utilities__EventEmitter__calling_off_with_no_arguments__should_remove_all_listeners() {
        beforeEach__Utilities__EventEmitter()

        eventEmitter.off()
        eventEmitter.emit("foo", with: 111 as AnyObject?)

        XCTAssertNil(receivedFoo1)
        XCTAssertNil(receivedFoo2)
        XCTAssertNil(receivedAll)

        eventEmitter.emit("bar", with: 111 as AnyObject?)

        XCTAssertNil(receivedBar)
        XCTAssertNil(receivedBarOnce)
        XCTAssertNil(receivedAll)
    }

    func test__016__Utilities__EventEmitter__calling_off_with_no_arguments__should_allow_listening_again() {
        beforeEach__Utilities__EventEmitter()

        eventEmitter.off()
        eventEmitter.on("foo", callback: { receivedFoo1 = $0 as? Int })
        eventEmitter.emit("foo", with: 111 as AnyObject?)
        XCTAssertEqual(receivedFoo1, 111)
    }

    func test__017__Utilities__EventEmitter__calling_off_with_no_arguments__should_remove_all_timeouts() {
        beforeEach__Utilities__EventEmitter()

        listenerFoo1!.setTimer(0.1, onTimeout: {
            fail("onTimeout callback shouldn't have been called")
        }).startTimer()
        listenerAll!.setTimer(0.1, onTimeout: {
            fail("onTimeout callback shouldn't have been called")
        }).startTimer()
        eventEmitter.off()
        waitUntil(timeout: DispatchTimeInterval.milliseconds(300)) { done in
            AblyTests.queue.asyncAfter(deadline: .now() + 0.15) {
                done()
            }
        }
    }

    func test__018__Utilities__EventEmitter__the_timed_method__should_not_call_onTimeout_if_the_deadline_isn_t_reached() {
        beforeEach__Utilities__EventEmitter()

        weak var timer = listenerFoo1!.setTimer(0.2, onTimeout: {
            fail("onTimeout callback shouldn't have been called")
        })
        waitUntil(timeout: DispatchTimeInterval.seconds(1)) { done in
            timer?.startTimer()
            eventEmitter.emit("foo", with: 123 as AnyObject?)
            AblyTests.queue.asyncAfter(deadline: .now() + 0.3) {
                XCTAssertNotNil(receivedFoo1)
                done()
            }
        }
    }

    func test__019__Utilities__EventEmitter__the_timed_method__should_call_onTimeout_and_off_the_listener_if_the_deadline_is_reached() {
        beforeEach__Utilities__EventEmitter()

        var calledOnTimeout = false
        let beforeEmitting = NSDate()
        listenerFoo1!.setTimer(0.3, onTimeout: {
            calledOnTimeout = true
            expect(NSDate()).to(beCloseTo(beforeEmitting.addingTimeInterval(0.3), within: 0.2))
        }).startTimer()
        waitUntil(timeout: DispatchTimeInterval.milliseconds(500)) { done in
            AblyTests.queue.asyncAfter(deadline: .now() + 0.35) {
                XCTAssertTrue(calledOnTimeout)
                eventEmitter.emit("foo", with: 123 as AnyObject?)
                XCTAssertNil(receivedFoo1)
                done()
            }
        }
    }

    // RTE6a
    func test__020__Utilities__EventEmitter__set_of_listeners__should_not_change_over_the_course_of_the_emit() {
        beforeEach__Utilities__EventEmitter()

        var firstCallbackCalled = false
        var secondCallbackCalled = false
        eventEmitter.on("a", callback: { _ in
            firstCallbackCalled = true
            eventEmitter.on("b", callback: { _ in
                secondCallbackCalled = true
            })
        })
        eventEmitter.emit("a", with: "123" as AnyObject?)
        XCTAssertTrue(firstCallbackCalled)
        XCTAssertFalse(secondCallbackCalled)
    }

    func test__021__Utilities__Logger__should_have_a_history_of_logs() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.logLevel = .verbose
        let realtime = PubSubClient(options: options)
        defer { realtime.close() }
        let channel = realtime.channels.get(test.uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                XCTAssertNil(error)
                done()
            }
        }

        let logger = options.logHandler

        expect(logger.history.count).toNot(beGreaterThan(100))
        XCTAssertEqual(logger.history.filter { $0.message.contains("channel state transitions from 1 - Attaching to 2 - Attached") }.count, 1)
        XCTAssertEqual(logger.history.filter { $0.message.contains("realtime state transitions to 2 - Connected") }.count, 1)
    }

    func test__022__Utilities__maxMessageSize__calculates_maxMessageSize_of_a_Message_with_name_and_data() {
        let message = Message(name: "this is name", data: data)
        let expectedSize = "{\"test\":\"test\"}".count + message.name!.count
        XCTAssertEqual(message.messageSize(), expectedSize)
    }

    func test__023__Utilities__maxMessageSize__calculates_maxMessageSize_of_a_Message_with_name__data_and_extras() {
        let message = Message(name: "this is name", data: data)
        message.extras = extras as JsonCompatible
        let expectedSize = "{\"test\":\"test\"}".count + "{\"push\":{\"key\":\"value\"}}".count + message.name!.count
        XCTAssertEqual(message.messageSize(), expectedSize)
    }

    func test__024__Utilities__maxMessageSize__calculates_maxMessageSize_of_a_Message_with_name__data__clientId_and_extras() {
        let message = Message(name: "this is name", data: data)
        message.clientId = clientId
        message.extras = extras as JsonCompatible
        let expectedSize = "{\"test\":\"test\"}".count + "{\"push\":{\"key\":\"value\"}}".count + clientId.count + message.name!.count
        XCTAssertEqual(message.messageSize(), expectedSize)
    }

    // Non-ASCII cases locking the string-measurement convention of Ably's published message-size
    // accounting: name, clientId and string data are measured as their UTF-8 byte length, while
    // extras (and JSON-stringified object/array data) are measured as the string length (the number
    // of UTF-16 code units) of their JSON representation. 你 is 3 UTF-8 bytes / 1 UTF-16 code unit;
    // 😊 is 4 UTF-8 bytes / 2 UTF-16 code units.
    func test__027__Utilities__maxMessageSize__measures_unicode_fields_per_documented_accounting() {
        // name (7) + clientId (7) + string data (7), all UTF-8 byte lengths.
        let message = Message(name: "你😊", data: "你😊")
        message.clientId = "你😊"
        XCTAssertEqual(message.messageSize(), 21)

        // extras: {"k":"你😊"} is 11 UTF-16 code units (versus 15 UTF-8 bytes).
        let messageWithExtras = Message(name: nil, data: "")
        messageWithExtras.extras = ["k": "你😊"] as JsonCompatible
        XCTAssertEqual(messageWithExtras.messageSize(), 11)

        // object data: {"k":"你😊"} JSON-stringified is 11 UTF-16 code units.
        let messageWithJSONData = Message(name: nil, data: ["k": "你😊"])
        XCTAssertEqual(messageWithJSONData.messageSize(), 11)
    }

    /// - TM2s
    /// - TM2s1
    /// - TM2s2
    func test__025_Utilities__message_should_populate_serial_timestamp_to_version() throws {
        beforeEach__Utilities__JSON_Encoder()
        var json = """
        {
            "messages": [
                {
                    "action": 0,
                    "timestamp": 12345,
                    "serial": "123"
                }
            ]
        }
        """
        var data = json.data(using: .utf8)!
        var pm = try jsonEncoder.decodeProtocolMessage(data)
        var messages = try XCTUnwrap(pm.messages)
        XCTAssert(messages[0].action == .create)
        XCTAssert(messages[0].serial == "123")
        XCTAssert(messages[0].version?.serial == "123")
        XCTAssert(messages[0].timestamp == Date(timeIntervalSince1970: 12.345))
        XCTAssert(messages[0].version?.timestamp == Date(timeIntervalSince1970: 12.345))

        // for update
        json = """
        {
           "messages": [
               {
                   "action": 1,
                   "timestamp": 12345,
                   "serial": "123"
               }
           ]
        }
        """
        data = json.data(using: .utf8)!
        pm = try jsonEncoder.decodeProtocolMessage(data)
        messages = try XCTUnwrap(pm.messages)
        XCTAssert(messages[0].action == .update)
        XCTAssert(messages[0].serial == "123")
        XCTAssert(messages[0].version?.serial == "123")
        XCTAssert(messages[0].timestamp == Date(timeIntervalSince1970: 12.345))
        XCTAssert(messages[0].version?.timestamp == Date(timeIntervalSince1970: 12.345))

        // partial
        json = """
        {
            "messages": [
                {
                    "action": 0,
                    "timestamp": 12345,
                    "serial": "123",
                    "version": {
                       "serial": "124",
                       "clientId": "testClient",
                       "description": "test operation"
                    }
                }
            ]
        }
        """
        data = json.data(using: .utf8)!
        pm = try jsonEncoder.decodeProtocolMessage(data)
        messages = try XCTUnwrap(pm.messages)
        XCTAssert(messages[0].action == .create)
        XCTAssert(messages[0].serial == "123")
        XCTAssert(messages[0].version?.serial == "124")
        XCTAssert(messages[0].version?.clientId == "testClient")
        XCTAssert(messages[0].version?.descriptionText == "test operation")
        XCTAssert(messages[0].timestamp == Date(timeIntervalSince1970: 12.345))
        XCTAssert(messages[0].version?.timestamp == Date(timeIntervalSince1970: 12.345))
    }

    /// - TM8a
    /// - TM2u
    func test__026_Utilities__message_should_always_populate_annotations_and_summary_when_decoding() throws {
        beforeEach__Utilities__JSON_Encoder()

        // Test with minimal message - no annotations field
        let json1 = """
        {
            "messages": [
                {
                    "action": 0,
                    "serial": "123"
                }
            ]
        }
        """
        let data1 = json1.data(using: .utf8)!
        let pm1 = try jsonEncoder.decodeProtocolMessage(data1)
        let messages1 = try XCTUnwrap(pm1.messages)
        let message1 = messages1[0]

        // Verify annotations are always populated
        XCTAssertNotNil(message1.annotations, "message.annotations should always be populated")
        XCTAssertNotNil(message1.annotations?.summary, "message.annotations.summary should always be populated")

        // Test with empty annotations object
        let json2 = """
        {
            "messages": [
                {
                    "action": 0,
                    "serial": "456",
                    "annotations": {}
                }
            ]
        }
        """
        let data2 = json2.data(using: .utf8)!
        let pm2 = try jsonEncoder.decodeProtocolMessage(data2)
        let messages2 = try XCTUnwrap(pm2.messages)
        let message2 = messages2[0]

        // Verify annotations are always populated even with empty annotations object
        XCTAssertNotNil(message2.annotations, "message.annotations should always be populated")
        XCTAssertNotNil(message2.annotations?.summary, "message.annotations.summary should always be populated when not provided")

        // Test with annotations containing summary
        let json3 = """
        {
            "messages": [
                {
                    "action": 0,
                    "serial": "789",
                    "annotations": {
                        "summary": {"count": 5, "type": "test"}
                    }
                }
            ]
        }
        """
        let data3 = json3.data(using: .utf8)!
        let pm3 = try jsonEncoder.decodeProtocolMessage(data3)
        let messages3 = try XCTUnwrap(pm3.messages)
        let message3 = messages3[0]

        // Verify annotations and summary are properly decoded
        XCTAssertNotNil(message3.annotations, "message.annotations should be populated")
        XCTAssertNotNil(message3.annotations?.summary, "message.annotations.summary should be populated")
        if let summary = message3.annotations?.summary as? [String: Any] {
            XCTAssertEqual(summary["count"] as? Int, 5)
            XCTAssertEqual(summary["type"] as? String, "test")
        } else {
            XCTFail("summary should be a dictionary with expected values")
        }
    }

    /// TM2s
    func test__027_Utilities__message_received_with_new_version_structure() throws {
        beforeEach__Utilities__JSON_Encoder()
        let json = """
        {
            "messages": [
                {
                    "action": 0,
                    "serial": "123",
                    "timestamp": 1234512340,
                    "version": {
                        "serial": "124",
                        "timestamp": 1234512345,
                        "clientId": "testClient",
                        "description": "test operation",
                        "metadata": {"key": "value"}
                    }
                }
            ]
        }
        """
        let data = json.data(using: .utf8)!
        let pm = try jsonEncoder.decodeProtocolMessage(data)
        let messages = try XCTUnwrap(pm.messages)
        let message = messages[0]

        XCTAssert(message.action == .create)
        XCTAssertNotNil(message.version)
        XCTAssert(message.serial == "123")
        XCTAssert(message.timestamp == Date(timeIntervalSince1970: 1234512.340))
        XCTAssert(message.version?.serial == "124")
        XCTAssert(message.version?.timestamp == Date(timeIntervalSince1970: 1234512.345))
        XCTAssert(message.version?.clientId == "testClient")
        XCTAssert(message.version?.descriptionText == "test operation")
        XCTAssertNotNil(message.version?.metadata)
        if let metadata = message.version?.metadata as? [String: Any] {
            XCTAssertEqual(metadata["key"] as? String, "value")
        } else {
            XCTFail("metadata should be a dictionary with expected values")
        }
        XCTAssertNotNil(message.annotations)
        XCTAssertNotNil(message.annotations?.summary)
    }

    /// TM2s
    /// TM8a
    /// TM2u
    func test__028_Utilities__message_encoding_with_version_and_annotations() throws {
        beforeEach__Utilities__JSON_Encoder()

        // Create a message with version and annotations
        let message = Message()
        message.action = .create
        message.serial = "123"
        message.timestamp = Date(timeIntervalSince1970: 1234512340)

        // Create version with all fields
        let version = MessageVersion()
        version.serial = "124"
        version.timestamp = Date(timeIntervalSince1970: 1234512345)
        version.clientId = "testClient"
        version.descriptionText = "test operation"
        version.metadata = ["key": "value"]
        message.version = version

        // Create annotations with summary
        let annotations = MessageAnnotations()
        annotations.summary = ["count": 5, "type": "test"]
        message.annotations = annotations

        // Encode the message
        let encodedDict = jsonEncoder.message(toDictionary: message)
        let data = try JSONSerialization.data(withJSONObject: encodedDict, options: [])
        let jsonObject = try JSONSerialization.jsonObject(with: data, options: []) as! [String: Any]

        XCTAssertEqual(jsonObject["serial"] as? String, "123")
        let encodedVersion = jsonObject["version"] as! [String: Any]
        XCTAssertEqual(encodedVersion["serial"] as? String, "124")
        XCTAssertEqual(encodedVersion["clientId"] as? String, "testClient")
        XCTAssertEqual(encodedVersion["description"] as? String, "test operation")
        let encodedMetadata = encodedVersion["metadata"] as! [String: Any]
        XCTAssertEqual(encodedMetadata["key"] as? String, "value")
    }
}
