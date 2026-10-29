// Derived from the UTS spec `objects/unit/value_types.md`.
//
// Drives the public `LiveCounter.create` / `LiveMap.create` value-type blueprints (RTLCV/RTLMV) and
// their evaluation into outbound `*_CREATE` `ObjectMessage`s. Construction is pure struct-building;
// evaluation goes through the harness's synchronous `ObjectsUTS.evaluate(counter:)` /
// `evaluate(map:internalQueue:)` (the unit stand-in for the spec's `evaluate(vt)`), which drive the
// production `ObjectCreationHelpers` composition builders with the fixed `ObjectsUTS.evaluationTimestamp`
// in place of a live per-object server time. The runtime-expressible RTLCV4a validation (a non-finite
// count) is asserted against the real production `ObjectCreationHelpers.evaluate(liveCounter:...)`,
// which performs the RTLCV4a finiteness check. There is no channel/connection/mock-WebSocket — a
// blueprint is evaluated directly. These infra stand-ins are NOT deviations.
//
// Deviations from the UTS spec (recorded in deviations.md):
// - (S-shape) The spec's outbound message carries `operation.counterCreate` / `operation.mapCreate`
//   with the retained local create (RTLCV4g5 / RTLMV4j5). cocoa's `ProtocolTypes.OutboundObjectMessage`
//   instead exposes `counterCreateWithObjectId` / `mapCreateWithObjectId` (the wire `initialValue` +
//   `nonce`), and the retained `WireCounterCreate` / `MapCreate` lives on that variant's `derivedFrom`
//   field — so every spec assertion on `operation.counterCreate.*` / `operation.mapCreate.*` maps to
//   `operation.<x>CreateWithObjectId.derivedFrom.*`.
// - (D-typed) The wrong-typed-input validation cases (RTLCV4a's `"not_a_number"`, RTLMV4a's `null`,
//   RTLMV4b's non-string key, RTLMV4c's function value) are compile-time-blocked by the typed
//   `create(initialCount: Double)` / `create(entries: [String: LiveMapValue])` signatures
//   (objects-mapping §6), so the invalid input cannot be constructed. The spec pseudocode is retained
//   as comments; only the runtime-expressible subset (RTLCV4a's non-finite `Double`) is a real assertion.

import AblyPubSubDevice
@testable import AblyLiveObjects
import Foundation
import Testing

struct ValueTypesTests {
    // MARK: - LiveCounter.create (RTLCV)

    // UTS: objects/unit/RTLCV3/create-with-count-0
    @Test
    func createCounterWithInitialCount() throws {
        // Test Steps
        // vt = LiveCounter.create(42)
        let vt = LiveCounter.create(initialCount: 42)

        // Assertions
        // ASSERT vt IS LiveCounter — statically guaranteed: `create` returns `LiveCounter` (RTLCV3b/RTLCV3d).
        // ASSERT vt.count == 42
        #expect(vt.count == 42)
    }

    // UTS: objects/unit/RTLCV3/create-default-zero-0
    @Test
    func createCounterDefaultsToZero() throws {
        // Test Steps
        // vt = LiveCounter.create()
        let vt = LiveCounter.create()

        // Assertions
        // ASSERT vt.count == 0
        #expect(vt.count == 0)
    }

    // UTS: objects/unit/RTLCV3c/no-validation-at-create-0
    @Test
    func createCounterPerformsNoValidation() throws {
        // Test Steps
        // vt = LiveCounter.create("not_a_number")
        // A non-number is compile-time-blocked by `create(initialCount: Double)` (D-typed). The
        // runtime-expressible facet of RTLCV3c — creation performs no validation, so even a value the
        // evaluator would later reject (a non-finite Double) is accepted without throwing — is asserted
        // here; the validation itself is deferred to evaluation (RTLCV4a, below).
        let vt = LiveCounter.create(initialCount: .nan)

        // Assertions
        // ASSERT vt IS LiveCounter  // does not throw
        #expect(vt.count.isNaN)
    }

