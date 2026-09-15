import _AblyPluginSupportPrivate
@testable import AblyLiveObjects
@testable import AblyLiveObjectsTesting
import AblyPubSubDevice
import Foundation
import Testing

/// Smoke tests for the test-access seams: gated-apply return values, the `testsOnly_` setters, the
/// sync-state read seam, and the apply-object-messages / `isEntryTombstoned` wrappers.
///
/// Each test proves the seam compiles and round-trips (set → get); the seams' production
/// behaviour is exercised in depth by the neighbouring test suites.
struct TestsOnlySeamsTests {
    // MARK: - Gated apply returns the emitted update

    struct GatedApplyReturnsUpdateTests {
        // Counter: rejected apply returns nil, accepted apply returns non-nil.
        @Test
        func counterApplyReturnsUpdateOrNil() {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let counter = InternalDefaultLiveCounter.createZeroValued(objectID: "counter:1@1", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
            // Seed the gate so that a lower serial is rejected.
            counter.testsOnly_setSiteTimeserials(["site1": "ts2"])
            var pool = ObjectsPool(logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())

            let operation = TestFactories.objectOperation(
                action: .known(.counterInc),
                counterInc: TestFactories.counterInc(number: 10),
            )

            // RTLO4a: serial "ts1" < existing "ts2" so the gate rejects → nil.
            let rejected = internalQueue.ably_syncNoDeadlock {
                counter.nosync_apply(
                    operation,
                    source: .channel,
                    objectMessage: TestFactories.inboundObjectMessage(serial: "ts1", siteCode: "site1"),
                    objectsPool: &pool,
                )
            }
            #expect(rejected == nil)

            // serial "ts3" > existing "ts2" so the gate accepts → non-nil update.
            let accepted = internalQueue.ably_syncNoDeadlock {
                counter.nosync_apply(
                    operation,
                    source: .channel,
                    objectMessage: TestFactories.inboundObjectMessage(serial: "ts3", siteCode: "site1"),
                    objectsPool: &pool,
                )
            }
            #expect(accepted != nil)
        }

        // Map: rejected apply returns nil, accepted apply returns non-nil.
        @Test
        func mapApplyReturnsUpdateOrNil() {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let map = InternalDefaultLiveMap.createZeroValued(objectID: "map:1@1", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
            // Seed the gate so that a lower serial is rejected.
            map.testsOnly_setSiteTimeserials(["site1": "ts2"])
            var pool = ObjectsPool(logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())

            let operation = TestFactories.objectOperation(
                action: .known(.mapSet),
                mapSet: ProtocolTypes.MapSet(key: "key", value: ProtocolTypes.ObjectData(string: "value")),
            )

            // RTLO4a: serial "ts1" < existing "ts2" so the gate rejects → nil.
            let rejected = internalQueue.ably_syncNoDeadlock {
                map.nosync_apply(
                    operation,
                    source: .channel,
                    objectMessage: TestFactories.inboundObjectMessage(serial: "ts1", siteCode: "site1"),
                    objectsPool: &pool,
                )
            }
            #expect(rejected == nil)

            // serial "ts3" > existing "ts2" so the gate accepts → non-nil update.
            let accepted = internalQueue.ably_syncNoDeadlock {
                map.nosync_apply(
                    operation,
                    source: .channel,
                    objectMessage: TestFactories.inboundObjectMessage(serial: "ts3", siteCode: "site1"),
                    objectsPool: &pool,
                )
            }
            #expect(accepted != nil)
        }
    }

    // MARK: - testsOnly_ pool-entry and state setters

    struct SetterTests {
        @Test
        func counterSetters() throws {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let counter = InternalDefaultLiveCounter.createZeroValued(objectID: "counter:1@1", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
            let coreSDK = MockCoreSDK(channelState: .attached, internalQueue: internalQueue)

            counter.testsOnly_setSiteTimeserials(["site1": "ts1"])
            #expect(counter.testsOnly_siteTimeserials == ["site1": "ts1"])

            let tombstonedAt = Date(timeIntervalSince1970: 1000)
            counter.testsOnly_setTombstonedAt(tombstonedAt)
            #expect(counter.testsOnly_tombstonedAt == tombstonedAt)
            #expect(counter.testsOnly_isTombstone)

            counter.testsOnly_setCreateOperationIsMerged(true)
            #expect(counter.testsOnly_createOperationIsMerged)

            counter.testsOnly_setData(42)
            #expect(try counter.value(coreSDK: coreSDK) == 42)
        }

        @Test
        func mapSetters() {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let map = InternalDefaultLiveMap.createZeroValued(objectID: "map:1@1", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())

            map.testsOnly_setSiteTimeserials(["site1": "ts1"])
            #expect(map.testsOnly_siteTimeserials == ["site1": "ts1"])

            let tombstonedAt = Date(timeIntervalSince1970: 2000)
            map.testsOnly_setTombstonedAt(tombstonedAt)
            #expect(map.testsOnly_tombstonedAt == tombstonedAt)
            #expect(map.testsOnly_isTombstone)

            map.testsOnly_setCreateOperationIsMerged(true)
            #expect(map.testsOnly_createOperationIsMerged)

            map.testsOnly_setClearTimeserial("ts9")
            #expect(map.testsOnly_clearTimeserial == "ts9")
        }

        @Test
        func objectsPoolSetEntry() {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            var pool = ObjectsPool(logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
            let counter = InternalDefaultLiveCounter.createZeroValued(objectID: "counter:1@1", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())

            pool.testsOnly_setEntry(.counter(counter), forObjectID: "counter:1@1")
            #expect(pool.entries["counter:1@1"]?.counterValue === counter)
        }

        @Test
        func realtimeObjectsSetPoolEntry() {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let realtimeObjects = InternalDefaultRealtimeObjectsTests.createDefaultRealtimeObjects(internalQueue: internalQueue)
            let counter = InternalDefaultLiveCounter.createZeroValued(objectID: "counter:1@1", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())

            realtimeObjects.testsOnly_setPoolEntry(.counter(counter), forObjectID: "counter:1@1")
            // The setter must mutate the *owned* pool (not the struct copy returned by the getter).
            #expect(realtimeObjects.testsOnly_objectsPool.entries["counter:1@1"]?.counterValue === counter)
        }
    }

    // MARK: - Sync-state read seam

    struct SyncStateTests {
        @Test
        func syncStateReadSeam() {
            let realtimeObjects = InternalDefaultRealtimeObjectsTests.createDefaultRealtimeObjects()
            #expect(realtimeObjects.testsOnly_syncState == .initialized)
        }
    }

    // MARK: - Apply object messages and isEntryTombstoned wrapper

    struct ApplyObjectMessagesTests {
        @Test
        func applyObjectMessagesForwardsToMutableState() throws {
            let internalQueue = TestFactories.createInternalQueue()
            let realtimeObjects = InternalDefaultRealtimeObjectsTests.createDefaultRealtimeObjects(internalQueue: internalQueue)
            let coreSDK = MockCoreSDK(channelState: .attached, internalQueue: internalQueue)

            // Applying a COUNTER_INC message creates the zero-value counter (RTO6) and applies the inc.
            realtimeObjects.testsOnly_applyObjectMessages(
                [
                    TestFactories.counterIncOperationMessage(objectId: "counter:1@1", number: 7),
                ],
                source: .channel,
            )

            let counter = try #require(realtimeObjects.testsOnly_objectsPool.entries["counter:1@1"]?.counterValue)
            #expect(try counter.value(coreSDK: coreSDK) == 7)
        }
    }

    struct IsEntryTombstonedTests {
        @Test
        func isEntryTombstonedWrapper() {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let map = InternalDefaultLiveMap.createZeroValued(objectID: "map:1@1", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
            let pool = ObjectsPool(logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())

            let tombstonedEntry = InternalObjectsMapEntry(tombstonedAt: Date(timeIntervalSince1970: 1000), timeserial: nil, data: nil)
            #expect(map.testsOnly_isEntryTombstoned(tombstonedEntry, objectsPool: pool))

            let liveEntry = InternalObjectsMapEntry(data: ProtocolTypes.ObjectData(string: "value"))
            #expect(!map.testsOnly_isEntryTombstoned(liveEntry, objectsPool: pool))
        }
    }

    // MARK: - Update-model enrichment (objectMessage + tombstone, RTLO4b4d/RTLO4b4e) and PAOM3

    /// Smoke tests for the update-model enrichment: op-path updates carry the internal source
    /// ``ProtocolTypes/InboundObjectMessage`` (RTLO4b4d), sync-path updates carry `nil` (RTO4b2a),
    /// tombstoning sets the `tombstone` flag (RTLO4b4e), and a tombstone teardown deregisters
    /// subscriptions (RTLO4b4c3c).
    struct UpdateEnrichmentTests {
        /// An internal source object message carrying a COUNTER_INC operation, for use as the
        /// threaded `objectMessage`.
        private static func counterIncMessage(objectId: String) -> ProtocolTypes.InboundObjectMessage {
            TestFactories.inboundObjectMessage(
                id: "msg-1",
                operation: TestFactories.objectOperation(action: .known(.counterInc), objectId: objectId, counterInc: TestFactories.counterInc(number: 10)),
                serial: "ts1",
                siteCode: "site1",
            )
        }

        // An op-path apply threads the source message onto the emitted/returned update (RTLO4b4d).
        @Test
        func opPathApplyCarriesObjectMessage() {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let counter = InternalDefaultLiveCounter.createZeroValued(objectID: "counter:1@1", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
            var pool = ObjectsPool(logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())

            let sourceObjectMessage = Self.counterIncMessage(objectId: "counter:1@1")
            let operation = TestFactories.objectOperation(
                action: .known(.counterInc),
                objectId: "counter:1@1",
                counterInc: TestFactories.counterInc(number: 10),
            )

            let update = internalQueue.ably_syncNoDeadlock {
                counter.nosync_apply(
                    operation,
                    source: .channel,
                    objectMessage: sourceObjectMessage,
                    objectsPool: &pool,
                )
            }

            #expect(update?.objectMessage == sourceObjectMessage)
            #expect(update?.tombstone == false)
        }

        // A sync-path replaceData produces an update with a nil message (RTO4b2a).
        @Test
        func syncPathReplaceDataHasNilMessage() {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let counter = InternalDefaultLiveCounter.createZeroValued(objectID: "counter:1@1", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())

            let update = internalQueue.ably_syncNoDeadlock {
                counter.nosync_replaceData(
                    using: TestFactories.counterObjectState(siteTimeserials: [:], count: 5),
                    objectMessageSerialTimestamp: nil,
                )
            }

            #expect(update.update?.amount == 5)
            #expect(update.objectMessage == nil)
            #expect(update.tombstone == false)
        }

        // An OBJECT_DELETE apply sets the tombstone flag and still carries the source message.
        @Test
        func objectDeleteSetsTombstoneFlag() {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let counter = InternalDefaultLiveCounter.createZeroValued(objectID: "counter:1@1", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
            var pool = ObjectsPool(logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())

            let operation = TestFactories.objectOperation(
                action: .known(.objectDelete),
                objectId: "counter:1@1",
                objectDelete: WireObjectDelete(),
            )
            let sourceObjectMessage = TestFactories.inboundObjectMessage(
                operation: operation,
                serial: "ts1",
                siteCode: "site1",
            )

            let update = internalQueue.ably_syncNoDeadlock {
                counter.nosync_apply(
                    operation,
                    source: .channel,
                    objectMessage: sourceObjectMessage,
                    objectsPool: &pool,
                )
            }

            #expect(update?.tombstone == true)
            #expect(update?.objectMessage == sourceObjectMessage)
            #expect(counter.testsOnly_isTombstone)
        }

        // After a tombstone update is emitted, the object's subscriptions are deregistered
        // (RTLO4b4c3c): the tombstone update is delivered, but no subsequent update is.
        @available(iOS 17.0.0, tvOS 17.0.0, *)
        @Test
        func tombstoneDeregistersSubscriptions() async throws {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let counter = InternalDefaultLiveCounter.createZeroValued(objectID: "counter:1@1", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
            let coreSDK = MockCoreSDK(channelState: .attached, internalQueue: internalQueue)
            var pool = ObjectsPool(logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())

            let subscriber = Subscriber<DefaultLiveCounterUpdate, SubscribeResponse>(callbackQueue: .main)
            try counter.subscribe(listener: subscriber.createListener(), coreSDK: coreSDK)

            // Apply OBJECT_DELETE — emits the tombstone update, then tears down subscriptions.
            let operation = TestFactories.objectOperation(
                action: .known(.objectDelete),
                objectId: "counter:1@1",
                objectDelete: WireObjectDelete(),
            )
            internalQueue.ably_syncNoDeadlock {
                _ = counter.nosync_apply(
                    operation,
                    source: .channel,
                    objectMessage: TestFactories.inboundObjectMessage(serial: "ts1", siteCode: "site1"),
                    objectsPool: &pool,
                )
                // A further emission must not reach the (now-deregistered) subscriber.
                counter.nosync_emit(.update(.init(amount: 99)))
            }

            let invocations = await subscriber.getInvocations()
            // Exactly one invocation: the tombstone update. The post-teardown emit is dropped.
            #expect(invocations.count == 1)
            #expect(invocations.first?.0.tombstone == true)
        }

        // PAOM3: op-bearing inbound messages convert to a public ObjectMessage; a message without an
        // operation, or with an unknown wire action, does not surface publicly (DEV-5).
        @Test
        func paom3Conversion() throws {
            // Op-bearing → non-nil, with mapped fields.
            let inbound = TestFactories.inboundObjectMessage(
                id: "msg-1",
                operation: TestFactories.objectOperation(
                    action: .known(.counterInc),
                    objectId: "counter:1@1",
                    counterInc: TestFactories.counterInc(number: 7),
                ),
                serial: "ts1",
                siteCode: "site1",
            )
            let converted = try #require(inbound.toPublicObjectMessage(channelName: "channel-1"))
            #expect(converted.id == "msg-1")
            #expect(converted.channel == "channel-1")
            #expect(converted.serial == "ts1")
            #expect(converted.operation.action == .counterInc)
            #expect(converted.operation.counterInc?.number == 7)

            // No operation → nil.
            #expect(TestFactories.objectMessageWithoutState().toPublicObjectMessage(channelName: "channel-1") == nil)

            // Unknown wire action → nil (never surfaces publicly, DEV-5).
            let unknownAction = TestFactories.inboundObjectMessage(
                operation: TestFactories.objectOperation(action: .unknown(99), objectId: "counter:1@1"),
            )
            #expect(unknownAction.toPublicObjectMessage(channelName: "channel-1") == nil)
        }
    }
}
