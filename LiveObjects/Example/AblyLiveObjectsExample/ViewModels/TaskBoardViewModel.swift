import AblyLiveObjects
import AblyPubSubDevice
import SwiftUI

@MainActor
final class TaskBoardViewModel: ObservableObject {
    @Published var tasks: [String: String] = [:]
    @Published var isLoading = true
    @Published var errorMessage: String?

    private var channel: RealtimeChannel
    private var object: any RealtimeObject
    private var root: (any LiveMapPathObject)?

    private var subscriptions: [String: any Subscription] = [:]

    init(client: PubSubClient, channelName: String = "objects-live-map") {
        let channelOptions = RealtimeChannelOptions()
        channelOptions.modes = [.objectPublish, .objectSubscribe]
        channel = client.channels.get(channelName, options: channelOptions)
        object = channel.object

        Task {
            await initializeTasks()
        }
    }

    deinit {
        // Clean up subscriptions
        subscriptions.values.forEach { $0.unsubscribe() }
        subscriptions.removeAll()
    }

    /// A path object for the tasks map. Purely navigational (does not resolve the path), and it
    /// survives the map being replaced by `removeAllTasks` — unlike the previous proxy-object API,
    /// there is no need to re-fetch anything when the object at the path changes.
    private var tasksMapPath: (any LiveMapPathObject)? {
        root?.get(key: "tasks").asLiveMap()
    }

    private func initializeTasks() async {
        do {
            isLoading = true
            errorMessage = nil

            // Get the root map path object. `object.get()` performs the ensure-active-channel
            // procedure (RTO23e/RTL33), so it implicitly attaches the channel — no explicit
            // attach needed — and resolves once the objects are synchronized.
            let root = try await object.get()
            self.root = root

            // Create the tasks map if nothing exists at its path yet. (Creation is declarative in
            // the path-based API: setting a `LiveMap` value type creates the map.)
            if let tasksMapPath, try !tasksMapPath.exists() {
                try await root.set(key: "tasks", value: .liveMap(.create()))
            }

            loadTasks()
            subscribeToTasksUpdates()

            isLoading = false
        } catch {
            errorMessage = "Failed to initialize: \(error.localizedDescription)"
            isLoading = false
        }
    }

    private func loadTasks() {
        do {
            guard let tasksMapPath else {
                return
            }

            var currentTasks: [String: String] = [:]
            for (key, value) in try tasksMapPath.entries() {
                if let stringValue = try value.asPrimitive().stringValue() {
                    currentTasks[key] = stringValue
                }
            }
            tasks = currentTasks
        } catch {
            errorMessage = "Failed to load tasks: \(error.localizedDescription)"
        }
    }

    private func subscribeToTasksUpdates() {
        do {
            guard let tasksMapPath else {
                return
            }

            // Clean up existing subscription
            subscriptions["tasks"]?.unsubscribe()

            // Subscribe to updates. Because the subscription is path-based, it also survives the
            // tasks map being replaced by `removeAllTasks`; there is no need to re-subscribe. The
            // event does not carry a per-key change set, so reload the tasks on each update.
            subscriptions["tasks"] = try tasksMapPath.subscribe { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.loadTasks()
                }
            }
        } catch {
            errorMessage = "Failed to subscribe to tasks: \(error.localizedDescription)"
        }
    }

    func addTask(_ title: String) {
        let taskTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !taskTitle.isEmpty else {
            return
        }

        Task {
            do {
                let taskId = UUID().uuidString
                try await tasksMapPath?.set(key: taskId, value: .primitive(.string(taskTitle)))
            } catch {
                errorMessage = "Failed to add task: \(error.localizedDescription)"
            }
        }
    }

    func editTask(id: String, newTitle: String) {
        let taskTitle = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !taskTitle.isEmpty else {
            return
        }

        Task {
            do {
                try await tasksMapPath?.set(key: id, value: .primitive(.string(taskTitle)))
            } catch {
                errorMessage = "Failed to edit task: \(error.localizedDescription)"
            }
        }
    }

    func removeTask(id: String) {
        Task {
            do {
                try await tasksMapPath?.remove(key: id)
            } catch {
                errorMessage = "Failed to remove task: \(error.localizedDescription)"
            }
        }
    }

    func removeAllTasks() {
        Task {
            do {
                // Replace the tasks map with a fresh empty one. The stored path objects and the
                // path-based subscription automatically refer to the new map.
                try await root?.set(key: "tasks", value: .liveMap(.create()))
            } catch {
                errorMessage = "Failed to remove all tasks: \(error.localizedDescription)"
            }
        }
    }
}
