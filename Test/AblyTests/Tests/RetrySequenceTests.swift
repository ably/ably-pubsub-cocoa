import XCTest
import AblyPubSubDevice.Private

class RetrySequenceTests: XCTestCase {
    func test_addRetryAttempt() {
        // Given: a RetrySequence initialized with a delay calculator that returns arbitrary values from its `delay(forRetryNumber:)` method...
        let delays: [TimeInterval] = [0.1, 0.3, 0.9]
        let calculator = MockRetryDelayCalculator(delays: delays)

        let sequence = RetrySequence(delayCalculator: calculator)

        // When: addRetryAttempt is called an arbitrarily-chosen number n ( = 3) times on the retry sequence...
        let firstRetryAttempt = sequence.addRetryAttempt()
        let secondRetryAttempt = sequence.addRetryAttempt()
        let thirdRetryAttempt = sequence.addRetryAttempt()

        // Then: the list of `delay` properties of the returned RetryAttempt objects matches those returned by the calculator's `delay(forRetryNumber: x)` method for x = 1, ... , n.
        XCTAssertEqual(firstRetryAttempt.delay, delays[0])
        XCTAssertEqual(secondRetryAttempt.delay, delays[1])
        XCTAssertEqual(thirdRetryAttempt.delay, delays[2])
    }
}
