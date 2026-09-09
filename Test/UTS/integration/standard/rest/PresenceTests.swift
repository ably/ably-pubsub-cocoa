import Testing
import Foundation
import Ably

/// REST presence (RSP1, RSP3, RSP3a, RSP4, RSP4b, RSP5)
/// Derived from ably/specification `uts/rest/integration/presence.md`
///
/// Direct-sandbox integration test against the Ably Sandbox (`sandbox.realtime.ably-nonprod.net`,
/// via SandboxApp.sandboxHost) — no proxy, no fault injection. Provisions a throwaway SandboxApp
/// (whose `test-app-setup.json` pre-populates presence fixtures on `persisted:presence_fixtures`)
/// and points real clients straight at the sandbox. Needs outbound network:
///
/// ```bash
/// swift test --filter UTS.PresenceTests
/// ```
@Suite(.serialized)
final class PresenceTests: IntegrationTestCase {

    // UTS: rest/integration/RSP1/access-presence-from-channel-0
    @Test(arguments: [false, true]) // useBinaryProtocol: false = JSON, true = msgpack
    func test_RSP1_access_presence_from_channel(useBinaryProtocol: Bool) async throws {
        // The spec's BEFORE/AFTER ALL sandbox app provisioning is owned by the withSandboxApp scope.
        try await withSandboxApp { app in
            // Setup
            let options = ARTClientOptions(key: app.defaultKey)
            options.restHost = SandboxApp.sandboxHost // the spec's endpoint: "nonprod:sandbox"
            options.useBinaryProtocol = useBinaryProtocol
            let client = ARTRest(options: options)

            let channel = client.channels.get("persisted:presence_fixtures")
            // ASSERT presence IS NOT null
            // (satisfied by the type system: ARTRestChannel.presence is a non-optional property)
            let presence: ARTRestPresence = channel.presence
            // ASSERT presence IS RestPresence
            #expect((presence as Any) is ARTRestPresence)
        }
    }

    // UTS: rest/integration/RSP3/get-presence-members-0
    @Test(arguments: [false, true]) // useBinaryProtocol: false = JSON, true = msgpack
    func test_RSP3_get_presence_members_from_fixture_channel(useBinaryProtocol: Bool) async throws {
        try await withSandboxApp { app in
            // Setup
            let options = ARTClientOptions(key: app.defaultKey)
            options.restHost = SandboxApp.sandboxHost // the spec's endpoint: "nonprod:sandbox"
            options.useBinaryProtocol = useBinaryProtocol
            let client = ARTRest(options: options)

            let channel = client.channels.get("persisted:presence_fixtures")
            // ASSERT result IS PaginatedResult
            // (satisfied by the type system: the helper returns ARTPaginatedResult<ARTPresenceMessage>)
            let result = try #require(await self.presenceGet(channel.presence))

            #expect(result.items.count >= 5) // At least the non-encrypted fixtures

            // Verify expected clients are present
            let clientIds = result.items.compactMap(\.clientId)
            #expect(clientIds.contains("client_bool"))
            #expect(clientIds.contains("client_string"))
            #expect(clientIds.contains("client_json"))
        }
    }

    // UTS: rest/integration/RSP3/presence-message-fields-1
    @Test(arguments: [false, true]) // useBinaryProtocol: false = JSON, true = msgpack
    func test_RSP3_get_returns_PresenceMessage_with_correct_fields(useBinaryProtocol: Bool) async throws {
        try await withSandboxApp { app in
            // Setup
            let options = ARTClientOptions(key: app.defaultKey)
            options.restHost = SandboxApp.sandboxHost // the spec's endpoint: "nonprod:sandbox"
            options.useBinaryProtocol = useBinaryProtocol
            let client = ARTRest(options: options)

            let channel = client.channels.get("persisted:presence_fixtures")
            let result = try #require(await self.presenceGet(channel.presence))

            // Find client_string member
            // ASSERT member IS NOT null (the #require covers it)
            let member = try #require(result.items.first { $0.clientId == "client_string" })

            // ASSERT member IS PresenceMessage
            // (satisfied by the type system: items is [ARTPresenceMessage])
            #expect(member.action == .present)
            #expect(member.clientId == "client_string")
            #expect(member.data as? String == "This is a string clientData payload")
            // ASSERT member.connectionId IS NOT null
            // (satisfied by the type system: ARTBaseMessage.connectionId is non-optional in cocoa)
        }
    }