    // UTS: objects/unit/RTLCV4/evaluate-generates-message-0
    @Test
    func evaluateCounterGeneratesCounterCreateMessage() throws {
        // Test Steps
        // vt = LiveCounter.create(42); messages = evaluate(vt)
        let vt = LiveCounter.create(initialCount: 42)
        let messages = ObjectsUTS.evaluate(counter: vt)

        // Assertions
        // ASSERT messages.length == 1
        #expect(messages.count == 1)
        let operation = try #require(messages[0].operation)
        // ASSERT msg.operation.action == "COUNTER_CREATE" (RTLCV4g1)
        #expect(operation.action == .known(.counterCreate))
        // ASSERT msg.operation.objectId STARTS WITH "counter:" / CONTAINS "@" (RTLCV4f/RTLCV4g2, RTO14)
        #expect(operation.objectId.hasPrefix("counter:"))
        #expect(operation.objectId.contains("@"))
        // ASSERT msg.operation.counterCreateWithObjectId IS NOT null (RTLCV4g3/RTLCV4g4)
        let withObjectId = try #require(operation.counterCreateWithObjectId)
        // ASSERT counterCreateWithObjectId.nonce IS NOT null / length >= 16 (RTLCV4d/RTLCV4g3)
        // `nonce` is a non-optional String in cocoa, so "IS NOT null" is structural.
        #expect(withObjectId.nonce.count >= 16)
        // ASSERT counterCreateWithObjectId.initialValue IS NOT null (RTLCV4c/RTLCV4g4)
        #expect(!withObjectId.initialValue.isEmpty)
    }

    // UTS: objects/unit/RTLCV4g5/retains-local-counter-create-0
    @Test
    func evaluateCounterRetainsLocalCounterCreate() throws {
        // Test Steps
        // vt = LiveCounter.create(42); messages = evaluate(vt)
        let vt = LiveCounter.create(initialCount: 42)
        let messages = ObjectsUTS.evaluate(counter: vt)

        // Assertions
        // ASSERT msg.operation.counterCreate IS NOT null / .count == 42 (RTLCV4g5)
        // (S-shape) cocoa retains the local `WireCounterCreate` on `counterCreateWithObjectId.derivedFrom`,
        // not on a top-level `operation.counterCreate`.
        let derivedFrom = try #require(messages[0].operation?.counterCreateWithObjectId?.derivedFrom)
        #expect(derivedFrom.count == 42)
    }

    // UTS: objects/unit/RTLCV4a/evaluate-validates-count-0
    @Test
    func evaluateCounterValidatesCountType() async throws {
        // Test Steps
        // vt = LiveCounter.create("not_a_number"); evaluate(vt) FAILS WITH error
        // The `"not_a_number"` input is compile-time-blocked by `create(initialCount: Double)` (D-typed).
        // RTLCV4a rejects "not a Number OR not finite" with 40003; the runtime-expressible half — a
        // non-finite Double — is asserted here against the production evaluate, which performs the
        // RTLCV4a finiteness check (the harness's synchronous `evaluate(counter:)` skips it).
        let internalQueue = ObjectsUTS.createInternalQueue()
        let coreSDK = ObjectsUTSCoreSDK()
        let vt = LiveCounter.create(initialCount: .infinity)

        // Assertions
        // ASSERT error.code == 40003
        do {
            _ = try await ObjectCreationHelpers.evaluate(liveCounter: vt, coreSDK: coreSDK, internalQueue: internalQueue)
            Issue.record("expected evaluation of a non-finite count to throw")
        } catch {
            #expect(error.code == 40003)
        }
    }

    // UTS: objects/unit/RTLCV4/evaluate-zero-count-0
    @Test
    func evaluateCounterWithZeroCount() throws {
        // Test Steps
        // vt = LiveCounter.create(0); messages = evaluate(vt)
        let vt = LiveCounter.create(initialCount: 0)
        let messages = ObjectsUTS.evaluate(counter: vt)

        // Assertions
        // ASSERT msg.operation.counterCreate.count == 0
        // (S-shape) retained create lives on `counterCreateWithObjectId.derivedFrom`.
        let derivedFrom = try #require(messages[0].operation?.counterCreateWithObjectId?.derivedFrom)
        #expect(derivedFrom.count == 0)
    }

    // MARK: - LiveMap.create (RTLMV)

    // UTS: objects/unit/RTLMV3/create-with-entries-0
    @Test
    func createMapWithEntries() throws {
        // Test Steps
        // vt = LiveMap.create({ "name": "Alice", "age": 30 })
        let vt = LiveMap.create(entries: [
            "name": "Alice",
            "age": 30,
        ])

        // Assertions
        // ASSERT vt IS LiveMap — statically guaranteed: `create` returns `LiveMap` (RTLMV3b/RTLMV3d).
        // ASSERT vt.entries["name"] == "Alice" / vt.entries["age"] == 30
        #expect(vt.entries?["name"] == "Alice")
        #expect(vt.entries?["age"] == 30)
    }

