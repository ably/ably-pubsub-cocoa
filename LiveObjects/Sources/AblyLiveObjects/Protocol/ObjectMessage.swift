internal import _AblyPluginSupportPrivate
import Ably
import Foundation

// This file contains the ObjectMessage types that we use within the codebase. We convert them to and from the corresponding wire types (e.g. `InboundWireObjectMessage`) for sending and receiving over the wire.

/// Namespace for the internal "protocol" representations of an object message and its constituent
/// operations, states and data.
///
/// These types are scoped under `ProtocolTypes` to disambiguate them from the identically-named
/// public value types (e.g. `ObjectOperation` / `ObjectData`) that the SDK exposes to users; see the
/// `Path Based API` directory. They mirror the wire types (e.g. ``InboundWireObjectMessage``) but
/// with decoded, strongly-typed payloads.
///
/// > Note: The spec-suggested name for this namespace was `Protocol`, but that clashes with the
/// > Objective-C `Protocol` type imported via Foundation (ambiguous for importers such as the test
/// > target), so `ProtocolTypes` is used instead.
internal enum ProtocolTypes {
    /// An `ObjectMessage` received in the `state` property of an `OBJECT` or `OBJECT_SYNC` `ProtocolMessage`.
    internal struct InboundObjectMessage: Equatable {
        internal var id: String? // OM2a
        internal var clientId: String? // OM2b
        internal var connectionId: String? // OM2c
        internal var extras: [String: JSONValue]? // OM2d
        internal var timestamp: Date? // OM2e
        internal var operation: ObjectOperation? // OM2f
        internal var object: ObjectState? // OM2g
        internal var serial: String? // OM2h
        internal var siteCode: String? // OM2i
        internal var serialTimestamp: Date? // OM2j
    }

    /// An `ObjectMessage` to be sent in the `state` property of an `OBJECT` `ProtocolMessage`.
    ///
    /// - Important: When adding new fields, also update ``InboundObjectMessage/createSynthetic(from:serial:siteCode:)``.
    internal struct OutboundObjectMessage: Equatable {
        internal var id: String? // OM2a
        internal var clientId: String? // OM2b
        internal var connectionId: String?
        internal var extras: [String: JSONValue]? // OM2d
        internal var timestamp: Date? // OM2e
        internal var operation: ObjectOperation? // OM2f
        internal var object: ObjectState? // OM2g
        internal var serial: String? // OM2h
        internal var siteCode: String? // OM2i
        internal var serialTimestamp: Date? // OM2j
    }

    internal struct ObjectOperation: Equatable {
        internal var action: WireEnum<ObjectOperationAction> // OOP3a
        internal var objectId: String // OOP3b
        internal var mapCreate: MapCreate? // OOP3j
        internal var mapSet: MapSet? // OOP3k
        internal var mapRemove: WireMapRemove? // OOP3l
        internal var counterCreate: WireCounterCreate? // OOP3m
        internal var counterInc: WireCounterInc? // OOP3n
        internal var objectDelete: WireObjectDelete? // OOP3o
        internal var mapCreateWithObjectId: MapCreateWithObjectId? // OOP3p
        internal var counterCreateWithObjectId: CounterCreateWithObjectId? // OOP3q
        internal var mapClear: WireMapClear? // OOP3r
    }

    internal struct ObjectData: Equatable {
        internal var objectId: String? // OD2a
        internal var boolean: Bool? // OD2c
        internal var bytes: Data? // OD2d
        internal var number: NSNumber? // OD2e
        internal var string: String? // OD2f
        internal var json: JSONObjectOrArray? // TODO: Needs specification (see https://github.com/ably/ably-liveobjects-swift-plugin/issues/46)
    }

    internal struct MapSet: Equatable {
        internal var key: String // MST2a
        internal var value: ObjectData? // MST2b
    }

    internal struct MapCreate: Equatable {
        internal var semantics: WireEnum<ObjectsMapSemantics> // MCR2a
        internal var entries: [String: ObjectsMapEntry]? // MCR2b
    }

    internal struct MapCreateWithObjectId: Equatable {
        internal var initialValue: String // MCRO2a
        internal var nonce: String // MCRO2b

        /// The source `MapCreate` from which this `MapCreateWithObjectId` was derived.
        /// For local use only (apply-on-ACK per RTLM23); must not be sent over the wire.
        /// - SeeAlso: RTLMV4j5
        internal var derivedFrom: MapCreate?
    }

    internal struct CounterCreateWithObjectId: Equatable {
        internal var initialValue: String // CCRO2a
        internal var nonce: String // CCRO2b

        /// The source `WireCounterCreate` from which this `CounterCreateWithObjectId` was derived.
        /// For local use only (apply-on-ACK per RTLC16); must not be sent over the wire.
        /// - SeeAlso: RTLCV4g5
        internal var derivedFrom: WireCounterCreate?
    }

    internal struct ObjectsMapEntry: Equatable {
        internal var tombstone: Bool? // OME2a
        internal var timeserial: String? // OME2b
        internal var data: ObjectData? // OME2c
        internal var serialTimestamp: Date? // OME2d
    }

