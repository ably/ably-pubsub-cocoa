import Testing
import Foundation
import AblyPubSubDevice
import AblyPubSubDevice.Private

/// Connection Recovery Tests (RTN16d, RTN16f, RTN16f1, RTN16g, RTN16g1, RTN16g2, RTN16i, RTN16j, RTN16k, RTN16l)
/// Derived from https://github.com/ably/specification/blob/main/uts/realtime/unit/connection/connection_recovery_test.md
@Suite(.serialized)
final class ConnectionRecoveryTests: UTSTestCase {

    // UTS: realtime/unit/RTN16g/recovery-key-structure-0
    @Test
    func test_RTN16g_createRecoveryKey_returns_connectionKey_msgSerial_and_channelSerials() throws {
        // Setup
        let wsProvider = MockWebSocketProvider(onConnectionAttempt: { connection in
            connection.respondWithSuccess()
            connection.sendToClient(.connected(
                connectionId: "connection-1",
                connectionKey: "key-abc-123",
                maxIdleInterval: 15,
                connectionStateTtl: 120
            ))
        })
        installMock(wsProvider)

        let client = makeRealtime { options in
            options.key = "appId.keyId:keySecret"
            options.autoConnect = false
        }

        // Test Steps
        // Connect
        client.connect()
        awaitConnectionState(client, .connected)

        // Get the WebSocket connection for sending mock responses
        let wsConnection = try #require(wsProvider.activeConnection)

        // Get two channels and simulate attaching them (including one with unicode name)
        let channelA = client.channels.get("channel-alpha")
        let channelB = client.channels.get("channel-éàü-世界")

        // Attach channel_a
        channelA.attach()
        wsConnection.sendToClient(.attached(channel: "channel-alpha", channelSerial: "serial-a-001"))
        awaitChannelState(channelA, .attached)

        // Attach channel_b (unicode name)
        channelB.attach()
        wsConnection.sendToClient(.attached(channel: "channel-éàü-世界", channelSerial: "serial-b-002"))
        awaitChannelState(channelB, .attached)

        // Create recovery key
        let recoveryKeyString = client.connection.createRecoveryKey()

        // Assertions
        // Recovery key is not null
        let unwrappedRecoveryKeyString = try #require(recoveryKeyString)

        // Deserialize the recovery key (JSON format per ably-js reference)
        let recoveryKey = try parseJSONObject(unwrappedRecoveryKeyString)

        // Contains connectionKey
        #expect(recoveryKey["connectionKey"] as? String == "key-abc-123")

        // Contains msgSerial (starts at 0 since no messages were sent)
        #expect(recoveryKey["msgSerial"] as? Int == 0)

        // Contains channelSerials map with both channels
        let channelSerials = try #require(recoveryKey["channelSerials"] as? [String: String])
        #expect(channelSerials["channel-alpha"] == "serial-a-001")

        // RTN16g1: Unicode channel name is correctly encoded in the serialized key
        #expect(channelSerials["channel-éàü-世界"] == "serial-b-002")

        // Verify round-trip: re-serializing and deserializing preserves the unicode name
        let reSerialized = try toJSONString(recoveryKey)
        let reParsed = try parseJSONObject(reSerialized)
        let reParsedSerials = try #require(reParsed["channelSerials"] as? [String: String])
        #expect(reParsedSerials["channel-éàü-世界"] == "serial-b-002")

        closeClient(client)
    }

