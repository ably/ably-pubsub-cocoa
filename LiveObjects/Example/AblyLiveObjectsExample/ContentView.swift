import AblyLiveObjects
import AblyPubSubDevice
import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel1: LiveCounterViewModel
    @StateObject private var viewModel2: LiveCounterViewModel
    @StateObject private var taskViewModel1: TaskBoardViewModel
    @StateObject private var taskViewModel2: TaskBoardViewModel
    private let client1: PubSubClient
    private let client2: PubSubClient

    init(client1: PubSubClient, client2: PubSubClient) {
        _viewModel1 = StateObject(wrappedValue: LiveCounterViewModel(client: client1))
        _viewModel2 = StateObject(wrappedValue: LiveCounterViewModel(client: client2))
        _taskViewModel1 = StateObject(wrappedValue: TaskBoardViewModel(client: client1))
        _taskViewModel2 = StateObject(wrappedValue: TaskBoardViewModel(client: client2))
        self.client1 = client1
        self.client2 = client2
    }

    var body: some View {
        TabView {
            // Live Counter tab
            Group {
                VStack(spacing: 1) {
                    LiveCounterView(viewModel: viewModel1, clientTitle: "Client 1")
                    Divider()
                    LiveCounterView(viewModel: viewModel2, clientTitle: "Client 2")
                }
            }
            .tabItem {
                Image(systemName: "plus.forwardslash.minus")
                Text("Live Counter")
            }

            // Task Board tab
            Group {
                VStack(spacing: 1) {
                    TaskBoardView(viewModel: taskViewModel1, clientTitle: "Client 1")
                    Divider()
                    TaskBoardView(viewModel: taskViewModel2, clientTitle: "Client 2")
                }
            }
            .tabItem {
                Image(systemName: "checklist")
                Text("Task Board")
            }
        }
    }
}
