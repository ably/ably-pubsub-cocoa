// Derived from the UTS spec `objects/unit/path_object_subscribe.md`.
//
// Drives `PathObject.subscribe(options:listener:)` path-subscription registration and RTO24 path-event
// dispatch. The spec's `setup_synced_channel` mock-WebSocket fixture has no unit-tier counterpart: the
// standard pool is seeded straight into an `ObjectsPool` (`ObjectsUTS.standardPool`) behind an
// `ObjectsUTSSeededRealtimeObjects`, and the spec's `root` is a `DefaultLiveMapPathObject` over it. Path
// dispatch (RTO24b1) reads each object's RTLO3f `parentReferences`, which the instance-tier seeder does
// not populate, so the fixture derives them from the seeded map entries via
// `ObjectsPool.nosync_rebuildParentReferences()` (and pins any extra objects a case makes reachable).
//
// The spec's `mock_ws.send_to_client(build_object_message(...))` has no mock transport here: the unit
// stand-in (`sendToClient`) applies the inbound operation to the target internal node inside one
// `internalQueue.ably_syncNoDeadlock { }` block (mirroring `InternalLiveCounterApiTests`'s RTLC11
// pattern) and then runs the same post-apply RTO24b path-subscription fan-out the production apply
// pipeline runs (`ObjectsPool.nosync_notifyPathSubscriptions`). Path-event callbacks land on the
// register's `userCallbackQueue` (`.main` for the seeded double), so each `poll_until` drains `.main`
// (never sleeps) before asserting. These are infra-driving stand-ins, not SDK deviations.
//
// Deviations from the UTS spec (recorded in deviations.md):
// - (D-1) RTO24b2c's first listener THROWs; Swift's `@Sendable` `PathObjectSubscriptionCallback` is
//   non-throwing (objects-mapping §8), so a throwing listener is not expressible. Modelled as a benign
//   listener — the case still verifies the second listener is unaffected (the observable behaviour).

import _AblyPluginSupportPrivate
import AblyPubSubDevice
@testable import AblyLiveObjects
@testable import AblyLiveObjectsTesting
import Foundation
import Testing

struct PathObjectSubscribeTests {
    // MARK: - Fixture

    /// The channel name the seeded pool models (the spec's `setup_synced_channel("test")`); surfaces as
    /// the delivered `ObjectMessage.channel` (PAOM2e) at the path-dispatch boundary.
    private static let channelName = "test"

    private struct Fixture {
        let root: DefaultLiveMapPathObject
        let realtimeObjects: ObjectsUTSSeededRealtimeObjects
        let internalQueue: DispatchQueue
        let coreSDK: ObjectsUTSCoreSDK
    }

    /// The unit stand-in for `setup_synced_channel("test")`: seeds the standard pool directly and wraps
    /// it in a `DefaultLiveMapPathObject` root. `extraCounters` pre-seeds additional zero-value counters
    /// (with pinned `parentReferences`) that a case needs reachable for path dispatch — objects the spec
    /// materialises lazily via a `MAP_SET` reference but which the unit tier cannot persist across the
    /// discrete `sendToClient` stand-ins (each reads a fresh pool copy).
    private static func makeFixture(
        channelState: _AblyPluginSupportPrivate.RealtimeChannelState = .attached,
        extraCounters: [(objectID: String, parentReferences: [String: Set<String>])] = [],
    ) -> Fixture {
        let internalQueue = ObjectsUTS.createInternalQueue()
        var pool = ObjectsUTS.standardPool(internalQueue: internalQueue)

        var extraNodes: [(node: InternalDefaultLiveCounter, refs: [String: Set<String>])] = []
        for extra in extraCounters {
            let node = ObjectsUTS.makeCounter(objectID: extra.objectID, data: 0, internalQueue: internalQueue)
            node.testsOnly_setSiteTimeserials(["aaa": StandardTestPool.poolSerial])
            pool.testsOnly_setEntry(.counter(node), forObjectID: extra.objectID)
            extraNodes.append((node, extra.parentReferences))
        }

        // RTO24b1 path dispatch reads each object's RTLO3f parentReferences; the instance-tier seeder
        // leaves them empty, so derive them from the seeded map entries (RTO5c10) on the internal queue.
        internalQueue.ably_syncNoDeadlock {
            pool.nosync_rebuildParentReferences()
        }
        // Pin the extra objects' references off-queue (`testsOnly_setParentReferences` hops the internal
        // queue itself, so it must not be called from within the block above).
        for entry in extraNodes {
            entry.node.testsOnly_setParentReferences(entry.refs)
        }

        let realtimeObjects = ObjectsUTSSeededRealtimeObjects(pool: pool, internalQueue: internalQueue)
        let coreSDK = ObjectsUTSCoreSDK(channelState: channelState)
        let root = DefaultLiveMapPathObject(channelObject: realtimeObjects, coreSDK: coreSDK, internalQueue: internalQueue, segments: [])
        return Fixture(root: root, realtimeObjects: realtimeObjects, internalQueue: internalQueue, coreSDK: coreSDK)
    }

