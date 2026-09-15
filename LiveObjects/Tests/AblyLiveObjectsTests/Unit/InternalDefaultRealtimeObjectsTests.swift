import _AblyPluginSupportPrivate
@testable import AblyLiveObjects
@testable import AblyLiveObjectsTesting
import AblyPubSubDevice
import Testing

/// Tests for `InternalDefaultRealtimeObjects`.
struct InternalDefaultRealtimeObjectsTests {
    // MARK: - Test Helpers

    /// Creates a InternalDefaultRealtimeObjects instance for testing
    static func createDefaultRealtimeObjects(
        clock: SimpleClock = MockSimpleClock(),
        internalQueue: DispatchQueue = TestFactories.createInternalQueue(),
    ) -> InternalDefaultRealtimeObjects {
        let logger = TestLogger()
        return InternalDefaultRealtimeObjects(
            logger: logger,
            internalQueue: internalQueue,
            userCallbackQueue: .main,
            clock: clock,
            channelName: "test-channel",
        )
    }

    /// Tests for `InternalDefaultRealtimeObjects.handleObjectSyncProtocolMessage`, covering RTO5 specification points.
    struct HandleObjectSyncProtocolMessageTests {
        // MARK: - RTO5a5: Single ProtocolMessage Sync Tests

        // Note: RTO5a5 (an OBJECT_SYNC with no channelSerial is a single-message sync — the objects are
        // applied and the sync completes SYNCED) is covered by the UTS port in
        // `Test/UTS/unit/objects/ObjectsPoolTests.swift` (`objectSyncWithNoChannelSerialIsSingleMessageSync`),
        // which seeds two objects in the single sync message to retain this native twin's multi-object
        // coverage plus asserts the spec-mandated `syncState == SYNCED`.

        // MARK: - Malformed channelSerial (RTO5a6)

        // Note: RTO5a6 (a malformed, colon-less channelSerial treated as absent per RTO5a5 — data
        // applied, sync completes) is covered by the UTS port in
        // `Test/UTS/unit/objects/ObjectsPoolTests.swift` (`malformedChannelSerialTreatedAsAbsent`),
        // which asserts the spec-mandated `syncState == SYNCED` (which implies the no-in-flight-sequence
        // invariant this native twin checked) plus the object landing in the pool.

        // An empty sequence id (":cursor") is accepted — everything before the first colon is the
        // sequence id (RTO5a1), and the spec does not rule out an empty one — so it opens an in-flight
        // sync sequence rather than completing immediately. A subsequent ":" ends the sequence
        // (RTO5a4), completing the sync and applying its objects.
        @Test
        func handlesEmptySequenceId() async throws {
            let internalQueue = TestFactories.createInternalQueue()
            let realtimeObjects = InternalDefaultRealtimeObjectsTests.createDefaultRealtimeObjects(internalQueue: internalQueue)
            let objectMessages = [
                TestFactories.simpleMapMessage(objectId: "map:1@123"),
            ]

            // Start a sequence with an empty sequence id.
            internalQueue.ably_syncNoDeadlock {
                realtimeObjects.nosync_handleObjectSyncProtocolMessage(
                    objectMessages: objectMessages,
                    protocolMessageChannelSerial: ":cursor456",
                )
            }

            // The sync sequence is in flight (not self-contained), so nothing is applied yet.
            #expect(realtimeObjects.testsOnly_hasSyncSequence)

            // End the sequence with an empty sequence id and empty cursor.
            internalQueue.ably_syncNoDeadlock {
                realtimeObjects.nosync_handleObjectSyncProtocolMessage(
                    objectMessages: [],
                    protocolMessageChannelSerial: ":",
                )
            }

            // The sequence completed and its objects were applied.
            #expect(!realtimeObjects.testsOnly_hasSyncSequence)
            let pool = realtimeObjects.testsOnly_objectsPool
            #expect(pool.entries["map:1@123"] != nil)
        }

        // MARK: - RTO5a1, RTO5a3, RTO5a4: Multi-ProtocolMessage Sync Tests

        // @spec RTO5a1
        // @spec RTO5a3
        // @spec RTO5a4
        // @spec RTO5f
        // @spec RTO5c3
        // @spec RTO5c4
        // @spec RTO5c5
        @Test
        func handlesMultiProtocolMessageSync() async throws {
            let internalQueue = TestFactories.createInternalQueue()
            let realtimeObjects = InternalDefaultRealtimeObjectsTests.createDefaultRealtimeObjects(internalQueue: internalQueue)
            let sequenceId = "seq123"

            // First message in sequence
            let firstMessages = [TestFactories.simpleMapMessage(objectId: "map:1@123")]
            internalQueue.ably_syncNoDeadlock {
                realtimeObjects.nosync_handleObjectSyncProtocolMessage(
                    objectMessages: firstMessages,
                    protocolMessageChannelSerial: "\(sequenceId):cursor1",
                )
            }

            // Verify sync sequence is active (RTO5a1, RTO5a3)
            #expect(realtimeObjects.testsOnly_hasSyncSequence)

            // Verify objects not yet applied to pool
            let poolAfterFirst = realtimeObjects.testsOnly_objectsPool
            #expect(poolAfterFirst.entries["map:1@123"] == nil)

            // Second message in sequence
            let secondMessages = [TestFactories.simpleMapMessage(objectId: "map:2@456")]
            internalQueue.ably_syncNoDeadlock {
                realtimeObjects.nosync_handleObjectSyncProtocolMessage(
                    objectMessages: secondMessages,
                    protocolMessageChannelSerial: "\(sequenceId):cursor2",
                )
            }

            // Verify sync sequence still active
            #expect(realtimeObjects.testsOnly_hasSyncSequence)

            // Verify objects still not applied to pool
            let poolAfterSecond = realtimeObjects.testsOnly_objectsPool
            #expect(poolAfterSecond.entries["map:1@123"] == nil)
            #expect(poolAfterSecond.entries["map:2@456"] == nil)

            // Final message in sequence (end of sequence per RTO5a4)
            let finalMessages = [TestFactories.simpleMapMessage(objectId: "map:3@789")]
            internalQueue.ably_syncNoDeadlock {
                realtimeObjects.nosync_handleObjectSyncProtocolMessage(
                    objectMessages: finalMessages,
                    protocolMessageChannelSerial: "\(sequenceId):", // Empty cursor indicates end
                )
            }

            // Verify sync sequence is cleared and there is no SyncObjectsPool or BufferedObjectOperations (RTO5c3, RTO5c4, RTO5c5)
            #expect(!realtimeObjects.testsOnly_hasSyncSequence)

            // Verify all objects were applied to pool (side effect of applySyncObjectsPool per RTO5c1b1b)
            let finalPool = realtimeObjects.testsOnly_objectsPool
            #expect(finalPool.entries["map:1@123"] != nil)
            #expect(finalPool.entries["map:2@456"] != nil)
            #expect(finalPool.entries["map:3@789"] != nil)
        }

        // MARK: - RTO5a2: New Sync Sequence Tests

        // @spec RTO5a2
        // @spec RTO5a2a
        @Test
        func newSequenceIdDiscardsInFlightSync() async throws {
            let internalQueue = TestFactories.createInternalQueue()
            let realtimeObjects = InternalDefaultRealtimeObjectsTests.createDefaultRealtimeObjects(internalQueue: internalQueue)
            let firstSequenceId = "seq1"
            let secondSequenceId = "seq2"

            // Start first sequence
            let firstMessages = [TestFactories.simpleMapMessage(objectId: "map:1@123")]
            internalQueue.ably_syncNoDeadlock {
                realtimeObjects.nosync_handleObjectSyncProtocolMessage(
                    objectMessages: firstMessages,
                    protocolMessageChannelSerial: "\(firstSequenceId):cursor1",
                )
            }

            #expect(realtimeObjects.testsOnly_hasSyncSequence)

            // Start new sequence with different ID (RTO5a2)
            let secondMessages = [TestFactories.simpleMapMessage(objectId: "map:2@456")]
            internalQueue.ably_syncNoDeadlock {
                realtimeObjects.nosync_handleObjectSyncProtocolMessage(
                    objectMessages: secondMessages,
                    protocolMessageChannelSerial: "\(secondSequenceId):cursor1",
                )
            }

            // Verify sync sequence is still active but with new ID
            #expect(realtimeObjects.testsOnly_hasSyncSequence)

            // Complete the new sequence
            internalQueue.ably_syncNoDeadlock {
                realtimeObjects.nosync_handleObjectSyncProtocolMessage(
                    objectMessages: [],
                    protocolMessageChannelSerial: "\(secondSequenceId):",
                )
            }

            // Verify only the second sequence's objects were applied (RTO5a2a - previous cleared)
            let pool = realtimeObjects.testsOnly_objectsPool
            #expect(pool.entries["map:1@123"] == nil) // From discarded first sequence
            #expect(pool.entries["map:2@456"] != nil) // From completed second sequence
            #expect(!realtimeObjects.testsOnly_hasSyncSequence)
        }

        // MARK: - RTO5c: Post-Sync Behavior Tests

        // A smoke test that the RTO5c post-sync behaviours performed inside ObjectsPool.applySyncObjectsPool get performed (they are tested in more detail there). Also the primary test for post-sync behaviours that exist outside of applySyncObjectsPool, such as RTO5c9.
        // @spec RTO5c9
        @Test
        func performsPostSyncSteps() async throws {
            let internalQueue = TestFactories.createInternalQueue()
            let realtimeObjects = InternalDefaultRealtimeObjectsTests.createDefaultRealtimeObjects(internalQueue: internalQueue)
            let coreSDK = MockCoreSDK(channelState: .attached, internalQueue: internalQueue)

            // Transition to synced state so that createCounter can work
            internalQueue.ably_syncNoDeadlock {
                realtimeObjects.nosync_onChannelAttached(hasObjects: false)
                realtimeObjects.nosync_setSiteCode("site1")
            }

            // Populate appliedOnAckSerials by performing a local operation (RTO5c9 setup)
            coreSDK.setPublishHandler { messages in
                PublishResult(serials: messages.map { _ in "serial_abc" })
            }
            _ = try await realtimeObjects.createCounter(count: 1, coreSDK: coreSDK)
            #expect(!realtimeObjects.testsOnly_appliedOnAckSerials.isEmpty)

            // Perform sync with only one object (RTO5a5 case)
            let syncMessages = [TestFactories.mapObjectMessage(objectId: "map:synced@1")]
            internalQueue.ably_syncNoDeadlock {
                realtimeObjects.nosync_handleObjectSyncProtocolMessage(
                    objectMessages: syncMessages,
                    protocolMessageChannelSerial: nil,
                )
            }

            // Verify root is preserved (RTO5c2a) and sync completed (RTO5c3)
            #expect(!realtimeObjects.testsOnly_hasSyncSequence)
            let finalPool = realtimeObjects.testsOnly_objectsPool
            #expect(finalPool.entries["root"] != nil) // Root preserved
            #expect(finalPool.entries["map:synced@1"] != nil) // Synced object added

            // Verify appliedOnAckSerials is cleared (RTO5c9)
            #expect(realtimeObjects.testsOnly_appliedOnAckSerials.isEmpty)
        }

        // MARK: - Edge Cases

        /// Test mixed object types in single sync
        @Test
        func handlesMixedObjectTypesInSync() async throws {
            let internalQueue = TestFactories.createInternalQueue()
            let realtimeObjects = InternalDefaultRealtimeObjectsTests.createDefaultRealtimeObjects(internalQueue: internalQueue)

            let mixedMessages = [
                TestFactories.mapObjectMessage(objectId: "map:1@123"),
                TestFactories.counterObjectMessage(objectId: "counter:1@456"),
                TestFactories.mapObjectMessage(objectId: "map:2@789"),
            ]

            internalQueue.ably_syncNoDeadlock {
                realtimeObjects.nosync_handleObjectSyncProtocolMessage(
                    objectMessages: mixedMessages,
                    protocolMessageChannelSerial: nil, // Single message sync
                )
            }

            // Verify all object types were processed
            let pool = realtimeObjects.testsOnly_objectsPool
            #expect(pool.entries["map:1@123"] != nil)
            #expect(pool.entries["counter:1@456"] != nil)
            #expect(pool.entries["map:2@789"] != nil)
            #expect(pool.entries.count == 4) // root + 3 objects
        }