    internal struct ObjectsMap: Equatable {
        internal var semantics: WireEnum<ObjectsMapSemantics> // OMP3a
        internal var entries: [String: ObjectsMapEntry]? // OMP3b
        internal var clearTimeserial: String? // OMP3c
    }

    internal struct ObjectState: Equatable {
        internal var objectId: String // OST2a
        internal var siteTimeserials: [String: String] // OST2b
        internal var tombstone: Bool // OST2c
        internal var createOp: ObjectOperation? // OST2d
        internal var map: ObjectsMap? // OST2e
        internal var counter: WireObjectsCounter? // OST2f
    }
}

internal extension ProtocolTypes.InboundObjectMessage {
    /// Initializes an `InboundObjectMessage` from an `InboundWireObjectMessage`, applying the data decoding rules of OD5.
    ///
    /// - Parameters:
    ///   - format: The format to use when applying the decoding rules of OD5.
    /// - Throws: `ARTErrorInfo` if JSON or Base64 decoding fails.
    init(
        wireObjectMessage: InboundWireObjectMessage,
        format: _AblyPluginSupportPrivate.EncodingFormat
    ) throws(ARTErrorInfo) {
        id = wireObjectMessage.id
        clientId = wireObjectMessage.clientId
        connectionId = wireObjectMessage.connectionId
        extras = wireObjectMessage.extras
        timestamp = wireObjectMessage.timestamp
        operation = try wireObjectMessage.operation.map { wireObjectOperation throws(ARTErrorInfo) in
            try .init(wireObjectOperation: wireObjectOperation, format: format)
        }
        object = try wireObjectMessage.object.map { wireObjectState throws(ARTErrorInfo) in
            try .init(wireObjectState: wireObjectState, format: format)
        }
        serial = wireObjectMessage.serial
        siteCode = wireObjectMessage.siteCode
        serialTimestamp = wireObjectMessage.serialTimestamp
    }
}

internal extension ProtocolTypes.OutboundObjectMessage {
    /// Converts this `OutboundObjectMessage` to an `OutboundWireObjectMessage`, applying the data encoding rules of OD4.
    ///
    /// - Parameters:
    ///   - format: The format to use when applying the encoding rules of OD4.
    func toWire(format: _AblyPluginSupportPrivate.EncodingFormat) -> OutboundWireObjectMessage {
        .init(
            id: id,
            clientId: clientId,
            connectionId: connectionId,
            extras: extras,
            timestamp: timestamp,
            operation: operation?.toWire(format: format),
            object: object?.toWire(format: format),
            serial: serial,
            siteCode: siteCode,
            serialTimestamp: serialTimestamp,
        )
    }
}

internal extension ProtocolTypes.ObjectOperation {
    /// Initializes an `ObjectOperation` from a `WireObjectOperation`, applying the data decoding rules of OD5.
    ///
    /// - Parameters:
    ///   - format: The format to use when applying the decoding rules of OD5.
    /// - Throws: `ARTErrorInfo` if JSON or Base64 decoding fails.
    init(
        wireObjectOperation: WireObjectOperation,
        format: _AblyPluginSupportPrivate.EncodingFormat
    ) throws(ARTErrorInfo) {
        action = wireObjectOperation.action
        objectId = wireObjectOperation.objectId

        mapCreate = try wireObjectOperation.mapCreate.map { wireMapCreate throws(ARTErrorInfo) in
            try .init(wireMapCreate: wireMapCreate, format: format)
        }
        mapSet = try wireObjectOperation.mapSet.map { wireMapSet throws(ARTErrorInfo) in
            try .init(wireMapSet: wireMapSet, format: format)
        }
        mapRemove = wireObjectOperation.mapRemove
        counterCreate = wireObjectOperation.counterCreate
        counterInc = wireObjectOperation.counterInc
        objectDelete = wireObjectOperation.objectDelete
        mapClear = wireObjectOperation.mapClear
        // Outbound-only — do not access on inbound data
        mapCreateWithObjectId = nil
        counterCreateWithObjectId = nil
    }

    /// Converts this `ObjectOperation` to a `WireObjectOperation`, applying the data encoding rules of OD4.
    ///
    /// - Parameters:
    ///   - format: The format to use when applying the encoding rules of OD4.
    func toWire(format: _AblyPluginSupportPrivate.EncodingFormat) -> WireObjectOperation {
        .init(
            action: action,
            objectId: objectId,
            mapCreate: mapCreate?.toWire(format: format),
            mapSet: mapSet?.toWire(format: format),
            mapRemove: mapRemove,
            counterCreate: counterCreate,
            counterInc: counterInc,
            objectDelete: objectDelete,
            mapCreateWithObjectId: mapCreateWithObjectId?.toWire(),
            counterCreateWithObjectId: counterCreateWithObjectId?.toWire(),
            mapClear: mapClear,
        )
    }
}