    // UTS: rest/integration/RSP3a1/get-with-limit-0
    @Test(arguments: [false, true]) // useBinaryProtocol: false = JSON, true = msgpack
    func test_RSP3a1_get_with_limit_parameter(useBinaryProtocol: Bool) async throws {
        try await withSandboxApp { app in
            // Setup
            let options = ARTClientOptions(key: app.defaultKey)
            options.restHost = SandboxApp.sandboxHost // the spec's endpoint: "nonprod:sandbox"
            options.useBinaryProtocol = useBinaryProtocol
            let client = ARTRest(options: options)

            let channel = client.channels.get("persisted:presence_fixtures")

            // Request with small limit
            let query = ARTPresenceQuery()
            query.limit = 2
            let result = try #require(await self.presenceGet(channel.presence, query: query))

            #expect(result.items.count <= 2)
            // If more members exist, pagination should be available
            if result.hasNext {
                #expect(result.items.count == 2)
            }
        }
    }

    // UTS: rest/integration/RSP3a2/get-with-clientid-filter-0
    @Test(arguments: [false, true]) // useBinaryProtocol: false = JSON, true = msgpack
    func test_RSP3a2_get_with_clientId_filter(useBinaryProtocol: Bool) async throws {
        try await withSandboxApp { app in
            // Setup
            let options = ARTClientOptions(key: app.defaultKey)
            options.restHost = SandboxApp.sandboxHost // the spec's endpoint: "nonprod:sandbox"
            options.useBinaryProtocol = useBinaryProtocol
            let client = ARTRest(options: options)

            let channel = client.channels.get("persisted:presence_fixtures")
            let query = ARTPresenceQuery()
            query.clientId = "client_json"
            let result = try #require(await self.presenceGet(channel.presence, query: query))

            #expect(result.items.count == 1)
            #expect(result.items.first?.clientId == "client_json")
            // The fixture has no encoding field, so data is returned as a raw string
            let data = try #require(result.items.first?.data as? String)
            #expect(data == "{ \"test\": \"This is a JSONObject clientData payload\"}")
        }
    }

    // UTS: rest/integration/RSP3/get-empty-channel-2
    @Test(arguments: [false, true]) // useBinaryProtocol: false = JSON, true = msgpack
    func test_RSP3_get_on_channel_with_no_presence(useBinaryProtocol: Bool) async throws {
        try await withSandboxApp { app in
            // Setup
            let options = ARTClientOptions(key: app.defaultKey)
            options.restHost = SandboxApp.sandboxHost // the spec's endpoint: "nonprod:sandbox"
            options.useBinaryProtocol = useBinaryProtocol
            let client = ARTRest(options: options)

            // Use a unique channel name that has no presence members
            let channelName = "presence-empty-\(UUID().uuidString)"
            let channel = client.channels.get(channelName)

            let result = try #require(await self.presenceGet(channel.presence))

            // ASSERT result.items IS List
            // (satisfied by the type system: items is [ARTPresenceMessage])
            #expect(result.items.count == 0)
            #expect(result.hasNext == false)
        }
    }

