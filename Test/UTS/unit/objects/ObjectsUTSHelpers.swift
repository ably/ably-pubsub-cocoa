import _AblyPluginSupportPrivate
import AblyPubSubDevice
@testable import AblyLiveObjects
@testable import AblyLiveObjectsTesting
import Foundation
import Testing

// Dedicated helper for the objects UNIT-tier UTS ports (the `objects/unit` public-tier specs:
// InstanceTests, ValueTypesTests, PathObject*Tests, …). This is a suite-local fixture namespace that
// rides in the `UTS` target alongside the ports — deliberately not in the shared
// `AblyLiveObjectsTesting` module, which is reserved for support code the native suite also consumes.
//
// The two truly-trivial no-op primitives this file used to replicate — `ObjectsUTSLogger` /
// `ObjectsUTSClock` — have been deduped to the shared `TestLogger` / `MockSimpleClock`. The remaining
// `ObjectsUTS*` doubles are kept because they have no drop-in shared equivalent (see `UTS/README.md`):
// the shared `MockCoreSDK` init requires a mutating `internalQueue:`-backed channel-state mutex,
// `SeededRealtimeObjects` is `private` to `DefaultPathObjectTests`, and the native event collectors
// are `private` per-suite.
//
// UNIT SCOPE: none of these helpers open a connection, attach a channel, or run `setup_synced_channel`.
// Objects are built directly via the `testsOnly_` node initialisers and wrapped with the internal
// `Instance.from(...)` factory seam (the same seam `PathObject.instance()` uses in production).

// MARK: - CoreSDK

/// A minimal ``CoreSDK`` exposing a fixed channel state (for the RTO25/RTO26 precondition checks the
/// node accessors run) and a canned server time. Publishing normally goes through
/// ``ObjectsUTSRealtimeObjects``, not this type — but the RTO20d4 port needs the *real*
/// `InternalDefaultRealtimeObjects` publishAndApply pipeline (to exercise the RTO20d4 production
/// guard), so this type optionally accepts a `publishHandler` returning a canned ``AblyLiveObjects.PublishResult``
/// (the unit stand-in for the spec's inline mock ACK). When set, the handler's result is delivered
/// asynchronously on `internalQueue`, mirroring the real transport's async ACK.
final class ObjectsUTSCoreSDK: CoreSDK {
    private let channelState: _AblyPluginSupportPrivate.RealtimeChannelState
    private let serverTime: Date
    private let internalQueue: DispatchQueue?
    private let publishHandler: (@Sendable ([ProtocolTypes.OutboundObjectMessage]) -> AblyLiveObjects.PublishResult)?
    private let _channelName: String

    init(
        channelState: _AblyPluginSupportPrivate.RealtimeChannelState = .attached,
        serverTime: Date = Date(),
        internalQueue: DispatchQueue? = nil,
        channelName: String = "",
        publishHandler: (@Sendable ([ProtocolTypes.OutboundObjectMessage]) -> AblyLiveObjects.PublishResult)? = nil,
    ) {
        self.channelState = channelState
        self.serverTime = serverTime
        self.internalQueue = internalQueue
        self._channelName = channelName
        self.publishHandler = publishHandler
    }

    func nosync_publish(objectMessages: [ProtocolTypes.OutboundObjectMessage], callback: @escaping @Sendable (Result<AblyLiveObjects.PublishResult, ErrorInfo>) -> Void) {
        guard let publishHandler, let internalQueue else {
            fatalError("nosync_publish is not exercised by the unit ports unless a publishHandler is supplied (writes otherwise go through ObjectsUTSRealtimeObjects)")
        }
        // Deliver the ACK asynchronously on the internal queue, as the real transport does — the
        // production `nosync_publishAndApply` expects its callback to fire after the mutex is released.
        let result = publishHandler(objectMessages)
        internalQueue.async { callback(.success(result)) }
    }

    func nosync_fetchServerTime(callback: @escaping @Sendable (Result<Date, ErrorInfo>) -> Void) {
        callback(.success(serverTime))
    }

