internal import _AblyPluginSupportPrivate
import Ably
import Foundation

// This file contains the ObjectMessage types that we send and receive over the wire. We convert them to and from the corresponding non-wire types (e.g. `InboundObjectMessage`) for use within the codebase.

/// An `ObjectMessage` received in the `state` property of an `OBJECT` or `OBJECT_SYNC` `ProtocolMessage`.
internal struct InboundWireObjectMessage {
    // TODO: Spec has `id`, `connectionId`, `timestamp`, `clientId`, `serial`, `sideCode` as non-nullable but I don't think this is right; raised https://github.com/ably/specification/issues/334
    internal var id: String? // OM2a
    internal var clientId: String? // OM2b
    internal var connectionId: String? // OM2c
    internal var extras: [String: JSONValue]? // OM2d
    internal var timestamp: Date? // OM2e
    internal var operation: WireObjectOperation? // OM2f
    internal var object: WireObjectState? // OM2g
    internal var serial: String? // OM2h
    internal var siteCode: String? // OM2i
    internal var serialTimestamp: Date? // OM2j
}

/// An `ObjectMessage` to be sent in the `state` property of an `OBJECT` `ProtocolMessage`.
internal struct OutboundWireObjectMessage {
    internal var id: String? // OM2a
    internal var clientId: String? // OM2b
    internal var connectionId: String?
    internal var extras: [String: JSONValue]? // OM2d
    internal var timestamp: Date? // OM2e
    internal var operation: WireObjectOperation? // OM2f
    internal var object: WireObjectState? // OM2g
    internal var serial: String? // OM2h
    internal var siteCode: String? // OM2i
    internal var serialTimestamp: Date? // OM2j
}

/// The keys for decoding an `InboundWireObjectMessage` or encoding an `OutboundWireObjectMessage`.
internal enum WireObjectMessageWireKey: String {
    case id
    case clientId
    case connectionId
    case extras
    case timestamp
    case operation
    case object
    case serial
    case siteCode
    case serialTimestamp
}

internal extension InboundWireObjectMessage {
    /// An error that can occur when decoding an ``InboundWireObjectMessage``.
    enum DecodingError: Error {
        // TODO: after https://github.com/ably/specification/issues/334 resolved, throw or remove these as needed
        /// The containing `ProtocolMessage` does not have an `id`.
        case parentMissingID
        /// The containing `ProtocolMessage` does not have a `connectionId`.
        case parentMissingConnectionID
        /// The containing `ProtocolMessage` does not have a `timestamp`.
        case parentMissingTimestamp
    }

    /// Decodes the `ObjectMessage` and then uses the containing `ProtocolMessage` to populate some absent fields per the rules of the specification.
    init(
        wireObject: [String: WireValue],
        decodingContext: _AblyPluginSupportPrivate.DecodingContextProtocol
    ) throws(ARTErrorInfo) {
        // OM2a
        if let id = try wireObject.optionalStringValueForKey(WireObjectMessageWireKey.id.rawValue) {
            self.id = id
        } else if let parentID = decodingContext.parentID {
            id = "\(parentID):\(decodingContext.indexInParent)"
        }

        clientId = try wireObject.optionalStringValueForKey(WireObjectMessageWireKey.clientId.rawValue)

        // OM2c
        if let connectionId = try wireObject.optionalStringValueForKey(WireObjectMessageWireKey.connectionId.rawValue) {
            self.connectionId = connectionId
        } else if let parentConnectionID = decodingContext.parentConnectionID {
            connectionId = parentConnectionID
        }

        if let wireExtras = try wireObject.optionalObjectValueForKey(WireObjectMessageWireKey.extras.rawValue) {
            extras = try wireExtras.ablyLiveObjects_mapValuesWithTypedThrow { wireValue throws(ARTErrorInfo) in
                try wireValue.toJSONValue
            }
        } else {
            extras = nil
        }

        // OM2e
        if let timestamp = try wireObject.optionalAblyProtocolDateValueForKey(WireObjectMessageWireKey.timestamp.rawValue) {
            self.timestamp = timestamp
        } else if let parentTimestamp = decodingContext.parentTimestamp {
            timestamp = parentTimestamp
        }

        operation = try wireObject.optionalDecodableValueForKey(WireObjectMessageWireKey.operation.rawValue)
        object = try wireObject.optionalDecodableValueForKey(WireObjectMessageWireKey.object.rawValue)
        serial = try wireObject.optionalStringValueForKey(WireObjectMessageWireKey.serial.rawValue)
        siteCode = try wireObject.optionalStringValueForKey(WireObjectMessageWireKey.siteCode.rawValue)
        serialTimestamp = try wireObject.optionalAblyProtocolDateValueForKey(WireObjectMessageWireKey.serialTimestamp.rawValue)
    }
}

