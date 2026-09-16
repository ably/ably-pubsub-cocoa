import AblyPubSubDevice
import UIKit
import CoreLocation

class AblyHelper: NSObject, ObservableObject {

    static let shared = AblyHelper()

    private var locationManager: CLLocationManager!

    private(set) var realtime: ARTRealtimeClient!

    private let key = "" // Your API Key from your app's dashboard

    var defaultDeviceToken: String?

    var locationDeviceToken: String?

    var activatePushCallback: ((String?, String?, ARTErrorInfo?) -> ())?

    @Published var isSubscribedToExampleChannel1 = false
    @Published var isSubscribedToExampleChannel2 = false
    @Published var isPushActivated = false

    private override init() {
        super.init()
        guard key != "" else {
            preconditionFailure("Obtain your API key at https://ably.com/accounts/")
        }
        let options = ARTClientOptions(key: key)
        options.clientId = "basic-apns-example"
        options.pushRegistererDelegate = self
        self.realtime = ARTRealtimeClient(options: options)
        UNUserNotificationCenter.current().delegate = self
        locationManager = CLLocationManager()
        locationManager.delegate = self
        locationManager.requestAlwaysAuthorization() // for simplicity we put it here, but in the real app you should care about particular moment, when you ask for any permissions
    }
}

extension AblyHelper {

    func activatePush(_ callback: @escaping (String?, String?, ARTErrorInfo?) -> ()) {
        Self.requestUserNotificationAuthorization()
        realtime.push.activate()
        activatePushCallback = callback
    }

    func activateLocationPush() {
        locationManager.startMonitoringLocationPushes { deviceToken, error in
            guard error == nil else {
                return ARTPush.didFailToRegisterForLocationNotificationsWithError(error!, realtime: self.realtime)
            }
            self.locationDeviceToken = deviceToken!.deviceTokenString
            ARTPush.didRegisterForLocationNotifications(withDeviceToken: deviceToken!, realtime: self.realtime)
        }
    }

    func deactivatePush() {
        realtime.push.deactivate()
    }

    func printIdentityToken() {
        let device = realtime.device
        // identityTokenDetails may be nil if the device hasn't been activated for push
        if let details = device.identityTokenDetails {
            // The token is a credential; print only a short prefix so debug
            // output / device logs don't leak it in full.
            let preview = details.token.prefix(8)
            print("Identity token exists for device id \(device.id): \(preview)…")
        } else {
            print("Identity token doesn't exist")
        }
    }

    func getDeviceDetails(_ callback: @escaping (ARTDeviceDetails?, ARTErrorInfo?) -> ()) {
        realtime.push.admin.deviceRegistrations.get(realtime.device.id, callback: callback)
    }

    // For this to work you must turn on 'Push Admin' capability in your API key settings
    func sendAdminPush(title: String, body: String) {
        let recipient = [
            "deviceId": realtime.device.id
        ]
        let data = [
            "notification": [
                "title": title,
                "body": body
            ],
            "data": [
                "foo": "bar",
                "baz": "qux"
            ]
        ]
        realtime.push.admin.publish(recipient, data: data) { error in
            print("Publish result: \(error?.localizedDescription ?? "Success")")
        }
    }

    func sendPushToChannel(_ channel: Channel) {
        let message = ARTMessage(name: "example", data: "rest data")
        message.extras = [
            "push": [
                "notification": [
                    "title": "Channel Push",
                    "body": "Sent push to \(channel.rawValue)"
                ],
                "data": [
                    "foo": "bar",
                    "baz": "qux"
                ]
            ]
        ] as any ARTJsonCompatible

        realtime.channels.get(channel.rawValue).publish([message]) { error in
            if let error {
                print("Error sending push to \(channel.rawValue) with error: \(error.localizedDescription)")
            } else {
                print("Sent push to \(channel.rawValue)")
            }
        }
    }

    func subscribeToChannel(_ channel: Channel) {
        realtime.channels.get(channel.rawValue).push.subscribeDevice { error in
            guard error == nil else {
                print("Error subscribing to \(channel.rawValue) with error: \(error!.localizedDescription)")
                return
            }
            print("Succesfully subscribed to \(channel.rawValue)")

            switch channel {
            case .exampleChannel1:
                self.isSubscribedToExampleChannel1 = true
            case .exampleChannel2:
                self.isSubscribedToExampleChannel2 = true
            }
        }
    }

    func unsubscribeFromChannel(_ channel: Channel) {
        realtime.channels.get(channel.rawValue).push.unsubscribeDevice { error in
            guard error == nil else {
                print("Error subscribing to \(channel.rawValue) with error: \(error!.localizedDescription)")
                return
            }

            print("Succesfully unsubscribed from \(channel.rawValue)")
            switch channel {
            case .exampleChannel1:
                self.isSubscribedToExampleChannel1 = false
            case .exampleChannel2:
                self.isSubscribedToExampleChannel2 = false
            }
        }
    }
}

extension AblyHelper: ARTPushRegistererDelegate {

    func didActivateAblyPush(_ error: ARTErrorInfo?) {
        print("Push activation: \(error?.localizedDescription ?? "Success")")
        activatePushCallback?(defaultDeviceToken, locationDeviceToken, error)
        activateLocationPush()
        if error == nil {
            isPushActivated = true
        }
    }

    func didDeactivateAblyPush(_ error: ARTErrorInfo?) {
        print("Push deactivation: \(error?.localizedDescription ?? "Success")")
        if error == nil {
            isPushActivated = false
        }
    }

    func didUpdateAblyPush(_ error: ARTErrorInfo?) {
        print("Push update: \(error?.localizedDescription ?? "Success")")
        activatePushCallback?(defaultDeviceToken, locationDeviceToken, error)
    }
}

extension AblyHelper: UNUserNotificationCenterDelegate {

    static func requestUserNotificationAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options:[.badge, .alert, .sound]) { granted, error in
            DispatchQueue.main.async() {
                print("Push auth: \(error?.localizedDescription ?? (granted ? "Granted" : "Not Granted"))")
            }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        print("Got push notification!")
        completionHandler([.banner, .sound])
    }
}

extension AblyHelper : CLLocationManagerDelegate {

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways:
            print("Location services always authorized.")
        case .notDetermined, .authorizedWhenInUse, .restricted, .denied:
            print("Location services unavailable for location pushes.")
            break
        default:
            break
        }
    }
}

enum Channel: String {
    case exampleChannel1
    case exampleChannel2
}