    /// The unit stand-in for `mock_ws.send_to_client(build_object_message(...))`: applies the inbound
    /// operation to its target node and runs the production RTO24b path-subscription fan-out, all on the
    /// internal queue (pool/node access is queue-confined). A referenced object not yet in the pool is
    /// created zero-value (RTO6), matching `nosync_applyObjectProtocolMessageObjectMessage` (RTO9a2a1).
    private static func sendToClient(_ message: ProtocolTypes.InboundObjectMessage, to fixture: Fixture) {
        fixture.internalQueue.ably_syncNoDeadlock {
            guard let operation = message.operation else {
                return
            }
            var pool = fixture.realtimeObjects.nosync_objectsPool
            let entry: ObjectsPool.Entry
            if let existing = pool.entries[operation.objectId] {
                entry = existing
            } else if let created = pool.createZeroValueObject(
                forObjectID: operation.objectId,
                logger: TestLogger(),
                internalQueue: fixture.internalQueue,
                userCallbackQueue: .main,
                clock: MockSimpleClock(),
            ) {
                entry = created
            } else {
                return
            }
            let result = entry.nosync_apply(operation, source: .channel, objectMessage: message, objectsPool: &pool)
            // RTLO4b4c3b -> RTO24b: fan a non-noop update out to path subscriptions (nil = skip).
            guard let changedMapKeys = result.changedMapKeysForPathEvent else {
                return
            }
            pool.nosync_notifyPathSubscriptions(
                objectID: operation.objectId,
                changedMapKeys: changedMapKeys,
                objectMessage: message,
                channelName: Self.channelName,
                register: fixture.realtimeObjects.pathObjectSubscriptionRegister,
            )
        }
    }

    /// The unit stand-in for an OBJECT_SYNC that re-states a counter's value (RTLC6 replaceData). A
    /// sync-originated update carries no source `ObjectMessage` (RTO4b2a), so the path fan-out passes a
    /// nil message and the delivered event's `message` is omitted (RTPO19e2).
    private static func sendSyncCounterState(objectId: String, count: Int, to fixture: Fixture) {
        // Grab the target node on the internal queue (pool access is queue-confined)...
        let node: InternalDefaultLiveCounter? = fixture.internalQueue.ably_syncNoDeadlock {
            if case let .counter(counter) = fixture.realtimeObjects.nosync_objectsPool.entries[objectId] {
                return counter
            }
            return nil
        }
        guard let node else {
            return
        }
        // ...re-state its value off-queue (`testsOnly_setData` hops the internal queue itself)...
        node.testsOnly_setData(Double(count))
        // ...then dispatch the sync-originated path event on the internal queue (no source
        // ObjectMessage, RTO4b2a).
        fixture.internalQueue.ably_syncNoDeadlock {
            fixture.realtimeObjects.nosync_objectsPool.nosync_notifyPathSubscriptions(
                objectID: objectId,
                changedMapKeys: [],
                objectMessage: nil,
                channelName: nil,
                register: fixture.realtimeObjects.pathObjectSubscriptionRegister,
            )
        }
    }

    /// Drains the register's `.main` userCallbackQueue so every already-enqueued path delivery has run
    /// (the `poll_until(...)` stand-in — never a sleep).
    private static func drainMain() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    // MARK: - RTPO19: subscribe() returns Subscription and receives events

    // UTS: objects/unit/RTPO19/subscribe-receives-events-0
    @Test
    func subscribeReturnsSubscriptionAndReceivesEvents() async throws {
        // Setup
        let fixture = Self.makeFixture()
        let events = ObjectsUTSPathEventCollector()
        let sub = try fixture.root.get(key: "score").subscribe(listener: events.listener)

        // Test Steps
        Self.sendToClient(
            ObjectsUTS.counterIncMessage(objectId: "counter:score@1000", number: 7, serial: "99", siteCode: "remote"),
            to: fixture,
        )
        await Self.drainMain() // poll_until(events.length >= 1)

        // Assertions
        // ASSERT sub IS Subscription — statically `any Subscription`, guaranteed by the signature.
        _ = sub
        #expect(events.events.count == 1)
        let event = try #require(events.events.first)
        // ASSERT events[0].object IS PathObject — statically `any PathObject`.
        #expect(event.object.path == "score") // RTPO19e1
        let message = try #require(event.message) // RTPO19e2 — message IS NOT null
        #expect(message.serial == "99")
        #expect(message.siteCode == "remote")
        // ASSERT events[0].message.operation IS NOT null — `operation` is non-optional on ObjectMessage.
        #expect(message.operation.action == .counterInc)
        #expect(message.channel == "test")
    }