extension OutboundWireObjectMessage: WireObjectEncodable {
    internal var toWireObject: [String: WireValue] {
        var result: [String: WireValue] = [:]

        if let id {
            result[WireObjectMessageWireKey.id.rawValue] = .string(id)
        }
        if let connectionId {
            result[WireObjectMessageWireKey.connectionId.rawValue] = .string(connectionId)
        }
        if let timestamp {
            result[WireObjectMessageWireKey.timestamp.rawValue] = .number(NSNumber(value: (timestamp.timeIntervalSince1970) * 1000))
        }
        if let siteCode {
            result[WireObjectMessageWireKey.siteCode.rawValue] = .string(siteCode)
        }
        if let serial {
            result[WireObjectMessageWireKey.serial.rawValue] = .string(serial)
        }
        if let clientId {
            result[WireObjectMessageWireKey.clientId.rawValue] = .string(clientId)
        }
        if let extras {
            result[WireObjectMessageWireKey.extras.rawValue] = .object(extras.mapValues { .init(jsonValue: $0) })
        }
        if let operation {
            result[WireObjectMessageWireKey.operation.rawValue] = .object(operation.toWireObject)
        }
        if let object {
            result[WireObjectMessageWireKey.object.rawValue] = .object(object.toWireObject)
        }
        if let serialTimestamp {
            result[WireObjectMessageWireKey.serialTimestamp.rawValue] = .number(NSNumber(value: serialTimestamp.timeIntervalSince1970 * 1000))
        }
        return result
    }
}

internal extension ProtocolTypes {
    // OOP2
    enum ObjectOperationAction: Int {
        case mapCreate = 0
        case mapSet = 1
        case mapRemove = 2
        case counterCreate = 3
        case counterInc = 4
        case objectDelete = 5
        case mapClear = 6
    }

    // OMP2
    enum ObjectsMapSemantics: Int {
        case lww = 0
    }
}

internal struct WireObjectOperation {
    internal var action: WireEnum<ProtocolTypes.ObjectOperationAction> // OOP3a
    internal var objectId: String // OOP3b
    internal var mapCreate: WireMapCreate? // OOP3j
    internal var mapSet: WireMapSet? // OOP3k
    internal var mapRemove: WireMapRemove? // OOP3l
    internal var counterCreate: WireCounterCreate? // OOP3m
    internal var counterInc: WireCounterInc? // OOP3n
    internal var objectDelete: WireObjectDelete? // OOP3o
    internal var mapCreateWithObjectId: WireMapCreateWithObjectId? // OOP3p
    internal var counterCreateWithObjectId: WireCounterCreateWithObjectId? // OOP3q
    internal var mapClear: WireMapClear? // OOP3r
}

extension WireObjectOperation: WireObjectCodable {
    internal enum WireKey: String {
        case action
        case objectId
        case mapCreate
        case mapSet
        case mapRemove
        case counterCreate
        case counterInc
        case objectDelete
        case mapCreateWithObjectId
        case counterCreateWithObjectId
        case mapClear
    }

