import _AblyPluginSupportPrivate
@testable import AblyLiveObjects
@testable import AblyLiveObjectsTesting
import AblyPubSubDevice
import Foundation
import Testing

struct InternalDefaultLiveMapTests {
    /// Tests for the `get` method, covering RTLM5 specification points
    struct GetTests {
        // @spec RTLM5c
        @Test(arguments: [.detached, .failed] as [_AblyPluginSupportPrivate.RealtimeChannelState])
        func getThrowsIfChannelIsDetachedOrFailed(channelState: _AblyPluginSupportPrivate.RealtimeChannelState) async throws {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let map = InternalDefaultLiveMap.createZeroValued(objectID: "arbitrary", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())

            #expect {
                _ = try map.get(key: "test", coreSDK: MockCoreSDK(channelState: channelState, internalQueue: internalQueue), delegate: MockLiveMapObjectsPoolDelegate(internalQueue: internalQueue))
            } throws: { error in
                guard let errorInfo = error as? ARTErrorInfo else {
                    return false
                }

                return errorInfo.code == 90001 && errorInfo.statusCode == 400
            }
        }

        // MARK: - RTLM5d Tests

        // @spec RTLM5d1
        @Test
        func returnsNilWhenNoEntryExists() throws {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let coreSDK = MockCoreSDK(channelState: .attaching, internalQueue: internalQueue)
            let map = InternalDefaultLiveMap.createZeroValued(objectID: "arbitrary", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
            #expect(try map.get(key: "nonexistent", coreSDK: coreSDK, delegate: MockLiveMapObjectsPoolDelegate(internalQueue: internalQueue)) == nil)
        }

        // @spec RTLM5d2h
        @Test
        func returnsNilWhenEntryIsTombstoned() throws {
            let logger = TestLogger()
            let entry = TestFactories.internalMapEntry(
                tombstonedAt: Date(),
                data: ProtocolTypes.ObjectData(boolean: true), // Value doesn't matter as it's tombstoned
            )
            let internalQueue = TestFactories.createInternalQueue()
            let coreSDK = MockCoreSDK(channelState: .attaching, internalQueue: internalQueue)
            let map = InternalDefaultLiveMap(testsOnly_data: ["key": entry], objectID: "arbitrary", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
            #expect(try map.get(key: "key", coreSDK: coreSDK, delegate: MockLiveMapObjectsPoolDelegate(internalQueue: internalQueue)) == nil)
        }

        // @spec RTLM5d2b
        @Test
        func returnsBooleanValue() throws {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let entry = TestFactories.internalMapEntry(data: ProtocolTypes.ObjectData(boolean: true))
            let coreSDK = MockCoreSDK(channelState: .attaching, internalQueue: internalQueue)
            let map = InternalDefaultLiveMap(testsOnly_data: ["key": entry], objectID: "arbitrary", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
            let result = try map.get(key: "key", coreSDK: coreSDK, delegate: MockLiveMapObjectsPoolDelegate(internalQueue: internalQueue))
            #expect(result?.boolValue == true)
        }

        // @spec RTLM5d2c
        @Test
        func returnsBytesValue() throws {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let bytes = Data([0x01, 0x02, 0x03])
            let entry = TestFactories.internalMapEntry(data: ProtocolTypes.ObjectData(bytes: bytes))
            let coreSDK = MockCoreSDK(channelState: .attaching, internalQueue: internalQueue)
            let map = InternalDefaultLiveMap(testsOnly_data: ["key": entry], objectID: "arbitrary", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
            let result = try map.get(key: "key", coreSDK: coreSDK, delegate: MockLiveMapObjectsPoolDelegate(internalQueue: internalQueue))
            #expect(result?.dataValue == bytes)
        }

        // @spec RTLM5d2d
        @Test
        func returnsNumberValue() throws {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let entry = TestFactories.internalMapEntry(data: ProtocolTypes.ObjectData(number: NSNumber(value: 123.456)))
            let coreSDK = MockCoreSDK(channelState: .attaching, internalQueue: internalQueue)
            let map = InternalDefaultLiveMap(testsOnly_data: ["key": entry], objectID: "arbitrary", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
            let result = try map.get(key: "key", coreSDK: coreSDK, delegate: MockLiveMapObjectsPoolDelegate(internalQueue: internalQueue))
            #expect(result?.numberValue == 123.456)
        }

        // @spec RTLM5d2e
        @Test
        func returnsStringValue() throws {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let entry = TestFactories.internalMapEntry(data: ProtocolTypes.ObjectData(string: "test"))
            let coreSDK = MockCoreSDK(channelState: .attaching, internalQueue: internalQueue)
            let map = InternalDefaultLiveMap(testsOnly_data: ["key": entry], objectID: "arbitrary", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
            let result = try map.get(key: "key", coreSDK: coreSDK, delegate: MockLiveMapObjectsPoolDelegate(internalQueue: internalQueue))
            #expect(result?.stringValue == "test")
        }

        // TODO: Needs specification (see https://github.com/ably/ably-liveobjects-swift-plugin/issues/46)
        // Tests when `json` is a JSON array
        @Test
        func returnsJSONArrayValue() throws {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let entry = TestFactories.internalMapEntry(data: ProtocolTypes.ObjectData(json: .array(["foo"])))
            let coreSDK = MockCoreSDK(channelState: .attaching, internalQueue: internalQueue)
            let map = InternalDefaultLiveMap(testsOnly_data: ["key": entry], objectID: "arbitrary", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
            let result = try map.get(key: "key", coreSDK: coreSDK, delegate: MockLiveMapObjectsPoolDelegate(internalQueue: internalQueue))
            #expect(result?.jsonArrayValue == ["foo"])
        }

        // TODO: Needs specification (see https://github.com/ably/ably-liveobjects-swift-plugin/issues/46)
        // Tests when `json` is a JSON object
        @Test
        func returnsJSONObjectValue() throws {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let entry = TestFactories.internalMapEntry(data: ProtocolTypes.ObjectData(json: .object(["foo": "bar"])))
            let coreSDK = MockCoreSDK(channelState: .attaching, internalQueue: internalQueue)
            let map = InternalDefaultLiveMap(testsOnly_data: ["key": entry], objectID: "arbitrary", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
            let result = try map.get(key: "key", coreSDK: coreSDK, delegate: MockLiveMapObjectsPoolDelegate(internalQueue: internalQueue))
            #expect(result?.jsonObjectValue == ["foo": "bar"])
        }

        // @spec RTLM5d2f1
        @Test
        func returnsNilWhenReferencedObjectDoesNotExist() throws {
            let logger = TestLogger()
            let entry = TestFactories.internalMapEntry(data: ProtocolTypes.ObjectData(objectId: "missing"))
            let internalQueue = TestFactories.createInternalQueue()
            let delegate = MockLiveMapObjectsPoolDelegate(internalQueue: internalQueue)
            let coreSDK = MockCoreSDK(channelState: .attaching, internalQueue: internalQueue)
            let map = InternalDefaultLiveMap(testsOnly_data: ["key": entry], objectID: "arbitrary", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
            #expect(try map.get(key: "key", coreSDK: coreSDK, delegate: delegate) == nil)
        }

        // @specOneOf(1/2) RTLM5d2f2 - Returns referenced map when it exists in pool
        @Test
        func returnsReferencedMap() throws {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let objectId = "map1"
            let entry = TestFactories.internalMapEntry(data: ProtocolTypes.ObjectData(objectId: objectId))
            let delegate = MockLiveMapObjectsPoolDelegate(internalQueue: internalQueue)
            let coreSDK = MockCoreSDK(channelState: .attaching, internalQueue: internalQueue)
            let referencedMap = InternalDefaultLiveMap.createZeroValued(objectID: "arbitrary", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
            delegate.objects[objectId] = .map(referencedMap)
            let map = InternalDefaultLiveMap(testsOnly_data: ["key": entry], objectID: "arbitrary", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
            let result = try map.get(key: "key", coreSDK: coreSDK, delegate: delegate)
            let returnedMap = result?.liveMapValue
            #expect(returnedMap as AnyObject === referencedMap as AnyObject)
        }

        // @specOneOf(2/2) RTLM5d2f2 - Returns referenced counter when it exists in pool
        @Test
        func returnsReferencedCounter() throws {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let objectId = "counter1"
            let entry = TestFactories.internalMapEntry(data: ProtocolTypes.ObjectData(objectId: objectId))
            let delegate = MockLiveMapObjectsPoolDelegate(internalQueue: internalQueue)
            let coreSDK = MockCoreSDK(channelState: .attaching, internalQueue: internalQueue)
            let referencedCounter = InternalDefaultLiveCounter.createZeroValued(objectID: "arbitrary", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
            delegate.objects[objectId] = .counter(referencedCounter)
            let map = InternalDefaultLiveMap(testsOnly_data: ["key": entry], objectID: "arbitrary", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
            let result = try map.get(key: "key", coreSDK: coreSDK, delegate: delegate)
            let returnedCounter = result?.liveCounterValue
            #expect(returnedCounter as AnyObject === referencedCounter as AnyObject)
        }

        // @spec RTLM5d2g
        @Test
        func returnsNullOtherwise() throws {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let entry = TestFactories.internalMapEntry(data: ProtocolTypes.ObjectData())
            let delegate = MockLiveMapObjectsPoolDelegate(internalQueue: internalQueue)
            let coreSDK = MockCoreSDK(channelState: .attaching, internalQueue: internalQueue)
            let map = InternalDefaultLiveMap(testsOnly_data: ["key": entry], objectID: "arbitrary", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
            #expect(try map.get(key: "key", coreSDK: coreSDK, delegate: delegate) == nil)
        }
    }

    /// Tests for the `replaceData` method, covering RTLM6 specification points
    struct ReplaceDataTests {
        // @spec RTLM6a
        @Test
        func replacesSiteTimeserials() {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let map = InternalDefaultLiveMap.createZeroValued(objectID: "arbitrary", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
            let state = TestFactories.objectState(
                objectId: "arbitrary-id",
                siteTimeserials: ["site1": "ts1", "site2": "ts2"],
            )
            var pool = ObjectsPool(logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
            internalQueue.ably_syncNoDeadlock {
                _ = map.nosync_replaceData(using: state, objectMessageSerialTimestamp: nil, objectsPool: &pool)
            }
            #expect(map.testsOnly_siteTimeserials == ["site1": "ts1", "site2": "ts2"])
        }

        // @spec RTLM6b
        @Test
        func setsCreateOperationIsMergedToFalseWhenCreateOpAbsent() {
            // Given:
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            var pool = ObjectsPool(logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
            let map = {
                let map = InternalDefaultLiveMap.createZeroValued(objectID: "arbitrary", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())

                // Test setup: Manipulate map so that its createOperationIsMerged gets set to true (we need to do this since we want to later assert that it gets set to false, but the default is false).
                let state = TestFactories.objectState(
                    createOp: TestFactories.mapCreateOperation(objectId: "arbitrary-id"),
                )
                internalQueue.ably_syncNoDeadlock {
                    _ = map.nosync_replaceData(using: state, objectMessageSerialTimestamp: nil, objectsPool: &pool)
                }
                #expect(map.testsOnly_createOperationIsMerged)

                return map
            }()

            // When:
            let state = TestFactories.objectState(objectId: "arbitrary-id", createOp: nil)
            internalQueue.ably_syncNoDeadlock {
                _ = map.nosync_replaceData(using: state, objectMessageSerialTimestamp: nil, objectsPool: &pool)
            }

            // Then:
            #expect(!map.testsOnly_createOperationIsMerged)
        }

        // @specOneOf(1/2) RTLM6c
        @Test
        func setsDataToMapEntries() throws {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let delegate = MockLiveMapObjectsPoolDelegate(internalQueue: internalQueue)
            let coreSDK = MockCoreSDK(channelState: .attaching, internalQueue: internalQueue)
            let map = InternalDefaultLiveMap.createZeroValued(objectID: "arbitrary", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
            let (key, entry) = TestFactories.stringMapEntry(key: "key1", value: "test")
            let state = TestFactories.mapObjectState(
                objectId: "arbitrary-id",
                entries: [key: entry],
            )
            var pool = ObjectsPool(logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
            internalQueue.ably_syncNoDeadlock {
                _ = map.nosync_replaceData(using: state, objectMessageSerialTimestamp: nil, objectsPool: &pool)
            }
            let newData = map.testsOnly_data
            #expect(newData.count == 1)
            #expect(Set(newData.keys) == ["key1"])
            #expect(try map.get(key: "key1", coreSDK: coreSDK, delegate: delegate)?.stringValue == "test")
        }

        // @specOneOf(2/2) RTLM6c - Tests that the map entries get combined with the createOp
        // @spec RTLM6d
        @Test
        func mergesInitialValueWhenCreateOpPresent() throws {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let delegate = MockLiveMapObjectsPoolDelegate(internalQueue: internalQueue)
            let coreSDK = MockCoreSDK(channelState: .attaching, internalQueue: internalQueue)
            let map = InternalDefaultLiveMap.createZeroValued(objectID: "arbitrary", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
            let state = TestFactories.objectState(
                objectId: "arbitrary-id",
                createOp: TestFactories.mapCreateOperation(
                    objectId: "arbitrary-id",
                    entries: [
                        "keyFromCreateOp": TestFactories.stringMapEntry(key: "keyFromCreateOp", value: "valueFromCreateOp").entry,
                    ],
                ),
                map: ProtocolTypes.ObjectsMap(
                    semantics: .known(.lww),
                    entries: [
                        "keyFromMapEntries": TestFactories.stringMapEntry(key: "keyFromMapEntries", value: "valueFromMapEntries").entry,
                    ],
                ),
            )
            var pool = ObjectsPool(logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
            internalQueue.ably_syncNoDeadlock {
                _ = map.nosync_replaceData(using: state, objectMessageSerialTimestamp: nil, objectsPool: &pool)
            }
            // Note that we just check for some basic expected side effects of merging the initial value; RTLM23 is tested in more detail elsewhere
            // Check that it contains the data from the entries (per RTLM6c) and also the createOp (per RTLM6d)
            #expect(try map.get(key: "keyFromMapEntries", coreSDK: coreSDK, delegate: delegate)?.stringValue == "valueFromMapEntries")
            #expect(try map.get(key: "keyFromCreateOp", coreSDK: coreSDK, delegate: delegate)?.stringValue == "valueFromCreateOp")
            #expect(map.testsOnly_createOperationIsMerged)
        }

        // @specOneOf(1/1) RTLM6i
        @Test
        func setsClearTimeserialFromObjectState() {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let map = InternalDefaultLiveMap.createZeroValued(objectID: "arbitrary", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
            let state = TestFactories.objectState(
                objectId: "arbitrary-id",
                map: TestFactories.objectsMap(clearTimeserial: "01234567890@abcdefghijklm"),
            )
            var pool = ObjectsPool(logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
            internalQueue.ably_syncNoDeadlock {
                _ = map.nosync_replaceData(using: state, objectMessageSerialTimestamp: nil, objectsPool: &pool)
            }
            #expect(map.testsOnly_clearTimeserial == "01234567890@abcdefghijklm")
        }

        /// Tests for RTLM6h (diff calculation on replaceData)
        struct DiffCalculationTests {
            // @specOneOf(1/2) RTLM6h - Tests that replaceData returns the diff calculated via RTLM22
            @Test
            func returnsCorrectDiffWithoutCreateOp() throws {
                let logger = TestLogger()
                let internalQueue = TestFactories.createInternalQueue()
                let map = InternalDefaultLiveMap.createZeroValued(objectID: "arbitrary", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())

                // Set initial data
                var pool = ObjectsPool(logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
                internalQueue.ably_syncNoDeadlock {
                    _ = map.nosync_replaceData(
                        using: TestFactories.mapObjectState(
                            objectId: "arbitrary-id",
                            entries: [
                                "key1": TestFactories.stringMapEntry(key: "key1", value: "value1").entry,
                                "key2": TestFactories.stringMapEntry(key: "key2", value: "value2").entry,
                            ],
                        ),
                        objectMessageSerialTimestamp: nil,
                        objectsPool: &pool,
                    )
                }

                // Replace data with modified entries (no createOp)
                let update = internalQueue.ably_syncNoDeadlock {
                    map.nosync_replaceData(
                        using: TestFactories.mapObjectState(
                            objectId: "arbitrary-id",
                            entries: [
                                "key1": TestFactories.stringMapEntry(key: "key1", value: "updatedValue").entry,
                                "key3": TestFactories.stringMapEntry(key: "key3", value: "value3").entry,
                            ],
                        ),
                        objectMessageSerialTimestamp: nil,
                        objectsPool: &pool,
                    )
                }

                // RTLM6h: Should return diff per RTLM22
                // key1: updated (changed value), key2: removed, key3: added
                let updateDict = try #require(update.update).update
                #expect(updateDict["key1"] == .updated) // value changed
                #expect(updateDict["key2"] == .removed) // removed
                #expect(updateDict["key3"] == .updated) // added
            }

            // @specOneOf(2/2) RTLM6h - Tests that replaceData returns the diff after merging createOp
            @Test
            func returnsCorrectDiffWithCreateOp() throws {
                let logger = TestLogger()
                let internalQueue = TestFactories.createInternalQueue()
                let map = InternalDefaultLiveMap.createZeroValued(objectID: "arbitrary", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())

                // Set initial data
                var pool = ObjectsPool(logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
                internalQueue.ably_syncNoDeadlock {
                    _ = map.nosync_replaceData(
                        using: TestFactories.mapObjectState(
                            objectId: "arbitrary-id",
                            entries: [
                                "existing": TestFactories.stringMapEntry(key: "existing", value: "value").entry,
                            ],
                        ),
                        objectMessageSerialTimestamp: nil,
                        objectsPool: &pool,
                    )
                }

                // Replace data with entries and createOp
                let update = internalQueue.ably_syncNoDeadlock {
                    map.nosync_replaceData(
                        using: TestFactories.objectState(
                            objectId: "arbitrary-id",
                            createOp: TestFactories.mapCreateOperation(
                                objectId: "arbitrary-id",
                                entries: [
                                    "fromCreateOp": TestFactories.stringMapEntry(key: "fromCreateOp", value: "value").entry,
                                ],
                            ),
                            map: ProtocolTypes.ObjectsMap(
                                semantics: .known(.lww),
                                entries: [
                                    "fromEntries": TestFactories.stringMapEntry(key: "fromEntries", value: "value").entry,
                                ],
                            ),
                        ),
                        objectMessageSerialTimestamp: nil,
                        objectsPool: &pool,
                    )
                }

                // RTLM6h: Should return diff from previousData to final data (after createOp merge)
                let updateDict = try #require(update.update).update
                #expect(updateDict["existing"] == .removed) // removed
                #expect(updateDict["fromEntries"] == .updated) // added
                #expect(updateDict["fromCreateOp"] == .updated) // added via createOp
            }
        }
    }

    /// Tests for the `size`, `entries`, `keys`, and `values` properties, covering RTLM10, RTLM11, RTLM12, and RTLM13 specification points
    struct AccessPropertiesTests {
        // MARK: - Error Throwing Tests (RTLM10c, RTLM11c, RTLM12b, RTLM13b)

        // @spec RTLM10c
        // @spec RTLM11c
        // @spec RTLM12b
        // @spec RTLM13b
        @Test(arguments: [.detached, .failed] as [_AblyPluginSupportPrivate.RealtimeChannelState])
        func allPropertiesThrowIfChannelIsDetachedOrFailed(channelState: _AblyPluginSupportPrivate.RealtimeChannelState) async throws {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let map = InternalDefaultLiveMap.createZeroValued(objectID: "arbitrary", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
            let coreSDK = MockCoreSDK(channelState: channelState, internalQueue: internalQueue)
            let delegate = MockLiveMapObjectsPoolDelegate(internalQueue: internalQueue)

            // Define actions to test
            let actions: [(String, () throws -> Any)] = [
                ("size", { try map.size(coreSDK: coreSDK, delegate: delegate) }),
                ("entries", { try map.entries(coreSDK: coreSDK, delegate: delegate) }),
                ("keys", { try map.keys(coreSDK: coreSDK, delegate: delegate) }),
                ("values", { try map.values(coreSDK: coreSDK, delegate: delegate) }),
            ]

            // Test each property throws the expected error
            for (propertyName, action) in actions {
                #expect("\(propertyName) should throw") {
                    _ = try action()
                } throws: { error in
                    guard let errorInfo = error as? ARTErrorInfo else {
                        return false
                    }
                    return errorInfo.code == 90001 && errorInfo.statusCode == 400
                }
            }
        }

        // MARK: - Tombstone Filtering Tests (RTLM10d, RTLM11d1, RTLM12b, RTLM13b)

        // @specOneOf(1/2) RTLM10d - Tests the "non-tombstoned" part of spec point
        // @spec RTLM11d1
        // @specOneOf(1/2) RTLM12b - Tests the "non-tombstoned" part of RTLM10d
        // @specOneOf(1/2) RTLM13b - Tests the "non-tombstoned" part of RTLM10d
        // @spec RTLM14
        @Test
        func allPropertiesFilterOutTombstonedEntries() throws {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let coreSDK = MockCoreSDK(channelState: .attaching, internalQueue: internalQueue)
            let delegate = MockLiveMapObjectsPoolDelegate(internalQueue: internalQueue)
            let map = InternalDefaultLiveMap(
                testsOnly_data: [
                    // tombstonedAt is nil, so not considered tombstoned
                    "active1": TestFactories.internalMapEntry(data: ProtocolTypes.ObjectData(string: "value1")),
                    // tombstonedAt is false, so not considered tombstoned
                    "tombstoned": TestFactories.internalMapEntry(tombstonedAt: Date(), data: ProtocolTypes.ObjectData(string: "tombstoned")),
                    "tombstoned2": TestFactories.internalMapEntry(tombstonedAt: Date(), data: ProtocolTypes.ObjectData(string: "tombstoned2")),
                ],
                objectID: "arbitrary",
                logger: logger,
                internalQueue: internalQueue,
                userCallbackQueue: .main,
                clock: MockSimpleClock(),
            )

            // Test size - should only count non-tombstoned entries
            let size = try map.size(coreSDK: coreSDK, delegate: delegate)
            #expect(size == 1)

            // Test entries - should only return non-tombstoned entries
            let entries = try map.entries(coreSDK: coreSDK, delegate: delegate)
            #expect(entries.count == 1)
            #expect(Set(entries.map(\.key)) == ["active1"])
            #expect(entries.first { $0.key == "active1" }?.value.stringValue == "value1")

            // Test keys - should only return keys from non-tombstoned entries
            let keys = try map.keys(coreSDK: coreSDK, delegate: delegate)
            #expect(keys.count == 1)
            #expect(Set(keys) == ["active1"])

            // Test values - should only return values from non-tombstoned entries
            let values = try map.values(coreSDK: coreSDK, delegate: delegate)
            #expect(values.count == 1)
            #expect(Set(values.compactMap(\.stringValue)) == Set(["value1"]))
        }

        // MARK: - Self-reference regression

        // Regression test: a DIRECT self-referencing entry (`data.objectId` == the map's own
        // objectID) previously crashed the read accessors with a Swift exclusive-access conflict.
        // The accessor holds the map's `mutableStateMutex` (via `withSync`) while the RTLM14c
        // tombstone check / RTLM5d2h conversion re-enters the SAME mutex via
        // `objectsPool.entries[objectId].nosync_isTombstone`. Indirect cycles (A→B→A) are fine;
        // only self-reference crashed. See the pool-level `getFullPaths` DFS for the analogous exclusivity
        // finding. Observable behaviour is unaffected by this Swift-specific guard: a non-tombstoned
        // self-reference is just a normal entry whose value is the map itself.
        @Test
        func selfReferencingEntryIsTreatedAsNormalEntry() throws {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let coreSDK = MockCoreSDK(channelState: .attaching, internalQueue: internalQueue)
            let delegate = MockLiveMapObjectsPoolDelegate(internalQueue: internalQueue)

            let selfObjectID = "map:self@1"
            let map = InternalDefaultLiveMap(
                testsOnly_data: [
                    "selfRef": TestFactories.internalMapEntry(data: ProtocolTypes.ObjectData(objectId: selfObjectID)),
                ],
                objectID: selfObjectID,
                logger: logger,
                internalQueue: internalQueue,
                userCallbackQueue: .main,
                clock: MockSimpleClock(),
            )
            // The entry references the containing map itself.
            delegate.objects[selfObjectID] = .map(map)

            // Each of these previously crashed via re-entrant mutex access; they must now treat the
            // self-reference as a normal LiveMap-valued entry.
            let size = try map.size(coreSDK: coreSDK, delegate: delegate)
            #expect(size == 1)

            let entries = try map.entries(coreSDK: coreSDK, delegate: delegate)
            #expect(entries.count == 1)
            #expect(entries.first?.key == "selfRef")
            #expect(entries.first?.value.liveMapValue as AnyObject === map as AnyObject)

            let keys = try map.keys(coreSDK: coreSDK, delegate: delegate)
            #expect(keys == ["selfRef"])

            let values = try map.values(coreSDK: coreSDK, delegate: delegate)
            #expect(values.count == 1)
            #expect(values.first?.liveMapValue as AnyObject === map as AnyObject)

            let got = try map.get(key: "selfRef", coreSDK: coreSDK, delegate: delegate)
            #expect(got?.liveMapValue as AnyObject === map as AnyObject)
        }

        // MARK: - Consistency Tests

        // @specOneOf(2/2) RTLM10d
        // @specOneOf(2/2) RTLM12b
        // @specOneOf(2/2) RTLM13b
        @Test
        func allAccessPropertiesReturnExpectedValuesAndAreConsistentWithEachOther() throws {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let coreSDK = MockCoreSDK(channelState: .attaching, internalQueue: internalQueue)
            let delegate = MockLiveMapObjectsPoolDelegate(internalQueue: internalQueue)
            let map = InternalDefaultLiveMap(
                testsOnly_data: [
                    "key1": TestFactories.internalMapEntry(data: ProtocolTypes.ObjectData(string: "value1")),
                    "key2": TestFactories.internalMapEntry(data: ProtocolTypes.ObjectData(string: "value2")),
                    "key3": TestFactories.internalMapEntry(data: ProtocolTypes.ObjectData(string: "value3")),
                ],
                objectID: "arbitrary",
                logger: logger,
                internalQueue: internalQueue,
                userCallbackQueue: .main,
                clock: MockSimpleClock(),
            )

            let size = try map.size(coreSDK: coreSDK, delegate: delegate)
            let entries = try map.entries(coreSDK: coreSDK, delegate: delegate)
            let keys = try map.keys(coreSDK: coreSDK, delegate: delegate)
            let values = try map.values(coreSDK: coreSDK, delegate: delegate)

            // All properties should return the same count
            #expect(size == 3)
            #expect(entries.count == 3)
            #expect(keys.count == 3)
            #expect(values.count == 3)

            // Keys should match the keys from entries
            #expect(Set(keys) == Set(entries.map(\.key)))

            // Values should match the values from entries
            #expect(Set(values.compactMap(\.stringValue)) == Set(entries.compactMap(\.value.stringValue)))
        }

        // MARK: - `entries` handling of different value types, per RTLM5d2

        // @spec RTLM11d
        @Test
        func entriesHandlesAllValueTypes() throws {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let delegate = MockLiveMapObjectsPoolDelegate(internalQueue: internalQueue)
            let coreSDK = MockCoreSDK(channelState: .attaching, internalQueue: internalQueue)

            // Create referenced objects for testing
            let referencedMap = InternalDefaultLiveMap.createZeroValued(objectID: "arbitrary", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
            let referencedCounter = InternalDefaultLiveCounter.createZeroValued(objectID: "arbitrary", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
            delegate.objects["map:ref@123"] = .map(referencedMap)
            delegate.objects["counter:ref@456"] = .counter(referencedCounter)

            let map = InternalDefaultLiveMap(
                testsOnly_data: [
                    "boolean": TestFactories.internalMapEntry(data: ProtocolTypes.ObjectData(boolean: true)), // RTLM5d2b
                    "bytes": TestFactories.internalMapEntry(data: ProtocolTypes.ObjectData(bytes: Data([0x01, 0x02, 0x03]))), // RTLM5d2c
                    "number": TestFactories.internalMapEntry(data: ProtocolTypes.ObjectData(number: NSNumber(value: 42))), // RTLM5d2d
                    "string": TestFactories.internalMapEntry(data: ProtocolTypes.ObjectData(string: "hello")), // RTLM5d2e
                    "jsonArray": TestFactories.internalMapEntry(data: ProtocolTypes.ObjectData(json: .array(["foo"]))), // TODO: Needs specification (see https://github.com/ably/ably-liveobjects-swift-plugin/issues/46)
                    "jsonObject": TestFactories.internalMapEntry(data: ProtocolTypes.ObjectData(json: .object(["foo": "bar"]))), // TODO: Needs specification (see https://github.com/ably/ably-liveobjects-swift-plugin/issues/46)
                    "mapRef": TestFactories.internalMapEntry(data: ProtocolTypes.ObjectData(objectId: "map:ref@123")), // RTLM5d2f2
                    "counterRef": TestFactories.internalMapEntry(data: ProtocolTypes.ObjectData(objectId: "counter:ref@456")), // RTLM5d2f2
                ],
                objectID: "arbitrary",
                logger: logger,
                internalQueue: internalQueue,
                userCallbackQueue: .main,
                clock: MockSimpleClock(),
            )

            let size = try map.size(coreSDK: coreSDK, delegate: delegate)
            let entries = try map.entries(coreSDK: coreSDK, delegate: delegate)
            let keys = try map.keys(coreSDK: coreSDK, delegate: delegate)
            let values = try map.values(coreSDK: coreSDK, delegate: delegate)

            #expect(size == 8)
            #expect(entries.count == 8)
            #expect(keys.count == 8)
            #expect(values.count == 8)

            // Verify the correct values are returned by `entries`
            let booleanEntry = entries.first { $0.key == "boolean" } // RTLM5d2b
            let bytesEntry = entries.first { $0.key == "bytes" } // RTLM5d2c
            let numberEntry = entries.first { $0.key == "number" } // RTLM5d2d
            let stringEntry = entries.first { $0.key == "string" } // RTLM5d2e
            let jsonArrayEntry = entries.first { $0.key == "jsonArray" } // RTLM5d2e
            let jsonObjectEntry = entries.first { $0.key == "jsonObject" } // RTLM5d2e
            let mapRefEntry = entries.first { $0.key == "mapRef" } // RTLM5d2f2
            let counterRefEntry = entries.first { $0.key == "counterRef" } // RTLM5d2f2

            #expect(booleanEntry?.value.boolValue == true) // RTLM5d2b
            #expect(bytesEntry?.value.dataValue == Data([0x01, 0x02, 0x03])) // RTLM5d2c
            #expect(numberEntry?.value.numberValue == 42) // RTLM5d2d
            #expect(stringEntry?.value.stringValue == "hello") // RTLM5d2e
            #expect(jsonArrayEntry?.value.jsonArrayValue == ["foo"]) // RTLM5d2e
            #expect(jsonObjectEntry?.value.jsonObjectValue == ["foo": "bar"]) // RTLM5d2e
            #expect(mapRefEntry?.value.liveMapValue as AnyObject === referencedMap as AnyObject) // RTLM5d2f2
            #expect(counterRefEntry?.value.liveCounterValue as AnyObject === referencedCounter as AnyObject) // RTLM5d2f2
        }
    }

    /// Tests for `MAP_SET` operations, covering RTLM7 specification points
    struct MapSetOperationTests {
        // MARK: - RTLM7h Tests (clearTimeserial check)

        // @spec RTLM7h
        @Test(arguments: [
            // serial < clearTimeserial: discard
            (operationSerial: "ts4" as String?, clearTimeserial: "ts5", expectedApplied: false),
            // serial == clearTimeserial: discard
            (operationSerial: "ts5" as String?, clearTimeserial: "ts5", expectedApplied: false),
            // serial > clearTimeserial: allow
            (operationSerial: "ts6" as String?, clearTimeserial: "ts5", expectedApplied: true),
            // serial is nil: discard
            (operationSerial: nil as String?, clearTimeserial: "ts5", expectedApplied: false),
        ] as [(operationSerial: String?, clearTimeserial: String, expectedApplied: Bool)])
        func checksClearTimeserialBeforeApplying(operationSerial: String?, clearTimeserial: String, expectedApplied: Bool) throws {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let delegate = MockLiveMapObjectsPoolDelegate(internalQueue: internalQueue)
            let coreSDK = MockCoreSDK(channelState: .attaching, internalQueue: internalQueue)
            // Given: a map with the specified clearTimeserial
            let map = InternalDefaultLiveMap(
                testsOnly_data: [:],
                objectID: "arbitrary",
                logger: logger,
                internalQueue: internalQueue,
                userCallbackQueue: .main,
                clock: MockSimpleClock(),
            )

            var pool = ObjectsPool(logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
            internalQueue.ably_syncNoDeadlock {
                _ = map.nosync_replaceData(
                    using: TestFactories.objectState(
                        map: TestFactories.objectsMap(clearTimeserial: clearTimeserial),
                    ),
                    objectMessageSerialTimestamp: nil,
                    objectsPool: &pool,
                )
            }

            // When: applying a MAP_SET operation with the specified serial
            let update = map.testsOnly_applyMapSetOperation(
                key: "key1",
                operationTimeserial: operationSerial,
                operationData: ProtocolTypes.ObjectData(string: "new"),
                objectsPool: &pool,
            )

            // Then: the operation is applied or discarded as expected
            #expect(update.isNoop == !expectedApplied)
            if expectedApplied {
                #expect(try map.get(key: "key1", coreSDK: coreSDK, delegate: delegate)?.stringValue == "new")
            } else {
                #expect(try map.get(key: "key1", coreSDK: coreSDK, delegate: delegate) == nil)
            }
        }

        // MARK: - RTLM7a Tests (Existing Entry)

        struct ExistingEntryTests {
            // @spec RTLM7a1
            @Test
            func discardsOperationWhenCannotBeApplied() throws {
                let logger = TestLogger()
                let internalQueue = TestFactories.createInternalQueue()
                let delegate = MockLiveMapObjectsPoolDelegate(internalQueue: internalQueue)
                let coreSDK = MockCoreSDK(channelState: .attaching, internalQueue: internalQueue)
                let map = InternalDefaultLiveMap(
                    testsOnly_data: ["key1": TestFactories.internalMapEntry(timeserial: "ts2", data: ProtocolTypes.ObjectData(string: "existing"))],
                    objectID: "arbitrary",
                    logger: logger,
                    internalQueue: internalQueue,
                    userCallbackQueue: .main,
                    clock: MockSimpleClock(),
                )
                var pool = ObjectsPool(logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())

                // Try to apply operation with lower timeserial (ts1 < ts2)
                let update = map.testsOnly_applyMapSetOperation(
                    key: "key1",
                    operationTimeserial: "ts1",
                    operationData: ProtocolTypes.ObjectData(objectId: "new"),
                    objectsPool: &pool,
                )

                // Verify the operation was discarded - existing data unchanged
                #expect(try map.get(key: "key1", coreSDK: coreSDK, delegate: delegate)?.stringValue == "existing")
                // Verify that RTLM7g1 didn't happen (i.e. that we didn't create a zero-value object in the pool for object ID "new")
                #expect(Set(pool.entries.keys) == ["root"])
                // Verify return value
                #expect(update.isNoop)
            }

            // @spec RTLM7a2
            // @specOneOf(1/2) RTLM7g1
            // @specOneOf(1/2) RTLM7f
            @Test(arguments: [
                // Case 1: ObjectData refers to a number value (shouldn't modify the ObjectsPool per RTLM7g)
                (operationData: ProtocolTypes.ObjectData(number: NSNumber(value: 42)), expectedCreatedObjectID: nil),
                // Case 2: ObjectData refers to an object value but the object ID is an empty string (shouldn't modify the ObjectsPool per RTLM7g)
                (operationData: ProtocolTypes.ObjectData(objectId: ""), expectedCreatedObjectID: nil),
                // Case 3: ObjectData refers to an object value (should modify the ObjectsPool per RTLM7g and RTLM7g1)
                (operationData: ProtocolTypes.ObjectData(objectId: "map:referenced@123"), expectedCreatedObjectID: "map:referenced@123"),
            ] as [(operationData: ProtocolTypes.ObjectData, expectedCreatedObjectID: String?)])
            func appliesOperationWhenCanBeApplied(operationData: ProtocolTypes.ObjectData, expectedCreatedObjectID: String?) throws {
                let logger = TestLogger()
                let internalQueue = TestFactories.createInternalQueue()
                let delegate = MockLiveMapObjectsPoolDelegate(internalQueue: internalQueue)
                let coreSDK = MockCoreSDK(channelState: .attaching, internalQueue: internalQueue)
                let map = InternalDefaultLiveMap(
                    testsOnly_data: ["key1": TestFactories.internalMapEntry(tombstonedAt: Date(), timeserial: "ts1", data: ProtocolTypes.ObjectData(string: "existing"))],
                    objectID: "arbitrary",
                    logger: logger,
                    internalQueue: internalQueue,
                    userCallbackQueue: .main,
                    clock: MockSimpleClock(),
                )
                var pool = ObjectsPool(logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())

                let update = map.testsOnly_applyMapSetOperation(
                    key: "key1",
                    operationTimeserial: "ts2",
                    operationData: operationData,
                    objectsPool: &pool,
                )

                // Update the delegate's pool to include any objects created by the MAP_SET operation (so that when we verify RTLM7b4 using map.get it can return a referenced object)
                if let expectedCreatedObjectID {
                    delegate.objects[expectedCreatedObjectID] = pool.entries[expectedCreatedObjectID]
                }

                // Verify the operation was applied
                let result = try map.get(key: "key1", coreSDK: coreSDK, delegate: delegate)
                if let numberValue = operationData.number {
                    #expect(result?.numberValue == numberValue.doubleValue)
                } else if expectedCreatedObjectID != nil {
                    #expect(result?.liveMapValue != nil)
                }

                // RTLM7a2e: Set ObjectsMapEntry.data to the ObjectData from the operation
                #expect(map.testsOnly_data["key1"]?.data?.number == operationData.number)
                #expect(map.testsOnly_data["key1"]?.data?.objectId == operationData.objectId)

                // RTLM7a2b: Set ObjectsMapEntry.timeserial to the operation's serial
                #expect(map.testsOnly_data["key1"]?.timeserial == "ts2")

                // RTLM7a2c: Set ObjectsMapEntry.tombstone to false
                #expect(map.testsOnly_data["key1"]?.tombstone == false)

                // RTLM7g/RTLM7g1: Check if zero-value object was created in pool
                if let expectedCreatedObjectID {
                    let createdObject = pool.entries[expectedCreatedObjectID]
                    #expect(createdObject != nil)
                    #expect(createdObject?.mapValue != nil)
                } else {
                    // For number values, no object should be created
                    #expect(Set(pool.entries.keys) == ["root"])
                }

                // RTLM7f: Check return value
                #expect(try #require(update.update).update == ["key1": .updated])
            }
        }

        // MARK: - RTLM7b Tests (No Existing Entry)

        struct NoExistingEntryTests {
            // @spec RTLM7b4
            // @spec RTLM7b2
            // @specOneOf(2/2) RTLM7g1
            // @specOneOf(2/2) RTLM7f
            @Test(arguments: [
                // Case 1: ObjectData refers to a number value (shouldn't modify the ObjectsPool per RTLM7g)
                (operationData: ProtocolTypes.ObjectData(number: NSNumber(value: 42)), expectedCreatedObjectID: nil),
                // Case 2: ObjectData refers to an object value but the object ID is an empty string (shouldn't modify the ObjectsPool per RTLM7g)
                (operationData: ProtocolTypes.ObjectData(objectId: ""), expectedCreatedObjectID: nil),
                // Case 3: ObjectData refers to an object value (should modify the ObjectsPool per RTLM7g and RTLM7g1)
                (operationData: ProtocolTypes.ObjectData(objectId: "map:referenced@123"), expectedCreatedObjectID: "map:referenced@123"),
            ] as [(operationData: ProtocolTypes.ObjectData, expectedCreatedObjectID: String?)])
            func createsNewEntryWhenNoExistingEntry(operationData: ProtocolTypes.ObjectData, expectedCreatedObjectID: String?) throws {
                let logger = TestLogger()
                let internalQueue = TestFactories.createInternalQueue()
                let delegate = MockLiveMapObjectsPoolDelegate(internalQueue: internalQueue)
                let coreSDK = MockCoreSDK(channelState: .attaching, internalQueue: internalQueue)
                let map = InternalDefaultLiveMap.createZeroValued(objectID: "arbitrary", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
                var pool = ObjectsPool(logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())

                let update = map.testsOnly_applyMapSetOperation(
                    key: "newKey",
                    operationTimeserial: "ts1",
                    operationData: operationData,
                    objectsPool: &pool,
                )

                // Update the delegate's pool to include any objects created by the MAP_SET operation (so that when we verify RTLM7b4 using map.get it can return a referenced object)
                if let expectedCreatedObjectID {
                    delegate.objects[expectedCreatedObjectID] = pool.entries[expectedCreatedObjectID]
                }

                // Verify new entry was created
                // RTLM7b4
                let result = try map.get(key: "newKey", coreSDK: coreSDK, delegate: delegate)
                if let numberValue = operationData.number {
                    #expect(result?.numberValue == numberValue.doubleValue)
                } else if expectedCreatedObjectID != nil {
                    #expect(result?.liveMapValue != nil)
                }
                let entry = try #require(map.testsOnly_data["newKey"])
                #expect(entry.timeserial == "ts1")
                // RTLM7b2
                #expect(entry.tombstone == false)

                // RTLM7g/RTLM7g1: Check if zero-value object was created in pool
                if let expectedCreatedObjectID {
                    let createdObject = try #require(pool.entries[expectedCreatedObjectID])
                    #expect(createdObject.mapValue != nil)
                } else {
                    // For number values, no object should be created
                    #expect(Set(pool.entries.keys) == ["root"])
                }

                // RTLM7f: Check return value
                #expect(try #require(update.update).update == ["newKey": .updated])
            }
        }

        // MARK: - RTLM7g1 Standalone Test (RTO6a Integration)

        // This is a sense check to convince ourselves that when applying a MAP_SET operation that references an object, then, because of RTO6a, if the referenced object already exists in the pool it is not replaced when RTLM7g1 is applied.
        @Test
        func doesNotReplaceExistingObjectWhenReferencedByMapSet() throws {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let delegate = MockLiveMapObjectsPoolDelegate(internalQueue: internalQueue)
            let coreSDK = MockCoreSDK(channelState: .attaching, internalQueue: internalQueue)
            let map = InternalDefaultLiveMap.createZeroValued(objectID: "arbitrary", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())

            // Create an existing object in the pool with some data
            let existingObjectId = "map:existing@123"
            let existingObject = InternalDefaultLiveMap(
                testsOnly_data: [:],
                objectID: "arbitrary",
                logger: logger,
                internalQueue: internalQueue,
                userCallbackQueue: .main,
                clock: MockSimpleClock(),
            )
            var pool = ObjectsPool(
                logger: logger,
                internalQueue: internalQueue,
                userCallbackQueue: .main,
                clock: MockSimpleClock(),
                testsOnly_otherEntries: [existingObjectId: .map(existingObject)],
            )
            // Populate the delegate so that when we "verify the MAP_SET operation was applied correctly" using map.get below it returns the referenced object
            delegate.objects[existingObjectId] = pool.entries[existingObjectId]

            // Apply MAP_SET operation that references the existing object
            _ = map.testsOnly_applyMapSetOperation(
                key: "referenceKey",
                operationTimeserial: "ts1",
                operationData: ProtocolTypes.ObjectData(objectId: existingObjectId),
                objectsPool: &pool,
            )

            // RTO6a: Verify that the existing object was NOT replaced
            let objectAfterMapSetValue = try #require(pool.entries[existingObjectId]?.mapValue)
            #expect(objectAfterMapSetValue as AnyObject === existingObject as AnyObject)

            // Verify the MAP_SET operation was applied correctly (creates reference in the map)
            let referenceValue = try map.get(key: "referenceKey", coreSDK: coreSDK, delegate: delegate)
            #expect(referenceValue?.liveMapValue != nil)
        }
    }

    /// Tests for `MAP_REMOVE` operations, covering RTLM8 specification points
    struct MapRemoveOperationTests {
        // MARK: - RTLM8g Tests (clearTimeserial check)

        // @spec RTLM8g
        @Test(arguments: [
            // serial < clearTimeserial: discard
            (operationSerial: "ts4" as String?, clearTimeserial: "ts5", expectedApplied: false),
            // serial == clearTimeserial: discard
            (operationSerial: "ts5" as String?, clearTimeserial: "ts5", expectedApplied: false),
            // serial > clearTimeserial: allow
            (operationSerial: "ts6" as String?, clearTimeserial: "ts5", expectedApplied: true),
            // serial is nil: discard
            (operationSerial: nil as String?, clearTimeserial: "ts5", expectedApplied: false),
        ] as [(operationSerial: String?, clearTimeserial: String, expectedApplied: Bool)])
        func checksClearTimeserialBeforeApplying(operationSerial: String?, clearTimeserial: String, expectedApplied: Bool) throws {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let delegate = MockLiveMapObjectsPoolDelegate(internalQueue: internalQueue)
            let coreSDK = MockCoreSDK(channelState: .attaching, internalQueue: internalQueue)

            // Given: a map with an existing entry and the specified clearTimeserial
            let map = InternalDefaultLiveMap(
                testsOnly_data: ["key1": TestFactories.internalMapEntry(timeserial: "ts1", data: ProtocolTypes.ObjectData(string: "existing"))],
                objectID: "arbitrary",
                logger: logger,
                internalQueue: internalQueue,
                userCallbackQueue: .main,
                clock: MockSimpleClock(),
            )

            var pool = ObjectsPool(logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
            internalQueue.ably_syncNoDeadlock {
                _ = map.nosync_replaceData(
                    using: TestFactories.objectState(
                        map: TestFactories.objectsMap(
                            entries: ["key1": TestFactories.stringMapEntry(key: "key1", value: "existing").entry],
                            clearTimeserial: clearTimeserial,
                        ),
                    ),
                    objectMessageSerialTimestamp: nil,
                    objectsPool: &pool,
                )
            }

            // When: applying a MAP_REMOVE operation with the specified serial
            let update = map.testsOnly_applyMapRemoveOperation(
                key: "key1",
                operationTimeserial: operationSerial,
                operationSerialTimestamp: nil,
                objectsPool: pool,
            )

            // Then: the operation is applied or discarded as expected
            #expect(update.isNoop == !expectedApplied)
            if expectedApplied {
                #expect(try map.get(key: "key1", coreSDK: coreSDK, delegate: delegate) == nil)
            } else {
                #expect(try map.get(key: "key1", coreSDK: coreSDK, delegate: delegate)?.stringValue == "existing")
            }
        }

        // MARK: - RTLM8a Tests (Existing Entry)

        struct ExistingEntryTests {
            // @spec RTLM8a1
            @Test
            func discardsOperationWhenCannotBeApplied() throws {
                let logger = TestLogger()
                let internalQueue = TestFactories.createInternalQueue()
                let delegate = MockLiveMapObjectsPoolDelegate(internalQueue: internalQueue)
                let coreSDK = MockCoreSDK(channelState: .attaching, internalQueue: internalQueue)
                let map = InternalDefaultLiveMap(
                    testsOnly_data: ["key1": TestFactories.internalMapEntry(timeserial: "ts2", data: ProtocolTypes.ObjectData(string: "existing"))],
                    objectID: "arbitrary",
                    logger: logger,
                    internalQueue: internalQueue,
                    userCallbackQueue: .main,
                    clock: MockSimpleClock(),
                )

                // Try to apply operation with lower timeserial (ts1 < ts2), cannot be applied per RTLM9
                let update = map.testsOnly_applyMapRemoveOperation(key: "key1", operationTimeserial: "ts1", operationSerialTimestamp: nil, objectsPool: ObjectsPool(logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock()))

                // Verify the operation was discarded - existing data unchanged
                #expect(try map.get(key: "key1", coreSDK: coreSDK, delegate: delegate)?.stringValue == "existing")
                // Verify return value
                #expect(update.isNoop)
            }

            // @spec RTLM8a2a
            // @spec RTLM8a2b
            // @spec RTLM8a2c
            // @specOneOf(1/2) RTLM8e
            @Test
            func appliesOperationWhenCanBeApplied() throws {
                let logger = TestLogger()
                let internalQueue = TestFactories.createInternalQueue()
                let delegate = MockLiveMapObjectsPoolDelegate(internalQueue: internalQueue)
                let coreSDK = MockCoreSDK(channelState: .attaching, internalQueue: internalQueue)
                let map = InternalDefaultLiveMap(
                    testsOnly_data: ["key1": TestFactories.internalMapEntry(tombstonedAt: nil, timeserial: "ts1", data: ProtocolTypes.ObjectData(string: "existing"))],
                    objectID: "arbitrary",
                    logger: logger,
                    internalQueue: internalQueue,
                    userCallbackQueue: .main,
                    clock: MockSimpleClock(),
                )

                // Apply operation with higher timeserial (ts2 > ts1), so can be applied per RTLM9
                let update = map.testsOnly_applyMapRemoveOperation(key: "key1", operationTimeserial: "ts2", operationSerialTimestamp: nil, objectsPool: ObjectsPool(logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock()))

                // Verify the operation was applied
                #expect(try map.get(key: "key1", coreSDK: coreSDK, delegate: delegate) == nil)

                // RTLM8a2a: Set ObjectsMapEntry.data to undefined/null
                #expect(map.testsOnly_data["key1"]?.data == nil)

                // RTLM8a2b: Set ObjectsMapEntry.timeserial to the operation's serial
                #expect(map.testsOnly_data["key1"]?.timeserial == "ts2")

                // RTLM8a2c: Set ObjectsMapEntry.tombstone to true
                #expect(map.testsOnly_data["key1"]?.tombstone == true)

                // RTLM8e: Check return value
                #expect(try #require(update.update).update == ["key1": .removed])
            }
        }

        // MARK: - RTLM8b Tests (No Existing Entry)

        struct NoExistingEntryTests {
            // @spec RTLM8b1 - Create new entry with ObjectsMapEntry.data set to undefined/null and operation's serial
            // @specOneOf(1/2) RTLM8e
            @Test
            func createsNewEntryWhenNoExistingEntry() throws {
                let logger = TestLogger()
                let internalQueue = TestFactories.createInternalQueue()
                let map = InternalDefaultLiveMap.createZeroValued(objectID: "arbitrary", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())

                let update = map.testsOnly_applyMapRemoveOperation(key: "newKey", operationTimeserial: "ts1", operationSerialTimestamp: nil, objectsPool: ObjectsPool(logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock()))

                // Verify new entry was created
                let entry = map.testsOnly_data["newKey"]
                #expect(entry != nil)
                #expect(entry?.timeserial == "ts1")
                #expect(entry?.data == nil)

                // RTLM8e: Check return value
                #expect(try #require(update.update).update == ["newKey": .removed])
            }

            // @spec RTLM8b2 - Set ObjectsMapEntry.tombstone for new entry to true
            @Test
            func setsNewEntryTombstoneToTrue() throws {
                let logger = TestLogger()
                let internalQueue = TestFactories.createInternalQueue()
                let map = InternalDefaultLiveMap.createZeroValued(objectID: "arbitrary", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())

                _ = map.testsOnly_applyMapRemoveOperation(key: "newKey", operationTimeserial: "ts1", operationSerialTimestamp: nil, objectsPool: ObjectsPool(logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock()))

                // Verify tombstone is true for new entry
                #expect(map.testsOnly_data["newKey"]?.tombstone == true)
            }
        }
    }

    /// Tests for map operation applicability, covering RTLM9 specification points
    struct MapOperationApplicabilityTests {
        // @spec RTLM9a
        // @spec RTLM9b
        // @spec RTLM9c
        // @spec RTLM9d
        // @spec RTLM9e
        @Test(arguments: [
            // RTLM9a, RTLM9e: LWW lexicographical comparison - operation can be applied
            // Standard case: ts2 > ts1
            (entrySerial: "ts1", operationSerial: "ts2", shouldApply: true),
            // Simple lexicographical: b > a
            (entrySerial: "a", operationSerial: "b", shouldApply: true),
            // Numeric strings: 2 > 1
            (entrySerial: "1", operationSerial: "2", shouldApply: true),
            // Longer string comparison: ts10 > ts1
            (entrySerial: "ts1", operationSerial: "ts10", shouldApply: true),

            // RTLM9a, RTLM9e: LWW lexicographical comparison - operation cannot be applied
            // Standard case: ts1 < ts2
            (entrySerial: "ts2", operationSerial: "ts1", shouldApply: false),
            // Simple lexicographical: a < b
            (entrySerial: "b", operationSerial: "a", shouldApply: false),
            // Numeric strings: 1 < 2
            (entrySerial: "2", operationSerial: "1", shouldApply: false),
            // Longer string comparison: ts1 < ts10
            (entrySerial: "ts10", operationSerial: "ts1", shouldApply: false),
            // Equal case: ts1 == ts1
            (entrySerial: "ts1", operationSerial: "ts1", shouldApply: false),

            // RTLM9b: Both serials null or empty - operation cannot be applied
            // Both null
            (entrySerial: nil, operationSerial: nil, shouldApply: false),
            // Both empty strings
            (entrySerial: "", operationSerial: "", shouldApply: false),

            // RTLM9c: Only entry serial exists - operation cannot be applied
            // Entry has serial, operation doesn't
            (entrySerial: "ts1", operationSerial: nil, shouldApply: false),
            // Entry has serial, operation empty
            (entrySerial: "ts1", operationSerial: "", shouldApply: false),

            // RTLM9d: Only operation serial exists - operation can be applied
            // Entry no serial, operation has serial
            (entrySerial: nil, operationSerial: "ts1", shouldApply: true),
            // Entry empty, operation has serial
            (entrySerial: "", operationSerial: "ts1", shouldApply: true),
        ] as [(entrySerial: String?, operationSerial: String?, shouldApply: Bool)])
        func mapOperationApplicability(entrySerial: String?, operationSerial: String?, shouldApply: Bool) throws {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let delegate = MockLiveMapObjectsPoolDelegate(internalQueue: internalQueue)
            let coreSDK = MockCoreSDK(channelState: .attaching, internalQueue: internalQueue)
            let map = InternalDefaultLiveMap(
                testsOnly_data: ["key1": TestFactories.internalMapEntry(timeserial: entrySerial, data: ProtocolTypes.ObjectData(string: "existing"))],
                objectID: "arbitrary",
                logger: logger,
                internalQueue: internalQueue,
                userCallbackQueue: .main,
                clock: MockSimpleClock(),
            )
            var pool = ObjectsPool(logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())

            _ = map.testsOnly_applyMapSetOperation(
                key: "key1",
                operationTimeserial: operationSerial,
                operationData: ProtocolTypes.ObjectData(string: "new"),
                objectsPool: &pool,
            )

            // We check whether the side effects of the MAP_SET operation have occurred or not as our proxy for checking that the appropriate applicability rules were applied.

            if shouldApply {
                // Verify operation was applied
                #expect(try map.get(key: "key1", coreSDK: coreSDK, delegate: delegate)?.stringValue == "new")
            } else {
                // Verify operation was discarded
                #expect(try map.get(key: "key1", coreSDK: coreSDK, delegate: delegate)?.stringValue == "existing")
            }
        }
    }

    /// Tests for the `mergeInitialValue` method, covering RTLM23 specification points
    struct MergeInitialValueTests {
        // @specOneOf(1/2) RTLM23a1 - via mapCreate
        @Test
        func appliesMapSetOperationsFromOperation() throws {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let delegate = MockLiveMapObjectsPoolDelegate(internalQueue: internalQueue)
            let coreSDK = MockCoreSDK(channelState: .attaching, internalQueue: internalQueue)
            let map = InternalDefaultLiveMap.createZeroValued(objectID: "arbitrary", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
            var pool = ObjectsPool(logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())

            // Apply merge operation with MAP_SET entries
            let operation = TestFactories.mapCreateOperation(
                objectId: "arbitrary-id",
                entries: [
                    "keyFromCreateOp": TestFactories.stringMapEntry(key: "keyFromCreateOp", value: "valueFromCreateOp").entry,
                ],
            )
            internalQueue.ably_syncNoDeadlock {
                _ = map.nosync_mergeInitialValue(from: operation, objectsPool: &pool)
            }

            // Note that we just check for some basic expected side effects of applying MAP_SET; RTLM7 is tested in more detail elsewhere
            // Check that it contains the data from the operation (per RTLM23a1)
            #expect(try map.get(key: "keyFromCreateOp", coreSDK: coreSDK, delegate: delegate)?.stringValue == "valueFromCreateOp")
        }

        // @specOneOf(2/2) RTLM23a1 - via mapCreateWithObjectId.derivedFrom
        // @spec RTLMV4j5
        @Test
        func appliesMapSetOperationsFromDerivedFrom() throws {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let delegate = MockLiveMapObjectsPoolDelegate(internalQueue: internalQueue)
            let coreSDK = MockCoreSDK(channelState: .attaching, internalQueue: internalQueue)
            let map = InternalDefaultLiveMap.createZeroValued(objectID: "arbitrary", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
            var pool = ObjectsPool(logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())

            // Apply merge operation with mapCreateWithObjectId.derivedFrom (no direct mapCreate)
            let operation = TestFactories.objectOperation(
                action: .known(.mapCreate),
                mapCreateWithObjectId: .init(
                    initialValue: "arbitrary",
                    nonce: "arbitrary",
                    derivedFrom: ProtocolTypes.MapCreate(
                        semantics: .known(.lww),
                        entries: [
                            "keyFromCreateOp": TestFactories.stringMapEntry(key: "keyFromCreateOp", value: "valueFromCreateOp").entry,
                        ],
                    ),
                ),
            )
            internalQueue.ably_syncNoDeadlock {
                _ = map.nosync_mergeInitialValue(from: operation, objectsPool: &pool)
            }

            // Check that it contains the data from the derived operation (per RTLM23a1)
            #expect(try map.get(key: "keyFromCreateOp", coreSDK: coreSDK, delegate: delegate)?.stringValue == "valueFromCreateOp")
        }

        // @spec RTLM23a2
        @Test
        func appliesMapRemoveOperationsFromOperation() throws {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let delegate = MockLiveMapObjectsPoolDelegate(internalQueue: internalQueue)
            let coreSDK = MockCoreSDK(channelState: .attaching, internalQueue: internalQueue)
            let map = InternalDefaultLiveMap(
                testsOnly_data: ["key1": TestFactories.internalStringMapEntry().entry],
                objectID: "arbitrary",
                logger: logger,
                internalQueue: internalQueue,
                userCallbackQueue: .main,
                clock: MockSimpleClock(),
            )
            var pool = ObjectsPool(logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())

            // Confirm that the initial data is there
            #expect(try map.get(key: "key1", coreSDK: coreSDK, delegate: delegate) != nil)

            // Apply merge operation with MAP_REMOVE entry
            let entry = TestFactories.mapEntry(
                tombstone: true,
                timeserial: "ts2", // Must be greater than existing entry's timeserial "ts1"
                data: ProtocolTypes.ObjectData(),
            )
            let operation = TestFactories.mapCreateOperation(
                objectId: "arbitrary-id",
                entries: ["key1": entry],
            )
            internalQueue.ably_syncNoDeadlock {
                _ = map.nosync_mergeInitialValue(from: operation, objectsPool: &pool)
            }

            // Verify the MAP_REMOVE operation was applied
            #expect(try map.get(key: "key1", coreSDK: coreSDK, delegate: delegate) == nil)
        }

        // @spec RTLM23c
        @Test
        func returnedUpdateMergesOperationUpdates() throws {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let map = InternalDefaultLiveMap(
                testsOnly_data: [
                    "keyThatWillBeRemoved": TestFactories.internalStringMapEntry(timeserial: "ts1").entry,
                    "keyThatWillNotBeRemoved": TestFactories.internalStringMapEntry(timeserial: "ts1").entry,
                ],
                objectID: "arbitrary",
                logger: logger,
                internalQueue: internalQueue,
                userCallbackQueue: .main,
                clock: MockSimpleClock(),
            )
            var pool = ObjectsPool(logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())

            // Apply merge operation with MAP_CREATE and MAP_REMOVE entries (copied from RTLM23a1 and RTLM23a2 test cases)
            let operation = TestFactories.mapCreateOperation(
                objectId: "arbitrary-id",
                entries: [
                    "keyThatWillBeRemoved": TestFactories.mapEntry(
                        tombstone: true,
                        timeserial: "ts2", // Must be greater than existing entry's timeserial "ts1"
                        data: ProtocolTypes.ObjectData(),
                    ),
                    "keyThatWillNotBeRemoved": TestFactories.mapEntry(
                        tombstone: true,
                        timeserial: "ts0", // Less than existing entry's timeserial "ts1" so MAP_REMOVE will be a no-op (this lets us test that no-ops are excluded from return value per RTLM23c)
                        data: ProtocolTypes.ObjectData(),
                    ),
                    "keyFromCreateOp": TestFactories.stringMapEntry(key: "keyFromCreateOp", value: "valueFromCreateOp").entry,
                ],
            )
            let update = internalQueue.ably_syncNoDeadlock {
                map.nosync_mergeInitialValue(from: operation, objectsPool: &pool)
            }

            // Verify merged return value per RTLM23c
            #expect(try #require(update.update).update == ["keyThatWillBeRemoved": .removed, "keyFromCreateOp": .updated])
        }

        // @spec RTLM23b
        @Test
        func setsCreateOperationIsMergedToTrue() {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let map = InternalDefaultLiveMap.createZeroValued(objectID: "arbitrary", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
            var pool = ObjectsPool(logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())

            // Apply merge operation
            let operation = TestFactories.mapCreateOperation(objectId: "arbitrary-id")
            internalQueue.ably_syncNoDeadlock {
                _ = map.nosync_mergeInitialValue(from: operation, objectsPool: &pool)
            }

            #expect(map.testsOnly_createOperationIsMerged)
        }
    }

    /// Tests for `MAP_CREATE` operations, covering RTLM16 specification points
    struct MapCreateOperationTests {
        // @spec RTLM16d
        // @spec RTLM16f
        @Test
        func mergesInitialValue() throws {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let delegate = MockLiveMapObjectsPoolDelegate(internalQueue: internalQueue)
            let coreSDK = MockCoreSDK(channelState: .attaching, internalQueue: internalQueue)
            let map = InternalDefaultLiveMap.createZeroValued(objectID: "arbitrary", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
            var pool = ObjectsPool(logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())

            // Set initial data but don't mark create operation as merged
            internalQueue.ably_syncNoDeadlock {
                _ = map.nosync_replaceData(using: TestFactories.mapObjectState(entries: ["key1": TestFactories.stringMapEntry().entry]), objectMessageSerialTimestamp: nil, objectsPool: &pool)
            }
            #expect(!map.testsOnly_createOperationIsMerged)

            // Apply MAP_CREATE operation
            let operation = TestFactories.mapCreateOperation(entries: ["key2": TestFactories.stringMapEntry(key: "key2", value: "value2").entry])
            let update = map.testsOnly_applyMapCreateOperation(operation, objectsPool: &pool)

            // Verify the operation was applied - initial value merged. (The full logic of RTLM23 is tested elsewhere; we just check for some of its side effects here.)
            #expect(try map.get(key: "key1", coreSDK: coreSDK, delegate: delegate)?.stringValue == "testValue") // Original data
            #expect(try map.get(key: "key2", coreSDK: coreSDK, delegate: delegate)?.stringValue == "value2") // From merge
            #expect(map.testsOnly_createOperationIsMerged)

            // Verify return value per RTLM16f
            #expect(try #require(update.update).update == ["key2": .updated])
        }
    }

    /// Tests for `MAP_CLEAR` operations, covering RTLM24 specification points
    struct MapClearOperationTests {
        // MARK: - RTLM24c Tests (clearTimeserial check)

        // @spec RTLM24c
        @Test(arguments: [
            // serial < clearTimeserial: discard
            (operationSerial: "ts4" as String?, clearTimeserial: "ts5", expectedApplied: false),
            // serial == clearTimeserial: RE-APPLY. RTLM24c discards only when clearTimeserial is
            // *strictly* greater than serial, so on equality the operation is applied (unlike
            // RTLM7h/RTLM8g which discard on `>=`). This case previously asserted `false`, which
            // encoded a cocoa bug (the gate used `serial <= clearTimeserial`); corrected to the spec.
            (operationSerial: "ts5" as String?, clearTimeserial: "ts5", expectedApplied: true),
            // serial > clearTimeserial: allow
            (operationSerial: "ts6" as String?, clearTimeserial: "ts5", expectedApplied: true),
            // serial is nil: discard
            (operationSerial: nil as String?, clearTimeserial: "ts5", expectedApplied: false),
        ] as [(operationSerial: String?, clearTimeserial: String, expectedApplied: Bool)])
        func checksClearTimeserialBeforeApplying(operationSerial: String?, clearTimeserial: String, expectedApplied: Bool) throws {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let delegate = MockLiveMapObjectsPoolDelegate(internalQueue: internalQueue)
            let coreSDK = MockCoreSDK(channelState: .attaching, internalQueue: internalQueue)

            // Given: a map with an existing entry and the specified clearTimeserial
            let map = InternalDefaultLiveMap(
                testsOnly_data: ["key1": TestFactories.internalMapEntry(timeserial: "ts1", data: ProtocolTypes.ObjectData(string: "existing"))],
                objectID: "arbitrary",
                logger: logger,
                internalQueue: internalQueue,
                userCallbackQueue: .main,
                clock: MockSimpleClock(),
            )

            var pool = ObjectsPool(logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
            internalQueue.ably_syncNoDeadlock {
                _ = map.nosync_replaceData(
                    using: TestFactories.objectState(
                        map: TestFactories.objectsMap(
                            entries: ["key1": TestFactories.stringMapEntry(key: "key1", value: "existing").entry],
                            clearTimeserial: clearTimeserial,
                        ),
                    ),
                    objectMessageSerialTimestamp: nil,
                    objectsPool: &pool,
                )
            }

            // When: applying a MAP_CLEAR operation with the specified serial
            let update = map.testsOnly_applyMapClearOperation(serial: operationSerial, objectsPool: pool)

            // Then: the operation is applied or discarded as expected
            #expect(update.isNoop == !expectedApplied)
            if expectedApplied {
                #expect(try map.get(key: "key1", coreSDK: coreSDK, delegate: delegate) == nil)
            } else {
                #expect(try map.get(key: "key1", coreSDK: coreSDK, delegate: delegate)?.stringValue == "existing")
            }
        }

        // MARK: - RTLM24 Tests (MAP_CLEAR operation application)

        // @spec RTLM24
        // @spec RTLM24d
        // @spec RTLM24e
        // @spec RTLM24e1
        // @spec RTLM24e1a
        // @spec RTLM24e1b
        // @spec RTLM24f
        @Test
        func appliesMapClearOperation() throws {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()

            // Given: a map with multiple entries at different timeserials, including one with nil timeserial
            let map = InternalDefaultLiveMap(
                testsOnly_data: [
                    "olderThanClear": TestFactories.internalMapEntry(timeserial: "ts1", data: ProtocolTypes.ObjectData(string: "value1")),
                    // Note that this shouldn't happen in real life — timeserials are unique
                    "equalToClear": TestFactories.internalMapEntry(timeserial: "ts3", data: ProtocolTypes.ObjectData(string: "value2")),
                    "newerThanClear": TestFactories.internalMapEntry(timeserial: "ts5", data: ProtocolTypes.ObjectData(string: "value3")),
                    "nilTimeserial": TestFactories.internalMapEntry(timeserial: nil, data: ProtocolTypes.ObjectData(string: "value4")),
                ],
                objectID: "arbitrary",
                logger: logger,
                internalQueue: internalQueue,
                userCallbackQueue: .main,
                clock: MockSimpleClock(),
            )

            // When: applying a MAP_CLEAR operation with serial "ts3"
            let update = map.testsOnly_applyMapClearOperation(serial: "ts3", objectsPool: ObjectsPool(logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock()))

            // Then: entries with timeserial < "ts3" or nil are removed from internal data, others remain
            #expect(Set(map.testsOnly_data.keys) == ["equalToClear", "newerThanClear"])

            // RTLM24f: update contains exactly the removed keys
            let mapUpdate = try #require(update.update)
            #expect(mapUpdate.update == [
                "olderThanClear": .removed,
                "nilTimeserial": .removed,
            ])

            // RTLM24d: clearTimeserial should be set
            #expect(map.testsOnly_clearTimeserial == "ts3")
        }
    }

    /// Tests for the `apply(_ operation:, …)` method, covering RTLM15 specification points
    struct ApplyOperationTests {
        // @spec RTLM15b - Tests that an operation does not get applied when canApplyOperation returns nil
        @Test
        func discardsOperationWhenCannotBeApplied() throws {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let delegate = MockLiveMapObjectsPoolDelegate(internalQueue: internalQueue)
            let coreSDK = MockCoreSDK(channelState: .attaching, internalQueue: internalQueue)
            let map = InternalDefaultLiveMap.createZeroValued(objectID: "arbitrary", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())

            // Set up the map with an existing site timeserial that will cause the operation to be discarded
            var pool = ObjectsPool(logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
            let (key1, entry1) = TestFactories.stringMapEntry(key: "key1", value: "existing", timeserial: nil)
            internalQueue.ably_syncNoDeadlock {
                _ = map.nosync_replaceData(
                    using: TestFactories.mapObjectState(
                        siteTimeserials: ["site1": "ts2"], // Existing serial "ts2"
                        entries: [key1: entry1],
                    ),
                    objectMessageSerialTimestamp: nil,
                    objectsPool: &pool,
                )
            }

            let operation = TestFactories.objectOperation(
                action: .known(.mapSet),
                mapSet: ProtocolTypes.MapSet(key: "key1", value: ProtocolTypes.ObjectData(string: "new")),
            )

            // Apply operation with serial "ts1" which is lexicographically less than existing "ts2" and thus will be applied per RTLO4a (this is a non-pathological case of RTOL4a, that spec point being fully tested elsewhere)
            let applied = internalQueue.ably_syncNoDeadlock {
                map.nosync_apply(
                    operation,
                    source: .channel,
                    objectMessage: TestFactories.inboundObjectMessage(serial: "ts1", siteCode: "site1"), // Less than existing "ts2"
                    objectsPool: &pool,
                )
            }
            #expect(applied == nil)

            // Check that the MAP_SET side-effects didn't happen:
            // Verify the operation was discarded - data unchanged (should still be "existing" from creation)
            #expect(try map.get(key: "key1", coreSDK: coreSDK, delegate: delegate)?.stringValue == "existing")
            // Verify site timeserials unchanged
            #expect(map.testsOnly_siteTimeserials == ["site1": "ts2"])
        }

        // @specOneOf(1/5) RTLM15c - We test this spec point for each possible operation
        // @spec RTLM15d1 - Tests MAP_CREATE operation application
        // @spec RTLM15d1a
        // @spec RTLM15d1b
        @available(iOS 17.0.0, tvOS 17.0.0, *)
        @Test
        func appliesMapCreateOperation() async throws {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let delegate = MockLiveMapObjectsPoolDelegate(internalQueue: internalQueue)
            let coreSDK = MockCoreSDK(channelState: .attaching, internalQueue: internalQueue)
            let map = InternalDefaultLiveMap.createZeroValued(objectID: "arbitrary", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())

            let subscriber = Subscriber<DefaultLiveMapUpdate, SubscribeResponse>(callbackQueue: .main)
            try map.subscribe(listener: subscriber.createListener(), coreSDK: coreSDK)

            let operation = TestFactories.mapCreateOperation(
                entries: ["key1": TestFactories.stringMapEntry(key: "key1", value: "value1").entry],
            )
            var pool = ObjectsPool(logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())

            // Apply MAP_CREATE operation
            let message = TestFactories.inboundObjectMessage(serial: "ts1", siteCode: "site1")
            let applied = internalQueue.ably_syncNoDeadlock {
                map.nosync_apply(
                    operation,
                    source: .channel,
                    objectMessage: message,
                    objectsPool: &pool,
                )
            }
            #expect(applied != nil)

            // Verify the operation was applied - initial value merged (the full logic of RTLM16 is tested elsewhere; we just check for some of its side effects here)
            #expect(try map.get(key: "key1", coreSDK: coreSDK, delegate: delegate)?.stringValue == "value1")
            #expect(map.testsOnly_createOperationIsMerged)
            // Verify RTLM15c side-effect: site timeserial was updated
            #expect(map.testsOnly_siteTimeserials == ["site1": "ts1"])

            // Verify update was emitted per RTLM15d1a, carrying the stamped source message (RTLO4b4d)
            let subscriberInvocations = await subscriber.getInvocations()
            #expect(subscriberInvocations.map(\.0) == [.init(update: ["key1": .updated], objectMessage: message)])
        }

        // @specOneOf(2/5) RTLM15c - We test this spec point for each possible operation
        // @spec RTLM15d6 - Tests MAP_SET operation application
        // @spec RTLM15d6a
        // @spec RTLM15d6b
        @available(iOS 17.0.0, tvOS 17.0.0, *)
        @Test
        func appliesMapSetOperation() async throws {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let delegate = MockLiveMapObjectsPoolDelegate(internalQueue: internalQueue)
            let coreSDK = MockCoreSDK(channelState: .attaching, internalQueue: internalQueue)
            let map = InternalDefaultLiveMap.createZeroValued(objectID: "arbitrary", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())

            let subscriber = Subscriber<DefaultLiveMapUpdate, SubscribeResponse>(callbackQueue: .main)
            try map.subscribe(listener: subscriber.createListener(), coreSDK: coreSDK)

            // Set initial data
            var pool = ObjectsPool(logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
            let (key1, entry1) = TestFactories.stringMapEntry(key: "key1", value: "existing", timeserial: nil)
            internalQueue.ably_syncNoDeadlock {
                _ = map.nosync_replaceData(
                    using: TestFactories.mapObjectState(
                        siteTimeserials: [:],
                        entries: [key1: entry1],
                    ),
                    objectMessageSerialTimestamp: nil,
                    objectsPool: &pool,
                )
            }
            #expect(try map.get(key: "key1", coreSDK: coreSDK, delegate: delegate)?.stringValue == "existing")

            let operation = TestFactories.objectOperation(
                action: .known(.mapSet),
                mapSet: ProtocolTypes.MapSet(key: "key1", value: ProtocolTypes.ObjectData(string: "new")),
            )

            // Apply MAP_SET operation
            let message = TestFactories.inboundObjectMessage(serial: "ts1", siteCode: "site1")
            let applied = internalQueue.ably_syncNoDeadlock {
                map.nosync_apply(
                    operation,
                    source: .channel,
                    objectMessage: message,
                    objectsPool: &pool,
                )
            }
            #expect(applied != nil)

            // Verify the operation was applied - value updated (the full logic of RTLM7 is tested elsewhere; we just check for some of its side effects here)
            #expect(try map.get(key: "key1", coreSDK: coreSDK, delegate: delegate)?.stringValue == "new")
            // Verify RTLM15c side-effect: site timeserial was updated
            #expect(map.testsOnly_siteTimeserials == ["site1": "ts1"])

            // Verify update was emitted per RTLM15d6a, carrying the stamped source message (RTLO4b4d)
            let subscriberInvocations = await subscriber.getInvocations()
            #expect(subscriberInvocations.map(\.0) == [.init(update: ["key1": .updated], objectMessage: message)])
        }

        // @specOneOf(3/5) RTLM15c - We test this spec point for each possible operation
        // @spec RTLM15d7 - Tests MAP_REMOVE operation application
        // @spec RTLM15d7a
        // @spec RTLM15d7b
        @available(iOS 17.0.0, tvOS 17.0.0, *)
        @Test
        func appliesMapRemoveOperation() async throws {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let delegate = MockLiveMapObjectsPoolDelegate(internalQueue: internalQueue)
            let coreSDK = MockCoreSDK(channelState: .attaching, internalQueue: internalQueue)
            let map = InternalDefaultLiveMap.createZeroValued(objectID: "arbitrary", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())

            let subscriber = Subscriber<DefaultLiveMapUpdate, SubscribeResponse>(callbackQueue: .main)
            try map.subscribe(listener: subscriber.createListener(), coreSDK: coreSDK)

            // Set initial data
            var pool = ObjectsPool(logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
            let (key1, entry1) = TestFactories.stringMapEntry(key: "key1", value: "existing", timeserial: nil)
            internalQueue.ably_syncNoDeadlock {
                _ = map.nosync_replaceData(
                    using: TestFactories.mapObjectState(
                        siteTimeserials: [:],
                        entries: [key1: entry1],
                    ),
                    objectMessageSerialTimestamp: nil,
                    objectsPool: &pool,
                )
            }
            #expect(try map.get(key: "key1", coreSDK: coreSDK, delegate: delegate)?.stringValue == "existing")

            let operation = TestFactories.objectOperation(
                action: .known(.mapRemove),
                mapRemove: WireMapRemove(key: "key1"),
            )

            // Apply MAP_REMOVE operation
            let message = TestFactories.inboundObjectMessage(serial: "ts1", siteCode: "site1")
            let applied = internalQueue.ably_syncNoDeadlock {
                map.nosync_apply(
                    operation,
                    source: .channel,
                    objectMessage: message,
                    objectsPool: &pool,
                )
            }
            #expect(applied != nil)

            // Verify the operation was applied - key removed (the full logic of RTLM8 is tested elsewhere; we just check for some of its side effects here)
            #expect(try map.get(key: "key1", coreSDK: coreSDK, delegate: delegate) == nil)
            // Verify RTLM15c side-effect: site timeserial was updated
            #expect(map.testsOnly_siteTimeserials == ["site1": "ts1"])

            // Verify update was emitted per RTLM15d7a, carrying the stamped source message (RTLO4b4d)
            let subscriberInvocations = await subscriber.getInvocations()
            #expect(subscriberInvocations.map(\.0) == [.init(update: ["key1": .removed], objectMessage: message)])
        }

        // @specOneOf(4/5) RTLM15c - We test this spec point for each possible operation
        // @spec RTLM15d8
        // @spec RTLM15d8a
        // @spec RTLM15d8b
        @available(iOS 17.0.0, tvOS 17.0.0, *)
        @Test
        func appliesMapClearOperation() async throws {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let delegate = MockLiveMapObjectsPoolDelegate(internalQueue: internalQueue)
            let coreSDK = MockCoreSDK(channelState: .attaching, internalQueue: internalQueue)
            let map = InternalDefaultLiveMap.createZeroValued(objectID: "arbitrary", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())

            let subscriber = Subscriber<DefaultLiveMapUpdate, SubscribeResponse>(callbackQueue: .main)
            try map.subscribe(listener: subscriber.createListener(), coreSDK: coreSDK)

            // Set initial data
            var pool = ObjectsPool(logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
            let (key1, entry1) = TestFactories.stringMapEntry(key: "key1", value: "existing", timeserial: nil)
            internalQueue.ably_syncNoDeadlock {
                _ = map.nosync_replaceData(
                    using: TestFactories.mapObjectState(
                        siteTimeserials: [:],
                        entries: [key1: entry1],
                    ),
                    objectMessageSerialTimestamp: nil,
                    objectsPool: &pool,
                )
            }
            #expect(try map.get(key: "key1", coreSDK: coreSDK, delegate: delegate)?.stringValue == "existing")

            let operation = TestFactories.objectOperation(
                action: .known(.mapClear),
                mapClear: WireMapClear(),
            )

            // Apply MAP_CLEAR operation
            let message = TestFactories.inboundObjectMessage(serial: "ts1", siteCode: "site1")
            let applied = internalQueue.ably_syncNoDeadlock {
                map.nosync_apply(
                    operation,
                    source: .channel,
                    objectMessage: message,
                    objectsPool: &pool,
                )
            }
            #expect(applied != nil)

            // Verify the operation was applied (the full logic of RTLM24 is tested elsewhere; we just check for some of its side effects here)
            #expect(try map.get(key: "key1", coreSDK: coreSDK, delegate: delegate) == nil)
            #expect(map.testsOnly_clearTimeserial == "ts1")
            // Verify RTLM15c side-effect: site timeserial was updated
            #expect(map.testsOnly_siteTimeserials == ["site1": "ts1"])

            // Verify update was emitted per RTLM15d8a, carrying the stamped source message (RTLO4b4d)
            let subscriberInvocations = await subscriber.getInvocations()
            #expect(subscriberInvocations.map(\.0) == [.init(update: ["key1": .removed], objectMessage: message)])
        }

        // @specOneOf(5/5) RTLM15c - Tests that siteTimeserials is NOT updated when source is LOCAL
        @Test
        func doesNotUpdateSiteTimeserialsForLocalSource() throws {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let delegate = MockLiveMapObjectsPoolDelegate(internalQueue: internalQueue)
            let coreSDK = MockCoreSDK(channelState: .attaching, internalQueue: internalQueue)
            let map = InternalDefaultLiveMap.createZeroValued(objectID: "arbitrary", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())

            let operation = TestFactories.objectOperation(
                action: .known(.mapSet),
                mapSet: ProtocolTypes.MapSet(key: "key1", value: ProtocolTypes.ObjectData(string: "new")),
            )
            var pool = ObjectsPool(logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())

            // Apply MAP_SET operation with LOCAL source
            let applied = internalQueue.ably_syncNoDeadlock {
                map.nosync_apply(
                    operation,
                    source: .local,
                    objectMessage: TestFactories.inboundObjectMessage(serial: "ts1", siteCode: "site1"),
                    objectsPool: &pool,
                )
            }
            #expect(applied != nil)

            // Verify the operation was applied
            #expect(try map.get(key: "key1", coreSDK: coreSDK, delegate: delegate)?.stringValue == "new")
            // Verify RTLM15c: siteTimeserials should NOT have been updated for LOCAL source
            #expect(map.testsOnly_siteTimeserials.isEmpty)
        }
    }

    /// Tests for the `set` method, covering RTLM20 specification points
    struct SetTests {
        // @spec RTLM20c
        @Test(arguments: [.detached, .failed, .suspended] as [_AblyPluginSupportPrivate.RealtimeChannelState])
        func throwsErrorForInvalidChannelState(channelState: _AblyPluginSupportPrivate.RealtimeChannelState) async throws {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let map = InternalDefaultLiveMap.createZeroValued(objectID: "arbitrary", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
            let coreSDK = MockCoreSDK(channelState: channelState, internalQueue: internalQueue)
            let realtimeObjects = MockRealtimeObjects()

            await #expect {
                try await map.set(key: "test", value: .primitive(.string("value")), coreSDK: coreSDK, realtimeObjects: realtimeObjects)
            } throws: { error in
                guard let errorInfo = error as? ARTErrorInfo else {
                    return false
                }

                return errorInfo.code == 90001 && errorInfo.statusCode == 400
            }
        }

        // Primitive value types map 1:1 onto their MAP_SET `ObjectData` and publish a single-element
        // array (RTLM20h2). Blueprint value types (RTLM20e7g / RTLM20h1) publish the `*_CREATE` messages
        // ahead of the MAP_SET; that atomic-array behaviour is covered by `DefaultInstanceTests`
        // (`mapSetCounterBlueprintPublishesCreateThenSet` etc.) and the UTS `InternalLiveMapApiTests`.
        // @spec RTLM20e
        // @specUntested RTLM20e1 - Not needed with Swift's type system
        // @spec RTLM20e2
        // @spec RTLM20e3
        // @spec RTLM20e6
        // @spec RTLM20e7b
        // @spec RTLM20e7c
        // @spec RTLM20e7d
        // @spec RTLM20e7e
        // @spec RTLM20e7f
        // @spec RTLM20h2
        @Test(arguments: [
            // RTLM20e7b
            (value: LiveMapValue.primitive(.jsonArray(["test"])), expectedData: .init(json: .array(["test"]))),
            (value: .primitive(.jsonObject(["foo": "bar"])), expectedData: .init(json: .object(["foo": "bar"]))),
            // RTLM20e7c
            (value: .primitive(.string("test")), expectedData: .init(string: "test")),
            // RTLM20e7d
            (value: .primitive(.number(42.5)), expectedData: .init(number: NSNumber(value: 42.5))),
            // RTLM20e7e
            (value: .primitive(.bool(true)), expectedData: .init(boolean: true)),
            // RTLM20e7f
            (value: .primitive(.data(Data([0x01, 0x02]))), expectedData: .init(bytes: Data([0x01, 0x02]))),
        ] as [(value: LiveMapValue, expectedData: ProtocolTypes.ObjectData)])
        func publishesCorrectObjectMessageForDifferentValueTypes(value: LiveMapValue, expectedData: ProtocolTypes.ObjectData) async throws {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let map = InternalDefaultLiveMap.createZeroValued(objectID: "map:test@123", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
            let coreSDK = MockCoreSDK(channelState: .attached, internalQueue: internalQueue)
            let realtimeObjects = MockRealtimeObjects()

            var publishedMessages: [ProtocolTypes.OutboundObjectMessage]?
            realtimeObjects.setPublishAndApplyHandler { messages in
                publishedMessages = messages
                return .success(())
            }

            try await map.set(key: "testKey", value: value, coreSDK: coreSDK, realtimeObjects: realtimeObjects)

            let expectedMessage = ProtocolTypes.OutboundObjectMessage(
                operation: ProtocolTypes.ObjectOperation(
                    // RTLM20e2
                    action: .known(.mapSet),
                    // RTLM20e3
                    objectId: "map:test@123",
                    mapSet: ProtocolTypes.MapSet(
                        // RTLM20e6
                        key: "testKey",
                        // RTLM20e7
                        value: expectedData,
                    ),
                ),
            )
            // RTLM20h2: a primitive publishes the MAP_SET as a single-element array
            let messages = try #require(publishedMessages)
            #expect(messages.count == 1)
            #expect(messages.first == expectedMessage)
        }

        @Test
        func throwsErrorWhenPublishFails() async throws {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let map = InternalDefaultLiveMap.createZeroValued(objectID: "map:test@123", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
            let coreSDK = MockCoreSDK(channelState: .attached, internalQueue: internalQueue)
            let realtimeObjects = MockRealtimeObjects()

            realtimeObjects.setPublishAndApplyHandler { _ in
                .failure(LiveObjectsError.other(NSError(domain: "test", code: 0, userInfo: [NSLocalizedDescriptionKey: "Publish failed"])).toARTErrorInfo())
            }

            await #expect {
                try await map.set(key: "testKey", value: .primitive(.string("testValue")), coreSDK: coreSDK, realtimeObjects: realtimeObjects)
            } throws: { error in
                guard let errorInfo = error as? ARTErrorInfo else {
                    return false
                }
                return errorInfo.message.contains("Publish failed")
            }
        }
    }

    /// Tests for the `remove` method, covering RTLM21 specification points
    struct RemoveTests {
        // @spec RTLM21c
        @Test(arguments: [.detached, .failed, .suspended] as [_AblyPluginSupportPrivate.RealtimeChannelState])
        func throwsErrorForInvalidChannelState(channelState: _AblyPluginSupportPrivate.RealtimeChannelState) async throws {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let map = InternalDefaultLiveMap.createZeroValued(objectID: "arbitrary", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
            let coreSDK = MockCoreSDK(channelState: channelState, internalQueue: internalQueue)
            let realtimeObjects = MockRealtimeObjects()

            await #expect {
                try await map.remove(key: "test", coreSDK: coreSDK, realtimeObjects: realtimeObjects)
            } throws: { error in
                guard let errorInfo = error as? ARTErrorInfo else {
                    return false
                }

                return errorInfo.code == 90001 && errorInfo.statusCode == 400
            }
        }

        // @specUntested RTLM21e
        // @specUntested RTLM21e1 - Not needed with Swift's type system
        // @spec RTLM21e2
        // @spec RTLM21e3
        // @spec RTLM21e5
        // @spec RTLM21g
        @Test
        func publishesCorrectObjectMessage() async throws {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let map = InternalDefaultLiveMap.createZeroValued(objectID: "map:test@123", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
            let coreSDK = MockCoreSDK(channelState: .attached, internalQueue: internalQueue)
            let realtimeObjects = MockRealtimeObjects()

            var publishedMessages: [ProtocolTypes.OutboundObjectMessage] = []
            realtimeObjects.setPublishAndApplyHandler { messages in
                publishedMessages.append(contentsOf: messages)
                return .success(())
            }

            try await map.remove(key: "testKey", coreSDK: coreSDK, realtimeObjects: realtimeObjects)

            let expectedMessage = ProtocolTypes.OutboundObjectMessage(
                operation: ProtocolTypes.ObjectOperation(
                    // RTLM21e2
                    action: .known(.mapRemove),
                    // RTLM21e3
                    objectId: "map:test@123",
                    mapRemove: WireMapRemove(
                        // RTLM21e5
                        key: "testKey",
                    ),
                ),
            )
            // RTLM21g
            #expect(publishedMessages.count == 1)
            #expect(publishedMessages[0] == expectedMessage)
        }

        @Test
        func throwsErrorWhenPublishFails() async throws {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let map = InternalDefaultLiveMap.createZeroValued(objectID: "map:test@123", logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
            let coreSDK = MockCoreSDK(channelState: .attached, internalQueue: internalQueue)
            let realtimeObjects = MockRealtimeObjects()

            realtimeObjects.setPublishAndApplyHandler { _ in
                .failure(LiveObjectsError.other(NSError(domain: "test", code: 0, userInfo: [NSLocalizedDescriptionKey: "Publish failed"])).toARTErrorInfo())
            }

            await #expect {
                try await map.remove(key: "testKey", coreSDK: coreSDK, realtimeObjects: realtimeObjects)
            } throws: { error in
                guard let errorInfo = error as? ARTErrorInfo else {
                    return false
                }
                return errorInfo.message.contains("Publish failed")
            }
        }
    }

    /// Divergence #3: the tombstone / OBJECT_DELETE / reset teardown paths must report only the
    /// NON-tombstoned entries as `removed`. Per RTLO4e5 the teardown update is the RTLM22 diff
    /// between the pre-teardown data and the (now cleared) data, and RTLM22b considers only
    /// non-tombstoned entries. An entry that was already tombstoned was never visible to
    /// subscribers, so it must not be reported as newly `removed`. (Previously these paths mapped
    /// ALL data entries — including already-tombstoned ones — to `removed`, which was internally
    /// inconsistent with `ObjectDiffHelpers.calculateMapDiff`.)
    struct TombstoneTeardownExcludesAlreadyTombstonedEntriesTests {
        private static func makeSeededMap(objectID: String, internalQueue: DispatchQueue) -> InternalDefaultLiveMap {
            InternalDefaultLiveMap(
                testsOnly_data: [
                    "kept": TestFactories.internalMapEntry(timeserial: "01", data: ProtocolTypes.ObjectData(string: "Alice")),
                    // Already tombstoned before the teardown — must be excluded from the removed update.
                    "gone": InternalObjectsMapEntry(tombstonedAt: Date(), timeserial: "01", data: nil),
                ],
                objectID: objectID,
                logger: TestLogger(),
                internalQueue: internalQueue,
                userCallbackQueue: .main,
                clock: MockSimpleClock(),
            )
        }

        // @specPartial RTLO4e5 - OBJECT_DELETE teardown reports only non-tombstoned entries as removed (RTLM15d5)
        @Test
        func objectDeleteExcludesAlreadyTombstonedEntries() throws {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let map = Self.makeSeededMap(objectID: "map:test@1000", internalQueue: internalQueue)
            map.testsOnly_setSiteTimeserials(["site1": "00"])

            var pool = ObjectsPool(logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
            let operation = TestFactories.objectOperation(action: .known(.objectDelete), objectId: "map:test@1000", objectDelete: WireObjectDelete())
            let update = internalQueue.ably_syncNoDeadlock {
                map.nosync_apply(
                    operation,
                    source: .channel,
                    objectMessage: TestFactories.inboundObjectMessage(serial: "01", siteCode: "site1", serialTimestamp: Date(timeIntervalSince1970: 1_700_000_000)),
                    objectsPool: &pool,
                )
            }

            #expect(map.testsOnly_isTombstone == true)
            // Only the non-tombstoned "kept" key is reported as removed; already-tombstoned "gone" is excluded.
            let unwrapped = try #require(update?.update)
            #expect(unwrapped.update == ["kept": .removed])
            #expect(update?.tombstone == true)
        }

        // @specPartial RTLO4e5 - replaceData tombstone teardown (RTLM6f) reports only non-tombstoned entries as removed
        @Test
        func replaceDataTombstoneExcludesAlreadyTombstonedEntries() throws {
            let logger = TestLogger()
            let internalQueue = TestFactories.createInternalQueue()
            let map = Self.makeSeededMap(objectID: "map:test@1000", internalQueue: internalQueue)

            var pool = ObjectsPool(logger: logger, internalQueue: internalQueue, userCallbackQueue: .main, clock: MockSimpleClock())
            let update = internalQueue.ably_syncNoDeadlock {
                map.nosync_replaceData(
                    using: TestFactories.mapObjectState(objectId: "map:test@1000", tombstone: true),
                    objectMessageSerialTimestamp: nil,
                    objectsPool: &pool,
                )
            }

            #expect(map.testsOnly_isTombstone == true)
            let unwrapped = try #require(update.update)
            #expect(unwrapped.update == ["kept": .removed])
            #expect(update.tombstone == true)
        }

        // @specPartial RTO4b2a - reset teardown reports only non-tombstoned entries as removed
        @available(iOS 17.0.0, tvOS 17.0.0, *)
        @Test
        func resetDataExcludesAlreadyTombstonedEntries() async throws {
            let internalQueue = TestFactories.createInternalQueue()
            let coreSDK = MockCoreSDK(channelState: .attaching, internalQueue: internalQueue)
            let map = Self.makeSeededMap(objectID: "root", internalQueue: internalQueue)

            let subscriber = Subscriber<DefaultLiveMapUpdate, SubscribeResponse>(callbackQueue: .main)
            try map.subscribe(listener: subscriber.createListener(), coreSDK: coreSDK)

            internalQueue.ably_syncNoDeadlock {
                _ = map.nosync_resetData()
            }

            let subscriberInvocations = await subscriber.getInvocations()
            // Only "kept" is reported as removed; already-tombstoned "gone" is excluded.
            #expect(subscriberInvocations.map(\.0) == [.init(update: ["kept": .removed])])
        }
    }

    /// Regression tests for the parent-reference *mutation* sites' self-reference guard (an
    /// extension of the read-path self-reference guard, whose counterpart is tested in
    /// `AccessPropertiesTests.selfReferencingEntryIsTreatedAsNormalEntry`).
    ///
    /// A wire-delivered MAP_SET (RTLM7a3/RTLM7g2), MAP_REMOVE (RTLM8a3), MAP_CLEAR (RTLM24e1c) or
    /// OBJECT_DELETE (RTLO4e9) touching an entry whose `data.objectId` equals the containing map's
    /// own objectID previously crashed with a Swift exclusive-access conflict: the apply path holds
    /// the map's `mutableStateMutex` while `objectsPool.entries[refId]?.nosync_(add|remove)ParentReference`
    /// re-enters that same mutex. These are peer-controllable inputs, so they must not crash.
    /// A self-parent is a legitimate graph edge; `getFullPaths`' RTLO4f2 cycle suppression handles
    /// the resulting self-loop.
    struct SelfReferenceParentReferenceGuardTests {
        static let selfID = "map:self@1"

        /// Creates a map with the given data whose objectID is `selfID`, registered in a pool under
        /// that same ID (so that pool lookups of a self-referencing entry resolve to the map itself).
        private func makeFixture(
            data: [String: InternalObjectsMapEntry],
            internalQueue: DispatchQueue,
        ) -> (map: InternalDefaultLiveMap, pool: ObjectsPool) {
            let logger = TestLogger()
            let map = InternalDefaultLiveMap(
                testsOnly_data: data,
                objectID: Self.selfID,
                logger: logger,
                internalQueue: internalQueue,
                userCallbackQueue: .main,
                clock: MockSimpleClock(),
            )
            let pool = ObjectsPool(
                logger: logger,
                internalQueue: internalQueue,
                userCallbackQueue: .main,
                clock: MockSimpleClock(),
                testsOnly_otherEntries: [Self.selfID: .map(map)],
            )
            return (map, pool)
        }

        /// A MAP_SET creating a self-referencing entry records the self-parent edge (RTLM7g2)
        /// without re-entering the map's mutex, and `getFullPaths` suppresses the self-loop.
        @Test
        func mapSetAddingSelfReferenceRecordsSelfParentEdge() throws {
            let internalQueue = TestFactories.createInternalQueue()
            var (map, pool) = makeFixture(data: [:], internalQueue: internalQueue)

            let operation = TestFactories.objectOperation(
                action: .known(.mapSet),
                mapSet: ProtocolTypes.MapSet(key: "selfRef", value: ProtocolTypes.ObjectData(objectId: Self.selfID)),
            )
            let applied = internalQueue.ably_syncNoDeadlock {
                map.nosync_apply(
                    operation,
                    source: .channel,
                    objectMessage: TestFactories.inboundObjectMessage(serial: "ts1", siteCode: "site1"),
                    objectsPool: &pool,
                )
            }
            #expect(applied != nil)

            // RTLM7g2: the self-parent edge is recorded on the map itself.
            #expect(map.testsOnly_parentReferences == [Self.selfID: ["selfRef"]])

            // RTLO4f2: the self-loop contributes no paths (and does not loop forever); with no
            // reference from root, there are no full paths at all.
            #expect(map.testsOnly_getFullPaths(objectsPool: pool).isEmpty)

            // With a root reference added alongside the self-loop, exactly the root path is
            // returned; the self-loop is suppressed by the per-branch visited set.
            map.testsOnly_setParentReferences([Self.selfID: ["selfRef"], "root": ["m"]])
            #expect(map.testsOnly_getFullPaths(objectsPool: pool) == [["m"]])
        }

        /// A MAP_SET overwriting an existing self-referencing entry drops the self-parent edge
        /// (RTLM7a3) without re-entering the map's mutex.
        @Test
        func mapSetOverwritingSelfReferencingEntryDropsSelfParentEdge() throws {
            let internalQueue = TestFactories.createInternalQueue()
            var (map, pool) = makeFixture(
                data: ["selfRef": TestFactories.internalMapEntry(timeserial: "ts1", data: ProtocolTypes.ObjectData(objectId: Self.selfID))],
                internalQueue: internalQueue,
            )
            // Seed the self-parent edge that the existing entry represents.
            map.testsOnly_setParentReferences([Self.selfID: ["selfRef"]])

            let operation = TestFactories.objectOperation(
                action: .known(.mapSet),
                // The overwriting value's type is unimportant; a string keeps the assertion simple.
                mapSet: ProtocolTypes.MapSet(key: "selfRef", value: ProtocolTypes.ObjectData(string: "overwritten")),
            )
            let applied = internalQueue.ably_syncNoDeadlock {
                map.nosync_apply(
                    operation,
                    source: .channel,
                    objectMessage: TestFactories.inboundObjectMessage(serial: "ts2", siteCode: "site1"), // greater than the entry's "ts1" so RTLM9 allows it
                    objectsPool: &pool,
                )
            }
            #expect(applied != nil)

            // RTLM7a3: the self-parent edge held via the overwritten entry is dropped.
            #expect(map.testsOnly_parentReferences.isEmpty)
        }

        /// A MAP_REMOVE of a self-referencing entry drops the self-parent edge (RTLM8a3) without
        /// re-entering the map's mutex.
        @Test
        func mapRemoveOfSelfReferencingEntryDropsSelfParentEdge() throws {
            let internalQueue = TestFactories.createInternalQueue()
            var (map, pool) = makeFixture(
                data: ["selfRef": TestFactories.internalMapEntry(timeserial: "ts1", data: ProtocolTypes.ObjectData(objectId: Self.selfID))],
                internalQueue: internalQueue,
            )
            map.testsOnly_setParentReferences([Self.selfID: ["selfRef"]])

            let operation = TestFactories.objectOperation(
                action: .known(.mapRemove),
                mapRemove: WireMapRemove(key: "selfRef"),
            )
            let applied = internalQueue.ably_syncNoDeadlock {
                map.nosync_apply(
                    operation,
                    source: .channel,
                    objectMessage: TestFactories.inboundObjectMessage(serial: "ts2", siteCode: "site1"), // greater than the entry's "ts1" so RTLM9 allows it
                    objectsPool: &pool,
                )
            }
            #expect(applied != nil)

            // RTLM8a3: the self-parent edge held via the removed entry is dropped.
            #expect(map.testsOnly_parentReferences.isEmpty)
            // The entry itself is tombstoned.
            #expect(map.testsOnly_data["selfRef"]?.tombstone == true)
        }

        /// A MAP_CLEAR of a map containing a self-referencing entry drops the self-parent edge
        /// (RTLM24e1c) without re-entering the map's mutex.
        @Test
        func mapClearWithSelfReferencingEntryDropsSelfParentEdge() throws {
            let internalQueue = TestFactories.createInternalQueue()
            var (map, pool) = makeFixture(
                data: ["selfRef": TestFactories.internalMapEntry(timeserial: "ts1", data: ProtocolTypes.ObjectData(objectId: Self.selfID))],
                internalQueue: internalQueue,
            )
            map.testsOnly_setParentReferences([Self.selfID: ["selfRef"]])

            let operation = TestFactories.objectOperation(
                action: .known(.mapClear),
                mapClear: WireMapClear(),
            )
            let applied = internalQueue.ably_syncNoDeadlock {
                map.nosync_apply(
                    operation,
                    source: .channel,
                    objectMessage: TestFactories.inboundObjectMessage(serial: "ts2", siteCode: "site1"), // greater than the entry's "ts1" so RTLM24e1 clears it
                    objectsPool: &pool,
                )
            }
            #expect(applied != nil)

            // RTLM24e1c: the self-parent edge held via the cleared entry is dropped.
            #expect(map.testsOnly_parentReferences.isEmpty)
            #expect(map.testsOnly_data.isEmpty)
        }

        /// An OBJECT_DELETE of a map containing a self-referencing entry drops the self-parent edge
        /// (RTLO4e9, via the held-parent-references teardown) without re-entering the map's mutex.
        @Test
        func objectDeleteWithSelfReferencingEntryDropsSelfParentEdge() throws {
            let internalQueue = TestFactories.createInternalQueue()
            var (map, pool) = makeFixture(
                data: ["selfRef": TestFactories.internalMapEntry(timeserial: "ts1", data: ProtocolTypes.ObjectData(objectId: Self.selfID))],
                internalQueue: internalQueue,
            )
            map.testsOnly_setParentReferences([Self.selfID: ["selfRef"]])

            let operation = TestFactories.objectOperation(
                action: .known(.objectDelete),
                objectId: Self.selfID,
                objectDelete: WireObjectDelete(),
            )
            let applied = internalQueue.ably_syncNoDeadlock {
                map.nosync_apply(
                    operation,
                    source: .channel,
                    objectMessage: TestFactories.inboundObjectMessage(serial: "ts1", siteCode: "site1"),
                    objectsPool: &pool,
                )
            }
            #expect(applied != nil)

            // RTLO4e9: the self-parent edge this map held on itself is dropped, and the map is
            // tombstoned.
            #expect(map.testsOnly_parentReferences.isEmpty)
            #expect(map.testsOnly_isTombstone)
        }
    }
}