    // UTS: realtime/unit/RTN16g2/recovery-key-null-inactive-0
    @Test
    func test_RTN16g2_createRecoveryKey_returns_null_in_inactive_states() throws {
        // Setup
        let wsProvider = MockWebSocketProvider(onConnectionAttempt: { connection in
            connection.respondWithSuccess()
            connection.sendToClient(.connected(
                connectionId: "connection-1",
                connectionKey: "key-1",
                maxIdleInterval: 15,
                connectionStateTtl: 120
            ))
        })
        installMock(wsProvider)

        let client = makeRealtime { options in
            options.key = "appId.keyId:keySecret"
            options.autoConnect = false
        }

        // Test Steps
        // Before connecting (INITIALIZED state, no connectionKey)
        #expect(client.connection.createRecoveryKey() == nil)

        // Connect and verify recovery key is available when CONNECTED
        client.connect()
        awaitConnectionState(client, .connected)
        #expect(client.connection.createRecoveryKey() != nil)

        // Transition to CLOSING then CLOSED
        let wsConnection = try #require(wsProvider.activeConnection)
        client.connection.close()
        awaitConnectionState(client, .closing)
        #expect(client.connection.createRecoveryKey() == nil)

        // The mock server doesn't auto-respond to the client's CLOSE frame, so deliver the server's
        // CLOSED to drive the connection from CLOSING to CLOSED (infra-driving detail:
        wsConnection.sendToClient(.closed())

        awaitConnectionState(client, .closed)
        #expect(client.connection.createRecoveryKey() == nil)

        // Assertions
        // All null cases verified inline above.
        // For FAILED and SUSPENDED states, create separate clients to test:

        // --- Test FAILED state ---
        let wsProviderFailed = MockWebSocketProvider(onConnectionAttempt: { connection in
            connection.respondWithSuccess()
            connection.sendToClient(.connected(
                connectionId: "conn-f",
                connectionKey: "key-f",
                maxIdleInterval: 15,
                connectionStateTtl: 120
            ))
        })
        installMock(wsProviderFailed)

        let clientFailed = makeRealtime { options in
            options.key = "appId.keyId:keySecret"
            options.autoConnect = false
        }
        clientFailed.connect()
        awaitConnectionState(clientFailed, .connected)

        // Trigger FAILED via fatal ERROR
        let wsConn = try #require(wsProviderFailed.activeConnection)
        wsConn.sendToClientAndClose(.error(code: 50000, statusCode: 500, message: "Fatal error"))
        awaitConnectionState(clientFailed, .failed)
        #expect(clientFailed.connection.createRecoveryKey() == nil)

        // --- Test SUSPENDED state ---
        let suspendedAttempts = Captured<MockWebSocket>()
        let wsProviderSuspended = MockWebSocketProvider(onConnectionAttempt: { connection in
            suspendedAttempts.append(connection)
            // All connections fail after initial, to force SUSPENDED
            if suspendedAttempts.count == 1 {
                connection.respondWithSuccess()
                connection.sendToClient(.connected(
                    connectionId: "conn-s",
                    connectionKey: "key-s",
                    maxIdleInterval: 15,
                    connectionStateTtl: 2
                ))
            } else {
                connection.respondWithRefused()
            }
        })
        installMock(wsProviderSuspended)

        enableFakeTimers()

        let clientSuspended = makeRealtime { options in
            options.key = "appId.keyId:keySecret"
            options.disconnectedRetryTimeout = 0.5
            options.autoConnect = false
            options.fallbackHosts = []
        }

        clientSuspended.connect()
        awaitConnectionState(clientSuspended, .connected)

        let wsConnS = try #require(wsProviderSuspended.activeConnection)
        wsConnS.simulateDisconnect()

        // Advance time until SUSPENDED (connectionStateTtl expires)
        for _ in 0..<10 {
            advanceTime(byMilliseconds: 1500)
            if clientSuspended.connection.state == .suspended {
                break
            }
        }

        awaitConnectionState(clientSuspended, .suspended)
        #expect(clientSuspended.connection.createRecoveryKey() == nil)

        closeClient(clientSuspended)
    }

    // UTS: realtime/unit/RTN16k/recover-query-param-0
    @Test
    func test_RTN16k_recover_option_adds_recover_query_param_to_WebSocket_URL() throws {
        // Setup
        let capturedConnectionAttempts = Captured<MockWebSocket>()

        // Construct a valid recoveryKey
        let recoveryKey = try toJSONString([
            "connectionKey": "recovered-key-xyz",
            "msgSerial": 5,
            "channelSerials": [String: String]()
        ])

        let wsProvider = MockWebSocketProvider(onConnectionAttempt: { connection in
            capturedConnectionAttempts.append(connection)
            connection.respondWithSuccess()

            if capturedConnectionAttempts.count == 1 {
                // First connection: successful recovery (same connectionId as implied by recoveryKey)
                connection.sendToClient(.connected(
                    connectionId: "recovered-conn-id",
                    connectionKey: "new-key-after-recovery",
                    maxIdleInterval: 15,
                    connectionStateTtl: 120
                ))
            } else {
                // Subsequent connection: resume after disconnect
                connection.sendToClient(.connected(
                    connectionId: "recovered-conn-id",
                    connectionKey: "resumed-key",
                    maxIdleInterval: 15,
                    connectionStateTtl: 120
                ))
            }
        })
        installMock(wsProvider)

        let client = makeRealtime { options in
            options.key = "appId.keyId:keySecret"
            options.recover = recoveryKey
            options.autoConnect = false
        }

        // Test Steps
        // Connect - should use recover param
        client.connect()
        awaitConnectionState(client, .connected)

        // Simulate disconnect and reconnection
        let wsConnection = try #require(wsProvider.activeConnection)
        wsConnection.simulateDisconnect()

        // Wait for resume reconnection
        // (poll for the second connection attempt first: right after simulate_disconnect the
        // connection is still transiently CONNECTED, so awaiting CONNECTED alone could match the
        // pre-disconnect state rather than the resume.)
        poll("second connection attempt") { capturedConnectionAttempts.count == 2 }
        awaitConnectionState(client, .connected, timeout: 5)

        // Assertions
        // First connection attempt includes recover param with connectionKey from recoveryKey
        #expect(capturedConnectionAttempts[0].queryParams["recover"] == "recovered-key-xyz")

        // First connection attempt does NOT include resume param
        #expect(capturedConnectionAttempts[0].queryParams["resume"] == nil)

        // Second connection attempt uses resume (not recover) since client is now connected
        #expect(capturedConnectionAttempts[1].queryParams["resume"] == "new-key-after-recovery")
        #expect(capturedConnectionAttempts[1].queryParams["recover"] == nil)

        closeClient(client)
    }

