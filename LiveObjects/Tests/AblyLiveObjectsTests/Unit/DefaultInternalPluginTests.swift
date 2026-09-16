import _AblyPluginSupportPrivate
@testable import AblyLiveObjects
@testable import AblyLiveObjectsTesting
import AblyPubSubDevice
import Foundation
import Testing

/// Tests for `DefaultInternalPlugin`'s engine setup, in particular the siteCode
/// seeding at channel preparation.
struct DefaultInternalPluginTests {
    // MARK: - Test doubles

    /// An empty marker conformer for `RealtimeChannel`.
    final class StubChannel: NSObject, _AblyPluginSupportPrivate.RealtimeChannel {}
    /// An empty marker conformer for `RealtimeClient`.
    final class StubClient: NSObject, _AblyPluginSupportPrivate.RealtimeClient {}
    /// An empty marker conformer for `Logger`.
    final class StubLogger: NSObject, _AblyPluginSupportPrivate.Logger {}

    /// A minimal `ConnectionDetailsProtocol` stub carrying just the fields the plugin reads.
    final class StubConnectionDetails: NSObject, _AblyPluginSupportPrivate.ConnectionDetailsProtocol, @unchecked Sendable {
        let objectsGCGracePeriod: NSNumber?
        let siteCode: String?
        let maxMessageSize: Int

        init(siteCode: String?, objectsGCGracePeriod: NSNumber? = nil, maxMessageSize: Int = 0) {
            self.siteCode = siteCode
            self.objectsGCGracePeriod = objectsGCGracePeriod
            self.maxMessageSize = maxMessageSize
        }
    }

    /// A minimal `PluginAPIProtocol` mock exercising only what `nosync_prepare` needs; the rest trap.
    final class MockPluginAPI: NSObject, _AblyPluginSupportPrivate.PluginAPIProtocol, @unchecked Sendable {
        let internalQueue: DispatchQueue
        let callbackQueue: DispatchQueue
        let clientOptions: ClientOptions
        let connectionDetails: (any _AblyPluginSupportPrivate.ConnectionDetailsProtocol)?
        let channelName: String

        private let lock = NSLock()
        private var pluginData: [String: Any] = [:]

        init(
            internalQueue: DispatchQueue,
            callbackQueue: DispatchQueue,
            clientOptions: ClientOptions = ClientOptions(),
            connectionDetails: (any _AblyPluginSupportPrivate.ConnectionDetailsProtocol)?,
            channelName: String = "test-channel"
        ) {
            self.internalQueue = internalQueue
            self.callbackQueue = callbackQueue
            self.clientOptions = clientOptions
            self.connectionDetails = connectionDetails
            self.channelName = channelName
        }

        var usesLiveObjectsProtocolV6: Bool { true }

        func internalQueue(for _: any _AblyPluginSupportPrivate.RealtimeClient) -> DispatchQueue { internalQueue }
        func callbackQueue(for _: any _AblyPluginSupportPrivate.RealtimeClient) -> DispatchQueue { callbackQueue }
        func options(for _: any _AblyPluginSupportPrivate.RealtimeClient) -> any _AblyPluginSupportPrivate.PublicClientOptions { clientOptions.asPluginPublicClientOptions }
        func logger(for _: any _AblyPluginSupportPrivate.RealtimeChannel) -> any _AblyPluginSupportPrivate.Logger { StubLogger() }
        func name(for _: any _AblyPluginSupportPrivate.RealtimeChannel) -> String { channelName }
        func nosync_latestConnectionDetails(for _: any _AblyPluginSupportPrivate.RealtimeClient) -> (any _AblyPluginSupportPrivate.ConnectionDetailsProtocol)? { connectionDetails }

        func nosync_setPluginDataValue(_ value: Any, forKey key: String, channel _: any _AblyPluginSupportPrivate.RealtimeChannel) {
            lock.withLock { pluginData[key] = value }
        }

        func nosync_pluginDataValue(forKey key: String, channel _: any _AblyPluginSupportPrivate.RealtimeChannel) -> Any? {
            lock.withLock { pluginData[key] }
        }

