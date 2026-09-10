internal import _AblyPluginSupportPrivate
import Ably

internal extension ARTClientOptions {
    private class Box<T> {
        internal let boxed: T

        internal init(boxed: T) {
            self.boxed = boxed
        }
    }

    private static let garbageCollectionOptionsKey = "Objects.garbageCollectionOptions"

    /// Can be overriden for testing purposes.
    var garbageCollectionOptions: InternalDefaultRealtimeObjects.GarbageCollectionOptions? {
        get {
            let optionsValue = Plugin.defaultPluginAPI.pluginOptionsValue(
                forKey: Self.garbageCollectionOptionsKey,
                clientOptions: asPluginPublicClientOptions,
            )

            guard let optionsValue else {
                return nil
            }

            guard let box = optionsValue as? Box<InternalDefaultRealtimeObjects.GarbageCollectionOptions> else {
                preconditionFailure("Expected GarbageCollectionOptionsBox, got \(optionsValue)")
            }

            return box.boxed
        }

        set {
            guard let newValue else {
                preconditionFailure("Not implemented the ability to un-set GC options")
            }

            Plugin.defaultPluginAPI.setPluginOptionsValue(
                Box<InternalDefaultRealtimeObjects.GarbageCollectionOptions>(boxed: newValue),
                forKey: Self.garbageCollectionOptionsKey,
                clientOptions: asPluginPublicClientOptions,
            )
        }
    }
}
