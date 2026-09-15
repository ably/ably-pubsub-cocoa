import AblyPubSubDevice.Private

/// A mock implementation of `RetryDelayCalculator`, whose `delay(forRetryNumber:)` method returns values from a provided array.
class MockRetryDelayCalculator: RetryDelayCalculator {
    private let delays: [TimeInterval]

    /// Creates a retry delay calculator whose `delay(forRetryNumber:)` method returns values from a provided sequence.
    ///
    /// - Parameters:
    ///     - delays: A sequence of time intervals. The created retry delay calculator's `delay(forRetryNumber:)` method will return the `(retryNumber - 1)`-th element of this array.
    init(delays: [TimeInterval]) {
        self.delays = delays
    }

    func delay(forRetryNumber retryNumber: Int) -> TimeInterval {
        delays[retryNumber - 1]
    }
}
