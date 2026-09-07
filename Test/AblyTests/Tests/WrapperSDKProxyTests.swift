import Ably
import XCTest
import Nimble

class WrapperSDKProxyTests: XCTestCase {
    // MARK: - Testing that connection state is shared with underlying Realtime client

    // WP5
    func test_sharesConnectionStateWithUnderlyingClient() throws {
        // Given: A proxy client
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        let client = AblyTests.newRealtime(options).client
        defer { client.dispose(); client.close() }

        let proxyClient = client.createWrapperSDKProxy(with: .init(agents: ["some-agent": test.id.uuidString]))

        // (An example of changes to the underlying connection being reflected in the proxy client)
        //
        // When: The underlying connection becomes CONNECTED
        // Then: So does the proxy client
        waitUntil(timeout: testTimeout) { done in
            proxyClient.connection.on(.connected) { _ in
                done()
            }

            client.connect()
        }
        XCTAssertEqual(proxyClient.connection.state, .connected)

        // (An example of the proxy client provoking changes in the underlying connection)
        //
        // When: We call `close()` on the proxy client
        // Then: It closes the underlying connection
        waitUntil(timeout: testTimeout) { done in
            client.connection.on(.closed) { _ in
                done()
            }

            proxyClient.close()
        }
        XCTAssertEqual(client.connection.state, .closed)
    }

    // WP5
    func test_sharesConnectionSubscriptionsWithUnderlyingRealtimeClient() throws {
        // Given: A proxy client
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        let client = AblyTests.newRealtime(options).client
        defer { client.dispose(); client.close() }

        let proxyClient = client.createWrapperSDKProxy(with: .init(agents: ["some-agent": test.id.uuidString]))

        // When: We add a connection event listener to the underlying client, then call `off()` on the proxy client and provoke a connection event
        var underlyingConnectionReceivedEvent = false
        client.connection.on(.connected) { _ in
            underlyingConnectionReceivedEvent = true
        }

        proxyClient.connection.off()

        // this is the "provoke a connection event" above
        waitUntil(timeout: testTimeout) { done in
            client.connection.on(.connected) { _ in
                done()
            }
            client.connect()
        }

        // Then: We do not receive the connection event on the aforementioned listener, because calling `off()` on the proxy client removed the listener
        XCTAssertFalse(underlyingConnectionReceivedEvent)
    }

    // MARK: - Testing that channel state is shared with underlying Realtime client

    // WP5
    func test_sharesChannelStateWithUnderlyingChannel() throws {
        // Given: A channel fetched from a proxy client
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = AblyTests.newRealtime(options).client
        defer { client.dispose(); client.close() }

        let proxyClient = client.createWrapperSDKProxy(with: .init(agents: ["some-agent": test.id.uuidString]))

        let channelName = test.uniqueChannelName()
        let channel = client.channels.get(channelName)
        let proxyChannel = proxyClient.channels.get(channelName)

        // (An example of changes to the underlying channel being reflected in the proxy channel)
        //
        // When: The underlying connection becomes CONNECTED
        // Then: So does the proxy channel
        waitUntil(timeout: testTimeout) { done in
            proxyChannel.on(.attached) { _ in
                done()
            }

            channel.attach()
        }
        XCTAssertEqual(proxyChannel.state, .attached)

        // (An example of the proxy channel provoking changes in the underlying channel)
        //
        // When: We call `detach()` on the proxy channel
        // Then: It detaches the underlying channel
        waitUntil(timeout: testTimeout) { done in
            channel.on(.detached) { _ in
                done()
            }

            proxyChannel.detach()
        }
        XCTAssertEqual(channel.state, .detached)
    }

