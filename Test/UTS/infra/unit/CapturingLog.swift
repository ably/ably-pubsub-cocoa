import Foundation
import AblyPubSubDevice

/// A `Log` that records every message the SDK logs, for tests that assert on log output (e.g.
/// "an error is logged"). Install via `ClientOptions.logHandler`.
///
/// The SDK's internal logger forwards every message to the injected `logHandler` (only the level
/// filter lives in `Log.log:withLevel:`), so overriding `log(_:with:)` *without* calling `super`
/// captures everything regardless of `logLevel` — and keeps the console quiet.
final class CapturingLog: Log {
    struct Entry {
        let level: LogLevel
        let message: String
    }

    private let lock = NSLock()
    private var storedEntries: [Entry] = []

    var entries: [Entry] {
        lock.lock(); defer { lock.unlock() }
        return storedEntries
    }

    override func log(_ message: String, with level: LogLevel) {
        lock.lock()
        storedEntries.append(Entry(level: level, message: message))
        lock.unlock()
    }

    /// Whether any captured message at `level` contains `substring` (case-insensitive).
    func contains(level: LogLevel, message substring: String) -> Bool {
        entries.contains { $0.level == level && $0.message.localizedCaseInsensitiveContains(substring) }
    }
}