        /// Test continuation of sync after interruption by new sequence
        @Test
        func handlesSequenceInterruptionCorrectly() async throws {
            let internalQueue = TestFactories.createInternalQueue()
            let realtimeObjects = InternalDefaultRealtimeObjectsTests.createDefaultRealtimeObjects(internalQueue: internalQueue)

            // Start first sequence
            internalQueue.ably_syncNoDeadlock {
                realtimeObjects.nosync_handleObjectSyncProtocolMessage(
                    objectMessages: [TestFactories.mapObjectMessage(objectId: "map:old@1")],
                    protocolMessageChannelSerial: "oldSeq:cursor1",
                )
            }

            #expect(realtimeObjects.testsOnly_hasSyncSequence)

            // Interrupt with new sequence
            internalQueue.ably_syncNoDeadlock {
                realtimeObjects.nosync_handleObjectSyncProtocolMessage(
                    objectMessages: [TestFactories.mapObjectMessage(objectId: "map:new@1")],
                    protocolMessageChannelSerial: "newSeq:cursor1",
                )
            }

            #expect(realtimeObjects.testsOnly_hasSyncSequence)

            // Continue new sequence
            internalQueue.ably_syncNoDeadlock {
                realtimeObjects.nosync_handleObjectSyncProtocolMessage(
                    objectMessages: [TestFactories.mapObjectMessage(objectId: "map:new@2")],
                    protocolMessageChannelSerial: "newSeq:cursor2",
                )
            }

            // Complete new sequence
            internalQueue.ably_syncNoDeadlock {
                realtimeObjects.nosync_handleObjectSyncProtocolMessage(
                    objectMessages: [],
                    protocolMessageChannelSerial: "newSeq:",
                )
            }

            // Verify only new sequence objects were applied
            let pool = realtimeObjects.testsOnly_objectsPool
            #expect(pool.entries["map:old@1"] == nil) // From interrupted sequence
            #expect(pool.entries["map:new@1"] != nil) // From completed sequence
            #expect(pool.entries["map:new@2"] != nil) // From completed sequence
            #expect(!realtimeObjects.testsOnly_hasSyncSequence)
        }
    }

    /// Tests for `InternalDefaultRealtimeObjects.onChannelAttached`, covering RTO4 specification points.
    ///
    /// Note: These tests use `OBJECT_SYNC` messages to populate the initial state of objects pools
    /// and sync sequences. This approach is more realistic than directly manipulating internal state,
    /// as it simulates how objects actually enter pools during normal operation.
    struct OnChannelAttachedTests {
        // MARK: - RTO4a Tests

        // @spec RTO4a - Checks that when the `HAS_OBJECTS` flag is 1 (i.e. the server will shortly perform an `OBJECT_SYNC` sequence) we don't modify the objects pool or sync sequence
        // @specOneOf(1/2) RTO4d
        @Test
        func handlesHasObjectTrue() {
            let internalQueue = TestFactories.createInternalQueue()
            let realtimeObjects = InternalDefaultRealtimeObjectsTests.createDefaultRealtimeObjects(internalQueue: internalQueue)

            // Set up initial state with additional objects by using the createZeroValueObject method
            let originalPool = realtimeObjects.testsOnly_objectsPool
            let originalRootObject = originalPool.root
            _ = realtimeObjects.testsOnly_createZeroValueLiveObject(forObjectID: "map:test@123")

            // Set up an in-progress sync sequence
            internalQueue.ably_syncNoDeadlock {
                realtimeObjects.nosync_handleObjectSyncProtocolMessage(
                    objectMessages: [
                        TestFactories.mapObjectMessage(objectId: "map:sync@456"),
                    ],
                    protocolMessageChannelSerial: "seq1:cursor1",
                )
            }

            #expect(realtimeObjects.testsOnly_hasSyncSequence)

            // Inject a buffered OBJECT operation
            internalQueue.ably_syncNoDeadlock {
                realtimeObjects.nosync_handleObjectProtocolMessage(objectMessages: [
                    TestFactories.mapCreateOperationMessage(objectId: "map:buffered@789"),
                ])
            }

            #expect(realtimeObjects.testsOnly_bufferedObjectOperationsCount == 1)

            // When: onChannelAttached is called with hasObjects = true
            internalQueue.ably_syncNoDeadlock {
                realtimeObjects.nosync_onChannelAttached(hasObjects: true)
            }

            // Then:
            #expect(realtimeObjects.testsOnly_onChannelAttachedHasObjects == true)

            // Verify ObjectsPool is unchanged
            let poolAfter = realtimeObjects.testsOnly_objectsPool
            #expect(poolAfter.root as AnyObject === originalRootObject as AnyObject)
            #expect(poolAfter.entries.count == 2) // root + additional map
            #expect(poolAfter.entries["map:test@123"] != nil)

            // Verify sync sequence is still active
            #expect(realtimeObjects.testsOnly_hasSyncSequence)

            // RTO4d: Verify buffered object operations were cleared
            #expect(realtimeObjects.testsOnly_bufferedObjectOperationsCount == 0)
        }

        // MARK: - RTO4b Tests

        // @spec RTO4b1
        // @spec RTO4b2
        // @spec RTO4b2a
        // @spec RTO4b3
        // @spec RTO4b4
        // @specOneOf(2/2) RTO4d
        @available(iOS 17.0.0, tvOS 17.0.0, *)
        @Test
        func handlesHasObjectsFalse() async throws {
            let internalQueue = TestFactories.createInternalQueue()
            let realtimeObjects = InternalDefaultRealtimeObjectsTests.createDefaultRealtimeObjects(internalQueue: internalQueue)

            // Set up initial state with additional objects in the pool using sync
            internalQueue.ably_syncNoDeadlock {
                realtimeObjects.nosync_handleObjectSyncProtocolMessage(
                    objectMessages: [
                        TestFactories.mapObjectMessage(objectId: "root", entries: [
                            "existingMap": TestFactories.objectReferenceMapEntry(key: "existingMap", objectId: "map:existing@123").entry,
                            "existingCounter": TestFactories.objectReferenceMapEntry(key: "existingCounter", objectId: "counter:existing@456").entry,
                        ]),
                        TestFactories.mapObjectMessage(objectId: "map:existing@123"),
                        TestFactories.counterObjectMessage(objectId: "counter:existing@456"),
                    ],
                    protocolMessageChannelSerial: nil, // Complete sync immediately
                )
            }

            let originalPool = realtimeObjects.testsOnly_objectsPool
            #expect(Set(originalPool.root.testsOnly_data.keys) == ["existingMap", "existingCounter"])

            // Give root a non-nil clearTimeserial so we can verify it gets nilled out per RTLM4
            // (using a serial before the entry timeserials so entries survive)
            let originalRoot = originalPool.root
            _ = originalRoot.testsOnly_applyMapClearOperation(serial: "aaa", objectsPool: originalPool)
            #expect(originalPool.root.testsOnly_clearTimeserial == "aaa")

            let rootSubscriber = Subscriber<DefaultLiveMapUpdate, SubscribeResponse>(callbackQueue: .main)
            let coreSDK = MockCoreSDK(channelState: .attached, internalQueue: internalQueue)
            try originalPool.root.subscribe(listener: rootSubscriber.createListener(), coreSDK: coreSDK)

            // Populate appliedOnAckSerials by performing a local operation (RTO5c9 setup)
            internalQueue.ably_syncNoDeadlock {
                realtimeObjects.nosync_setSiteCode("site1")
            }
            coreSDK.setPublishHandler { messages in
                PublishResult(serials: messages.map { _ in "serial_abc" })
            }
            _ = try await realtimeObjects.createCounter(count: 1, coreSDK: coreSDK)
            #expect(!realtimeObjects.testsOnly_appliedOnAckSerials.isEmpty)

            // Set up an in-progress sync sequence
            internalQueue.ably_syncNoDeadlock {
                realtimeObjects.nosync_handleObjectSyncProtocolMessage(
                    objectMessages: [
                        TestFactories.mapObjectMessage(objectId: "map:sync@789"),
                    ],
                    protocolMessageChannelSerial: "seq1:cursor1",
                )
            }

            #expect(realtimeObjects.testsOnly_hasSyncSequence)
            #expect(originalPool.entries.count == 3) // root + 2 additional objects

            // When: onChannelAttached is called with hasObjects = false
            internalQueue.ably_syncNoDeadlock {
                realtimeObjects.nosync_onChannelAttached(hasObjects: false)
            }

            // Then: Verify the expected behavior per RTO4b
            #expect(realtimeObjects.testsOnly_onChannelAttachedHasObjects == false)

            // RTO4b1, RTO4b2: All objects except root must be removed, root must be cleared to zero-value
            let newPool = realtimeObjects.testsOnly_objectsPool
            #expect(newPool.entries.count == 1) // Only root should remain
            #expect(newPool.entries["root"] != nil)
            #expect(newPool.entries["map:existing@123"] == nil) // Should be removed
            #expect(newPool.entries["counter:existing@456"] == nil) // Should be removed
            // Verify that `removed` was emitted for root's existing keys per RTO4b2a
            let subscriberInvocations = await rootSubscriber.getInvocations()
            #expect(subscriberInvocations.map(\.0) == [.init(update: ["existingMap": .removed, "existingCounter": .removed])])

            // Verify root is the same object, but with data cleared (RTO4b2)
            // TODO: this one is unclear (are we meant to replace the root or just clear its data?) https://github.com/ably/specification/pull/333/files#r2183493458. I believe that the answer is that we should just clear its data but the spec point needs to be clearer, see https://github.com/ably/specification/pull/346/files#r2201434895.
            let newRoot = newPool.root
            #expect(newRoot as AnyObject === originalPool.root as AnyObject) // Should be same instance
            #expect(newRoot.testsOnly_data.isEmpty) // Should be zero-valued (empty)
            #expect(newRoot.testsOnly_clearTimeserial == nil) // RTLM4: zero-value LiveMap has clearTimeserial set to null

            // RTO4b3, RTO4b4, RTO4d: SyncObjectsPool must be cleared, sync sequence cleared, BufferedObjectOperations cleared, appliedOnAckSerials cleared
            #expect(!realtimeObjects.testsOnly_hasSyncSequence)
            #expect(realtimeObjects.testsOnly_appliedOnAckSerials.isEmpty)
        }

        // @spec RTO4b4
        // The RTO4b ATTACHED(HAS_OBJECTS=false) sync completion runs the same completion actions as
        // the RTO5c OBJECT_SYNC path (both via the shared `nosync_completeSync`), which includes
        // resolving any parked publishAndApply sync waiter (RTO20e). This complements
        // `handlesHasObjectsFalse` (which covers the pool reset + appliedOnAckSerials clear) with the
        // waiter-resolution that the shared completion tail performs — so the two paths cannot drift.
        @Test
        func handlesHasObjectsFalseResolvesParkedPublishAndApplyWaiter() async throws {
            let internalQueue = TestFactories.createInternalQueue()
            let realtimeObjects = InternalDefaultRealtimeObjectsTests.createDefaultRealtimeObjects(internalQueue: internalQueue)
            let coreSDK = MockCoreSDK(channelState: .attached, internalQueue: internalQueue)

            // Move to SYNCING (so a publishAndApply parks in the RTO20e wait) and set the siteCode.
            internalQueue.ably_syncNoDeadlock {
                realtimeObjects.nosync_onChannelAttached(hasObjects: true)
                realtimeObjects.nosync_setSiteCode("site1")
            }

            // After the publish ACK, complete the sync via ATTACHED(HAS_OBJECTS=false) — the RTO4b path,
            // which must drain the parked waiter via the shared `nosync_completeSync` (RTO5c tail).
            coreSDK.setPublishCallbackHandler { messages, callback in
                let result = PublishResult(serials: messages.map { _ in "serial_xyz" })

                internalQueue.async {
                    callback(.success(result))

                    internalQueue.async {
                        realtimeObjects.nosync_onChannelAttached(hasObjects: false)
                    }
                }
            }

            // The create parks in the RTO20e wait; resolving at all proves the RTO4b completion drained
            // the parked waiter (a hang would time the test out).
            let returnedCounter = try await realtimeObjects.createCounter(count: 42, coreSDK: coreSDK)
            #expect(try returnedCounter.value(coreSDK: coreSDK) == 42)
        }

        // MARK: - Edge Cases and Integration Tests

        /// Test that multiple calls to onChannelAttached work correctly
        @Test
        func handlesMultipleCallsCorrectly() {
            let internalQueue = TestFactories.createInternalQueue()
            let realtimeObjects = InternalDefaultRealtimeObjectsTests.createDefaultRealtimeObjects(internalQueue: internalQueue)

            // First call with hasObjects = true (should do nothing)
            internalQueue.ably_syncNoDeadlock {
                realtimeObjects.nosync_onChannelAttached(hasObjects: true)
            }
            #expect(realtimeObjects.testsOnly_onChannelAttachedHasObjects == true)
            let originalPool = realtimeObjects.testsOnly_objectsPool
            let originalRoot = originalPool.root

            // Second call with hasObjects = false (should reset)
            internalQueue.ably_syncNoDeadlock {
                realtimeObjects.nosync_onChannelAttached(hasObjects: false)
            }
            #expect(realtimeObjects.testsOnly_onChannelAttachedHasObjects == false)
            let newPool = realtimeObjects.testsOnly_objectsPool
            #expect(newPool.root as AnyObject === originalRoot as AnyObject)
            #expect(newPool.entries.count == 1)

            // Third call with hasObjects = true again (should do nothing)
            internalQueue.ably_syncNoDeadlock {
                realtimeObjects.nosync_onChannelAttached(hasObjects: true)
            }
            #expect(realtimeObjects.testsOnly_onChannelAttachedHasObjects == true)
            let finalPool = realtimeObjects.testsOnly_objectsPool
            #expect(finalPool.root as AnyObject === originalRoot as AnyObject) // Should be unchanged
        }

