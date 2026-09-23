import AblyPubSubDevice
import SwiftUI

@main
struct AblyCocoaAPNSExampleApp: App {

    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        AblyHelper.shared.defaultDeviceToken = deviceToken.deviceTokenString
        Push.didRegisterForRemoteNotifications(withDeviceToken: deviceToken, pubsub: AblyHelper.shared.client)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Push.didFailToRegisterForRemoteNotificationsWithError(error, pubsub: AblyHelper.shared.client)
    }
}

extension Data {

    var deviceTokenString: String {
        var result = ""
        for byte in self {
            result += String(format: "%02x", UInt(byte))
        }
        return result
    }
}