    internal init(wireObject: [String: WireValue]) throws(ARTErrorInfo) {
        action = try wireObject.wireEnumValueForKey(WireKey.action.rawValue)
        objectId = try wireObject.stringValueForKey(WireKey.objectId.rawValue)

        mapCreate = try wireObject.optionalDecodableValueForKey(WireKey.mapCreate.rawValue)
        mapSet = try wireObject.optionalDecodableValueForKey(WireKey.mapSet.rawValue)
        mapRemove = try wireObject.optionalDecodableValueForKey(WireKey.mapRemove.rawValue)
        counterCreate = try wireObject.optionalDecodableValueForKey(WireKey.counterCreate.rawValue)
        counterInc = try wireObject.optionalDecodableValueForKey(WireKey.counterInc.rawValue)
        objectDelete = try wireObject.optionalDecodableValueForKey(WireKey.objectDelete.rawValue)
        mapClear = try wireObject.optionalDecodableValueForKey(WireKey.mapClear.rawValue)
        // Outbound-only — do not access on inbound data
        mapCreateWithObjectId = nil
        counterCreateWithObjectId = nil
    }

    internal var toWireObject: [String: WireValue] {
        var result: [String: WireValue] = [
            WireKey.action.rawValue: .number(action.rawValue as NSNumber),
            WireKey.objectId.rawValue: .string(objectId),
        ]

        if let mapCreate {
            result[WireKey.mapCreate.rawValue] = .object(mapCreate.toWireObject)
        }
        if let mapSet {
            result[WireKey.mapSet.rawValue] = .object(mapSet.toWireObject)
        }
        if let mapRemove {
            result[WireKey.mapRemove.rawValue] = .object(mapRemove.toWireObject)
        }
        if let counterCreate {
            result[WireKey.counterCreate.rawValue] = .object(counterCreate.toWireObject)
        }
        if let counterInc {
            result[WireKey.counterInc.rawValue] = .object(counterInc.toWireObject)
        }
        if let objectDelete {
            result[WireKey.objectDelete.rawValue] = .object(objectDelete.toWireObject)
        }
        if let mapCreateWithObjectId {
            result[WireKey.mapCreateWithObjectId.rawValue] = .object(mapCreateWithObjectId.toWireObject)
        }
        if let counterCreateWithObjectId {
            result[WireKey.counterCreateWithObjectId.rawValue] = .object(counterCreateWithObjectId.toWireObject)
        }
        if let mapClear {
            result[WireKey.mapClear.rawValue] = .object(mapClear.toWireObject)
        }

        return result
    }
}

internal struct WireObjectState {
    internal var objectId: String // OST2a
    internal var siteTimeserials: [String: String] // OST2b
    internal var tombstone: Bool // OST2c
    internal var createOp: WireObjectOperation? // OST2d
    internal var map: WireObjectsMap? // OST2e
    internal var counter: WireObjectsCounter? // OST2f
}

extension WireObjectState: WireObjectCodable {
    internal enum WireKey: String {
        case objectId
        case siteTimeserials
        case tombstone
        case createOp
        case map
        case counter
    }

    internal init(wireObject: [String: WireValue]) throws(ARTErrorInfo) {
        objectId = try wireObject.stringValueForKey(WireKey.objectId.rawValue)
        siteTimeserials = try wireObject.objectValueForKey(WireKey.siteTimeserials.rawValue).ablyLiveObjects_mapValuesWithTypedThrow { value throws(ARTErrorInfo) in
            guard case let .string(string) = value else {
                throw WireValueDecodingError.wrongTypeForKey(WireKey.siteTimeserials.rawValue, actualValue: value).toARTErrorInfo()
            }
            return string
        }
        tombstone = try wireObject.boolValueForKey(WireKey.tombstone.rawValue)
        createOp = try wireObject.optionalDecodableValueForKey(WireKey.createOp.rawValue)
        map = try wireObject.optionalDecodableValueForKey(WireKey.map.rawValue)
        counter = try wireObject.optionalDecodableValueForKey(WireKey.counter.rawValue)
    }