    func testsOnly_overridePublish(with _: @escaping ([ProtocolTypes.OutboundObjectMessage]) async throws(ErrorInfo) -> AblyLiveObjects.PublishResult) {
        fatalError("testsOnly_overridePublish is not exercised by the unit ports")
    }

    var nosync_channelState: _AblyPluginSupportPrivate.RealtimeChannelState {
        channelState
    }

    var channelName: String {
        // Delivery-boundary ports (RTINS16e2) set this so the projected PAOM3 message carries the
        // channel name (PAOM2e); it defaults to empty for ports that do not assert on it.
        _channelName
    }

    // The unit ports run against a fully-configured channel (the RTO2a2/RTO2b2/RTO26 guards must pass),
    // matching the previously-stubbed always-pass behaviour.
    var nosync_objectChannelModes: _AblyPluginSupportPrivate.ChannelMode {
        [.objectSubscribe, .objectPublish]
    }

    var echoMessages: Bool {
        true
    }

    var nosync_connectionStateError: ErrorInfo? {
        nil
    }

    var nosync_maxMessageSize: Int? {
        // The unit ports do not publish through this CoreSDK, so the RTO15d gate is never consulted;
        // nil falls back to the Ably default if it ever were.
        nil
    }

    func nosync_attach(callback: @escaping @Sendable (ErrorInfo?) -> Void) {
        // The unit ports drive get() on an ATTACHED channel (RTL33a), so the RTL33b implicit attach
        // is never reached; succeed for completeness.
        callback(nil)
    }
}

// MARK: - RealtimeObjects

/// A minimal ``InternalRealtimeObjectsProtocol`` (mirrors AblyLiveObjectsTests' `MockRealtimeObjects`).
/// Captures the messages passed to `publishAndApply` (the RTO20 write seam that map `set`/`remove` and
/// counter `increment`/`decrement` publish through) without touching a real channel.
///
/// - Note: unlike the production `InternalDefaultRealtimeObjects`, this mock does **not** apply the
///   published operation back onto the object graph. Ported cases that would assert a value *after*
///   local apply (e.g. `value() == 150`) are therefore split: the unit port asserts the published
///   operation; the post-apply value assertion needs the full pipeline and is out of unit scope.
final class ObjectsUTSRealtimeObjects: InternalRealtimeObjectsProtocol {
    private let poolDelegate: ObjectsUTSPoolDelegate?
    private let mutex = NSLock()
    private nonisolated(unsafe) var _handler: (([ProtocolTypes.OutboundObjectMessage]) -> Result<Void, ErrorInfo>)?

    /// A real (unused-in-dispatch) register so the type conforms to `InternalRealtimeObjectsProtocol`.
    /// The unit ports do not exercise path-subscription dispatch (Phase 4 part 2).
    private let _pathObjectSubscriptionRegister = PathObjectSubscriptionRegister(
        internalQueue: DispatchQueue(label: "ObjectsUTSRealtimeObjects.internal"),
        userCallbackQueue: DispatchQueue(label: "ObjectsUTSRealtimeObjects.userCallback"),
    )

    init(poolDelegate: ObjectsUTSPoolDelegate? = nil) {
        self.poolDelegate = poolDelegate
    }

    var pathObjectSubscriptionRegister: PathObjectSubscriptionRegister {
        _pathObjectSubscriptionRegister
    }

    var nosync_objectsPool: ObjectsPool {
        guard let poolDelegate else {
            preconditionFailure("ObjectsUTSRealtimeObjects was not initialised with a poolDelegate")
        }
        return poolDelegate.nosync_objectsPool
    }

    func setPublishAndApplyHandler(_ handler: @escaping ([ProtocolTypes.OutboundObjectMessage]) -> Result<Void, ErrorInfo>) {
        mutex.withLock { _handler = handler }
    }