    // WP5
    func test_sharesChannelStateSubscriptionsWithUnderlyingChannel() throws {
        // Given: A channel fetched from a proxy client
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = AblyTests.newRealtime(options).client
        defer { client.dispose(); client.close() }

        let proxyClient = client.createWrapperSDKProxy(with: .init(agents: ["some-agent": test.id.uuidString]))

        let channelName = test.uniqueChannelName()
        let channel = client.channels.get(channelName)
        let proxyChannel = proxyClient.channels.get(channelName)

        // When: We add a channel state event listener to the underlying channel, then call `off()` on the proxy channel and provoke a channel state event
        var underlyingChannelReceivedEvent = false
        channel.on(.attached) { _ in
            underlyingChannelReceivedEvent = true
        }

        proxyChannel.off()

        // this is the "provoke a channel state event" above
        waitUntil(timeout: testTimeout) { done in
            channel.on(.attached) { _ in
                done()
            }
            channel.attach()
        }

        // Then: We do not receive the channel state event on the aforementioned listener, because calling `off()` on the proxy channel removed the listener
        XCTAssertFalse(underlyingChannelReceivedEvent)
    }

    // WP5
    func test_sharesChannelMessageSubscriptionsWithUnderlyingChannel() throws {
        // Given: A channel fetched from a proxy client
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = AblyTests.newRealtime(options).client
        defer { client.dispose(); client.close() }

        let proxyClient = client.createWrapperSDKProxy(with: .init(agents: ["some-agent": test.id.uuidString]))

        let channelName = test.uniqueChannelName()
        let channel = client.channels.get(channelName)
        let proxyChannel = proxyClient.channels.get(channelName)

        // When: We add a message listener to the underlying channel, then call `unsubscribe()` on the proxy channel and send a message on the channel
        var underlyingChannelReceivedMessage = false
        channel.subscribe { _ in
            underlyingChannelReceivedMessage = true
        }

        proxyChannel.unsubscribe()

        // this is the "send a message on the channel" above
        waitUntil(timeout: testTimeout) { done in
            channel.subscribe { _ in
                done()
            }
            channel.publish(nil, data: nil)
        }

        // Then: We do not receive the message on the aforementioned listener, because calling `unsubscribe()` on the proxy channel removed the listener
        XCTAssertFalse(underlyingChannelReceivedMessage)
    }

    // MARK: - `request()`

    // WP6
    func test_request_addsWrapperSDKAgentToHeader() throws {
        // Given: a wrapper SDK proxy client
        let test = Test()

        let options = try AblyTests.commonAppSetup(for: test)
        let realtime = ARTRealtime(options: options)
        defer { realtime.dispose(); realtime.close() }

        let testHTTPExecutor = TestProxyHTTPExecutor(logger: .init(clientOptions: options))
        realtime.internal.rest.httpExecutor = testHTTPExecutor

        let proxyClient = realtime.createWrapperSDKProxy(with: .init(agents: ["my-wrapper-sdk": "1.0.0"]))

        // When: We call `request(…)` on the wrapper proxy SDK client

        waitUntil(timeout: testTimeout) { done in
            do {
                try proxyClient.request(
                    "GET",
                    path: "/time",
                    params: nil,
                    body: nil,
                    headers: nil
                ) { response, error in
                    XCTAssertNil(error)
                    done()
                }
            } catch {
                XCTFail("request threw error: \(error)")
                done()
            }
        }

        // Then: The HTTP request contains the wrapper SDK's agents in the Ably-Agent header

        let request = try XCTUnwrap(testHTTPExecutor.requests.first)

        let expectedIdentifier = [
            "ably-pubsub-cocoa/2.0.0",
            ARTDefault.platformAgent(),
            "my-wrapper-sdk/1.0.0"
        ].sorted().joined(separator: " ")
        XCTAssertEqual(request.allHTTPHeaderFields?["Ably-Agent"], expectedIdentifier)
    }