    internal var toWireObject: [String: WireValue] {
        var result: [String: WireValue] = [
            WireKey.objectId.rawValue: .string(objectId),
            WireKey.siteTimeserials.rawValue: .object(siteTimeserials.mapValues { .string($0) }),
            WireKey.tombstone.rawValue: .bool(tombstone),
        ]

        if let createOp {
            result[WireKey.createOp.rawValue] = .object(createOp.toWireObject)
        }
        if let map {
            result[WireKey.map.rawValue] = .object(map.toWireObject)
        }
        if let counter {
            result[WireKey.counter.rawValue] = .object(counter.toWireObject)
        }

        return result
    }
}

internal struct WireObjectsMap {
    internal var semantics: WireEnum<ProtocolTypes.ObjectsMapSemantics> // OMP3a
    internal var entries: [String: WireObjectsMapEntry]? // OMP3b
    internal var clearTimeserial: String? // OMP3c
}

extension WireObjectsMap: WireObjectCodable {
    internal enum WireKey: String {
        case semantics
        case entries
        case clearTimeserial
    }

    internal init(wireObject: [String: WireValue]) throws(ARTErrorInfo) {
        semantics = try wireObject.wireEnumValueForKey(WireKey.semantics.rawValue)
        entries = try wireObject.optionalObjectValueForKey(WireKey.entries.rawValue)?.ablyLiveObjects_mapValuesWithTypedThrow { value throws(ARTErrorInfo) in
            guard case let .object(object) = value else {
                throw WireValueDecodingError.wrongTypeForKey(WireKey.entries.rawValue, actualValue: value).toARTErrorInfo()
            }
            return try WireObjectsMapEntry(wireObject: object)
        }
        clearTimeserial = try wireObject.optionalStringValueForKey(WireKey.clearTimeserial.rawValue)
    }

    internal var toWireObject: [String: WireValue] {
        var result: [String: WireValue] = [
            WireKey.semantics.rawValue: .number(semantics.rawValue as NSNumber),
        ]

        if let entries {
            result[WireKey.entries.rawValue] = .object(entries.mapValues { .object($0.toWireObject) })
        }
        if let clearTimeserial {
            result[WireKey.clearTimeserial.rawValue] = .string(clearTimeserial)
        }

        return result
    }
}

internal struct WireObjectsCounter: Equatable {
    internal var count: NSNumber? // OCN2a
}

extension WireObjectsCounter: WireObjectCodable {
    internal enum WireKey: String {
        case count
    }

    internal init(wireObject: [String: WireValue]) throws(ARTErrorInfo) {
        count = try wireObject.optionalNumberValueForKey(WireKey.count.rawValue)
    }

    internal var toWireObject: [String: WireValue] {
        var result: [String: WireValue] = [:]
        if let count {
            result[WireKey.count.rawValue] = .number(count)
        }
        return result
    }
}

internal struct WireMapSet {
    internal var key: String // MST2a
    internal var value: WireObjectData? // MST2b
}

extension WireMapSet: WireObjectCodable {
    internal enum WireKey: String {
        case key
        case value
    }

    internal init(wireObject: [String: WireValue]) throws(ARTErrorInfo) {
        key = try wireObject.stringValueForKey(WireKey.key.rawValue)
        value = try wireObject.optionalDecodableValueForKey(WireKey.value.rawValue)
    }

    internal var toWireObject: [String: WireValue] {
        var result: [String: WireValue] = [
            WireKey.key.rawValue: .string(key),
        ]

        if let value {
            result[WireKey.value.rawValue] = .object(value.toWireObject)
        }

        return result
    }
}

internal struct WireMapRemove: Equatable {
    internal var key: String // MRM2a
}

