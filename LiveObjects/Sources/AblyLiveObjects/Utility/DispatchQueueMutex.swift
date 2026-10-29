import Foundation

/// A class that provides mutually exclusive access to a value using a serial dispatch queue.
///
/// In order to access or mutate the mutex's value, it is expected that you know whether or not you are already executing on the mutex's queue. If you are, then use ``withoutSync(_:)``, which simply performs a runtime check that the current queue is correct. If not, then use ``withSync(_:)``, which synchronously dispatches to the queue. ``withSync(_:)`` must not be called from the queue, as doing so would cause a deadlock (there is a runtime check which terminates execution in this case).
///
/// This class is styled on Swift's built-in `Mutex` type.
internal final class DispatchQueueMutex<T>: Sendable {
    /// The queue that this mutex uses to synchronise access to the wrapped value.
    internal let dispatchQueue: DispatchQueue

    private nonisolated(unsafe) var value: T

    internal init(dispatchQueue: DispatchQueue, initialValue: T) {
        self.dispatchQueue = dispatchQueue
        value = initialValue
    }

    /// Provides access to the wrapped value by dispatching synchronously to the dispatch queue.
    ///
    /// - Parameters:
    ///   - body: The action to perform. It can read and/or mutate the wrapped value.
    ///
    /// - Warning: This must only be called when not already on the dispatch queue. Violating this precondition will result in a runtime error.
    internal func withSync<R, E>(_ body: (inout T) throws(E) -> R) throws(E) -> R {
        let result: Result<R, E> = dispatchQueue.ably_syncNoDeadlock {
            do throws(E) {
                return try .success(body(&value))
            } catch {
                return .failure(error)
            }
        }

        return try result.get()
    }

    /// Provides access to the wrapped value without dispatching to the dispatch queue.
    ///
    /// - Parameters:
    ///   - body: The action to perform. It can read and/or mutate the wrapped value.
    ///
    /// - Warning: This must only be called when already on the dispatch queue. Violating this precondition will result in a runtime error.
    internal func withoutSync<R, E>(_ body: (inout T) throws(E) -> R) throws(E) -> R {
        dispatchPrecondition(condition: .onQueue(dispatchQueue))

        return try body(&value)
    }
}
