import Foundation
import Testing
import AblyPubSubDevice
import AblyLiveObjects

/// Shared wiring and read helpers for the `objects` direct-sandbox integration suites
/// (`integration/standard/objects/`).

/// Client options for a realtime client wired straight to the nonprod sandbox (no proxy), with the
/// LiveObjects plugin installed (accessing `channel.object` without it is a programmer error).
func objectsClientOptions(key: String, useBinaryProtocol: Bool) -> ARTClientOptions {
    let options = ARTClientOptions(key: key)
    options.realtimeHost = SandboxApp.sandboxHost
    options.restHost = SandboxApp.sandboxHost
    options.useBinaryProtocol = useBinaryProtocol
    options.autoConnect = false
    options.plugins = [.liveObjects: AblyLiveObjects.Plugin.self]
    return options
}

/// A channel with the object modes (defaults to OBJECT_SUBSCRIBE + OBJECT_PUBLISH).
func objectsChannel(_ client: ARTRealtime,
                    _ name: String,
                    modes: ARTChannelMode = [.objectSubscribe, .objectPublish]) -> ARTRealtimeChannel {
    let options = ARTRealtimeChannelOptions()
    options.modes = modes
    return client.channels.get(name, options: options)
}

// MARK: - Dynamic `value()` reads (RTPO7)

// The spec's dynamic `pathObj.value()` returns "the resolved counter value or any primitive";
// ably-cocoa's typed views split that read per expected type. These
// helpers perform the read against the expected type, returning `nil` when the path doesn't resolve
// or resolves to a different type — which is also how the spec's `value() == null` (the tombstoned /
// absent case, RTLM5d2h) is asserted. A thrown RTO25 precondition error also reads as `nil` here;
// these suites only read on ATTACHED channels, where that error cannot arise.

/// The spec's `pathObj.value()` against an expected **counter**.
func counterValue(at node: any PathObject) -> Double? {
    guard let value = try? node.asLiveCounter().value() else { return nil }
    return value
}

/// The spec's `pathObj.value()` against an expected **string** primitive.
func stringValue(at node: any PathObject) -> String? {
    try? node.asPrimitive().stringValue()
}

/// The spec's `pathObj.value()` against an expected **number** primitive.
func numberValue(at node: any PathObject) -> Double? {
    try? node.asPrimitive().numberValue()
}

/// Signals that a UTS objects helper could not satisfy its expected-type contract. The paired
/// `Issue.record` call carries the diagnostic; this type only unwinds the test.
struct ObjectsHelperError: Error, CustomStringConvertible {
    let description: String
}

/// The spec's `pathObj.instance().id` against an expected **counter** — unwraps the `Instance` enum,
/// stopping the test if nothing resolves or the instance isn't a counter.
func counterInstanceId(at node: any PathObject,
                       sourceLocation: SourceLocation = #_sourceLocation) throws -> String {
    let instance = try #require(try node.instance(),
                                "expected an instance at path '\(node.path)'",
                                sourceLocation: sourceLocation)
    guard case let .liveCounter(counter) = instance else {
        Issue.record("expected a liveCounter instance at path '\(node.path)', got \(instance.type)",
                     sourceLocation: sourceLocation)
        throw ObjectsHelperError(description: "expected a liveCounter instance at path '\(node.path)'")
    }
    return counter.id
}