    // MARK: - RTPO19b: subscribe() checks RTO25 access preconditions on DETACHED channel

    // UTS: objects/unit/RTPO19b/subscribe-precondition-detached-0
    @Test
    func subscribePreconditionDetachedThrows() throws {
        // Setup — the RTO25b precondition reads the channel state off the core SDK; model DETACHED.
        let fixture = Self.makeFixture(channelState: .detached)

        // Test Steps
        do {
            _ = try fixture.root.subscribe { _ in }
            Issue.record("expected subscribe on a DETACHED channel to throw")
        } catch {
            // Assertions
            #expect(error.code == 90001) // RTO25b
            #expect(error.statusCode == 400) // RTO25b
        }
    }

    // MARK: - RTPO19c1a: subscribe() with non-positive depth throws 40003

    // UTS: objects/unit/RTPO19c1a/subscribe-non-positive-depth-throws-0
    @Test
    func subscribeNonPositiveDepthThrows() throws {
        // Setup
        let fixture = Self.makeFixture()

        // Test Steps
        do {
            _ = try fixture.root.subscribe(options: .init(depth: 0)) { _ in }
            Issue.record("expected subscribe with depth 0 to throw")
        } catch {
            // Assertions
            #expect(error.code == 40003) // RTPO19c1a
        }
    }

    // UTS: objects/unit/RTPO19c1a/subscribe-negative-depth-throws-0
    @Test
    func subscribeNegativeDepthThrows() throws {
        // Setup
        let fixture = Self.makeFixture()

        // Test Steps
        do {
            _ = try fixture.root.subscribe(options: .init(depth: -1)) { _ in }
            Issue.record("expected subscribe with depth -1 to throw")
        } catch {
            // Assertions
            #expect(error.code == 40003) // RTPO19c1a
        }
    }

    // MARK: - RTPO19c1: depth filtering

    // UTS: objects/unit/RTPO19c1/subscribe-depth-1-self-only-0
    @Test
    func subscribeWithDepth1ReceivesSelfOnly() async throws {
        // Setup
        let fixture = Self.makeFixture()
        let events = ObjectsUTSPathEventCollector()
        _ = try fixture.root.subscribe(options: .init(depth: 1), listener: events.listener)
        // Quiescence control: an unlimited-depth root listener that DOES cover the out-of-scope child
        // path, so it fires on the send below and gives us a delivery to await.
        let control = ObjectsUTSPathEventCollector()
        _ = try fixture.root.subscribe(listener: control.listener)

        // Test Steps
        Self.sendToClient(
            ObjectsUTS.mapSetMessage(objectId: "root", key: "name", value: .init(string: "Bob"), serial: StandardTestPool.remoteSerial(0), siteCode: "remote"),
            to: fixture,
        )
        await Self.drainMain() // poll_until(events.length >= 1)

        let controlBefore = control.events.count
        Self.sendToClient(
            ObjectsUTS.counterIncMessage(objectId: "counter:score@1000", number: 7, serial: "100", siteCode: "remote"),
            to: fixture,
        )
        // Negative-assertion quiescence: await the unlimited-depth control's delivery for THIS dispatch,
        // then assert the depth-1 listener did NOT fire on the out-of-scope child update.
        await Self.drainMain() // poll_until(control.length > control_before)
        #expect(control.events.count > controlBefore)

        // Assertions
        #expect(events.events.count == 1)
    }

