import Ably
import Foundation

// The user-facing value types representing an inbound object message that carried an
// operation. These correspond to the spec's `PublicAPI::ObjectMessage` (PAOM),
// `PublicAPI::ObjectOperation` (PAOOP) and friends.
//
// They are delivered to subscription listeners (see ``PathObjectSubscriptionEvent`` /
// ``InstanceSubscriptionEvent``) so user code can inspect the metadata of the message that
// triggered an object change. They are modelled as plain `Sendable` value types rather than
// protocols: they carry no behaviour, only data. Their internal wire counterparts of the same
// name live under the ``ProtocolTypes`` namespace.

// MARK: - ObjectMessage (PAOM)

/// The user-facing representation of an inbound object message that carried an operation.
/// Spec: `PAOM`.
public struct ObjectMessage: Sendable, Equatable {
    /// The `id` of the source object message. Spec: `PAOM2a`.
    public var id: String?
    /// The `clientId` of the source object message. Spec: `PAOM2b`.
    public var clientId: String?
    /// The `connectionId` of the source object message. Spec: `PAOM2c`.
    public var connectionId: String?
    /// The `timestamp` of the source object message. Spec: `PAOM2d`.
    public var timestamp: Date?
    /// The name of the channel on which the source object message was received. Spec: `PAOM2e`.
    public var channel: String
    /// The operation carried by the source object message. Spec: `PAOM2f`.
    public var operation: ObjectOperation
    /// The `serial` of the source object message. Spec: `PAOM2g`.
    public var serial: String?
    /// The `serialTimestamp` of the source object message. Spec: `PAOM2h`.
    public var serialTimestamp: Date?
    /// The `siteCode` of the source object message. Spec: `PAOM2i`.
    public var siteCode: String?
    /// The `extras` of the source object message. Spec: `PAOM2j`.
    public var extras: [String: JSONValue]?

    public init(
        id: String? = nil,
        clientId: String? = nil,
        connectionId: String? = nil,
        timestamp: Date? = nil,
        channel: String,
        operation: ObjectOperation,
        serial: String? = nil,
        serialTimestamp: Date? = nil,
        siteCode: String? = nil,
        extras: [String: JSONValue]? = nil
    ) {
        self.id = id
        self.clientId = clientId
        self.connectionId = connectionId
        self.timestamp = timestamp
        self.channel = channel
        self.operation = operation
        self.serial = serial
        self.serialTimestamp = serialTimestamp
        self.siteCode = siteCode
        self.extras = extras
    }
}

// MARK: - ObjectOperation (PAOOP)

/// The user-facing representation of an object operation. It is the type of
/// ``ObjectMessage/operation``.
///
/// Unlike the wire `ObjectOperation`, it does not carry the `mapCreateWithObjectId` /
/// `counterCreateWithObjectId` variants; those outbound-only forms are resolved back to their
/// derived ``MapCreate`` / ``CounterCreate`` forms. Spec: `PAOOP`.
public struct ObjectOperation: Sendable, Equatable {
    /// The action of the operation. Spec: `PAOOP2a`.
    public var action: ObjectOperationAction
    /// The object ID the operation applies to. Spec: `PAOOP2b`.
    public var objectId: String
    /// The map-create payload, if applicable. Spec: `PAOOP2c`.
    public var mapCreate: MapCreate?
    /// The map-set payload, if applicable. Spec: `PAOOP2d`.
    public var mapSet: MapSet?
    /// The map-remove payload, if applicable. Spec: `PAOOP2e`.
    public var mapRemove: MapRemove?
    /// The counter-create payload, if applicable. Spec: `PAOOP2f`.
    public var counterCreate: CounterCreate?
    /// The counter-increment payload, if applicable. Spec: `PAOOP2g`.
    public var counterInc: CounterInc?
    /// The object-delete payload, if applicable. Spec: `PAOOP2h`.
    public var objectDelete: ObjectDelete?
    /// The map-clear payload, if applicable. Spec: `PAOOP2i`.
    public var mapClear: MapClear?

    public init(
        action: ObjectOperationAction,
        objectId: String,
        mapCreate: MapCreate? = nil,
        mapSet: MapSet? = nil,
        mapRemove: MapRemove? = nil,
        counterCreate: CounterCreate? = nil,
        counterInc: CounterInc? = nil,
        objectDelete: ObjectDelete? = nil,
        mapClear: MapClear? = nil
    ) {
        self.action = action
        self.objectId = objectId
        self.mapCreate = mapCreate
        self.mapSet = mapSet
        self.mapRemove = mapRemove
        self.counterCreate = counterCreate
        self.counterInc = counterInc
        self.objectDelete = objectDelete
        self.mapClear = mapClear
    }
}

