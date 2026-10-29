import AblyPubSubDevice
import SwiftUI

struct ContentView: View {
    @StateObject private var ablyHelper = AblyHelper.shared

    @State var showDeviceDetailsAlert = false
    @State var deviceDetails: DeviceDetails?
    @State var deviceDetailsError: ErrorInfo?

    @State var showDeviceTokensAlert = false
    @State var defaultDeviceToken: String?
    @State var locationDeviceToken: String?
    @State var deviceTokensError: ErrorInfo?

    var body: some View {
        NavigationView {
            VStack {
                Image("ably-logo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 44)
                    .padding()

                PushButton(
                    isButtonEnabled: true, // Button to toggle push activation is always enabled
                    systemImage: ablyHelper.isPushActivated ? "bell.slash" : "bell",
                    activeTitle: "Deactivate Push",
                    inactiveTitle: "Activate Push",
                    isActive: ablyHelper.isPushActivated,
                    action: {
                        if ablyHelper.isPushActivated {
                            ablyHelper.deactivatePush()
                        } else {
                            AblyHelper.shared.activatePush {
                                defaultDeviceToken = $0
                                locationDeviceToken = $1
                                deviceTokensError = $2
                                showDeviceTokensAlert = true
                            }
                        }
                    }
                )
                .alert(isPresented: $showDeviceTokensAlert) {
                    if let deviceTokensError = deviceTokensError {
                        return Alert(title: Text("Device Tokens"), message: Text("Error: \(deviceTokensError)"))
                    }
                    else if let defaultDeviceToken = defaultDeviceToken, let locationDeviceToken = locationDeviceToken {
                        return Alert(title: Text("Device Tokens"),
                                     message: Text("Default: \(defaultDeviceToken)\n\nLocation: \(locationDeviceToken)"))
                    }
                    else if let defaultDeviceToken = defaultDeviceToken {
                        return Alert(title: Text("Device Tokens"), message: Text("Default: \(defaultDeviceToken)"))
                    }
                    return Alert(title: Text("Push activation"), message: Text("Success"))
                }

                HStack {
                    let backgroundColor = Color(red: 0.40, green: 0.44, blue: 0.52)
                    StatelessButton(
                        isButtonEnabled: ablyHelper.isPushActivated,
                        systemImage: "printer.fill",
                        title: "Print Token",
                        backgroundColor: backgroundColor,
                        action: {
                            ablyHelper.printIdentityToken()
                        }
                    )
                    StatelessButton(
                        isButtonEnabled: ablyHelper.isPushActivated,
                        systemImage: "info.circle.fill",
                        title: "Device Details",
                        backgroundColor: backgroundColor,
                        action: {
                            AblyHelper.shared.getDeviceDetails { details, error in
                                deviceDetails = details
                                deviceDetailsError = error
                                showDeviceDetailsAlert = true
                            }
                        }
                    )
                }
                .fixedSize(horizontal: false, vertical: true)

                .alert(isPresented: $showDeviceDetailsAlert) {
                    if deviceDetails != nil {
                        return Alert(title: Text("Device Details"), message: Text("\(deviceDetails!)"))
                    }
                    else if deviceDetailsError != nil {
                        return Alert(title: Text("Device Details Error"), message: Text("\(deviceDetailsError!)"))
                    }
                    return Alert(title: Text("Device Details Error"), message: Text("Unknown result."))
                }
                Text("Device Push")
                    .fontWeight(.bold)
                    .padding(.top)
                StatelessButton(
                    isButtonEnabled: ablyHelper.isPushActivated,
                    systemImage: "iphone.gen3",
                    title: "Send Push to deviceId",
                    action: {
                        AblyHelper.shared.sendAdminPush(title: "Hello", body: "This push was sent with deviceId")
                    }
                )
                .fixedSize(horizontal: false, vertical: true)
                Text("Channels Push")
                    .fontWeight(.bold)
                    .padding(.top)

                HStack {
                    PushButton(
                        isButtonEnabled: ablyHelper.isPushActivated,
                        systemImage: ablyHelper.isSubscribedToExampleChannel1
                        ? "xmark.circle.fill"
                        : "checkmark.circle.fill",
                        activeTitle: "Unsubscribe from exampleChannel1",
                        inactiveTitle: "Subscribe to exampleChannel1",
                        isActive: ablyHelper.isSubscribedToExampleChannel1,
                        action: {
                            if ablyHelper.isSubscribedToExampleChannel1 {
                                ablyHelper.unsubscribeFromChannel(.exampleChannel1)
                            } else {
                                ablyHelper.subscribeToChannel(.exampleChannel1)
                            }
                        }
                    )
                    PushButton(
                        isButtonEnabled: ablyHelper.isPushActivated,
                        systemImage: ablyHelper.isSubscribedToExampleChannel2
                        ? "xmark.circle.fill"
                        : "checkmark.circle.fill",
                        activeTitle: "Unsubscribe from exampleChannel2",
                        inactiveTitle: "Subscribe to exampleChannel2",
                        isActive: ablyHelper.isSubscribedToExampleChannel2,
                        action: {
                            if ablyHelper.isSubscribedToExampleChannel2 {
                                ablyHelper.unsubscribeFromChannel(.exampleChannel2)
                            } else {
                                ablyHelper.subscribeToChannel(.exampleChannel2)
                            }
                        }
                    )
                }
                .fixedSize(horizontal: false, vertical: true)

                HStack {
                    StatelessButton(
                        isButtonEnabled: ablyHelper.isPushActivated && ablyHelper.isSubscribedToExampleChannel1,
                        systemImage: "paperplane.circle.fill",
                        title: "Send Push to \(Channel.exampleChannel1.rawValue)",
                        action: {
                            AblyHelper.shared.sendPushToChannel(.exampleChannel1)
                        }
                    )
                    StatelessButton(
                        isButtonEnabled: ablyHelper.isPushActivated && ablyHelper.isSubscribedToExampleChannel2,
                        systemImage: "paperplane.circle.fill",
                        title: "Send Push to \(Channel.exampleChannel2.rawValue)",
                        action: {
                            AblyHelper.shared.sendPushToChannel(.exampleChannel2)
                        }
                    )
                }
                .fixedSize(horizontal: false, vertical: true)

                #if USE_LOCATION_PUSH
                NavigationLink {
                    LocationPushEventsView()
                } label: {
                    Text("Location push events")
                }
                .padding()
                #endif
                Spacer()
            }
            .padding()
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
