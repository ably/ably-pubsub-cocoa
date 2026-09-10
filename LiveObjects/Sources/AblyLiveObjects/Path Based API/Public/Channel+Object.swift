internal import _AblyPluginSupportPrivate
import Ably

public extension ARTRealtimeChannel {
    /// The ``RealtimeObject`` for this channel — the entry point into the LiveObjects API.
    ///
    /// From here, ``RealtimeObject/get()`` returns a ``LiveMapPathObject`` rooted at the channel's
    /// root map, from which the rest of the object graph is navigated.
    ///
    /// > Note: It is a programmer error to access this property without first providing the
    /// > `LiveObjects` plugin in the client options.
    ///
    /// Spec: `RTL27`.
    var object: any RealtimeObject {
        nonTypeErasedObject
    }

    internal var nonTypeErasedObject: PublicDefaultRealtimeObject { // internal for AblyLiveObjectsTesting
        let pluginAPI = Plugin.defaultPluginAPI
        let underlyingObjects = pluginAPI.underlyingObjects(for: asPluginPublicRealtimeChannel)
        let internalQueue = pluginAPI.internalQueue(for: underlyingObjects.client)
        let internalObjects = internalQueue.ably_syncNoDeadlock {
            DefaultInternalPlugin.nosync_realtimeObjects(for: underlyingObjects.channel, pluginAPI: pluginAPI)
        }

        let pluginLogger = pluginAPI.logger(for: underlyingObjects.channel)
        let logger = DefaultLogger(pluginLogger: pluginLogger, pluginAPI: pluginAPI)

        let coreSDK = DefaultCoreSDK(
            channel: underlyingObjects.channel,
            client: underlyingObjects.client,
            pluginAPI: Plugin.defaultPluginAPI,
            logger: logger,
        )

        return PublicObjectsStore.shared.getOrCreateRealtimeObject(
            proxying: internalObjects,
            creationArgs: .init(
                coreSDK: coreSDK,
                logger: logger,
            ),
        )
    }
}