    // UTS: rest/integration/RSP4/history-returns-events-0
    @Test(arguments: [false, true]) // useBinaryProtocol: false = JSON, true = msgpack
    func test_RSP4_history_returns_presence_events(useBinaryProtocol: Bool) async throws {
        try await withSandboxApp { app in
            // Setup
            let options = ARTClientOptions(key: app.defaultKey)
            options.restHost = SandboxApp.sandboxHost // the spec's endpoint: "nonprod:sandbox"
            options.useBinaryProtocol = useBinaryProtocol
            let client = ARTRest(options: options)

            let channelName = "presence-history-\(UUID().uuidString)"

            // Use realtime client to generate presence history
            let realtimeOptions = ARTClientOptions(key: app.defaultKey)
            realtimeOptions.realtimeHost = SandboxApp.sandboxHost
            realtimeOptions.restHost = SandboxApp.sandboxHost
            realtimeOptions.useBinaryProtocol = useBinaryProtocol
            realtimeOptions.clientId = "test-client"
            realtimeOptions.autoConnect = false

            try await withRealtimeClient(realtimeOptions) { realtime in
                realtime.connect()
                guard await awaitState(realtime, .connected) else { return }
                let realtimeChannel = realtime.channels.get(channelName)
                await self.awaitPresenceOp("presence.enter") { realtimeChannel.presence.enter("entered", callback: $0) }
                await self.awaitPresenceOp("presence.update") { realtimeChannel.presence.update("updated", callback: $0) }
                await self.awaitPresenceOp("presence.leave") { realtimeChannel.presence.leave("left", callback: $0) }
            } // AWAIT realtime.close() — performed by the withRealtimeClient scope (close + await CLOSED)

            // Poll REST history until events appear
            let restChannel = client.channels.get(channelName)

            // Keep the page the poll settled on — a refetch could return fewer items.
            guard let history = try await pollUntil("presence history has at least 3 events", timeout: 10, interval: 0.5, {
                let result = try await self.presenceHistoryPage(restChannel.presence)
                return result.items.count >= 3 ? result : nil
            }) else { return }

            #expect(history.items.count >= 3)

            // Check for expected actions (order depends on direction)
            let actions = history.items.map(\.action)
            #expect(actions.contains(.enter))
            #expect(actions.contains(.update))
            #expect(actions.contains(.leave))
        }
    }

    // UTS: rest/integration/RSP4b1/history-time-range-0
    @Test(arguments: [false, true]) // useBinaryProtocol: false = JSON, true = msgpack
    func test_RSP4b1_history_with_start_end_time_range(useBinaryProtocol: Bool) async throws {
        try await withSandboxApp { app in
            // Setup
            let options = ARTClientOptions(key: app.defaultKey)
            options.restHost = SandboxApp.sandboxHost // the spec's endpoint: "nonprod:sandbox"
            options.useBinaryProtocol = useBinaryProtocol
            options.clientId = "test-client"
            let client = ARTRest(options: options)

            let channelName = "presence-history-time-\(UUID().uuidString)"

            // Generate presence events via realtime
            let realtimeOptions = ARTClientOptions(key: app.defaultKey)
            realtimeOptions.realtimeHost = SandboxApp.sandboxHost
            realtimeOptions.restHost = SandboxApp.sandboxHost
            realtimeOptions.useBinaryProtocol = useBinaryProtocol
            realtimeOptions.clientId = "time-test-client"
            realtimeOptions.autoConnect = false

            try await withRealtimeClient(realtimeOptions) { realtime in
                realtime.connect()
                guard await awaitState(realtime, .connected) else { return }
                let realtimeChannel = realtime.channels.get(channelName)
                await self.awaitPresenceOp("presence.enter") { realtimeChannel.presence.enter("test", callback: $0) }
                await self.awaitPresenceOp("presence.leave") { realtimeChannel.presence.leave(nil, callback: $0) }
            } // AWAIT realtime.close() — performed by the withRealtimeClient scope (close + await CLOSED)

            // Poll until events appear, keeping the page the poll settled on (its server-assigned
            // timestamps drive the query below) — a refetch could return fewer items.
            let restChannel = client.channels.get(channelName)
            guard let events = try await pollUntil("presence history has at least 2 events", timeout: 10, interval: 0.5, {
                let result = try await self.presenceHistoryPage(restChannel.presence)
                return result.items.count >= 2 ? result.items : nil
            }) else { return }

            // Use server-assigned timestamps to define the queried range. Client-side now() must
            // not be used here — client and server clocks may differ, and a skewed client clock
            // would silently exclude the events.
            let eventTimestamps = events.compactMap(\.timestamp)
            let timeBefore = try #require(eventTimestamps.min()).addingTimeInterval(-1)
            let timeAfter = try #require(eventTimestamps.max()).addingTimeInterval(1)

            // Query with time range
            let query = ARTDataQuery()
            query.start = timeBefore
            query.end = timeAfter
            let history = try #require(await self.presenceHistory(restChannel.presence, query: query))

            #expect(history.items.count >= 2)
        }
    }