extension WireMapRemove: WireObjectCodable {
    internal enum WireKey: String {
        case key
    }

    internal init(wireObject: [String: WireValue]) throws(ARTErrorInfo) {
        key = try wireObject.stringValueForKey(WireKey.key.rawValue)
    }

    internal var toWireObject: [String: WireValue] {
        [
            WireKey.key.rawValue: .string(key),
        ]
    }
}

internal struct WireMapCreate {
    internal var semantics: WireEnum<ProtocolTypes.ObjectsMapSemantics> // MCR2a
    internal var entries: [String: WireObjectsMapEntry]? // MCR2b
}

extension WireMapCreate: WireObjectCodable {
    internal enum WireKey: String {
        case semantics
        case entries
    }

    internal init(wireObject: [String: WireValue]) throws(ARTErrorInfo) {
        semantics = try wireObject.wireEnumValueForKey(WireKey.semantics.rawValue)
        entries = try wireObject.optionalObjectValueForKey(WireKey.entries.rawValue)?.ablyLiveObjects_mapValuesWithTypedThrow { value throws(ARTErrorInfo) in
            guard case let .object(object) = value else {
                throw WireValueDecodingError.wrongTypeForKey(WireKey.entries.rawValue, actualValue: value).toARTErrorInfo()
            }
            return try WireObjectsMapEntry(wireObject: object)
        }
    }

    internal var toWireObject: [String: WireValue] {
        var result: [String: WireValue] = [
            WireKey.semantics.rawValue: .number(semantics.rawValue as NSNumber),
        ]

        if let entries {
            result[WireKey.entries.rawValue] = .object(entries.mapValues { .object($0.toWireObject) })
        }

        return result
    }
}

internal struct WireCounterCreate: Equatable {
    internal var count: NSNumber? // CCR2a
}

extension WireCounterCreate: WireObjectCodable {
    internal enum WireKey: String {
        case count
    }

    internal init(wireObject: [String: WireValue]) throws(ARTErrorInfo) {
        count = try wireObject.optionalNumberValueForKey(WireKey.count.rawValue)
    }

    internal var toWireObject: [String: WireValue] {
        var result: [String: WireValue] = [:]
        if let count {
            result[WireKey.count.rawValue] = .number(count)
        }
        return result
    }
}

internal struct WireCounterInc: Equatable {
    internal var number: NSNumber // CIN2a
}

extension WireCounterInc: WireObjectCodable {
    internal enum WireKey: String {
        case number
    }

    internal init(wireObject: [String: WireValue]) throws(ARTErrorInfo) {
        number = try wireObject.numberValueForKey(WireKey.number.rawValue)
    }

    internal var toWireObject: [String: WireValue] {
        [
            WireKey.number.rawValue: .number(number),
        ]
    }
}

internal struct WireObjectDelete: Equatable {}

extension WireObjectDelete: WireObjectCodable {
    internal init(wireObject _: [String: WireValue]) throws(ARTErrorInfo) {
        // No fields to decode
    }

    internal var toWireObject: [String: WireValue] {
        [:]
    }
}

internal struct WireMapClear: Equatable {}

extension WireMapClear: WireObjectCodable {
    internal init(wireObject _: [String: WireValue]) throws(ARTErrorInfo) {
        // No fields to decode
    }

    internal var toWireObject: [String: WireValue] {
        [:]
    }
}

internal struct WireMapCreateWithObjectId: Equatable {
    internal var initialValue: String // MCRO2a
    internal var nonce: String // MCRO2b
}

extension WireMapCreateWithObjectId: WireObjectCodable {
    internal enum WireKey: String {
        case nonce
        case initialValue
    }

    internal init(wireObject: [String: WireValue]) throws(ARTErrorInfo) {
        nonce = try wireObject.stringValueForKey(WireKey.nonce.rawValue)
        initialValue = try wireObject.stringValueForKey(WireKey.initialValue.rawValue)
    }

