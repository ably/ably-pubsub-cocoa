import AblyPubSubDevice
@testable import AblyLiveObjects

extension RealtimeChannel {
    /// For tests to access the non-public API of `PublicDefaultRealtimeObject`.
    var testsOnly_nonTypeErasedObject: PublicDefaultRealtimeObject {
        nonTypeErasedObject
    }
}