internal extension ProtocolTypes.ObjectData {
    /// Initializes an `ObjectData` from a `WireObjectData`, applying the data decoding rules of OD5.
    ///
    /// - Parameters:
    ///   - format: The format to use when applying the decoding rules of OD5.
    /// - Throws: `ARTErrorInfo` if JSON or Base64 decoding fails.
    init(
        wireObjectData: WireObjectData,
        format: _AblyPluginSupportPrivate.EncodingFormat
    ) throws(ARTErrorInfo) {
        objectId = wireObjectData.objectId
        boolean = wireObjectData.boolean
        number = wireObjectData.number
        string = wireObjectData.string

        // OD5: Decode data based on format
        switch format {
        case .messagePack:
            // OD5a: When the MessagePack protocol is used
            // OD5a1: The payloads in (…) ObjectData.bytes (…) are decoded as their corresponding MessagePack types
            if let wireBytes = wireObjectData.bytes {
                switch wireBytes {
                case let .data(data):
                    bytes = data
                case .string:
                    // Not very clear what we're meant to do if `bytes` contains a string; let's ignore it. I think it's a bit moot - shouldn't happen. The only reason I'm considering it here is because of our slightly weird WireObjectData.bytes type which is typed as a string or data; might be good to at some point figure out how to rule out the string case earlier when using MessagePack, but it's not a big issue
                    bytes = nil
                }
            } else {
                bytes = nil
            }
        case .json:
            // OD5b: When the JSON protocol is used
            // OD5b2: The ObjectData.bytes payload is Base64-decoded into a binary value
            if let wireBytes = wireObjectData.bytes {
                switch wireBytes {
                case let .string(base64String):
                    bytes = try Data.fromBase64Throwing(base64String)
                case .data:
                    // This is an error in our logic, not a malformed wire value
                    preconditionFailure("Should not receive Data for JSON encoding format")
                }
            } else {
                bytes = nil
            }
        }

        // TODO: Needs specification (see https://github.com/ably/ably-liveobjects-swift-plugin/issues/46)
        if let wireJson = wireObjectData.json {
            let jsonValue = try JSONObjectOrArray(jsonString: wireJson)
            json = jsonValue
        } else {
            json = nil
        }
    }

    /// Converts this `ObjectData` to a `WireObjectData`, applying the data encoding rules of OD4.
    ///
    /// - Parameters:
    ///   - format: The format to use when applying the encoding rules of OD4.
    func toWire(format: _AblyPluginSupportPrivate.EncodingFormat) -> WireObjectData {
        // OD4: Encode data based on format
        let wireBytes: StringOrData? = if let bytes {
            switch format {
            case .messagePack:
                // OD4c: When the MessagePack protocol is used
                // OD4c2: A binary payload is encoded as a MessagePack binary type, and the result is set on the ObjectData.bytes attribute
                .data(bytes)
            case .json:
                // OD4d: When the JSON protocol is used
                // OD4d2: A binary payload is Base64-encoded and represented as a JSON string; the result is set on the ObjectData.bytes attribute
                .string(bytes.base64EncodedString())
            }
        } else {
            nil
        }

        let wireNumber: NSNumber? = if let number {
            switch format {
            case .json:
                number
            case .messagePack:
                // OD4c: When the MessagePack protocol is used
                // OD4c3 A number payload is encoded as a MessagePack float64 type, and the result is set on the ObjectData.number attribute
                .init(value: number.doubleValue) // `doubleValue`, not `art_doubleValue`: an outbound number is always one we built from a Swift Double (RTLMV4d), not a JSON-decoded NSDecimalNumber, so there are no digits to recover here.
            }
        } else {
            nil
        }

        return .init(
            objectId: objectId,
            boolean: boolean,
            bytes: wireBytes,
            number: wireNumber,
            // OD4c4: A string payload is encoded as a MessagePack string type, and the result is set on the ObjectData.string attribute
            // OD4d4: A string payload is represented as a JSON string and set on the ObjectData.string attribute
            string: string,
            // TODO: Needs specification (see https://github.com/ably/ably-liveobjects-swift-plugin/issues/46)
            json: json?.toJSONString,
        )
    }
}

internal extension ProtocolTypes.MapSet {
    init(
        wireMapSet: WireMapSet,
        format: _AblyPluginSupportPrivate.EncodingFormat
    ) throws(ARTErrorInfo) {
        key = wireMapSet.key
        value = try wireMapSet.value.map { wireObjectData throws(ARTErrorInfo) in
            try .init(wireObjectData: wireObjectData, format: format)
        }
    }

    func toWire(format: _AblyPluginSupportPrivate.EncodingFormat) -> WireMapSet {
        .init(
            key: key,
            value: value?.toWire(format: format),
        )
    }
}

internal extension ProtocolTypes.MapCreate {
    init(
        wireMapCreate: WireMapCreate,
        format: _AblyPluginSupportPrivate.EncodingFormat
    ) throws(ARTErrorInfo) {
        semantics = wireMapCreate.semantics
        entries = try wireMapCreate.entries?.ablyLiveObjects_mapValuesWithTypedThrow { wireMapEntry throws(ARTErrorInfo) in
            try .init(wireObjectsMapEntry: wireMapEntry, format: format)
        }
    }

