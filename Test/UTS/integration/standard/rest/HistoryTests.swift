import Testing
import Foundation
import Ably

/// REST channel history (RSL2a, RSL2b, RSL2b1, RSL2b2, RSL2b3)
/// Derived from ably/specification `uts/rest/integration/history.md`
///
/// Direct-sandbox integration test against the Ably Sandbox (`sandbox.realtime.ably-nonprod.net`,
/// via SandboxApp.sandboxHost) — no proxy, no fault injection. Provisions a throwaway SandboxApp
/// and points real REST clients straight at the sandbox. Needs outbound network:
///
/// ```bash
/// swift test --filter UTS.HistoryTests
/// ```
@Suite(.serialized)
final class HistoryTests: IntegrationTestCase {

    // UTS: rest/integration/RSL2a/history-returns-messages-0
    @Test(arguments: [false, true]) // useBinaryProtocol: false = JSON, true = msgpack
    func test_RSL2a_history_returns_published_messages(useBinaryProtocol: Bool) async throws {
        // The spec's BEFORE/AFTER ALL sandbox app provisioning is owned by the withSandboxApp scope.
        try await withSandboxApp { app in
            // Setup
            let options = ARTClientOptions(key: app.defaultKey)
            options.restHost = SandboxApp.sandboxHost // the spec's endpoint: "nonprod:sandbox"
            options.useBinaryProtocol = useBinaryProtocol
            let client = ARTRest(options: options)
            let channelName = "history-test-RSL2a-\(UUID().uuidString)"
            let channel = client.channels.get(channelName)

            // Test Steps
            // Publish some messages
            await self.awaitPublish(channel, name: "event1", data: "data1")
            await self.awaitPublish(channel, name: "event2", data: "data2")
            await self.awaitPublish(channel, name: "event3", data: ["key": "value"])

            // Poll until messages appear in history, keeping the page the poll settled on —
            // a refetch could hit a less-replicated frontend and return fewer items than the poll just observed.
            guard let history = try await pollUntil("channel history contains all 3 messages", timeout: 10, interval: 0.5, {
                let items = try await self.historyItems(of: channel)
                return items.count == 3 ? items : nil
            }) else { return }

            // Assertions
            try #require(history.count == 3)

            // Default order is backwards (newest first)
            #expect(history[0].name == "event3")
            #expect(history[0].data as? NSDictionary == ["key": "value"])

            #expect(history[1].name == "event2")
            #expect(history[1].data as? String == "data2")

            #expect(history[2].name == "event1")
            #expect(history[2].data as? String == "data1")

            // All messages should have timestamps
            #expect(history.allSatisfy { $0.timestamp != nil })
        }
    }

    // UTS: rest/integration/RSL2b1/history-direction-forwards-0
    @Test(arguments: [false, true]) // useBinaryProtocol: false = JSON, true = msgpack
    func test_RSL2b1_history_direction_forwards(useBinaryProtocol: Bool) async throws {
        try await withSandboxApp { app in
            // Setup
            let options = ARTClientOptions(key: app.defaultKey)
            options.restHost = SandboxApp.sandboxHost // the spec's endpoint: "nonprod:sandbox"
            options.useBinaryProtocol = useBinaryProtocol
            let client = ARTRest(options: options)
            let channelName = "history-direction-\(UUID().uuidString)"
            let channel = client.channels.get(channelName)

            // Test Steps
            // Publish messages - ordering is determined by server timestamp
            await self.awaitPublish(channel, name: "first", data: "1")
            await self.awaitPublish(channel, name: "second", data: "2")
            await self.awaitPublish(channel, name: "third", data: "3")

            // Poll until all messages appear
            guard try await pollUntil("channel history contains all 3 messages", timeout: 10, interval: 0.5, {
                try await self.historyItems(of: channel).count == 3
            }) else { return }

            let forwardsQuery = ARTDataQuery()
            forwardsQuery.direction = .forwards
            let history = await historyItems(of: channel, query: forwardsQuery)

            // Assertions
            try #require(history.count == 3)
            #expect(history[0].name == "first")
            #expect(history[1].name == "second")
            #expect(history[2].name == "third")
        }
    }

