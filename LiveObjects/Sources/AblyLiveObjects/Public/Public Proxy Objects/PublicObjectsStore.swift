import Foundation

/// Stores the public path-based objects that wrap the SDK's internal components.
///
/// This allows us to provide stable object identity for our public objects. Concretely, it allows us
/// to consistently return the same `PublicDefaultRealtimeObject` instance across multiple calls to
/// `ARTRealtimeChannel.object`. It mirrors the mechanism previously used for the (now-removed)
/// `objects` API.
///
/// - Note: We can only make a best-effort attempt to maintain the pointer identity of the public
///   objects. Since the SDK cannot maintain a strong reference to the public objects (given that the
///   whole reason that these objects exist is for us to know whether the user holds a strong reference
///   to them), if the user releases all of their strong references to a public object then the next
///   time they fetch the public object they will receive a new object.
internal final class PublicObjectsStore: Sendable {
    // Used to synchronize access to mutable state
    private let mutex = NSLock()
    private nonisolated(unsafe) var mutableState = MutableState()

    internal static let shared = PublicObjectsStore()

    internal struct RealtimeObjectCreationArgs {
        internal var coreSDK: CoreSDK
        internal var logger: Logger
    }

    /// Fetches the cached `PublicDefaultRealtimeObject` that wraps a given `InternalDefaultRealtimeObjects`, creating a new public object if there isn't already one.
    internal func getOrCreateRealtimeObject(proxying proxied: InternalDefaultRealtimeObjects, creationArgs: RealtimeObjectCreationArgs) -> PublicDefaultRealtimeObject {
        mutex.withLock {
            mutableState.getOrCreateRealtimeObject(proxying: proxied, creationArgs: creationArgs)
        }
    }

    private struct MutableState {
        private var realtimeObjectProxies = Proxies<PublicDefaultRealtimeObject>()

        /// Stores weak references to proxy objects.
        private struct Proxies<Proxy: AnyObject> {
            private var proxiesByProxiedObjectIdentifier: [ObjectIdentifier: WeakRef<Proxy>] = [:]

            /// Fetches the proxy that wraps `proxied`, creating a new proxy if there isn't already one. Stores a weak reference to the proxy.
            mutating func getOrCreate(
                proxying proxied: some AnyObject,
                logger: Logger,
                logObjectType: String,
                createProxy: () -> Proxy,
            ) -> Proxy {
                removeDeallocatedEntries(logger: logger, logObjectType: logObjectType)

                let proxiedObjectIdentifier = ObjectIdentifier(proxied)

                if let existing = proxiesByProxiedObjectIdentifier[proxiedObjectIdentifier]?.referenced {
                    logger.log("Reusing existing \(logObjectType) proxy (proxy: \(ObjectIdentifier(existing)), proxied: \(proxiedObjectIdentifier))", level: .debug)
                    return existing
                }

                let created = createProxy()
                proxiesByProxiedObjectIdentifier[proxiedObjectIdentifier] = .init(referenced: created)
                logger.log("Creating new \(logObjectType) proxy (proxy: \(ObjectIdentifier(created)), proxied: \(proxiedObjectIdentifier))", level: .debug)

                return created
            }

            private mutating func removeDeallocatedEntries(logger: Logger, logObjectType: String) {
                var keysToRemove: Set<ObjectIdentifier> = []
                for (proxiedObjectIdentifier, weakProxyRef) in proxiesByProxiedObjectIdentifier where weakProxyRef.referenced == nil {
                    logger.log("Clearing unused \(logObjectType) proxy from cache (proxied: \(proxiedObjectIdentifier))", level: .debug)
                    keysToRemove.insert(proxiedObjectIdentifier)
                }

                for key in keysToRemove {
                    proxiesByProxiedObjectIdentifier.removeValue(forKey: key)
                }
            }
        }

        internal mutating func getOrCreateRealtimeObject(
            proxying proxied: InternalDefaultRealtimeObjects,
            creationArgs: RealtimeObjectCreationArgs,
        ) -> PublicDefaultRealtimeObject {
            realtimeObjectProxies.getOrCreate(
                proxying: proxied,
                logger: creationArgs.logger,
                logObjectType: "RealtimeObject",
            ) {
                .init(
                    proxied: proxied,
                    coreSDK: creationArgs.coreSDK,
                    logger: creationArgs.logger,
                )
            }
        }
    }
}
