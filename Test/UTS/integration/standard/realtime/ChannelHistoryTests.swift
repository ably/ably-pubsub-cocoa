import Testing
import Foundation
import Ably

/// RealtimeChannel history (RTL10d)
/// Derived from ably/specification `uts/realtime/integration/channel_history_test.md`
///
/// Direct-sandbox integration test against the Ably Sandbox (`sandbox.realtime.ably-nonprod.net`,
/// via SandboxApp.sandboxHost) — no proxy, no fault injection. Provisions a throwaway SandboxApp
/// and connects real clients straight to the sandbox. Needs outbound network:
///
/// ```bash
/// swift test --filter UTS.ChannelHistoryTests
/// ```
@Suite(.serialized)
final class ChannelHistoryTests: IntegrationTestCase {

    // UTS: realtime/integration/RTL10d/history-cross-client-0
    @Test(arguments: [false, true]) // useBinaryProtocol: false = JSON, true = msgpack
    func test_RTL10d_history_contains_messages_published_by_another_client(useBinaryProtocol: Bool) async throws {
        // The spec's BEFORE/AFTER ALL sandbox app provisioning is owned by the withSandboxApp scope.
        try await withSandboxApp { app in
            // Setup
            let channelName = "history-RTL10d-\(UUID().uuidString)"

            let publisherOptions = ARTClientOptions(key: app.defaultKey)
            publisherOptions.realtimeHost = SandboxApp.sandboxHost
            publisherOptions.restHost = SandboxApp.sandboxHost
            publisherOptions.useBinaryProtocol = useBinaryProtocol
            publisherOptions.autoConnect = false

            let subscriberOptions = ARTClientOptions(key: app.defaultKey)
            subscriberOptions.realtimeHost = SandboxApp.sandboxHost
            subscriberOptions.restHost = SandboxApp.sandboxHost
            subscriberOptions.useBinaryProtocol = useBinaryProtocol
            subscriberOptions.autoConnect = false

            try await withRealtimeClient(publisherOptions) { publisher in
                try await withRealtimeClient(subscriberOptions) { subscriber in
                    publisher.connect()
                    subscriber.connect()

                    // The spec times these in-body connect-awaits explicitly (WITH timeout: 10 seconds).
                    guard await awaitState(publisher, .connected, timeout: 10) else { return }
                    guard await awaitState(subscriber, .connected, timeout: 10) else { return }

                    let pubChannel = publisher.channels.get(channelName)
                    let subChannel = subscriber.channels.get(channelName)

                    pubChannel.attach()
                    guard await awaitChannelState(pubChannel, .attached, timeout: 10) else { return }
                    subChannel.attach()
                    guard await awaitChannelState(subChannel, .attached, timeout: 10) else { return }

                    // Test Steps
                    // Publish messages from publisher client and await confirmation
                    await awaitPublish(pubChannel, name: "event1", data: "data1")
                    await awaitPublish(pubChannel, name: "event2", data: "data2")
                    await awaitPublish(pubChannel, name: "event3", data: "data3")

                    // Retrieve history from subscriber client
                    // Poll until all messages appear, keeping the page the poll settled on —
                    // a refetch could hit a less-replicated frontend and return fewer items than the poll just observed.
                    guard let historyItems = try await pollUntil("subscriber history contains all 3 messages", timeout: 10, interval: 0.5, {
                        let items = try await self.historyItems(of: subChannel)
                        return items.count == 3 ? items : nil
                    }) else { return }

                    // Assertions
                    try #require(historyItems.count == 3)

                    // Default order is backwards (newest first)
                    #expect(historyItems[0].name == "event3")
                    #expect(historyItems[0].data as? String == "data3")

                    #expect(historyItems[1].name == "event2")
                    #expect(historyItems[1].data as? String == "data2")

                    #expect(historyItems[2].name == "event1")
                    #expect(historyItems[2].data as? String == "data1")

                    // Cleanup (per spec): publisher.close() / subscriber.close() are handled by the
                    // withRealtimeClient scopes (close + await CLOSED).
                }
            }
        }
    }
}

extension ChannelHistoryTests {
    /// Awaits the publish acknowledgement (the spec's `AWAIT pub_channel.publish(...)`), recording
    /// an issue on error.
    private func awaitPublish(_ channel: ARTRealtimeChannel,
                              name: String,
                              data: String,
                              sourceLocation: SourceLocation = #_sourceLocation) async {
        let failure: String? = await withCheckedContinuation { continuation in
            channel.publish(name, data: data) { error in
                continuation.resume(returning: error.map { "\($0)" })
            }
        }

        if let failure {
            Issue.record("publish(\(name)) failed: \(failure)", sourceLocation: sourceLocation)
        }
    }

    /// Fetches the channel's history (default query — backwards order) and returns its items,
    /// propagating any `history()` error so it aborts the enclosing `pollUntil` and surfaces the
    /// real failure — matching the plain `poll_until` reference semantics (js/java do the same).
    /// The eventual-consistency race is an under-count, absorbed by the poll's count check, not an
    /// error.
    private func historyItems(of channel: ARTRealtimeChannel) async throws -> [ARTMessage] {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[ARTMessage], Error>) in
            channel.history { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: result?.items ?? [])
                }
            }
        }
    }
}
