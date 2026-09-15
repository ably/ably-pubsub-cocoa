import AblyPubSubDevice.Private

/// A mock instance of `JitterCoefficientGenerator`, whose `generateJitterCoefficient()` method returns values from a provided sequence.
///
/// This class can safely be used across threads.
class MockJitterCoefficientGenerator: JitterCoefficientGenerator {
    private var iterator: any IteratorProtocol<Double>
    private let semaphore = DispatchSemaphore(value: 1)

    /// Creates a jitter coefficient generator whose `generateJitterCoefficient()` method returns values from a provided sequence.
    ///
    /// - Params:
    ///     - coefficients: A sequence of values, each in the range (0.8 ... 1). If `generateJitterCoefficient()` is called when there are no values left to iterate in the sequence, a runtime exception will occur.
    init(coefficients: some Sequence<Double>) {
        self.iterator = coefficients.makeIterator()
    }

    func generateJitterCoefficient() -> Double {
        semaphore.wait()
        guard let coefficient = iterator.next() else {
            fatalError("Ran out of jitter coefficients")
        }
        semaphore.signal()
        precondition((0.8...1.0).contains(coefficient))
        return coefficient
    }
}