    func nosync_publishAndApply(
        objectMessages: [ProtocolTypes.OutboundObjectMessage],
        coreSDK _: CoreSDK,
        callback: @escaping @Sendable (Result<Void, ErrorInfo>) -> Void,
    ) {
        let handler = mutex.withLock { _handler }
        if let handler {
            callback(handler(objectMessages))
        } else {
            callback(.success(()))
        }
    }
}

// MARK: - Pool delegate

/// A pool delegate holding a fixed set of `objectId -> Entry` mappings, so that map `get`/`entries`
/// can resolve `objectId` references to nested objects (mirrors `MockLiveMapObjectsPoolDelegate`).
final class ObjectsUTSPoolDelegate: LiveMapObjectsPoolDelegate {
    private let poolMutex: DispatchQueueMutex<ObjectsPool>

    init(internalQueue: DispatchQueue, entries: [String: ObjectsPool.Entry] = [:]) {
        poolMutex = DispatchQueueMutex(
            dispatchQueue: internalQueue,
            initialValue: ObjectsPool(
                logger: TestLogger(),
                internalQueue: internalQueue,
                userCallbackQueue: .main,
                clock: MockSimpleClock(),
                testsOnly_otherEntries: entries,
            ),
        )
    }

    var nosync_objectsPool: ObjectsPool {
        poolMutex.withoutSync { $0 }
    }
}

// MARK: - Event collector

/// A tiny thread-safe collector for ``InstanceSubscriptionEvent``s delivered to a subscribe listener.
///
/// A single-type stand-in for AblyLiveObjectsTests' variadic `Subscriber`; avoiding parameter packs
/// keeps it clear of that type's `@available(iOS 17, tvOS 17)` gate.
final class ObjectsUTSEventCollector: Sendable {
    private let callbackQueue: DispatchQueue
    private let mutex = NSLock()
    private nonisolated(unsafe) var _events: [InstanceSubscriptionEvent] = []

    init(callbackQueue: DispatchQueue = .main) {
        self.callbackQueue = callbackQueue
    }

    /// The listener to hand to `subscribe(listener:)`.
    var listener: InstanceSubscriptionCallback {
        { [weak self] event in
            self?.mutex.withLock { self?._events.append(event) }
        }
    }

    /// Drains `callbackQueue` (so all already-emitted deliveries have run) and returns the events so far.
    func events() async -> [InstanceSubscriptionEvent] {
        await withCheckedContinuation { continuation in
            callbackQueue.async { continuation.resume() }
        }
        return mutex.withLock { _events }
    }
}

// MARK: - Captured publish

/// A thread-safe holder for the messages a `publishAndApply` handler captures (mirrors the private
/// `Published` holder in AblyLiveObjectsTests' `DefaultInstanceTests`).
final class ObjectsUTSPublished: Sendable {
    private let mutex = NSLock()
    private nonisolated(unsafe) var messages: [ProtocolTypes.OutboundObjectMessage]?

    func set(_ value: [ProtocolTypes.OutboundObjectMessage]) {
        mutex.withLock { messages = value }
    }

    func get() -> [ProtocolTypes.OutboundObjectMessage]? {
        mutex.withLock { messages }
    }
}

// MARK: - Construction / evaluation helpers

/// Shared node-construction and blueprint-evaluation helpers for the objects UNIT-tier UTS ports.
enum ObjectsUTS {
    static func createInternalQueue() -> DispatchQueue {
        DispatchQueue(label: "io.ably.uts.objects.\(UUID().uuidString)", qos: .userInitiated)
    }