    // UTS: rest/integration/RSP4b2/history-direction-forwards-0
    @Test(arguments: [false, true]) // useBinaryProtocol: false = JSON, true = msgpack
    func test_RSP4b2_history_direction_forwards(useBinaryProtocol: Bool) async throws {
        try await withSandboxApp { app in
            // Setup
            let options = ARTClientOptions(key: app.defaultKey)
            options.restHost = SandboxApp.sandboxHost // the spec's endpoint: "nonprod:sandbox"
            options.useBinaryProtocol = useBinaryProtocol
            let client = ARTRest(options: options)

            let channelName = "presence-direction-\(UUID().uuidString)"

            // Generate ordered presence events
            let realtimeOptions = ARTClientOptions(key: app.defaultKey)
            realtimeOptions.realtimeHost = SandboxApp.sandboxHost
            realtimeOptions.restHost = SandboxApp.sandboxHost
            realtimeOptions.useBinaryProtocol = useBinaryProtocol
            realtimeOptions.clientId = "direction-client"
            realtimeOptions.autoConnect = false

            try await withRealtimeClient(realtimeOptions) { realtime in
                realtime.connect()
                guard await awaitState(realtime, .connected) else { return }
                let realtimeChannel = realtime.channels.get(channelName)
                await self.awaitPresenceOp("presence.enter") { realtimeChannel.presence.enter("first", callback: $0) }
                await self.awaitPresenceOp("presence.update") { realtimeChannel.presence.update("second", callback: $0) }
                await self.awaitPresenceOp("presence.update") { realtimeChannel.presence.update("third", callback: $0) }
            } // AWAIT realtime.close() — performed by the withRealtimeClient scope (close + await CLOSED)

            // Poll until events appear
            let restChannel = client.channels.get(channelName)
            guard try await pollUntil("presence history has at least 3 events", timeout: 10, interval: 0.5, {
                try await self.presenceHistoryPage(restChannel.presence).items.count >= 3
            }) else { return }

            // Get history forwards (oldest first)
            let forwardsQuery = ARTDataQuery()
            forwardsQuery.direction = .forwards
            let historyForwards = try #require(await self.presenceHistory(restChannel.presence, query: forwardsQuery))

            #expect(historyForwards.items.count >= 3)
            #expect(historyForwards.items.first?.data as? String == "first")

            // Get history backwards (newest first) - default
            let backwardsQuery = ARTDataQuery()
            backwardsQuery.direction = .backwards
            let historyBackwards = try #require(await self.presenceHistory(restChannel.presence, query: backwardsQuery))

            #expect(historyBackwards.items.first?.data as? String == "third")
        }
    }

