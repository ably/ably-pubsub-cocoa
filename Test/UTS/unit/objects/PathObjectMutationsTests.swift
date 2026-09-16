// Derived from the UTS spec `objects/unit/path_object_mutations.md`.
//
// Drives the `PathObject` write surface (RTPO15 `set`, RTPO16 `remove`, RTPO17 `increment`,
// RTPO18 `decrement`, and the RTPO3c2 unresolvable-path guard) through the path layer. Writes are
// delegated to the backing `InternalLiveMap`/`InternalLiveCounter` node, so each case navigates the
// standard pool seeded directly by `ObjectsUTS.standardPool` (the unit stand-in for the spec's
// `setup_synced_channel`, which would materialise the tree via an OBJECT_SYNC) fronted by a
// `DefaultLiveMapPathObject` root over an `ObjectsUTSSeededRealtimeObjects` double. The seeded double
// captures each published message AND asynchronously applies the operation back onto the pool entry
// (the RTO20 ACK echo, reduced to what the pool can express), so the awaited write happens-after its
// local apply and the post-apply value reads (`value() == "Bob"` / `== 125` / `== null`) are directly
// portable.
//
// Wrong-type writes go THROUGH the cast (objects-mapping §7): the typed views have only their own
// write methods, so a wrong-kind write (`set` on a counter, `increment` on a map) is expressed by
// casting to the view whose method is needed (`asLiveMap()`/`asLiveCounter()` never throw, RTTS5d)
// and asserting the OPERATION throws 92007 (RTPO15e/RTPO16e/RTPO17e/RTPO18e). Unresolvable-path
// writes throw 92005 with statusCode 400 (RTPO3c2). Both are runtime assertions, not omissions.
//
// The mock-WebSocket infrastructure the spec declares (`MockWebSocket`, `setup_synced_channel`) has no
// unit-tier counterpart — direct seeding + the publishAndApply capture/echo seam stand in for it. That
// is an infra-driving choice, NOT a deviation. There are no genuine SDK deviations in this suite.

import AblyPubSubDevice
@testable import AblyLiveObjects
@testable import AblyLiveObjectsTesting
import Foundation
import Testing

struct PathObjectMutationsTests {
    // MARK: - Fixture

    private typealias Fixture = (root: DefaultLiveMapPathObject, realtimeObjects: ObjectsUTSSeededRealtimeObjects)

    /// The unit stand-in for `{ client, channel, root, mock_ws } = AWAIT setup_synced_channel("test")`:
    /// seed the standard pool directly, expose it through a seeded realtime-objects double, then front
    /// it with the root map path object (the spec's `root`).
    private static func makeFixture() -> Fixture {
        let internalQueue = ObjectsUTS.createInternalQueue()
        let pool = ObjectsUTS.standardPool(internalQueue: internalQueue)
        let realtimeObjects = ObjectsUTSSeededRealtimeObjects(pool: pool, internalQueue: internalQueue)
        let coreSDK = ObjectsUTSCoreSDK()
        let root = DefaultLiveMapPathObject(channelObject: realtimeObjects, coreSDK: coreSDK, internalQueue: internalQueue, segments: [])
        return (root, realtimeObjects)
    }

    // MARK: - RTPO15: set() delegates to InternalLiveMap#set

    // UTS: objects/unit/RTPO15/set-delegates-to-map-0
    @Test
    func setDelegatesToMapSet() async throws {
        // Setup
        let root = Self.makeFixture().root

        // Test Steps
        // AWAIT root.set("name", "Bob")
        try await root.set(key: "name", value: "Bob")

        // Assertions
        // ASSERT root.get("name").value() == "Bob"
        #expect(try root.get(key: "name").asPrimitive().value() == .string("Bob"))
    }

    // UTS: objects/unit/RTPO15/set-nested-path-0
    @Test
    func setOnNestedPath() async throws {
        // Setup
        let root = Self.makeFixture().root

        // Test Steps
        // AWAIT root.get("profile").set("email", "bob@example.com")
        try await root.get(key: "profile").asLiveMap().set(key: "email", value: "bob@example.com")

        // Assertions
        // ASSERT root.get("profile").get("email").value() == "bob@example.com"
        #expect(try root.get(key: "profile").asLiveMap().get(key: "email").asPrimitive().value() == .string("bob@example.com"))
    }

    // UTS: objects/unit/RTPO15d/set-non-map-throws-0
    @Test
    func setOnNonMapThrows92007() async throws {
        // Setup
        let root = Self.makeFixture().root

        // Test Steps + Assertions
        // AWAIT root.get("score").set("key", "value") FAILS WITH error
        // `score` resolves to a counter; the wrong-type write goes THROUGH the (never-throwing)
        // asLiveMap() cast and the set operation throws 92007 (RTPO15e).
        do {
            try await root.get(key: "score").asLiveMap().set(key: "key", value: "value")
            Issue.record("expected set() on a non-map to throw 92007")
        } catch {
            // ASSERT error.code == 92007 (typed throws: `error` is already an ErrorInfo)
            #expect(error.code == 92007)
        }
    }

    // MARK: - RTPO16: remove() delegates to InternalLiveMap#remove

    // UTS: objects/unit/RTPO16/remove-delegates-to-map-0
    @Test
    func removeDelegatesToMapRemove() async throws {
        // Setup
        let root = Self.makeFixture().root

        // Test Steps
        // AWAIT root.remove("name")
        try await root.remove(key: "name")

        // Assertions
        // ASSERT root.get("name").value() == null
        #expect(try root.get(key: "name").asPrimitive().value() == nil)
    }