    static func makeCounter(objectID: String = "counter:1@0", data: Double = 0, internalQueue: DispatchQueue) -> InternalDefaultLiveCounter {
        InternalDefaultLiveCounter(testsOnly_data: data, objectID: objectID, logger: TestLogger(), internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
    }

    static func makeMap(objectID: String = "map:1@0", data: [String: InternalObjectsMapEntry] = [:], internalQueue: DispatchQueue) -> InternalDefaultLiveMap {
        InternalDefaultLiveMap(testsOnly_data: data, objectID: objectID, logger: TestLogger(), internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
    }

    static func mapEntry(data: ProtocolTypes.ObjectData, timeserial: String = StandardTestPool.poolSerial) -> InternalObjectsMapEntry {
        InternalObjectsMapEntry(tombstonedAt: nil, timeserial: timeserial, data: data)
    }

    /// A fresh empty ``ObjectsPool`` for feeding into `nosync_apply(...)`.
    static func freshPool(internalQueue: DispatchQueue) -> ObjectsPool {
        ObjectsPool(logger: TestLogger(), internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
    }

    // MARK: Standard test pool (path-object ports)

    /// Builds the shared standard LiveObjects tree used by the path-object UTS ports
    /// (`objects/helpers/standard_test_pool.md`), seeded directly into an ``ObjectsPool`` (the unit
    /// stand-in for `setup_synced_channel`, which materialises it via an OBJECT_SYNC).
    ///
    /// ```
    /// root (map)
    ///   name    -> "Alice"                     age    -> 30
    ///   active  -> true                         score  -> counter:score@1000 (100)
    ///   profile -> map:profile@1000             data   -> json {"tags": ["a","b"]}
    ///   avatar  -> bytes [1,2,3]
    /// map:profile@1000: email -> "alice@example.com", nested_counter -> counter:nested@1000 (5),
    ///                   prefs -> map:prefs@1000
    /// map:prefs@1000:   theme -> "dark"
    /// ```
    ///
    /// If `prefsBackRef` is true, `map:prefs@1000` gains a `back_ref -> map:profile@1000` entry,
    /// forming the `profile -> prefs -> profile` cycle the RTPO14b2 compactJson test exercises.
    ///
    /// Serial baseline (per the spec's standard tree): every map entry carries
    /// `timeserial: StandardTestPool.poolSerial` (`"t:0"`, the `mapEntry` default) and every object
    /// `siteTimeserials: ["aaa": StandardTestPool.poolSerial]` — so `StandardTestPool.remoteSerial(i)`
    /// operations win entry-level LWW against the pool baseline, as the spec intends.
    static func standardPool(internalQueue: DispatchQueue, prefsBackRef: Bool = false) -> ObjectsPool {
        let scoreCounter = makeCounter(objectID: "counter:score@1000", data: 100, internalQueue: internalQueue)
        let nestedCounter = makeCounter(objectID: "counter:nested@1000", data: 5, internalQueue: internalQueue)

        var prefsData: [String: InternalObjectsMapEntry] = ["theme": mapEntry(data: ProtocolTypes.ObjectData(string: "dark"))]
        if prefsBackRef {
            prefsData["back_ref"] = mapEntry(data: ProtocolTypes.ObjectData(objectId: "map:profile@1000"))
        }
        let prefs = makeMap(objectID: "map:prefs@1000", data: prefsData, internalQueue: internalQueue)

        let profile = makeMap(
            objectID: "map:profile@1000",
            data: [
                "email": mapEntry(data: ProtocolTypes.ObjectData(string: "alice@example.com")),
                "nested_counter": mapEntry(data: ProtocolTypes.ObjectData(objectId: "counter:nested@1000")),
                "prefs": mapEntry(data: ProtocolTypes.ObjectData(objectId: "map:prefs@1000")),
            ],
            internalQueue: internalQueue,
        )
        let root = makeMap(
            objectID: ObjectsPool.rootKey,
            data: [
                "name": mapEntry(data: ProtocolTypes.ObjectData(string: "Alice")),
                "age": mapEntry(data: ProtocolTypes.ObjectData(number: NSNumber(value: 30))),
                "active": mapEntry(data: ProtocolTypes.ObjectData(boolean: true)),
                "score": mapEntry(data: ProtocolTypes.ObjectData(objectId: "counter:score@1000")),
                "profile": mapEntry(data: ProtocolTypes.ObjectData(objectId: "map:profile@1000")),
                "data": mapEntry(data: ProtocolTypes.ObjectData(json: .object(["tags": .array([.string("a"), .string("b")])]))),
                "avatar": mapEntry(data: ProtocolTypes.ObjectData(bytes: Data([1, 2, 3]))),
            ],
            internalQueue: internalQueue,
        )

        // Spec baseline: all objects have `siteTimeserials: { "aaa": POOL_SERIAL }`.
        let poolSiteTimeserials = ["aaa": StandardTestPool.poolSerial]
        scoreCounter.testsOnly_setSiteTimeserials(poolSiteTimeserials)
        nestedCounter.testsOnly_setSiteTimeserials(poolSiteTimeserials)
        prefs.testsOnly_setSiteTimeserials(poolSiteTimeserials)
        profile.testsOnly_setSiteTimeserials(poolSiteTimeserials)
        root.testsOnly_setSiteTimeserials(poolSiteTimeserials)

        var pool = freshPool(internalQueue: internalQueue)
        pool.testsOnly_setEntry(.counter(scoreCounter), forObjectID: "counter:score@1000")
        pool.testsOnly_setEntry(.counter(nestedCounter), forObjectID: "counter:nested@1000")
        pool.testsOnly_setEntry(.map(prefs), forObjectID: "map:prefs@1000")
        pool.testsOnly_setEntry(.map(profile), forObjectID: "map:profile@1000")
        pool.testsOnly_setEntry(.map(root), forObjectID: ObjectsPool.rootKey)
        return pool
    }

    // MARK: Blueprint evaluation (value_types.md `evaluate(vt)`)

    /// A fixed timestamp for object-ID generation in evaluation tests (RTO14 uses it verbatim).
    static let evaluationTimestamp = Date(timeIntervalSince1970: 1_754_042_434)

    /// Evaluates a ``LiveCounter`` blueprint into the outbound `ObjectMessage`(s) it generates.
    ///
    /// The cocoa evaluation seam is `ObjectCreationHelpers.creationOperationForLiveCounter(...)`; there
    /// is no standalone public `evaluate`. The blueprint's internal `count` (RTLCV2a) is read here and
    /// fed to that helper (DEV: evaluate seam differs from the spec's blueprint#evaluate).
    static func evaluate(counter blueprint: LiveCounter) -> [ProtocolTypes.OutboundObjectMessage] {
        [ObjectCreationHelpers.creationOperationForLiveCounter(count: blueprint.count, timestamp: evaluationTimestamp).objectMessage]
    }

    /// Evaluates a ``LiveMap`` blueprint into the outbound `ObjectMessage`(s) it generates, mirroring the
    /// spec's `evaluate(vt)` (RTLMV4). Recurses for nested `LiveMap`/`LiveCounter` entries, producing the
    /// depth-first ordered array (RTLMV4k). Uses the shared pure composition builders in
    /// `ObjectCreationHelpers` directly with a fixed `evaluationTimestamp` (RTO14), so it stays
    /// synchronous — unlike the production `ObjectCreationHelpers.evaluate(liveMap:)`, which fetches a
    /// per-object server time via the async `CoreSDK` seam.
    static func evaluate(map blueprint: LiveMap, internalQueue: DispatchQueue) -> [ProtocolTypes.OutboundObjectMessage] {
        internalQueue.ably_syncNoDeadlock {
            evaluateMap(blueprint).messages
        }
    }

    /// Recursive synchronous evaluation core for ``evaluate(map:internalQueue:)``. Returns the ordered
    /// `*_CREATE` messages (RTLMV4k) and the objectId of the map this blueprint represents (the final
    /// message's objectId, RTLMV4d2). Must be called on the internal queue (`nosync_toObjectData`).
    private static func evaluateMap(_ blueprint: LiveMap) -> (messages: [ProtocolTypes.OutboundObjectMessage], objectId: String) {
        var nested: [ProtocolTypes.OutboundObjectMessage] = []
        var entries: [String: ProtocolTypes.ObjectData] = [:]
        for (key, value) in blueprint.entries ?? [:] {
            switch value {
            case let .primitive(primitive):
                // RTLMV4d3–d7
                entries[key] = InternalLiveMapValue(primitive).nosync_toObjectData
            case let .liveCounter(childBlueprint):
                // RTLMV4d1
                let operation = ObjectCreationHelpers.creationOperationForLiveCounter(count: childBlueprint.count, timestamp: evaluationTimestamp)
                nested.append(operation.objectMessage)
                entries[key] = .init(objectId: operation.objectID)
            case let .liveMap(childBlueprint):
                // RTLMV4d2
                let child = evaluateMap(childBlueprint)
                nested.append(contentsOf: child.messages)
                entries[key] = .init(objectId: child.objectId)
            }
        }
        let operation = ObjectCreationHelpers.creationOperationForLiveMap(entries: entries, timestamp: evaluationTimestamp)
        // RTLMV4k: nested creates depth-first, then this map's MAP_CREATE
        return (nested + [operation.objectMessage], operation.objectID)
    }

    // MARK: Inbound message builders (subscribe ports; `mock_ws.send_to_client` stand-in)

    /// An inbound OBJECT operation message (the unit stand-in for a `build_object_message` frame
    /// delivered by `mock_ws.send_to_client`). Mirrors the native `TestFactories.inboundObjectMessage`.
    static func inboundOperation(_ operation: ProtocolTypes.ObjectOperation, serial: String, siteCode: String) -> ProtocolTypes.InboundObjectMessage {
        ProtocolTypes.InboundObjectMessage(id: nil, clientId: nil, connectionId: nil, extras: nil, timestamp: nil, operation: operation, object: nil, serial: serial, siteCode: siteCode, serialTimestamp: nil)
    }

    /// A MAP_SET operation message (`build_map_set`). Pass either a primitive `ObjectData` or one
    /// carrying `objectId` to point the key at a live object.
    static func mapSetMessage(objectId: String, key: String, value: ProtocolTypes.ObjectData, serial: String, siteCode: String) -> ProtocolTypes.InboundObjectMessage {
        inboundOperation(
            ProtocolTypes.ObjectOperation(action: .known(.mapSet), objectId: objectId, mapSet: ProtocolTypes.MapSet(key: key, value: value)),
            serial: serial,
            siteCode: siteCode,
        )
    }

    /// A COUNTER_INC operation message (`build_counter_inc`).
    static func counterIncMessage(objectId: String, number: Int, serial: String, siteCode: String) -> ProtocolTypes.InboundObjectMessage {
        inboundOperation(
            ProtocolTypes.ObjectOperation(action: .known(.counterInc), objectId: objectId, counterInc: WireCounterInc(number: NSNumber(value: number))),
            serial: serial,
            siteCode: siteCode,
        )
    }

    /// A MAP_CLEAR operation message (`build_map_clear`).
    static func mapClearMessage(objectId: String, serial: String, siteCode: String) -> ProtocolTypes.InboundObjectMessage {
        inboundOperation(
            ProtocolTypes.ObjectOperation(action: .known(.mapClear), objectId: objectId, mapClear: WireMapClear()),
            serial: serial,
            siteCode: siteCode,
        )
    }

    /// An OBJECT_DELETE operation message (`build_object_delete`), which tombstones the target object.
    /// Mirrors the native `TestFactories.objectDeleteOperationMessage`.
    static func objectDeleteMessage(objectId: String, serial: String, siteCode: String) -> ProtocolTypes.InboundObjectMessage {
        inboundOperation(
            ProtocolTypes.ObjectOperation(action: .known(.objectDelete), objectId: objectId, objectDelete: WireObjectDelete()),
            serial: serial,
            siteCode: siteCode,
        )
    }

    /// A noop COUNTER_INC operation message: a COUNTER_INC whose `counterInc` payload is absent, so the
    /// counter apply produces a `.noop` (RTLC9h). The spec models the noop as `counterInc: {}` (present
    /// but empty); cocoa's `WireCounterInc.number` is non-optional, so an empty/number-less increment is
    /// represented by an absent `counterInc` — the same RTLC9h noop branch (recorded in deviations.md).
    static func counterIncNoopMessage(objectId: String, serial: String, siteCode: String) -> ProtocolTypes.InboundObjectMessage {
        inboundOperation(
            ProtocolTypes.ObjectOperation(action: .known(.counterInc), objectId: objectId, counterInc: nil),
            serial: serial,
            siteCode: siteCode,
        )
    }

    /// An inbound OBJECT_SYNC state message carrying a counter's full state (used to drive a
    /// sync-originated update, whose delivered event has no public message per RTO4b2a).
    static func counterSyncMessage(objectId: String, count: Int) -> ProtocolTypes.InboundObjectMessage {
        ProtocolTypes.InboundObjectMessage(
            id: nil,
            clientId: nil,
            connectionId: nil,
            extras: nil,
            timestamp: nil,
            operation: nil,
            object: ProtocolTypes.ObjectState(
                objectId: objectId,
                siteTimeserials: ["aaa": StandardTestPool.poolSerial],
                tombstone: false,
                createOp: nil,
                map: nil,
                counter: WireObjectsCounter(count: NSNumber(value: count)),
            ),
            serial: nil,
            siteCode: nil,
            serialTimestamp: nil,
        )
    }

    /// An inbound OBJECT_SYNC state message re-stating the root map's entries.
    static func rootSyncMessage(entries: [String: ProtocolTypes.ObjectsMapEntry]) -> ProtocolTypes.InboundObjectMessage {
        ProtocolTypes.InboundObjectMessage(
            id: nil,
            clientId: nil,
            connectionId: nil,
            extras: nil,
            timestamp: nil,
            operation: nil,
            object: ProtocolTypes.ObjectState(
                objectId: ObjectsPool.rootKey,
                siteTimeserials: ["aaa": StandardTestPool.poolSerial],
                tombstone: false,
                createOp: nil,
                map: ProtocolTypes.ObjectsMap(semantics: .known(.lww), entries: entries),
                counter: nil,
            ),
            serial: nil,
            siteCode: nil,
            serialTimestamp: nil,
        )
    }

    /// An inbound map entry (wire form) for `rootSyncMessage`.
    static func wireMapEntry(data: ProtocolTypes.ObjectData) -> ProtocolTypes.ObjectsMapEntry {
        ProtocolTypes.ObjectsMapEntry(tombstone: false, timeserial: StandardTestPool.poolSerial, data: data)
    }
}

// MARK: - Path-subscription event collector

/// A thread-safe collector for ``PathObjectSubscriptionEvent``s delivered to a path-object subscribe
/// listener (the path-layer analogue of ``ObjectsUTSEventCollector``).
final class ObjectsUTSPathEventCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storedEvents: [PathObjectSubscriptionEvent] = []

    /// The listener to hand to `subscribe(listener:)`.
    var listener: PathObjectSubscriptionCallback {
        { [weak self] event in
            self?.lock.withLock { self?.storedEvents.append(event) }
        }
    }

    var events: [PathObjectSubscriptionEvent] {
        lock.withLock { storedEvents }
    }

    /// The `.path` of every delivered event, sorted (delivery order across paths is unspecified).
    var sortedPaths: [String] {
        events.map(\.object.path).sorted()
    }
}

// MARK: - Instance-subscription event collector (engine-driven instance-subscribe ports)

/// A thread-safe collector for ``InstanceSubscriptionEvent``s that is read **synchronously** after the
/// engine's `userCallbackQueue` has been drained (the instance-layer analogue of
/// ``ObjectsUTSPathEventCollector``). Unlike ``ObjectsUTSEventCollector`` — which drains its own
/// `.main` callback queue asynchronously — this suits the `LiveObjectSubscribeTests` fixture, where
/// instance-subscribe deliveries land on the engine's own `userCallbackQueue` (drained via
/// `queue.sync {}`), after which `events` reads the accumulated deliveries directly.
final class ObjectsUTSInstanceEventCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storedEvents: [InstanceSubscriptionEvent] = []

    /// The listener to hand to `subscribe(listener:)`.
    var listener: InstanceSubscriptionCallback {
        { [weak self] event in
            self?.lock.withLock { self?.storedEvents.append(event) }
        }
    }

    var events: [InstanceSubscriptionEvent] {
        lock.withLock { storedEvents }
    }
}

// MARK: - Seeded realtime objects (path-object ports)

/// A realtime-objects double exposing a pre-seeded **full** ``ObjectsPool`` (root + nested objects)
/// for path resolution, and capturing the messages published by the write path. Mirrors the native
/// `SeededRealtimeObjects` double in `LiveObjects/Tests/AblyLiveObjectsTests/DefaultPathObjectTests.swift`
/// (which the UTS target cannot import). Unlike ``ObjectsUTSRealtimeObjects`` — whose pool delegate
/// auto-creates an empty root — this injects a fully-seeded pool so `DefaultPathObject` resolution
/// walks root -> children exactly as production does.
final class ObjectsUTSSeededRealtimeObjects: InternalRealtimeObjectsProtocol {
    private let poolMutex: DispatchQueueMutex<ObjectsPool>
    private let mutex = NSLock()
    private nonisolated(unsafe) var _captured: [ProtocolTypes.OutboundObjectMessage]?
    private let _pathObjectSubscriptionRegister: PathObjectSubscriptionRegister

