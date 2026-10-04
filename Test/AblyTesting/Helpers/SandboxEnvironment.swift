import Foundation

/// Shared constants for the Ably sandbox environments used by test provisioning.
public enum SandboxEnvironment {
    /// The endpoint for the Ably **nonprod sandbox**. Keys provisioned against the sandbox only
    /// work there, so clients that use them must set `endpoint` to this value. Single source of
    /// truth for every test tree that provisions against nonprod (the UTS integration tier and the
    /// LiveObjects tests).
    public static let nonprodEndpoint = "nonprod:sandbox"

    /// The host that ``nonprodEndpoint`` resolves to. Provisioning calls, which do not go through
    /// the SDK, send their requests here.
    public static let nonprodHost = "sandbox.realtime.ably-nonprod.net"

    /// Per-request timeout for provisioning calls — fail fast instead of the 60s URLSession
    /// default, so a single stalled attempt doesn't dominate the retry budget of
    /// `withProvisioningRetries`.
    public static let provisioningTimeout: TimeInterval = 30
}
