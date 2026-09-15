import _AblyPluginSupportPrivate
@testable import AblyLiveObjects
@testable import AblyLiveObjectsTesting
import AblyPubSubDevice
import Testing

/// Tests for `LiveObjectMutableState`.
struct LiveObjectMutableStateTests {
    /// Tests for `LiveObjectMutableState.canApplyOperation`, covering RTLO4 specification points.
    struct CanApplyOperationTests {
        /// Test case data for canApplyOperation tests
        struct TestCase {
            let description: String
            let objectMessageSerial: String?
            let objectMessageSiteCode: String?
            let siteTimeserials: [String: String]
            let expectedResult: LiveObjectMutableState<Void>.ApplicableOperation?
        }

        // @spec RTLO4a3
        // @spec RTLO4a4
        // @spec RTLO4a5
        // @spec RTLO4a6
        @Test(arguments: [
            // RTLO4a3: Both ObjectMessage.serial and ObjectMessage.siteCode must be non-empty strings
            TestCase(
                description: "serial is nil, siteCode is valid - should return nil",
                objectMessageSerial: nil,
                objectMessageSiteCode: "site1",
                siteTimeserials: [:],
                expectedResult: nil,
            ),
            TestCase(
                description: "serial is empty string, siteCode is valid - should return nil",
                objectMessageSerial: "",
                objectMessageSiteCode: "site1",
                siteTimeserials: [:],
                expectedResult: nil,
            ),
            TestCase(
                description: "serial is valid, siteCode is nil - should return nil",
                objectMessageSerial: "serial1",
                objectMessageSiteCode: nil,
                siteTimeserials: [:],
                expectedResult: nil,
            ),
            TestCase(
                description: "serial is valid, siteCode is empty string - should return nil",
                objectMessageSerial: "serial1",
                objectMessageSiteCode: "",
                siteTimeserials: [:],
                expectedResult: nil,
            ),
            TestCase(
                description: "both serial and siteCode are invalid - should return nil",
                objectMessageSerial: nil,
                objectMessageSiteCode: "",
                siteTimeserials: [:],
                expectedResult: nil,
            ),

            // RTLO4a5: If the siteSerial for this LiveObject is null or an empty string, return ApplicableOperation
            TestCase(
                description: "siteSerial is nil (siteCode doesn't exist) - should return ApplicableOperation",
                objectMessageSerial: "serial2",
                objectMessageSiteCode: "site1",
                siteTimeserials: ["site2": "serial1"], // i.e. only has an entry for a different siteCode
                expectedResult: LiveObjectMutableState.ApplicableOperation(objectMessageSerial: "serial2", objectMessageSiteCode: "site1"),
            ),
            TestCase(
                description: "siteSerial is empty string - should return ApplicableOperation",
                objectMessageSerial: "serial2",
                objectMessageSiteCode: "site1",
                siteTimeserials: ["site1": "", "site2": "serial1"],
                expectedResult: LiveObjectMutableState.ApplicableOperation(objectMessageSerial: "serial2", objectMessageSiteCode: "site1"),
            ),

            // RTLO4a6: If the siteSerial for this LiveObject is not an empty string, return ApplicableOperation if ObjectMessage.serial is greater than siteSerial when compared lexicographically
            TestCase(
                description: "serial is greater than siteSerial lexicographically - should return ApplicableOperation",
                objectMessageSerial: "serial2",
                objectMessageSiteCode: "site1",
                siteTimeserials: ["site1": "serial1"],
                expectedResult: LiveObjectMutableState.ApplicableOperation(objectMessageSerial: "serial2", objectMessageSiteCode: "site1"),
            ),
            TestCase(
                description: "serial is less than siteSerial lexicographically - should return nil",
                objectMessageSerial: "serial1",
                objectMessageSiteCode: "site1",
                siteTimeserials: ["site1": "serial2"],
                expectedResult: nil,
            ),
            TestCase(
                description: "serial equals siteSerial - should return nil",
                objectMessageSerial: "serial1",
                objectMessageSiteCode: "site1",
                siteTimeserials: ["site1": "serial1"],
                expectedResult: nil,
            ),
        ])
        func canApplyOperation(testCase: TestCase) {
            let state = LiveObjectMutableState<Void>(
                objectID: "test:object@123",
                testsOnly_siteTimeserials: testCase.siteTimeserials,
            )
            let logger = TestLogger()

            let result = state.canApplyOperation(
                objectMessageSerial: testCase.objectMessageSerial,
                objectMessageSiteCode: testCase.objectMessageSiteCode,
                logger: logger,
            )

            #expect(result == testCase.expectedResult, "Expected \(String(describing: testCase.expectedResult)) for case: \(testCase.description)")
        }
    }

