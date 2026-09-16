@testable import AblyLiveObjects
@testable import AblyLiveObjectsTesting
import AblyPubSubDevice.Private
import Testing

@Suite(.tags(.integration), .serialized)
struct ObjectLifetimesTests {
    @Test("LiveObjects functionality works with only a strong reference to channel's public object property")
    func withStrongReferenceToPublicObjectsProperty() async throws {
        // The objects that we'll create.
        struct CreatedObjects {
            /// The queue on which we expect ably-cocoa's QueuedDealloc mechanism to enqueue the relinquishing of `weakInternalRealtime`.
            var realtimeDeallocQueue: DispatchQueue

            weak var weakPublicRealtime: ARTRealtimeClient?
            weak var weakInternalRealtime: ARTRealtimeClientInternal?
            weak var weakPublicChannel: ARTRealtimeChannel?
            weak var weakInternalChannel: ARTRealtimeChannelInternal?
            var strongPublicRealtimeObject: PublicDefaultRealtimeObject
            weak var weakInternalRealtimeObjects: InternalDefaultRealtimeObjects?
        }

        // What we're left with after discarding a CreatedObjects.
        struct RemainingObjects {
            /// The queue on which we expect ably-cocoa's QueuedDealloc mechanism to enqueue the relinquishing of `weakInternalRealtime`.
            var realtimeDeallocQueue: DispatchQueue

            // weakPublicRealtime is gone now
            weak var weakInternalRealtime: ARTRealtimeClientInternal?
            // weakPublicChannel is gone now
            weak var weakInternalChannel: ARTRealtimeChannelInternal?
            weak var weakPublicRealtimeObject: PublicDefaultRealtimeObject?
            weak var weakInternalRealtimeObjects: InternalDefaultRealtimeObjects?
        }

        func createAndDiscardObjects() async throws -> RemainingObjects {
            func createObjects() async throws -> CreatedObjects {
                // We disable autoConnect since being connected extends the internal Realtime instance's lifetime (it stays alive whilst connected), and I don't want that interfering with this test.
                let realtime = try await ClientHelper.realtimeWithObjects(options: .init(autoConnect: false))
                let channel = realtime.channels.get(UUID().uuidString, options: ClientHelper.channelOptionsWithObjects())
                let anyObject = channel.object
                // For some reason putting `channel.object as? PublicDefaultRealtimeObject` inside the #require gives "no calls to throwing functions occur within 'try' expression" 🤷
                let object = try #require(anyObject as? PublicDefaultRealtimeObject)

                return .init(
                    realtimeDeallocQueue: realtime.internal.queue,
                    weakPublicRealtime: realtime,
                    weakInternalRealtime: realtime.internal,
                    weakPublicChannel: channel,
                    weakInternalChannel: channel.internal,
                    strongPublicRealtimeObject: object,
                    weakInternalRealtimeObjects: object.testsOnly_proxied,
                )
            }

            let createdObjects = try await createObjects()

            // The only public object we have a strong reference to is strongPublicRealtimeObject, so the other public objects should have already been deallocated
            #expect(createdObjects.weakPublicRealtime == nil)
            #expect(createdObjects.weakPublicChannel == nil)

            // Now we check that, since we still have a strong reference to strongPublicRealtimeObject, none of the dependencies that it needs in order to function have been deallocated.
            await withCheckedContinuation { continuation in
                // We wait for everything on realtimeDeallocQueue to execute, to be sure that we'd catch a dealloc that had been enqueued via ably-cocoa's QueuedDealloc mechanism.
                createdObjects.realtimeDeallocQueue.async {
                    continuation.resume()
                }
            }
            #expect(createdObjects.weakInternalRealtime != nil)
            #expect(createdObjects.weakInternalChannel != nil)
            #expect(createdObjects.weakInternalRealtimeObjects != nil)

            // TODO: test that we can receive events on a LiveObject (https://github.com/ably/ably-liveobjects-swift-plugin/issues/30)

            // Note that after this return we no longer have a reference to createdObjects and thus no longer have a strong reference to our public RealtimeObject instance
            return .init(
                realtimeDeallocQueue: createdObjects.realtimeDeallocQueue,
                weakInternalRealtime: createdObjects.weakInternalRealtime,
                weakInternalChannel: createdObjects.weakInternalChannel,
                weakPublicRealtimeObject: createdObjects.strongPublicRealtimeObject,
                weakInternalRealtimeObjects: createdObjects.weakInternalRealtimeObjects,
            )
        }

        let remainingObjects = try await createAndDiscardObjects()

        // Check that the public RealtimeObject has been deallocated now that we've no longer got a strong reference to it
        #expect(remainingObjects.weakPublicRealtimeObject == nil)

        // Check that the internal objects that the public RealtimeObject needed in order to function have now been deallocated
        await withCheckedContinuation { continuation in
            // We wait for everything on realtimeDeallocQueue to execute, to be sure that we'd catch a dealloc that had been enqueued via ably-cocoa's QueuedDealloc mechanism.
            remainingObjects.realtimeDeallocQueue.async {
                continuation.resume()
            }
        }

        #expect(remainingObjects.weakInternalRealtime == nil)
        #expect(remainingObjects.weakInternalChannel == nil)
        #expect(remainingObjects.weakInternalRealtimeObjects == nil)
    }

