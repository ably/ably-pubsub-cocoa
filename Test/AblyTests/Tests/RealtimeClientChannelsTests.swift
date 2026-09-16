import AblyPubSubDevice
import Nimble
import XCTest

#if hasFeature(RetroactiveAttribute)
// Swift isn't yet smart enough to do this automatically when bridging Objective-C APIs
extension ARTRealtimeChannels: @retroactive Sequence {
    public func makeIterator() -> NSFastEnumerationIterator {
        return NSFastEnumerationIterator(iterate())
    }
}
#else
// Swift isn't yet smart enough to do this automatically when bridging Objective-C APIs
extension ARTRealtimeChannels: Sequence {
    public func makeIterator() -> NSFastEnumerationIterator {
        return NSFastEnumerationIterator(iterate())
    }
}
#endif

class RealtimeClientChannelsTests: XCTestCase {
    // RTS2
    func test__001__Channels__should_exist_methods_to_check_if_a_channel_exists_or_iterate_through_the_existing_channels() throws {
        let test = Test()
        let client = ARTRealtimeClient(options: try AblyTests.commonAppSetup(for: test))
        defer { client.dispose(); client.close() }
        var disposable = [String]()

        let channelName1 = test.uniqueChannelName(prefix: "1")
        let channelName2 = test.uniqueChannelName(prefix: "2")
        let channelName3 = test.uniqueChannelName(prefix: "3")

        disposable.append(client.channels.get(channelName1).name)
        disposable.append(client.channels.get(channelName2).name)
        disposable.append(client.channels.get(channelName3).name)

        XCTAssertNotNil(client.channels.get(channelName2))
        XCTAssertTrue(client.channels.exists(channelName2))
        XCTAssertFalse(client.channels.exists("testX"))

        for channel in client.channels {
            XCTAssertTrue(disposable.contains((channel as! ARTRealtimeChannel).name))
        }
    }

    // RTS3

    // RTS3a
    func test__002__Channels__get__should_create_a_new_Channel_if_none_exists_or_return_the_existing_one() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = ARTRealtimeClient(options: options)
        defer { client.dispose(); client.close() }

        XCTAssertEqual(client.channels.internal.collection.count, 0)
        let channelName = test.uniqueChannelName()
        let channel = client.channels.get(channelName)
        XCTAssertEqual(channel.name, "\(options.testOptions.channelNamePrefix!)-\(channelName)")

        XCTAssertEqual(client.channels.internal.collection.count, 1)
        XCTAssertTrue(client.channels.get(channelName).internal === channel.internal)
        XCTAssertEqual(client.channels.internal.collection.count, 1)
    }

    // RTS3b
    func test__003__Channels__get__should_be_possible_to_specify_a_ChannelOptions() throws {
        let test = Test()
        let client = ARTRealtimeClient(options: try AblyTests.commonAppSetup(for: test))
        defer { client.dispose(); client.close() }
        let options = ARTRealtimeChannelOptions()
        let channel = client.channels.get(test.uniqueChannelName(), options: options)
        XCTAssertTrue(channel.options === options)
    }

    // RTS3c
    func test__004__Channels__get__accessing_an_existing_Channel_with_options_should_update_the_options_and_then_return_the_object() throws {
        let test = Test()
        let client = ARTRealtimeClient(options: try AblyTests.commonAppSetup(for: test))
        defer { client.dispose(); client.close() }
        let channelName = test.uniqueChannelName()
        XCTAssertNil(client.channels.get(channelName).options)
        let options = ARTRealtimeChannelOptions()
        let channel = client.channels.get(channelName, options: options)
        XCTAssertTrue(channel.options === options)
    }

    // RTS4

    func test__005__Channels__release__should_release_a_channel() throws {
        let test = Test()
        let client = ARTRealtimeClient(options: try AblyTests.commonAppSetup(for: test))
        defer { client.dispose(); client.close() }

        let channelName = test.uniqueChannelName()
        let channel = client.channels.get(channelName)
        channel.subscribe { _ in
            fail("shouldn't happen")
        }
        channel.presence.subscribe { _ in
            fail("shouldn't happen")
        }
        waitUntil(timeout: testTimeout) { done in
            client.channels.release(channelName) { errorInfo in
                XCTAssertNil(errorInfo)
                XCTAssertEqual(channel.state, ARTRealtimeChannelState.detached)
                done()
            }
        }

        let sameChannel = client.channels.get(channelName)
        waitUntil(timeout: testTimeout) { done in
            sameChannel.subscribe { _ in
                sameChannel.presence.enterClient("foo", data: nil) { _ in
                    delay(0.0) { done() } // Delay to make sure EventEmitter finish its cycle.
                }
            }
            sameChannel.publish("foo", data: nil)
        }
    }

    // RTS4b
    func test__006__Channels__release__should_log_a_deprecation_warning_when_releasing_an_attached_channel() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.logHandler = ARTLog(capturingOutput: true)
        let client = ARTRealtime(options: options)
        defer { client.dispose(); client.close() }

        let channelName = test.uniqueChannelName()
        let channel = client.channels.get(channelName)
        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                XCTAssertNil(error)
                done()
            }
        }

        waitUntil(timeout: testTimeout) { done in
            client.channels.release(channelName) { errorInfo in
                XCTAssertNil(errorInfo)
                XCTAssertEqual(channel.state, ARTRealtimeChannelState.detached)
                done()
            }
        }
        XCTAssertFalse(client.channels.exists(channelName))

        let deprecationWarnings = options.logHandler.captured.filter { $0.level == .warn && $0.message.contains("is deprecated") }
        XCTAssertEqual(deprecationWarnings.count, 1)
        expect(deprecationWarnings.first?.message).to(contain("in the attached state"))
    }

    // RTS4d
    func test__007__Channels__release__should_not_log_a_deprecation_warning_when_releasing_a_detached_channel() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.logHandler = ARTLog(capturingOutput: true)
        let client = ARTRealtime(options: options)
        defer { client.dispose(); client.close() }

        let channelName = test.uniqueChannelName()
        let channel = client.channels.get(channelName)
        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                XCTAssertNil(error)
                channel.detach { error in
                    XCTAssertNil(error)
                    done()
                }
            }
        }
        XCTAssertEqual(channel.state, ARTRealtimeChannelState.detached)

        client.channels.release(channelName)
        XCTAssertFalse(client.channels.exists(channelName))

        let deprecationWarnings = options.logHandler.captured.filter { $0.message.contains("is deprecated") }
        XCTAssertTrue(deprecationWarnings.isEmpty)
    }
}
