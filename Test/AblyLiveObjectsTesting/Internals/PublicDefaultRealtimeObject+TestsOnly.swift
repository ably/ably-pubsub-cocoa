@testable import AblyLiveObjects

extension PublicDefaultRealtimeObject {
    var testsOnly_proxied: InternalDefaultRealtimeObjects {
        proxied
    }

    var testsOnly_coreSDK: CoreSDK {
        coreSDK
    }
}