    func toWire(format: _AblyPluginSupportPrivate.EncodingFormat) -> WireMapCreate {
        .init(
            semantics: semantics,
            entries: entries?.mapValues { $0.toWire(format: format) },
        )
    }
}

internal extension ProtocolTypes.MapCreateWithObjectId {
    init(wireMapCreateWithObjectId: WireMapCreateWithObjectId) {
        nonce = wireMapCreateWithObjectId.nonce
        initialValue = wireMapCreateWithObjectId.initialValue
    }

    func toWire() -> WireMapCreateWithObjectId {
        .init(initialValue: initialValue, nonce: nonce)
    }
}

internal extension ProtocolTypes.CounterCreateWithObjectId {
    init(wireCounterCreateWithObjectId: WireCounterCreateWithObjectId) {
        nonce = wireCounterCreateWithObjectId.nonce
        initialValue = wireCounterCreateWithObjectId.initialValue
    }

    func toWire() -> WireCounterCreateWithObjectId {
        .init(initialValue: initialValue, nonce: nonce)
    }
}

internal extension ProtocolTypes.ObjectsMapEntry {
    /// Initializes an `ObjectsMapEntry` from a `WireObjectsMapEntry`, applying the data decoding rules of OD5.
    ///
    /// - Parameters:
    ///   - format: The format to use when applying the decoding rules of OD5.
    /// - Throws: `ARTErrorInfo` if JSON or Base64 decoding fails.
    init(
        wireObjectsMapEntry: WireObjectsMapEntry,
        format: _AblyPluginSupportPrivate.EncodingFormat
    ) throws(ARTErrorInfo) {
        tombstone = wireObjectsMapEntry.tombstone
        timeserial = wireObjectsMapEntry.timeserial
        data = if let wireObjectData = wireObjectsMapEntry.data {
            try .init(wireObjectData: wireObjectData, format: format)
        } else {
            nil
        }
        serialTimestamp = wireObjectsMapEntry.serialTimestamp
    }

    /// Converts this `ObjectsMapEntry` to a `WireObjectsMapEntry`, applying the data encoding rules of OD4.
    ///
    /// - Parameters:
    ///   - format: The format to use when applying the encoding rules of OD4.
    func toWire(format: _AblyPluginSupportPrivate.EncodingFormat) -> WireObjectsMapEntry {
        .init(
            tombstone: tombstone,
            timeserial: timeserial,
            data: data?.toWire(format: format),
        )
    }
}

internal extension ProtocolTypes.ObjectsMap {
    /// Initializes an `ObjectsMap` from a `WireObjectsMap`, applying the data decoding rules of OD5.
    ///
    /// - Parameters:
    ///   - format: The format to use when applying the decoding rules of OD5.
    /// - Throws: `ARTErrorInfo` if JSON or Base64 decoding fails.
    init(
        wireObjectsMap: WireObjectsMap,
        format: _AblyPluginSupportPrivate.EncodingFormat
    ) throws(ARTErrorInfo) {
        semantics = wireObjectsMap.semantics
        entries = try wireObjectsMap.entries?.ablyLiveObjects_mapValuesWithTypedThrow { wireMapEntry throws(ARTErrorInfo) in
            try .init(wireObjectsMapEntry: wireMapEntry, format: format)
        }
        clearTimeserial = wireObjectsMap.clearTimeserial
    }

    /// Converts this `ObjectsMap` to a `WireObjectsMap`, applying the data encoding rules of OD4.
    ///
    /// - Parameters:
    ///   - format: The format to use when applying the encoding rules of OD4.
    func toWire(format: _AblyPluginSupportPrivate.EncodingFormat) -> WireObjectsMap {
        .init(
            semantics: semantics,
            entries: entries?.mapValues { $0.toWire(format: format) },
            clearTimeserial: clearTimeserial,
        )
    }
}

internal extension ProtocolTypes.ObjectState {
    /// Initializes an `ObjectState` from a `WireObjectState`, applying the data decoding rules of OD5.
    ///
    /// - Parameters:
    ///   - format: The format to use when applying the decoding rules of OD5.
    /// - Throws: `ARTErrorInfo` if JSON or Base64 decoding fails.
    init(
        wireObjectState: WireObjectState,
        format: _AblyPluginSupportPrivate.EncodingFormat
    ) throws(ARTErrorInfo) {
        objectId = wireObjectState.objectId
        siteTimeserials = wireObjectState.siteTimeserials
        tombstone = wireObjectState.tombstone
        createOp = try wireObjectState.createOp.map { wireObjectOperation throws(ARTErrorInfo) in
            try .init(wireObjectOperation: wireObjectOperation, format: format)
        }
        map = try wireObjectState.map.map { wireObjectsMap throws(ARTErrorInfo) in
            try .init(wireObjectsMap: wireObjectsMap, format: format)
        }
        counter = wireObjectState.counter
    }