    internal var toWireObject: [String: WireValue] {
        [
            WireKey.nonce.rawValue: .string(nonce),
            WireKey.initialValue.rawValue: .string(initialValue),
        ]
    }
}

internal struct WireCounterCreateWithObjectId: Equatable {
    internal var initialValue: String // CCRO2a
    internal var nonce: String // CCRO2b
}

extension WireCounterCreateWithObjectId: WireObjectCodable {
    internal enum WireKey: String {
        case nonce
        case initialValue
    }

    internal init(wireObject: [String: WireValue]) throws(ARTErrorInfo) {
        nonce = try wireObject.stringValueForKey(WireKey.nonce.rawValue)
        initialValue = try wireObject.stringValueForKey(WireKey.initialValue.rawValue)
    }

    internal var toWireObject: [String: WireValue] {
        [
            WireKey.nonce.rawValue: .string(nonce),
            WireKey.initialValue.rawValue: .string(initialValue),
        ]
    }
}

internal struct WireObjectsMapEntry {
    internal var tombstone: Bool? // OME2a
    internal var timeserial: String? // OME2b
    internal var data: WireObjectData? // OME2c
    internal var serialTimestamp: Date? // OME2d
}

extension WireObjectsMapEntry: WireObjectCodable {
    internal enum WireKey: String {
        case tombstone
        case timeserial
        case data
        case serialTimestamp
    }

    internal init(wireObject: [String: WireValue]) throws(ARTErrorInfo) {
        tombstone = try wireObject.optionalBoolValueForKey(WireKey.tombstone.rawValue)
        timeserial = try wireObject.optionalStringValueForKey(WireKey.timeserial.rawValue)
        data = try wireObject.optionalDecodableValueForKey(WireKey.data.rawValue)
        serialTimestamp = try wireObject.optionalAblyProtocolDateValueForKey(WireKey.serialTimestamp.rawValue)
    }

    internal var toWireObject: [String: WireValue] {
        var result: [String: WireValue] = [:]

        if let data {
            result[WireKey.data.rawValue] = .object(data.toWireObject)
        }
        if let tombstone {
            result[WireKey.tombstone.rawValue] = .bool(tombstone)
        }
        if let timeserial {
            result[WireKey.timeserial.rawValue] = .string(timeserial)
        }
        if let serialTimestamp {
            result[WireKey.serialTimestamp.rawValue] = .number(NSNumber(value: serialTimestamp.timeIntervalSince1970 * 1000))
        }

        return result
    }
}

internal struct WireObjectData {
    internal var objectId: String? // OD2a
    internal var boolean: Bool? // OD2c
    internal var bytes: StringOrData? // OD2d
    internal var number: NSNumber? // OD2e
    internal var string: String? // OD2f
    internal var json: String? // TODO: Needs specification (see https://github.com/ably/ably-liveobjects-swift-plugin/issues/46)
}

extension WireObjectData: WireObjectCodable {
    internal enum WireKey: String {
        case objectId
        case boolean
        case bytes
        case number
        case string
        case json
    }

    internal init(wireObject: [String: WireValue]) throws(ARTErrorInfo) {
        objectId = try wireObject.optionalStringValueForKey(WireKey.objectId.rawValue)
        boolean = try wireObject.optionalBoolValueForKey(WireKey.boolean.rawValue)
        bytes = try wireObject.optionalDecodableValueForKey(WireKey.bytes.rawValue)
        number = try wireObject.optionalNumberValueForKey(WireKey.number.rawValue)
        string = try wireObject.optionalStringValueForKey(WireKey.string.rawValue)
        json = try wireObject.optionalStringValueForKey(WireKey.json.rawValue)
    }

