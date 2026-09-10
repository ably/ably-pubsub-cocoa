@testable import AblyLiveObjects
import Foundation

/// A mock implementation of SimpleClock for testing purposes.
final class MockSimpleClock: SimpleClock {
    private let mutex = NSLock()

    /// The current time that this mock clock will return.
    private nonisolated(unsafe) var currentTime: Date

    /// Creates a new MockSimpleClock with the specified current time.
    /// - Parameter currentTime: The time that this clock should return. Defaults to the current system time.
    init(currentTime: Date = Date()) {
        self.currentTime = currentTime
    }

    /// Returns the current time set for this mock clock.
    var now: Date {
        mutex.withLock {
            currentTime
        }
    }

    /// Updates the current time of this mock clock.
    /// - Parameter newTime: The new time to set.
    func setTime(_ newTime: Date) {
        mutex.withLock {
            currentTime = newTime
        }
    }

    /// Advances the clock by the specified time interval.
    /// - Parameter interval: The time interval to advance by.
    func advance(by interval: TimeInterval) {
        mutex.withLock {
            currentTime = currentTime.addingTimeInterval(interval)
        }
    }
}
