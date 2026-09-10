internal import _AblyPluginSupportPrivate
import Ably
import CryptoKit
import Foundation

/// Helpers for creating a new LiveObject.
///
/// These generate an object ID and the `ObjectMessage` needed to create the LiveObject.
internal enum ObjectCreationHelpers {
    /// The metadata that `createCounter` needs in order to request that Realtime create a LiveCounter and to populate the local objects pool.
    internal struct CounterCreationOperation {
        /// The generated object ID. Needed for populating the local objects pool.
        ///
        /// We include this property separately as a non-nil value, instead of expecting the caller to fish the nullable value out of ``objectMessage``.
        internal var objectID: String

        /// The ObjectMessage that must be sent in order for Realtime to create the object.
        internal var objectMessage: ProtocolTypes.OutboundObjectMessage
    }

    /// The metadata that `createMap` needs in order to request that Realtime create a LiveMap and to populate the local objects pool.
    internal struct MapCreationOperation {
        /// The generated object ID. Needed for populating the local objects pool.
        ///
        /// We include this property separately as a non-nil value, instead of expecting the caller to fish the nullable value out of ``objectMessage``.
        internal var objectID: String

        /// The ObjectMessage that must be sent in order for Realtime to create the object.
        internal var objectMessage: ProtocolTypes.OutboundObjectMessage

        /// The semantics that should be used for the created LiveMap.
        ///
        /// We include this property separately as a non-nil value, instead of expecting the caller to fish the nullable value out of ``objectMessage``.
        internal var semantics: ProtocolTypes.ObjectsMapSemantics
    }

    /// Creates a `COUNTER_CREATE` `ObjectMessage` for the `RealtimeObjects.createCounter` method per RTLCV4.
    ///
    /// - Parameters:
    ///   - count: The initial count for the new LiveCounter object
    ///   - timestamp: The timestamp to use for the generated object ID.
    internal static func creationOperationForLiveCounter(
        count: Double,
        timestamp: Date,
    ) -> CounterCreationOperation {
        // RTLCV4b: Create initial value for the new LiveCounter
        let counterCreate = WireCounterCreate(count: NSNumber(value: count))

        // RTLCV4c: Create an initial value JSON string as described in RTLCV4c
        let initialValueJSONString = createInitialValueJSONString(from: counterCreate)

        // RTLCV4d: Create a unique nonce as a random string
        let nonce = generateNonce()

        // RTLCV4e: Get the current server time (using the provided timestamp)
        let serverTime = timestamp

        // RTLCV4f: Create an objectId for the new LiveCounter object as described in RTO14
        let objectId = createObjectID(
            type: "counter",
            initialValue: initialValueJSONString,
            nonce: nonce,
            timestamp: serverTime,
        )

        // RTLCV4g: Set ObjectMessage.operation fields
        let operation = ProtocolTypes.ObjectOperation(
            action: .known(.counterCreate),
            objectId: objectId,
            counterCreateWithObjectId: .init(
                initialValue: initialValueJSONString,
                nonce: nonce,
                derivedFrom: counterCreate, // RTLCV4g5
            ),
        )

        let objectMessage = ProtocolTypes.OutboundObjectMessage(
            operation: operation,
        )

        return CounterCreationOperation(
            objectID: objectId,
            objectMessage: objectMessage,
        )
    }

    /// Adapter over ``creationOperationForLiveMap(entries:timestamp:)`` that accepts already-internal
    /// map values (`InternalLiveMapValue`), converting each to its `ObjectData` per RTLMV4d before
    /// delegating to the shared composition builder. Used by the legacy `RealtimeObjects.createMap`
    /// entry API (whose values may reference *existing* pooled objects by `objectId`, which a
    /// blueprint cannot express), so it stays `nosync_` — `nosync_toObjectData` reads a referenced
    /// node's `objectID` and must run on the internal queue.
    internal static func nosync_creationOperationForLiveMap(
        entries: [String: InternalLiveMapValue],
        timestamp: Date,
    ) -> MapCreationOperation {
        // RTLMV4d: Create an ObjectData for each entry value
        creationOperationForLiveMap(
            entries: entries.mapValues { $0.nosync_toObjectData },
            timestamp: timestamp,
        )
    }