    internal var toWireObject: [String: WireValue] {
        var result: [String: WireValue] = [:]

        if let objectId {
            result[WireKey.objectId.rawValue] = .string(objectId)
        }
        if let boolean {
            result[WireKey.boolean.rawValue] = .bool(boolean)
        }
        if let bytes {
            result[WireKey.bytes.rawValue] = bytes.toWireValue
        }
        if let number {
            result[WireKey.number.rawValue] = .number(number)
        }
        if let string {
            result[WireKey.string.rawValue] = .string(string)
        }
        if let json {
            result[WireKey.json.rawValue] = .string(json)
        }

        return result
    }
}

/// A type that can be either a string or binary data.
///
/// Used to represent the values that `WireObjectData.bytes` might hold, after being encoded per OD4 or before being decoded per OD5.
internal enum StringOrData: Equatable, WireCodable {
    case string(String)
    case data(Data)

    /// An error that can occur when decoding a ``StringOrData``.
    internal enum DecodingError: Error {
        case unsupportedValue(WireValue)
    }

    internal init(wireValue: WireValue) throws(ARTErrorInfo) {
        self = switch wireValue {
        case let .string(string):
            .string(string)
        case let .data(data):
            .data(data)
        default:
            throw DecodingError.unsupportedValue(wireValue).toARTErrorInfo()
        }
    }

    internal var toWireValue: WireValue {
        switch self {
        case let .string(string):
            .string(string)
        case let .data(data):
            .data(data)
        }
    }
}

// MARK: - CustomDebugStringConvertible

extension WireObjectsCounter: CustomDebugStringConvertible {
    internal var debugDescription: String {
        if let count {
            "{ count: \(count) }"
        } else {
            "{ count: nil }"
        }
    }
}

extension WireObjectsMapEntry: CustomDebugStringConvertible {
    internal var debugDescription: String {
        var parts: [String] = []

        if let tombstone { parts.append("tombstone: \(tombstone)") }
        if let timeserial { parts.append("timeserial: \(timeserial)") }
        if let data { parts.append("data: \(data)") }
        if let serialTimestamp { parts.append("serialTimestamp: \(serialTimestamp)") }

        return "{ " + parts.joined(separator: ", ") + " }"
    }
}

extension WireObjectData: CustomDebugStringConvertible {
    internal var debugDescription: String {
        var parts: [String] = []

        if let objectId { parts.append("objectId: \(objectId)") }
        if let boolean { parts.append("boolean: \(boolean)") }
        if let bytes { parts.append("bytes: \(bytes)") }
        if let number { parts.append("number: \(number)") }
        if let string { parts.append("string: \(string)") }
        if let json { parts.append("json: \(json)") }

        return "{ " + parts.joined(separator: ", ") + " }"
    }
}

extension WireMapSet: CustomDebugStringConvertible {
    internal var debugDescription: String {
        var parts: [String] = []

        parts.append("key: \(key)")
        if let value { parts.append("value: \(value)") }

        return "{ " + parts.joined(separator: ", ") + " }"
    }
}

extension WireMapRemove: CustomDebugStringConvertible {
    internal var debugDescription: String {
        "{ key: \(key) }"
    }
}

extension WireMapCreate: CustomDebugStringConvertible {
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

extension WireCounterCreate: CustomDebugStringConvertible {
    internal var debugDescription: String {
        if let count {
            "{ count: \(count) }"
        } else {
            "{ count: nil }"
        }
    }
}

extension WireCounterInc: CustomDebugStringConvertible {
    internal var debugDescription: String {
        "{ number: \(number) }"
    }
}

extension WireObjectDelete: CustomDebugStringConvertible {
    internal var debugDescription: String {
        "{ }"
    }
}

extension WireMapCreateWithObjectId: CustomDebugStringConvertible {
    internal var debugDescription: String {
        "{ initialValue: \(initialValue), nonce: \(nonce) }"
    }
}

extension WireCounterCreateWithObjectId: CustomDebugStringConvertible {
    internal var debugDescription: String {
        "{ initialValue: \(initialValue), nonce: \(nonce) }"
    }
}
