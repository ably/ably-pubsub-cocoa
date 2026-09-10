import Foundation

/// Retries `body` up to `attempts` times against transient network stalls, with exponential
/// backoff between attempts (0.5s, 1s, 2s, …); the final attempt's error propagates. A cancelled
/// task propagates out of the throwing sleep instead of burning the remaining retries.
///
/// Intended for test-setup provisioning calls (sandbox app creation, fixture ingestion, tooling
/// downloads) where a single stalled request would otherwise fail every test sharing the result.
/// Callers are responsible for retry safety — e.g. the non-idempotent sandbox `POST /apps` is safe
/// because an orphaned app from a timed-out create is auto-deleted after a few minutes of no use.
public func withProvisioningRetries<T>(attempts: Int = 5, _ body: () async throws -> T) async throws -> T {
    precondition(attempts >= 1, "attempts must be at least 1")
    for attempt in 0 ..< attempts - 1 {
        do {
            return try await body()
        } catch {
            try await Task.sleep(nanoseconds: UInt64(500_000_000 * (1 << attempt)))
        }
    }
    return try await body()
}

/// Synchronous variant of ``withProvisioningRetries(attempts:_:)`` for the XCTest-era helpers that
/// provision on the calling thread (sleeps the thread between attempts).
public func withProvisioningRetriesSync<T>(attempts: Int = 5, _ body: () throws -> T) throws -> T {
    precondition(attempts >= 1, "attempts must be at least 1")
    for attempt in 0 ..< attempts - 1 {
        do {
            return try body()
        } catch {
            Thread.sleep(forTimeInterval: 0.5 * Double(1 << attempt))
        }
    }
    return try body()
}
