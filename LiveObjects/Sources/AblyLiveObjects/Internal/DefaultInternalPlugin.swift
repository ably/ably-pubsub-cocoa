internal import _AblyPluginSupportPrivate
import Ably

// We explicitly import the NSObject class, else it seems to get transitively imported from  `internal import _AblyPluginSupportPrivate`, leading to the error "Class cannot be declared public because its superclass is internal".
import ObjectiveC.NSObject

/// The default implementation of `_AblyPluginSupportPrivate`'s `LiveObjectsInternalPluginProtocol`. Implements the interface that ably-cocoa uses to access the functionality provided by the LiveObjects plugin.
@objc
internal final class DefaultInternalPlugin: NSObject, _AblyPluginSupportPrivate.LiveObjectsInternalPluginProtocol {
    private let pluginAPI: _AblyPluginSupportPrivate.PluginAPIProtocol

    internal var compatibleWithProtocolV6: Bool { true }

    internal init(pluginAPI: _AblyPluginSupportPrivate.PluginAPIProtocol) {
        precondition(
            pluginAPI.usesLiveObjectsProtocolV6,
            "This version of the LiveObjects plugin requires a version of ably-cocoa that uses LiveObjects protocol v6.",
        )
        self.pluginAPI = pluginAPI
    }

    // MARK: - Channel `objects` property

    /// The `pluginDataValue(forKey:channel:)` key that we use to store the value of the `ARTRealtimeChannel.objects` property.
    private static let pluginDataKey = "LiveObjects"

    /// Retrieves the `RealtimeObjects` for this channel.
    ///
    /// We expect this value to have been previously set by ``prepare(_:)``.
    internal static func nosync_realtimeObjects(for channel: _AblyPluginSupportPrivate.RealtimeChannel, pluginAPI: _AblyPluginSupportPrivate.PluginAPIProtocol) -> InternalDefaultRealtimeObjects {
        guard let pluginData = pluginAPI.nosync_pluginDataValue(forKey: pluginDataKey, channel: channel) else {
            // InternalPlugin.prepare was not called
            fatalError("To access LiveObjects functionality, you must pass the LiveObjects plugin in the client options when creating the ARTRealtime instance: `clientOptions.plugins = [.liveObjects: AblyLiveObjects.Plugin.self]`")
        }

        // swiftlint:disable:next force_cast
        return pluginData as! InternalDefaultRealtimeObjects
    }

    // MARK: - LiveObjectsInternalPluginProtocol

    // Populates the channel's `objects` property.
    internal func nosync_prepare(_ channel: _AblyPluginSupportPrivate.RealtimeChannel, client: _AblyPluginSupportPrivate.RealtimeClient) {
        let pluginLogger = pluginAPI.logger(for: channel)
        let internalQueue = pluginAPI.internalQueue(for: client)
        let callbackQueue = pluginAPI.callbackQueue(for: client)
        let options = ARTClientOptions.castPluginPublicClientOptions(pluginAPI.options(for: client))

        let garbageCollectionOptions = options.garbageCollectionOptions ?? {
            if let latestConnectionDetails = pluginAPI.nosync_latestConnectionDetails(for: client), let gracePeriod = latestConnectionDetails.objectsGCGracePeriod {
                // If we already have connection details, then use its grace period per RTO10b2
                .init(gracePeriod: .dynamic(gracePeriod.doubleValue))
            } else {
                // RTO10b3: use the default grace period
                .init()
            }
        }()

        let logger = DefaultLogger(pluginLogger: pluginLogger, pluginAPI: pluginAPI)
        logger.log("LiveObjects.DefaultInternalPlugin received prepare(_:)", level: .debug)
        let liveObjects = InternalDefaultRealtimeObjects(
            logger: logger,
            internalQueue: internalQueue,
            userCallbackQueue: callbackQueue,
            clock: DefaultSimpleClock(),
            channelName: pluginAPI.name(for: channel),
            garbageCollectionOptions: garbageCollectionOptions,
        )
        pluginAPI.nosync_setPluginDataValue(liveObjects, forKey: Self.pluginDataKey, channel: channel)

        // Seed the RTO20c1 siteCode from the latest connection details at engine creation, through the
        // same `nosync_setSiteCode` path that the CONNECTED `ProtocolMessage` handler
        // (`nosync_onConnected`) uses. That handler (`ARTRealtime.m`
        // `nosync_onConnectedWithConnectionDetails:`) only reaches channels that already exist at
        // CONNECTED time; a channel created *after* connect (the normal `connect → channels.get(name)`
        // flow) would otherwise never receive a siteCode, leaving `publishAndApply` unable to apply
        // local echo (RTO20c1) until the next reconnect. Seeding here closes that gap; the later
        // CONNECTED handler keeps it fresh. A channel created before connect seeds nil and is covered by
        // that later handler.
        liveObjects.nosync_setSiteCode(pluginAPI.nosync_latestConnectionDetails(for: client)?.siteCode)
    }

