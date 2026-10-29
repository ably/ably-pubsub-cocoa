import XCTest
import AblyPubSubDevice.Private
import AblyTesting

class ConnectRetryStateTests: XCTestCase {
    func test_addRetryAttempt() {
        // Given: an ConnectRetryState initialized with a delay calculator that returns arbitrary values from its `delay(forRetryNumber:)` method...
        let delays: [TimeInterval] = [0.1, 0.3, 0.9]
        let calculator = MockRetryDelayCalculator(delays: delays)

        let retryState = ConnectRetryState(retryDelayCalculator: calculator,
                                          logger: .init(core: MockInternalLogCore()),
                                          logMessagePrefix: "")

        // When: addRetryAttempt is called an arbitrarily-chosen number n ( = 3) times on the connect retry state...
        let firstRetryAttempt = retryState.addRetryAttempt()
        let secondRetryAttempt = retryState.addRetryAttempt()
        let thirdRetryAttempt = retryState.addRetryAttempt()

        // Then: the list of `delay` properties of the returned RetryAttempt objects matches those returned by the calculator's `delay(forRetryNumber: x)` method for x = 1, ... , n.
        XCTAssertEqual(firstRetryAttempt.delay, delays[0])
        XCTAssertEqual(secondRetryAttempt.delay, delays[1])
        XCTAssertEqual(thirdRetryAttempt.delay, delays[2])
    }

    func test_transitionToNonConnectingOrDisconnectedStateResetsRetrySequence() {
        // Given: an ConnectRetryState initialized with a delay calculator that returns arbitrary values from its `delay(forRetryNumber:)` method...
        let delays: [TimeInterval] = [0.1, 0.3, 0.9]
        let calculator = MockRetryDelayCalculator(delays: delays)

        let retryState = ConnectRetryState(retryDelayCalculator: calculator,
                                           logger: .init(core: MockInternalLogCore()),
                                           logMessagePrefix: "")

        // When: addRetryAttempt is called an arbitrarily-chosen number n ( = 3) times on the connect retry state, and then connectionWillTransition(to:) is called on the connect retry state with a connection state that is not CONNECTING or DISCONNECTED (arbitrarily chosen CONNECTED here), and addRetryAttempt is then called again on the connect retry state...
        (0..<3).forEach { _ in let _ = retryState.addRetryAttempt() }
        retryState.connectionWillTransition(to: .connected)
        let retryAttempt = retryState.addRetryAttempt()

        // Then: the `delay` property of the post-connectionWillTransition(to:) returned RetryAttempt object matches that returned by the calculator's `delay(forRetryNumber: 1)` method.
        XCTAssertEqual(retryAttempt.delay, delays[0])
    }

    func test_transitionToConnectingOrDisconnectedStateDoesNotResetRetrySequence() {
        // Given: an ConnectRetryState initialized with a delay calculator that returns arbitrary values from its `delay(forRetryNumber:)` method...
        let delays: [TimeInterval] = [0.1, 0.3, 0.9, 0.7]
        let calculator = MockRetryDelayCalculator(delays: delays)

        let retryState = ConnectRetryState(retryDelayCalculator: calculator,
                                           logger: .init(core: MockInternalLogCore()),
                                           logMessagePrefix: "")

        // When: addRetryAttempt is called an arbitrarily-chosen number n ( = 3) times on the connect retry state, and then connectionWillTransition(to:) is called on the connect retry state, once with connection state CONNECTING and once with connection state DISCONNECTED, and addRetryAttempt is then called again on the connect retry state...
        (0..<3).forEach { _ in let _ = retryState.addRetryAttempt() }
        retryState.connectionWillTransition(to: .connecting)
        retryState.connectionWillTransition(to: .disconnected)
        let retryAttempt = retryState.addRetryAttempt()

        // Then: the `delay` property of the post-connectionWillTransition(to:) returned RetryAttempt object matches that returned by the calculator's `delay(forRetryNumber: n + 1)` method.
        XCTAssertEqual(retryAttempt.delay, delays[3])
    }
}