    struct SubscriptionTests {
        // swiftlint:disable trailing_closure

        // @spec RTLO4b2
        @available(iOS 17.0.0, tvOS 17.0.0, *)
        @Test(arguments: [.detached, .failed] as [_AblyPluginSupportPrivate.RealtimeChannelState])
        func subscribeThrowsIfChannelIsDetachedOrFailed(channelState: _AblyPluginSupportPrivate.RealtimeChannelState) async throws {
            var mutableState = LiveObjectMutableState<String>(objectID: "foo")
            let queue = DispatchQueue.main
            let subscriber = Subscriber<String, SubscribeResponse>(callbackQueue: queue)
            let internalQueue = TestFactories.createInternalQueue()
            let coreSDK = MockCoreSDK(channelState: channelState, internalQueue: internalQueue)

            #expect {
                try internalQueue.ably_syncNoDeadlock {
                    try mutableState.nosync_subscribe(listener: subscriber.createListener(), coreSDK: coreSDK, updateSelfLater: { _ in fatalError("Not expected") })
                }
            } throws: { error in
                guard let errorInfo = error as? ARTErrorInfo else {
                    return false
                }

                return errorInfo.code == 90001 && errorInfo.statusCode == 400
            }
        }

        struct EmitTests {
            // @spec RTLO4b4c3a
            @available(iOS 17.0.0, tvOS 17.0.0, *)
            @Test
            func update() async throws {
                // Given
                var mutableState = LiveObjectMutableState<String>(objectID: "foo")
                let queue = DispatchQueue.main
                let subscriber = Subscriber<String, SubscribeResponse>(callbackQueue: queue)
                let internalQueue = TestFactories.createInternalQueue()
                let coreSDK = MockCoreSDK(channelState: .attached, internalQueue: internalQueue)
                try internalQueue.ably_syncNoDeadlock {
                    _ = try mutableState.nosync_subscribe(listener: subscriber.createListener(), coreSDK: coreSDK, updateSelfLater: { _ in fatalError("Not expected") })
                }

                // When
                mutableState.emit(.update("bar"), on: queue)

                // Then
                let subscriberInvocations = await subscriber.getInvocations()
                #expect(subscriberInvocations.map(\.0) == ["bar"])
            }
        }

        struct UnsubscribeTests {
            final class MutableStateStore<Update: Sendable>: Sendable {
                private let mutex: DispatchQueueMutex<LiveObjectMutableState<Update>>

                init(stored: LiveObjectMutableState<Update>, internalQueue: DispatchQueue) {
                    mutex = .init(dispatchQueue: internalQueue, initialValue: stored)
                }

                @discardableResult
                func subscribe(listener: @escaping LiveObjectUpdateCallback<Update>, coreSDK: CoreSDK) throws(ARTErrorInfo) -> SubscribeResponse {
                    try mutex.withSync { stored throws(ARTErrorInfo) in
                        try stored.nosync_subscribe(listener: listener, coreSDK: coreSDK, updateSelfLater: { [weak self] action in
                            guard let self else {
                                return
                            }

                            mutex.withSync { stored in
                                action(&stored)
                            }
                        })
                    }
                }

                func emit(_ update: LiveObjectUpdate<Update>, on queue: DispatchQueue) {
                    mutex.withSync { stored in
                        stored.emit(update, on: queue)
                    }
                }

                func unsubscribeAll() {
                    mutex.withSync { stored in
                        stored.unsubscribeAll()
                    }
                }
            }

            // @specOneOf(1/3) RTLO4b7 - Check we can unsubscribe using the response that's returned from `subscribe`
            @available(iOS 17.0.0, tvOS 17.0.0, *)
            @Test
            func unsubscribeFromReturnValue() async throws {
                // Given
                let queue = DispatchQueue.main
                let internalQueue = TestFactories.createInternalQueue()
                let store = MutableStateStore<String>(stored: .init(objectID: "foo"), internalQueue: internalQueue)
                let subscriber = Subscriber<String, SubscribeResponse>(callbackQueue: queue)
                let coreSDK = MockCoreSDK(channelState: .attached, internalQueue: internalQueue)
                let subscription = try store.subscribe(listener: subscriber.createListener(), coreSDK: coreSDK)

                // When
                store.emit(.update("bar"), on: queue)
                subscription.unsubscribe()
                store.emit(.update("baz"), on: queue)

                // Then
                let subscriberInvocations = await subscriber.getInvocations()
                #expect(subscriberInvocations.map(\.0) == ["bar"])
            }