    // UTS: objects/unit/RTLMV3/create-no-entries-0
    @Test
    func createMapWithNoEntries() throws {
        // Test Steps
        // vt = LiveMap.create()
        let vt = LiveMap.create()

        // Assertions
        // ASSERT vt IS LiveMap — statically guaranteed; internal entries is undefined (RTLMV3a1).
        #expect(vt.entries == nil)
    }

    // UTS: objects/unit/RTLMV4/evaluate-generates-message-0
    @Test
    func evaluateMapGeneratesMapCreateMessage() throws {
        // Setup
        let internalQueue = ObjectsUTS.createInternalQueue()

        // Test Steps
        // vt = LiveMap.create({ "name": "Alice" }); messages = evaluate(vt)
        let vt = LiveMap.create(entries: ["name": "Alice"])
        let messages = ObjectsUTS.evaluate(map: vt, internalQueue: internalQueue)

        // Assertions
        // ASSERT messages.length == 1
        #expect(messages.count == 1)
        let operation = try #require(messages[0].operation)
        // ASSERT msg.operation.action == "MAP_CREATE" (RTLMV4j1)
        #expect(operation.action == .known(.mapCreate))
        // ASSERT msg.operation.objectId STARTS WITH "map:" (RTLMV4i, RTO14)
        #expect(operation.objectId.hasPrefix("map:"))
        // ASSERT msg.operation.mapCreateWithObjectId IS NOT null (RTLMV4j3/RTLMV4j4)
        let withObjectId = try #require(operation.mapCreateWithObjectId)
        // ASSERT mapCreateWithObjectId.nonce.length >= 16 (RTLMV4g/RTLMV4j3) — `nonce` is non-optional.
        #expect(withObjectId.nonce.count >= 16)
        // ASSERT mapCreateWithObjectId.initialValue IS NOT null (RTLMV4f/RTLMV4j4)
        #expect(!withObjectId.initialValue.isEmpty)
    }

    // UTS: objects/unit/RTLMV4j5/retains-local-map-create-0
    @Test
    func evaluateMapRetainsLocalMapCreate() throws {
        // Setup
        let internalQueue = ObjectsUTS.createInternalQueue()

        // Test Steps
        // vt = LiveMap.create({ "name": "Alice" }); messages = evaluate(vt)
        let vt = LiveMap.create(entries: ["name": "Alice"])
        let messages = ObjectsUTS.evaluate(map: vt, internalQueue: internalQueue)

        // Assertions
        // ASSERT msg.operation.mapCreate IS NOT null / .semantics == "LWW" /
        //        .entries["name"].data.string == "Alice" (RTLMV4j5, RTLMV4e1)
        // (S-shape) cocoa retains the local `MapCreate` on `mapCreateWithObjectId.derivedFrom`.
        let derivedFrom = try #require(messages[0].operation?.mapCreateWithObjectId?.derivedFrom)
        #expect(derivedFrom.semantics == .known(.lww))
        #expect(derivedFrom.entries?["name"]?.data?.string == "Alice")
    }

    // UTS: objects/unit/RTLMV4d/entry-value-types-0
    @Test
    func evaluateMapEntryValueTypeMapping() throws {
        // Setup
        let internalQueue = ObjectsUTS.createInternalQueue()

        // Test Steps
        // vt = LiveMap.create({ str, num, bool, json_arr, json_obj }); messages = evaluate(vt)
        let vt = LiveMap.create(entries: [
            "str": "hello",
            "num": 42,
            "bool": true,
            "json_arr": [1, 2, 3],
            "json_obj": ["key": "value"],
        ])
        let messages = ObjectsUTS.evaluate(map: vt, internalQueue: internalQueue)

        // Assertions
        // (S-shape) entries live on `mapCreateWithObjectId.derivedFrom.entries`.
        let entries = try #require(messages[0].operation?.mapCreateWithObjectId?.derivedFrom?.entries)
        // ASSERT entries["str"].data.string == "hello" (RTLMV4d4)
        #expect(entries["str"]?.data?.string == "hello")
        // ASSERT entries["num"].data.number == 42 (RTLMV4d5)
        #expect(entries["num"]?.data?.number == 42)
        // ASSERT entries["bool"].data.boolean == true (RTLMV4d6)
        #expect(entries["bool"]?.data?.boolean == true)
        // ASSERT entries["json_arr"].data.json == [1, 2, 3] (RTLMV4d3)
        #expect(entries["json_arr"]?.data?.json == .array([1, 2, 3]))
        // ASSERT entries["json_obj"].data.json == { "key": "value" } (RTLMV4d3)
        #expect(entries["json_obj"]?.data?.json == .object(["key": "value"]))
    }

