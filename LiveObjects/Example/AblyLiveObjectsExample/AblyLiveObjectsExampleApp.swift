import AblyLiveObjects
import AblyPubSubDevice
import SwiftUI

@main
struct AblyLiveObjectsExampleApp: App {
    private func getClient() -> PubSubClient {
        let clientOptions = ClientOptions(key: Secrets.ablyAPIKey)
        clientOptions.plugins = [.liveObjects: AblyLiveObjects.Plugin.self]
        return PubSubDevice.createClient(options: clientOptions)
    }

    var body: some Scene {
        WindowGroup {
            #if os(macOS)
                ContentView(client1: getClient(), client2: getClient())
                    .frame(width: 400, height: 700, alignment: .center)
            #else
                ContentView(client1: getClient(), client2: getClient())
            #endif
        }
        #if os(macOS)
        .windowResizability(.contentSize)
        #endif
    }
}
