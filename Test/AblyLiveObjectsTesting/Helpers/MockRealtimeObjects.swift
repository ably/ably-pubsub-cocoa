import _AblyPluginSupportPrivate
import Ably
@testable import AblyLiveObjects

final class MockRealtimeObjects: InternalRealtimeObjectsProtocol {
    private let objectsPoolDelegate: MockLiveMapObjectsPoolDelegate?

    /// Synchronizes access to `_publishAndApplyHandler`.
    private let mutex = NSLock()
    private nonisolated(unsafe) var _publishAndApplyHandler: (([ProtocolTypes.OutboundObjectMessage]) -> Result<Void, ARTErrorInfo>)?

    /// A real (unused-in-dispatch) register so the type conforms to `InternalRealtimeObjectsProtocol`.
    /// Tests that exercise path-subscription dispatch use the real `InternalDefaultRealtimeObjects`.
    private let _pathObjectSubscriptionRegister = PathObjectSubscriptionRegister(
        internalQueue: DispatchQueue(label: "MockRealtimeObjects.internal"),
        userCallbackQueue: DispatchQueue(label: "MockRealtimeObjects.userCallback"),
    )

    init(objectsPoolDelegate: MockLiveMapObjectsPoolDelegate? = nil) {
        self.objectsPoolDelegate = objectsPoolDelegate
    }

    var pathObjectSubscriptionRegister: PathObjectSubscriptionRegister {
        _pathObjectSubscriptionRegister
    }

    var nosync_objectsPool: ObjectsPool {
        guard let objectsPoolDelegate else {
            preconditionFailure("MockRealtimeObjects was not initialised with an objectsPoolDelegate")
        }
        return objectsPoolDelegate.nosync_objectsPool
    }

    func setPublishAndApplyHandler(_ handler: @escaping ([ProtocolTypes.OutboundObjectMessage]) -> Result<Void, ARTErrorInfo>) {
        mutex.withLock {
            _publishAndApplyHandler = handler
        }
    }

    func nosync_publishAndApply(
        objectMessages: [ProtocolTypes.OutboundObjectMessage],
        coreSDK: CoreSDK,
        callback: @escaping @Sendable (Result<Void, ARTErrorInfo>) -> Void,
    ) {
        var handler: (([ProtocolTypes.OutboundObjectMessage]) -> Result<Void, ARTErrorInfo>)?
        mutex.withLock {
            handler = _publishAndApplyHandler
        }

        if let handler {
            callback(handler(objectMessages))
        } else {
            callback(.success(()))
        }
    }
}
