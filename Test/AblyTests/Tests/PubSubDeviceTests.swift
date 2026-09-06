import Ably
import Ably.Private
import AblyPubSubDevice
import Nimble
import XCTest

private let deviceAgentName = "ably-pubsub-device"

class PubSubDeviceTests: XCTestCase {

    // MARK: - The declaration the client carries

    func test__001__createClient__declares_the_device_agent_without_a_version() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false

        let client = PubSubDevice.createClient(options: options)
        defer { client.dispose(); client.close() }

        let agents = try XCTUnwrap(client.internal.options.agents)
        XCTAssertEqual(agents[deviceAgentName], ARTClientInformationAgentNotVersioned)

        // The identifier is emitted as a bare token; a version on it would say
        // nothing, since the SDK entry beside it already carries one.
        let identifier = ARTClientInformation.agentIdentifier(withAdditionalAgents: agents)
        XCTAssertTrue(identifier.contains(" \(deviceAgentName)") || identifier.hasPrefix("\(deviceAgentName) "))
        XCTAssertFalse(identifier.contains("\(deviceAgentName)/"))
    }

    func test__002__createClient__leaves_the_callers_options_untouched() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        options.agents = ["some-wrapper": "1.2.3"]

        let client = PubSubDevice.createClient(options: options)
        defer { client.dispose(); client.close() }

        XCTAssertEqual(options.agents, ["some-wrapper": "1.2.3"])
        XCTAssertNil(options.agents?[deviceAgentName])
    }

    func test__003__createClient__preserves_agents_supplied_by_the_caller() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        options.agents = ["some-wrapper": "1.2.3"]

        let client = PubSubDevice.createClient(options: options)
        defer { client.dispose(); client.close() }

        let agents = try XCTUnwrap(client.internal.options.agents)
        XCTAssertEqual(agents["some-wrapper"], "1.2.3")
        XCTAssertEqual(agents[deviceAgentName], ARTClientInformationAgentNotVersioned)
    }

    func test__004__createClient__the_declaration_wins_over_a_caller_entry_of_the_same_name() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        options.agents = [deviceAgentName: "9.9.9"]

        let client = PubSubDevice.createClient(options: options)
        defer { client.dispose(); client.close() }

        let agents = try XCTUnwrap(client.internal.options.agents)
        XCTAssertEqual(agents[deviceAgentName], ARTClientInformationAgentNotVersioned)
    }

    func test__005__createClient__carries_over_the_rest_of_the_options() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        options.clientId = "device-client"
        options.idempotentRestPublishing = true

        let client = PubSubDevice.createClient(options: options)
        defer { client.dispose(); client.close() }

        XCTAssertEqual(client.internal.options.clientId, "device-client")
        XCTAssertTrue(client.internal.options.idempotentRestPublishing)
    }

    // MARK: - The other doors

    func test__006__createClient__accepts_a_key() throws {
        let client = PubSubDevice.createClient(key: "fake:key")
        defer { client.dispose(); client.close() }

        XCTAssertEqual(client.internal.options.key, "fake:key")
        XCTAssertEqual(client.internal.options.agents?[deviceAgentName], ARTClientInformationAgentNotVersioned)
    }

    func test__007__createClient__accepts_a_token() throws {
        let client = PubSubDevice.createClient(token: "fake_token")
        defer { client.dispose(); client.close() }

        XCTAssertEqual(client.internal.options.token, "fake_token")
        XCTAssertEqual(client.internal.options.agents?[deviceAgentName], ARTClientInformationAgentNotVersioned)
    }

    // MARK: - What reaches the wire
    //
    // Billing reads the agent off the wire, so these assert on what is actually
    // sent rather than on the options the client holds.

    func test__008__createClient__sends_the_declaration_on_the_realtime_connection() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        options.testOptions.transportFactory = TestProxyTransportFactory()

        let client = PubSubDevice.createClient(options: options)
        defer { client.dispose(); client.close() }
        client.connect()

        waitUntil(timeout: testTimeout) { done in
            client.connection.on { stateChange in
                switch stateChange.current {
                case .failed:
                    AblyTests.checkError(stateChange.reason, withAlternative: "Failed state")
                    done()
                case .connected:
                    guard let transport = client.internal.transport as? TestProxyTransport,
                          let query = transport.lastUrl?.query else {
                        XCTFail("MockTransport isn't working")
                        done()
                        return
                    }
                    expect(query).to(haveParam("agent", hasPrefix: "ably-cocoa/"))
                    XCTAssertTrue(query.contains(deviceAgentName))
                    XCTAssertFalse(query.contains("\(deviceAgentName)%2F"))
                    done()
                default:
                    break
                }
            }
        }
    }

    func test__009__createClient__sends_the_declaration_on_http_requests() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false

        let client = PubSubDevice.createClient(options: options)
        defer { client.dispose(); client.close() }

        let testHTTPExecutor = TestProxyHTTPExecutor(logger: .init(clientOptions: options))
        client.internal.rest.httpExecutor = testHTTPExecutor

        waitUntil(timeout: testTimeout) { done in
            client.time { _, error in
                XCTAssertNil(error)
                let headerAgent = testHTTPExecutor.requests.first?.allHTTPHeaderFields?["Ably-Agent"]
                XCTAssertNotNil(headerAgent)
                XCTAssertTrue(headerAgent?.contains(deviceAgentName) ?? false)
                XCTAssertFalse(headerAgent?.contains("\(deviceAgentName)/") ?? true)
                done()
            }
        }
    }

    // MARK: - A client built from the core alone

    func test__010__the_core_constructor__declares_nothing() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false

        let client = ARTRealtime(options: options)
        defer { client.dispose(); client.close() }

        XCTAssertNil(client.internal.options.agents?[deviceAgentName])
    }
}