    // UTS: rest/integration/RSP4b3/history-limit-pagination-0
    @Test(arguments: [false, true]) // useBinaryProtocol: false = JSON, true = msgpack
    func test_RSP4b3_history_with_limit_and_pagination(useBinaryProtocol: Bool) async throws {
        try await withSandboxApp { app in
            // Setup
            let options = ARTClientOptions(key: app.defaultKey)
            options.restHost = SandboxApp.sandboxHost // the spec's endpoint: "nonprod:sandbox"
            options.useBinaryProtocol = useBinaryProtocol
            let client = ARTRest(options: options)

            let channelName = "presence-limit-\(UUID().uuidString)"

            // Generate multiple presence events
            let realtimeOptions = ARTClientOptions(key: app.defaultKey)
            realtimeOptions.realtimeHost = SandboxApp.sandboxHost
            realtimeOptions.restHost = SandboxApp.sandboxHost
            realtimeOptions.useBinaryProtocol = useBinaryProtocol
            realtimeOptions.clientId = "limit-client"
            realtimeOptions.autoConnect = false

            try await withRealtimeClient(realtimeOptions) { realtime in
                realtime.connect()
                guard await awaitState(realtime, .connected) else { return }
                let realtimeChannel = realtime.channels.get(channelName)
                for i in 1...5 {
                    await self.awaitPresenceOp("presence.update") { realtimeChannel.presence.update("update-\(i)", callback: $0) }
                }
            } // AWAIT realtime.close() — performed by the withRealtimeClient scope (close + await CLOSED)

            // Poll until all events appear
            let restChannel = client.channels.get(channelName)
            guard try await pollUntil("presence history has at least 5 events", timeout: 10, interval: 0.5, {
                try await self.presenceHistoryPage(restChannel.presence).items.count >= 5
            }) else { return }

            // Request with small limit
            let limitQuery = ARTDataQuery()
            limitQuery.limit = 2
            let page1 = try #require(await self.presenceHistory(restChannel.presence, query: limitQuery))

            #expect(page1.items.count == 2)
            #expect(page1.hasNext == true)

            // Get next page
            // ASSERT page2 IS NOT null (the #require covers it)
            let page2 = try #require(await self.nextPage(of: page1))

            #expect(page2.items.count >= 1)
        }
    }

    // UTS: rest/integration/RSP5/decode-string-data-0
    @Test(arguments: [false, true]) // useBinaryProtocol: false = JSON, true = msgpack
    func test_RSP5_string_data_decoded_correctly(useBinaryProtocol: Bool) async throws {
        try await withSandboxApp { app in
            // Setup
            let options = ARTClientOptions(key: app.defaultKey)
            options.restHost = SandboxApp.sandboxHost // the spec's endpoint: "nonprod:sandbox"
            options.useBinaryProtocol = useBinaryProtocol
            let client = ARTRest(options: options)

            let channel = client.channels.get("persisted:presence_fixtures")
            let query = ARTPresenceQuery()
            query.clientId = "client_string"
            let result = try #require(await self.presenceGet(channel.presence, query: query))

            #expect(result.items.count == 1)
            // ASSERT result.items[0].data IS String (the #require's cast covers it)
            let data = try #require(result.items.first?.data as? String)
            #expect(data == "This is a string clientData payload")
        }
    }

    // UTS: rest/integration/RSP5/decode-json-data-1
    @Test(arguments: [false, true]) // useBinaryProtocol: false = JSON, true = msgpack
    func test_RSP5_JSON_data_decoded_to_object(useBinaryProtocol: Bool) async throws {
        try await withSandboxApp { app in
            // Setup
            let options = ARTClientOptions(key: app.defaultKey)
            options.restHost = SandboxApp.sandboxHost // the spec's endpoint: "nonprod:sandbox"
            options.useBinaryProtocol = useBinaryProtocol
            let client = ARTRest(options: options)

            let channel = client.channels.get("persisted:presence_fixtures")
            let query = ARTPresenceQuery()
            query.clientId = "client_decoded"
            let result = try #require(await self.presenceGet(channel.presence, query: query))

            #expect(result.items.count == 1)
            // ASSERT result.items[0].data IS Object/Map (the #require's cast covers it)
            let data = try #require(result.items.first?.data as? [String: Any])
            #expect((data["example"] as? [String: Any])?["json"] as? String == "Object")
        }
    }

    // UTS: rest/integration/RSP5/decode-encrypted-data-2
    @Test(arguments: [false, true]) // useBinaryProtocol: false = JSON, true = msgpack
    func test_RSP5_encrypted_data_decoded_with_cipher(useBinaryProtocol: Bool) async throws {
        try await withSandboxApp { app in
            // Setup
            let options = ARTClientOptions(key: app.defaultKey)
            options.restHost = SandboxApp.sandboxHost // the spec's endpoint: "nonprod:sandbox"
            options.useBinaryProtocol = useBinaryProtocol
            let client = ARTRest(options: options)

            let cipherKey = try #require(Data(base64Encoded: "WUP6u0K7MXI5Zeo0VppPwg=="))

            // CipherParams(key:, algorithm: "aes", mode: "cbc", keyLength: 128) — cocoa's
            // ARTCipherParams derives keyLength from the key (16 bytes = 128) and defaults the
            // mode to CBC, so algorithm + key express the spec's full cipher configuration.
            let channelOptions = ARTChannelOptions(cipher: ARTCipherParams(algorithm: "aes", key: cipherKey as NSData))
            let channel = client.channels.get("persisted:presence_fixtures", options: channelOptions)

            let query = ARTPresenceQuery()
            query.clientId = "client_encoded"
            let result = try #require(await self.presenceGet(channel.presence, query: query))

            // The encrypted fixture should be decrypted
            #expect(result.items.count == 1)
            #expect(result.items.first?.data != nil)
            // Actual decrypted value depends on fixture content
        }
    }