    // UTS: objects/unit/RTLMV4d1/nested-value-types-0
    @Test
    func evaluateNestedValueTypesDepthFirst() throws {
        // Setup
        let internalQueue = ObjectsUTS.createInternalQueue()

        // Test Steps
        // inner_counter = LiveCounter.create(10)
        // inner_map = LiveMap.create({ "nested_count": inner_counter })
        // outer = LiveMap.create({ "child": inner_map })
        // messages = evaluate(outer)
        let outer = LiveMap.create(entries: [
            "child": .liveMap(.create(entries: [
                "nested_count": .liveCounter(.create(initialCount: 10)),
            ])),
        ])
        let messages = ObjectsUTS.evaluate(map: outer, internalQueue: internalQueue)

        // Assertions
        // ASSERT messages.length == 3 (RTLMV4k depth-first: inner creates before outer)
        #expect(messages.count == 3)
        // ASSERT messages[0].operation.action == "COUNTER_CREATE" / objectId STARTS WITH "counter:" (RTLMV4d1)
        #expect(messages[0].operation?.action == .known(.counterCreate))
        #expect(messages[0].operation?.objectId.hasPrefix("counter:") == true)
        // ASSERT messages[1].operation.action == "MAP_CREATE" / objectId STARTS WITH "map:" (RTLMV4d2)
        #expect(messages[1].operation?.action == .known(.mapCreate))
        #expect(messages[1].operation?.objectId.hasPrefix("map:") == true)
        // ASSERT messages[2].operation.action == "MAP_CREATE" / objectId STARTS WITH "map:"
        #expect(messages[2].operation?.action == .known(.mapCreate))
        #expect(messages[2].operation?.objectId.hasPrefix("map:") == true)

        let innerCounterId = try #require(messages[0].operation?.objectId)
        let innerMapId = try #require(messages[1].operation?.objectId)

        // ASSERT messages[1].operation.mapCreate.entries["nested_count"].data.objectId == inner_counter_id
        // ASSERT messages[2].operation.mapCreate.entries["child"].data.objectId == inner_map_id
        // (S-shape) entries live on `mapCreateWithObjectId.derivedFrom.entries`.
        let innerMapEntries = try #require(messages[1].operation?.mapCreateWithObjectId?.derivedFrom?.entries)
        #expect(innerMapEntries["nested_count"]?.data?.objectId == innerCounterId)
        let outerMapEntries = try #require(messages[2].operation?.mapCreateWithObjectId?.derivedFrom?.entries)
        #expect(outerMapEntries["child"]?.data?.objectId == innerMapId)
    }

    // UTS: objects/unit/RTLMV4a/evaluate-validates-entries-0
    @Test
    func evaluateMapValidatesEntriesType() throws {
        // Test Steps
        // vt = LiveMap.create(null); evaluate(vt) FAILS WITH error
        // Assertions
        // ASSERT error.code == 40003
        //
        // (D-typed) NOT EXPRESSIBLE. `LiveMap.create(entries: [String: LiveMapValue])` cannot take
        // `null`; the only "no entries" form is `LiveMap.create()`, which is a *valid* empty map
        // (RTLMV4e2, below), not a 40003 error. There is no runtime-expressible facet of RTLMV4a's
        // "entries is null / not a Dict" rejection — the type system forbids constructing the invalid
        // input entirely (objects-mapping §6). Retained as a documented omission per the translation
        // gate; no runtime assertion is possible.
    }

    // UTS: objects/unit/RTLMV4b/evaluate-validates-keys-0
    @Test
    func evaluateMapValidatesKeyTypes() throws {
        // Test Steps
        // vt = LiveMap.create({ 123: "value" }); evaluate(vt) FAILS WITH error
        // Assertions
        // ASSERT error.code == 40003
        //
        // (D-typed) NOT EXPRESSIBLE. Map keys in `create(entries: [String: LiveMapValue])` are `String`
        // by type, so a non-string key cannot be constructed (objects-mapping §6). The spec itself marks
        // this case non-applicable in languages where map keys are always strings. Retained as a
        // documented omission per the translation gate; no runtime assertion is possible.
    }

