import Foundation
import Ably
import AblyPubSubDevice

/// Which entry point the suite builds realtime clients through, selected by the `UTS_SIDE`
/// environment variable.
///
/// The specs are identical either way; what differs is the door they reach the SDK through. The
/// factory has tests of its own, but they check only that it stamps the declaring agent and leaves
/// the caller's options untouched — they barely use the client it returns. Running the specs
/// through it is what puts that client to work, and so shows the factory to be a faithful
/// pass-through and not merely a correct stamp.
///
/// Unset means `core`. An unrecognised value aborts rather than falling back, because a silent
/// fallback would turn a mistyped CI leg into a second copy of the core run and report it as
/// coverage.
enum UTSSide: String, Sendable {
    /// Today's constructors, `ARTRealtime(options:)`.
    case core
    /// `AblyPubSubDevice`'s factory, the entry point an app uses.
    case device

    static let current: UTSSide = {
        guard let raw = ProcessInfo.processInfo.environment["UTS_SIDE"], !raw.isEmpty else {
            return .core
        }
        guard let side = UTSSide(rawValue: raw) else {
            fatalError("UTS_SIDE must be 'core' or 'device', got '\(raw)'")
        }
        return side
    }()
}

/// Builds a realtime client through the currently selected side.
///
/// Every realtime client in every tier comes from here, so a suite run under `UTS_SIDE=device`
/// exercises the specs through `PubSubDevice.createClient` rather than the constructor.
///
/// REST clients are deliberately not routed through this: the device package exposes no HTTP door,
/// so `ARTRest` is the only entry point for a stateless client in either mode.
func makeRealtimeForSide(options: ARTClientOptions) -> ARTRealtime {
    switch UTSSide.current {
    case .core:
        return ARTRealtime(options: options)
    case .device:
        return PubSubDevice.createClient(options: options)
    }
}
