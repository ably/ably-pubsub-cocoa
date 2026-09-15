import XCTest
import AblyTesting
import AblyPubSubDevice.Private

class AttachRetryStateTests: XCTestCase {
    func test_addRetryAttempt() {
        // Given: an AttachRetryState initialized with a delay calculator that returns arbitrary values from its `delay(forRetryNumber:)` method...
        let delays: [TimeInterval] = [0.1, 0.3, 0.9]
        let calculator = MockRetryDelayCalculator(delays: delays)

        let retryState = AttachRetryState(retryDelayCalculator: calculator,
                                          logger: .init(core: MockInternalLogCore()),
                                          logMessagePrefix: "")

        // When: addRetryAttempt is called an arbitrarily-chosen number n ( = 3) times on the attach retry state...
        let firstRetryAttempt = retryState.addRetryAttempt()
        let secondRetryAttempt = retryState.addRetryAttempt()
        let thirdRetryAttempt = retryState.addRetryAttempt()

        // Then: the list of `delay` properties of the returned RetryAttempt objects matches those returned by the calculator's `delay(forRetryNumber: x)` method for x = 1, ... , n.
        XCTAssertEqual(firstRetryAttempt.delay, delays[0])
        XCTAssertEqual(secondRetryAttempt.delay, delays[1])
        XCTAssertEqual(thirdRetryAttempt.delay, delays[2])
    }

    func test_transitionToNonAttachingOrSuspendedStateResetsRetrySequence() {
        // Given: an AttachRetryState initialized with a delay calculator that returns arbitrary values from its `delay(forRetryNumber:)` method...
        let delays: [TimeInterval] = [0.1, 0.3, 0.9]
        let calculator = MockRetryDelayCalculator(delays: delays)

        let retryState = AttachRetryState(retryDelayCalculator: calculator,
                                          logger: .init(core: MockInternalLogCore()),
                                          logMessagePrefix: "")

        // When: addRetryAttempt is called an arbitrarily-chosen number n ( = 3) times on the attach retry state, and then channelWillTransition(to:) is called on the attach retry state with a channel state that is not SUSPENDED or ATTACHING (arbitrarily chosen ATTACHED here), and addRetryAttempt is then called again on the attach retry state...
        (0..<3).forEach { _ in let _ = retryState.addRetryAttempt() }
        retryState.channelWillTransition(to: .attached)
        let retryAttempt = retryState.addRetryAttempt()

        // Then: the `delay` property of the post-channelWillTransition(to:) returned RetryAttempt object matches that returned by the calculator's `delay(forRetryNumber: 1)` method.
        XCTAssertEqual(retryAttempt.delay, delays[0])
    }

    func test_transitionToAttachingOrSuspendedStateDoesNotResetRetrySequence() {
        // Given: an AttachRetryState initialized with a delay calculator that returns arbitrary values from its `delay(forRetryNumber:)` method...
        let delays: [TimeInterval] = [0.1, 0.3, 0.9, 0.7]
        let calculator = MockRetryDelayCalculator(delays: delays)

        let retryState = AttachRetryState(retryDelayCalculator: calculator,
                                          logger: .init(core: MockInternalLogCore()),
                                          logMessagePrefix: "")

        // When: addRetryAttempt is called an arbitrarily-chosen number n ( = 3) times on the attach retry state, and then channelWillTransition(to:) is called on the attach retry state, once with channel state SUSPENDED and once with channel state ATTACHING, and addRetryAttempt is then called again on the attach retry state...
        (0..<3).forEach { _ in let _ = retryState.addRetryAttempt() }
        retryState.channelWillTransition(to: .suspended)
        retryState.channelWillTransition(to: .attaching)
        let retryAttempt = retryState.addRetryAttempt()

        // Then: the `delay` property of the post-channelWillTransition(to:) returned RetryAttempt object matches that returned by the calculator's `delay(forRetryNumber: n + 1)` method.
        XCTAssertEqual(retryAttempt.delay, delays[3])
    }
}
