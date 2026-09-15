import AblyPubSubDevice
import AblyDeltaCodec
import Nimble
import XCTest

// Test all RSL4 message data types
private let testData: [NSObject?] = [
    // String data
    "{ foo: \"bar\", count: 1, status: \"active\" }" as NSString,
    "{ foo: \"bar\", count: 2, status: \"active\" }" as NSString,
    "{ foo: \"bar\", count: 2, status: \"inactive\" }" as NSString,
    // Binary data
    Data(Array(repeating: 0x01, count: 20) + [0x01]) as NSData,
    Data(Array(repeating: 0x01, count: 20) + [0x02]) as NSData,
    Data(Array(repeating: 0x01, count: 20) + [0x03]) as NSData,
    // JSON data
    Array(repeating: "bar", count: 20) + ["bar"] as NSArray,
    Array(repeating: "bar", count: 20) + ["baz"] as NSArray,
    Array(repeating: "bar", count: 20) + ["bar"] as NSArray,
    // nil data
    nil,
]

class DeltaCodecTests: XCTestCase {
    // XCTest invokes this method before executing the first test in the test suite. We use it to ensure that the global variables are initialized at the same moment, and in the same order, as they would have been when we used the Quick testing framework.
    override class var defaultTestSuite: XCTestSuite {
        _ = testData

        return super.defaultTestSuite
    }

    // RTL19
    func parameterizedTest__001__DeltaCodec__decoding__should_decode_vcdiff_encoded_messages(useBinaryProtocol: Bool) throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.useBinaryProtocol = useBinaryProtocol
        let client = AblyTests.newRealtime(options).client
        defer { client.dispose(); client.close() }

        let channelOptions = ARTRealtimeChannelOptions()
        channelOptions.modes = [.subscribe, .publish]
        channelOptions.params = [
            "delta": "vcdiff",
        ]