    // UTS: rest/integration/RSL2b2/history-limit-parameter-0
    @Test(arguments: [false, true]) // useBinaryProtocol: false = JSON, true = msgpack
    func test_RSL2b2_history_limit_parameter(useBinaryProtocol: Bool) async throws {
        try await withSandboxApp { app in
            // Setup
            let options = ARTClientOptions(key: app.defaultKey)
            options.restHost = SandboxApp.sandboxHost // the spec's endpoint: "nonprod:sandbox"
            options.useBinaryProtocol = useBinaryProtocol
            let client = ARTRest(options: options)
            let channelName = "history-limit-\(UUID().uuidString)"
            let channel = client.channels.get(channelName)

            // Test Steps
            // Publish multiple messages
            for i in 1...10 {
                await self.awaitPublish(channel, name: "event-\(i)", data: "\(i)")
            }

            // Poll until all messages are persisted
            guard try await pollUntil("channel history contains all 10 messages", timeout: 10, interval: 0.5, {
                try await self.historyItems(of: channel).count == 10
            }) else { return }

            let limitQuery = ARTDataQuery()
            limitQuery.limit = 5
            let history = await historyItems(of: channel, query: limitQuery)

            // Assertions
            try #require(history.count == 5)

            // Should get the 5 most recent (backwards direction by default)
            #expect(history[0].name == "event-10")
            #expect(history[4].name == "event-6")
        }
    }

    // UTS: rest/integration/RSL2b3/history-time-range-0
    @Test(arguments: [false, true]) // useBinaryProtocol: false = JSON, true = msgpack
    func test_RSL2b3_history_time_range_parameters(useBinaryProtocol: Bool) async throws {
        try await withSandboxApp { app in
            // Setup
            let options = ARTClientOptions(key: app.defaultKey)
            options.restHost = SandboxApp.sandboxHost // the spec's endpoint: "nonprod:sandbox"
            options.useBinaryProtocol = useBinaryProtocol
            let client = ARTRest(options: options)
            let channelName = "history-timerange-\(UUID().uuidString)"
            let channel = client.channels.get(channelName)

            // Test Steps
            // Publish early messages
            await self.awaitPublish(channel, name: "early1", data: "e1")
            await self.awaitPublish(channel, name: "early2", data: "e2")

            // Small delay to help ensure server assigns distinct timestamps between batches
            // (spec: WAIT 2ms — a spec-mandated real wait, not a wait on observable state)
            try await Task.sleep(nanoseconds: 2_000_000)

            // Publish late messages
            await self.awaitPublish(channel, name: "late1", data: "l1")
            await self.awaitPublish(channel, name: "late2", data: "l2")

            // Poll until all messages appear, keeping the page the poll settled on — its
            // server-assigned timestamps drive the boundary below, and a refetch could return fewer items.
            guard let allMessages = try await pollUntil("channel history contains all 4 messages", timeout: 10, interval: 0.5, {
                let items = try await self.historyItems(of: channel)
                return items.count == 4 ? items : nil
            }) else { return }

            // Use server-assigned timestamps to define the time boundary.
            // Client-side now() must not be used here — client and server clocks may
            // differ, and publishes may complete within the same client-clock millisecond.
            let earlyTimestamps = allMessages
                .filter { $0.name?.hasPrefix("early") == true }
                .compactMap { $0.timestamp }
                .map { Int64(($0.timeIntervalSince1970 * 1000).rounded()) }
            let lateTimestamps = allMessages
                .filter { $0.name?.hasPrefix("late") == true }
                .compactMap { $0.timestamp }
                .map { Int64(($0.timeIntervalSince1970 * 1000).rounded()) }

            let maxEarlyTs = try #require(earlyTimestamps.max())
            let minLateTs = try #require(lateTimestamps.min())
            let timeBoundary = (maxEarlyTs + minLateTs) / 2 // floor((max_early_ts + min_late_ts) / 2)

            // Query only early messages (up to the boundary)
            let earlyQuery = ARTDataQuery()
            earlyQuery.start = self.dateFromMilliseconds(maxEarlyTs - 1000)
            earlyQuery.end = self.dateFromMilliseconds(timeBoundary)
            let earlyHistory = await historyItems(of: channel, query: earlyQuery)

            // Query only late messages (from the boundary onwards)
            let lateQuery = ARTDataQuery()
            lateQuery.start = self.dateFromMilliseconds(timeBoundary + 1)
            lateQuery.end = self.dateFromMilliseconds(minLateTs + 1000)
            let lateHistory = await historyItems(of: channel, query: lateQuery)

            // Assertions
            #expect(earlyHistory.count >= 1)
            #expect(lateHistory.count >= 1)

            // Early messages should contain "early" names
            #expect(earlyHistory.contains { $0.name?.hasPrefix("early") == true })

            // Late messages should contain "late" names
            #expect(lateHistory.contains { $0.name?.hasPrefix("late") == true })
        }
    }