    init(pool: ObjectsPool, internalQueue: DispatchQueue) {
        poolMutex = DispatchQueueMutex(dispatchQueue: internalQueue, initialValue: pool)
        _pathObjectSubscriptionRegister = PathObjectSubscriptionRegister(internalQueue: internalQueue, userCallbackQueue: .main)
    }

    var nosync_objectsPool: ObjectsPool {
        poolMutex.withoutSync { $0 }
    }

    var pathObjectSubscriptionRegister: PathObjectSubscriptionRegister {
        _pathObjectSubscriptionRegister
    }

    /// The messages captured by the most recent `publishAndApply` (write ports assert against this).
    var capturedMessages: [ProtocolTypes.OutboundObjectMessage]? {
        mutex.withLock { _captured }
    }

    func nosync_publishAndApply(
        objectMessages: [ProtocolTypes.OutboundObjectMessage],
        coreSDK _: CoreSDK,
        callback: @escaping @Sendable (Result<Void, ErrorInfo>) -> Void,
    ) {
        mutex.withLock { _captured = objectMessages }
        // The RTO20 ACK echo, reduced to what the seeded pool can express: apply each captured
        // operation to its existing pool entry, so the spec's post-apply value reads work. A fresh
        // siteCode guarantees RTLO4a applicability against the seeded siteTimeserials. Operations
        // targeting objects outside the pool (e.g. `*_CREATE` blueprints) are not echoed — those
        // need the full `InternalDefaultRealtimeObjects` pipeline.
        //
        // The echo is asynchronous, like the real ACK: the write APIs call `publishAndApply` while
        // holding the written object's own state mutex, so applying synchronously here would be an
        // exclusivity violation. Hopping the (serial) internal queue runs the apply after the write's
        // locked region exits, and the callback fires after the apply, so an awaited write
        // happens-after its echo.
        let poolMutex = poolMutex
        poolMutex.dispatchQueue.async {
            var pool = poolMutex.withoutSync { $0 }
            for message in objectMessages {
                guard let operation = message.operation,
                      let entry = pool.entries[operation.objectId]
                else {
                    continue
                }
                let objectMessage = ObjectsUTS.inboundOperation(operation, serial: "uts-apply-serial", siteCode: "uts-apply")
                switch entry {
                case let .map(map):
                    _ = map.nosync_apply(
                        operation,
                        source: .channel,
                        objectMessage: objectMessage,
                        objectsPool: &pool,
                    )
                case let .counter(counter):
                    _ = counter.nosync_apply(
                        operation,
                        source: .channel,
                        objectMessage: objectMessage,
                        objectsPool: &pool,
                    )
                }
            }
            callback(.success(()))
        }
    }
}