    // UTS: objects/unit/RTPO19c1/subscribe-depth-2-children-0
    @Test
    func subscribeWithDepth2ReceivesSelfAndChildren() async throws {
        // Setup
        let fixture = Self.makeFixture()
        let events = ObjectsUTSPathEventCollector()
        _ = try fixture.root.subscribe(options: .init(depth: 2), listener: events.listener)
        // Quiescence control: an unlimited-depth root listener that covers the out-of-scope grandchild.
        let control = ObjectsUTSPathEventCollector()
        _ = try fixture.root.subscribe(listener: control.listener)

        // Test Steps
        // Self event (root map update) — candidate [] is covered at depth 2.
        Self.sendToClient(
            ObjectsUTS.mapSetMessage(objectId: "root", key: "name", value: .init(string: "Bob"), serial: StandardTestPool.remoteSerial(0), siteCode: "remote"),
            to: fixture,
        )
        await Self.drainMain() // poll_until(events.length >= 1)

        // Child event (root["score"] counter) — candidate ["score"], relativeDepth 2 <= 2, covered.
        Self.sendToClient(
            ObjectsUTS.counterIncMessage(objectId: "counter:score@1000", number: 7, serial: "100", siteCode: "remote"),
            to: fixture,
        )
        await Self.drainMain() // poll_until(events.length >= 2)

        // Grandchild event (root["profile"]["nested_counter"] counter) — candidate
        // ["profile","nested_counter"], relativeDepth 3 > 2, NOT covered. A COUNTER_INC yields ONLY this
        // single candidate (no key candidate).
        let controlBefore = control.events.count
        Self.sendToClient(
            ObjectsUTS.counterIncMessage(objectId: "counter:nested@1000", number: 1, serial: "101", siteCode: "remote"),
            to: fixture,
        )
        // Negative-assertion quiescence: await the unlimited-depth control's delivery for THIS dispatch,
        // then assert the depth-2 listener did NOT fire on the grandchild update.
        await Self.drainMain() // poll_until(control.length > control_before)
        #expect(control.events.count > controlBefore)

        // Assertions
        #expect(events.events.count == 2)
    }

    // UTS: objects/unit/RTPO19c1/subscribe-unlimited-depth-0
    @Test
    func subscribeWithNoDepthReceivesAllDescendants() async throws {
        // Setup
        let fixture = Self.makeFixture()
        let events = ObjectsUTSPathEventCollector()
        _ = try fixture.root.subscribe(listener: events.listener)

        // Test Steps
        Self.sendToClient(
            ObjectsUTS.mapSetMessage(objectId: "root", key: "name", value: .init(string: "Bob"), serial: StandardTestPool.remoteSerial(0), siteCode: "remote"),
            to: fixture,
        )
        await Self.drainMain() // poll_until(events.length >= 1)

        Self.sendToClient(
            ObjectsUTS.counterIncMessage(objectId: "counter:score@1000", number: 7, serial: "100", siteCode: "remote"),
            to: fixture,
        )
        await Self.drainMain() // poll_until(events.length >= 2)

        Self.sendToClient(
            ObjectsUTS.mapSetMessage(objectId: "map:prefs@1000", key: "theme", value: .init(string: "light"), serial: StandardTestPool.remoteSerial(1), siteCode: "remote"),
            to: fixture,
        )
        await Self.drainMain() // poll_until(events.length >= 3)

        // Assertions
        #expect(events.events.count >= 3)
    }

    // MARK: - RTPO19d: subscribe() returns Subscription with unsubscribe()

    // UTS: objects/unit/RTPO19d/subscribe-returns-subscription-0
    @Test
    func subscribeReturnsSubscriptionWithUnsubscribe() async throws {
        // Setup
        let fixture = Self.makeFixture()
        let events = ObjectsUTSPathEventCollector()
        let sub = try fixture.root.get(key: "score").subscribe(listener: events.listener)
        // Quiescence control: a separate, still-subscribed listener on the same object that WILL fire on
        // the send below, giving a delivery to await.
        let control = ObjectsUTSPathEventCollector()
        _ = try fixture.root.get(key: "score").subscribe(listener: control.listener)

        // Test Steps
        // ASSERT sub IS Subscription — statically `any Subscription`.
        sub.unsubscribe()

        Self.sendToClient(
            ObjectsUTS.counterIncMessage(objectId: "counter:score@1000", number: 7, serial: "99", siteCode: "remote"),
            to: fixture,
        )
        // Negative-assertion quiescence: await the still-subscribed control's delivery for this dispatch,
        // then assert the unsubscribed listener did not fire.
        await Self.drainMain() // poll_until(control.length >= 1)
        #expect(control.events.count >= 1)

        // Assertions
        #expect(events.events.count == 0)
    }

    // MARK: - RTPO19e1: subscribe() event provides correct PathObject

    // UTS: objects/unit/RTPO19e1/event-path-object-correct-0
    @Test
    func subscribeEventProvidesCorrectPathObject() async throws {
        // Setup
        let fixture = Self.makeFixture()
        let events = ObjectsUTSPathEventCollector()
        _ = try fixture.root.subscribe(listener: events.listener)

        // Test Steps
        Self.sendToClient(
            ObjectsUTS.counterIncMessage(objectId: "counter:score@1000", number: 7, serial: "99", siteCode: "remote"),
            to: fixture,
        )
        await Self.drainMain() // poll_until(events.length >= 1)

        // Assertions
        let event = try #require(events.events.first)
        // ASSERT events[0].object IS PathObject — statically `any PathObject`.
        #expect(event.object.path == "score") // RTPO19e1
        #expect(try event.object.asLiveCounter().value() == 107) // 100 + 7
    }