    // UTS: realtime/unit/RTN16f/recover-initializes-msgserial-0
    @Test
    func test_RTN16f_recover_option_initializes_msgSerial_from_recoveryKey() throws {
        // Setup
        // Construct a recoveryKey with msgSerial of 42
        let recoveryKey = try toJSONString([
            "connectionKey": "old-key",
            "msgSerial": 42,
            "channelSerials": ["test-channel": "ch-serial-1"]
        ])

        let connectionAttempts = Captured<MockWebSocket>()
        let wsProvider = MockWebSocketProvider(onConnectionAttempt: { connection in
            connectionAttempts.append(connection)
            connection.respondWithSuccess()

            if connectionAttempts.count == 1 {
                // Successful recovery
                connection.sendToClient(.connected(
                    connectionId: "recovered-conn",
                    connectionKey: "new-key",
                    maxIdleInterval: 15,
                    connectionStateTtl: 120
                ))
            }
        })
        installMock(wsProvider)

        let client = makeRealtime { options in
            options.key = "appId.keyId:keySecret"
            options.recover = recoveryKey
            options.autoConnect = false
        }

        // Test Steps
        // Connect with recovery
        client.connect()
        awaitConnectionState(client, .connected)

        // Get WebSocket connection reference
        let wsConnection = try #require(wsProvider.activeConnection)

        // Attach the recovered channel
        let channel = client.channels.get("test-channel")
        channel.attach()
        wsConnection.sendToClient(.attached(channel: "test-channel", channelSerial: "ch-serial-updated"))
        awaitChannelState(channel, .attached)

        // Publish a message - the msgSerial should start from the recovered value (42)
        channel.publish("event", data: "data")

        // Capture the MESSAGE frame sent by the client
        poll("MESSAGE frame sent to server") {
            wsConnection.sentMessages.contains { $0.action == .message }
        }
        let messageFrame = wsConnection.sentMessages.first { $0.action == .message }

        // ACK the message
        wsConnection.sendToClient(.ack(msgSerial: 42, count: 1))

        // Assertions
        // The first message published uses msgSerial from the recoveryKey
        let unwrappedMessageFrame = try #require(messageFrame)
        #expect(unwrappedMessageFrame.msgSerial?.intValue == 42)

        closeClient(client)
    }