        let channel = client.channels.get(test.uniqueChannelName(), options: channelOptions)

        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                XCTAssertNil(error)
                done()
            }
        }

        guard let transport = client.internal.transport as? TestProxyTransport else {
            fail("TestProxyTransport is not be assigned"); return
        }

        var receivedMessages: [ARTMessage] = []
        channel.subscribe { message in
            receivedMessages.append(message)
        }

        // We publish the messages sequentially, waiting for one publish to complete before performing the next. This is to ensure that Realtime uses deltas when sending the message to the subscription (there is a limit of concurrent delta generations and we don't want to exceed it; see https://ably-real-time.slack.com/archives/C07D55B6NLQ/p1754995949137159?thread_ts=1754992828.228879&cid=C07D55B6NLQ)
        func publishTestData(startingFromIndex index: Int, done: @escaping () -> Void) {
            channel.publish(String(index), data: testData[index]) { error in
                if let error {
                    fail("Error publishing message: \(error)")
                    return
                }

                if index + 1 < testData.endIndex {
                    publishTestData(startingFromIndex: index + 1, done: done)
                } else {
                    done()
                }
            }

        }
        waitUntil(timeout: testTimeout) { done in
            publishTestData(startingFromIndex: 0, done: done)
        }

        XCTAssertNil(channel.errorReason)
        expect(receivedMessages).toEventually(haveCount(testData.count))

        for (i, message) in receivedMessages.enumerated() {
            if let name = message.name, let expectedMessageIndex = Int(name) {
                XCTAssertEqual(i, expectedMessageIndex)
                XCTAssertEqual(message.data as? NSObject, testData[expectedMessageIndex])
            } else {
                fail("Received message has an unexpected 'id': \(message)")
            }
        }

        channel.unsubscribe()

        let protocolMessages = transport.protocolMessagesReceived.filter { $0.action == .message }
        let messagesReceivedInProtocolMessages = protocolMessages.reduce([]) { $0 + ($1.messages ?? []) }

        // Check that we did not receive more messages than we sent; this tells us that we successfully decoded the deltas and did not need to perform an RTL18 recovery.
        expect(messagesReceivedInProtocolMessages.count).to(equal(testData.count))

        let messagesEncoding = messagesReceivedInProtocolMessages.map(\.encoding)

        let expectedMessagesEncoding: [String?] = if useBinaryProtocol {
            // String data
            [nil] as [String?] + Array(repeating: "utf-8/vcdiff", count: 2) +
            // Binary data
            Array(repeating: "vcdiff", count: 3) +
            // JSON data
            Array(repeating: "json/utf-8/vcdiff", count: 3) +
            // nil data
            [nil] as [String?]
        } else {
            // String data
            [nil] as [String?] + Array(repeating: "utf-8/vcdiff/base64", count: 2) +
            // Binary data
            Array(repeating: "vcdiff/base64", count: 3) +
            // JSON data
            Array(repeating: "json/utf-8/vcdiff/base64", count: 3) +
            // nil data
            [nil] as [String?]
        }

        expect(messagesEncoding).to(equal(expectedMessagesEncoding))
    }

    func test__001__withBinaryProtocol_DeltaCodec__decoding__should_decode_vcdiff_encoded_messages() throws {
        try parameterizedTest__001__DeltaCodec__decoding__should_decode_vcdiff_encoded_messages(useBinaryProtocol: true)
    }

    func test__001__withoutBinaryProtocol_DeltaCodec__decoding__should_decode_vcdiff_encoded_messages() throws {
        try parameterizedTest__001__DeltaCodec__decoding__should_decode_vcdiff_encoded_messages(useBinaryProtocol: false)
    }

    // RTL20
    func test__002__DeltaCodec__decoding__should_fail_and_recover_when_the_vcdiff_messages_are_out_of_order() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = AblyTests.newRealtime(options).client
        defer { client.dispose(); client.close() }
        let channelOptions = ARTRealtimeChannelOptions()
        channelOptions.params = ["delta": "vcdiff"]
        let channel = client.channels.get(test.uniqueChannelName(), options: channelOptions)

        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                XCTAssertNil(error)
                done()
            }
        }

        guard let transport = client.internal.transport as? TestProxyTransport else {
            fail("TestProxyTransport is not be assigned"); return
        }

        transport.setBeforeIncomingMessageModifier { protocolMessage in
            if protocolMessage.action == .message,
               let thirdMessage = protocolMessage.messages?.filter({ $0.name == "2" }).first
            {
                thirdMessage.extras = [
                    "delta": [
                        "format": "vcdiff",
                        "from": "foo:1:0",
                    ],
                ] as NSDictionary
                transport.setBeforeIncomingMessageModifier(nil)
            }
            return protocolMessage
        }

        var receivedMessages: [ARTMessage] = []
        channel.subscribe { message in
            receivedMessages.append(message)
        }

        for (i, data) in testData.enumerated() {
            channel.publish(String(i), data: data)
        }

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)
            channel.once(.attaching) { stateChange in
                XCTAssertEqual(receivedMessages.count, 2) // third message and onward are discarded
                XCTAssertEqual(stateChange.reason?.code, ARTErrorCode.unableToDecodeMessage.intValue)
                partialDone()
            }
            channel.once(.attached) { _ in
                partialDone()
            }
        }

        expect(receivedMessages).toEventually(haveCount(testData.count))
    }

    // RTL18
    func test__003__DeltaCodec__decoding__should_recover_when_the_vcdiff_message_decoding_fails() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = AblyTests.newRealtime(options).client
        defer { client.dispose(); client.close() }
        let channelOptions = ARTRealtimeChannelOptions()
        channelOptions.params = ["delta": "vcdiff"]
        let channel = client.channels.get(test.uniqueChannelName(), options: channelOptions)

        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                XCTAssertNil(error)
                done()
            }
        }

        guard let transport = client.internal.transport as? TestProxyTransport else {
            fail("TestProxyTransport is not be assigned"); return
        }

        transport.setBeforeIncomingMessageModifier { protocolMessage in
            if protocolMessage.action == .message,
               let thirdMessage = protocolMessage.messages?.filter({ $0.name == "2" }).first
            {
                thirdMessage.data = Data() // invalid delta
                transport.setBeforeIncomingMessageModifier(nil)
            }
            return protocolMessage
        }

        var receivedMessages: [ARTMessage] = []
        channel.subscribe { message in
            receivedMessages.append(message)
        }

        for (i, data) in testData.enumerated() {
            channel.publish(String(i), data: data)
        }

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)
            channel.once(.attaching) { stateChange in
                XCTAssertEqual(receivedMessages.count, 2) // third message and onward are discarded
                guard let errorReason = stateChange.reason else {
                    fail("Reason should not be empty"); partialDone(); return
                }
                XCTAssertEqual(errorReason.code, ARTErrorCode.unableToDecodeMessage.intValue)
                partialDone()
            }
            channel.once(.attached) { _ in
                partialDone()
            }
        }

        expect(receivedMessages).toEventually(haveCount(testData.count))
    }
}