    // MARK: - RTPO19e2: subscribe() event delivers PublicAPI::ObjectMessage for operations

    // UTS: objects/unit/RTPO19e2/event-message-delivery-0
    @Test
    func subscribeEventDeliversObjectMessageForOperations() async throws {
        // Setup
        let fixture = Self.makeFixture()
        let events = ObjectsUTSPathEventCollector()
        _ = try fixture.root.get(key: "score").subscribe(listener: events.listener)

        // Test Steps
        Self.sendToClient(
            ObjectsUTS.counterIncMessage(objectId: "counter:score@1000", number: 42, serial: "serial-1", siteCode: "site-a"),
            to: fixture,
        )
        await Self.drainMain() // poll_until(events.length >= 1)

        // Assertions
        let event = try #require(events.events.first)
        let message = try #require(event.message) // message IS NOT null
        #expect(message.channel == "test")
        #expect(message.serial == "serial-1")
        #expect(message.siteCode == "site-a")
        // ASSERT events[0].message.operation IS NOT null — `operation` is non-optional on ObjectMessage.
        #expect(message.operation.action == .counterInc)
        #expect(message.operation.objectId == "counter:score@1000")
        #expect(message.operation.counterInc?.number == 42)
    }

    // UTS: objects/unit/RTPO19e2/event-message-omitted-no-operation-0
    @Test
    func subscribeEventOmitsMessageWhenNoOperation() async throws {
        // Setup
        let fixture = Self.makeFixture()
        let events = ObjectsUTSPathEventCollector()
        _ = try fixture.root.subscribe(listener: events.listener)

        // Test Steps
        // A sync-triggered update of counter:score@1000 (100 -> 200) via replaceData (RTLC6); its
        // objectMessage has no `operation` field, so the delivered event carries no message (RTO4b2a).
        // Per RTO5c2a root is retained and still references "score", so counter:score stays reachable.
        Self.sendSyncCounterState(objectId: "counter:score@1000", count: 200, to: fixture)
        await Self.drainMain() // poll_until(events.length >= 1)

        // Assertions
        #expect(!events.events.isEmpty)
        // Events from sync-triggered updates should have no message.
        for event in events.events {
            #expect(event.message == nil)
        }
    }

    // MARK: - RTPO19f: subscribe() follows path not identity

    // UTS: objects/unit/RTPO19f/subscribe-follows-path-0
    @Test
    func subscribeFollowsPathNotIdentity() async throws {
        // Setup — pre-seed counter:new@2000 (reachable at ["score"]) so the increment on the NEW object
        // below can dispatch; without it the fixture yields no path for the replacement counter and the
        // second Test Step would be a silent no-op (the MAP_SET event alone would satisfy found_new).
        let fixture = Self.makeFixture(extraCounters: [
            (objectID: "counter:new@2000", parentReferences: ["root": ["score"]]),
        ])
        let events = ObjectsUTSPathEventCollector()
        _ = try fixture.root.get(key: "score").subscribe(listener: events.listener)

        // Test Steps
        // Replace the counter at "score" with a new counter.
        Self.sendToClient(
            ObjectsUTS.mapSetMessage(objectId: "root", key: "score", value: .init(objectId: "counter:new@2000"), serial: StandardTestPool.remoteSerial(0), siteCode: "remote"),
            to: fixture,
        )
        // Increment the NEW counter at "score".
        Self.sendToClient(
            ObjectsUTS.counterIncMessage(objectId: "counter:new@2000", number: 10, serial: "100", siteCode: "remote"),
            to: fixture,
        )
        await Self.drainMain() // poll_until(events.length >= 1)

        // Assertions
        // Should receive event for the new object, since subscription follows path.
        var foundNew = false
        for event in events.events where event.object.path == "score" {
            foundNew = true
        }
        #expect(foundNew)
        // The second dispatch is the increment on the NEW counter — this is what proves the subscription
        // followed the path to the replacement object rather than staying bound to the old identity
        // (the MAP_SET dispatch alone would already satisfy found_new above)
        #expect(events.events.count == 2)
        let incrementEvent = try #require(events.events.last)
        #expect(incrementEvent.object.path == "score")
        #expect(incrementEvent.message?.operation.action == .counterInc)
        #expect(incrementEvent.message?.operation.objectId == "counter:new@2000")
    }

    // MARK: - RTPO19g: subscribe() has no side effects

