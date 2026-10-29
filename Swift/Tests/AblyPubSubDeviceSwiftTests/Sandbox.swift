import AblyPubSubDeviceSwift
import AblyTesting
import Foundation

/// Creates sandbox apps for the integration tests in this target.
enum Sandbox {
    enum Error: Swift.Error {
        case badResponseStatus(Int)
    }

    private struct TestApp: Decodable {
        var keys: [Key]

        struct Key: Decodable {
            var keyStr: String
        }
    }

    /// Client options for a new sandbox app, using the app's key with full channel and presence capabilities.
    static func clientOptions() async throws -> ClientOptions {
        let key = try await withProvisioningRetries { try await createApp().keys[0].keyStr }
        let options = ClientOptions(key: key)
        options.endpoint = SandboxEnvironment.nonprodEndpoint
        return options
    }

    private static func createApp() async throws -> TestApp {
        var request = URLRequest(url: URL(string: "https://\(SandboxEnvironment.nonprodHost)/apps")!)
        request.httpMethod = "POST"
        request.timeoutInterval = SandboxEnvironment.provisioningTimeout
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try appCreationRequestBody()

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as! HTTPURLResponse).statusCode
        guard (200 ..< 300).contains(statusCode) else {
            throw Error.badResponseStatus(statusCode)
        }
        return try JSONDecoder().decode(TestApp.self, from: data)
    }

    private static func appCreationRequestBody() throws -> Data {
        // This file lives at Swift/Tests/AblyPubSubDeviceSwiftTests/ in the ably-cocoa repo.
        let setupFileURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // AblyPubSubDeviceSwiftTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // Swift
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("Test/AblyTests/ably-common/test-resources/test-app-setup.json")
        let setup = try JSONSerialization.jsonObject(with: Data(contentsOf: setupFileURL)) as! [String: Any]
        return try JSONSerialization.data(withJSONObject: setup["post_apps"]!)
    }
}