    // UTS: rest/integration/RSP5/decode-history-messages-3
    @Test(arguments: [false, true]) // useBinaryProtocol: false = JSON, true = msgpack
    func test_RSP5_history_messages_also_decoded(useBinaryProtocol: Bool) async throws {
        try await withSandboxApp { app in
            // Setup
            let options = ARTClientOptions(key: app.defaultKey)
            options.restHost = SandboxApp.sandboxHost // the spec's endpoint: "nonprod:sandbox"
            options.useBinaryProtocol = useBinaryProtocol
            let client = ARTRest(options: options)

            let channelName = "presence-decode-history-\(UUID().uuidString)"

            // Generate presence event with JSON data
            let realtimeOptions = ARTClientOptions(key: app.defaultKey)
            realtimeOptions.realtimeHost = SandboxApp.sandboxHost
            realtimeOptions.restHost = SandboxApp.sandboxHost
            realtimeOptions.useBinaryProtocol = useBinaryProtocol
            realtimeOptions.clientId = "decode-client"
            realtimeOptions.autoConnect = false

            let jsonData: [String: Any] = ["key": "value", "number": 123]
            try await withRealtimeClient(realtimeOptions) { realtime in
                realtime.connect()
                guard await awaitState(realtime, .connected) else { return }
                let realtimeChannel = realtime.channels.get(channelName)
                await self.awaitPresenceOp("presence.enter") { realtimeChannel.presence.enter(jsonData, callback: $0) }
            } // AWAIT realtime.close() — performed by the withRealtimeClient scope (close + await CLOSED)

            // Poll and retrieve history, keeping the page the poll settled on.
            let restChannel = client.channels.get(channelName)
            guard let history = try await pollUntil("presence history has at least 1 event", timeout: 10, interval: 0.5, {
                let result = try await self.presenceHistoryPage(restChannel.presence)
                return result.items.count >= 1 ? result : nil
            }) else { return }

            // ASSERT history.items[0].data IS Object/Map (the #require's cast covers it)
            let data = try #require(history.items.first?.data as? [String: Any])
            #expect(data["key"] as? String == "value")
            #expect(data["number"] as? Int == 123)
        }
    }

    // UTS: rest/integration/RSP3/full-pagination-3
    @Test(arguments: [false, true]) // useBinaryProtocol: false = JSON, true = msgpack
    func test_RSP3_full_pagination_through_presence_members(useBinaryProtocol: Bool) async throws {
        try await withSandboxApp { app in
            // Setup
            let options = ARTClientOptions(key: app.defaultKey)
            options.restHost = SandboxApp.sandboxHost // the spec's endpoint: "nonprod:sandbox"
            options.useBinaryProtocol = useBinaryProtocol
            let client = ARTRest(options: options)

            // The fixture channel has multiple members
            let channel = client.channels.get("persisted:presence_fixtures")

            // Request with small limit to force pagination
            let query = ARTPresenceQuery()
            query.limit = 2
            let page1 = try #require(await self.presenceGet(channel.presence, query: query))

            var allMembers: [ARTPresenceMessage] = []
            allMembers.append(contentsOf: page1.items)

            var currentPage = page1
            while currentPage.hasNext {
                guard let next = await nextPage(of: currentPage) else { break }
                currentPage = next
                allMembers.append(contentsOf: currentPage.items)
            }

            // Should have retrieved all fixture members
            #expect(allMembers.count >= 5)

            // Verify no duplicates
            let clientIds = allMembers.compactMap(\.clientId)
            #expect(Set(clientIds).count == clientIds.count)
        }
    }