    // UTS: objects/unit/RTPO19g/subscribe-no-side-effects-0
    @Test
    func subscribeHasNoSideEffects() throws {
        // Setup
        let fixture = Self.makeFixture()
        let stateBefore = fixture.coreSDK.nosync_channelState

        // Test Steps
        _ = try fixture.root.get(key: "score").subscribe { _ in }

        // Assertions
        #expect(fixture.coreSDK.nosync_channelState == stateBefore)
    }

    // MARK: - RTPO19: subscribe() on primitive path receives change events

    // UTS: objects/unit/RTPO19/subscribe-primitive-path-0
    @Test
    func subscribeOnPrimitivePathReceivesChangeEvents() async throws {
        // Setup
        let fixture = Self.makeFixture()
        let events = ObjectsUTSPathEventCollector()
        _ = try fixture.root.get(key: "name").subscribe(listener: events.listener)

        // Test Steps
        Self.sendToClient(
            ObjectsUTS.mapSetMessage(objectId: "root", key: "name", value: .init(string: "Bob"), serial: StandardTestPool.remoteSerial(0), siteCode: "remote"),
            to: fixture,
        )
        await Self.drainMain() // poll_until(events.length >= 1)

        // Assertions
        #expect(events.events.count == 1)
        let event = try #require(events.events.first)
        #expect(event.object.path == "name")
    }

    // MARK: - RTPO19: MAP_CLEAR triggers subscription events on child paths

    // UTS: objects/unit/RTPO19/map-clear-triggers-child-events-0
    @Test
    func mapClearTriggersChildEvents() async throws {
        // Setup
        let fixture = Self.makeFixture()
        let events = ObjectsUTSPathEventCollector()
        _ = try fixture.root.subscribe(listener: events.listener)

        // Test Steps
        Self.sendToClient(
            ObjectsUTS.mapClearMessage(objectId: "root", serial: "99", siteCode: "remote"),
            to: fixture,
        )
        await Self.drainMain() // poll_until(events.length >= 1)

        // Assertions
        #expect(events.events.count >= 1)
    }

    // MARK: - RTPO19: child events bubble up to parent subscription

    // UTS: objects/unit/RTPO19/child-events-bubble-0
    @Test
    func childEventsBubbleUpToParentSubscription() async throws {
        // Setup
        let fixture = Self.makeFixture()
        let events = ObjectsUTSPathEventCollector()
        _ = try fixture.root.get(key: "profile").subscribe(listener: events.listener)

        // Test Steps
        Self.sendToClient(
            ObjectsUTS.mapSetMessage(objectId: "map:profile@1000", key: "email", value: .init(string: "bob@example.com"), serial: StandardTestPool.remoteSerial(0), siteCode: "remote"),
            to: fixture,
        )
        await Self.drainMain() // poll_until(events.length >= 1)

        Self.sendToClient(
            ObjectsUTS.counterIncMessage(objectId: "counter:nested@1000", number: 3, serial: "100", siteCode: "remote"),
            to: fixture,
        )
        await Self.drainMain() // poll_until(events.length >= 2)

        // Assertions
        #expect(events.events.count >= 2)
    }

    // MARK: - RTO24c1: depth filtering formula

    // UTS: objects/unit/RTO24c1/depth-filtering-formula-0
    @Test
    func depthFilteringFormula() async throws {
        // Setup — seed a grandchild counter under profile.prefs (path ["profile","prefs","deep"]) so the
        // grandchild stimulus can be a COUNTER_INC yielding ONLY that single depth-3 candidate.
        let fixture = Self.makeFixture(extraCounters: [
            (objectID: "counter:deep@3000", parentReferences: ["map:prefs@1000": ["deep"]]),
        ])
        // Sent BEFORE subscribing, so it does not fire the listener under test (RTO6 zero-value-creates
        // counter:deep@3000 in the seeded pool).
        Self.sendToClient(
            ObjectsUTS.mapSetMessage(objectId: "map:prefs@1000", key: "deep", value: .init(objectId: "counter:deep@3000"), serial: "50", siteCode: "remote"),
            to: fixture,
        )
        let events = ObjectsUTSPathEventCollector()
        // Subscribe at "profile" with depth 2:
        //   self (profile)          -> ["profile"],                  1 - 1 + 1 = 1 <= 2  yes
        //   child (profile.nested)  -> ["profile","nested_counter"], 2 - 1 + 1 = 2 <= 2  yes
        //   grandchild (prefs.deep) -> ["profile","prefs","deep"],   3 - 1 + 1 = 3 > 2   no
        _ = try fixture.root.get(key: "profile").subscribe(options: .init(depth: 2), listener: events.listener)
        // Quiescence control: an unlimited-depth root listener that covers the out-of-scope grandchild.
        let control = ObjectsUTSPathEventCollector()
        _ = try fixture.root.subscribe(listener: control.listener)

        // Test Steps
        // Self event (profile map update) — first covered candidate is ["profile"].
        Self.sendToClient(
            ObjectsUTS.mapSetMessage(objectId: "map:profile@1000", key: "email", value: .init(string: "bob@example.com"), serial: StandardTestPool.remoteSerial(0), siteCode: "remote"),
            to: fixture,
        )
        await Self.drainMain() // poll_until(events.length >= 1)

        // Child event (nested counter, relativeDepth 2) — covered.
        Self.sendToClient(
            ObjectsUTS.counterIncMessage(objectId: "counter:nested@1000", number: 3, serial: "100", siteCode: "remote"),
            to: fixture,
        )
        await Self.drainMain() // poll_until(events.length >= 2)

        // Grandchild event (counter:deep, relativeDepth 3) — should NOT be received by the depth-2 sub.
        let controlBefore = control.events.count
        Self.sendToClient(
            ObjectsUTS.counterIncMessage(objectId: "counter:deep@3000", number: 1, serial: "101", siteCode: "remote"),
            to: fixture,
        )
        // Negative-assertion quiescence: await the unlimited-depth control's delivery for THIS dispatch,
        // then assert the depth-2 listener did NOT fire on the grandchild.
        await Self.drainMain() // poll_until(control.length > control_before)
        #expect(control.events.count > controlBefore)

        // Assertions
        #expect(events.events.count == 2)
    }

