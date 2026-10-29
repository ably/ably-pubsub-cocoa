    import XCTest
    import AblyPubSubDevice

    final class SPMTests: XCTestCase {
        func pubSubDeviceInitTest() {
            let clientOptions = ClientOptions()
            let _: PubSubClient = PubSubDevice.createClient(options: clientOptions)
            let _ = PubSubDevice.createClient(key: "xxxx:xxxx")
            let _ = PubSubDevice.createClient(token: "xxxx")
        }
    }