    // WP6
    func test_request_firstAndNext_addWrapperSDKAgentToHeader() throws {
        // Given: a wrapper SDK proxy client
        let test = Test()

        let options = try AblyTests.commonAppSetup(for: test)
        options.testOptions.channelNamePrefix = nil // so that we can just use `channelName` in the `request` call below
        let realtime = ARTRealtime(options: options)
        defer { realtime.dispose(); realtime.close() }

        let testHTTPExecutor = TestProxyHTTPExecutor(logger: .init(clientOptions: options))
        realtime.internal.rest.httpExecutor = testHTTPExecutor

        // Publish some messages so that we can use the history API to fetch them
        let channelName = test.uniqueChannelName()
        let channel = realtime.channels.get(channelName)
        for i in 1...2 {
            waitUntil(timeout: testTimeout) { done in
                channel.publish(nil, data: "\(i)") { error in
                    XCTAssertNil(error)
                    done()
                }
            }
        }

        let proxyClient = realtime.createWrapperSDKProxy(with: .init(agents: ["my-wrapper-sdk": "1.0.0"]))

        // When: We call `request(…)` on the wrapper proxy SDK client and then fetch its `first()` and `next()` pages

        waitUntil(timeout: testTimeout) { done in
            do {
                try proxyClient.request(
                    "GET",
                    path: "/channels/\(channelName)/messages",
                    params: ["limit": "1"],
                    body: nil,
                    headers: nil
                ) { firstPage, error in
                    XCTAssertNil(error)

                    guard let firstPage else {
                        done()
                        return
                    }

                    XCTAssertEqual(firstPage.items.count, 1)

                    firstPage.first { firstPageAgain, error in
                        XCTAssertNil(error)

                        guard let firstPageAgain else {
                            done()
                            return
                        }

                        XCTAssertEqual(firstPageAgain.items.count, 1)

                        firstPageAgain.next { secondPage, error in
                            XCTAssertNil(error)

                            guard let secondPage else {
                                done()
                                return
                            }

                            XCTAssertEqual(secondPage.items.count, 1)

                            done()
                        }
                    }

                }
            } catch {
                XCTFail("request threw error: \(error)")
                done()
            }
        }

        // Then: The HTTP requests all contain the wrapper SDK's agents in the Ably-Agent header

        XCTAssertEqual(testHTTPExecutor.requests.count, 3) // initial `request()`, `first()`, `next()`

        let expectedIdentifier = [
            "ably-pubsub-cocoa/2.0.0",
            ARTDefault.platformAgent(),
            "my-wrapper-sdk/1.0.0"
        ].sorted().joined(separator: " ")

        for request in testHTTPExecutor.requests {
            XCTAssertEqual(request.allHTTPHeaderFields?["Ably-Agent"], expectedIdentifier)
        }
    }

    // WP6
    func parameterizedTest_addsWrapperSDKAgentToRequests(
        test: Test,
        expectedRequestCount: Int = 1,
        performRequest: @escaping (ARTWrapperSDKProxyRealtime) -> Void
    ) throws {
        // Given: a wrapper SDK proxy client

        let options = try AblyTests.commonAppSetup(for: test)
        let realtime = ARTRealtime(options: options)
        defer { realtime.dispose(); realtime.close() }

        let testHTTPExecutor = TestProxyHTTPExecutor(logger: .init(clientOptions: options))
        realtime.internal.rest.httpExecutor = testHTTPExecutor

        let proxyClient = realtime.createWrapperSDKProxy(with: .init(agents: ["my-wrapper-sdk": "1.0.0"]))

        // When: We perform an HTTP request via the wrapper proxy SDK client
        performRequest(proxyClient)

        // Then: The HTTP request all contains the wrapper SDK's agents in the Ably-Agent header
        XCTAssertEqual(testHTTPExecutor.requests.count, expectedRequestCount)

        let expectedIdentifier = [
            "ably-pubsub-cocoa/2.0.0",
            ARTDefault.platformAgent(),
            "my-wrapper-sdk/1.0.0"
        ].sorted().joined(separator: " ")

        for request in testHTTPExecutor.requests {
            XCTAssertEqual(request.allHTTPHeaderFields?["Ably-Agent"], expectedIdentifier)
        }
    }

    // WP6
    func test_time_addsWrapperSDKAgentToRequest() throws {
        let test = Test()

        try parameterizedTest_addsWrapperSDKAgentToRequests(test: test) { proxyClient in
            waitUntil(timeout: testTimeout) { done in
                proxyClient.time() { _, error in
                    XCTAssertNil(error)
                    done()
                }
            }
        }
    }

