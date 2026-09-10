import _AblyPluginSupportPrivate
@testable import AblyLiveObjects
import Foundation

// Shared-module mirror of the UTS spec helper `uts/objects/helpers/standard_test_pool.md`: the
// serial/siteCode vocabulary plus the spec-pool operation-message and `SyncObjectsPool` builders
// that the native `AblyLiveObjectsTests` suite and the UTS objects tier both consume. (The other
// `build_*` operation and `*ObjectState` builders the spec defines live on `TestFactories` in
// `Helpers/TestFactories.swift` — they keep that namespace, so they stay with the rest of the
// 500+-reference factory family.)
//
// Two parts of the spec file are deliberately NOT here:
// 1. The transport-level helpers (`setup_synced_channel`, `build_object_message` /
//    `build_object_sync_message` / `build_ack_message`) are NOT-APPLICABLE — the unit tier has no
//    mock transport (see `objects-mapping.md` §13, "Transport-level stand-ins").
// 2. The UTS-port parallel builders live in `Test/UTS/unit/objects/ObjectsUTSHelpers.swift`
//    (`ObjectsUTS.*`), the port-only harness reserved by the §13 placement boundary — which is
//    where ably-js and ably-java keep their single equivalent file too.
//
// The authoritative spec-symbol → cocoa-symbol index is the `objects-mapping.md` §13 coverage table.

// MARK: - Serial vocabulary

// Spec format definitions (quoted from `standard_test_pool.md`):
//
//   SITE_CODE = "test-site"
//   POOL_SERIAL = "t:0"
//   ack_serial(msgSerial, i) => "t:" + (msgSerial + 1) + ":" + i
//   remote_serial(i) => "t:" + (i + 1)
//   below_ack_serial(i) => "t:0:" + i
//
// Serials compare as strings (RTLM9e) and ad-hoc values silently sort wrong — always call these;
// never inline a `"t:N"` serial or siteCode literal.

enum StandardTestPool {
    /// The harness ConnectionDetails siteCode (spec `SITE_CODE`).
    static let siteCode = "test-site"

    /// The timeserial every standard-pool entry/object is seeded with (spec `POOL_SERIAL`).
    static let poolSerial = "t:0"

    /// Local apply-on-ACK serial (spec `ack_serial(msgSerial, i) => "t:" + (msgSerial + 1) + ":" + i`).
    /// e.g. `ackSerial(msgSerial: 0, i: 0) == "t:1:0"`. Sorts AFTER `poolSerial`.
    static func ackSerial(msgSerial: Int, i: Int) -> String { "t:\(msgSerial + 1):\(i)" }

    /// Remote inbound "winning" serial (spec `remote_serial(i) => "t:" + (i + 1)`).
    /// e.g. `remoteSerial(0) == "t:1"`. Sorts AFTER `poolSerial`.
    static func remoteSerial(_ i: Int) -> String { "t:\(i + 1)" }

    /// "Loses to the ACK serial" probe (spec `below_ack_serial(i) => "t:0:" + i`).
    /// e.g. `belowAckSerial(9) == "t:0:9"`. Sorts BELOW `ackSerial(msgSerial: 0, i: 0)` but ABOVE `poolSerial`.
    static func belowAckSerial(_ i: Int) -> String { "t:0:\(i)" }
}

// MARK: - SyncObjectsPool construction

extension SyncObjectsPool {
    /// Test-only convenience to create a `SyncObjectsPool` from an array of `(state, serialTimestamp)` pairs,
    /// wrapping each in an `InboundObjectMessage` and calling `accumulate`.
    static func testsOnly_fromStates(
        _ states: [(state: ProtocolTypes.ObjectState, serialTimestamp: Date?)],
        logger: AblyLiveObjects.Logger = TestLogger(),
    ) -> SyncObjectsPool {
        var pool = SyncObjectsPool()
        let messages = states.map { pair in
            TestFactories.inboundObjectMessage(
                object: pair.state,
                serialTimestamp: pair.serialTimestamp,
            )
        }
        pool.accumulate(messages, logger: logger)
        return pool
    }
}

// MARK: - Spec-pool operation-message builders

extension TestFactories {
    /// Creates an InboundObjectMessage with an OBJECT_DELETE operation.
    ///
    /// Mirrors the UTS `build_object_delete` builder from
    /// `uts/objects/helpers/standard_test_pool.md`. Takes `serial` / `siteCode` /
    /// `serialTimestamp` as parameters, matching the other `*OperationMessage` builders.
    static func objectDeleteOperationMessage(
        objectId: String = "test:object@123",
        serial: String = "ts1",
        siteCode: String = "site1",
        serialTimestamp: Date? = nil,
    ) -> ProtocolTypes.InboundObjectMessage {
        inboundObjectMessage(
            operation: objectOperation(
                action: .known(.objectDelete),
                objectId: objectId,
                objectDelete: WireObjectDelete(),
            ),
            serial: serial,
            siteCode: siteCode,
            serialTimestamp: serialTimestamp,
        )
    }

    /// Creates an InboundObjectMessage with a MAP_SET operation carrying an arbitrary `ObjectData`
    /// value — the general form of the spec's `build_map_set` (the `String`-taking
    /// `TestFactories.mapSetOperationMessage` overload is the convenience for string values).
    /// Used by the UTS map ports for `{ objectId: … }` / `{ number: … }` MapSet values.
    static func mapSetOperationMessage(
        objectId: String,
        key: String,
        value: ProtocolTypes.ObjectData,
        serial: String,
        siteCode: String,
    ) -> ProtocolTypes.InboundObjectMessage {
        inboundObjectMessage(
            operation: objectOperation(
                action: .known(.mapSet),
                objectId: objectId,
                mapSet: ProtocolTypes.MapSet(key: key, value: value),
            ),
            serial: serial,
            siteCode: siteCode,
        )
    }

    /// Creates an InboundObjectMessage with a MAP_REMOVE operation that also carries a
    /// `serialTimestamp` (the base `TestFactories.mapRemoveOperationMessage` does not), needed to
    /// exercise the RTLO6 `tombstonedAt` derivation.
    static func mapRemoveOperationMessage(
        objectId: String,
        key: String,
        serial: String,
        siteCode: String,
        serialTimestamp: Date?,
    ) -> ProtocolTypes.InboundObjectMessage {
        inboundObjectMessage(
            operation: objectOperation(
                action: .known(.mapRemove),
                objectId: objectId,
                mapRemove: WireMapRemove(key: key),
            ),
            serial: serial,
            siteCode: siteCode,
            serialTimestamp: serialTimestamp,
        )
    }
}