    // UTS: rest/integration/RSP3/invalid-credentials-rejected-4
    @Test(arguments: [false, true]) // useBinaryProtocol: false = JSON, true = msgpack
    func test_RSP3_invalid_credentials_rejected(useBinaryProtocol: Bool) async throws {
        try await withSandboxApp { _ in
            // Setup
            let options = ARTClientOptions(key: "invalid.key:secret")
            options.restHost = SandboxApp.sandboxHost // the spec's endpoint: "nonprod:sandbox"
            options.useBinaryProtocol = useBinaryProtocol
            let client = ARTRest(options: options)

            // AWAIT client.channels.get("test").presence.get() FAILS WITH error
            let error = try #require(await self.presenceGetError(client.channels.get("test").presence))
            #expect(error.statusCode == 401)
            #expect(error.code >= 40100 && error.code < 40200)
        }
    }

    // UTS: rest/integration/RSP3/subscribe-capability-sufficient-5
    @Test(arguments: [false, true]) // useBinaryProtocol: false = JSON, true = msgpack
    func test_RSP3_subscribe_capability_sufficient(useBinaryProtocol: Bool) async throws {
        try await withSandboxApp { app in
            // Setup
            // Use key with limited capabilities (keys[3] has subscribe only)
            try #require(app.keys.count > 3, "test-app-setup.json should provision keys[3] (subscribe-only)")
            let restrictedKey = app.keys[3]

            let options = ARTClientOptions(key: restrictedKey)
            options.restHost = SandboxApp.sandboxHost // the spec's endpoint: "nonprod:sandbox"
            options.useBinaryProtocol = useBinaryProtocol
            let client = ARTRest(options: options)

            // This should work - subscribe capability is sufficient for presence.get
            // ASSERT result IS NOT null (the #require covers it)
            _ = try #require(await self.presenceGet(client.channels.get("persisted:presence_fixtures").presence))
        }
    }
}

extension PresenceTests {
    /// Awaits `presence.get()` (the spec's `result = AWAIT channel.presence.get()`), returning the
    /// paginated result — or nil, after recording an issue, on failure (tests unwrap with
    /// `try #require`).
    private func presenceGet(_ presence: ARTRestPresence,
                             sourceLocation: SourceLocation = #_sourceLocation) async -> ARTPaginatedResult<ARTPresenceMessage>? {
        let (result, failure): (ARTPaginatedResult<ARTPresenceMessage>?, String?) = await withCheckedContinuation { continuation in
            presence.get { result, error in
                continuation.resume(returning: (result, error.map { "\($0)" }))
            }
        }

        if let failure {
            Issue.record("presence.get() failed: \(failure)", sourceLocation: sourceLocation)
        }

        return result
    }

    /// Awaits `presence.get(query)` (the spec's `AWAIT channel.presence.get(limit:/clientId:)`),
    /// returning the paginated result — or nil, after recording an issue, on failure.
    private func presenceGet(_ presence: ARTRestPresence,
                             query: ARTPresenceQuery,
                             sourceLocation: SourceLocation = #_sourceLocation) async -> ARTPaginatedResult<ARTPresenceMessage>? {
        let (result, failure): (ARTPaginatedResult<ARTPresenceMessage>?, String?) = await withCheckedContinuation { continuation in
            do {
                try presence.get(query) { result, error in
                    continuation.resume(returning: (result, error.map { "presence.get(query) failed: \($0)" }))
                }
            } catch {
                continuation.resume(returning: (nil, "presence.get(query) threw: \(error)"))
            }
        }

        if let failure {
            Issue.record("\(failure)", sourceLocation: sourceLocation)
        }

        return result
    }

