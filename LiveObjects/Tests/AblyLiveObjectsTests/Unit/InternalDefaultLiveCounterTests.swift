import _AblyPluginSupportPrivate
@testable import AblyLiveObjects
@testable import AblyLiveObjectsTesting
import AblyPubSubDevice
import Foundation
import Testing

struct InternalDefaultLiveCounterTests {
    /// Tests for the `value` property, covering RTLC5 specification points
    struct ValueTests {
        // @spec RTLC5b
        @Test(arguments: [.detached, .failed] as [_AblyPluginSupportPrivate.RealtimeChannelState])
        func valueThrowsIfChannelIsDetachedOrFailed(channelState: _AblyPluginSupportPrivate.RealtimeChannelState) async throws {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let counter = InternalDefaultLiveCounter.createZeroValued(objectID: "arbitrary", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
            let coreSDK = MockCoreSDK(channelState: channelState, internalQueue: internalQueue)

            #expect {
                _ = try counter.value(coreSDK: coreSDK)
            } throws: { error in
                guard let errorInfo = error as? ARTErrorInfo else {
                    return false
                }

                return errorInfo.code == 90001 && errorInfo.statusCode == 400
            }
        }

        // @spec RTLC5c
        @Test
        func valueReturnsCurrentDataWhenChannelIsValid() throws {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let counter = InternalDefaultLiveCounter.createZeroValued(objectID: "arbitrary", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
            let coreSDK = MockCoreSDK(channelState: .attached, internalQueue: internalQueue)

            // Set some test data
            internalQueue.ably_syncNoDeadlock {
                _ = counter.nosync_replaceData(using: TestFactories.counterObjectState(count: 42), objectMessageSerialTimestamp: nil)
            }

            #expect(try counter.value(coreSDK: coreSDK) == 42)
        }
    }

