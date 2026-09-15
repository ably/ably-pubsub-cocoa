import AblyPubSubDevice
import Nimble
import XCTest

#if hasFeature(RetroactiveAttribute)
// Swift isn't yet smart enough to do this automatically when bridging Objective-C APIs
extension ARTRestChannels: @retroactive Sequence {
    public func makeIterator() -> NSFastEnumerationIterator {
        return NSFastEnumerationIterator(iterate())
    }
}
#else
extension ARTRestChannels: Sequence {
    public func makeIterator() -> NSFastEnumerationIterator {
        return NSFastEnumerationIterator(iterate())
    }
}
#endif

private func beAChannel(named expectedValue: String) -> Nimble.Predicate<ARTChannel> {
    return Predicate.define("be a channel with name \"\(expectedValue)\"") { actualExpression, msg -> PredicateResult in
        let actualValue = try actualExpression.evaluate()
        let m = msg.appended(details: "\"\(actualValue?.name ?? "nil")\" instead")
        return PredicateResult(status: PredicateStatus(bool: actualValue?.name == expectedValue), message: m)
    }
}

private var client: ARTRest!
private var channelName: String!

private let cipherParams: ARTCipherParams? = nil

class RestClientChannelsTests: XCTestCase {
    // XCTest invokes this method before executing the first test in the test suite. We use it to ensure that the global variables are initialized at the same moment, and in the same order, as they would have been when we used the Quick testing framework.
    override class var defaultTestSuite: XCTestSuite {
        _ = client
        _ = channelName
        _ = cipherParams

        return super.defaultTestSuite
    }

    override func setUp() {
        super.setUp()

        client = ARTRest(key: "fake:key")
        channelName = ProcessInfo.processInfo.globallyUniqueString
    }

    // RSN1
    func test__001__RestClient__channels__should_return_collection_of_channels() {
        let _: ARTRestChannels = client.channels
    }

    // RSN3

    // RSN3a
    func test__003__RestClient__channels__get__should_return_a_channel() {
        let channel = client.channels.get(channelName).internal
        expect(channel).to(beAChannel(named: channelName))

        let sameChannel = client.channels.get(channelName).internal
        XCTAssertTrue(sameChannel === channel)
    }

    // RSN3b
    func test__004__RestClient__channels__get__should_return_a_channel_with_the_provided_options() {
        let options = ARTChannelOptions(cipher: cipherParams)
        let channel = client.channels.get(channelName, options: options)

        expect(channel.internal).to(beAChannel(named: channelName))
        XCTAssertTrue(channel.internal.options === options)
    }

    // RSN3b
    func test__005__RestClient__channels__get__should_not_replace_the_options_on_an_existing_channel_when_none_are_provided() {
        let options = ARTChannelOptions(cipher: cipherParams)
        let channel = client.channels.get(channelName, options: options).internal

        let newButSameChannel = client.channels.get(channelName).internal

        XCTAssertTrue(newButSameChannel === channel)
        XCTAssertTrue(newButSameChannel.options === options)
    }

    // RSN3c
    func test__006__RestClient__channels__get__should_replace_the_options_on_an_existing_channel_when_new_ones_are_provided() {
        let channel = client.channels.get(channelName).internal
        let oldOptions = channel.options

        let newOptions = ARTChannelOptions(cipher: cipherParams)
        let newButSameChannel = client.channels.get(channelName, options: newOptions).internal

        XCTAssertTrue(newButSameChannel === channel)
        XCTAssertTrue(newButSameChannel.options === newOptions)
        expect(newButSameChannel.options).notTo(beIdenticalTo(oldOptions))
    }

    // RSN2

    func test__007__RestClient__channels__channelExists__should_check_if_a_channel_exists() {
        XCTAssertFalse(client.channels.exists(channelName))

        client.channels.get(channelName)

        XCTAssertTrue(client.channels.exists(channelName))
    }

    // RSN4

    func test__008__RestClient__channels__releaseChannel__should_release_a_channel() {
        weak var channel: ARTRestChannelInternal!

        autoreleasepool {
            channel = client.channels.get(channelName).internal

            expect(channel).to(beAChannel(named: channelName))
            client.channels.release(channel.name)
        }

        XCTAssertNil(channel)
    }

    // RSN2
    func test__002__RestClient__channels__should_be_enumerable() {
        let channels = [
            client.channels.get(channelName).internal,
            client.channels.get(String(channelName.reversed())).internal,
        ]

        for channel in client.channels {
            expect(channels).to(contain((channel as! ARTRestChannel).internal))
        }
    }
}