    /// Shared composition builder that assembles the `MAP_CREATE` `ObjectMessage` for a new LiveMap
    /// per RTLMV4e–RTLMV4j, given the entries' `ObjectData` already resolved. This is the single
    /// MAP_CREATE composition path: the recursive ``evaluate(liveMap:coreSDK:internalQueue:)`` uses it
    /// after building nested-entry `objectId` references, and `RealtimeObjects.createMap` uses it via
    /// the `nosync_` adapter above. Pure (no node access), so it needs no queue.
    ///
    /// - Parameters:
    ///   - entries: The `ObjectData` for each initial entry of the new LiveMap object (per RTLMV4d).
    ///   - timestamp: The RTLMV4h server time to use for the generated object ID.
    internal static func creationOperationForLiveMap(
        entries: [String: ProtocolTypes.ObjectData],
        timestamp: Date,
    ) -> MapCreationOperation {
        // RTLMV4e2: Wrap each entry's ObjectData in an ObjectsMapEntry
        let mapEntries = entries.mapValues { objectData -> ProtocolTypes.ObjectsMapEntry in
            ProtocolTypes.ObjectsMapEntry(data: objectData)
        }

        // RTLMV4e1
        let semantics = ProtocolTypes.ObjectsMapSemantics.lww
        let mapCreate = ProtocolTypes.MapCreate(
            semantics: .known(semantics),
            entries: mapEntries,
        )

        // RTLMV4f: Create an initial value JSON string as described in RTLMV4f
        let initialValueJSONString = createInitialValueJSONString(from: mapCreate.toWire(format: .json))

        // RTLMV4g: Create a unique nonce as a random string
        let nonce = generateNonce()

        // RTLMV4h: Get the current server time (using the provided timestamp)
        let serverTime = timestamp

        // RTLMV4i: Create an objectId for the new LiveMap object as described in RTO14
        let objectId = createObjectID(
            type: "map",
            initialValue: initialValueJSONString,
            nonce: nonce,
            timestamp: serverTime,
        )

        // RTLMV4j: Set ObjectMessage.operation fields
        let operation = ProtocolTypes.ObjectOperation(
            action: .known(.mapCreate),
            objectId: objectId,
            mapCreateWithObjectId: .init(
                initialValue: initialValueJSONString,
                nonce: nonce,
                derivedFrom: mapCreate, // RTLMV4j5
            ),
        )

        let objectMessage = ProtocolTypes.OutboundObjectMessage(
            operation: operation,
        )

        return MapCreationOperation(
            objectID: objectId,
            objectMessage: objectMessage,
            semantics: semantics,
        )
    }

    // MARK: - Recursive blueprint evaluation (RTLMV4 / RTLCV4)

    /// The result of evaluating a value-type blueprint: the ordered list of `*_CREATE` `ObjectMessages`
    /// that must be published to bring the described object graph into existence (RTLMV4k, depth-first;
    /// self-create last), together with the `objectId` of the object the blueprint itself represents —
    /// which is the `objectId` of the *final* message in the list (RTLM20e7g2 / RTLMV4d2).
    internal typealias EvaluationResult = (messages: [ProtocolTypes.OutboundObjectMessage], objectId: String)

    /// Evaluates a ``LiveCounter`` blueprint per RTLCV4, producing the single `COUNTER_CREATE`
    /// `ObjectMessage` needed to create it. Fetches its own RTLCV4e server time (RTO16) so that, when
    /// nested within a ``LiveMap`` evaluation, each created object is timestamped independently
    /// (the cached RTO16a offset makes repeat fetches cheap).
    internal static func evaluate(
        liveCounter: LiveCounter,
        coreSDK: CoreSDK,
        internalQueue: DispatchQueue,
    ) async throws(ARTErrorInfo) -> EvaluationResult {
        // RTLCV4a: validate the initial count is finite up front (before any object ID is generated)
        if !liveCounter.count.isFinite {
            throw LiveObjectsError.counterInitialValueInvalid(value: liveCounter.count).toARTErrorInfo()
        }

        // RTLCV4e: get the current server time (per object, per RTO16)
        let timestamp = try await fetchServerTime(coreSDK: coreSDK, internalQueue: internalQueue)

        // RTLCV4: build the COUNTER_CREATE
        let operation = creationOperationForLiveCounter(count: liveCounter.count, timestamp: timestamp)
        return ([operation.objectMessage], operation.objectID)
    }