    /// Converts this `ObjectState` to a `WireObjectState`, applying the data encoding rules of OD4.
    ///
    /// - Parameters:
    ///   - format: The format to use when applying the encoding rules of OD4.
    func toWire(format: _AblyPluginSupportPrivate.EncodingFormat) -> WireObjectState {
        .init(
            objectId: objectId,
            siteTimeserials: siteTimeserials,
            tombstone: tombstone,
            createOp: createOp?.toWire(format: format),
            map: map?.toWire(format: format),
            counter: counter,
        )
    }
}

// MARK: - PAOM3: wire (protocol) -> public conversion

internal extension ProtocolTypes.InboundObjectMessage {
    /// Builds the user-facing ``ObjectMessage`` (PAOM) from this inbound message, per PAOM3.
    ///
    /// Returns `nil` unless the message carries an operation with a *known* action (PAOM3a1): a
    /// message with no operation is not surfaced, and an unknown wire action must never surface
    /// publicly (there is no `UNKNOWN` case in the public ``ObjectOperationAction``). Callers
    /// only pass op-bearing, non-sync messages (sync-originated updates carry `nil`, RTO4b2a).
    ///
    /// - Parameter channelName: the name of the channel the message was received on (PAOM2e/PAOM3b).
    func toPublicObjectMessage(channelName: String) -> ObjectMessage? {
        // PAOM3a1: precondition — the source message must carry an operation with a known action.
        guard let operation, let publicOperation = operation.toPublicObjectOperation() else {
            return nil
        }

        return .init(
            id: id, // PAOM2a
            clientId: clientId, // PAOM2b
            connectionId: connectionId, // PAOM2c
            timestamp: timestamp, // PAOM2d
            channel: channelName, // PAOM2e, PAOM3b
            operation: publicOperation, // PAOM2f
            serial: serial, // PAOM2g
            serialTimestamp: serialTimestamp, // PAOM2h
            siteCode: siteCode, // PAOM2i
            extras: extras, // PAOM2j
        )
    }
}

internal extension ProtocolTypes.ObjectOperation {
    /// Converts this operation to the public ``ObjectOperation`` (PAOOP), resolving the outbound-only
    /// `*CreateWithObjectId` variants back to their derived create payloads (PAOOP3b/PAOOP3c).
    ///
    /// Returns `nil` for an unknown wire action, which must never surface publicly (PAOOP2a).
    func toPublicObjectOperation() -> ObjectOperation? {
        // PAOOP2a: an unknown action has no public representation.
        guard case let .known(action) = action else {
            return nil
        }

        let publicAction: ObjectOperationAction = switch action {
        case .mapCreate:
            .mapCreate
        case .mapSet:
            .mapSet
        case .mapRemove:
            .mapRemove
        case .counterCreate:
            .counterCreate
        case .counterInc:
            .counterInc
        case .objectDelete:
            .objectDelete
        case .mapClear:
            .mapClear
        }

        // PAOOP3b: prefer mapCreate, else the MapCreate the WithObjectId variant was derived from.
        let resolvedMapCreate = mapCreate ?? mapCreateWithObjectId?.derivedFrom
        // PAOOP3c: prefer counterCreate, else the derived CounterCreate.
        let resolvedCounterCreate = counterCreate ?? counterCreateWithObjectId?.derivedFrom

        return .init(
            action: publicAction, // PAOOP2a
            objectId: objectId, // PAOOP2b
            mapCreate: resolvedMapCreate?.toPublicMapCreate(), // PAOOP2c/PAOOP3b
            mapSet: mapSet.map { .init(key: $0.key, value: $0.value?.toPublicObjectData() ?? .init()) }, // PAOOP2d
            mapRemove: mapRemove.map { .init(key: $0.key) }, // PAOOP2e
            // art_doubleValue on both counts below: this operation came off the wire, where JSON decoding
            // can give us an NSDecimalNumber
            counterCreate: resolvedCounterCreate.map { .init(count: $0.count?.art_doubleValue ?? 0) }, // PAOOP2f/PAOOP3c
            counterInc: counterInc.map { .init(number: $0.number.art_doubleValue) }, // PAOOP2g
            objectDelete: objectDelete.map { _ in .init() }, // PAOOP2h
            mapClear: mapClear.map { _ in .init() }, // PAOOP2i
        )
    }
}

internal extension ProtocolTypes.MapCreate {
    func toPublicMapCreate() -> MapCreate {
        // The public `ObjectsMapSemantics` has only `.lww` (unknown semantics are dropped, a recorded
        // deviation), so every map surfaces as `.lww`.
        .init(
            semantics: .lww, // MCR2a
            entries: entries?.mapValues { $0.toPublicObjectsMapEntry() } ?? [:], // MCR2b
        )
    }
}

internal extension ProtocolTypes.ObjectsMapEntry {
    func toPublicObjectsMapEntry() -> ObjectsMapEntry {
        .init(
            tombstone: tombstone, // OME2a
            timeserial: timeserial, // OME2b
            serialTimestamp: serialTimestamp, // OME2d
            data: data?.toPublicObjectData(), // OME2c
        )
    }
}