    // UTS: rest/integration/RSL2/history-empty-channel-0
    @Test(arguments: [false, true]) // useBinaryProtocol: false = JSON, true = msgpack
    func test_RSL2_history_on_channel_with_no_messages(useBinaryProtocol: Bool) async throws {
        try await withSandboxApp { app in
            // Setup
            let options = ARTClientOptions(key: app.defaultKey)
            options.restHost = SandboxApp.sandboxHost // the spec's endpoint: "nonprod:sandbox"
            options.useBinaryProtocol = useBinaryProtocol
            let client = ARTRest(options: options)
            // Use a fresh channel with no messages
            let channelName = "history-empty-\(UUID().uuidString)"
            let channel = client.channels.get(channelName)

            // Test Steps
            let history = await historyPage(of: channel)

            // Assertions
            // ASSERT history.items IS List
            // (no separate assertion: satisfied by the type system — ARTPaginatedResult.items is
            // [ARTMessage])
            #expect(history.items.count == 0)
            #expect(history.hasNext == false)
            #expect(history.isLast == true)
        }
    }
}

extension HistoryTests {
    /// Awaits the publish acknowledgement (the spec's `AWAIT channel.publish(name:data:)`),
    /// recording an issue on error.
    private func awaitPublish(_ channel: ARTRestChannel,
                              name: String,
                              data: Any,
                              sourceLocation: SourceLocation = #_sourceLocation) async {
        let failure: String? = await withCheckedContinuation { continuation in
            channel.publish(name, data: data, callback: { error in
                continuation.resume(returning: error.map { "\($0)" })
            })
        }

        if let failure {
            Issue.record("publish(\(name)) failed: \(failure)", sourceLocation: sourceLocation)
        }
    }

    /// Fetches the channel's history — with the given query (the spec's
    /// `channel.history(direction:/limit:/start:/end:)`) or the default query when nil — and
    /// returns its items, recording an issue on error.
    private func historyItems(of channel: ARTRestChannel,
                              query: ARTDataQuery? = nil,
                              sourceLocation: SourceLocation = #_sourceLocation) async -> [ARTMessage] {
        let (items, failure): ([ARTMessage], String?) = await withCheckedContinuation { continuation in
            do {
                try channel.history(query, callback: { result, error in
                    continuation.resume(returning: (result?.items ?? [], error.map { "history() failed: \($0)" }))
                })
            } catch {
                continuation.resume(returning: ([], "history(query) rejected the query: \(error)"))
            }
        }

        if let failure {
            Issue.record("\(failure)", sourceLocation: sourceLocation)
        }

        return items
    }

    /// Fetches the channel's history (default query) and returns its items, propagating any
    /// `history()` error so it aborts the enclosing `pollUntil` and surfaces the real failure
    /// (matching the plain `poll_until` reference semantics; js/java do the same).
    private func historyItems(of channel: ARTRestChannel) async throws -> [ARTMessage] {
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

    /// Fetches the channel's history (default query) and returns the page's items plus its
    /// pagination flags (the spec's `history.hasNext()` / `history.isLast()`), recording an issue
    /// on error. Extracted to value types — `ARTPaginatedResult` is not Sendable, so it cannot
    /// cross the continuation.
    private func historyPage(of channel: ARTRestChannel,
                             sourceLocation: SourceLocation = #_sourceLocation) async
        -> (items: [ARTMessage], hasNext: Bool, isLast: Bool) {
        let (page, failure): ((items: [ARTMessage], hasNext: Bool, isLast: Bool), String?) = await withCheckedContinuation { continuation in
            channel.history { result, error in
                continuation.resume(returning: ((items: result?.items ?? [],
                                                 hasNext: result?.hasNext ?? false,
                                                 isLast: result?.isLast ?? true),
                                                error.map { "\($0)" }))
            }
        }

        if let failure {
            Issue.record("history() failed: \(failure)", sourceLocation: sourceLocation)
        }

        return page
    }

    /// Builds a `Date` from a Unix-epoch millisecond timestamp (the spec's ms arithmetic on
    /// server-assigned timestamps).
    private func dateFromMilliseconds(_ milliseconds: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000)
    }
}