    // UTS: realtime/unit/RTN16f1/malformed-recovery-key-0
    @Test
    func test_RTN16f1_malformed_recoveryKey_logs_error_and_connects_normally() {
        // Setup
        let capturedConnectionAttempts = Captured<MockWebSocket>()
        let log = CapturingLog()
        let wsProvider = MockWebSocketProvider(onConnectionAttempt: { connection in
            capturedConnectionAttempts.append(connection)
            connection.respondWithSuccess()
            connection.sendToClient(.connected(
                connectionId: "fresh-conn",
                connectionKey: "fresh-key",
                maxIdleInterval: 15,
                connectionStateTtl: 120
            ))
        })
        installMock(wsProvider)

        // Use a malformed (non-JSON) recover string
        let client = makeRealtime { options in
            options.key = "appId.keyId:keySecret"
            options.recover = "this-is-not-valid-json!!!"
            options.autoConnect = false
            options.logHandler = log
        }

        // Test Steps
        // Connect - should proceed as a normal connection (no recover param)
        client.connect()
        awaitConnectionState(client, .connected)

        // Assertions
        // Connection succeeded normally
        #expect(client.connection.state == .connected)
        #expect(client.connection.id == "fresh-conn")
        #expect(client.connection.key == "fresh-key")

        // No recover param was sent (malformed key was rejected)
        #expect(capturedConnectionAttempts[0].queryParams["recover"] == nil)

        // Also no resume param (this is a fresh connection)
        #expect(capturedConnectionAttempts[0].queryParams["resume"] == nil)

        // Only one connection attempt (normal connection, no retries)
        #expect(capturedConnectionAttempts.count == 1)

        // Implementation note: The spec requires that an error be logged when the recovery key is
        // malformed. Verified here by capturing log output and asserting an error-level message
        // mentioning the malformed recovery key was emitted.
        #expect(log.contains(level: .error, message: "recovery key"))

        closeClient(client)
    }

    // UTS: realtime/unit/RTN16j/recover-channel-serials-0
    @Test
    func test_RTN16j_recover_option_instantiates_channels_from_recoveryKey() throws {
        // Setup
        // Construct a recoveryKey with multiple channels
        let recoveryKey = try toJSONString([
            "connectionKey": "old-key-abc",
            "msgSerial": 10,
            "channelSerials": [
                "channel-one": "serial-1-abc",
                "channel-two": "serial-2-def",
                "channel-üñîçöðé": "serial-3-unicode"
            ]
        ])

        let wsProvider = MockWebSocketProvider(onConnectionAttempt: { connection in
            connection.respondWithSuccess()
            connection.sendToClient(.connected(
                connectionId: "recovered-conn",
                connectionKey: "new-key",
                maxIdleInterval: 15,
                connectionStateTtl: 120
            ))
        })
        installMock(wsProvider)

        let client = makeRealtime { options in
            options.key = "appId.keyId:keySecret"
            options.recover = recoveryKey
            options.autoConnect = false
        }

        // Test Steps
        // Connect with recovery
        client.connect()
        awaitConnectionState(client, .connected)

        // Assertions
        // RTN16j: Channels from the recoveryKey are instantiated
        let channelOne = client.channels.get("channel-one")
        let channelTwo = client.channels.get("channel-two")
        let channelUnicode = client.channels.get("channel-üñîçöðé")

        // Each channel has its channelSerial set from the recoveryKey
        #expect(channelOne.properties.channelSerial == "serial-1-abc")
        #expect(channelTwo.properties.channelSerial == "serial-2-def")
        #expect(channelUnicode.properties.channelSerial == "serial-3-unicode")

        // RTN16i: Channels are NOT automatically attached — the user must explicitly attach them.
        // They should be in INITIALIZED state (the library instantiated them but didn't attach).
        #expect(channelOne.state == .initialized)
        #expect(channelTwo.state == .initialized)
        #expect(channelUnicode.state == .initialized)

        // When the user attaches, the ATTACH message should include the channelSerial
        // (this enables the server to resume the channel from the correct point)
        let wsConnection = try #require(wsProvider.activeConnection)

        channelOne.attach()

        // Capture the ATTACH frame sent by the client
        poll("ATTACH frame for channel-one sent to server") {
            wsConnection.sentMessages.contains { $0.action == .attach && $0.channel == "channel-one" }
        }
        let sentFrames = wsConnection.sentMessages.filter { $0.action == .attach && $0.channel == "channel-one" }
        #expect(sentFrames.count == 1)
        #expect(sentFrames.first?.channelSerial == "serial-1-abc")

        // Complete the attachment
        wsConnection.sendToClient(.attached(channel: "channel-one", channelSerial: "serial-1-abc-updated"))
        awaitChannelState(channelOne, .attached)

        closeClient(client)
    }
}

// MARK: - Helpers

private extension ConnectionRecoveryTests {
    /// Deserializes a JSON object string into a dictionary (UTS `fromJson`).
    func parseJSONObject(_ string: String, sourceLocation: SourceLocation = #_sourceLocation) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: Data(string.utf8))
        guard let dictionary = object as? [String: Any] else {
            Issue.record("Expected a JSON object, got: \(string)", sourceLocation: sourceLocation)
            return [:]
        }
        return dictionary
    }

    /// Serializes a dictionary to a JSON object string (UTS `toJson`).
    func toJSONString(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object)
        return String(decoding: data, as: UTF8.self)
    }
}