internal extension ProtocolTypes.ObjectData {
    /// Converts internal (decoded) object data to the public ``ObjectData`` (OD2). The public shape
    /// exposes decoded binary directly and has no `encoding`; `number` is a `Double` and `json` is the
    /// decoded `JSONValue` (the internal field is already the OD5-decoded object/array).
    func toPublicObjectData() -> ObjectData {
        .init(
            objectId: objectId, // OD2a
            encoding: nil, // OD2b — internal data is already decoded
            boolean: boolean, // OD2c
            bytes: bytes, // OD2d
            number: number?.art_doubleValue, // OD2e — art_doubleValue: this data came off the wire, as JSON decoded it
            string: string, // OD2f
            json: json?.toJSONValue, // OD2g — pass the decoded value through, no re-serialization
        )
    }
}

// MARK: - Message size calculation (OM3, OOP4, OST3, OD3)

// The size algorithm below is implemented on the `ProtocolTypes` (non-wire) types
// rather than on `OutboundWireObjectMessage` because it depends on the
// `MapCreate`/`CounterCreate` retained in `mapCreateWithObjectId`/`counterCreateWithObjectId`
// (RTLMV4j5 / RTLCV4g5), which our `toWire(...)` conversion deliberately drops. Those payloads
// survive only on the `ProtocolTypes` types, which is also exactly what `nosync_publish` carries.
//
// Note on string measurement: message-size accounting measures string fields two different ways,
// per the resolved convention (the spec's TO3l8f canonical definition, and Ably's published "How
// does Ably measure message size" accounting). The RTO15d client-side size gate therefore accepts
// or rejects a given message identically across the cocoa, java and js SDKs:
//   - UTF-8 byte length for every plain string and map key: `clientId` (OM3f), the
//     `MapCreate`/`MapSet`/`MapRemove` operation keys (MCR3a1/MST3c/MRM3a), the `ObjectsMap`
//     map-state entry keys (OMP4a1) and `ObjectData.string`/`json` (OD3e/OD3g). Keys are the same
//     kind of string as values, and because the server counts bytes, measuring in UTF-8 bytes can
//     never under-count and thus never false-reject a message the server would accept.
//   - String length (the number of UTF-16 code units) for `extras` (OM3d), matching the docs'
//     verbatim rule that `extras` is "the string length of its JSON representation". All three SDKs
//     already agree on this.
// For ASCII these coincide; they differ only for non-ASCII text.

internal extension ProtocolTypes.OutboundObjectMessage {
    /// The size of this `ObjectMessage` in bytes, calculated per OM3. Used by RTO15d to enforce `maxMessageSize`.
    var size: Int {
        // OM3a: sum of the sizes of the clientId, operation, object and extras properties.
        let clientIdSize = clientId?.utf8.count ?? 0 // OM3f (UTF-8 byte length)
        let operationSize = operation?.size ?? 0 // OM3b, OOP4
        let objectSize = object?.size ?? 0 // OM3c, OST3
        // OM3d: "the string length of its JSON representation" (docs verbatim) — measured as the
        // number of UTF-16 code units (`.utf16.count`), not UTF-8 bytes; all three SDKs agree.
        let extrasSize = extras.map { JSONObjectOrArray.object($0).toJSONString.utf16.count } ?? 0
        // OM3e: a null or omitted property contributes zero.
        return clientIdSize + operationSize + objectSize + extrasSize
    }
}

internal extension ProtocolTypes.ObjectOperation {
    /// The size of this `ObjectOperation` in bytes, calculated per OOP4.
    var size: Int {
        // OOP4h: map create component — `mapCreate`, else the `MapCreate` retained in `mapCreateWithObjectId`, else zero.
        let mapCreateSize = mapCreate?.size ?? mapCreateWithObjectId?.derivedFrom?.size ?? 0 // OOP4h1, OOP4h2, OOP4h3
        let mapSetSize = mapSet?.size ?? 0 // OOP4i, MST3
        let mapRemoveSize = mapRemove?.size ?? 0 // OOP4j, MRM3
        // OOP4k: counter create component — `counterCreate`, else the `CounterCreate` retained in `counterCreateWithObjectId`, else zero.
        let counterCreateSize = counterCreate?.size ?? counterCreateWithObjectId?.derivedFrom?.size ?? 0 // OOP4k1, OOP4k2, OOP4k3
        let counterIncSize = counterInc?.size ?? 0 // OOP4l, CIN3
        // OOP4g / OOP4f: sum of the components; a null or omitted property contributes zero.
        return mapCreateSize + mapSetSize + mapRemoveSize + counterCreateSize + counterIncSize
    }
}

internal extension ProtocolTypes.ObjectState {
    /// The size of this `ObjectState` in bytes, calculated per OST3.
    var size: Int {
        let mapSize = map?.size ?? 0 // OST3b, OMP4
        let counterSize = counter?.size ?? 0 // OST3c, OCN3
        let createOpSize = createOp?.size ?? 0 // OST3d, OOP4
        // OST3a / OST3e: sum of the properties; a null or omitted property contributes zero.
        return mapSize + counterSize + createOpSize
    }
}