    // WP6
    func test_history_addsWrapperSDKAgentToRequest() throws {
        let test = Test()

        try parameterizedTest_addsWrapperSDKAgentToRequests(test: test, expectedRequestCount: 3) { proxyClient in
            // Publish some messages so that we can use the history API to fetch them
            let channel = proxyClient.channels.get(test.uniqueChannelName())
            for i in 1...2 {
                waitUntil(timeout: testTimeout) { done in
                    channel.publish(nil, data: "\(i)") { error in
                        XCTAssertNil(error)
                        done()
                    }
                }
            }

            waitUntil(timeout: testTimeout) { done in
                let query = ARTRealtimeHistoryQuery()
                query.limit = 1

                do {
                    try channel.history(query) { firstPage, error in
                        XCTAssertNil(error)

                        guard let firstPage else {
                            done()
                            return
                        }

                        // This test also doubles up as a smoke test that `-first` and `-next` on a normal ARTPaginatedResult (as opposed to an ARTHTTPPaginatedResponse) add the SDK agent

                        firstPage.first { firstPageAgain, error in
                            XCTAssertNil(error)

                            guard let firstPageAgain else {
                                done()
                                return
                            }

                            firstPageAgain.next { _, error in
                                XCTAssertNil(error)
                                done()
                            }
                        }
                    }
                } catch {
                    XCTFail("history threw error \(error)")
                    done()
                }
            }
        }
    }

    // WP6
    func test_stats_addsWrapperSDKAgentToRequest() throws {
        let test = Test()

        try parameterizedTest_addsWrapperSDKAgentToRequests(test: test) { proxyClient in
            waitUntil(timeout: testTimeout) { done in
                proxyClient.stats() { _, error in
                    XCTAssertNil(error)
                    done()
                }
            }
        }
    }

    // WP6
    func test_pushAdmin_addsWrapperSDKAgentToRequests() throws {
        let test = Test()

        try parameterizedTest_addsWrapperSDKAgentToRequests(test: test) { proxyClient in
            waitUntil(timeout: testTimeout) { done in
                proxyClient.push.admin.publish(["clientId" : "foo"], data: ["notification" : ["title" : "Welcome"]]) { error in
                    XCTAssertNil(error)
                    done()
                }
            }
        }
    }

    // WP6
    func test_pushAdmin_channelSubscriptions_addsWrapperSDKAgentToRequests() throws {
        let test = Test()

        // We just do a smoke test of one of the methods offered by this class

        try parameterizedTest_addsWrapperSDKAgentToRequests(test: test) { proxyClient in
            waitUntil(timeout: testTimeout) { done in
                proxyClient.push.admin.channelSubscriptions.listChannels { _, error in
                    XCTAssertNil(error)
                    done()
                }
            }
        }
    }

    // WP6
    func test_pushAdmin_deviceRegistrations_addsWrapperSDKAgentToRequests() throws {
        let test = Test()

        // We just do a smoke test of one of the methods offered by this class

        try parameterizedTest_addsWrapperSDKAgentToRequests(test: test) { proxyClient in
            waitUntil(timeout: testTimeout) { done in
                proxyClient.push.admin.deviceRegistrations.list([:]) { _, error in
                    XCTAssertNil(error)
                    done()
                }
            }
        }
    }

#if os(iOS)
    // WP6
    func test_pushChannel_addsWrapperSDKAgentToRequests() throws {
        let test = Test()

        // We just do a smoke test of one of the methods offered by this class

        try parameterizedTest_addsWrapperSDKAgentToRequests(test: test) { proxyClient in
            // These three lines are copied from PushChannelTests
            let testIdentityTokenDetails = ARTDeviceIdentityTokenDetails(token: "xxxx-xxxx-xxx", issued: Date(), expires: Date.distantFuture, capability: "", clientId: "")
            proxyClient.device.setAndPersistIdentityTokenDetails(testIdentityTokenDetails)
            defer { proxyClient.device.setAndPersistIdentityTokenDetails(nil) }

            let channel = proxyClient.channels.get(test.uniqueChannelName())

            waitUntil(timeout: testTimeout) { done in
                channel.push.subscribeDevice { error in
                    // (We expect this request to fail, because we're using a fake device token. Doesn't matter in this test, because all we care about is checking that the request contained the wrapper SDK agent)
                    if (error?.domain == ARTAblyErrorDomain && error?.code == 40005) {
                        done()
                        return
                    }
                    XCTAssertNil(error)
                    done()
                }
            }
        }
    }
#endif

