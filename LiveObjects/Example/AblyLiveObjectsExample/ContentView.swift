import AblyLiveObjects
import AblyPubSubDevice
import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel1: LiveCounterViewModel
    @StateObject private var viewModel2: LiveCounterViewModel
    @StateObject private var taskViewModel1: TaskBoardViewModel
    @StateObject private var taskViewModel2: TaskBoardViewModel
    private let realtime1: ARTRealtime
    private let realtime2: ARTRealtime

    init(realtime1: ARTRealtime, realtime2: ARTRealtime) {
        _viewModel1 = StateObject(wrappedValue: LiveCounterViewModel(realtime: realtime1))
        _viewModel2 = StateObject(wrappedValue: LiveCounterViewModel(realtime: realtime2))
        _taskViewModel1 = StateObject(wrappedValue: TaskBoardViewModel(realtime: realtime1))
        _taskViewModel2 = StateObject(wrappedValue: TaskBoardViewModel(realtime: realtime2))
        self.realtime1 = realtime1
        self.realtime2 = realtime2
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