        /// Test that sync sequence is properly discarded even with complex sync state
        @Test
        func discardsComplexSyncSequence() {
            let internalQueue = TestFactories.createInternalQueue()
            let realtimeObjects = InternalDefaultRealtimeObjectsTests.createDefaultRealtimeObjects(internalQueue: internalQueue)

            // Create a complex sync sequence using OBJECT_SYNC messages
            // (This simulates realistic multi-message sync scenarios)
            internalQueue.ably_syncNoDeadlock {
                realtimeObjects.nosync_handleObjectSyncProtocolMessage(
                    objectMessages: [
                        TestFactories.mapObjectMessage(objectId: "map:sync1@123"),
                    ],
                    protocolMessageChannelSerial: "seq1:cursor1",
                )
            }

            internalQueue.ably_syncNoDeadlock {
                realtimeObjects.nosync_handleObjectSyncProtocolMessage(
                    objectMessages: [
                        TestFactories.counterObjectMessage(objectId: "counter:sync1@456"),
                    ],
                    protocolMessageChannelSerial: "seq1:cursor2",
                )
            }

            #expect(realtimeObjects.testsOnly_hasSyncSequence)

            // When: onChannelAttached is called with hasObjects = false
            internalQueue.ably_syncNoDeadlock {
                realtimeObjects.nosync_onChannelAttached(hasObjects: false)
            }

            // Then: All sync data should be discarded
            #expect(!realtimeObjects.testsOnly_hasSyncSequence)
            let pool = realtimeObjects.testsOnly_objectsPool
            #expect(pool.entries.count == 1) // Only root
            #expect(pool.entries["map:sync1@123"] == nil)
            #expect(pool.entries["counter:sync1@456"] == nil)
        }

        /// Test behavior when there's no sync sequence in progress
        @Test
        func handlesNoSyncSequenceCorrectly() {
            let internalQueue = TestFactories.createInternalQueue()
            let realtimeObjects = InternalDefaultRealtimeObjectsTests.createDefaultRealtimeObjects(internalQueue: internalQueue)

            // Add some objects to the pool using OBJECT_SYNC messages
            // (This is the realistic way objects enter the pool, not through direct manipulation)
            internalQueue.ably_syncNoDeadlock {
                realtimeObjects.nosync_handleObjectSyncProtocolMessage(
                    objectMessages: [
                        TestFactories.mapObjectMessage(objectId: "map:test@123"),
                    ],
                    protocolMessageChannelSerial: nil, // Complete sync immediately
                )
            }

            let pool = realtimeObjects.testsOnly_objectsPool

            #expect(!realtimeObjects.testsOnly_hasSyncSequence)
            #expect(pool.entries.count == 2) // root + additional map

            // When: onChannelAttached is called with hasObjects = false
            internalQueue.ably_syncNoDeadlock {
                realtimeObjects.nosync_onChannelAttached(hasObjects: false)
            }

            // Then: Should still reset the pool correctly
            let newPool = realtimeObjects.testsOnly_objectsPool
            #expect(newPool.entries.count == 1) // Only root
            #expect(newPool.entries["map:test@123"] == nil)
            #expect(!realtimeObjects.testsOnly_hasSyncSequence) // Should remain false
        }

        /// Test that the root object's delegate is correctly set after reset
        @Test
        func setsCorrectDelegateOnNewRoot() {
            let internalQueue = TestFactories.createInternalQueue()
            let realtimeObjects = InternalDefaultRealtimeObjectsTests.createDefaultRealtimeObjects(internalQueue: internalQueue)

            // When: onChannelAttached is called with hasObjects = false
            internalQueue.ably_syncNoDeadlock {
                realtimeObjects.nosync_onChannelAttached(hasObjects: false)
            }

            // Then: The new root should be properly initialized
            let newRoot = realtimeObjects.testsOnly_objectsPool.root
            #expect(newRoot.testsOnly_data.isEmpty) // Should be zero-valued (empty)
        }
    }

    /// Tests for `InternalDefaultRealtimeObjects.getRoot`, covering RTO1 specification points
    struct GetRootTests {
        // MARK: - RTO1c Tests

        // @specOneOf(1/4) RTO1c - getRoot waits for sync completion when sync completes via ATTACHED with `HAS_OBJECTS` false (RTO4b)
        @Test
        func waitsForSyncCompletionViaAttachedHasObjectsFalse() async throws {
            let internalQueue = TestFactories.createInternalQueue()
            let realtimeObjects = InternalDefaultRealtimeObjectsTests.createDefaultRealtimeObjects(internalQueue: internalQueue)
            let coreSDK = MockCoreSDK(channelState: .attached, internalQueue: internalQueue)

            // Start getRoot call - it should wait for sync completion
            async let getRootTask = realtimeObjects.getRoot(coreSDK: coreSDK)

            // Wait for getRoot to start waiting for sync
            _ = try #require(await realtimeObjects.testsOnly_waitingForSyncEvents.first { _ in true })

            // Complete sync via ATTACHED with HAS_OBJECTS false (RTO4b)
            internalQueue.ably_syncNoDeadlock {
                realtimeObjects.nosync_onChannelAttached(hasObjects: false)
            }

            // getRoot should now complete
            _ = try await getRootTask
        }

        // @specOneOf(2/4) RTO1c - getRoot waits for sync completion when sync completes via single `OBJECT_SYNC` with no channelSerial (RTO5a5)
        @Test
        func waitsForSyncCompletionViaSingleObjectSync() async throws {
            let internalQueue = TestFactories.createInternalQueue()
            let realtimeObjects = InternalDefaultRealtimeObjectsTests.createDefaultRealtimeObjects(internalQueue: internalQueue)
            let coreSDK = MockCoreSDK(channelState: .attached, internalQueue: internalQueue)

            // Start getRoot call - it should wait for sync completion
            async let getRootTask = realtimeObjects.getRoot(coreSDK: coreSDK)

            // Wait for getRoot to start waiting for sync
            _ = try #require(await realtimeObjects.testsOnly_waitingForSyncEvents.first { _ in true })

            // Complete sync via single OBJECT_SYNC with no channelSerial (RTO5a5)
            let (testKey, testEntry) = TestFactories.stringMapEntry(key: "testKey", value: "testValue")
            let (referencedKey, referencedEntry) = TestFactories.objectReferenceMapEntry(key: "referencedObject", objectId: "map:test@123")
            internalQueue.ably_syncNoDeadlock {
                realtimeObjects.nosync_handleObjectSyncProtocolMessage(
                    objectMessages: [
                        TestFactories.rootObjectMessage(entries: [
                            testKey: testEntry,
                            referencedKey: referencedEntry,
                        ]),
                        TestFactories.mapObjectMessage(objectId: "map:test@123"),
                    ],
                    protocolMessageChannelSerial: nil, // RTO5a5 case
                )
            }

            // getRoot should now complete
            let root = try await getRootTask

            // Verify the root object contains the expected entries from the sync
            let testValue = try root.get(key: "testKey", coreSDK: coreSDK, delegate: realtimeObjects)?.stringValue
            #expect(testValue == "testValue")

            // Verify the root object contains a reference to the other LiveObject
            let referencedObject = try root.get(key: "referencedObject", coreSDK: coreSDK, delegate: realtimeObjects)
            #expect(referencedObject != nil)
        }

        // @specOneOf(3/4) RTO1c - getRoot waits for sync completion when sync completes via multiple `OBJECT_SYNC` messages (RTO5a4)
        @Test
        func waitsForSyncCompletionViaMultipleObjectSync() async throws {
            let internalQueue = TestFactories.createInternalQueue()
            let realtimeObjects = InternalDefaultRealtimeObjectsTests.createDefaultRealtimeObjects(internalQueue: internalQueue)
            let coreSDK = MockCoreSDK(channelState: .attached, internalQueue: internalQueue)
            let sequenceId = "seq123"

            // Start getRoot call - it should wait for sync completion
            async let getRootTask = realtimeObjects.getRoot(coreSDK: coreSDK)

            // Wait for getRoot to start waiting for sync
            _ = try #require(await realtimeObjects.testsOnly_waitingForSyncEvents.first { _ in true })

            // Start multi-message sync sequence (RTO5a1, RTO5a3)
            let (firstKey, firstEntry) = TestFactories.stringMapEntry(key: "firstKey", value: "firstValue")
            let (firstObjectKey, firstObjectEntry) = TestFactories.objectReferenceMapEntry(key: "firstObject", objectId: "map:first@123")
            let (secondObjectKey, secondObjectEntry) = TestFactories.objectReferenceMapEntry(key: "secondObject", objectId: "map:second@456")
            let (finalObjectKey, finalObjectEntry) = TestFactories.objectReferenceMapEntry(key: "finalObject", objectId: "map:final@789")
            internalQueue.ably_syncNoDeadlock {
                realtimeObjects.nosync_handleObjectSyncProtocolMessage(
                    objectMessages: [
                        TestFactories.rootObjectMessage(entries: [
                            firstKey: firstEntry,
                            firstObjectKey: firstObjectEntry,
                            secondObjectKey: secondObjectEntry,
                            finalObjectKey: finalObjectEntry,
                        ]),
                        TestFactories.mapObjectMessage(objectId: "map:first@123"),
                    ],
                    protocolMessageChannelSerial: "\(sequenceId):cursor1",
                )
            }

            // Continue sync sequence - add more objects but don't redefine root
            internalQueue.ably_syncNoDeadlock {
                realtimeObjects.nosync_handleObjectSyncProtocolMessage(
                    objectMessages: [
                        TestFactories.mapObjectMessage(objectId: "map:second@456"),
                    ],
                    protocolMessageChannelSerial: "\(sequenceId):cursor2",
                )
            }

            // Complete sync sequence (RTO5a4) - add final object
            internalQueue.ably_syncNoDeadlock {
                realtimeObjects.nosync_handleObjectSyncProtocolMessage(
                    objectMessages: [
                        TestFactories.mapObjectMessage(objectId: "map:final@789"),
                    ],
                    protocolMessageChannelSerial: "\(sequenceId):", // Empty cursor indicates end
                )
            }

            // getRoot should now complete
            let root = try await getRootTask

            // Verify the root object contains the expected entries from the sync sequence
            let firstValue = try root.get(key: "firstKey", coreSDK: coreSDK, delegate: realtimeObjects)?.stringValue
            let firstObject = try root.get(key: "firstObject", coreSDK: coreSDK, delegate: realtimeObjects)
            let secondObject = try root.get(key: "secondObject", coreSDK: coreSDK, delegate: realtimeObjects)
            let finalObject = try root.get(key: "finalObject", coreSDK: coreSDK, delegate: realtimeObjects)
            #expect(firstValue == "firstValue")
            #expect(firstObject != nil)
            #expect(secondObject != nil)
            #expect(finalObject != nil)
        }

        // @specOneOf(4/4) RTO1c - getRoot returns immediately when sync is already complete
        @Test
        func returnsImmediatelyWhenSyncAlreadyComplete() async throws {
            let internalQueue = TestFactories.createInternalQueue()
            let realtimeObjects = InternalDefaultRealtimeObjectsTests.createDefaultRealtimeObjects(internalQueue: internalQueue)
            let coreSDK = MockCoreSDK(channelState: .attached, internalQueue: internalQueue)

            // Complete sync first
            internalQueue.ably_syncNoDeadlock {
                realtimeObjects.nosync_onChannelAttached(hasObjects: false)
            }

            // getRoot should return
            _ = try await realtimeObjects.getRoot(coreSDK: coreSDK)

            // Verify no waiting events were emitted
            realtimeObjects.testsOnly_finishAllTestHelperStreams()
            let waitingEvents: [Void] = await realtimeObjects.testsOnly_waitingForSyncEvents.reduce(into: []) { result, _ in
                result.append(())
            }
            #expect(waitingEvents.isEmpty)
        }

        // MARK: - RTO1d Tests

        // @spec RTO1d
        @Test
        func returnsRootObjectFromObjectsPool() async throws {
            let internalQueue = TestFactories.createInternalQueue()
            let realtimeObjects = InternalDefaultRealtimeObjectsTests.createDefaultRealtimeObjects(internalQueue: internalQueue)
            let coreSDK = MockCoreSDK(channelState: .attached, internalQueue: internalQueue)

            // Complete sync first
            internalQueue.ably_syncNoDeadlock {
                realtimeObjects.nosync_onChannelAttached(hasObjects: false)
            }

            // Call getRoot
            let root = try await realtimeObjects.getRoot(coreSDK: coreSDK)

            // Verify it's the same object as the one in the pool with key "root"
            let poolRoot = realtimeObjects.testsOnly_objectsPool.entries["root"]?.mapValue
            #expect(root as AnyObject === poolRoot as AnyObject)
        }

        // MARK: - RTO1b Tests

