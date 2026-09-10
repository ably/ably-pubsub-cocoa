import Ably
@testable import AblyLiveObjects

extension ARTRealtimeChannel {
    /// For tests to access the non-public API of `PublicDefaultRealtimeObject`.
    var testsOnly_nonTypeErasedObject: PublicDefaultRealtimeObject {
        nonTypeErasedObject
    }
}
