// Swift does not import the SDK's callback methods as `async` functions itself: the callback parameters aren't named like completion handlers, and their error parameter is an `ARTErrorInfo` rather than exactly an `NSError`. These helpers do the bridging for the extensions in this module.
//
// The helpers, and every `async` function in this module, are `nonisolated(nonsending)`: they run on the caller's actor, so the SDK object they are called on and the arguments a caller passes in, such as message data, are never sent across an isolation boundary.

/// Calls an operation whose callback only reports an error, and throws that error.
nonisolated(nonsending) internal func withErrorCallback(
    _ operation: (@escaping Callback) -> Void
) async throws(ErrorInfo) {
    try await withCheckedContinuation { (continuation: CheckedContinuation<Result<Void, ErrorInfo>, Never>) in
        operation { error in
            if let error {
                continuation.resume(returning: .failure(error))
            } else {
                continuation.resume(returning: .success(()))
            }
        }
    }.get()
}

/// Calls an operation whose callback reports a result or an error, and returns the result or throws the error.
///
/// The SDK can call back with neither, for example when the server acknowledges a publish without reporting its serials. That is a success, so the result is optional rather than an error.
///
/// The result crosses from the SDK's callback queue to the caller, so it must be `Sendable`. Don't wrap a non-`Sendable` result to get around this: the SDK may still be using the object.
nonisolated(nonsending) internal func withResultCallback<Result: Sendable>(
    _ operation: (@escaping (Result?, ErrorInfo?) -> Void) -> Void
) async throws(ErrorInfo) -> Result? {
    try await withCheckedContinuation { (continuation: CheckedContinuation<Swift.Result<Result?, ErrorInfo>, Never>) in
        operation { result, error in
            if let error {
                continuation.resume(returning: .failure(error))
            } else {
                continuation.resume(returning: .success(result))
            }
        }
    }.get()
}