    // The core SDK calls this from `-[ARTRealtimeChannels release:]` when a channel is released.
    // Disposes the channel's objects engine with a release-specific cause, failing any in-flight
    // operation proactively (rather than waiting for the channel's eventual deallocation, which would
    // fail waiters with a generic cause via `deinit`). This release-time disposal is not specified. A
    // channel may be released without ever having had its objects engine accessed, but `nosync_prepare`
    // runs for every channel at creation, so the plugin data is present; we still guard defensively so
    // a teardown race cannot trap.
    internal func nosync_onChannelRelease(_ channel: _AblyPluginSupportPrivate.RealtimeChannel) {
        guard pluginAPI.nosync_pluginDataValue(forKey: Self.pluginDataKey, channel: channel) != nil else {
            return
        }
        nosync_realtimeObjects(for: channel).nosync_disposeForChannelRelease()
    }

    /// Retrieves the internally-typed `objects` property for the channel.
    private func nosync_realtimeObjects(for channel: _AblyPluginSupportPrivate.RealtimeChannel) -> InternalDefaultRealtimeObjects {
        Self.nosync_realtimeObjects(for: channel, pluginAPI: pluginAPI)
    }

    /// A class that wraps an object message.
    ///
    /// We need this intermediate type because we want object messages to be structs — because they're nicer to work with internally — but a struct can't conform to the class-bound `_AblyPluginSupportPrivate.ObjectMessageProtocol`.
    internal final class ObjectMessageBox<T>: _AblyPluginSupportPrivate.ObjectMessageProtocol where T: Sendable {
        internal let objectMessage: T

        internal init(objectMessage: T) {
            self.objectMessage = objectMessage
        }
    }

    internal func decodeObjectMessage(
        _ serialized: [String: Any],
        context: DecodingContextProtocol,
        format: EncodingFormat,
        error errorPtr: AutoreleasingUnsafeMutablePointer<_AblyPluginSupportPrivate.PublicErrorInfo?>?,
    ) -> (any ObjectMessageProtocol)? {
        let wireObject = WireValue.objectFromPluginSupportData(serialized)

        do {
            let wireObjectMessage = try InboundWireObjectMessage(
                wireObject: wireObject,
                decodingContext: context,
            )
            let objectMessage = try ProtocolTypes.InboundObjectMessage(
                wireObjectMessage: wireObjectMessage,
                format: format,
            )
            return ObjectMessageBox(objectMessage: objectMessage)
        } catch {
            errorPtr?.pointee = error.asPluginPublicErrorInfo
            return nil
        }
    }

    internal func encodeObjectMessage(
        _ publicObjectMessage: any _AblyPluginSupportPrivate.ObjectMessageProtocol,
        format: EncodingFormat,
    ) -> [String: Any] {
        guard let outboundObjectMessageBox = publicObjectMessage as? ObjectMessageBox<ProtocolTypes.OutboundObjectMessage> else {
            preconditionFailure("Expected to receive the same OutboundObjectMessage type as we emit")
        }

        let wireObjectMessage = outboundObjectMessageBox.objectMessage.toWire(format: format)
        return wireObjectMessage.toWireObject.toPluginSupportDataDictionary
    }