internal extension ProtocolTypes.MapCreate {
    /// The size of this `MapCreate` in bytes, calculated per MCR3.
    var size: Int {
        // MCR3a: sum over entries of the key size plus the entry size. MCR3a1 keys are measured as
        // their UTF-8 byte length.
        entries?.reduce(0) { $0 + $1.key.utf8.count + $1.value.size } ?? 0 // MCR3a1, MCR3a2, MCR3b
    }
}

internal extension ProtocolTypes.MapSet {
    /// The size of this `MapSet` in bytes, calculated per MST3.
    var size: Int {
        // MST3a: sum of the key and value sizes. MST3c: the key is measured as its UTF-8 byte length.
        key.utf8.count + (value?.size ?? 0) // MST3b (OD3), MST3c, MST3d
    }
}

internal extension ProtocolTypes.ObjectsMap {
    /// The size of this `ObjectsMap` in bytes, calculated per OMP4.
    var size: Int {
        // OMP4a: sum over entries of the key size plus the entry size. OMP4a1 map-state entry keys
        // are measured as their UTF-8 byte length, consistent with all other operation/map keys.
        entries?.reduce(0) { $0 + $1.key.utf8.count + $1.value.size } ?? 0 // OMP4a1, OMP4a2, OMP4b
    }
}

internal extension ProtocolTypes.ObjectsMapEntry {
    /// The size of this `ObjectsMapEntry` in bytes, calculated per OME3.
    var size: Int {
        // OME3a, OME3b: equal to the size of the `data` property (OD3). OME3c: null/omitted is zero.
        data?.size ?? 0
    }
}

internal extension ProtocolTypes.ObjectData {
    /// The size of this `ObjectData` in bytes, calculated per OD3.
    var size: Int {
        // OD3: ably-java returns the size of the first present leaf, checked in this order.
        if let string {
            return string.utf8.count // OD3e (UTF-8 byte length)
        }
        if number != nil {
            return 8 // OD3d
        }
        if boolean != nil {
            return 1 // OD3b
        }
        if let bytes {
            return bytes.count // OD3c (actual binary length, not the base64 representation)
        }
        if let json {
            return json.toJSONString.utf8.count // OD3g (byte length of the JSON-encoded string)
        }
        return 0 // OD3f
    }
}

// The following four types are shared between the wire and non-wire models, so their size
// calculations live here alongside the rest of the OM3 algorithm.

internal extension WireMapRemove {
    /// The size of this `MapRemove` in bytes, calculated per MRM3.
    var size: Int {
        // MRM3a: the `key` property, measured as its UTF-8 byte length.
        key.utf8.count
    }
}

internal extension WireCounterCreate {
    /// The size of this `CounterCreate` in bytes, calculated per CCR3.
    var size: Int {
        // CCR3a: 8 if `count` is a number. CCR3b: 0 if `count` is null or omitted.
        count != nil ? 8 : 0
    }
}

internal extension WireCounterInc {
    /// The size of this `CounterInc` in bytes, calculated per CIN3.
    var size: Int {
        8 // CIN3a (`number` is always present on our type; a number is 8 bytes)
    }
}

internal extension WireObjectsCounter {
    /// The size of this `ObjectsCounter` in bytes, calculated per OCN3.
    var size: Int {
        // OCN3a: 8 if `count` is a number. OCN3b: 0 if `count` is null or omitted.
        count != nil ? 8 : 0
    }
}

// MARK: - CustomDebugStringConvertible

extension ProtocolTypes.InboundObjectMessage: CustomDebugStringConvertible {
    internal var debugDescription: String {
        var parts: [String] = []

        if let id { parts.append("id: \(id)") }
        if let clientId { parts.append("clientId: \(clientId)") }
        if let connectionId { parts.append("connectionId: \(connectionId)") }
        if let extras { parts.append("extras: \(extras)") }
        if let timestamp { parts.append("timestamp: \(timestamp)") }
        if let operation { parts.append("operation: \(operation)") }
        if let object { parts.append("object: \(object)") }
        if let serial { parts.append("serial: \(serial)") }
        if let siteCode { parts.append("siteCode: \(siteCode)") }
        if let serialTimestamp { parts.append("serialTimestamp: \(serialTimestamp)") }

        return "{ " + parts.joined(separator: ", ") + " }"
    }
}

extension ProtocolTypes.OutboundObjectMessage: CustomDebugStringConvertible {
    internal var debugDescription: String {
        var parts: [String] = []

        if let id { parts.append("id: \(id)") }
        if let clientId { parts.append("clientId: \(clientId)") }
        if let connectionId { parts.append("connectionId: \(connectionId)") }
        if let extras { parts.append("extras: \(extras)") }
        if let timestamp { parts.append("timestamp: \(timestamp)") }
        if let operation { parts.append("operation: \(operation)") }
        if let object { parts.append("object: \(object)") }
        if let serial { parts.append("serial: \(serial)") }
        if let siteCode { parts.append("siteCode: \(siteCode)") }
        if let serialTimestamp { parts.append("serialTimestamp: \(serialTimestamp)") }

        return "{ " + parts.joined(separator: ", ") + " }"
    }
}