    /// Awaits `presence.get()` expecting it to fail (the spec's `AWAIT presence.get() FAILS WITH
    /// error`), returning the error — or nil, after recording an issue, if it unexpectedly
    /// succeeded (tests unwrap with `try #require`).
    private func presenceGetError(_ presence: ARTRestPresence,
                                  sourceLocation: SourceLocation = #_sourceLocation) async -> ARTErrorInfo? {
        let error: ARTErrorInfo? = await withCheckedContinuation { continuation in
            presence.get { _, error in
                continuation.resume(returning: error)
            }
        }

        if error == nil {
            Issue.record("presence.get() unexpectedly succeeded", sourceLocation: sourceLocation)
        }

        return error
    }

    /// Awaits `presence.history()` (the spec's `result = AWAIT rest_channel.presence.history()`),
    /// returning the paginated result — or nil, after recording an issue, on failure.
    private func presenceHistory(_ presence: ARTRestPresence,
                                 sourceLocation: SourceLocation = #_sourceLocation) async -> ARTPaginatedResult<ARTPresenceMessage>? {
        let (result, failure): (ARTPaginatedResult<ARTPresenceMessage>?, String?) = await withCheckedContinuation { continuation in
            presence.history { result, error in
                continuation.resume(returning: (result, error.map { "\($0)" }))
            }
        }

        if let failure {
            Issue.record("presence.history() failed: \(failure)", sourceLocation: sourceLocation)
        }

        return result
    }

    /// Fetches presence history (default query), propagating any `presence.history()` error so it
    /// aborts the enclosing `pollUntil` and surfaces the real failure (plain `poll_until`
    /// semantics; js/java do the same).
    private func presenceHistoryPage(_ presence: ARTRestPresence) async throws -> ARTPaginatedResult<ARTPresenceMessage> {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ARTPaginatedResult<ARTPresenceMessage>, Error>) in
            presence.history { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let result {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: HTTPError("presence.history returned no result and no error"))
                }
            }
        }
    }

    /// Awaits `presence.history(query)` (the spec's `AWAIT presence.history(start:/direction:/limit:)`),
    /// returning the paginated result — or nil, after recording an issue, on failure.
    private func presenceHistory(_ presence: ARTRestPresence,
                                 query: ARTDataQuery,
                                 sourceLocation: SourceLocation = #_sourceLocation) async -> ARTPaginatedResult<ARTPresenceMessage>? {
        let (result, failure): (ARTPaginatedResult<ARTPresenceMessage>?, String?) = await withCheckedContinuation { continuation in
            do {
                try presence.history(query) { result, error in
                    continuation.resume(returning: (result, error.map { "presence.history(query) failed: \($0)" }))
                }
            } catch {
                continuation.resume(returning: (nil, "presence.history(query) threw: \(error)"))
            }
        }

        if let failure {
            Issue.record("\(failure)", sourceLocation: sourceLocation)
        }

        return result
    }

    /// Awaits `page.next()` (the spec's `page2 = AWAIT page1.next()`), returning the next page —
    /// or nil, after recording an issue, on failure.
    private func nextPage(of page: ARTPaginatedResult<ARTPresenceMessage>,
                          sourceLocation: SourceLocation = #_sourceLocation) async -> ARTPaginatedResult<ARTPresenceMessage>? {
        let (result, failure): (ARTPaginatedResult<ARTPresenceMessage>?, String?) = await withCheckedContinuation { continuation in
            page.next { result, error in
                continuation.resume(returning: (result, error.map { "\($0)" }))
            }
        }

        if let failure {
            Issue.record("next() failed: \(failure)", sourceLocation: sourceLocation)
        }

        return result
    }

    /// Awaits a realtime presence operation's acknowledgement (the spec's
    /// `AWAIT realtime_channel.presence.enter/update/leave(...)`), recording an issue on error.
    private func awaitPresenceOp(_ label: String,
                                 sourceLocation: SourceLocation = #_sourceLocation,
                                 _ operation: (@escaping ARTCallback) -> Void) async {
        let failure: String? = await withCheckedContinuation { continuation in
            operation { error in
                continuation.resume(returning: error.map { "\($0)" })
            }
        }

        if let failure {
            Issue.record("\(label) failed: \(failure)", sourceLocation: sourceLocation)
        }
    }
}