    internal func nosync_onChannelAttached(_ channel: _AblyPluginSupportPrivate.RealtimeChannel, hasObjects: Bool) {
        nosync_realtimeObjects(for: channel).nosync_onChannelAttached(hasObjects: hasObjects)
    }

    internal func nosync_handleObjectProtocolMessage(withObjectMessages publicObjectMessages: [any _AblyPluginSupportPrivate.ObjectMessageProtocol], channel: _AblyPluginSupportPrivate.RealtimeChannel) {
        guard let inboundObjectMessageBoxes = publicObjectMessages as? [ObjectMessageBox<ProtocolTypes.InboundObjectMessage>] else {
            preconditionFailure("Expected to receive the same InboundObjectMessage type as we emit")
        }

        let objectMessages = inboundObjectMessageBoxes.map(\.objectMessage)

        nosync_realtimeObjects(for: channel).nosync_handleObjectProtocolMessage(
            objectMessages: objectMessages,
        )
    }

    internal func nosync_handleObjectSyncProtocolMessage(withObjectMessages publicObjectMessages: [any _AblyPluginSupportPrivate.ObjectMessageProtocol], protocolMessageChannelSerial: String?, channel: _AblyPluginSupportPrivate.RealtimeChannel) {
        guard let inboundObjectMessageBoxes = publicObjectMessages as? [ObjectMessageBox<ProtocolTypes.InboundObjectMessage>] else {
            preconditionFailure("Expected to receive the same InboundObjectMessage type as we emit")
        }

        let objectMessages = inboundObjectMessageBoxes.map(\.objectMessage)

        nosync_realtimeObjects(for: channel).nosync_handleObjectSyncProtocolMessage(
            objectMessages: objectMessages,
            protocolMessageChannelSerial: protocolMessageChannelSerial,
        )
    }

    internal func nosync_onChannelStateChanged(_ channel: _AblyPluginSupportPrivate.RealtimeChannel, toState state: _AblyPluginSupportPrivate.RealtimeChannelState, reason: (any _AblyPluginSupportPrivate.PublicErrorInfo)?) {
        let errorReason = reason.map { ARTErrorInfo.castPluginPublicErrorInfo($0) }
        nosync_realtimeObjects(for: channel).nosync_onChannelStateChanged(toState: state, reason: errorReason)
    }

    internal func nosync_onConnected(withConnectionDetails connectionDetails: (any ConnectionDetailsProtocol)?, channel: any RealtimeChannel) {
        let realtimeObjects = nosync_realtimeObjects(for: channel)

        let gracePeriod = connectionDetails?.objectsGCGracePeriod?.doubleValue ?? InternalDefaultRealtimeObjects.GarbageCollectionOptions.defaultGracePeriod
        // RTO10b
        realtimeObjects.nosync_setGarbageCollectionGracePeriod(gracePeriod)

        realtimeObjects.nosync_setSiteCode(connectionDetails?.siteCode)
    }

    // MARK: - Sending `OBJECT` ProtocolMessage

    internal static func nosync_sendObject(
        objectMessages: [ProtocolTypes.OutboundObjectMessage],
        channel: _AblyPluginSupportPrivate.RealtimeChannel,
        client: _AblyPluginSupportPrivate.RealtimeClient,
        pluginAPI: PluginAPIProtocol,
        callback: @escaping @Sendable (Result<PublishResult, ARTErrorInfo>) -> Void,
    ) {
        let objectMessageBoxes: [ObjectMessageBox<ProtocolTypes.OutboundObjectMessage>] = objectMessages.map { .init(objectMessage: $0) }
        let internalQueue = pluginAPI.internalQueue(for: client)

        pluginAPI.nosync_sendObject(
            withObjectMessages: objectMessageBoxes,
            channel: channel,
        ) { pluginPublishResult, error in
            dispatchPrecondition(condition: .onQueue(internalQueue))

            if let error {
                callback(.failure(ARTErrorInfo.castPluginPublicErrorInfo(error)))
            } else {
                guard let pluginPublishResult else {
                    preconditionFailure("Got nil publishResult and nil error")
                }

                let publishResult = PublishResult(pluginPublishResult: pluginPublishResult)
                callback(.success(publishResult))
            }
        }
    }
}
