import AblyPubSubDevice
import AblyPubSubDevice.Private
import XCTest

class BackoffRetryDelayCalculatorTests: XCTestCase {
    func test_delay() {
        let initialRetryTimeout = 0.5 // arbitrarily chosen

        let jitterCoefficients = StaticJitterCoefficients()
        let mockJitterCoefficientGenerator = MockJitterCoefficientGenerator(coefficients: jitterCoefficients)

        let expectedDelays = AblyTests.expectedRetryDelays(forTimeout: initialRetryTimeout, jitterCoefficients: jitterCoefficients)

        let calculator = BackoffRetryDelayCalculator(
            initialRetryTimeout: initialRetryTimeout,
            jitterCoefficientGenerator: mockJitterCoefficientGenerator
        )

        let calculatedDelays = (1...).lazy.map { calculator.delay(forRetryNumber: $0) }

        let sampleSize = 10 // arbitrarily chosen, large enough so that we see the initial values and then the constant tail
        XCTAssertEqual(Array(calculatedDelays.prefix(sampleSize)), Array(expectedDelays.prefix(sampleSize)))
    }
}