    @Test("LiveObjects functionality works with only a strong reference to a public LiveObject")
    func withStrongReferenceToPublicLiveObject() async throws {
        // Note: This test is very similar to withStrongReferenceToPublicObjectsProperty but "one layer down" — i.e. it checks that instead of a RealtimeObjects reference keeping everything working, a LiveObject reference keeps everything working. Keep these two tests in sync.

        // The objects that we'll create.
        struct CreatedObjects {
            /// The queue on which we expect ably-cocoa's QueuedDealloc mechanism to enqueue the relinquishing of `weakInternalRealtime`.
            var realtimeDeallocQueue: DispatchQueue

            weak var weakPublicRealtime: ARTRealtimeClient?
            weak var weakInternalRealtime: ARTRealtimeClientInternal?
            weak var weakPublicChannel: ARTRealtimeChannel?
            weak var weakInternalChannel: ARTRealtimeChannelInternal?
            weak var weakPublicRealtimeObject: PublicDefaultRealtimeObject?
            weak var weakInternalRealtimeObjects: InternalDefaultRealtimeObjects?
            var strongPublicLiveObject: DefaultLiveMapPathObject
        }

        // What we're left with after discarding a CreatedObjects.
        struct RemainingObjects {
            /// The queue on which we expect ably-cocoa's QueuedDealloc mechanism to enqueue the relinquishing of `weakInternalRealtime`.
            var realtimeDeallocQueue: DispatchQueue

            // weakPublicRealtime is gone now
            weak var weakInternalRealtime: ARTRealtimeClientInternal?
            // weakPublicChannel is gone now
            weak var weakInternalChannel: ARTRealtimeChannelInternal?
            // weakPublicRealtimeObject is gone now
            weak var weakInternalRealtimeObjects: InternalDefaultRealtimeObjects?
            weak var weakPublicLiveObject: DefaultLiveMapPathObject?
        }

        func createAndDiscardObjects() async throws -> RemainingObjects {
            func createObjects() async throws -> CreatedObjects {
                // We disable autoConnect since being connected extends the internal Realtime instance's lifetime (it stays alive whilst connected), and I don't want that interfering with this test.
                let realtime = try await ClientHelper.realtimeWithObjects()
                // Unlike in withStrongReferenceToPublicObjectsProperty, we'll have to allow it to connect, because we need to attach so that get() returns. We'll instead manually close the connection before proceeding with the test
                let channel = realtime.channels.get(UUID().uuidString, options: ClientHelper.channelOptionsWithObjects())
                try await channel.attachAsync()
                let anyObject = channel.object
                // For some reason putting `channel.object as? PublicDefaultRealtimeObject` inside the #require gives "no calls to throwing functions occur within 'try' expression" 🤷
                let object = try #require(anyObject as? PublicDefaultRealtimeObject)
                let root = try #require(try await object.get() as? DefaultLiveMapPathObject)

                // Wait for the connection to close, as mentioned above
                async let connectionClosedPromise: Void = withCheckedContinuation { continuation in
                    realtime.connection.on(.closed) { _ in
                        continuation.resume()
                    }
                }
                realtime.connection.close()
                _ = await connectionClosedPromise

                return .init(
                    realtimeDeallocQueue: realtime.internal.queue,
                    weakPublicRealtime: realtime,
                    weakInternalRealtime: realtime.internal,
                    weakPublicChannel: channel,
                    weakInternalChannel: channel.internal,
                    weakPublicRealtimeObject: object,
                    weakInternalRealtimeObjects: object.testsOnly_proxied,
                    strongPublicLiveObject: root,
                )
            }

            let createdObjects = try await createObjects()

            // The only public object we have a strong reference to is strongPublicLiveObject, so the other public objects should have already been deallocated
            #expect(createdObjects.weakPublicRealtime == nil)
            #expect(createdObjects.weakPublicChannel == nil)
            #expect(createdObjects.weakPublicRealtimeObject == nil)

            // Now we check that, since we still have a strong reference to strongPublicLiveObject, none of the dependencies that it needs in order to function have been deallocated.
            await withCheckedContinuation { continuation in
                // We wait for everything on realtimeDeallocQueue to execute, to be sure that we'd catch a dealloc that had been enqueued via ably-cocoa's QueuedDealloc mechanism.
                createdObjects.realtimeDeallocQueue.async {
                    continuation.resume()
                }
            }
            #expect(createdObjects.weakInternalRealtime != nil)
            #expect(createdObjects.weakInternalChannel != nil)
            #expect(createdObjects.weakInternalRealtimeObjects != nil)

            // TODO: test that we can receive events on a LiveObject (https://github.com/ably/ably-liveobjects-swift-plugin/issues/30)

            // Note that after this return we no longer have a reference to createdObjects and thus no longer have a strong reference to our public LiveObject instance
            return .init(
                realtimeDeallocQueue: createdObjects.realtimeDeallocQueue,
                weakInternalRealtime: createdObjects.weakInternalRealtime,
                weakInternalChannel: createdObjects.weakInternalChannel,
                weakInternalRealtimeObjects: createdObjects.weakInternalRealtimeObjects,
                weakPublicLiveObject: createdObjects.strongPublicLiveObject,
            )
        }

        let remainingObjects = try await createAndDiscardObjects()

        // Check that the public LiveObject has been deallocated now that we've no longer got a strong reference to it
        #expect(remainingObjects.weakPublicLiveObject == nil)

        // Check that the internal objects that the public LiveObject needed in order to function have now been deallocated
        await withCheckedContinuation { continuation in
            // We wait for everything on realtimeDeallocQueue to execute, to be sure that we'd catch a dealloc that had been enqueued via ably-cocoa's QueuedDealloc mechanism.
            remainingObjects.realtimeDeallocQueue.async {
                continuation.resume()
            }
        }

        #expect(remainingObjects.weakInternalRealtime == nil)
        #expect(remainingObjects.weakInternalChannel == nil)
        #expect(remainingObjects.weakInternalRealtimeObjects == nil)
    }

    // Only the `RealtimeObject` is covered here: it is the one public object `PublicObjectsStore`
    // caches, keyed by the internal objects it proxies. `PathObject`s are deliberately excluded —
    // `get()` builds a fresh one per call, because a path object is a navigational reference rather
    // than a handle on a particular object, and pointer identity is offered only at the level of the
    // internal objects a path resolves through. See `PublicObjectsStore` for more.
    @Test("The public RealtimeObject has a stable identity")
    func publicObjectIdentity() async throws {
        let realtime = try await ClientHelper.realtimeWithObjects()
        defer { realtime.close() }
        let channel = realtime.channels.get(UUID().uuidString, options: ClientHelper.channelOptionsWithObjects())
        try await channel.attachAsync()

        let object = try #require(channel.object as? PublicDefaultRealtimeObject)
        let objectAgain = try #require(channel.object as? PublicDefaultRealtimeObject)

        #expect(object === objectAgain)
    }
}
