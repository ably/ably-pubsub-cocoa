    import XCTest
    import AblyPubSubDevice

    final class SPMTests: XCTestCase {
        func ablyInitTest() {
            let clientOptions = ARTClientOptions()
            let _ = ARTHttpClient(options: clientOptions)
            let _ = ARTRealtime(options: clientOptions)
        }

        func pubSubDeviceInitTest() {
            let clientOptions = ARTClientOptions()
            let _ = PubSubDevice.createClient(options: clientOptions)
            let _ = PubSubDevice.createClient(key: "xxxx:xxxx")
            let _ = PubSubDevice.createClient(token: "xxxx")
        }
    }
