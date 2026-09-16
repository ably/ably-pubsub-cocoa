@testable import AblyLiveObjects
@testable import AblyLiveObjectsTesting
import AblyPubSubDevice

/// Helper for creating ably-cocoa objects, for use in integration tests.
enum ClientHelper {
    /// Creates a sandbox Realtime client with LiveObjects support.
    static func realtimeWithObjects(options: PartialClientOptions = .init()) async throws -> RealtimeClient {
        let clientOptions = try await Sandbox.clientOptions()
        clientOptions.plugins = [.liveObjects: AblyLiveObjects.Plugin.self]

        clientOptions.testOptions.transportFactory = TestProxyTransportFactory()

        if TestLogger.loggingEnabled {
            clientOptions.logLevel = .verbose
        }

        if let useBinaryProtocol = options.useBinaryProtocol {
            clientOptions.useBinaryProtocol = useBinaryProtocol
        }
        if let autoConnect = options.autoConnect {
            clientOptions.autoConnect = autoConnect
        }
        if let logIdentifier = options.logIdentifier {
            let logger = PrefixedLogger(prefix: "(\(logIdentifier)) ")
            clientOptions.logHandler = logger
        }
        if let garbageCollectionOptions = options.garbageCollectionOptions {
            clientOptions.garbageCollectionOptions = garbageCollectionOptions
        }

        return RealtimeClient(options: clientOptions)
    }

    /// An ably-cocoa logger that adds a given prefix to all emitted log messages.
    private class PrefixedLogger: Log {
        // This dance of using an implicitly unwrapped optional instead of a `let` is because we can't write a custom designated initializer (see comment below).
        var _prefix: String!
        var prefix: String {
            get {
                _prefix
            }

            set {
                if _prefix != nil {
                    fatalError("PrefixedLogger prefix cannot be changed after initialization")
                }
                _prefix = newValue
            }
        }

        // We use a convenience initializer because it's not clear to a consumer of the public API how to implement a custom designated initializer (super.init delegates to the non-public init(capturingOutput:).
        convenience init(prefix: String) {
            self.init()
            self.prefix = prefix
        }

        override public func log(_ message: String, with level: LogLevel) {
            let newMessage = "\(prefix)\(message)"
            super.log(newMessage, with: level)
        }
    }

    /// Creates channel options that include the channel modes needed for LiveObjects.
    static func channelOptionsWithObjects() -> RealtimeChannelOptions {
        let options = RealtimeChannelOptions()
        options.modes = [.objectSubscribe, .objectPublish]
        return options
    }

    struct PartialClientOptions: Encodable, Hashable {
        var useBinaryProtocol: Bool?
        var autoConnect: Bool?
        var garbageCollectionOptions: InternalDefaultRealtimeObjects.GarbageCollectionOptions?

        /// A prefix for all log messages emitted by the client. Allows clients to be distinguished in log messages for tests which use multiple clients.
        var logIdentifier: String?
    }
}