    // UTS: objects/unit/RTPO16d/remove-non-map-throws-0
    @Test
    func removeOnNonMapThrows92007() async throws {
        // Setup
        let root = Self.makeFixture().root

        // Test Steps + Assertions
        // AWAIT root.get("score").remove("key") FAILS WITH error
        // `score` is a counter; the wrong-type remove goes through asLiveMap() and throws 92007 (RTPO16e).
        do {
            try await root.get(key: "score").asLiveMap().remove(key: "key")
            Issue.record("expected remove() on a non-map to throw 92007")
        } catch {
            // ASSERT error.code == 92007
            #expect(error.code == 92007)
        }
    }

    // MARK: - RTPO17: increment() delegates to InternalLiveCounter#increment

    // UTS: objects/unit/RTPO17/increment-delegates-to-counter-0
    @Test
    func incrementDelegatesToCounter() async throws {
        // Setup
        let root = Self.makeFixture().root

        // Test Steps
        // AWAIT root.get("score").increment(25)
        try await root.get(key: "score").asLiveCounter().increment(amount: 25)

        // Assertions
        // ASSERT root.get("score").value() == 125 (100 + 25, via the ACK echo)
        #expect(try root.get(key: "score").asLiveCounter().value() == 125)
    }

    // UTS: objects/unit/RTPO17/increment-default-amount-0
    @Test
    func incrementDefaultsToOne() async throws {
        // Setup
        let root = Self.makeFixture().root

        // Test Steps
        // AWAIT root.get("score").increment()   # RTPO17a1 — amount defaults to 1
        try await root.get(key: "score").asLiveCounter().increment()

        // Assertions
        // ASSERT root.get("score").value() == 101 (100 + 1)
        #expect(try root.get(key: "score").asLiveCounter().value() == 101)
    }

    // UTS: objects/unit/RTPO17d/increment-non-counter-throws-0
    @Test
    func incrementOnNonCounterThrows92007() async throws {
        // Setup
        let root = Self.makeFixture().root

        // Test Steps + Assertions
        // AWAIT root.increment(5) FAILS WITH error
        // `root` is a map; increment goes THROUGH the never-throwing asLiveCounter() cast and the
        // operation throws 92007 (RTPO17e).
        do {
            try await root.asLiveCounter().increment(amount: 5)
            Issue.record("expected increment() on a non-counter to throw 92007")
        } catch {
            // ASSERT error.code == 92007
            #expect(error.code == 92007)
        }
    }

    // MARK: - RTPO18: decrement() delegates to InternalLiveCounter#decrement

    // UTS: objects/unit/RTPO18/decrement-delegates-to-counter-0
    @Test
    func decrementDelegatesToCounter() async throws {
        // Setup
        let root = Self.makeFixture().root

        // Test Steps
        // AWAIT root.get("score").decrement(10)
        try await root.get(key: "score").asLiveCounter().decrement(amount: 10)

        // Assertions
        // ASSERT root.get("score").value() == 90 (100 - 10, via the ACK echo)
        #expect(try root.get(key: "score").asLiveCounter().value() == 90)
    }

    // UTS: objects/unit/RTPO18/decrement-default-amount-0
    @Test
    func decrementDefaultsToOne() async throws {
        // Setup
        let root = Self.makeFixture().root

        // Test Steps
        // AWAIT root.get("score").decrement()   # RTPO18a1 — amount defaults to 1
        try await root.get(key: "score").asLiveCounter().decrement()

        // Assertions
        // ASSERT root.get("score").value() == 99 (100 - 1)
        #expect(try root.get(key: "score").asLiveCounter().value() == 99)
    }

    // UTS: objects/unit/RTPO18d/decrement-non-counter-throws-0
    @Test
    func decrementOnNonCounterThrows92007() async throws {
        // Setup
        let root = Self.makeFixture().root

        // Test Steps + Assertions
        // AWAIT root.decrement(5) FAILS WITH error
        // `root` is a map; decrement goes through asLiveCounter() and the operation throws 92007 (RTPO18e).
        do {
            try await root.asLiveCounter().decrement(amount: 5)
            Issue.record("expected decrement() on a non-counter to throw 92007")
        } catch {
            // ASSERT error.code == 92007
            #expect(error.code == 92007)
        }
    }

    // MARK: - RTPO3c2: write operations on an unresolvable path throw 92005

    // UTS: objects/unit/RTPO3c2/set-unresolvable-throws-0
    @Test
    func setOnUnresolvablePathThrows92005() async throws {
        // Setup
        let root = Self.makeFixture().root

        // Test Steps + Assertions
        // AWAIT root.get("nonexistent").get("deep").set("key", "value") FAILS WITH error
        // `nonexistent` does not resolve, so the write path is unresolvable and set throws 92005 (RTPO3c2).
        do {
            try await root.get(key: "nonexistent").asLiveMap().get(key: "deep").asLiveMap().set(key: "key", value: "value")
            Issue.record("expected set() on an unresolvable path to throw 92005")
        } catch {
            // ASSERT error.code == 92005
            #expect(error.code == 92005)
            // ASSERT error.statusCode == 400
            #expect(error.statusCode == 400)
        }
    }

    // UTS: objects/unit/RTPO3c2/increment-unresolvable-throws-0
    @Test
    func incrementOnUnresolvablePathThrows92005() async throws {
        // Setup
        let root = Self.makeFixture().root

        // Test Steps + Assertions
        // AWAIT root.get("nonexistent").increment(5) FAILS WITH error
        // `nonexistent` does not resolve, so the counter write path is unresolvable and increment
        // throws 92005 (RTPO3c2).
        do {
            try await root.get(key: "nonexistent").asLiveCounter().increment(amount: 5)
            Issue.record("expected increment() on an unresolvable path to throw 92005")
        } catch {
            // ASSERT error.code == 92005
            #expect(error.code == 92005)
            // ASSERT error.statusCode == 400
            #expect(error.statusCode == 400)
        }
    }
}
