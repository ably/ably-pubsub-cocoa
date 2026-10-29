@testable import AblyLiveObjects
import Foundation

/// A mock delegate that can return predefined objects
final class MockLiveMapObjectsPoolDelegate: LiveMapObjectsPoolDelegate {
    private let poolMutex: DispatchQueueMutex<ObjectsPool>

    init(internalQueue: DispatchQueue) {
        poolMutex = DispatchQueueMutex(
            dispatchQueue: internalQueue,
            initialValue: Self.createPool(
                internalQueue: internalQueue,
                otherEntries: [:],
            ),
        )
    }

    static func createPool(internalQueue: DispatchQueue, otherEntries: [String: ObjectsPool.Entry]) -> ObjectsPool {
        .init(
            // Only otherEntries matters; the others just control the creation of the object at the root key, which none of the tests that use this delegate care about
            logger: TestLogger(),
            internalQueue: internalQueue,
            userCallbackQueue: .main,
            clock: MockSimpleClock(),
            testsOnly_otherEntries: otherEntries,
        )
    }

    var objects: [String: ObjectsPool.Entry] {
        get {
            poolMutex.withSync { $0.entries }
        }
        set {
            poolMutex.withSync { $0 = Self.createPool(internalQueue: poolMutex.dispatchQueue, otherEntries: newValue) }
        }
    }

    var nosync_objectsPool: ObjectsPool {
        poolMutex.withoutSync { $0 }
    }
}
