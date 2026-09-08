import Foundation
import Testing
import Ably
import Ably.Private

/// Self-tests for the harness itself, not derived from any UTS spec.
///
/// The per-side runs are only worth anything if the seam actually routes through the selected door.
/// If it stopped doing so, every spec would still pass — the run would just be a second copy of the
/// core run, reported as if it were coverage. These assert the routing directly, so that failure
/// shows up here instead of hiding behind a green suite.
@Suite("Harness: UTS_SIDE seam")
struct SideSeamTests {

    private static let deviceAgentName = "ably-pubsub-device"

    private func makeClient() -> ARTRealtime {
        let options = ARTClientOptions(key: "appId.keyId:keySecret")
        options.autoConnect = false
        return makeRealtimeForSide(options: options)
    }

    @Test("the seam routes through the door the mode names")
    func seamRoutesThroughSelectedSide() {
        let client = makeClient()
        defer { client.close() }

        let declared = client.internal.options.agents?[Self.deviceAgentName]

        switch UTSSide.current {
        case .core:
            #expect(declared == nil, "core mode built a client carrying the device declaration")
        case .device:
            #expect(
                declared == ARTClientInformationAgentNotVersioned,
                "device mode built a client without the device declaration — the suite is silently repeating the core run"
            )
        }
    }

    @Test("an unset UTS_SIDE means core")
    func defaultsToCore() {
        let raw = ProcessInfo.processInfo.environment["UTS_SIDE"]
        if raw == nil || raw?.isEmpty == true {
            #expect(UTSSide.current == .core)
        } else {
            #expect(UTSSide.current.rawValue == raw)
        }
    }
}