        // @spec RTO1b
        @Test(arguments: [.detached, .failed] as [_AblyPluginSupportPrivate.RealtimeChannelState])
        func getRootThrowsIfChannelIsDetachedOrFailed(channelState: _AblyPluginSupportPrivate.RealtimeChannelState) async throws {
            let internalQueue = TestFactories.createInternalQueue()
            let realtimeObjects = InternalDefaultRealtimeObjectsTests.createDefaultRealtimeObjects(internalQueue: internalQueue)
            let coreSDK = MockCoreSDK(channelState: channelState, internalQueue: internalQueue)

            await #expect {
                _ = try await realtimeObjects.getRoot(coreSDK: coreSDK)
            } throws: { error in
                guard let errorInfo = error as? ARTErrorInfo else {
                    return false
                }

                return errorInfo.code == 90001 && errorInfo.statusCode == 400
            }
        }
    }

    /// Tests for `InternalDefaultRealtimeObjects.handleObjectProtocolMessage`, covering RTO8 specification points.
    struct HandleObjectProtocolMessageTests {
        // Tests that when an OBJECT ProtocolMessage is received and there isn't a sync in progress, its operations are handled per RTO8b.
        struct ApplyOperationTests {
            // @specUntested RTO9a1 - There is no way to check that it was a no-op since there are no side effects that this spec point tells us not to apply
            // @specUntested RTO9a2b - There is no way to check that it was a no-op since there are no side effects that this spec point tells us not to apply

            // MARK: - RTO9a3 Tests

            // MARK: - RTO9a2a4 Tests

            // @spec RTO9a2a4 - Tests that when source is LOCAL but the operation is not applied, the serial is not added to appliedOnAckSerials.
            //
            // This covers the scenario where an operation's echo is received from the server (as a channel-sourced OBJECT message)
            // before the ACK arrives from publish. The echo updates the object's siteTimeserials (per RTLC7c / RTLM15c), so when
            // the ACK subsequently triggers a local apply, canApplyOperation (RTLO4a6) rejects it because the serial is not newer
            // than the existing siteTimeserial.
            //
            // It's important that the serial is not added to appliedOnAckSerials in this case, because the echo has already been
            // processed as a normal channel-sourced message, so no future echo will arrive to trigger RTO9a3 to clear it. Adding
            // it would cause appliedOnAckSerials to grow unboundedly.
            @Test
            func doesNotAddToAppliedOnAckSerialsWhenOperationIsNotApplied() async throws {
                let internalQueue = TestFactories.createInternalQueue()
                let realtimeObjects = InternalDefaultRealtimeObjectsTests.createDefaultRealtimeObjects(internalQueue: internalQueue)
                let coreSDK = MockCoreSDK(channelState: .attached, internalQueue: internalQueue)

                // Transition to synced state
                let siteCode = "site1"
                internalQueue.ably_syncNoDeadlock {
                    realtimeObjects.nosync_onChannelAttached(hasObjects: false)
                    realtimeObjects.nosync_setSiteCode(siteCode)
                }

                // Create a counter so we have an object to operate on
                coreSDK.setPublishHandler { messages in
                    PublishResult(serials: messages.map { _ in "serial_create" })
                }
                let counter = try await realtimeObjects.createCounter(count: 42, coreSDK: coreSDK)
                let objectId = counter.testsOnly_objectID

                // Simulate the echo arriving before the ACK: a channel-sourced COUNTER_INC
                // with the same serial that the ACK will return. This sets siteTimeserials
                // on the counter (RTLC7c).
                let incrementSerial = "serial_inc"
                let echoMessage = TestFactories.counterIncOperationMessage(
                    objectId: objectId,
                    number: 5,
                    serial: incrementSerial,
                    siteCode: siteCode,
                )
                internalQueue.ably_syncNoDeadlock {
                    realtimeObjects.nosync_handleObjectProtocolMessage(objectMessages: [echoMessage])
                }

                // Now perform the local increment whose ACK returns the same serial.
                // canApplyOperation (RTLO4a6) will reject it because the serial is not
                // newer than the siteTimeserial that the echo already set.
                coreSDK.setPublishHandler { messages in
                    PublishResult(serials: messages.map { _ in incrementSerial })
                }
                try await counter.increment(amount: 5, coreSDK: coreSDK, realtimeObjects: realtimeObjects)

                // Verify the serial was NOT added to appliedOnAckSerials
                #expect(!realtimeObjects.testsOnly_appliedOnAckSerials.contains(incrementSerial))

                // Verify the increment was only applied once (via the echo), not double-applied
                #expect(try counter.value(coreSDK: coreSDK) == 47)
            }

            // MARK: - RTO9a2a1 Tests

            // @spec RTO9a2a1 - Tests that if necessary it creates an object in the ObjectsPool
            @Test
            func createsObjectInObjectsPoolWhenNecessary() {
                let internalQueue = TestFactories.createInternalQueue()
                let realtimeObjects = InternalDefaultRealtimeObjectsTests.createDefaultRealtimeObjects(internalQueue: internalQueue)
                let objectId = "map:new@123"

                // Verify the object doesn't exist in the pool initially
                let initialPool = realtimeObjects.testsOnly_objectsPool
                #expect(initialPool.entries[objectId] == nil)

                // Create a MAP_SET operation message for a non-existent object
                let operationMessage = TestFactories.mapSetOperationMessage(
                    objectId: objectId,
                    key: "testKey",
                    value: "testValue",
                )

                // Handle the object protocol message
                internalQueue.ably_syncNoDeadlock {
                    realtimeObjects.nosync_handleObjectProtocolMessage(objectMessages: [operationMessage])
                }

                // Verify the object was created in the ObjectsPool (RTO9a2a1)
                let finalPool = realtimeObjects.testsOnly_objectsPool
                #expect(finalPool.entries[objectId] != nil)
            }

            // MARK: - RTO9a2a3 Tests for MAP_CREATE

            // TODO: Understand what to do with OBJECT_DELETE (https://github.com/ably/specification/pull/343#discussion_r2193126548)

            // @specOneOf(1/6) RTO9a2a3 - Tests MAP_CREATE operation application
            @Test
            func appliesMapCreateOperation() throws {
                let internalQueue = TestFactories.createInternalQueue()
                let realtimeObjects = InternalDefaultRealtimeObjectsTests.createDefaultRealtimeObjects(internalQueue: internalQueue)
                let objectId = "map:test@123"

                // Create a map object in the pool first
                let (entryKey, entry) = TestFactories.stringMapEntry(key: "existingKey", value: "existingValue")
                internalQueue.ably_syncNoDeadlock {
                    realtimeObjects.nosync_handleObjectSyncProtocolMessage(
                        objectMessages: [
                            TestFactories.mapObjectMessage(
                                objectId: objectId,
                                siteTimeserials: ["site1": "ts1"],
                                entries: [entryKey: entry],
                            ),
                        ],
                        protocolMessageChannelSerial: nil,
                    )
                }

                // Verify the object exists and has initial data
                let map = try #require(realtimeObjects.testsOnly_objectsPool.entries[objectId]?.mapValue)
                let coreSDK = MockCoreSDK(channelState: .attached, internalQueue: internalQueue)
                let initialValue = try #require(map.get(key: "existingKey", coreSDK: coreSDK, delegate: realtimeObjects)?.stringValue)
                #expect(initialValue == "existingValue")

                // Create a MAP_CREATE operation message
                let (createKey, createEntry) = TestFactories.stringMapEntry(key: "createKey", value: "createValue")
                let operationMessage = TestFactories.mapCreateOperationMessage(
                    objectId: objectId,
                    entries: [createKey: createEntry],
                    serial: "ts2", // Higher than existing "ts1"
                    siteCode: "site1",
                )

                // Handle the object protocol message
                internalQueue.ably_syncNoDeadlock {
                    realtimeObjects.nosync_handleObjectProtocolMessage(objectMessages: [operationMessage])
                }

                // Verify the operation was applied by checking for side effects
                // The full logic of applying the operation is tested in RTLM15; we just check for some of its side effects here
                let finalValue = try #require(map.get(key: "createKey", coreSDK: coreSDK, delegate: realtimeObjects)?.stringValue)
                #expect(finalValue == "createValue")
                #expect(map.testsOnly_createOperationIsMerged)
                #expect(map.testsOnly_siteTimeserials["site1"] == "ts2")
            }

            // MARK: - RTO9a2a3 Tests for MAP_SET

            // @specOneOf(2/6) RTO9a2a3 - Tests MAP_SET operation application
            @Test
            func appliesMapSetOperation() throws {
                let internalQueue = TestFactories.createInternalQueue()
                let realtimeObjects = InternalDefaultRealtimeObjectsTests.createDefaultRealtimeObjects(internalQueue: internalQueue)
                let objectId = "map:test@123"

                // Create a map object in the pool first
                let (entryKey, entry) = TestFactories.stringMapEntry(key: "existingKey", value: "existingValue")
                internalQueue.ably_syncNoDeadlock {
                    realtimeObjects.nosync_handleObjectSyncProtocolMessage(
                        objectMessages: [
                            TestFactories.mapObjectMessage(
                                objectId: objectId,
                                siteTimeserials: ["site1": "ts1"],
                                entries: [entryKey: entry],
                            ),
                        ],
                        protocolMessageChannelSerial: nil,
                    )
                }

                // Verify the object exists and has initial data
                let map = try #require(realtimeObjects.testsOnly_objectsPool.entries[objectId]?.mapValue)
                let coreSDK = MockCoreSDK(channelState: .attached, internalQueue: internalQueue)
                let initialValue = try #require(map.get(key: "existingKey", coreSDK: coreSDK, delegate: realtimeObjects)?.stringValue)
                #expect(initialValue == "existingValue")

                // Create a MAP_SET operation message
                let operationMessage = TestFactories.mapSetOperationMessage(
                    objectId: objectId,
                    key: "existingKey",
                    value: "newValue",
                    serial: "ts2", // Higher than existing "ts1"
                    siteCode: "site1",
                )

                // Handle the object protocol message
                internalQueue.ably_syncNoDeadlock {
                    realtimeObjects.nosync_handleObjectProtocolMessage(objectMessages: [operationMessage])
                }

                // Verify the operation was applied by checking for side effects
                // The full logic of applying the operation is tested in RTLM15; we just check for some of its side effects here
                let finalValue = try #require(map.get(key: "existingKey", coreSDK: coreSDK, delegate: realtimeObjects)?.stringValue)
                #expect(finalValue == "newValue")
                #expect(map.testsOnly_siteTimeserials["site1"] == "ts2")
            }

            // MARK: - RTO9a2a3 Tests for MAP_REMOVE

            // @specOneOf(3/6) RTO9a2a3 - Tests MAP_REMOVE operation application
            @Test
            func appliesMapRemoveOperation() throws {
                let internalQueue = TestFactories.createInternalQueue()
                let realtimeObjects = InternalDefaultRealtimeObjectsTests.createDefaultRealtimeObjects(internalQueue: internalQueue)
                let objectId = "map:test@123"

                // Create a map object in the pool first
                let (entryKey, entry) = TestFactories.stringMapEntry(key: "existingKey", value: "existingValue")
                internalQueue.ably_syncNoDeadlock {
                    realtimeObjects.nosync_handleObjectSyncProtocolMessage(
                        objectMessages: [
                            TestFactories.mapObjectMessage(
                                objectId: objectId,
                                siteTimeserials: ["site1": "ts1"],
                                entries: [entryKey: entry],
                            ),
                        ],
                        protocolMessageChannelSerial: nil,
                    )
                }

                // Verify the object exists and has initial data
                let map = try #require(realtimeObjects.testsOnly_objectsPool.entries[objectId]?.mapValue)
                let coreSDK = MockCoreSDK(channelState: .attached, internalQueue: internalQueue)
                let initialValue = try #require(map.get(key: "existingKey", coreSDK: coreSDK, delegate: realtimeObjects)?.stringValue)
                #expect(initialValue == "existingValue")

                // Create a MAP_REMOVE operation message
                let operationMessage = TestFactories.mapRemoveOperationMessage(
                    objectId: objectId,
                    key: "existingKey",
                    serial: "ts2", // Higher than existing "ts1"
                    siteCode: "site1",
                )

                // Handle the object protocol message
                internalQueue.ably_syncNoDeadlock {
                    realtimeObjects.nosync_handleObjectProtocolMessage(objectMessages: [operationMessage])
                }

                // Verify the operation was applied by checking for side effects
                // The full logic of applying the operation is tested in RTLM15; we just check for some of its side effects here
                let finalValue = try map.get(key: "existingKey", coreSDK: coreSDK, delegate: realtimeObjects)
                #expect(finalValue == nil) // Key should be removed/tombstoned
                #expect(map.testsOnly_siteTimeserials["site1"] == "ts2")
            }

            // MARK: - RTO9a2a3 Tests for COUNTER_CREATE

            // @specOneOf(4/6) RTO9a2a3 - Tests COUNTER_CREATE operation application
            @Test
            func appliesCounterCreateOperation() throws {
                let internalQueue = TestFactories.createInternalQueue()
                let realtimeObjects = InternalDefaultRealtimeObjectsTests.createDefaultRealtimeObjects(internalQueue: internalQueue)
                let objectId = "counter:test@123"

                // Create a counter object in the pool first
                internalQueue.ably_syncNoDeadlock {
                    realtimeObjects.nosync_handleObjectSyncProtocolMessage(
                        objectMessages: [
                            TestFactories.counterObjectMessage(
                                objectId: objectId,
                                siteTimeserials: ["site1": "ts1"],
                                count: 5,
                            ),
                        ],
                        protocolMessageChannelSerial: nil,
                    )
                }

                // Verify the object exists and has initial data
                let counter = try #require(realtimeObjects.testsOnly_objectsPool.entries[objectId]?.counterValue)
                let coreSDK = MockCoreSDK(channelState: .attached, internalQueue: internalQueue)
                let initialValue = try counter.value(coreSDK: coreSDK)
                #expect(initialValue == 5)

                // Create a COUNTER_CREATE operation message
                let operationMessage = TestFactories.counterCreateOperationMessage(
                    objectId: objectId,
                    count: 10,
                    serial: "ts2", // Higher than existing "ts1"
                    siteCode: "site1",
                )

                // Handle the object protocol message
                internalQueue.ably_syncNoDeadlock {
                    realtimeObjects.nosync_handleObjectProtocolMessage(objectMessages: [operationMessage])
                }

                // Verify the operation was applied by checking for side effects
                // The full logic of applying the operation is tested in RTLC7; we just check for some of its side effects here
                let finalValue = try counter.value(coreSDK: coreSDK)
                #expect(finalValue == 15) // 5 + 10 (initial value merged)
                #expect(counter.testsOnly_siteTimeserials["site1"] == "ts2")
            }

            // MARK: - RTO9a2a3 Tests for COUNTER_INC

            // @specOneOf(5/6) RTO9a2a3 - Tests COUNTER_INC operation application
            @Test
            func appliesCounterIncOperation() throws {
                let internalQueue = TestFactories.createInternalQueue()
                let realtimeObjects = InternalDefaultRealtimeObjectsTests.createDefaultRealtimeObjects(internalQueue: internalQueue)
                let objectId = "counter:test@123"

                // Create a counter object in the pool first
                internalQueue.ably_syncNoDeadlock {
                    realtimeObjects.nosync_handleObjectSyncProtocolMessage(
                        objectMessages: [
                            TestFactories.counterObjectMessage(
                                objectId: objectId,
                                siteTimeserials: ["site1": "ts1"],
                                count: 5,
                            ),
                        ],
                        protocolMessageChannelSerial: nil,
                    )
                }

                // Verify the object exists and has initial data
                let counter = try #require(realtimeObjects.testsOnly_objectsPool.entries[objectId]?.counterValue)
                let coreSDK = MockCoreSDK(channelState: .attached, internalQueue: internalQueue)
                let initialValue = try counter.value(coreSDK: coreSDK)
                #expect(initialValue == 5)

                // Create a COUNTER_INC operation message
                let operationMessage = TestFactories.counterIncOperationMessage(
                    objectId: objectId,
                    number: 10,
                    serial: "ts2", // Higher than existing "ts1"
                    siteCode: "site1",
                )

                // Handle the object protocol message
                internalQueue.ably_syncNoDeadlock {
                    realtimeObjects.nosync_handleObjectProtocolMessage(objectMessages: [operationMessage])
                }

                // Verify the operation was applied by checking for side effects
                // The full logic of applying the operation is tested in RTLC7; we just check for some of its side effects here
                let finalValue = try counter.value(coreSDK: coreSDK)
                #expect(finalValue == 15) // 5 + 10
                #expect(counter.testsOnly_siteTimeserials["site1"] == "ts2")
            }

            // MARK: - RTO9a2a3 Tests for MAP_CLEAR

            // @specOneOf(6/6) RTO9a2a3 - Tests MAP_CLEAR operation application
            @Test
            func appliesMapClearOperation() throws {
                let internalQueue = TestFactories.createInternalQueue()
                let realtimeObjects = InternalDefaultRealtimeObjectsTests.createDefaultRealtimeObjects(internalQueue: internalQueue)
                let objectId = "map:test@123"

                // Create a map object in the pool first
                let (entryKey, entry) = TestFactories.stringMapEntry(key: "existingKey", value: "existingValue")
                internalQueue.ably_syncNoDeadlock {
                    realtimeObjects.nosync_handleObjectSyncProtocolMessage(
                        objectMessages: [
                            TestFactories.mapObjectMessage(
                                objectId: objectId,
                                siteTimeserials: ["site1": "ts1"],
                                entries: [entryKey: entry],
                            ),
                        ],
                        protocolMessageChannelSerial: nil,
                    )
                }

                // Verify the object exists and has initial data
                let map = try #require(realtimeObjects.testsOnly_objectsPool.entries[objectId]?.mapValue)
                let coreSDK = MockCoreSDK(channelState: .attached, internalQueue: internalQueue)
                let initialValue = try #require(map.get(key: "existingKey", coreSDK: coreSDK, delegate: realtimeObjects)?.stringValue)
                #expect(initialValue == "existingValue")

                // Create a MAP_CLEAR operation message
                let operationMessage = TestFactories.mapClearOperationMessage(
                    objectId: objectId,
                    serial: "ts2", // Higher than existing "ts1"
                    siteCode: "site1",
                )

                // Handle the object protocol message
                internalQueue.ably_syncNoDeadlock {
                    realtimeObjects.nosync_handleObjectProtocolMessage(objectMessages: [operationMessage])
                }

                // Verify the operation was applied by checking for side effects
                // The full logic of applying the operation is tested in RTLM15; we just check for some of its side effects here
                let finalValue = try map.get(key: "existingKey", coreSDK: coreSDK, delegate: realtimeObjects)
                #expect(finalValue == nil) // Key should be removed by MAP_CLEAR
                #expect(map.testsOnly_clearTimeserial == "ts2")
                #expect(map.testsOnly_siteTimeserials["site1"] == "ts2")
            }
        }

        // Tests that when an OBJECT ProtocolMessage is received during a sync sequence, its operations are buffered per RTO8a and applied after sync completion per RTO5c6.
        struct BufferOperationTests {
            // @spec RTO8a
            // @spec RTO5c6
            @Test
            func buffersObjectOperationsDuringSyncAndAppliesAfterCompletion() async throws {
                let internalQueue = TestFactories.createInternalQueue()
                let realtimeObjects = InternalDefaultRealtimeObjectsTests.createDefaultRealtimeObjects(internalQueue: internalQueue)
                let sequenceId = "seq123"

                // Start sync sequence with first OBJECT_SYNC message
                let (entryKey, entry) = TestFactories.stringMapEntry(key: "existingKey", value: "existingValue")
                let firstSyncMessages = [
                    TestFactories.mapObjectMessage(
                        objectId: "map:1@123",
                        siteTimeserials: ["site1": "ts1"], // Explicit sync data siteCode and serial
                        entries: [entryKey: entry],
                    ),
                ]
                internalQueue.ably_syncNoDeadlock {
                    realtimeObjects.nosync_handleObjectSyncProtocolMessage(
                        objectMessages: firstSyncMessages,
                        protocolMessageChannelSerial: "\(sequenceId):cursor1",
                    )
                }

                // Verify sync sequence is active
                #expect(realtimeObjects.testsOnly_hasSyncSequence)

                // Inject first OBJECT ProtocolMessage during sync (RTO8a)
                let firstObjectMessage = TestFactories.mapSetOperationMessage(
                    objectId: "map:1@123",
                    key: "key1",
                    value: "value1",
                    serial: "ts3", // Higher than sync data "ts1"
                    siteCode: "site1",
                )
                internalQueue.ably_syncNoDeadlock {
                    realtimeObjects.nosync_handleObjectProtocolMessage(objectMessages: [firstObjectMessage])
                }

                // Verify the operation was buffered and not applied yet
                let poolAfterFirstObject = realtimeObjects.testsOnly_objectsPool
                #expect(poolAfterFirstObject.entries["map:1@123"] == nil) // Object not yet created from sync

                // Inject second OBJECT ProtocolMessage during sync (RTO8a)
                let secondObjectMessage = TestFactories.counterIncOperationMessage(
                    objectId: "counter:1@456",
                    number: 10,
                    serial: "ts4", // Higher than sync data "ts2"
                    siteCode: "site1",
                )
                internalQueue.ably_syncNoDeadlock {
                    realtimeObjects.nosync_handleObjectProtocolMessage(objectMessages: [secondObjectMessage])
                }

                // Verify the second operation was also buffered and not applied yet
                let poolAfterSecondObject = realtimeObjects.testsOnly_objectsPool
                #expect(poolAfterSecondObject.entries["counter:1@456"] == nil) // Object not yet created from sync

                // Complete sync sequence with final OBJECT_SYNC message
                let finalSyncMessages = [
                    TestFactories.counterObjectMessage(
                        objectId: "counter:1@456",
                        siteTimeserials: ["site1": "ts2"],
                        count: 5,
                    ),
                ]
                internalQueue.ably_syncNoDeadlock {
                    realtimeObjects.nosync_handleObjectSyncProtocolMessage(
                        objectMessages: finalSyncMessages,
                        protocolMessageChannelSerial: "\(sequenceId):", // Empty cursor indicates end
                    )
                }

                // Verify sync sequence is cleared
                #expect(!realtimeObjects.testsOnly_hasSyncSequence)

                // Verify all objects were applied to pool from sync
                let finalPool = realtimeObjects.testsOnly_objectsPool
                let map = try #require(finalPool.entries["map:1@123"]?.mapValue)
                let counter = try #require(finalPool.entries["counter:1@456"]?.counterValue)

                // Note: the siteTimeserials check here is a side-effect of RTLM15c and RTLC7c that shows us that the CHANNEL source is being used per RTO5c6

                // Verify the buffered operations were applied after sync completion (RTO5c6)
                // Check that MAP_SET operation was applied to the map
                let coreSDK = MockCoreSDK(channelState: .attached, internalQueue: internalQueue)
                let mapValue = try #require(map.get(key: "key1", coreSDK: coreSDK, delegate: realtimeObjects)?.stringValue)
                #expect(mapValue == "value1")
                #expect(map.testsOnly_siteTimeserials["site1"] == "ts3")

                // Check that COUNTER_INC operation was applied to the counter
                let counterValue = try counter.value(coreSDK: coreSDK)
                #expect(counterValue == 15) // 5 (from sync) + 10 (from buffered operation)
                #expect(counter.testsOnly_siteTimeserials["site1"] == "ts4")
            }
        }
    }

    /// Tests for `InternalDefaultRealtimeObjects.createMap`, covering RTO11 specification points (these are largely a smoke test, the rest being tested in ObjectCreationHelpers tests)
    struct CreateMapTests {
        // @spec RTO11d
        @Test(arguments: [.detached, .failed, .suspended] as [_AblyPluginSupportPrivate.RealtimeChannelState])
        func throwsIfChannelIsInInvalidState(channelState: _AblyPluginSupportPrivate.RealtimeChannelState) async throws {
            let internalQueue = TestFactories.createInternalQueue()
            let realtimeObjects = InternalDefaultRealtimeObjectsTests.createDefaultRealtimeObjects(internalQueue: internalQueue)
            let coreSDK = MockCoreSDK(channelState: channelState, internalQueue: internalQueue)
            let entries: [String: InternalLiveMapValue] = ["testKey": .string("testValue")]

            await #expect {
                _ = try await realtimeObjects.createMap(entries: entries, coreSDK: coreSDK)
            } throws: { error in
                guard let errorInfo = error as? ARTErrorInfo else {
                    return false
                }
                return errorInfo.code == 90001 && errorInfo.statusCode == 400
            }
        }

        // @spec RTO11f7
        // @spec RTO11i
        @Test
        func publishesObjectMessageAndCreatesMap() async throws {
            let internalQueue = TestFactories.createInternalQueue()
            let realtimeObjects = InternalDefaultRealtimeObjectsTests.createDefaultRealtimeObjects(internalQueue: internalQueue)
            let coreSDK = MockCoreSDK(channelState: .attached, serverTime: .init(timeIntervalSince1970: 1_754_042_434), internalQueue: internalQueue)

            // Transition to synced state (required for publishAndApply)
            internalQueue.ably_syncNoDeadlock {
                realtimeObjects.nosync_onChannelAttached(hasObjects: false)
                realtimeObjects.nosync_setSiteCode("site1")
            }

            // Track published messages
            var publishedMessages: [ProtocolTypes.OutboundObjectMessage] = []
            coreSDK.setPublishHandler { messages in
                publishedMessages.append(contentsOf: messages)
                return PublishResult(serials: messages.map { _ in "serial_\(UUID().uuidString)" })
            }

            // Call createMap
            let returnedMap = try await realtimeObjects.createMap(
                entries: [
                    "stringKey": .string("stringValue"),
                ],
                coreSDK: coreSDK,
            )

            // Verify ObjectMessage was published (RTO11i)
            #expect(publishedMessages.count == 1)
            let publishedMessage = publishedMessages[0]

            // Sense check of ObjectMessage structure per RTO11f9-13
            #expect(publishedMessage.operation?.action == .known(.mapCreate))
            let objectID = try #require(publishedMessage.operation?.objectId)
            #expect(objectID.hasPrefix("map:"))
            #expect(objectID.contains("1754042434000")) // check contains the server timestamp in milliseconds per RTO11f7
            #expect(publishedMessage.operation?.mapCreateWithObjectId != nil)
            let mapInitialValueString = try #require(publishedMessage.operation?.mapCreateWithObjectId?.initialValue)
            let mapInitialValue = try #require(try JSONObjectOrArray(jsonString: mapInitialValueString).objectValue)
            #expect(mapInitialValue["entries"] == .object(["stringKey": .object(["data": .object(["string": "stringValue"])])]))

            // Sense check that create op was applied locally by publishAndApply (
            #expect(returnedMap.testsOnly_data == ["stringKey": InternalObjectsMapEntry(data: ProtocolTypes.ObjectData(string: "stringValue"))])
            #expect(realtimeObjects.testsOnly_objectsPool.entries[objectID]?.mapValue === returnedMap)
        }

        // @specUntested RTO11h3d - This spec point covers a logic error so let's not try to test

        // @spec RTO11f14b
        @Test
        func withNoEntriesArgumentCreatesEmptyMap() async throws {
            let internalQueue = TestFactories.createInternalQueue()
            let realtimeObjects = InternalDefaultRealtimeObjectsTests.createDefaultRealtimeObjects(internalQueue: internalQueue)
            let coreSDK = MockCoreSDK(channelState: .attached, internalQueue: internalQueue)

            // Transition to synced state (required for publishAndApply)
            internalQueue.ably_syncNoDeadlock {
                realtimeObjects.nosync_onChannelAttached(hasObjects: false)
                realtimeObjects.nosync_setSiteCode("site1")
            }

            // Track published messages
            var publishedMessages: [ProtocolTypes.OutboundObjectMessage] = []
            coreSDK.setPublishHandler { messages in
                publishedMessages.append(contentsOf: messages)
                return PublishResult(serials: messages.map { _ in "serial_\(UUID().uuidString)" })
            }

            // Call createMap with no entries
            let result = try await realtimeObjects.createMap(entries: [:], coreSDK: coreSDK)

            // Verify ObjectMessage was published
            #expect(publishedMessages.count == 1)
            let publishedMessage = publishedMessages[0]

            // Verify map operation has empty entries per RTO11f14b
            let mapInitialValueString = try #require(publishedMessage.operation?.mapCreateWithObjectId?.initialValue)
            let mapInitialValue = try #require(try JSONObjectOrArray(jsonString: mapInitialValueString).objectValue)
            #expect(mapInitialValue["entries"] == .object([:]))

            // Verify LiveMap has expected entries
            #expect(result.testsOnly_data.isEmpty)
        }

        // @spec RTO11h2
        @Test
        func returnsExistingObjectIfAlreadyInPool() async throws {
            let internalQueue = TestFactories.createInternalQueue()
            let realtimeObjects = InternalDefaultRealtimeObjectsTests.createDefaultRealtimeObjects(internalQueue: internalQueue)
            let coreSDK = MockCoreSDK(channelState: .attached, internalQueue: internalQueue)

            // Transition to synced state (required for publishAndApply)
            internalQueue.ably_syncNoDeadlock {
                realtimeObjects.nosync_onChannelAttached(hasObjects: false)
                realtimeObjects.nosync_setSiteCode("site1")
            }

            // Track published messages and the generated objectId
            var publishedMessages: [ProtocolTypes.OutboundObjectMessage] = []
            var maybeGeneratedObjectID: String?
            var maybeExistingObject: AnyObject?

            coreSDK.setPublishHandler { messages in
                publishedMessages.append(contentsOf: messages)

                // Extract the generated objectId from the published message
                if let objectID = messages.first?.operation?.objectId {
                    maybeGeneratedObjectID = objectID

                    // Create an object with this exact ID in the pool
                    // This simulates the object already existing when createMap tries to get it, before the publish operation completes (e.g. because it has been populated by receipt of an OBJECT)
                    maybeExistingObject = realtimeObjects.testsOnly_createZeroValueLiveObject(forObjectID: objectID)?.mapValue
                }
                return PublishResult(serials: messages.map { _ in nil })
            }

            // Call createMap - the publishHandler will create the object with the generated ID
            let result = try await realtimeObjects.createMap(entries: ["testKey": .string("testValue")], coreSDK: coreSDK)

            // Verify ObjectMessage was published
            #expect(publishedMessages.count == 1)

            // Extract the variables that we populated based on the generated object ID
            let generatedObjectID = try #require(maybeGeneratedObjectID)
            let existingObject = try #require(maybeExistingObject)

            // Verify the returned object is the same as the existing one
            #expect(result === existingObject)

            // Check that the existing object has not been replaced in the pool
            #expect(realtimeObjects.testsOnly_objectsPool.entries[generatedObjectID]?.mapValue === existingObject)
        }
    }

    /// Tests for `InternalDefaultRealtimeObjects.createCounter`, covering RTO12 specification points (these are largely a smoke test, the rest being tested in ObjectCreationHelpers tests)
    struct CreateCounterTests {
        // @spec RTO12d
        @Test(arguments: [.detached, .failed, .suspended] as [_AblyPluginSupportPrivate.RealtimeChannelState])
        func throwsIfChannelIsInInvalidState(channelState: _AblyPluginSupportPrivate.RealtimeChannelState) async throws {
            let internalQueue = TestFactories.createInternalQueue()
            let realtimeObjects = InternalDefaultRealtimeObjectsTests.createDefaultRealtimeObjects(internalQueue: internalQueue)
            let coreSDK = MockCoreSDK(channelState: channelState, internalQueue: internalQueue)

            await #expect {
                _ = try await realtimeObjects.createCounter(count: 10.5, coreSDK: coreSDK)
            } throws: { error in
                guard let errorInfo = error as? ARTErrorInfo else {
                    return false
                }
                return errorInfo.code == 90001 && errorInfo.statusCode == 400
            }
        }

        // @spec RTO12f5
        // @spec RTO12i
        @Test
        func publishesObjectMessageAndCreatesCounter() async throws {
            let internalQueue = TestFactories.createInternalQueue()
            let realtimeObjects = InternalDefaultRealtimeObjectsTests.createDefaultRealtimeObjects(internalQueue: internalQueue)
            let coreSDK = MockCoreSDK(channelState: .attached, serverTime: .init(timeIntervalSince1970: 1_754_042_434), internalQueue: internalQueue)

            // Transition to synced state (required for publishAndApply)
            internalQueue.ably_syncNoDeadlock {
                realtimeObjects.nosync_onChannelAttached(hasObjects: false)
                realtimeObjects.nosync_setSiteCode("site1")
            }

            // Track published messages
            var publishedMessages: [ProtocolTypes.OutboundObjectMessage] = []
            coreSDK.setPublishHandler { messages in
                publishedMessages.append(contentsOf: messages)
                return PublishResult(serials: messages.map { _ in "serial_\(UUID().uuidString)" })
            }

            // Call createCounter
            let returnedCounter = try await realtimeObjects.createCounter(count: 10.5, coreSDK: coreSDK)

            // Verify ObjectMessage was published (RTO12i)
            #expect(publishedMessages.count == 1)
            let publishedMessage = publishedMessages[0]

            // Sense check of ObjectMessage structure per RTO12f7-11
            #expect(publishedMessage.operation?.action == .known(.counterCreate))
            let objectID = try #require(publishedMessage.operation?.objectId)
            #expect(objectID.hasPrefix("counter:"))
            #expect(objectID.contains("1754042434000")) // check contains the server timestamp in milliseconds per RTO12f5
            #expect(publishedMessage.operation?.counterCreateWithObjectId != nil)
            let counterInitialValueString = try #require(publishedMessage.operation?.counterCreateWithObjectId?.initialValue)
            let counterInitialValue = try #require(try JSONObjectOrArray(jsonString: counterInitialValueString).objectValue)
            #expect(counterInitialValue["count"] == .number(10.5))

            // Sense check that create op was applied locally by publishAndApply
            #expect(try returnedCounter.value(coreSDK: coreSDK) == 10.5)
            #expect(realtimeObjects.testsOnly_objectsPool.entries[objectID]?.counterValue === returnedCounter)
        }

        // @specUntested RTO12h3d - This spec point covers a logic error so let's not try to test

        // @specOneOf(2/2) RTO12f12a
        @Test
        func withNoEntriesArgumentCreatesWithZeroValue() async throws {
            let internalQueue = TestFactories.createInternalQueue()
            let realtimeObjects = InternalDefaultRealtimeObjectsTests.createDefaultRealtimeObjects(internalQueue: internalQueue)
            let coreSDK = MockCoreSDK(channelState: .attached, internalQueue: internalQueue)

            // Transition to synced state (required for publishAndApply)
            internalQueue.ably_syncNoDeadlock {
                realtimeObjects.nosync_onChannelAttached(hasObjects: false)
                realtimeObjects.nosync_setSiteCode("site1")
            }

            // Track published messages
            var publishedMessages: [ProtocolTypes.OutboundObjectMessage] = []
            coreSDK.setPublishHandler { messages in
                publishedMessages.append(contentsOf: messages)
                return PublishResult(serials: messages.map { _ in "serial_\(UUID().uuidString)" })
            }

            // Call createCounter with no count
            let result = try await realtimeObjects.createCounter(coreSDK: coreSDK)

            // Verify ObjectMessage was published
            #expect(publishedMessages.count == 1)
            let publishedMessage = publishedMessages[0]

            // Verify counter operation has zero count per RTO12f12a
            let counterInitialValueString = try #require(publishedMessage.operation?.counterCreateWithObjectId?.initialValue)
            let counterInitialValue = try #require(try JSONObjectOrArray(jsonString: counterInitialValueString).objectValue)
            #expect(counterInitialValue["count"] == .number(0))

            // Verify LiveCounter has zero value
            #expect(try result.value(coreSDK: coreSDK) == 0)
        }

        // @spec RTO12h2
        @Test
        func returnsExistingObjectIfAlreadyInPool() async throws {
            let internalQueue = TestFactories.createInternalQueue()
            let realtimeObjects = InternalDefaultRealtimeObjectsTests.createDefaultRealtimeObjects(internalQueue: internalQueue)
            let coreSDK = MockCoreSDK(channelState: .attached, internalQueue: internalQueue)

            // Transition to synced state (required for publishAndApply)
            internalQueue.ably_syncNoDeadlock {
                realtimeObjects.nosync_onChannelAttached(hasObjects: false)
                realtimeObjects.nosync_setSiteCode("site1")
            }

            // Track published messages and the generated objectId
            var publishedMessages: [ProtocolTypes.OutboundObjectMessage] = []
            var maybeGeneratedObjectID: String?
            var maybeExistingObject: AnyObject?

            coreSDK.setPublishHandler { messages in
                publishedMessages.append(contentsOf: messages)

                // Extract the generated objectId from the published message
                if let objectID = messages.first?.operation?.objectId {
                    maybeGeneratedObjectID = objectID

                    // Create an object with this exact ID in the pool
                    // This simulates the object already existing when createMap tries to get it, before the publish operation completes (e.g. because it has been populated by receipt of an OBJECT)
                    maybeExistingObject = realtimeObjects.testsOnly_createZeroValueLiveObject(forObjectID: objectID)?.counterValue
                }
                return PublishResult(serials: messages.map { _ in nil })
            }

            // Call createCounter - the publishHandler will create the object with the generated ID
            let result = try await realtimeObjects.createCounter(count: 10.5, coreSDK: coreSDK)

            // Verify ObjectMessage was published
            #expect(publishedMessages.count == 1)

            // Extract the variables that we populated based on the generated object ID
            let generatedObjectID = try #require(maybeGeneratedObjectID)
            let existingObject = try #require(maybeExistingObject)

            // Verify the returned object is the same as the existing one
            #expect(result === existingObject)

            // Check that the existing object has not been replaced in the pool
            #expect(realtimeObjects.testsOnly_objectsPool.entries[generatedObjectID]?.counterValue === existingObject)
        }
    }

    struct SyncEventsTests {
        enum ChannelEvent {
            case attached(hasObjects: Bool)
            case objectSync(channelSerial: String?)
        }

        struct Scenario {
            /// A human-readable description of the test scenario.
            var description: String

            /// The channel events to be applied in sequence.
            var channelEvents: [ChannelEvent]

            /// The expected sync events that the RealtimeObjects should emit, in the order they are expected to be emitted.
            var expectedSyncEvents: [ObjectsEvent]
        }

        // @spec RTO17b
        // @spec RTO4c
        // @spec RTO5e
        // @spec RTO5c8
        @MainActor
        @Test(
            arguments: [
                // 1. ATTACHED with HAS_OBJECTS false

                .init(
                    description: "The first ATTACHED should always provoke a SYNCING even when HAS_OBJECTS is false, so that the SYNCED is preceded by SYNCING",
                    channelEvents: [.attached(hasObjects: false)],
                    expectedSyncEvents: [.syncing, .synced],
                ),

                .init(
                    description: "ATTACHED with HAS_OBJECTS false once SYNCED emits SYNCING and then SYNCED",
                    channelEvents: [.attached(hasObjects: false), .attached(hasObjects: false)],
                    expectedSyncEvents: [
                        .syncing, .synced, // The initial SYNCED
                        .syncing, .synced, // From the subsequent ATTACHED
                    ],
                ),

                .init(
                    description: "If we're in SYNCING awaiting an OBJECT_SYNC but then instead get an ATTACHED with HAS_OBJECTS false, we should emit a SYNCED",
                    channelEvents: [.attached(hasObjects: true), .attached(hasObjects: false)],
                    expectedSyncEvents: [.syncing, .synced],
                ),

                // 2. ATTACHED with HAS_OBJECTS true

                .init(
                    description: "An initial ATTACHED with HAS_OBJECTS true provokes a SYNCING",
                    channelEvents: [.attached(hasObjects: true)],
                    expectedSyncEvents: [.syncing],
                ),

                .init(
                    description: "ATTACHED with HAS_OBJECTS true when SYNCED should provoke another SYNCING, because we're waiting to receive the updated objects in an OBJECT_SYNC",
                    channelEvents: [.attached(hasObjects: false), .attached(hasObjects: true)],
                    expectedSyncEvents: [.syncing, .synced, .syncing],
                ),

                .init(
                    description: "If we're in SYNCING awaiting an OBJECT_SYNC but then instead get another ATTACHED with HAS_OBJECTS true, we should remain SYNCING (i.e. not emit another event)",
                    channelEvents: [.attached(hasObjects: true), .attached(hasObjects: true)],
                    expectedSyncEvents: [.syncing],
                ),

                // 3. OBJECT_SYNC straight after ATTACHED

                .init(
                    description: "A complete multi-message OBJECT_SYNC sequence after ATTACHED emits SYNCING and then SYNCED",
                    channelEvents: [
                        .attached(hasObjects: true),
                        .objectSync(channelSerial: "foo:1"),
                        .objectSync(channelSerial: "foo:2"),
                        .objectSync(channelSerial: "foo:"),
                    ],
                    expectedSyncEvents: [.syncing, .synced],
                ),
                .init(
                    description: "A complete single-message OBJECT_SYNC after ATTACHED emits SYNCING and then SYNCED",
                    channelEvents: [
                        .attached(hasObjects: true),
                        .objectSync(channelSerial: "foo:"),
                    ],
                    expectedSyncEvents: [.syncing, .synced],
                ),
                .init(
                    description: "SYNCED is not emitted midway through a multi-message OBJECT_SYNC sequence",
                    channelEvents: [
                        .attached(hasObjects: true),
                        .objectSync(channelSerial: "foo:1"),
                        .objectSync(channelSerial: "foo:2"),
                    ],
                    expectedSyncEvents: [.syncing],
                ),

                // 4. OBJECT_SYNC when already SYNCED

                .init(
                    description: "A complete multi-message OBJECT_SYNC sequence when already SYNCED emits SYNCING and then SYNCED",
                    channelEvents: [
                        .attached(hasObjects: false), // to get us to SYNCED
                        .objectSync(channelSerial: "foo:1"),
                        .objectSync(channelSerial: "foo:2"),
                        .objectSync(channelSerial: "foo:"),
                    ],
                    expectedSyncEvents: [
                        .syncing, .synced, // The initial SYNCED
                        .syncing, .synced, // From the complete OBJECT_SYNC
                    ],
                ),
                .init(
                    description: "A complete single-message OBJECT_SYNC when already SYNCED emits SYNCING and then SYNCED",
                    channelEvents: [
                        .attached(hasObjects: false), // to get us to SYNCED
                        .objectSync(channelSerial: "foo:"),
                    ],
                    expectedSyncEvents: [
                        .syncing, .synced, // The initial SYNCED
                        .syncing, .synced, // From the complete OBJECT_SYNC
                    ],
                ),

                // 5. New sync sequence in the middle of a sync sequence

                .init(
                    description: "A new OBJECT_SYNC sequence in the middle of a sync sequence does not provoke another SYNCING",
                    channelEvents: [
                        .attached(hasObjects: true),
                        .objectSync(channelSerial: "foo:1"),
                        .objectSync(channelSerial: "foo:2"),
                        .objectSync(channelSerial: "bar:1"),
                    ],
                    expectedSyncEvents: [.syncing],
                ),
            ] as [Scenario],
        )
        func emitsCorrectSyncEvents(scenario: Scenario) async throws {
            // Given: An InternalDefaultRealtimeObjects
            let internalQueue = TestFactories.createInternalQueue()
            let realtimeObjects = InternalDefaultRealtimeObjectsTests.createDefaultRealtimeObjects(internalQueue: internalQueue)

            var receivedSyncEvents: [ObjectsEvent] = []
            for event in [ObjectsEvent.syncing, .synced] {
                realtimeObjects.on(event: event) { _ in
                    MainActor.assumeIsolated {
                        receivedSyncEvents.append(event)
                    }
                }
            }

            // When: The sequence of channel events described by the scenario is received
            internalQueue.ably_syncNoDeadlock {
                for channelEvent in scenario.channelEvents {
                    switch channelEvent {
                    case let .attached(hasObjects):
                        realtimeObjects.nosync_onChannelAttached(hasObjects: hasObjects)
                    case let .objectSync(channelSerial):
                        realtimeObjects.nosync_handleObjectSyncProtocolMessage(
                            objectMessages: [],
                            protocolMessageChannelSerial: channelSerial,
                        )
                    }
                }
            }

            // Give event callbacks a chance to happen on the main queue
            await Task { @MainActor in }.value

            // Then: It emits the expected sequence of sync events
            #expect(receivedSyncEvents == scenario.expectedSyncEvents)
        }
    }

    /// Tests for `nosync_publishAndApply`, covering RTO20 specification points.
    struct PublishAndApplyTests {
        // @spec RTO20b
        @Test
        func publishFailurePropagatesError() async throws {
            let internalQueue = TestFactories.createInternalQueue()
            let realtimeObjects = InternalDefaultRealtimeObjectsTests.createDefaultRealtimeObjects(internalQueue: internalQueue)
            let coreSDK = MockCoreSDK(channelState: .attached, internalQueue: internalQueue)

            // Configure publish to throw an error
            let publishError = ARTErrorInfo.create(withCode: 40000, message: "publish failed")
            coreSDK.setPublishHandler { _ throws(ARTErrorInfo) in
                throw publishError
            }

            let thrownError = try await #require(throws: ARTErrorInfo.self) {
                try await realtimeObjects.createMap(entries: ["key": .string("value")], coreSDK: coreSDK)
            }
            #expect(thrownError === publishError)
        }

        // @spec RTO20c1
        @Test
        func missingSiteCodeSkipsLocalApply() async throws {
            let internalQueue = TestFactories.createInternalQueue()
            let realtimeObjects = InternalDefaultRealtimeObjectsTests.createDefaultRealtimeObjects(internalQueue: internalQueue)
            let coreSDK = MockCoreSDK(channelState: .attached, internalQueue: internalQueue)

            // Transition to synced state without setting siteCode
            internalQueue.ably_syncNoDeadlock {
                realtimeObjects.nosync_onChannelAttached(hasObjects: false)
            }

            coreSDK.setPublishHandler { messages in
                PublishResult(serials: messages.map { _ in "serial_abc" })
            }

            // The publish succeeds, but the local apply is skipped because siteCode is
            // missing. createMap then fails because the object isn't in the pool.
            let error = try await #require(throws: ARTErrorInfo.self) {
                try await realtimeObjects.createMap(entries: ["key": .string("value")], coreSDK: coreSDK)
            }
            #expect(error.code == 50000)
            #expect(error.statusCode == 500)
        }

        // @spec RTO20c2
        @Test
        func mismatchedSerialsLengthSkipsLocalApply() async throws {
            let internalQueue = TestFactories.createInternalQueue()
            let realtimeObjects = InternalDefaultRealtimeObjectsTests.createDefaultRealtimeObjects(internalQueue: internalQueue)
            let coreSDK = MockCoreSDK(channelState: .attached, internalQueue: internalQueue)

            // Transition to synced state
            internalQueue.ably_syncNoDeadlock {
                realtimeObjects.nosync_onChannelAttached(hasObjects: false)
                realtimeObjects.nosync_setSiteCode("site1")
            }

            // Return wrong number of serials
            coreSDK.setPublishHandler { _ in
                PublishResult(serials: ["serial1", "serial2"])
            }

            // The publish succeeds, but the local apply is skipped because the serials
            // length doesn't match. createMap then fails because the object isn't in the pool.
            let error = try await #require(throws: ARTErrorInfo.self) {
                try await realtimeObjects.createMap(entries: ["key": .string("value")], coreSDK: coreSDK)
            }
            #expect(error.code == 50000)
            #expect(error.statusCode == 500)
        }

        // @spec RTO20d1
        @Test
        func nullSerialSkipsLocalApplication() async throws {
            let internalQueue = TestFactories.createInternalQueue()
            let realtimeObjects = InternalDefaultRealtimeObjectsTests.createDefaultRealtimeObjects(internalQueue: internalQueue)
            let coreSDK = MockCoreSDK(channelState: .attached, internalQueue: internalQueue)

            // Transition to synced state
            internalQueue.ably_syncNoDeadlock {
                realtimeObjects.nosync_onChannelAttached(hasObjects: false)
                realtimeObjects.nosync_setSiteCode("site1")
            }

            // Pre-create a map in the pool so that createMap's RTO11h2 lookup succeeds
            // even when the operation is skipped due to nil serial
            var preCreatedObjectID: String?
            coreSDK.setPublishHandler { messages in
                // Extract the generated objectId and pre-create the object in the pool
                if let objectID = messages.first?.operation?.objectId {
                    preCreatedObjectID = objectID
                    _ = realtimeObjects.testsOnly_createZeroValueLiveObject(forObjectID: objectID)
                }
                // Return nil serial (conflation) — RTO20d1 says the operation should be skipped
                return PublishResult(serials: [nil])
            }

            let returnedMap = try await realtimeObjects.createMap(entries: ["key": .string("value")], coreSDK: coreSDK)

            let objectID = try #require(preCreatedObjectID)

            // The map exists in the pool (pre-created) but its data should be empty because
            // the MAP_CREATE was never applied locally (serial was nil)
            #expect(returnedMap.testsOnly_data.isEmpty)
            #expect(realtimeObjects.testsOnly_objectsPool.entries[objectID]?.mapValue === returnedMap)
        }

        // @spec RTO20b
        // @spec RTO20d2
        // @spec RTO20d2a
        // @spec RTO20d2b
        // @spec RTO20d3
        // @spec RTO20f
        @Test
        func constructsSyntheticMessageAndAppliesWithLocalSource() async throws {
            let internalQueue = TestFactories.createInternalQueue()
            let realtimeObjects = InternalDefaultRealtimeObjectsTests.createDefaultRealtimeObjects(internalQueue: internalQueue)
            let coreSDK = MockCoreSDK(channelState: .attached, internalQueue: internalQueue)

            // Transition to synced state
            let serial = "serial_abc"
            let siteCode = "site1"
            internalQueue.ably_syncNoDeadlock {
                realtimeObjects.nosync_onChannelAttached(hasObjects: false)
                realtimeObjects.nosync_setSiteCode(siteCode)
            }

            // RTO20b: Capture the outbound message published via the core SDK, and return a real serial
            var capturedOutboundMessages: [ProtocolTypes.OutboundObjectMessage] = []
            coreSDK.setPublishHandler { messages in
                capturedOutboundMessages = messages
                return PublishResult(serials: messages.map { _ in serial })
            }

            let returnedMap = try await realtimeObjects.createMap(entries: ["key": .string("value")], coreSDK: coreSDK)

            // RTO20b: Verify the outbound message was published with the expected operation
            // and without serial or siteCode (those are populated on the synthetic message)
            let outboundMessage = try #require(capturedOutboundMessages.first)
            let outboundOperation = try #require(outboundMessage.operation)
            #expect(outboundOperation.action == .known(.mapCreate))
            #expect(outboundMessage.serial == nil)
            #expect(outboundMessage.siteCode == nil)

            // RTO20f: The synthetic message was applied (data is present)
            #expect(returnedMap.testsOnly_data == ["key": InternalObjectsMapEntry(data: ProtocolTypes.ObjectData(string: "value"))])

            // RTO20f: The synthetic message was applied with source LOCAL
            // (confirmed because siteTimeserials were not updated, per RTLM15c / RTLC7c)
            #expect(returnedMap.testsOnly_siteTimeserials.isEmpty)

            // RTO20d2a: The serial from PublishResult was used in the synthetic message
            // (confirmed because RTO9a2a4 adds it to appliedOnAckSerials upon successful apply)
            #expect(realtimeObjects.testsOnly_appliedOnAckSerials.contains(serial))

            // RTO20d2b: The siteCode from connectionDetails was used in the synthetic message
            // (confirmed because canApplyOperation (RTLO4a3) requires a non-empty siteCode for
            // the apply to succeed, which it did per the checks above)
        }

        // @spec RTO20e
        @Test
        func waitsForSyncStateToBecomeSynced() async throws {
            let internalQueue = TestFactories.createInternalQueue()
            let realtimeObjects = InternalDefaultRealtimeObjectsTests.createDefaultRealtimeObjects(internalQueue: internalQueue)
            let coreSDK = MockCoreSDK(channelState: .attached, internalQueue: internalQueue)

            // Set siteCode but leave sync state as SYNCING (hasObjects: true triggers SYNCING, and
            // without completing the sync sequence we remain in SYNCING)
            internalQueue.ably_syncNoDeadlock {
                realtimeObjects.nosync_onChannelAttached(hasObjects: true)
                realtimeObjects.nosync_setSiteCode("site1")
            }

            // Simulate the sync completing after the publish ACK.
            coreSDK.setPublishCallbackHandler { messages, callback in
                let result = PublishResult(serials: messages.map { _ in "serial_xyz" })

                internalQueue.async {
                    callback(.success(result))

                    internalQueue.async {
                        realtimeObjects.nosync_handleObjectSyncProtocolMessage(
                            objectMessages: [],
                            protocolMessageChannelSerial: nil,
                        )
                    }
                }
            }
            let returnedCounter = try await realtimeObjects.createCounter(count: 42, coreSDK: coreSDK)

            // Verify the operation was applied
            #expect(try returnedCounter.value(coreSDK: coreSDK) == 42)
        }

        // @spec RTO20e1
        @Test(arguments: [
            _AblyPluginSupportPrivate.RealtimeChannelState.detached,
            _AblyPluginSupportPrivate.RealtimeChannelState.suspended,
            _AblyPluginSupportPrivate.RealtimeChannelState.failed,
        ])
        func channelStateChangeWhileWaitingForSync(channelState: _AblyPluginSupportPrivate.RealtimeChannelState) async throws {
            let internalQueue = TestFactories.createInternalQueue()
            let realtimeObjects = InternalDefaultRealtimeObjectsTests.createDefaultRealtimeObjects(internalQueue: internalQueue)
            let coreSDK = MockCoreSDK(channelState: .attached, internalQueue: internalQueue)

            // Set siteCode but leave sync state as SYNCING
            internalQueue.ably_syncNoDeadlock {
                realtimeObjects.nosync_onChannelAttached(hasObjects: true)
                realtimeObjects.nosync_setSiteCode("site1")
            }

            // Simulate a channel state change arriving after the publish ACK.
            coreSDK.setPublishCallbackHandler { messages, callback in
                let result = PublishResult(serials: messages.map { _ in "serial_xyz" })

                internalQueue.async {
                    callback(.success(result))

                    internalQueue.async {
                        realtimeObjects.nosync_onChannelStateChanged(toState: channelState, reason: nil)
                    }
                }
            }
            let error = try await #require(throws: ARTErrorInfo.self) {
                try await realtimeObjects.createCounter(count: 5, coreSDK: coreSDK)
            }
            #expect(error.code == 92008)
            #expect(error.statusCode == 400)
        }
    }

    /// Tests for `InternalDefaultRealtimeObjects.nosync_onChannelStateChanged`, covering the RTO27
    /// channel-state data lifecycle.
    struct ChannelStateChangeTests {
        /// Seeds `realtimeObjects` with a populated pool: `root` referencing a non-empty nested map
        /// (`map:child@1` with key `k` → `"v"`) and a counter (`counter:child@2` == 42). Uses a
        /// self-contained OBJECT_SYNC so the sync completes immediately (state becomes SYNCED).
        private static func seedPopulatedPool(
            _ realtimeObjects: InternalDefaultRealtimeObjects,
            internalQueue: DispatchQueue,
        ) {
            internalQueue.ably_syncNoDeadlock {
                realtimeObjects.nosync_handleObjectSyncProtocolMessage(
                    objectMessages: [
                        TestFactories.mapObjectMessage(objectId: "root", entries: [
                            "childMap": TestFactories.objectReferenceMapEntry(key: "childMap", objectId: "map:child@1").entry,
                            "childCounter": TestFactories.objectReferenceMapEntry(key: "childCounter", objectId: "counter:child@2").entry,
                        ]),
                        TestFactories.mapObjectMessage(objectId: "map:child@1", entries: [
                            "k": TestFactories.stringMapEntry(key: "k", value: "v").entry,
                        ]),
                        TestFactories.counterObjectMessage(objectId: "counter:child@2", count: 42),
                    ],
                    protocolMessageChannelSerial: nil, // self-contained sync (RTO5a5) — completes immediately
                )
            }
        }

        // @spec RTO27a1
        // @spec RTO27a2
        @Test(arguments: [
            _AblyPluginSupportPrivate.RealtimeChannelState.detached,
            _AblyPluginSupportPrivate.RealtimeChannelState.failed,
        ])
        func detachedOrFailedClearsObjectsData(channelState: _AblyPluginSupportPrivate.RealtimeChannelState) throws {
            let internalQueue = TestFactories.createInternalQueue()
            let realtimeObjects = InternalDefaultRealtimeObjectsTests.createDefaultRealtimeObjects(internalQueue: internalQueue)
            Self.seedPopulatedPool(realtimeObjects, internalQueue: internalQueue)

            // Precondition: pool is populated.
            let pool = realtimeObjects.testsOnly_objectsPool
            #expect(Set(pool.root.testsOnly_data.keys) == ["childMap", "childCounter"])
            let childMap = try #require(pool.entries["map:child@1"]?.mapValue)
            let childCounter = try #require(pool.entries["counter:child@2"]?.counterValue)
            #expect(!childMap.testsOnly_data.isEmpty)
            #expect(childCounter.testsOnly_data == 42)

            // When the channel enters DETACHED / FAILED.
            internalQueue.ably_syncNoDeadlock {
                realtimeObjects.nosync_onChannelStateChanged(toState: channelState, reason: nil)
            }

            // RTO27a1: every object's data is cleared to its zero value, but the objects remain in
            // the pool (only their data is cleared).
            let poolAfter = realtimeObjects.testsOnly_objectsPool
            #expect(poolAfter.entries.count == 3) // root + 2 children still present
            #expect(poolAfter.root.testsOnly_data.isEmpty)
            #expect(try #require(poolAfter.entries["map:child@1"]?.mapValue).testsOnly_data.isEmpty)
            #expect(try #require(poolAfter.entries["counter:child@2"]?.counterValue).testsOnly_data == 0)
            // Root remains the same instance (data cleared in place).
            #expect(poolAfter.root as AnyObject === pool.root as AnyObject)
        }

        // @spec RTO27b
        @Test
        func suspendedRetainsObjectsData() throws {
            let internalQueue = TestFactories.createInternalQueue()
            let realtimeObjects = InternalDefaultRealtimeObjectsTests.createDefaultRealtimeObjects(internalQueue: internalQueue)
            Self.seedPopulatedPool(realtimeObjects, internalQueue: internalQueue)

            // When the channel enters SUSPENDED.
            internalQueue.ably_syncNoDeadlock {
                realtimeObjects.nosync_onChannelStateChanged(toState: .suspended, reason: nil)
            }

            // RTO27b: the stored objects data is retained unchanged.
            let poolAfter = realtimeObjects.testsOnly_objectsPool
            #expect(Set(poolAfter.root.testsOnly_data.keys) == ["childMap", "childCounter"])
            #expect(try !(#require(poolAfter.entries["map:child@1"]?.mapValue).testsOnly_data.isEmpty))
            #expect(try #require(poolAfter.entries["counter:child@2"]?.counterValue).testsOnly_data == 42)
        }

        // RTO27a1 requires the clear to emit no LiveObjectUpdate events.
        // @specPartial RTO27a1 - asserts the "without emitting any LiveObjectUpdate events" clause
        @available(iOS 17.0.0, tvOS 17.0.0, *) // Subscriber uses parameter packs, an iOS 17 / tvOS 17 Swift runtime feature; see Subscriber.swift
        @Test
        func clearOnDetachedEmitsNoUpdateEvents() async throws {
            let internalQueue = TestFactories.createInternalQueue()
            let realtimeObjects = InternalDefaultRealtimeObjectsTests.createDefaultRealtimeObjects(internalQueue: internalQueue)
            Self.seedPopulatedPool(realtimeObjects, internalQueue: internalQueue)

            let pool = realtimeObjects.testsOnly_objectsPool
            let coreSDK = MockCoreSDK(channelState: .attached, internalQueue: internalQueue)

            // Subscribe to root, the nested map and the counter.
            let rootSubscriber = Subscriber<DefaultLiveMapUpdate, SubscribeResponse>(callbackQueue: .main)
            let mapSubscriber = Subscriber<DefaultLiveMapUpdate, SubscribeResponse>(callbackQueue: .main)
            let counterSubscriber = Subscriber<DefaultLiveCounterUpdate, SubscribeResponse>(callbackQueue: .main)
            let childMap = try #require(pool.entries["map:child@1"]?.mapValue)
            let childCounter = try #require(pool.entries["counter:child@2"]?.counterValue)
            try pool.root.subscribe(listener: rootSubscriber.createListener(), coreSDK: coreSDK)
            try childMap.subscribe(listener: mapSubscriber.createListener(), coreSDK: coreSDK)
            try childCounter.subscribe(listener: counterSubscriber.createListener(), coreSDK: coreSDK)

            // When the channel enters DETACHED.
            internalQueue.ably_syncNoDeadlock {
                realtimeObjects.nosync_onChannelStateChanged(toState: .detached, reason: nil)
            }

            // Drain the user callback queue so any (unwanted) callbacks have run.
            await Task { @MainActor in }.value

            // RTO27a1: no update events are emitted by the clear.
            #expect(await rootSubscriber.getInvocations().isEmpty)
            #expect(await mapSubscriber.getInvocations().isEmpty)
            #expect(await counterSubscriber.getInvocations().isEmpty)
        }

        // RTO27a2: a partial multi-ProtocolMessage sync sequence's SyncObjectsPool is discarded.
        // @specPartial RTO27a2 - asserts the in-progress SyncObjectsPool is cleared
        @Test
        func detachedClearsInProgressSyncObjectsPool() {
            let internalQueue = TestFactories.createInternalQueue()
            let realtimeObjects = InternalDefaultRealtimeObjectsTests.createDefaultRealtimeObjects(internalQueue: internalQueue)

            // Start (but do not finish) a multi-ProtocolMessage sync sequence, so a SyncObjectsPool
            // is accumulating.
            internalQueue.ably_syncNoDeadlock {
                realtimeObjects.nosync_handleObjectSyncProtocolMessage(
                    objectMessages: [
                        TestFactories.mapObjectMessage(objectId: "map:sync@1"),
                    ],
                    protocolMessageChannelSerial: "seq1:cursor1", // non-terminal cursor — sync stays in progress
                )
            }
            #expect(realtimeObjects.testsOnly_hasSyncSequence)

            // When the channel enters DETACHED.
            internalQueue.ably_syncNoDeadlock {
                realtimeObjects.nosync_onChannelStateChanged(toState: .detached, reason: nil)
            }

            // RTO27a2: the accumulated SyncObjectsPool (the stored sync sequence) is cleared.
            #expect(!realtimeObjects.testsOnly_hasSyncSequence)
        }

        // Post-clear, a re-attach + OBJECT_SYNC repopulates the pool (RTO27a data loss is recoverable).
        @Test
        func reattachAndSyncRepopulatesAfterClear() throws {
            let internalQueue = TestFactories.createInternalQueue()
            let realtimeObjects = InternalDefaultRealtimeObjectsTests.createDefaultRealtimeObjects(internalQueue: internalQueue)
            Self.seedPopulatedPool(realtimeObjects, internalQueue: internalQueue)

            // Clear via DETACHED.
            internalQueue.ably_syncNoDeadlock {
                realtimeObjects.nosync_onChannelStateChanged(toState: .detached, reason: nil)
            }
            #expect(realtimeObjects.testsOnly_objectsPool.root.testsOnly_data.isEmpty)

            // Re-attach with objects, then complete a fresh OBJECT_SYNC.
            internalQueue.ably_syncNoDeadlock {
                realtimeObjects.nosync_onChannelAttached(hasObjects: true)
                realtimeObjects.nosync_handleObjectSyncProtocolMessage(
                    objectMessages: [
                        TestFactories.mapObjectMessage(objectId: "root", entries: [
                            "childCounter": TestFactories.objectReferenceMapEntry(key: "childCounter", objectId: "counter:child@2").entry,
                        ]),
                        TestFactories.counterObjectMessage(objectId: "counter:child@2", count: 99),
                    ],
                    protocolMessageChannelSerial: nil,
                )
            }

            // The pool is repopulated from the fresh sync.
            let poolAfter = realtimeObjects.testsOnly_objectsPool
            #expect(Set(poolAfter.root.testsOnly_data.keys) == ["childCounter"])
            #expect(try #require(poolAfter.entries["counter:child@2"]?.counterValue).testsOnly_data == 99)
        }
    }

    /// Teardown from `deinit`.
    ///
    /// Regression test for the deinit-on-internal-queue crash found by the objects UTS integration
    /// suites (ably/ably-cocoa#2226): ARC can run the engine's `deinit` *on* the internal queue —
    /// e.g. when the owning `ARTRealtimeChannel` is deallocated during client/channel teardown,
    /// which happens on that queue. The previous blocking `deinit { dispose() }` then tripped
    /// `ably_syncNoDeadlock`'s `.notOnQueue` precondition and crashed (SIGTRAP / EXC_BREAKPOINT).
    /// `deinit` now hops the queue-confined cleanup asynchronously (never sync-blocking its own
    /// queue). This
    /// deinit-on-queue hazard is cocoa-specific (absent in a GC'd runtime).
    struct DisposeTests {
        @Test
        func deallocatingOnInternalQueueDoesNotCrash() async throws {
            let internalQueue = TestFactories.createInternalQueue()
            var objects: InternalDefaultRealtimeObjects? = InternalDefaultRealtimeObjectsTests.createDefaultRealtimeObjects(
                internalQueue: internalQueue,
            )
            // Sanity: it exists before we drop it (also keeps `objects` a genuine last strong ref).
            #expect(objects != nil)

            // Release the last strong reference from *within* the internal queue, reproducing exactly
            // what ARC does when the owning channel is torn down on that queue. Before the fix, the
            // resulting `deinit` → `dispose()` → `withSync` trapped here.
            internalQueue.sync {
                objects = nil
            }

            // Flush the queue so `deinit`'s asynchronous teardown hop has run, then confirm we reached
            // here without crashing. (Waiter-draining semantics are unchanged — `deinit` runs the same
            // `nosync_dispose` as the explicit `dispose()` path, covered by the dispose tests — so this
            // test targets only the reproduction of the crash.)
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                internalQueue.async {
                    continuation.resume()
                }
            }
            #expect(objects == nil)
        }
    }
}