    // WP6
    func test_presenceHistory_addsWrapperSDKAgentToRequest() throws {
        let test = Test()

        try parameterizedTest_addsWrapperSDKAgentToRequests(test: test) { proxyClient in
            let channel = proxyClient.channels.get(test.uniqueChannelName())

            waitUntil(timeout: testTimeout) { done in
                channel.presence.history() { _, error in
                    XCTAssertNil(error)
                    done()
                }
            }
        }
    }

    // MARK: - `agent` channel param

    // WP7
    private func parameterizedTest_checkAttachProtocolMessage(
        wrapperProxyAgents: [String: String]?,
        fetchProxyChannel: (ARTWrapperSDKProxyRealtime) -> ARTWrapperSDKProxyRealtimeChannel,
        verifyAttachProtocolMessage: (ARTProtocolMessage) -> Void
    ) throws {
        // Given
        let test = Test()

        let options = try AblyTests.commonAppSetup(for: test)
        let realtime = AblyTests.newRealtime(options).client
        defer { realtime.dispose(); realtime.close() }

        let proxyClient = realtime.createWrapperSDKProxy(with: .init(agents: wrapperProxyAgents))

        // When
        let proxyChannel = fetchProxyChannel(proxyClient)

        waitUntil(timeout: testTimeout) { done in
            proxyChannel.attach { error in
                XCTAssertNil(error)
                done()
            }
        }

        // Then
        let transport = try XCTUnwrap(realtime.internal.transport as? TestProxyTransport)
        let attachProtocolMessage = try XCTUnwrap(transport.protocolMessagesSent.first { $0.action == .attach })

        verifyAttachProtocolMessage(attachProtocolMessage)
    }

    // WP7
    func test_doesNotAddAgentParam_whenProxyClientCreatedWithoutAgents() throws {
        let test = Test()

        try parameterizedTest_checkAttachProtocolMessage(
            wrapperProxyAgents: nil,
            fetchProxyChannel: { proxyClient in
                proxyClient.channels.get(test.uniqueChannelName())
            },
            verifyAttachProtocolMessage: { attachProtocolMessage in
                XCTAssertNil(attachProtocolMessage.params)
            }
        )
    }

    // WP7
    func test_addsAgentChannelParam_whenFetchedWithNoChannelOptions() throws {
        let test = Test()

        try parameterizedTest_checkAttachProtocolMessage(
            wrapperProxyAgents: ["my-wrapper-sdk": "1.0.0"],
            fetchProxyChannel: { proxyClient in
                proxyClient.channels.get(test.uniqueChannelName())
            },
            verifyAttachProtocolMessage: { attachProtocolMessage in
                XCTAssertEqual(attachProtocolMessage.params, ["agent": "my-wrapper-sdk/1.0.0"])
            }
        )
    }

    // WP7
    func test_addsAgentChannelParam_whenFetchedWithChannelOptions() throws {
        let test = Test()

        try parameterizedTest_checkAttachProtocolMessage(
            wrapperProxyAgents: ["my-wrapper-sdk": "1.0.0"],
            fetchProxyChannel: { proxyClient in
                let options = ARTRealtimeChannelOptions()
                options.params = ["someKey": "someValue"] // arbitrary
                options.modes = [.subscribe] // arbitrary

                return proxyClient.channels.get(test.uniqueChannelName(), options: options)
            },
            verifyAttachProtocolMessage: { attachProtocolMessage in
                // Check the modes get preserved
                XCTAssertEqual(attachProtocolMessage.flags & Int64(ARTChannelMode.subscribe.rawValue), Int64(ARTChannelMode.subscribe.rawValue))

                // Check the params get merged
                XCTAssertEqual(attachProtocolMessage.params, ["agent": "my-wrapper-sdk/1.0.0", "someKey": "someValue"])
            }
        )
    }
}