    // UTS: objects/unit/RTLMV4c/evaluate-validates-values-0
    @Test
    func evaluateMapValidatesValueTypes() throws {
        // Test Steps
        // vt = LiveMap.create({ "fn": some_function }); evaluate(vt) FAILS WITH error
        // Assertions
        // ASSERT error.code == 40013
        //
        // (D-typed) NOT EXPRESSIBLE. Entry values are the closed `LiveMapValue` enum, so an
        // unsupported value (a function, a live graph object) cannot be constructed (objects-mapping §6);
        // every constructible value is an "expected type", so the 40013 rejection path is unreachable.
        // Retained as a documented omission per the translation gate; no runtime assertion is possible.
    }

    // UTS: objects/unit/RTLMV4e2/empty-entries-0
    @Test
    func evaluateMapWithNoEntriesProducesEmptyEntries() throws {
        // Setup
        let internalQueue = ObjectsUTS.createInternalQueue()

        // Test Steps
        // vt = LiveMap.create(); messages = evaluate(vt)
        let vt = LiveMap.create()
        let messages = ObjectsUTS.evaluate(map: vt, internalQueue: internalQueue)

        // Assertions
        // ASSERT msg.operation.mapCreate.entries == {} (RTLMV4e2)
        // (S-shape) retained create lives on `mapCreateWithObjectId.derivedFrom`.
        let derivedFrom = try #require(messages[0].operation?.mapCreateWithObjectId?.derivedFrom)
        #expect(derivedFrom.entries == [:])
    }

    // UTS: objects/unit/RTLMV4d/map-set-all-types-table-0
    @Test
    func evaluateMapAllValueTypesTable() throws {
        // Setup
        let internalQueue = ObjectsUTS.createInternalQueue()

        // Evaluates a single-entry map and returns the entry's ObjectData (the spec's per-scenario
        // `messages[0].operation.mapCreate.entries["test_key"]`, S-shape: `derivedFrom.entries`).
        func dataField(for value: LiveMapValue) throws -> ProtocolTypes.ObjectData {
            let messages = ObjectsUTS.evaluate(map: .create(entries: ["test_key": value]), internalQueue: internalQueue)
            let entries = try #require(messages[0].operation?.mapCreateWithObjectId?.derivedFrom?.entries)
            return try #require(entries["test_key"]?.data)
        }

        // Test Steps + Assertions
        // FOR scenario IN type_scenarios: evaluate({ "test_key": input }); ASSERT entry.data[field] == value
        // { input: "hello", expected_field: "string", expected_value: "hello" }
        #expect(try dataField(for: "hello").string == "hello")
        // { input: 42, expected_field: "number", expected_value: 42 }
        #expect(try dataField(for: 42).number == 42)
        // { input: 3.14, expected_field: "number", expected_value: 3.14 }
        #expect(try dataField(for: 3.14).number == 3.14)
        // { input: 0, expected_field: "number", expected_value: 0 }
        #expect(try dataField(for: 0).number == 0)
        // { input: -1, expected_field: "number", expected_value: -1 }
        #expect(try dataField(for: -1).number == -1)
        // { input: true, expected_field: "boolean", expected_value: true }
        #expect(try dataField(for: true).boolean == true)
        // { input: false, expected_field: "boolean", expected_value: false }
        #expect(try dataField(for: false).boolean == false)
        // { input: [1, "a", null], expected_field: "json", expected_value: [1, "a", null] }
        #expect(try dataField(for: [1, "a", .null]).json == .array([1, "a", .null]))
        // { input: { "k": "v" }, expected_field: "json", expected_value: { "k": "v" } }
        #expect(try dataField(for: ["k": "v"]).json == .object(["k": "v"]))
        // { input: bytes([1, 2, 3]), expected_field: "bytes", expected_value: "AQID" }
        // cocoa stores raw `Data`, not the spec's base64 string "AQID"; compare the raw bytes.
        #expect(try dataField(for: .primitive(.data(Data([1, 2, 3])))).bytes == Data([1, 2, 3]))
    }
}