            // @specOneOf(2/3) RTLO4b7 - Check we can unsubscribe using the `response` that's passed to the listener, and that when two updates are emitted back-to-back, the unsubscribe in the first listener causes us to not recieve the second update
            @available(iOS 17.0.0, tvOS 17.0.0, *)
            @Test(.disabled("This doesn't currently work and I don't think it's a priority, nor do I want to dwell on it right now or rush trying to fix it; see https://github.com/ably/ably-liveobjects-swift-plugin/issues/28"))
            func unsubscribeInsideCallback_backToBackUpdates() async throws {
                // Given
                let queue = DispatchQueue.main
                let internalQueue = TestFactories.createInternalQueue()
                let store = MutableStateStore<String>(stored: .init(objectID: "foo"), internalQueue: internalQueue)
                let subscriber = Subscriber<String, SubscribeResponse>(callbackQueue: queue)
                let coreSDK = MockCoreSDK(channelState: .attached, internalQueue: internalQueue)
                // Create a listener that calls `unsubscribe` on the `response` that's passed to the listener
                let listener = subscriber.createListener { _, response in
                    response.unsubscribe()
                }
                try store.subscribe(listener: listener, coreSDK: coreSDK)

                // When
                store.emit(.update("bar"), on: queue)
                store.emit(.update("baz"), on: queue)

                // Then
                let subscriberInvocations = await subscriber.getInvocations()
                // This is failing because it's still receiving "baz" too
                #expect(subscriberInvocations.map(\.0) == ["bar"])
            }

            // @specOneOf(3/3) RTLO4b7 - Check we can unsubscribe using the `response` that's passed to the listener. This is a simpler version of the above test, in that there is an async pause between the unsubscribe-in-callback and the next `emit`.
            @available(iOS 17.0.0, tvOS 17.0.0, *)
            @Test
            func unsubscribeInsideCallback_nonBackToBackUpdates() async throws {
                // Given
                let queue = DispatchQueue.main
                let internalQueue = TestFactories.createInternalQueue()
                let store = MutableStateStore<String>(stored: .init(objectID: "foo"), internalQueue: internalQueue)
                let subscriber = Subscriber<String, SubscribeResponse>(callbackQueue: queue)
                let coreSDK = MockCoreSDK(channelState: .attached, internalQueue: internalQueue)
                // Create a listener that calls `unsubscribe` on the `response` that's passed to the listener
                let listener = subscriber.createListener { _, response in
                    response.unsubscribe()
                }
                try store.subscribe(listener: listener, coreSDK: coreSDK)

                // When
                store.emit(.update("bar"), on: queue)
                // This is what distinguishes us from the previous test; the updates aren't back to back
                _ = await subscriber.getInvocations()
                store.emit(.update("baz"), on: queue)

                // Then
                let subscriberInvocations = await subscriber.getInvocations()
                #expect(subscriberInvocations.map(\.0) == ["bar"])
            }

            // @spec RTLO4d
            @available(iOS 17.0.0, tvOS 17.0.0, *)
            @Test
            func unsubscribeAll() async throws {
                // Given
                let queue = DispatchQueue.main
                let internalQueue = TestFactories.createInternalQueue()
                let store = MutableStateStore<String>(stored: .init(objectID: "foo"), internalQueue: internalQueue)
                let coreSDK = MockCoreSDK(channelState: .attached, internalQueue: internalQueue)
                let subscribers: [Subscriber<String, SubscribeResponse>] = [
                    .init(callbackQueue: queue),
                    .init(callbackQueue: queue),
                ]
                for subscriber in subscribers {
                    try store.subscribe(listener: subscriber.createListener(), coreSDK: coreSDK)
                }

                // When
                store.emit(.update("bar"), on: queue)
                store.unsubscribeAll()
                store.emit(.update("baz"), on: queue)

                // Then
                for subscriber in subscribers {
                    let subscriberInvocations = await subscriber.getInvocations()
                    #expect(subscriberInvocations.map(\.0) == ["bar"])
                }
            }
        }

        // swiftlint:enable trailing_closure
    }
}