    // MARK: - RTO24c1: prefix mismatch does not trigger subscription

    // UTS: objects/unit/RTO24c1/prefix-mismatch-0
    @Test
    func prefixMismatchDoesNotTrigger() async throws {
        // Setup
        let fixture = Self.makeFixture()
        let profileEvents = ObjectsUTSPathEventCollector()
        _ = try fixture.root.get(key: "profile").subscribe(listener: profileEvents.listener)
        // Control listener at root: fires on both out-of-scope sends below, providing a delivery to
        // await on the same dispatch before asserting profile_events is unchanged.
        let controlEvents = ObjectsUTSPathEventCollector()
        _ = try fixture.root.subscribe(listener: controlEvents.listener)

        // Test Steps
        // Change at "score" — "profile" is not a prefix of "score".
        Self.sendToClient(
            ObjectsUTS.counterIncMessage(objectId: "counter:score@1000", number: 7, serial: "99", siteCode: "remote"),
            to: fixture,
        )
        // Change at "name" — "profile" is not a prefix of "name".
        Self.sendToClient(
            ObjectsUTS.mapSetMessage(objectId: "root", key: "name", value: .init(string: "Bob"), serial: StandardTestPool.remoteSerial(0), siteCode: "remote"),
            to: fixture,
        )
        // QUIESCENCE: await the control listener (fires for both sends) so any profile_events callback
        // would also have run before we assert it is unchanged.
        await Self.drainMain() // poll_until(control_events.length >= 2)
        #expect(controlEvents.events.count >= 2)

        // Assertions
        #expect(profileEvents.events.count == 0)
    }

    // MARK: - RTO24b2a: candidate path construction includes map update keys

    // UTS: objects/unit/RTO24b2a/candidate-paths-map-keys-0
    @Test
    func candidatePathsIncludeMapKeys() async throws {
        // Setup
        let fixture = Self.makeFixture()
        let scoreEvents = ObjectsUTSPathEventCollector()
        let rootEvents = ObjectsUTSPathEventCollector()
        // Subscribe at the child path "score" (pathToThis=[] + key "score" = ["score"]).
        _ = try fixture.root.get(key: "score").subscribe(listener: scoreEvents.listener)
        // Subscribe at root path (pathToThis=[]).
        _ = try fixture.root.subscribe(listener: rootEvents.listener)

        // Test Steps
        // MAP_SET on root with key "score" — candidates [] (root itself) and ["score"] (map update key);
        // both subscriptions should fire.
        Self.sendToClient(
            ObjectsUTS.mapSetMessage(objectId: "root", key: "score", value: .init(objectId: "counter:new@2000"), serial: StandardTestPool.remoteSerial(0), siteCode: "remote"),
            to: fixture,
        )
        await Self.drainMain() // poll_until(score_events.length >= 1 && root_events.length >= 1)

        // Assertions
        #expect(scoreEvents.events.count == 1)
        let scoreEvent = try #require(scoreEvents.events.first)
        #expect(scoreEvent.object.path == "score")
        #expect(rootEvents.events.count == 1)
    }

    // MARK: - RTO24b2c: listener exception does not affect other listeners