// MARK: - ObjectOperationAction (OOP2)

/// The set of actions that an ``ObjectOperation`` can represent. Spec: `OOP2`.
public enum ObjectOperationAction: Sendable, Equatable {
    case mapCreate
    case mapSet
    case mapRemove
    case counterCreate
    case counterInc
    case objectDelete
    case mapClear
}

// MARK: - Operation payloads

/// The map-create operation payload. Spec: `MCR`.
public struct MapCreate: Sendable, Equatable {
    /// The conflict-resolution semantics for the map. Spec: `MCR2a`.
    public var semantics: ObjectsMapSemantics
    /// The initial entries for the map. Spec: `MCR2b`.
    public var entries: [String: ObjectsMapEntry]

    public init(semantics: ObjectsMapSemantics, entries: [String: ObjectsMapEntry]) {
        self.semantics = semantics
        self.entries = entries
    }
}

/// The map-set operation payload. Spec: `MST`.
public struct MapSet: Sendable, Equatable {
    /// The key being set. Spec: `MST2a`.
    public var key: String
    /// The value being set. Spec: `MST2b`.
    public var value: ObjectData

    public init(key: String, value: ObjectData) {
        self.key = key
        self.value = value
    }
}

/// The map-remove operation payload. Spec: `MRM`.
public struct MapRemove: Sendable, Equatable {
    /// The key being removed. Spec: `MRM2a`.
    public var key: String

    public init(key: String) {
        self.key = key
    }
}

/// The counter-create operation payload. Spec: `CCR`.
public struct CounterCreate: Sendable, Equatable {
    /// The initial count. Spec: `CCR2a`.
    public var count: Double

    public init(count: Double) {
        self.count = count
    }
}

/// The counter-increment operation payload. Spec: `CIN`.
public struct CounterInc: Sendable, Equatable {
    /// The amount to increment by. Spec: `CIN2a`.
    public var number: Double

    public init(number: Double) {
        self.number = number
    }
}

/// The object-delete operation payload. Spec: `ODE`.
public struct ObjectDelete: Sendable, Equatable {
    public init() {}
}

/// The map-clear operation payload. Spec: `MCL`.
public struct MapClear: Sendable, Equatable {
    public init() {}
}

// MARK: - Supporting wire types

/// The conflict-resolution semantics for a map. Spec: `OMP2`.
public enum ObjectsMapSemantics: Sendable, Equatable {
    /// Last-write-wins. Spec: `OMP2`.
    case lww
}

/// A single entry within a ``MapCreate`` payload. Spec: `OME`.
public struct ObjectsMapEntry: Sendable, Equatable {
    /// Whether this entry is tombstoned (removed). Spec: `OME2a`.
    public var tombstone: Bool?
    /// The timeserial at which this entry was last updated. Spec: `OME2b`.
    public var timeserial: String?
    /// The serial timestamp at which this entry was last updated. Spec: `OME2d`.
    public var serialTimestamp: Date?
    /// The entry's data. Spec: `OME2c`.
    public var data: ObjectData?

    public init(
        tombstone: Bool? = nil,
        timeserial: String? = nil,
        serialTimestamp: Date? = nil,
        data: ObjectData? = nil
    ) {
        self.tombstone = tombstone
        self.timeserial = timeserial
        self.serialTimestamp = serialTimestamp
        self.data = data
    }
}

/// The data value carried by a map entry or map-set operation. Spec: `OD`.
public struct ObjectData: Sendable, Equatable {
    /// The object ID, if this data references a `LiveObject`. Spec: `OD2a`.
    public var objectId: String?
    /// The encoding applied to the data. Spec: `OD2b`.
    public var encoding: String?
    /// A boolean value. Spec: `OD2c`.
    public var boolean: Bool?
    /// A binary value. Spec: `OD2d`.
    public var bytes: Data?
    /// A numeric value. Spec: `OD2e`.
    public var number: Double?
    /// A string value. Spec: `OD2f`.
    public var string: String?
    /// The decoded JSON value (a JSON object or array), per `OD2g`. The wire carries this as a
    /// JSON-encoded string, decoded per `OD5`. Spec: `OD2g`.
    public var json: JSONValue?

    public init(
        objectId: String? = nil,
        encoding: String? = nil,
        boolean: Bool? = nil,
        bytes: Data? = nil,
        number: Double? = nil,
        string: String? = nil,
        json: JSONValue? = nil
    ) {
        self.objectId = objectId
        self.encoding = encoding
        self.boolean = boolean
        self.bytes = bytes
        self.number = number
        self.string = string
        self.json = json
    }
}
