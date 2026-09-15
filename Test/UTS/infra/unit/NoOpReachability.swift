import Foundation
import AblyPubSubDevice
import AblyPubSubDevice.Private

/// A reachability implementation that never reports any network changes.
///
/// Unit tests use the `MockWebSocket` transport and must not touch the real network; installing
/// this via `options.testOptions.reachabilityClass` stops the SDK from starting OS-level
/// network monitoring during a test.
final class NoOpReachability: NSObject, ARTReachability {
    init(logger: InternalLog, queue: DispatchQueue) {
        super.init()
    }

    func listen(forHost host: String, callback: @escaping (Bool) -> Void) {
        // Intentionally empty: never deliver a reachability change.
    }

    func off() {
        // Nothing to tear down.
    }
}