    /// Tests for the `replaceData` method, covering RTLC6 specification points
    struct ReplaceDataTests {
        // @spec RTLC6a
        @Test
        func replacesSiteTimeserials() {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let counter = InternalDefaultLiveCounter.createZeroValued(objectID: "arbitrary", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
            let state = TestFactories.counterObjectState(
                siteTimeserials: ["site1": "ts1"], // Test value
            )
            internalQueue.ably_syncNoDeadlock {
                _ = counter.nosync_replaceData(using: state, objectMessageSerialTimestamp: nil)
            }
            #expect(counter.testsOnly_siteTimeserials == ["site1": "ts1"])
        }

        /// Tests for the case where createOp is not present
        struct WithoutCreateOpTests {
            // @spec RTLC6b - Tests the case without createOp, as RTLC16b takes precedence when createOp exists
            @Test
            func setsCreateOperationIsMergedToFalse() {
                // Given: A counter whose createOperationIsMerged is true
                let logger = TestLogger()
                let internalQueue = TestFactories.createInternalQueue()
                let counter = {
                    let counter = InternalDefaultLiveCounter.createZeroValued(objectID: "arbitrary", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
                    // Test setup: Manipulate counter so that its createOperationIsMerged gets set to true (we need to do this since we want to later assert that it gets set to false, but the default is false).
                    let state = TestFactories.counterObjectState(
                        createOp: TestFactories.objectOperation(
                            action: .known(.counterCreate),
                        ),
                    )
                    internalQueue.ably_syncNoDeadlock {
                        _ = counter.nosync_replaceData(using: state, objectMessageSerialTimestamp: nil)
                    }
                    #expect(counter.testsOnly_createOperationIsMerged)

                    return counter
                }()

                // When:
                let state = TestFactories.counterObjectState(
                    createOp: nil, // Test value - must be nil to test RTLC6b
                )
                internalQueue.ably_syncNoDeadlock {
                    _ = counter.nosync_replaceData(using: state, objectMessageSerialTimestamp: nil)
                }

                // Then:
                #expect(!counter.testsOnly_createOperationIsMerged)
            }

            // @specOneOf(1/4) RTLC6c - count but no createOp
            @Test
            func setsDataToCounterCount() throws {
                let logger = TestLogger()
                let internalQueue = TestFactories.createInternalQueue()
                let counter = InternalDefaultLiveCounter.createZeroValued(objectID: "arbitrary", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
                let coreSDK = MockCoreSDK(channelState: .attaching, internalQueue: internalQueue)
                let state = TestFactories.counterObjectState(
                    count: 42, // Test value
                )
                internalQueue.ably_syncNoDeadlock {
                    _ = counter.nosync_replaceData(using: state, objectMessageSerialTimestamp: nil)
                }
                #expect(try counter.value(coreSDK: coreSDK) == 42)
            }

            // @specOneOf(2/4) RTLC6c - no count, no createOp
            @Test
            func setsDataToZeroWhenCounterCountDoesNotExist() throws {
                let logger = TestLogger()
                let internalQueue = TestFactories.createInternalQueue()
                let counter = InternalDefaultLiveCounter.createZeroValued(objectID: "arbitrary", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
                let coreSDK = MockCoreSDK(channelState: .attaching, internalQueue: internalQueue)
                internalQueue.ably_syncNoDeadlock {
                    _ = counter.nosync_replaceData(using: TestFactories.counterObjectState(
                        count: nil, // Test value - must be nil
                    ), objectMessageSerialTimestamp: nil)
                }

                #expect(try counter.value(coreSDK: coreSDK) == 0)
            }
        }

        /// Tests for RTLC16 (merge initial value from createOp)
        struct WithCreateOpTests {
            // @spec RTLC16 - Tests that replaceData merges initial value when createOp is present
            @Test
            func mergesInitialValueWhenCreateOpPresent() throws {
                let logger = TestLogger()
                let internalQueue = TestFactories.createInternalQueue()
                let counter = InternalDefaultLiveCounter.createZeroValued(objectID: "arbitrary", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
                let coreSDK = MockCoreSDK(channelState: .attaching, internalQueue: internalQueue)
                let state = TestFactories.counterObjectState(
                    createOp: TestFactories.counterCreateOperation(count: 10), // Test value - must exist
                    count: 5, // Test value - must exist
                )
                internalQueue.ably_syncNoDeadlock {
                    _ = counter.nosync_replaceData(using: state, objectMessageSerialTimestamp: nil)
                }
                #expect(try counter.value(coreSDK: coreSDK) == 15) // First sets to 5 (RTLC6c) then adds 10 (RTLC16a)
                #expect(counter.testsOnly_createOperationIsMerged)
            }
        }

        /// Tests for RTLC6h (diff calculation on replaceData)
        struct DiffCalculationTests {
            // @specOneOf(1/2) RTLC6h - Tests that replaceData returns the diff calculated via RTLC14
            @Test
            func returnsCorrectDiffWithoutCreateOp() throws {
                let logger = TestLogger()
                let internalQueue = TestFactories.createInternalQueue()
                let counter = InternalDefaultLiveCounter.createZeroValued(objectID: "arbitrary", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
                let coreSDK = MockCoreSDK(channelState: .attaching, internalQueue: internalQueue)

                // Set initial data to 10
                internalQueue.ably_syncNoDeadlock {
                    _ = counter.nosync_replaceData(using: TestFactories.counterObjectState(count: 10), objectMessageSerialTimestamp: nil)
                }
                #expect(try counter.value(coreSDK: coreSDK) == 10)

                // Replace data with count 25 (no createOp)
                let update = internalQueue.ably_syncNoDeadlock {
                    counter.nosync_replaceData(using: TestFactories.counterObjectState(count: 25), objectMessageSerialTimestamp: nil)
                }

                // RTLC6h: Should return diff from previousData (10) to newData (25) = 15
                #expect(try #require(update.update).amount == 15)
                #expect(try counter.value(coreSDK: coreSDK) == 25)
            }

            // @specOneOf(2/2) RTLC6h - Tests that replaceData returns the diff after merging createOp
            @Test
            func returnsCorrectDiffWithCreateOp() throws {
                let logger = TestLogger()
                let internalQueue = TestFactories.createInternalQueue()
                let counter = InternalDefaultLiveCounter.createZeroValued(objectID: "arbitrary", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
                let coreSDK = MockCoreSDK(channelState: .attaching, internalQueue: internalQueue)

                // Set initial data to 10
                internalQueue.ably_syncNoDeadlock {
                    _ = counter.nosync_replaceData(using: TestFactories.counterObjectState(count: 10), objectMessageSerialTimestamp: nil)
                }
                #expect(try counter.value(coreSDK: coreSDK) == 10)

                // Replace data with count 5 and createOp with count 8
                // This should set data to 5, then add 8 (mergeInitialValue), resulting in 13
                let update = internalQueue.ably_syncNoDeadlock {
                    counter.nosync_replaceData(
                        using: TestFactories.counterObjectState(
                            createOp: TestFactories.counterCreateOperation(count: 8),
                            count: 5,
                        ),
                        objectMessageSerialTimestamp: nil,
                    )
                }

                // RTLC6h: Should return diff from previousData (10) to newData (13) = 3
                #expect(try #require(update.update).amount == 3)
                #expect(try counter.value(coreSDK: coreSDK) == 13)
            }
        }
    }

    /// Tests for the `mergeInitialValue` method, covering RTLC16 specification points
    struct MergeInitialValueTests {
        // @specOneOf(1/3) RTLC16a - with count via counterCreate
        // @specOneOf(1/2) RTLC16c
        @Test
        func addsCounterCountToData() throws {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let counter = InternalDefaultLiveCounter.createZeroValued(objectID: "arbitrary", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
            let coreSDK = MockCoreSDK(channelState: .attaching, internalQueue: internalQueue)

            // Set initial data
            internalQueue.ably_syncNoDeadlock {
                _ = counter.nosync_replaceData(using: TestFactories.counterObjectState(count: 5), objectMessageSerialTimestamp: nil)
            }
            #expect(try counter.value(coreSDK: coreSDK) == 5)

            // Apply merge operation
            let operation = TestFactories.counterCreateOperation(count: 10) // Test value - must exist
            let update = internalQueue.ably_syncNoDeadlock {
                counter.nosync_mergeInitialValue(from: operation)
            }

            #expect(try counter.value(coreSDK: coreSDK) == 15) // 5 + 10

            // Check return value
            #expect(try #require(update.update).amount == 10)
        }

        // @specOneOf(2/3) RTLC16a - with count via counterCreateWithObjectId.derivedFrom
        // @specOneOf(2/2) RTLC16c
        // @spec RTLCV4g5
        @Test
        func addsCounterCountToDataFromDerivedFrom() throws {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let counter = InternalDefaultLiveCounter.createZeroValued(objectID: "arbitrary", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
            let coreSDK = MockCoreSDK(channelState: .attaching, internalQueue: internalQueue)

            // Set initial data
            internalQueue.ably_syncNoDeadlock {
                _ = counter.nosync_replaceData(using: TestFactories.counterObjectState(count: 5), objectMessageSerialTimestamp: nil)
            }
            #expect(try counter.value(coreSDK: coreSDK) == 5)

            // Apply merge operation with counterCreateWithObjectId.derivedFrom (no direct counterCreate)
            let operation = TestFactories.objectOperation(
                action: .known(.counterCreate),
                counterCreateWithObjectId: .init(
                    initialValue: "arbitrary",
                    nonce: "arbitrary",
                    derivedFrom: WireCounterCreate(count: NSNumber(value: 10)),
                ),
            )
            let update = internalQueue.ably_syncNoDeadlock {
                counter.nosync_mergeInitialValue(from: operation)
            }

            #expect(try counter.value(coreSDK: coreSDK) == 15) // 5 + 10

            // Check return value
            #expect(try #require(update.update).amount == 10)
        }

        // @specOneOf(3/3) RTLC16a - no count
        // @spec RTLC16d
        @Test
        func doesNotModifyDataWhenCounterCountDoesNotExist() throws {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let counter = InternalDefaultLiveCounter.createZeroValued(objectID: "arbitrary", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
            let coreSDK = MockCoreSDK(channelState: .attaching, internalQueue: internalQueue)

            // Set initial data
            internalQueue.ably_syncNoDeadlock {
                _ = counter.nosync_replaceData(using: TestFactories.counterObjectState(count: 5), objectMessageSerialTimestamp: nil)
            }
            #expect(try counter.value(coreSDK: coreSDK) == 5)

            // Apply merge operation with no count
            let operation = TestFactories.objectOperation(
                action: .known(.counterCreate),
                counterCreate: nil, // Test value - must be nil
            )
            let update = internalQueue.ably_syncNoDeadlock {
                counter.nosync_mergeInitialValue(from: operation)
            }

            #expect(try counter.value(coreSDK: coreSDK) == 5) // Unchanged

            // Check return value
            #expect(update.isNoop)
        }

        // @spec RTLC16b
        @Test
        func setsCreateOperationIsMergedToTrue() {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let counter = InternalDefaultLiveCounter.createZeroValued(objectID: "arbitrary", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())

            // Apply merge operation
            let operation = TestFactories.counterCreateOperation(count: 10) // Test value - must exist
            internalQueue.ably_syncNoDeadlock {
                _ = counter.nosync_mergeInitialValue(from: operation)
            }

            #expect(counter.testsOnly_createOperationIsMerged)
        }
    }

    /// Tests for `COUNTER_CREATE` operations, covering RTLC8 specification points
    struct CounterCreateOperationTests {
        // @spec RTLC8b
        @Test
        func discardsOperationWhenCreateOperationIsMerged() throws {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let counter = InternalDefaultLiveCounter.createZeroValued(objectID: "arbitrary", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
            let coreSDK = MockCoreSDK(channelState: .attaching, internalQueue: internalQueue)

            // Set initial data and mark create operation as merged
            internalQueue.ably_syncNoDeadlock {
                _ = counter.nosync_replaceData(using: TestFactories.counterObjectState(count: 5), objectMessageSerialTimestamp: nil)
                _ = counter.nosync_mergeInitialValue(from: TestFactories.counterCreateOperation(count: 10))
            }
            #expect(counter.testsOnly_createOperationIsMerged)

            // Try to apply another COUNTER_CREATE operation
            let operation = TestFactories.counterCreateOperation(count: 20)
            let update = counter.testsOnly_applyCounterCreateOperation(operation)

            // Verify the operation was discarded - data unchanged
            #expect(try counter.value(coreSDK: coreSDK) == 15) // 5 + 10, not 5 + 10 + 20

            // Verify return value
            #expect(update.isNoop)
        }

        // @spec RTLC8c
        // @spec RTLC8e
        @Test
        func mergesInitialValue() throws {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let counter = InternalDefaultLiveCounter.createZeroValued(objectID: "arbitrary", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
            let coreSDK = MockCoreSDK(channelState: .attaching, internalQueue: internalQueue)

            // Set initial data but don't mark create operation as merged
            internalQueue.ably_syncNoDeadlock {
                _ = counter.nosync_replaceData(using: TestFactories.counterObjectState(count: 5), objectMessageSerialTimestamp: nil)
            }
            #expect(!counter.testsOnly_createOperationIsMerged)

            // Apply COUNTER_CREATE operation
            let operation = TestFactories.counterCreateOperation(count: 10)
            let update = counter.testsOnly_applyCounterCreateOperation(operation)

            // Verify the operation was applied - initial value merged. (The full logic of RTLC16 is tested elsewhere; we just check for some of its side effects here.)
            #expect(try counter.value(coreSDK: coreSDK) == 15) // 5 + 10
            #expect(counter.testsOnly_createOperationIsMerged)

            // Verify return value per RTLC8e
            #expect(try #require(update.update).amount == 10)
        }
    }

    /// Tests for `COUNTER_INC` operations, covering RTLC9 specification points
    struct CounterIncOperationTests {
        // @spec RTLC9f
        // @spec RTLC9g
        // @spec RTLC9h
        @Test(
            arguments: [
                (
                    operation: TestFactories.counterInc(number: 10),
                    expectedValue: 15.0, // 5 + 10
                    expectedUpdate: .update(.init(amount: 10)) // RTLC9g
                ),
                (
                    operation: nil as WireCounterInc?,
                    expectedValue: 5.0, // unchanged
                    expectedUpdate: .noop // RTLC9h
                ),
            ] as [(operation: WireCounterInc?, expectedValue: Double, expectedUpdate: LiveObjectUpdate<DefaultLiveCounterUpdate>)],
        )
        func addsAmountToData(operation: WireCounterInc?, expectedValue: Double, expectedUpdate: LiveObjectUpdate<DefaultLiveCounterUpdate>) throws {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let counter = InternalDefaultLiveCounter.createZeroValued(objectID: "arbitrary", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
            let coreSDK = MockCoreSDK(channelState: .attaching, internalQueue: internalQueue)

            // Set initial data
            internalQueue.ably_syncNoDeadlock {
                _ = counter.nosync_replaceData(using: TestFactories.counterObjectState(count: 5), objectMessageSerialTimestamp: nil)
            }
            #expect(try counter.value(coreSDK: coreSDK) == 5)

            // Apply COUNTER_INC operation
            let update = counter.testsOnly_applyCounterIncOperation(operation)

            // Verify the operation was applied correctly
            #expect(try counter.value(coreSDK: coreSDK) == expectedValue)

            // Verify return value
            #expect(update == expectedUpdate)
        }
    }

    /// Tests for the `apply(_ operation:, …)` method, covering RTLC7 specification points
    struct ApplyOperationTests {
        // @spec RTLC7b - Tests that an operation does not get applied when canApplyOperation returns nil
        @Test
        func discardsOperationWhenCannotBeApplied() throws {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let counter = InternalDefaultLiveCounter.createZeroValued(objectID: "arbitrary", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
            let coreSDK = MockCoreSDK(channelState: .attaching, internalQueue: internalQueue)

            // Set up the counter with an existing site timeserial that will cause the operation to be discarded
            internalQueue.ably_syncNoDeadlock {
                _ = counter.nosync_replaceData(using: TestFactories.counterObjectState(
                    siteTimeserials: ["site1": "ts2"], // Existing serial "ts2"
                    count: 5,
                ), objectMessageSerialTimestamp: nil)
            }

            let operation = TestFactories.objectOperation(
                action: .known(.counterInc),
                counterInc: TestFactories.counterInc(number: 10),
            )
            var pool = ObjectsPool(logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())

            // Apply operation with serial "ts1" which is lexicographically less than existing "ts2" and thus will be applied per RTLO4a (this is a non-pathological case of RTOL4a, that spec point being fully tested elsewhere)
            let applied = internalQueue.ably_syncNoDeadlock {
                counter.nosync_apply(
                    operation,
                    source: .channel,
                    objectMessage: TestFactories.inboundObjectMessage(serial: "ts1", siteCode: "site1"), // Less than existing "ts2"
                    objectsPool: &pool,
                )
            }
            #expect(applied == nil)

            // Check that the COUNTER_INC side-effects didn't happen:
            // Verify the operation was discarded - data unchanged (should still be 5 from creation)
            #expect(try counter.value(coreSDK: coreSDK) == 5)
            // Verify site timeserials unchanged
            #expect(counter.testsOnly_siteTimeserials == ["site1": "ts2"])
        }

        // @specOneOf(1/2) RTLC7c - We test this spec point for each possible operation
        // @spec RTLC7d1 - Tests COUNTER_CREATE operation application
        // @spec RTLC7d1a
        // @spec RTLC7d1b
        @available(iOS 17.0.0, tvOS 17.0.0, *)
        @Test
        func appliesCounterCreateOperation() async throws {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let counter = InternalDefaultLiveCounter.createZeroValued(objectID: "arbitrary", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
            let coreSDK = MockCoreSDK(channelState: .attaching, internalQueue: internalQueue)

            let subscriber = Subscriber<DefaultLiveCounterUpdate, SubscribeResponse>(callbackQueue: .main)
            try counter.subscribe(listener: subscriber.createListener(), coreSDK: coreSDK)

            let operation = TestFactories.counterCreateOperation(count: 15)
            var pool = ObjectsPool(logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())

            // Apply COUNTER_CREATE operation
            let message = TestFactories.inboundObjectMessage(serial: "ts1", siteCode: "site1")
            let applied = internalQueue.ably_syncNoDeadlock {
                counter.nosync_apply(
                    operation,
                    source: .channel,
                    objectMessage: message,
                    objectsPool: &pool,
                )
            }
            #expect(applied != nil)

            // Verify the operation was applied - initial value merged (the full logic of RTLC8 is tested elsewhere; we just check for some of its side effects here)
            #expect(try counter.value(coreSDK: coreSDK) == 15)
            #expect(counter.testsOnly_createOperationIsMerged)
            // Verify RTLC7c side-effect: site timeserial was updated
            #expect(counter.testsOnly_siteTimeserials == ["site1": "ts1"])

            // Verify update was emitted per RTLC7d1a, carrying the stamped source message (RTLO4b4d)
            let subscriberInvocations = await subscriber.getInvocations()
            #expect(subscriberInvocations.map(\.0) == [.init(amount: 15, objectMessage: message)])
        }

        // @specOneOf(2/2) RTLC7c - We test this spec point for each possible operation
        // @spec RTLC7d5 - Tests COUNTER_INC operation application
        // @spec RTLC7d5a
        // @spec RTLC7d5b
        @available(iOS 17.0.0, tvOS 17.0.0, *)
        @Test
        func appliesCounterIncOperation() async throws {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let counter = InternalDefaultLiveCounter.createZeroValued(objectID: "arbitrary", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
            let coreSDK = MockCoreSDK(channelState: .attaching, internalQueue: internalQueue)

            let subscriber = Subscriber<DefaultLiveCounterUpdate, SubscribeResponse>(callbackQueue: .main)
            try counter.subscribe(listener: subscriber.createListener(), coreSDK: coreSDK)

            // Set initial data
            internalQueue.ably_syncNoDeadlock {
                _ = counter.nosync_replaceData(using: TestFactories.counterObjectState(siteTimeserials: [:], count: 5), objectMessageSerialTimestamp: nil)
            }
            #expect(try counter.value(coreSDK: coreSDK) == 5)

            let operation = TestFactories.objectOperation(
                action: .known(.counterInc),
                counterInc: TestFactories.counterInc(number: 10),
            )
            var pool = ObjectsPool(logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())

            // Apply COUNTER_INC operation
            let message = TestFactories.inboundObjectMessage(serial: "ts1", siteCode: "site1")
            let applied = internalQueue.ably_syncNoDeadlock {
                counter.nosync_apply(
                    operation,
                    source: .channel,
                    objectMessage: message,
                    objectsPool: &pool,
                )
            }
            #expect(applied != nil)

            // Verify the operation was applied - amount added to data (the full logic of RTLC9 is tested elsewhere; we just check for some of its side effects here)
            #expect(try counter.value(coreSDK: coreSDK) == 15) // 5 + 10
            // Verify RTLC7c side-effect: site timeserial was updated
            #expect(counter.testsOnly_siteTimeserials == ["site1": "ts1"])

            // Verify update was emitted per RTLC7d5a, carrying the stamped source message (RTLO4b4d)
            let subscriberInvocations = await subscriber.getInvocations()
            #expect(subscriberInvocations.map(\.0) == [.init(amount: 10, objectMessage: message)])
        }
    }

    /// Tests for the `increment` method, covering RTLC12 specification points
    struct IncrementTests {
        // @spec RTLC12c
        @Test(arguments: [.detached, .failed, .suspended] as [_AblyPluginSupportPrivate.RealtimeChannelState])
        func throwsErrorForInvalidChannelState(channelState: _AblyPluginSupportPrivate.RealtimeChannelState) async throws {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let counter = InternalDefaultLiveCounter.createZeroValued(objectID: "arbitrary", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
            let coreSDK = MockCoreSDK(channelState: channelState, internalQueue: internalQueue)
            let realtimeObjects = MockRealtimeObjects()

            await #expect {
                try await counter.increment(amount: 10, coreSDK: coreSDK, realtimeObjects: realtimeObjects)
            } throws: { error in
                guard let errorInfo = error as? ARTErrorInfo else {
                    return false
                }

                return errorInfo.code == 90001 && errorInfo.statusCode == 400
            }
        }

        // @spec RTLC12e2
        // @spec RTLC12e3
        // @spec RTLC12e5
        // @spec RTLC12g
        @Test
        func publishesCorrectObjectMessage() async throws {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let counter = InternalDefaultLiveCounter.createZeroValued(objectID: "counter:test@123", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
            let coreSDK = MockCoreSDK(channelState: .attached, internalQueue: internalQueue)
            let realtimeObjects = MockRealtimeObjects()

            var publishedMessages: [ProtocolTypes.OutboundObjectMessage] = []
            realtimeObjects.setPublishAndApplyHandler { messages in
                publishedMessages.append(contentsOf: messages)
                return .success(())
            }

            try await counter.increment(amount: 10.5, coreSDK: coreSDK, realtimeObjects: realtimeObjects)

            let expectedMessage = ProtocolTypes.OutboundObjectMessage(
                operation: ProtocolTypes.ObjectOperation(
                    // RTLC12e2
                    action: .known(.counterInc),
                    // RTLC12e3
                    objectId: "counter:test@123",
                    // RTLC12e5
                    counterInc: WireCounterInc(number: NSNumber(value: 10.5)),
                ),
            )
            // RTLC12g
            #expect(publishedMessages.count == 1)
            #expect(publishedMessages[0] == expectedMessage)
        }

        @Test
        func throwsErrorWhenPublishFails() async throws {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let counter = InternalDefaultLiveCounter.createZeroValued(objectID: "counter:test@123", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
            let coreSDK = MockCoreSDK(channelState: .attached, internalQueue: internalQueue)
            let realtimeObjects = MockRealtimeObjects()

            realtimeObjects.setPublishAndApplyHandler { _ in
                .failure(LiveObjectsError.other(NSError(domain: "test", code: 0, userInfo: [NSLocalizedDescriptionKey: "Publish failed"])).toARTErrorInfo())
            }

            await #expect {
                try await counter.increment(amount: 10, coreSDK: coreSDK, realtimeObjects: realtimeObjects)
            } throws: { error in
                guard let errorInfo = error as? ARTErrorInfo else {
                    return false
                }
                return errorInfo.message.contains("Publish failed")
            }
        }
    }

    /// Tests for the `decrement` method, covering RTLC13 specification points
    struct DecrementTests {
        // @spec RTLC13b
        @Test
        func isOppositeOfIncrement() async throws {
            // This is just a smoke test; we assume that this just calls `increment`, which is tested elsewhere.
            let internalQueue = TestFactories.createInternalQueue()
            let counter = InternalDefaultLiveCounter.createZeroValued(objectID: "counter:test@123", logger: TestLogger(), internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
            let coreSDK = MockCoreSDK(channelState: .attached, internalQueue: internalQueue)
            let realtimeObjects = MockRealtimeObjects()

            var publishedMessages: [ProtocolTypes.OutboundObjectMessage] = []
            realtimeObjects.setPublishAndApplyHandler { messages in
                publishedMessages.append(contentsOf: messages)
                return .success(())
            }

            try await counter.decrement(amount: 10.5, coreSDK: coreSDK, realtimeObjects: realtimeObjects)

            // RTLC12g
            #expect(publishedMessages.count == 1)
            #expect(publishedMessages[0].operation?.counterInc?.number == -10.5 /* i.e. assert the amount gets negated */ )
        }
    }
}