    // UTS: objects/unit/RTO24b2c/listener-exception-caught-0
    @Test
    func listenerExceptionDoesNotAffectOthers() async throws {
        // Setup
        let fixture = Self.makeFixture()
        let events = ObjectsUTSPathEventCollector()
        // The spec's first listener THROWs; Swift's `@Sendable` PathObjectSubscriptionCallback is
        // non-throwing (objects-mapping §8, deviations D-1), so a throwing listener is not expressible.
        // Modelled as a benign listener — the case still verifies the second listener is unaffected.
        _ = try fixture.root.subscribe { _ in }
        _ = try fixture.root.subscribe(listener: events.listener)

        // Test Steps
        Self.sendToClient(
            ObjectsUTS.mapSetMessage(objectId: "root", key: "name", value: .init(string: "Bob"), serial: StandardTestPool.remoteSerial(0), siteCode: "remote"),
            to: fixture,
        )
        await Self.drainMain() // poll_until(events.length >= 1)

        // Assertions
        #expect(events.events.count == 1)
    }

    // MARK: - RTO24b1: dispatch via getFullPaths for multi-path objects

    // UTS: objects/unit/RTO24b1/multi-path-dispatch-0
    @Test
    func multiPathDispatchViaGetFullPaths() async throws {
        // Setup
        let fixture = Self.makeFixture()
        let eventsScore = ObjectsUTSPathEventCollector()
        let eventsAlias = ObjectsUTSPathEventCollector()

        // "score" already points to counter:score@1000. Add a second reference "alias" ->
        // counter:score@1000 so it has two paths (the MAP_SET apply registers the second parentReference).
        Self.sendToClient(
            ObjectsUTS.mapSetMessage(objectId: "root", key: "alias", value: .init(objectId: "counter:score@1000"), serial: "98", siteCode: "remote"),
            to: fixture,
        )

        _ = try fixture.root.get(key: "score").subscribe(listener: eventsScore.listener)
        _ = try fixture.root.get(key: "alias").subscribe(listener: eventsAlias.listener)

        // Test Steps
        // Increment counter:score@1000 — getFullPaths returns ["score"] and ["alias"].
        Self.sendToClient(
            ObjectsUTS.counterIncMessage(objectId: "counter:score@1000", number: 5, serial: "99", siteCode: "remote"),
            to: fixture,
        )
        await Self.drainMain() // poll_until(events_score.length >= 1 && events_alias.length >= 1)

        // Assertions
        #expect(eventsScore.events.count == 1)
        let scoreEvent = try #require(eventsScore.events.first)
        #expect(scoreEvent.object.path == "score")
        #expect(eventsAlias.events.count == 1)
        let aliasEvent = try #require(eventsAlias.events.first)
        #expect(aliasEvent.object.path == "alias")
    }

    // MARK: - RTO24b2b: subscription fires exactly once per dispatch

    // UTS: objects/unit/RTO24b2b/fires-once-per-dispatch-0
    @Test
    func subscriptionFiresExactlyOncePerDispatch() async throws {
        // Setup — pre-seed counter:new@2000 (reachable at ["score"]) so the control increment below can
        // dispatch a single-candidate event on it (the spec's second, single-candidate control dispatch).
        let fixture = Self.makeFixture(extraCounters: [
            (objectID: "counter:new@2000", parentReferences: ["root": ["score"]]),
        ])
        let events = ObjectsUTSPathEventCollector()
        // Subscribe at root (unlimited depth) — covers both [] and ["score"].
        _ = try fixture.root.subscribe(listener: events.listener)

        // Test Steps
        // MAP_SET on root with key "score" — candidates [] and ["score"]; the root subscription covers
        // both but should fire exactly once with the first candidate (pathToThis = []).
        Self.sendToClient(
            ObjectsUTS.mapSetMessage(objectId: "root", key: "score", value: .init(objectId: "counter:new@2000"), serial: StandardTestPool.remoteSerial(0), siteCode: "remote"),
            to: fixture,
        )
        await Self.drainMain() // poll_until(events.length >= 1)

        // QUIESCENCE: a second, single-candidate dispatch acts as the control delivery. Awaiting it
        // guarantees any spurious second callback from the first (multi-candidate) dispatch would already
        // have run, so events.length == 2 confirms the first dispatch fired exactly once.
        Self.sendToClient(
            ObjectsUTS.counterIncMessage(objectId: "counter:new@2000", number: 1, serial: "100", siteCode: "remote"),
            to: fixture,
        )
        await Self.drainMain() // poll_until(events.length >= 2)

        // Assertions
        // Exactly one event per dispatch: one from the multi-candidate MAP_SET + one from the increment.
        #expect(events.events.count == 2)
    }
}
