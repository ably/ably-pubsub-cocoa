import AblyTesting
import Foundation

/// A test app provisioned in the Ably sandbox (`sandbox.realtime.ably-nonprod.net`).
///
/// Integration test suites provision one app in suite setup (`create()`) and tear it down in suite
/// teardown (`delete()`). The app is created against the sandbox directly (not through the proxy)
/// so provisioning is independent of any fault rules under test.
///
/// ```swift
/// let app = try await SandboxApp.create()
/// let key = app.defaultKey   // "appId.keyId:keySecret"
/// // … tests …
/// await app.delete()   // always, in teardown — even when the scenario failed
/// ```
///
/// Mirrors ably-java's `infra/integration/SandboxApp.kt`.
final class SandboxApp: Sendable {

    /// The Ably **nonprod sandbox** host — the `nonprod:sandbox` endpoint (used uniformly across the
    /// realtime/objects/rest integration specs), resolved to a hostname. Realtime and REST share
    /// this single host, so point both transports at it: set `realtimeHost` and/or `restHost` from
    /// here.
    static let sandboxHost = SandboxEnvironment.nonprodHost

    private static let sandboxBaseURL = URL(string: "https://\(sandboxHost)")!

    /// The canonical app spec shared across all Ably SDK test suites.
    private static let appSetupURL = URL(string: "https://raw.githubusercontent.com/ably/ably-common/refs/heads/main/test-resources/test-app-setup.json")!

    private static let session = makeURLSession(requestTimeout: 30)

    /// The provisioned app's id.
    let appId: String
    /// A full-capability API key string in `appId.keyId:keySecret` form.
    let defaultKey: String
    /// API keys with different capabilities, in `appId.keyId:keySecret` form. The first is the
    /// default key. See `test-app-setup.json` in ably-common for what each key can do.
    let keys: [String]

    private init(appId: String, defaultKey: String, keys: [String]) {
        self.appId = appId
        self.defaultKey = defaultKey
        self.keys = keys
    }

    /// Provisions a fresh sandbox app and returns its id and keys. Retried, including the
    /// non-idempotent POST — an orphaned app from a timed-out create is auto-deleted by the
    /// sandbox after a few minutes of no use.
    static func create() async throws -> SandboxApp {
        let appSpec = try await loadAppCreationJSON()
        return try await withProvisioningRetries {
            let request = try jsonRequest("POST", sandboxBaseURL.appendingPathComponent("apps"), body: appSpec)
            let (data, status) = try await httpRequest(request, session: session)
            guard (200..<300).contains(status) else {
                throw HTTPError("Sandbox POST /apps returned \(status): \(String(decoding: data, as: UTF8.self))")
            }
            guard let body = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let appId = body["appId"] as? String,
                  let keyObjects = body["keys"] as? [[String: Any]] else {
                throw HTTPError("Sandbox POST /apps returned an unexpected body")
            }
            let keys = keyObjects.compactMap { $0["keyStr"] as? String }
            guard let defaultKey = keys.first else {
                throw HTTPError("Sandbox POST /apps returned no keys")
            }
            return SandboxApp(appId: appId, defaultKey: defaultKey, keys: keys)
        }
    }

    /// Deletes the provisioned app. Network/timeout errors are ignored — best-effort cleanup must
    /// never mask a test failure — but a `CancellationError` is rethrown so cooperative task
    /// cancellation is not swallowed during teardown.
    func delete() async throws {
        var request = URLRequest(url: Self.sandboxBaseURL.appendingPathComponent("apps/\(appId)"))
        request.httpMethod = "DELETE"
        let basic = Data(defaultKey.utf8).base64EncodedString()
        request.setValue("Basic \(basic)", forHTTPHeaderField: "Authorization")
        do {
            _ = try await httpRequest(request, session: Self.session)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Best-effort cleanup: ignore network/timeout errors (sandbox apps auto-expire).
        }
    }

    /// Fetches the `post_apps` body from the shared `test-app-setup.json` in ably-common. Retried.
    private static func loadAppCreationJSON() async throws -> Any {
        try await withProvisioningRetries {
            let (data, status) = try await httpRequest(URLRequest(url: appSetupURL), session: session)
            guard status == 200 else {
                throw HTTPError("GET test-app-setup.json returned \(status)")
            }
            guard let setup = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let postApps = setup["post_apps"] else {
                throw HTTPError("test-app-setup.json has no post_apps key")
            }
            return postApps
        }
    }
}