extension ProtocolTypes.ObjectOperation: CustomDebugStringConvertible {
    internal var debugDescription: String {
        var parts: [String] = []

        parts.append("action: \(action)")
        parts.append("objectId: \(objectId)")
        if let mapCreate { parts.append("mapCreate: \(mapCreate)") }
        if let mapSet { parts.append("mapSet: \(mapSet)") }
        if let mapRemove { parts.append("mapRemove: \(mapRemove)") }
        if let counterCreate { parts.append("counterCreate: \(counterCreate)") }
        if let counterInc { parts.append("counterInc: \(counterInc)") }
        if let objectDelete { parts.append("objectDelete: \(objectDelete)") }
        if let mapCreateWithObjectId { parts.append("mapCreateWithObjectId: \(mapCreateWithObjectId)") }
        if let counterCreateWithObjectId { parts.append("counterCreateWithObjectId: \(counterCreateWithObjectId)") }
        if let mapClear { parts.append("mapClear: \(mapClear)") }

        return "{ " + parts.joined(separator: ", ") + " }"
    }
}

extension ProtocolTypes.ObjectState: CustomDebugStringConvertible {
    internal var debugDescription: String {
        var parts: [String] = []

        parts.append("objectId: \(objectId)")
        parts.append("siteTimeserials: \(siteTimeserials)")
        parts.append("tombstone: \(tombstone)")
        if let createOp { parts.append("createOp: \(createOp)") }
        if let map { parts.append("map: \(map)") }
        if let counter { parts.append("counter: \(counter)") }

        return "{ " + parts.joined(separator: ", ") + " }"
    }
}

extension ProtocolTypes.ObjectsMap: CustomDebugStringConvertible {
    internal var debugDescription: String {
        var parts: [String] = []

        parts.append("semantics: \(semantics)")
        if let entries {
            let formattedEntries = entries
                .map { key, entry in
                    "\(key): \(entry)"
                }
                .joined(separator: ", ")
            parts.append("entries: { \(formattedEntries) }")
        }
        if let clearTimeserial { parts.append("clearTimeserial: \(clearTimeserial)") }

        return "{ " + parts.joined(separator: ", ") + " }"
    }
}

extension ProtocolTypes.ObjectsMapEntry: CustomDebugStringConvertible {
    internal var debugDescription: String {
        var parts: [String] = []

        if let tombstone { parts.append("tombstone: \(tombstone)") }
        if let timeserial { parts.append("timeserial: \(timeserial)") }
        if let data { parts.append("data: \(data)") }
        if let serialTimestamp { parts.append("serialTimestamp: \(serialTimestamp)") }

        return "{ " + parts.joined(separator: ", ") + " }"
    }
}

extension ProtocolTypes.ObjectData: CustomDebugStringConvertible {
    internal var debugDescription: String {
        var parts: [String] = []

        if let objectId { parts.append("objectId: \(objectId)") }
        if let boolean { parts.append("boolean: \(boolean)") }
        if let bytes { parts.append("bytes: \(bytes.count) bytes") }
        if let number { parts.append("number: \(number)") }
        if let string { parts.append("string: \(string)") }
        if let json { parts.append("json: \(json)") }

        return "{ " + parts.joined(separator: ", ") + " }"
    }
}

extension ProtocolTypes.MapSet: CustomDebugStringConvertible {
    internal var debugDescription: String {
        var parts: [String] = []

        parts.append("key: \(key)")
        if let value { parts.append("value: \(value)") }

        return "{ " + parts.joined(separator: ", ") + " }"
    }
}

extension ProtocolTypes.MapCreate: CustomDebugStringConvertible {
    internal var debugDescription: String {
        var parts: [String] = []

        parts.append("semantics: \(semantics)")
        if let entries {
            let formattedEntries = entries
                .map { key, entry in
                    "\(key): \(entry)"
                }
                .joined(separator: ", ")
            parts.append("entries: { \(formattedEntries) }")
        }

        return "{ " + parts.joined(separator: ", ") + " }"
    }
}

extension ProtocolTypes.MapCreateWithObjectId: CustomDebugStringConvertible {
    internal var debugDescription: String {
        var parts: [String] = []

        parts.append("initialValue: \(initialValue)")
        parts.append("nonce: \(nonce)")
        if let derivedFrom { parts.append("derivedFrom: \(derivedFrom)") }

        return "{ " + parts.joined(separator: ", ") + " }"
    }
}

extension ProtocolTypes.CounterCreateWithObjectId: CustomDebugStringConvertible {
    internal var debugDescription: String {
        var parts: [String] = []

        parts.append("initialValue: \(initialValue)")
        parts.append("nonce: \(nonce)")
        if let derivedFrom { parts.append("derivedFrom: \(derivedFrom)") }

        return "{ " + parts.joined(separator: ", ") + " }"
    }
}
