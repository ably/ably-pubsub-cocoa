import AblyLiveObjects
import AblyPubSubDevice
import SwiftUI

enum VoteColor: String, CaseIterable {
    case red
    case green
    case blue

    var displayName: String {
        rawValue.capitalized
    }

    var swiftUIColor: SwiftUI.Color {
        switch self {
        case .red:
            .red
        case .green:
            .green
        case .blue:
            .blue
        }
    }
}

@MainActor
final class LiveCounterViewModel: ObservableObject {
    @Published var redCount: Double = 0
    @Published var greenCount: Double = 0
    @Published var blueCount: Double = 0
    @Published var isLoading = true
    @Published var errorMessage: String?

    private var channel: ARTRealtimeChannel
    private var object: any RealtimeObject
    private var root: (any LiveMapPathObject)?

    private var subscriptions: [String: any Subscription] = [:]

    init(realtime: ARTRealtime) {
        // Use URL parameters or default channel name
        let channelName = "live-objects-counter"
        let channelOptions = ARTRealtimeChannelOptions()
        channelOptions.modes = [.objectPublish, .objectSubscribe]
        channel = realtime.channels.get(channelName, options: channelOptions)
        object = channel.object

        Task {
            await initializeCounters()
        }
    }

    deinit {
        // Clean up subscriptions
        subscriptions.values.forEach { $0.unsubscribe() }
        subscriptions.removeAll()
    }

    /// A path object for the counter of a given color. Purely navigational (does not resolve the
    /// path), and it survives the counter being replaced by `resetCounter` — unlike the previous
    /// proxy-object API, there is no need to re-fetch anything when the object at the path changes.
    private func counterPath(for color: VoteColor) -> (any LiveCounterPathObject)? {
        root?.get(key: color.rawValue).asLiveCounter()
    }

    private func initializeCounters() async {
        do {
            isLoading = true
            errorMessage = nil

            // Get the root map path object. `object.get()` performs the ensure-active-channel
            // procedure (RTO23e/RTL33), so it implicitly attaches the channel — no explicit
            // attach needed — and resolves once the objects are synchronized.
            let root = try await object.get()
            self.root = root

            // Initialize all color counters
            for color in VoteColor.allCases {
                await initializeCounter(for: color)
            }

            isLoading = false
        } catch {
            errorMessage = "Failed to initialize: \(error.localizedDescription)"
            isLoading = false
        }
    }

    private func initializeCounter(for color: VoteColor) async {
        do {
            guard let counterPath = counterPath(for: color) else {
                return
            }

            // Create the counter if nothing exists at its path yet. (Creation is declarative in the
            // path-based API: setting a `LiveCounter` value type creates the counter.)
            if try !counterPath.exists() {
                try await root?.set(key: color.rawValue, value: .liveCounter(.create()))
            }

            // Read its current value and subscribe to updates
            updateCounterValue(for: color)
            subscribeToCounter(color: color)
        } catch {
            errorMessage = "Failed to initialize \(color.rawValue) counter: \(error.localizedDescription)"
        }
    }

    private func subscribeToCounter(color: VoteColor) {
        do {
            guard let counterPath = counterPath(for: color) else {
                return
            }

            subscriptions[color.rawValue]?.unsubscribe()

            // Because the subscription is path-based, it also survives the counter being replaced
            // by `resetCounter`; there is no need to re-subscribe.
            subscriptions[color.rawValue] = try counterPath.subscribe { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.updateCounterValue(for: color)
                }
            }

            updateCounterValue(for: color)
        } catch {
            errorMessage = "Failed to subscribe to \(color.rawValue) counter: \(error)"
        }
    }

    private func updateCounterValue(for color: VoteColor) {
        do {
            guard let value = try counterPath(for: color)?.value() else {
                return
            }
            switch color {
            case .red:
                redCount = value
            case .green:
                greenCount = value
            case .blue:
                blueCount = value
            }
        } catch {
            errorMessage = "Error updating \(color.rawValue) counter value: \(error)"
        }
    }

    func vote(for color: VoteColor) {
        Task {
            do {
                try await counterPath(for: color)?.increment()
            } catch {
                errorMessage = "Failed to vote for \(color.rawValue): \(error.localizedDescription)"
            }
        }
    }

    func resetCounter(color: VoteColor) {
        Task {
            do {
                // Replace the counter with a fresh zero-count one. The stored path objects and the
                // path-based subscription automatically refer to the new counter.
                try await root?.set(key: color.rawValue, value: .liveCounter(.create()))
            } catch {
                errorMessage = "Failed to reset counters: \(error.localizedDescription)"
            }
        }
    }

    func resetAllCounters() {
        for color in VoteColor.allCases {
            resetCounter(color: color)
        }
    }
}