    /// Evaluates a ``LiveMap`` blueprint per RTLMV4, producing the ordered `*_CREATE` `ObjectMessages`
    /// for the map and all objects nested within its entries (depth-first, the map's own `MAP_CREATE`
    /// last, per RTLMV4k). Recurses for `LiveMap`/`LiveCounter` entry values, pointing each entry at its
    /// child's final `objectId` (RTLMV4d1/d2); primitives convert 1:1 (RTLMV4d3–d7). Fetches this map's
    /// own RTLMV4h server time (RTO16) *after* its children, mirroring the depth-first creation order.
    internal static func evaluate(
        liveMap: LiveMap,
        coreSDK: CoreSDK,
        internalQueue: DispatchQueue,
    ) async throws(ARTErrorInfo) -> EvaluationResult {
        // RTLMV4a/b/c: entries is a `[String: LiveMapValue]?`, keys are `String`, and each value is the
        // closed `LiveMapValue` enum, so "entries is a Dict", "keys are String", and "values are of an
        // expected type" (including RTLMV4c1: a live graph object cannot be a value) are all satisfied
        // structurally by the type system — no runtime validation is possible or needed here.
        var nestedMessages: [ProtocolTypes.OutboundObjectMessage] = []
        var entries: [String: ProtocolTypes.ObjectData] = [:]

        // RTLMV4d: build the ObjectData for each entry
        for (key, value) in liveMap.entries ?? [:] {
            switch value {
            case let .primitive(primitive):
                // RTLMV4d3–d7: primitives map 1:1 onto their ObjectData field
                entries[key] = InternalLiveMapValue(primitive).nosync_toObjectData
            case let .liveCounter(childBlueprint):
                // RTLMV4d1: evaluate the nested LiveCounter, collecting its COUNTER_CREATE and
                // pointing this entry at the created counter's objectId
                let child = try await evaluate(liveCounter: childBlueprint, coreSDK: coreSDK, internalQueue: internalQueue)
                nestedMessages.append(contentsOf: child.messages)
                entries[key] = .init(objectId: child.objectId)
            case let .liveMap(childBlueprint):
                // RTLMV4d2: recursively evaluate the nested LiveMap, collecting all its messages and
                // pointing this entry at the final message's objectId (the child map's MAP_CREATE)
                let child = try await evaluate(liveMap: childBlueprint, coreSDK: coreSDK, internalQueue: internalQueue)
                nestedMessages.append(contentsOf: child.messages)
                entries[key] = .init(objectId: child.objectId)
            }
        }

        // RTLMV4h: get the current server time for this map (per object, per RTO16)
        let timestamp = try await fetchServerTime(coreSDK: coreSDK, internalQueue: internalQueue)

        // RTLMV4e–j: build this map's own MAP_CREATE
        let operation = creationOperationForLiveMap(entries: entries, timestamp: timestamp)

        // RTLMV4k: nested creates (depth-first) followed by this map's MAP_CREATE
        return (nestedMessages + [operation.objectMessage], operation.objectID)
    }

    /// Fetches the current server time (RTO16), bridging the internal-queue callback API to `async`.
    ///
    /// `CoreSDK.nosync_fetchServerTime` must be invoked on the internal queue (the underlying core-SDK
    /// call asserts this), so we hop onto `internalQueue` before calling it.
    private static func fetchServerTime(coreSDK: CoreSDK, internalQueue: DispatchQueue) async throws(ARTErrorInfo) -> Date {
        let result: Result<Date, ARTErrorInfo> = await withCheckedContinuation { continuation in
            internalQueue.async {
                coreSDK.nosync_fetchServerTime { continuation.resume(returning: $0) }
            }
        }
        return try result.get()
    }

    // MARK: - Private Helper Methods

    /// Encodes a wire-encodable object to a JSON string for use as an initial value, per RTLMV4f and RTLCV4c.
    private static func createInitialValueJSONString(from encodable: some WireObjectEncodable) -> String {
        let jsonObject: [String: JSONValue] = encodable.toWireObject.mapValues { wireValue in
            do {
                return try wireValue.toJSONValue
            } catch {
                // By using `format: .json` we've requested a type that should be JSON-encodable, so if it isn't then it's a programmer error. (We can't reason about it statically though because of our choice to use a general-purpose WireValue type; maybe could improve upon this in the future.)
                preconditionFailure("Failed to convert WireValue \(wireValue) to JSONValue when encoding initialValue")
            }
        }

        return JSONObjectOrArray.object(jsonObject).toJSONString
    }

    /// Creates an Object ID for a new LiveObject instance, per RTO14.
    internal static func createObjectID( // internal for AblyLiveObjectsTesting
        type: String,
        initialValue: String,
        nonce: String,
        timestamp: Date,
    ) -> String {
        // RTO14b1: Generate a SHA-256 digest
        let hash = SHA256.hash(data: Data("\(initialValue):\(nonce)".utf8))

        // RTO14b2: Base64URL-encode the generated digest
        let base64URLHash = Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        // RTO14c: Return an Object ID in the format [type]:[hash]@[timestamp]
        let timestampMillis = Int(timestamp.timeIntervalSince1970 * 1000)
        return "\(type):\(base64URLHash)@\(timestampMillis)"
    }

    /// Generates a unique nonce as a random string, per RTLMV4g and RTLCV4d.
    private static func generateNonce() -> String {
        // TODO: confirm if there's any specific rules here: https://github.com/ably/specification/pull/353/files#r2228252389
        let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0 ..< 16).map { _ in letters.randomElement()! })
    }
}