        func log(_: String, with _: _AblyPluginSupportPrivate.LogLevel, file _: UnsafePointer<CChar>, line _: Int, logger _: any _AblyPluginSupportPrivate.Logger) {
            // no-op
        }

        // MARK: Unused by these tests

        func underlyingObjects(for _: any _AblyPluginSupportPrivate.PublicRealtimeChannel) -> any _AblyPluginSupportPrivate.PublicRealtimeChannelUnderlyingObjects {
            fatalError("not used")
        }

        func setPluginOptionsValue(_: Any, forKey _: String, clientOptions _: any _AblyPluginSupportPrivate.PublicClientOptions) {
            fatalError("not used")
        }

        func pluginOptionsValue(forKey _: String, clientOptions _: any _AblyPluginSupportPrivate.PublicClientOptions) -> Any? {
            fatalError("not used")
        }

        func nosync_sendObject(withObjectMessages _: [any _AblyPluginSupportPrivate.ObjectMessageProtocol], channel _: any _AblyPluginSupportPrivate.RealtimeChannel, completion _: (((any _AblyPluginSupportPrivate.PublishResultProtocol)?, (any _AblyPluginSupportPrivate.PublicErrorInfo)?) -> Void)?) {
            fatalError("not used")
        }

        func nosync_state(for _: any _AblyPluginSupportPrivate.RealtimeChannel) -> _AblyPluginSupportPrivate.RealtimeChannelState {
            fatalError("not used")
        }

        func nosync_objectChannelModes(for _: any _AblyPluginSupportPrivate.RealtimeChannel) -> _AblyPluginSupportPrivate.ChannelMode {
            fatalError("not used")
        }

        func nosync_connectionStateError(for _: any _AblyPluginSupportPrivate.RealtimeClient) -> (any _AblyPluginSupportPrivate.PublicErrorInfo)? {
            fatalError("not used")
        }

        func nosync_attach(_: any _AblyPluginSupportPrivate.RealtimeChannel, completion _: (((any _AblyPluginSupportPrivate.PublicErrorInfo)?) -> Void)?) {
            fatalError("not used")
        }

        func nosync_fetchServerTime(for _: any _AblyPluginSupportPrivate.RealtimeClient, completion _: ((Date?, (any _AblyPluginSupportPrivate.PublicErrorInfo)?) -> Void)?) {
            fatalError("not used")
        }
    }

    // MARK: - siteCode seeding

    /// Prepares a channel and returns the engine the plugin stored for it.
    private static func prepareEngine(connectionDetails: (any _AblyPluginSupportPrivate.ConnectionDetailsProtocol)?) -> InternalDefaultRealtimeObjects {
        let internalQueue = DispatchQueue(label: "DefaultInternalPluginTests.internal")
        let pluginAPI = MockPluginAPI(
            internalQueue: internalQueue,
            callbackQueue: .main,
            connectionDetails: connectionDetails,
        )
        let plugin = DefaultInternalPlugin(pluginAPI: pluginAPI)
        let channel = StubChannel()
        let client = StubClient()

        internalQueue.sync {
            plugin.nosync_prepare(channel, client: client)
        }
        return internalQueue.sync {
            DefaultInternalPlugin.nosync_realtimeObjects(for: channel, pluginAPI: pluginAPI)
        }
    }

    // When the latest connection details carry a siteCode, the engine is seeded with it at prepare time
    // (so a channel created after CONNECTED — which never receives the CONNECTED ProtocolMessage — can
    // apply local echo per RTO20c1).
    @Test
    func seedsSiteCodeFromConnectionDetailsAtPrepare() {
        let engine = Self.prepareEngine(connectionDetails: StubConnectionDetails(siteCode: "site42"))
        #expect(engine.testsOnly_siteCode == "site42")
    }

    // When there are no connection details (channel created before CONNECTED), the seed is nil; the
    // later CONNECTED ProtocolMessage handler (nosync_onConnected) will supply the siteCode. The current skip-with-warning
    // behaviour on publish is preserved.
    @Test
    func seedsNilSiteCodeWhenNoConnectionDetails() {
        let engine = Self.prepareEngine(connectionDetails: nil)
        #expect(engine.testsOnly_siteCode == nil)
    }
}
