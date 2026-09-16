import AblyPubSubDevice
import AblyPubSubDevice.Private
import AblyTestingObjC
import Nimble
import XCTest

private var testHTTPExecutor: TestProxyHTTPExecutor!

private func testOptionsGiveBasicAuthFalse(_ caseSetter: (AuthOptions) -> Void) {
    let options = ClientOptions()
    caseSetter(options)

    let client = HttpClient(options: options)

    XCTAssertFalse(client.auth.internal.options.isBasicAuth())
}

private let expectedHostOrder = [4, 3, 0, 2, 1]
private let shuffleArrayInExpectedHostOrder = { (array: NSMutableArray) in
    let arranged = expectedHostOrder.reversed().map { array[$0] }
    for (i, element) in arranged.enumerated() {
        array[i] = element
    }
}

private let _fallbackHosts = ["f.ably-realtime.com", "g.ably-realtime.com", "h.ably-realtime.com", "i.ably-realtime.com", "j.ably-realtime.com"]

private func testUsesAlternativeHost(_ caseTest: FakeNetworkResponse, channelName: String) {
    let options = ClientOptions(key: "xxxx:xxxx")
    let client = HttpClient(options: options)
    let internalLog = InternalLog(clientOptions: options)
    let mockHTTP = MockHTTP(logger: internalLog)
    testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: internalLog)
    client.internal.httpExecutor = testHTTPExecutor
    mockHTTP.setNetworkState(network: caseTest, resetAfter: 1)
    let channel = client.channels.get(channelName)

    waitUntil(timeout: testTimeout) { done in
        channel.publish(nil, data: "nil") { _ in
            done()
        }
    }

    XCTAssertEqual(testHTTPExecutor.requests.count, 2)
    if testHTTPExecutor.requests.count != 2 {
        return
    }
    XCTAssertTrue(NSRegularExpression.match(testHTTPExecutor.requests[0].url!.absoluteString, pattern: "//rest.ably.io"))
    XCTAssertTrue(NSRegularExpression.match(testHTTPExecutor.requests[1].url!.absoluteString, pattern: "//[a-e].ably-realtime.com"))
}

private func testStoresSuccessfulFallbackHostAsDefaultHost(_ caseTest: FakeNetworkResponse, channelName: String) {
    let options = ClientOptions(key: "xxxx:xxxx")
    let client = HttpClient(options: options)
    let internalLog = InternalLog(clientOptions: options)
    let mockHTTP = MockHTTP(logger: internalLog)
    testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: internalLog)
    client.internal.httpExecutor = testHTTPExecutor
    mockHTTP.setNetworkState(network: caseTest, resetAfter: 1)
    let channel = client.channels.get(channelName)

    waitUntil(timeout: testTimeout) { done in
        channel.publish(nil, data: "nil") { _ in
            done()
        }
    }

    XCTAssertEqual(testHTTPExecutor.requests.count, 2)
    XCTAssertTrue(NSRegularExpression.match(testHTTPExecutor.requests[0].url!.host, pattern: "rest.ably.io"))
    XCTAssertTrue(NSRegularExpression.match(testHTTPExecutor.requests[1].url!.host, pattern: "[a-e].ably-realtime.com"))

    // #1 Store fallback used to request
    let usedFallbackURL = testHTTPExecutor.requests[1].url!

    waitUntil(timeout: testTimeout) { done in
        channel.publish(nil, data: "nil") { _ in
            done()
        }
    }

    let reusedURL = testHTTPExecutor.requests[2].url!

    // Reuse host has to be equal previous (stored #1) fallback host
    XCTAssertEqual(testHTTPExecutor.requests.count, 3)
    XCTAssertEqual(usedFallbackURL.host, reusedURL.host)
}

private func testRestoresDefaultPrimaryHostAfterTimeoutExpires(_ caseTest: FakeNetworkResponse, channelName: String) {
    let options = ClientOptions(key: "xxxx:xxxx")
    options.logLevel = .debug
    options.fallbackRetryTimeout = 1
    let client = HttpClient(options: options)
    let internalLog = InternalLog(clientOptions: options)
    let mockHTTP = MockHTTP(logger: internalLog)
    testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: internalLog)
    client.internal.httpExecutor = testHTTPExecutor
    mockHTTP.setNetworkState(network: caseTest, resetAfter: 1)
    let channel = client.channels.get(channelName)

    waitUntil(timeout: testTimeout) { done in
        channel.publish(nil, data: "nil") { _ in
            done()
        }
    }

    waitUntil(timeout: testTimeout) { done in
        delay(1.1) {
            channel.publish(nil, data: "nil") { _ in
                done()
            }
        }
    }

    XCTAssertEqual(testHTTPExecutor.requests.count, 3)
    XCTAssertEqual(testHTTPExecutor.requests[2].url!.host, "rest.ably.io")
}

private func testUsesAnotherFallbackHost(_ caseTest: FakeNetworkResponse, channelName: String) {
    let options = ClientOptions(key: "xxxx:xxxx")
    options.fallbackRetryTimeout = 10
    options.logLevel = .debug
    let client = HttpClient(options: options)
    let internalLog = InternalLog(clientOptions: options)
    let mockHTTP = MockHTTP(logger: internalLog)
    testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: internalLog)
    client.internal.httpExecutor = testHTTPExecutor
    mockHTTP.setNetworkState(network: caseTest, resetAfter: 2)
    let channel = client.channels.get(channelName)

    waitUntil(timeout: testTimeout) { done in
        channel.publish(nil, data: "nil") { _ in
            done()
        }
    }

    XCTAssertEqual(testHTTPExecutor.requests.count, 3)
    XCTAssertTrue(NSRegularExpression.match(testHTTPExecutor.requests[1].url!.host, pattern: "[a-e].ably-realtime.com"))
    XCTAssertTrue(NSRegularExpression.match(testHTTPExecutor.requests[2].url!.host, pattern: "[a-e].ably-realtime.com"))
    XCTAssertNotEqual(testHTTPExecutor.requests[1].url!.host, testHTTPExecutor.requests[2].url!.host)
}

class HttpClientTests: XCTestCase {
    // XCTest invokes this method before executing the first test in the test suite. We use it to ensure that the global variables are initialized at the same moment, and in the same order, as they would have been when we used the Quick testing framework.
    override class var defaultTestSuite: XCTestSuite {
        _ = testHTTPExecutor
        _ = expectedHostOrder
        _ = _fallbackHosts

        return super.defaultTestSuite
    }

    // G4
    func test__001__RestClient__All_REST_requests_should_include_the_current_API_version() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = HttpClient(options: options)
        testHTTPExecutor = TestProxyHTTPExecutor(logger: .init(clientOptions: options))
        client.internal.httpExecutor = testHTTPExecutor
        let channel = client.channels.get(test.uniqueChannelName())
        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "message") { error in
                XCTAssertNil(error)
                let version = testHTTPExecutor.requests.first!.allHTTPHeaderFields?["X-Ably-Version"]

                // This test should not directly validate version against Default.version(), as
                // ultimately the version header has been derived from that value.
                XCTAssertEqual(version, "6")

                done()
            }
        }
    }

    // RSC1

    func test__015__RestClient__initializer__should_accept_an_API_key() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)

        let client = HttpClient(key: options.key!)
        client.internal.prioritizedHost = options.restHost

        let publishTask = publishTestMessage(client, channelName: test.uniqueChannelName())

        expect(publishTask.error).toEventually(beNil(), timeout: testTimeout)
    }

    func test__016__RestClient__initializer__should_throw_when_provided_an_invalid_key() {
        XCTAssertNotNil(tryInObjC {
            _ = HttpClient(key: "invalid_key")
        })
    }

    func test__017__RestClient__initializer__should_result_in_error_status_when_provided_a_bad_key() {
        let test = Test()
        let client = HttpClient(key: "fake:key")

        let publishTask = publishTestMessage(client, channelName: test.uniqueChannelName(), failOnError: false)

        expect(publishTask.error?.code).toEventually(equal(ErrorCode.invalidCredentials.intValue), timeout: testTimeout)
    }

    func test__018__RestClient__initializer__should_accept_a_token() throws {
        let test = Test()
        ClientOptions.setDefaultEnvironment(getEnvironment())
        defer { ClientOptions.setDefaultEnvironment(nil) }

        let client = HttpClient(token: try getTestToken(for: test))
        let publishTask = publishTestMessage(client, channelName: test.uniqueChannelName())
        expect(publishTask.error).toEventually(beNil(), timeout: testTimeout)
    }

    func test__019__RestClient__initializer__should_accept_an_options_object() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = HttpClient(options: options)

        let publishTask = publishTestMessage(client, channelName: test.uniqueChannelName())

        expect(publishTask.error).toEventually(beNil(), timeout: testTimeout)
    }

    func test__020__RestClient__initializer__should_accept_an_options_object_with_token_authentication() throws {
        let test = Test()
        let options = try AblyTests.clientOptions(for: test, requestToken: true)
        let client = HttpClient(options: options)

        let publishTask = publishTestMessage(client, channelName: test.uniqueChannelName())

        expect(publishTask.error).toEventually(beNil(), timeout: testTimeout)
    }

    func test__021__RestClient__initializer__should_result_in_error_status_when_provided_a_bad_token() throws {
        let test = Test()
        let options = try AblyTests.clientOptions(for: test)
        options.token = "invalid_token"
        let client = HttpClient(options: options)

        let publishTask = publishTestMessage(client, channelName: test.uniqueChannelName(), failOnError: false)

        expect(publishTask.error?.code).toEventually(equal(ErrorCode.invalidCredentials.intValue), timeout: testTimeout)
    }

    // RSC2
    func test__022__RestClient__logging__should_output_to_the_system_log_and_the_log_level_should_be_Warn() {
        ClientOptions.setDefaultEnvironment(getEnvironment())
        defer {
            ClientOptions.setDefaultEnvironment(nil)
        }

        let options = ClientOptions(key: "xxxx:xxxx")
        options.logHandler = Log(capturingOutput: true)
        let client = HttpClient(options: options)

        client.internal.logger_onlyForUseInClassMethodsAndTests.log("This is a warning", with: .warn, file: "foo.m", line: 10)

        XCTAssertEqual(client.internal.logger_onlyForUseInClassMethodsAndTests.logLevel, LogLevel.warn)
        guard let line = options.logHandler.captured.last else {
            fail("didn't log line.")
            return
        }
        XCTAssertEqual(line.level, LogLevel.warn)
        XCTAssertEqual(line.toString(), "WARN: (foo.m:10) This is a warning")
    }

    // RSC3
    func test__023__RestClient__logging__should_have_a_mutable_log_level() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.logHandler = Log(capturingOutput: true)
        let client = HttpClient(options: options)
        client.internal.logger_onlyForUseInClassMethodsAndTests.logLevel = .error

        let logTime = NSDate()
        client.internal.logger_onlyForUseInClassMethodsAndTests.log("This is a warning", with: .warn, file: "foo.m", line: 10)

        let logs = options.logHandler.captured.filter { !$0.date.isBefore(logTime as Date) }
        expect(logs).to(beEmpty())
    }

    // RSC4
    func test__024__RestClient__logging__should_accept_a_custom_logger() throws {
        let test = Test()

        enum Captured {
            static var log: (String, LogLevel) = ("", .none)
        }
        class MyLogger: Log {
            override func log(_ message: String, with level: LogLevel) {
                Captured.log = (message, level)
            }
        }

        let options = try AblyTests.commonAppSetup(for: test)
        let customLogger = MyLogger()
        options.logHandler = customLogger
        options.logLevel = .verbose
        let client = HttpClient(options: options)

        client.internal.logger_onlyForUseInClassMethodsAndTests.log("This is a warning", with: .warn, file: "foo.m", line: 10)

        XCTAssertEqual(Captured.log.0, "(foo.m:10) This is a warning")
        XCTAssertEqual(Captured.log.1, LogLevel.warn)

        XCTAssertEqual(client.internal.logger_onlyForUseInClassMethodsAndTests.logLevel, customLogger.logLevel)
    }

    // RSC11

    // RSC11a
    func test__025__RestClient__endpoint__should_accept_a_custom_host_and_send_requests_to_the_specified_host() {
        let test = Test()
        let options = ClientOptions(key: "fake:key")
        options.restHost = "fake.ably.io"
        let client = HttpClient(options: options)
        testHTTPExecutor = TestProxyHTTPExecutor(logger: .init(clientOptions: options))
        client.internal.httpExecutor = testHTTPExecutor

        publishTestMessage(client, channelName: test.uniqueChannelName(), failOnError: false)

        expect(testHTTPExecutor.requests.first?.url?.host).toEventually(equal("fake.ably.io"), timeout: testTimeout)
    }

    func test__026__RestClient__endpoint__should_ignore_an_environment_when_restHost_is_customized() {
        let test = Test()
        let options = ClientOptions(key: "fake:key")
        options.environment = "test"
        options.restHost = "fake.ably.io"
        let client = HttpClient(options: options)
        testHTTPExecutor = TestProxyHTTPExecutor(logger: .init(clientOptions: options))
        client.internal.httpExecutor = testHTTPExecutor

        publishTestMessage(client, channelName: test.uniqueChannelName(), failOnError: false)

        expect(testHTTPExecutor.requests.first?.url?.host).toEventually(equal("fake.ably.io"), timeout: testTimeout)
    }

    // RSC11b
    func test__027__RestClient__endpoint__should_accept_an_environment_when_restHost_is_left_unchanged() {
        let test = Test()
        let options = ClientOptions(key: "fake:key")
        options.environment = "myEnvironment"
        let client = HttpClient(options: options)
        testHTTPExecutor = TestProxyHTTPExecutor(logger: .init(clientOptions: options))
        client.internal.httpExecutor = testHTTPExecutor

        publishTestMessage(client, channelName: test.uniqueChannelName(), failOnError: false)

        expect(testHTTPExecutor.requests.first?.url?.host).toEventually(equal("myEnvironment-rest.ably.io"), timeout: testTimeout)
    }

    func test__028__RestClient__endpoint__should_default_to_https___rest_ably_io() {
        let test = Test()
        let options = ClientOptions(key: "fake:key")
        let client = HttpClient(options: options)
        testHTTPExecutor = TestProxyHTTPExecutor(logger: .init(clientOptions: options))
        client.internal.httpExecutor = testHTTPExecutor

        publishTestMessage(client, channelName: test.uniqueChannelName(), failOnError: false)

        expect(testHTTPExecutor.requests.first?.url?.absoluteString).toEventually(beginWith("https://rest.ably.io"), timeout: testTimeout)
    }

    func test__029__RestClient__endpoint__should_connect_over_plain_http____when_tls_is_off() throws {
        let test = Test()
        let options = try AblyTests.clientOptions(for: test, requestToken: true)
        options.tls = false
        let client = HttpClient(options: options)
        testHTTPExecutor = TestProxyHTTPExecutor(logger: .init(clientOptions: options))
        client.internal.httpExecutor = testHTTPExecutor

        publishTestMessage(client, channelName: test.uniqueChannelName(), failOnError: false)

        expect(testHTTPExecutor.requests.first?.url?.scheme).toEventually(equal("http"), timeout: testTimeout)
    }

    // RSC11b
    func test__030__RestClient__endpoint__should_not_prepend_the_environment_if_environment_is_configured_as__production_() {
        let options = ClientOptions(key: "xxxx:xxxx")
        options.environment = "production"
        let client = HttpClient(options: options)
        XCTAssertEqual(client.internal.options.restHost, Default.restHost())
        XCTAssertEqual(client.internal.options.realtimeHost, Default.realtimeHost())
    }

    // RSC13

    func test__031__RestClient__should_use_the_the_connection_and_request_timeouts_specified__timeout_for_any_single_HTTP_request_and_response() {
        let test = Test()
        let options = ClientOptions(key: "xxxx:xxxx")
        options.restHost = "10.255.255.1" // non-routable IP address
        XCTAssertEqual(options.httpRequestTimeout, 10.0) // Seconds
        options.httpRequestTimeout = 1.0
        let client = HttpClient(options: options)
        let channel = client.channels.get(test.uniqueChannelName())
        waitUntil(timeout: testTimeout) { done in
            let start = NSDate()
            channel.publish(nil, data: "message") { error in
                let end = NSDate()
                expect(end.timeIntervalSince(start as Date)).to(beCloseTo(options.httpRequestTimeout, within: 0.5))
                XCTAssertNotNil(error)
                if let error = error {
                    expect(error.code).to(satisfyAnyOf(equal(-1001 /* Timed Out */ ), equal(-1004 /* Cannot Connect To Host */ )))
                }
                done()
            }
        }
    }

    func test__032__RestClient__should_use_the_the_connection_and_request_timeouts_specified__max_number_of_fallback_hosts() {
        let test = Test()
        let options = ClientOptions(key: "xxxx:xxxx")
        XCTAssertEqual(options.httpMaxRetryCount, 3)
        options.httpMaxRetryCount = 1
        let client = HttpClient(options: options)
        let internalLog = InternalLog(clientOptions: options)
        let mockHTTP = MockHTTP(logger: internalLog)
        testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: internalLog)
        client.internal.httpExecutor = testHTTPExecutor
        mockHTTP.setNetworkState(network: .hostUnreachable)

        var totalRetry: UInt = 0
        testHTTPExecutor.setListenerAfterRequest { request in
            if NSRegularExpression.match(request.url!.absoluteString, pattern: "//[a-e].ably-realtime.com") {
                totalRetry += 1
            }
        }

        let channel = client.channels.get(test.uniqueChannelName())
        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "nil") { _ in
                done()
            }
        }
        XCTAssertEqual(totalRetry, options.httpMaxRetryCount)
    }

    func test__033__RestClient__should_use_the_the_connection_and_request_timeouts_specified__max_elapsed_time_in_which_fallback_host_retries_for_HTTP_requests_will_be_attempted() {
        let test = Test()
        let options = ClientOptions(key: "xxxx:xxxx")
        XCTAssertEqual(options.httpMaxRetryDuration, 15.0) // Seconds
        options.httpMaxRetryDuration = 1.0
        let client = HttpClient(options: options)
        let internalLog = InternalLog(clientOptions: options)
        let mockHTTP = MockHTTP(logger: internalLog)
        testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: internalLog)
        client.internal.httpExecutor = testHTTPExecutor
        mockHTTP.setNetworkState(network: .requestTimeout(timeout: 0.1))
        let channel = client.channels.get(test.uniqueChannelName())
        waitUntil(timeout: testTimeout) { done in
            let start = Date()
            channel.publish(nil, data: "nil") { _ in
                let end = Date()
                expect(end.timeIntervalSince(start)).to(beCloseTo(options.httpMaxRetryDuration, within: 0.9))
                done()
            }
        }
    }

    // RSC5
    func test__002__RestClient__should_provide_access_to_the_AuthOptions_object_passed_in_ClientOptions() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = HttpClient(options: options)

        let authOptions = client.auth.internal.options

        XCTAssertTrue(authOptions == options)
    }

    // RSC12
    func test__003__RestClient__REST_endpoint_host_should_be_configurable_in_the_Client_constructor_with_the_option_restHost() throws {
        let test = Test()
        let options = ClientOptions(key: "xxxx:xxxx")
        XCTAssertEqual(options.restHost, "rest.ably.io")
        options.restHost = "rest.ably.test"
        XCTAssertEqual(options.restHost, "rest.ably.test")
        let client = HttpClient(options: options)
        testHTTPExecutor = TestProxyHTTPExecutor(logger: .init(clientOptions: options))
        client.internal.httpExecutor = testHTTPExecutor
        waitUntil(timeout: testTimeout) { done in
            client.channels.get(test.uniqueChannelName()).publish(nil, data: "message") { error in
                XCTAssertNotNil(error)
                done()
            }
        }

        let url = try XCTUnwrap(testHTTPExecutor.requests.first?.url, "No request url found")

        expect(url.absoluteString).to(contain("//rest.ably.test"))
    }

    // RSC16

    func test__034__RestClient__time__should_return_server_time() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = HttpClient(options: options)

        var time: NSDate?

        client.time { date, _ in
            time = date as NSDate? as NSDate?
        }

        expect(time?.timeIntervalSince1970).toEventually(beCloseTo(NSDate().timeIntervalSince1970, within: 60), timeout: testTimeout)
    }

    // RSC7, RSC18
    func test__004__RestClient__should_send_requests_over_http_and_https() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)

        let clientHttps = HttpClient(options: options)
        testHTTPExecutor = TestProxyHTTPExecutor(logger: .init(clientOptions: options))
        clientHttps.internal.httpExecutor = testHTTPExecutor

        let channelName = test.uniqueChannelName()

        waitUntil(timeout: testTimeout) { done in
            publishTestMessage(clientHttps, channelName: channelName) { _ in
                done()
            }
        }

        let requestUrlA = try XCTUnwrap(testHTTPExecutor.requests.first?.url, "No request url found")

        XCTAssertEqual(requestUrlA.scheme, "https")

        options.clientId = "client_http"
        options.useTokenAuth = true
        options.tls = false
        let clientHttp = HttpClient(options: options)
        testHTTPExecutor = TestProxyHTTPExecutor(logger: .init(clientOptions: options))
        clientHttp.internal.httpExecutor = testHTTPExecutor

        waitUntil(timeout: testTimeout) { done in
            publishTestMessage(clientHttp, channelName: channelName) { _ in
                done()
            }
        }

        let requestUrlB = try XCTUnwrap(testHTTPExecutor.requests.last?.url, "No request url found")
        XCTAssertEqual(requestUrlB.scheme, "http")
    }

    // RSC9
    func test__005__RestClient__should_use_Auth_to_manage_authentication() throws {
        let test = Test()
        let options = try AblyTests.clientOptions(for: test)
        let testTokenDetails = try getTestTokenDetails(for: test)
        options.tokenDetails = testTokenDetails
        options.authCallback = { _, completion in
            completion(testTokenDetails, nil)
        }

        let client = HttpClient(options: options)
        expect(client.auth).to(beAnInstanceOf(Auth.self))

        waitUntil(timeout: testTimeout) { done in
            client.auth.authorize(nil, options: nil) { tokenDetails, error in
                if let e = error {
                    XCTFail(e.localizedDescription)
                    done()
                    return
                }
                guard let tokenDetails = tokenDetails else {
                    XCTFail("expected tokenDetails to not be nil when error is nil")
                    done()
                    return
                }
                XCTAssertEqual(tokenDetails.token, testTokenDetails.token)
                done()
            }
        }
    }

    // RSC10
    func test__006__RestClient__should_request_another_token_after_current_one_is_no_longer_valid() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.token = try getTestToken(for: test, ttl: 0.5)
        let client = HttpClient(options: options)
        testHTTPExecutor = TestProxyHTTPExecutor(logger: .init(clientOptions: options))
        client.internal.httpExecutor = testHTTPExecutor
        let auth = client.auth

        waitUntil(timeout: testTimeout) { done in
            delay(1.0) {
                client.channels.get(test.uniqueChannelName()).history { result, error in
                    XCTAssertNil(error)
                    XCTAssertNotNil(result)

                    guard let headerErrorCode = testHTTPExecutor.responses.first?.value(forHTTPHeaderField: "X-Ably-Errorcode") else {
                        fail("X-Ably-Errorcode not found"); done()
                        return
                    }
                    XCTAssertEqual(Int(headerErrorCode), ErrorCode.tokenExpired.intValue)

                    // Different token
                    XCTAssertNotEqual(auth.tokenDetails!.token, options.token)
                    done()
                }
            }
        }
    }

    // RSC10
    func test__007__RestClient__should_result_in_an_error_when_user_does_not_have_sufficient_permissions() throws {
        let test = Test()
        let options = try AblyTests.clientOptions(for: test)
        options.token = try getTestToken(for: test, capability: "{ \"main\":[\"subscribe\"] }")
        let client = HttpClient(options: options)
        testHTTPExecutor = TestProxyHTTPExecutor(logger: .init(clientOptions: options))
        client.internal.httpExecutor = testHTTPExecutor

        waitUntil(timeout: testTimeout) { done in
            client.channels.get(test.uniqueChannelName()).history { result, error in
                guard let errorCode = error?.code else {
                    fail("Error is empty"); done()
                    return
                }
                XCTAssertEqual(errorCode, ErrorCode.operationNotPermittedWithProvidedCapability.intValue)
                XCTAssertNil(result)

                guard let headerErrorCode = testHTTPExecutor.responses.first?.value(forHTTPHeaderField: "X-Ably-Errorcode") else {
                    fail("X-Ably-Errorcode not found"); done()
                    return
                }
                XCTAssertEqual(Int(headerErrorCode), ErrorCode.operationNotPermittedWithProvidedCapability.intValue)
                done()
            }
        }
    }

    // RSC14

    // RSC14a
    func test__035__RestClient__Authentication__should_support_basic_authentication_when_an_API_key_is_provided_with_the_key_option() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        guard let components = options.key?.components(separatedBy: ":"), let keyName = components.first, let keySecret = components.last else {
            fail("Invalid API key: \(options.key ?? "nil")"); return
        }
        ClientOptions.setDefaultEnvironment(getEnvironment())
        defer {
            ClientOptions.setDefaultEnvironment(nil)
        }
        let rest = HttpClient(key: "\(keyName):\(keySecret)")
        waitUntil(timeout: testTimeout) { done in
            rest.channels.get(test.uniqueChannelName()).publish(nil, data: "testing") { error in
                XCTAssertNil(error)
                done()
            }
        }
    }

    // RSC14b

    func test__038__RestClient__Authentication__basic_authentication_flag__should_be_true_when_initialized_with_a_key() {
        let client = HttpClient(key: "key:secret")
        XCTAssertTrue(client.auth.internal.options.isBasicAuth())
    }

    func test__039__RestClient__Authentication__basic_authentication_flag__should_be_false_when_options__useTokenAuth_is_set() {
        testOptionsGiveBasicAuthFalse { $0.useTokenAuth = true; $0.key = "fake:key" }
    }

    func test__040__RestClient__Authentication__basic_authentication_flag__should_be_false_when_options__authUrl_is_set() {
        testOptionsGiveBasicAuthFalse { $0.authUrl = URL(string: "http://test.com") }
    }

    func test__041__RestClient__Authentication__basic_authentication_flag__should_be_false_when_options__authCallback_is_set() {
        testOptionsGiveBasicAuthFalse { $0.authCallback = { _, _ in } }
    }

    func test__042__RestClient__Authentication__basic_authentication_flag__should_be_false_when_options__tokenDetails_is_set() {
        testOptionsGiveBasicAuthFalse { $0.tokenDetails = TokenDetails(token: "token") }
    }

    func test__043__RestClient__Authentication__basic_authentication_flag__should_be_false_when_options__token_is_set() {
        testOptionsGiveBasicAuthFalse { $0.token = "token" }
    }

    func test__044__RestClient__Authentication__basic_authentication_flag__should_be_false_when_options__key_is_set() {
        testOptionsGiveBasicAuthFalse { $0.tokenDetails = TokenDetails(token: "token"); $0.key = "fake:key" }
    }

    // RSC14c
    func test__036__RestClient__Authentication__should_error_when_expired_token_and_no_means_to_renew() throws {
        let test = Test()
        let client = HttpClient(options: try AblyTests.commonAppSetup(for: test))
        let auth = client.auth

        let tokenParams = TokenParams()
        let tokenTtl = 3.0
        tokenParams.ttl = NSNumber(value: tokenTtl) // Seconds

        let options: ClientOptions = try AblyTests.waitFor(timeout: testTimeout) { value in
            auth.requestToken(tokenParams, with: nil) { tokenDetails, error in
                if let e = error {
                    XCTFail(e.localizedDescription)
                    value(nil)
                    return
                }

                guard let currentTokenDetails = tokenDetails else {
                    XCTFail("expected tokenDetails not to be nil when error is nil")
                    value(nil)
                    return
                }

                let options: ClientOptions
                do {
                    options = try AblyTests.clientOptions(for: test)
                } catch {
                    XCTFail(error.localizedDescription)
                    value(nil)
                    return
                }
                options.key = client.internal.options.key

                // Expired token
                options.tokenDetails = TokenDetails(
                    token: currentTokenDetails.token,
                    expires: currentTokenDetails.expires!.addingTimeInterval(testTimeout.toTimeInterval()),
                    issued: currentTokenDetails.issued,
                    capability: currentTokenDetails.capability,
                    clientId: currentTokenDetails.clientId
                )

                options.authUrl = URL(string: "http://test-auth.ably.io")
                value(options)
            }
        }

        let rest = HttpClient(options: options)
        testHTTPExecutor = TestProxyHTTPExecutor(logger: .init(clientOptions: options))
        rest.internal.httpExecutor = testHTTPExecutor

        waitUntil(timeout: testTimeout) { done in
            // Delay for token expiration
            delay(tokenTtl + AblyTests.tokenExpiryTolerance) {
                // [40140, 40150) - token expired and will not recover because authUrl is invalid
                publishTestMessage(rest, channelName: test.uniqueChannelName()) { error in
                    guard let errorCode = testHTTPExecutor.responses.first?.value(forHTTPHeaderField: "X-Ably-Errorcode") else {
                        fail("expected X-Ably-Errorcode header in response")
                        return
                    }
                    expect(Int(errorCode)).to(beGreaterThanOrEqualTo(ErrorCode.tokenErrorUnspecified.intValue))
                    expect(Int(errorCode)).to(beLessThan(ErrorCode.connectionLimitsExceeded.intValue))
                    XCTAssertNotNil(error)
                    done()
                }
            }
        }
    }

    // RSC14d
    func test__037__RestClient__Authentication__should_renew_the_token_when_it_has_expired() throws {
        let test = Test()
        let client = HttpClient(options: try AblyTests.commonAppSetup(for: test))
        let auth = client.auth

        let tokenParams = TokenParams()
        let tokenTtl = 3.0
        tokenParams.ttl = NSNumber(value: tokenTtl) // Seconds

        waitUntil(timeout: testTimeout) { done in
            auth.requestToken(tokenParams, with: nil) { tokenDetails, error in
                if let e = error {
                    XCTFail(e.localizedDescription)
                    done()
                    return
                }

                guard let currentTokenDetails = tokenDetails else {
                    XCTFail("expected tokenDetails not to be nil when error is nil")
                    done()
                    return
                }

                let options: ClientOptions
                do {
                    options = try AblyTests.clientOptions(for: test)
                } catch {
                    XCTFail(error.localizedDescription)
                    done()
                    return
                }
                options.key = client.internal.options.key

                // Expired token
                options.tokenDetails = TokenDetails(
                    token: currentTokenDetails.token,
                    expires: currentTokenDetails.expires!.addingTimeInterval(testTimeout.toTimeInterval()),
                    issued: currentTokenDetails.issued,
                    capability: currentTokenDetails.capability,
                    clientId: currentTokenDetails.clientId
                )

                let rest = HttpClient(options: options)
                testHTTPExecutor = TestProxyHTTPExecutor(logger: .init(clientOptions: options))
                rest.internal.httpExecutor = testHTTPExecutor

                // Delay for token expiration
                delay(tokenTtl + AblyTests.tokenExpiryTolerance) {
                    // [40140, 40150) - token expired and will not recover because authUrl is invalid
                    publishTestMessage(rest, channelName: test.uniqueChannelName()) { error in
                        guard let errorCode = testHTTPExecutor.responses.first?.value(forHTTPHeaderField: "X-Ably-Errorcode") else {
                            fail("expected X-Ably-Errorcode header in response")
                            return
                        }
                        expect(Int(errorCode)).to(beGreaterThanOrEqualTo(ErrorCode.tokenErrorUnspecified.intValue))
                        expect(Int(errorCode)).to(beLessThan(ErrorCode.connectionLimitsExceeded.intValue))
                        XCTAssertNil(error)
                        XCTAssertNotEqual(rest.auth.tokenDetails!.token, currentTokenDetails.token)
                        done()
                    }
                }
            }
        }
    }

    // RSC15

    // TO3k7

    // RSC15b

    // RSC15b1
    func test__055__RestClient__Host_Fallback__Fallback_behavior__should_be_applied_when_restHost__port_and_tlsPort_has_not_been_set_to_an_explicit_value() throws {
        let test = Test()
        let options = ClientOptions(key: "xxxx:xxxx")
        let client = HttpClient(options: options)
        let internalLog = InternalLog(clientOptions: options)
        let mockHTTP = MockHTTP(logger: internalLog)
        testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: internalLog)
        client.internal.httpExecutor = testHTTPExecutor
        mockHTTP.setNetworkState(network: .hostUnreachable, resetAfter: 2)
        mockHTTP.setSuccessResponse(
            data: try JSONSerialization.data(withJSONObject: ["serials": []], options: []),
            contentType: "application/json"
        )
        let channel = client.channels.get(test.uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "") { error in
                XCTAssertNil(error)
                done()
            }
        }

        let requests = testHTTPExecutor.requests
        XCTAssertEqual(requests.count, 3)
        let capturedURLs = requests.map { $0.url!.absoluteString }
        XCTAssertTrue(NSRegularExpression.match(capturedURLs.at(0), pattern: "//rest.ably.io"))
        XCTAssertTrue(NSRegularExpression.match(capturedURLs.at(1), pattern: "//[a-e].ably-realtime.com"))
        XCTAssertTrue(NSRegularExpression.match(capturedURLs.at(2), pattern: "//[a-e].ably-realtime.com"))
    }

    // RSC15b1
    func test__056__RestClient__Host_Fallback__Fallback_behavior__should_NOT_be_applied_when_ClientOptions_restHost_has_been_set() {
        let test = Test()
        let options = ClientOptions(key: "xxxx:xxxx")
        options.restHost = "fake.ably.io"
        let client = HttpClient(options: options)
        let internalLog = InternalLog(clientOptions: options)
        let mockHTTP = MockHTTP(logger: internalLog)
        testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: internalLog)
        client.internal.httpExecutor = testHTTPExecutor
        mockHTTP.setNetworkState(network: .hostUnreachable)
        let channel = client.channels.get(test.uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "") { error in
                expect(error?.message).to(contain("hostname could not be found"))
                done()
            }
        }

        let requests = testHTTPExecutor.requests
        XCTAssertEqual(requests.count, 1)
        let capturedURLs = requests.map { $0.url!.absoluteString }
        XCTAssertTrue(NSRegularExpression.match(capturedURLs.at(0), pattern: "//fake.ably.io"))
    }

    // RSC15b1
    func test__057__RestClient__Host_Fallback__Fallback_behavior__should_NOT_be_applied_when_ClientOptions_port_has_been_set() {
        let test = Test()
        let options = ClientOptions(token: "xxxx")
        options.tls = false
        options.port = 999
        let client = HttpClient(options: options)
        let internalLog = InternalLog(clientOptions: options)
        let mockHTTP = MockHTTP(logger: internalLog)
        testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: internalLog)
        client.internal.httpExecutor = testHTTPExecutor
        mockHTTP.setNetworkState(network: .hostUnreachable)
        let channel = client.channels.get(test.uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "") { error in
                expect(error?.message).to(contain("hostname could not be found"))
                done()
            }
        }

        let requests = testHTTPExecutor.requests
        XCTAssertEqual(requests.count, 1)
        let capturedURLs = requests.map { $0.url!.absoluteString }
        expect(capturedURLs.at(0)).to(beginWith("http://rest.ably.io:999"))
    }

    // RSC15b1
    func test__058__RestClient__Host_Fallback__Fallback_behavior__should_NOT_be_applied_when_ClientOptions_tlsPort_has_been_set() {
        let test = Test()
        let options = ClientOptions(key: "xxxx:xxxx")
        options.tlsPort = 999
        let client = HttpClient(options: options)
        let internalLog = InternalLog(clientOptions: options)
        let mockHTTP = MockHTTP(logger: internalLog)
        testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: internalLog)
        client.internal.httpExecutor = testHTTPExecutor
        mockHTTP.setNetworkState(network: .hostUnreachable)
        let channel = client.channels.get(test.uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "") { error in
                expect(error?.message).to(contain("hostname could not be found"))
                done()
            }
        }

        let requests = testHTTPExecutor.requests
        XCTAssertEqual(requests.count, 1)
        let capturedURLs = requests.map { $0.url!.absoluteString }
        expect(capturedURLs.at(0)).to(beginWith("https://rest.ably.io:999"))
    }

    // RSC15b2
    func test__059__RestClient__Host_Fallback__Fallback_behavior__should_be_applied_when_ClientOptions_fallbackHosts_is_provided() {
        let test = Test()
        let options = ClientOptions(key: "xxxx:xxxx")
        options.fallbackHosts = ["a.cocoa.ably", "b.cocoa.ably"]
        let client = HttpClient(options: options)
        let internalLog = InternalLog(clientOptions: options)
        let mockHTTP = MockHTTP(logger: internalLog)
        testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: internalLog)
        client.internal.httpExecutor = testHTTPExecutor
        mockHTTP.setNetworkState(network: .hostUnreachable)
        let channel = client.channels.get(test.uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "") { error in
                expect(error?.message).to(contain("hostname could not be found"))
                done()
            }
        }

        XCTAssertEqual(testHTTPExecutor.requests.count, 3)
        let capturedURLs = testHTTPExecutor.requests.map { $0.url!.absoluteString }
        XCTAssertTrue(NSRegularExpression.match(capturedURLs.at(0), pattern: "//rest.ably.io"))
        XCTAssertTrue(NSRegularExpression.match(capturedURLs.at(1), pattern: "//[a-b].cocoa.ably"))
        XCTAssertTrue(NSRegularExpression.match(capturedURLs.at(2), pattern: "//[a-b].cocoa.ably"))
    }

    // RSC15b3, RSC15g4
    // RSC15k
    func test__045__RestClient__Host_Fallback__failing_HTTP_requests_with_custom_endpoint_should_result_in_an_error_immediately() {
        let test = Test()
        let options = ClientOptions(key: "xxxx:xxxx")
        options.restHost = "fake.ably.io"
        let client = HttpClient(options: options)
        let internalLog = InternalLog(clientOptions: options)
        let mockHTTP = MockHTTP(logger: internalLog)
        testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: internalLog)
        client.internal.httpExecutor = testHTTPExecutor
        mockHTTP.setNetworkState(network: .hostUnreachable)
        let channel = client.channels.get(test.uniqueChannelName())
        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "message") { error in
                expect(error?.message).to(contain("hostname could not be found"))
                done()
            }
        }
        XCTAssertEqual(testHTTPExecutor.requests.count, 1)
    }

    // RSC15g

    // RSC15g1
    func test__061__RestClient__Host_Fallback__fallback_hosts_list_and_priorities__should_use_ClientOptions_fallbackHosts_when_list_is_provided() {
        let test = Test()
        let options = ClientOptions(key: "xxxx:xxxx")
        options.fallbackHosts = ["f.ably-realtime.com"]
        let client = HttpClient(options: options)
        let internalLog = InternalLog(clientOptions: options)
        let mockHTTP = MockHTTP(logger: internalLog)
        testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: internalLog)
        client.internal.httpExecutor = testHTTPExecutor
        mockHTTP.setNetworkState(network: .hostUnreachable)
        let channel = client.channels.get(test.uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "") { error in
                expect(error?.message).to(contain("hostname could not be found"))
                done()
            }
        }

        XCTAssertEqual(testHTTPExecutor.requests.count, 2)
        let capturedURLs = testHTTPExecutor.requests.compactMap { $0.url?.absoluteString }
        XCTAssertTrue(NSRegularExpression.match(capturedURLs.at(0), pattern: "//rest.ably.io"))
        XCTAssertTrue(NSRegularExpression.match(capturedURLs.at(1), pattern: "//f.ably-realtime.com"))
    }

    // RSC15g2
    func test__062__RestClient__Host_Fallback__fallback_hosts_list_and_priorities__should_use_environment_fallback_hosts_when_ClientOptions_environment_is_set_to_a_value_other_than__production__and_ClientOptions_fallbackHosts_is_not_set() throws {
        let test = Test()
        let options = ClientOptions(key: "xxxx:xxxx")
        options.environment = "test"
        let client = HttpClient(options: options)
        let internalLog = InternalLog(clientOptions: options)
        let mockHTTP = MockHTTP(logger: internalLog)
        testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: internalLog)
        client.internal.httpExecutor = testHTTPExecutor
        mockHTTP.setNetworkState(network: .hostUnreachable, resetAfter: 2)
        mockHTTP.setSuccessResponse(
            data: try JSONSerialization.data(withJSONObject: ["serials": []], options: []),
            contentType: "application/json"
        )
        let channel = client.channels.get(test.uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "") { error in
                XCTAssertNil(error)
                done()
            }
        }

        XCTAssertEqual(testHTTPExecutor.requests.count, 3)
        let capturedURLs = testHTTPExecutor.requests.compactMap { $0.url?.absoluteString }
        XCTAssertTrue(NSRegularExpression.match(capturedURLs.at(0), pattern: "//test-rest.ably.io"))
        XCTAssertTrue(NSRegularExpression.match(capturedURLs.at(1), pattern: "//test-[a-e]-fallback.ably-realtime.com"))
        XCTAssertTrue(NSRegularExpression.match(capturedURLs.at(1), pattern: "//test-[a-e]-fallback.ably-realtime.com"))
    }

    // RSC15g2
    func test__063__RestClient__Host_Fallback__fallback_hosts_list_and_priorities__should_NOT_use_environment_fallback_hosts_when_ClientOptions_environment_is_set_to__production_() {
        let test = Test()
        let options = ClientOptions(key: "xxxx:xxxx")
        options.environment = "production"
        let client = HttpClient(options: options)
        let internalLog = InternalLog(clientOptions: options)
        let mockHTTP = MockHTTP(logger: internalLog)
        testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: internalLog)
        client.internal.httpExecutor = testHTTPExecutor
        mockHTTP.setNetworkState(network: .hostUnreachable)
        let channel = client.channels.get(test.uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "") { error in
                expect(error?.message).to(contain("hostname could not be found"))
                done()
            }
        }

        XCTAssertEqual(testHTTPExecutor.requests.count, 4)
        let capturedURLs = testHTTPExecutor.requests.compactMap { $0.url?.absoluteString }
        XCTAssertTrue(NSRegularExpression.match(capturedURLs.at(0), pattern: "//rest.ably.io"))
        XCTAssertTrue(NSRegularExpression.match(capturedURLs.at(1), pattern: "//[a-e].ably-realtime.com"))
        XCTAssertTrue(NSRegularExpression.match(capturedURLs.at(2), pattern: "//[a-e].ably-realtime.com"))
        XCTAssertTrue(NSRegularExpression.match(capturedURLs.at(3), pattern: "//[a-e].ably-realtime.com"))
    }

    // RSC15g3
    func test__064__RestClient__Host_Fallback__fallback_hosts_list_and_priorities__should_use_default_fallback_hosts_when_both_ClientOptions_fallbackHosts_and_ClientOptions_environment_are_not_set() {
        let test = Test()
        let options = ClientOptions(key: "xxxx:xxxx")
        options.environment = ""
        let client = HttpClient(options: options)
        let internalLog = InternalLog(clientOptions: options)
        let mockHTTP = MockHTTP(logger: internalLog)
        testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: internalLog)
        client.internal.httpExecutor = testHTTPExecutor
        mockHTTP.setNetworkState(network: .hostUnreachable)
        let channel = client.channels.get(test.uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "") { error in
                expect(error?.message).to(contain("hostname could not be found"))
                done()
            }
        }

        XCTAssertEqual(testHTTPExecutor.requests.count, 4)
        let capturedURLs = testHTTPExecutor.requests.compactMap { $0.url?.absoluteString }
        XCTAssertTrue(NSRegularExpression.match(capturedURLs.at(0), pattern: "//rest.ably.io"))
        XCTAssertTrue(NSRegularExpression.match(capturedURLs.at(1), pattern: "//[a-e].ably-realtime.com"))
        XCTAssertTrue(NSRegularExpression.match(capturedURLs.at(2), pattern: "//[a-e].ably-realtime.com"))
        XCTAssertTrue(NSRegularExpression.match(capturedURLs.at(3), pattern: "//[a-e].ably-realtime.com"))
    }

    // RSC15g4
    // RSC15g1
    func test__047__RestClient__Host_Fallback__won_t_apply_fallback_hosts_if_ClientOptions_fallbackHosts_array_is_empty() {
        let test = Test()
        let options = ClientOptions(key: "xxxx:xxxx")
        options.fallbackHosts = [] // to test TO3k6
        let client = HttpClient(options: options)
        let internalLog = InternalLog(clientOptions: options)
        let mockHTTP = MockHTTP(logger: internalLog)
        testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: internalLog)
        client.internal.httpExecutor = testHTTPExecutor
        mockHTTP.setNetworkState(network: .hostUnreachable)
        let channel = client.channels.get(test.uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "nil") { _ in
                done()
            }
        }

        XCTAssertEqual(testHTTPExecutor.requests.count, 1)
        let capturedURLs = testHTTPExecutor.requests.map { $0.url!.absoluteString }
        XCTAssertTrue(NSRegularExpression.match(capturedURLs.at(0), pattern: "//rest.ably.io"))
    }

    // RSC15g3
    func test__048__RestClient__Host_Fallback__won_t_apply_custom_fallback_hosts_if_ClientOptions_fallbackHosts_and_ClientOptions_environment_are_not_set__use_defaults_instead() {
        let test = Test()
        let options = ClientOptions(key: "xxxx:xxxx")
        options.fallbackHosts = nil
        let client = HttpClient(options: options)
        let internalLog = InternalLog(clientOptions: options)
        let mockHTTP = MockHTTP(logger: internalLog)
        testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: internalLog)
        client.internal.httpExecutor = testHTTPExecutor
        mockHTTP.setNetworkState(network: .hostUnreachable, resetAfter: 1)
        let channel = client.channels.get(test.uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "nil") { _ in
                done()
            }
        }

        XCTAssertEqual(testHTTPExecutor.requests.count, 2)
        if testHTTPExecutor.requests.count < 2 {
            return
        }

        let capturedURLs = testHTTPExecutor.requests.map { $0.url!.absoluteString }
        XCTAssertTrue(NSRegularExpression.match(capturedURLs.at(1), pattern: "//[a-e].ably-realtime.com"))
    }

    // RSC15e
    func test__049__RestClient__Host_Fallback__every_new_HTTP_request_is_first_attempted_to_the_default_primary_host_rest_ably_io() {
        let test = Test()
        let options = ClientOptions(key: "xxxx:xxxx")
        options.httpMaxRetryCount = 1
        options.fallbackRetryTimeout = 1 // RSC15j exception
        let client = HttpClient(options: options)
        let internalLog = InternalLog(clientOptions: options)
        let mockHTTP = MockHTTP(logger: internalLog)
        testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: internalLog)
        client.internal.httpExecutor = testHTTPExecutor
        mockHTTP.setNetworkState(network: .hostUnreachable, resetAfter: 1)
        let channel = client.channels.get(test.uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "nil") { _ in
                done()
            }
        }

        waitUntil(timeout: testTimeout) { done in
            // RSC15j exception
            delay(1.1) {
                channel.publish(nil, data: "nil") { _ in
                    done()
                }
            }
        }

        XCTAssertEqual(testHTTPExecutor.requests.count, 3)
        XCTAssertTrue(NSRegularExpression.match(testHTTPExecutor.requests.at(0)?.url?.absoluteString, pattern: "//\(Default.restHost())"))
        XCTAssertTrue(NSRegularExpression.match(testHTTPExecutor.requests.at(1)?.url?.absoluteString, pattern: "//[a-e].ably-realtime.com"))
        XCTAssertTrue(NSRegularExpression.match(testHTTPExecutor.requests.at(2)?.url?.absoluteString, pattern: "//\(Default.restHost())"))
    }

    // RSC15a

    // RSC15h
    func test__065__RestClient__Host_Fallback__retry_hosts_in_random_order__default_fallback_hosts_should_match__a_e__ably_realtime_com() {
        let defaultFallbackHosts = Default.fallbackHosts()
        defaultFallbackHosts.forEach { host in
            expect(host).to(match("[a-e].ably-realtime.com"))
        }
        XCTAssertEqual(defaultFallbackHosts.count, 5)
    }

    // RSC15i
    func test__066__RestClient__Host_Fallback__retry_hosts_in_random_order__environment_fallback_hosts_have_the_format__environment___a_e__fallback_ably_realtime_com() {
        let environmentFallbackHosts = Default.fallbackHosts(withEnvironment: "sandbox")
        environmentFallbackHosts.forEach { host in
            expect(host).to(match("sandbox-[a-e]-fallback.ably-realtime.com"))
        }
        XCTAssertEqual(environmentFallbackHosts.count, 5)
    }

    func test__067__RestClient__Host_Fallback__retry_hosts_in_random_order__until_httpMaxRetryCount_has_been_reached() {
        let test = Test()
        let options = ClientOptions(key: "xxxx:xxxx")
        options.testOptions.shuffleArray = shuffleArrayInExpectedHostOrder
        let client = HttpClient(options: options)
        options.httpMaxRetryCount = 3
        let internalLog = InternalLog(clientOptions: options)
        let mockHTTP = MockHTTP(logger: internalLog)
        testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: internalLog)
        client.internal.httpExecutor = testHTTPExecutor
        mockHTTP.setNetworkState(network: .hostUnreachable)
        let channel = client.channels.get(test.uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "nil") { _ in
                done()
            }
        }

        XCTAssertEqual(testHTTPExecutor.requests.count, Int(1 + options.httpMaxRetryCount))

        let extractHostname = { (request: URLRequest) in
            NSRegularExpression.extract(request.url!.absoluteString, pattern: "[a-e].ably-realtime.com")
        }
        let resultFallbackHosts = testHTTPExecutor.requests.compactMap(extractHostname)
        let expectedFallbackHosts = Array(expectedHostOrder.map { Default.fallbackHosts()[$0] }[0 ..< Int(options.httpMaxRetryCount)])

        XCTAssertEqual(resultFallbackHosts, expectedFallbackHosts)
    }

    func test__068__RestClient__Host_Fallback__retry_hosts_in_random_order__use_custom_fallback_hosts_if_set() {
        let test = Test()
        let options = ClientOptions(key: "xxxx:xxxx")
        options.httpMaxRetryCount = 10
        let customFallbackHosts = ["j.ably-realtime.com",
                                   "i.ably-realtime.com",
                                   "h.ably-realtime.com",
                                   "g.ably-realtime.com",
                                   "f.ably-realtime.com"]
        options.fallbackHosts = customFallbackHosts
        options.testOptions.shuffleArray = shuffleArrayInExpectedHostOrder
        let client = HttpClient(options: options)
        let internalLog = InternalLog(clientOptions: options)
        let mockHTTP = MockHTTP(logger: internalLog)
        testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: internalLog)
        client.internal.httpExecutor = testHTTPExecutor
        mockHTTP.setNetworkState(network: .hostUnreachable)
        let channel = client.channels.get(test.uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "nil") { _ in
                done()
            }
        }

        XCTAssertEqual(testHTTPExecutor.requests.count, customFallbackHosts.count + 1)

        let extractHostname = { (request: URLRequest) in
            NSRegularExpression.extract(request.url!.absoluteString, pattern: "[f-j].ably-realtime.com")
        }
        let resultFallbackHosts = testHTTPExecutor.requests.compactMap(extractHostname)
        let expectedFallbackHosts = expectedHostOrder.map { customFallbackHosts[$0] }

        XCTAssertEqual(resultFallbackHosts, expectedFallbackHosts)
    }

    func test__069__RestClient__Host_Fallback__retry_hosts_in_random_order__until_all_fallback_hosts_have_been_tried() {
        let test = Test()
        let options = ClientOptions(key: "xxxx:xxxx")
        options.httpMaxRetryCount = 10
        options.testOptions.shuffleArray = shuffleArrayInExpectedHostOrder
        let client = HttpClient(options: options)
        let internalLog = InternalLog(clientOptions: options)
        let mockHTTP = MockHTTP(logger: internalLog)
        testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: internalLog)
        client.internal.httpExecutor = testHTTPExecutor
        mockHTTP.setNetworkState(network: .hostUnreachable)
        let channel = client.channels.get(test.uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "nil") { _ in
                done()
            }
        }

        XCTAssertEqual(testHTTPExecutor.requests.count, Default.fallbackHosts().count + 1)

        let extractHostname = { (request: URLRequest) in
            NSRegularExpression.extract(request.url!.absoluteString, pattern: "[a-e].ably-realtime.com")
        }
        let resultFallbackHosts = testHTTPExecutor.requests.compactMap(extractHostname)
        let expectedFallbackHosts = expectedHostOrder.map { Default.fallbackHosts()[$0] }

        XCTAssertEqual(resultFallbackHosts, expectedFallbackHosts)
    }

    func test__070__RestClient__Host_Fallback__retry_hosts_in_random_order__until_httpMaxRetryCount_has_been_reached__if_custom_fallback_hosts_are_provided_in_ClientOptions_fallbackHosts__then_they_will_be_used_instead() {
        let test = Test()
        let options = ClientOptions(key: "xxxx:xxxx")
        options.httpMaxRetryCount = 4
        options.fallbackHosts = _fallbackHosts
        options.testOptions.shuffleArray = shuffleArrayInExpectedHostOrder

        let client = HttpClient(options: options)
        let internalLog = InternalLog(clientOptions: options)
        let mockHTTP = MockHTTP(logger: internalLog)
        testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: internalLog)
        client.internal.httpExecutor = testHTTPExecutor
        mockHTTP.setNetworkState(network: .hostUnreachable)
        let channel = client.channels.get(test.uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "nil") { _ in
                done()
            }
        }

        XCTAssertEqual(testHTTPExecutor.requests.count, Int(1 + options.httpMaxRetryCount))
        XCTAssertTrue((testHTTPExecutor.requests.count) < (_fallbackHosts.count + 1))

        let extractHostname = { (request: URLRequest) in
            NSRegularExpression.extract(request.url!.absoluteString, pattern: "[f-j].ably-realtime.com")
        }
        let resultFallbackHosts = testHTTPExecutor.requests.compactMap(extractHostname)
        let expectedFallbackHosts = Array(expectedHostOrder.map { _fallbackHosts[$0] }[0 ..< Int(options.httpMaxRetryCount)])

        XCTAssertEqual(resultFallbackHosts, expectedFallbackHosts)
    }

    func test__071__RestClient__Host_Fallback__retry_hosts_in_random_order__until_all_fallback_hosts_have_been_tried__if_custom_fallback_hosts_are_provided_in_ClientOptions_fallbackHosts__then_they_will_be_used_instead() {
        let test = Test()
        let options = ClientOptions(key: "xxxx:xxxx")
        options.httpMaxRetryCount = 10
        options.fallbackHosts = _fallbackHosts
        options.testOptions.shuffleArray = shuffleArrayInExpectedHostOrder

        let client = HttpClient(options: options)
        let internalLog = InternalLog(clientOptions: options)
        let mockHTTP = MockHTTP(logger: internalLog)
        testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: internalLog)
        client.internal.httpExecutor = testHTTPExecutor
        mockHTTP.setNetworkState(network: .hostUnreachable)
        let channel = client.channels.get(test.uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "nil") { _ in
                done()
            }
        }

        XCTAssertEqual(testHTTPExecutor.requests.count, Default.fallbackHosts().count + 1)

        let extractHostname = { (request: URLRequest) in
            NSRegularExpression.extract(request.url!.absoluteString, pattern: "[f-j].ably-realtime.com")
        }

        let resultFallbackHosts = testHTTPExecutor.requests.compactMap(extractHostname)
        let expectedFallbackHosts = expectedHostOrder.map { _fallbackHosts[$0] }

        XCTAssertEqual(resultFallbackHosts, expectedFallbackHosts)
    }

    func test__072__RestClient__Host_Fallback__retry_hosts_in_random_order__all_fallback_requests_headers_should_contain__Host__header_with_fallback_host_address() {
        let test = Test()
        let options = ClientOptions(key: "xxxx:xxxx")
        options.httpMaxRetryCount = 10
        options.fallbackHosts = _fallbackHosts

        let client = HttpClient(options: options)
        let internalLog = InternalLog(clientOptions: options)
        let mockHTTP = MockHTTP(logger: internalLog)
        testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: internalLog)
        client.internal.httpExecutor = testHTTPExecutor
        mockHTTP.setNetworkState(network: .hostUnreachable)
        let channel = client.channels.get(test.uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "nil") { _ in
                done()
            }
        }

        XCTAssertEqual(testHTTPExecutor.requests.count, Default.fallbackHosts().count + 1)

        let fallbackRequests = testHTTPExecutor.requests.filter {
            NSRegularExpression.match($0.url!.absoluteString, pattern: "[f-j].ably-realtime.com")
        }

        let fallbackRequestsWithHostHeader = fallbackRequests.filter {
            $0.allHTTPHeaderFields!["Host"] == $0.url?.host
        }

        XCTAssertEqual(fallbackRequests.count, fallbackRequestsWithHostHeader.count)
    }

    func test__073__RestClient__Host_Fallback__retry_hosts_in_random_order__if_an_empty_array_of_fallback_hosts_is_provided__then_fallback_host_functionality_is_disabled() {
        let test = Test()
        let options = ClientOptions(key: "xxxx:xxxx")
        options.httpMaxRetryCount = 5
        options.fallbackHosts = []

        let client = HttpClient(options: options)
        let internalLog = InternalLog(clientOptions: options)
        let mockHTTP = MockHTTP(logger: internalLog)
        testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: internalLog)
        client.internal.httpExecutor = testHTTPExecutor
        mockHTTP.setNetworkState(network: .hostUnreachable)
        let channel = client.channels.get(test.uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "nil") { _ in
                done()
            }
        }

        XCTAssertEqual(testHTTPExecutor.requests.count, 1)
        XCTAssertTrue(NSRegularExpression.match(testHTTPExecutor.requests[0].url!.absoluteString, pattern: "//rest.ably.io"))
    }

    // RSC15d

    func test__074__RestClient__Host_Fallback__should_use_an_alternative_host_when___hostUnreachable() {
        let test = Test()
        testUsesAlternativeHost(.hostUnreachable, channelName: test.uniqueChannelName())
    }

    func test__075__RestClient__Host_Fallback__should_use_an_alternative_host_when___requestTimeout_timeout__0_1_() {
        let test = Test()
        testUsesAlternativeHost(.requestTimeout(timeout: 0.1), channelName: test.uniqueChannelName())
    }

    func test__076__RestClient__Host_Fallback__should_use_an_alternative_host_when___hostInternalError_code__501_() {
        let test = Test()
        testUsesAlternativeHost(.hostInternalError(code: 501), channelName: test.uniqueChannelName())
    }

    // RSC15d
    func test__050__RestClient__Host_Fallback__should_not_use_an_alternative_host_when_the_client_receives_an_bad_request() {
        let test = Test()
        let options = ClientOptions(key: "xxxx:xxxx")
        let client = HttpClient(options: options)
        let internalLog = InternalLog(clientOptions: options)
        let mockHTTP = MockHTTP(logger: internalLog)
        testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: internalLog)
        client.internal.httpExecutor = testHTTPExecutor
        mockHTTP.setNetworkState(network: .host400BadRequest, resetAfter: 1)
        let channel = client.channels.get(test.uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "nil") { _ in
                done()
            }
        }

        XCTAssertEqual(testHTTPExecutor.requests.count, 1)
        XCTAssertTrue(NSRegularExpression.match(testHTTPExecutor.requests[0].url!.absoluteString, pattern: "//rest.ably.io"))
    }

    // RSC15f

    func test__077__RestClient__Host_Fallback__should_store_successful_fallback_host_as_default_host___hostUnreachable() {
        let test = Test()
        testStoresSuccessfulFallbackHostAsDefaultHost(.hostUnreachable, channelName: test.uniqueChannelName())
    }

    func test__078__RestClient__Host_Fallback__should_store_successful_fallback_host_as_default_host___requestTimeout_timeout__0_1_() {
        let test = Test()
        testStoresSuccessfulFallbackHostAsDefaultHost(.requestTimeout(timeout: 0.1), channelName: test.uniqueChannelName())
    }

    func test__079__RestClient__Host_Fallback__should_store_successful_fallback_host_as_default_host___hostInternalError_code__501_() {
        let test = Test()
        testStoresSuccessfulFallbackHostAsDefaultHost(.hostInternalError(code: 501), channelName: test.uniqueChannelName())
    }

    func test__080__RestClient__Host_Fallback__should_store_successful_fallback_host_as_default_host__should_restore_default_primary_host_after_fallbackRetryTimeout_expired___hostUnreachable() {
        let test = Test()
        testRestoresDefaultPrimaryHostAfterTimeoutExpires(.hostUnreachable, channelName: test.uniqueChannelName())
    }

    func test__081__RestClient__Host_Fallback__should_store_successful_fallback_host_as_default_host__should_restore_default_primary_host_after_fallbackRetryTimeout_expired___requestTimeout_timeout__0_1_() {
        let test = Test()
        testRestoresDefaultPrimaryHostAfterTimeoutExpires(.requestTimeout(timeout: 0.1), channelName: test.uniqueChannelName())
    }

    func test__082__RestClient__Host_Fallback__should_store_successful_fallback_host_as_default_host__should_restore_default_primary_host_after_fallbackRetryTimeout_expired___hostInternalError_code__501_() {
        let test = Test()
        testRestoresDefaultPrimaryHostAfterTimeoutExpires(.hostInternalError(code: 501), channelName: test.uniqueChannelName())
    }

    func test__083__RestClient__Host_Fallback__should_store_successful_fallback_host_as_default_host__should_use_another_fallback_host_if_previous_fallback_request_failed_and_store_it_as_default_if_current_fallback_request_succseeded___hostUnreachable() {
        let test = Test()
        testUsesAnotherFallbackHost(.hostUnreachable, channelName: test.uniqueChannelName())
    }

    func test__084__RestClient__Host_Fallback__should_store_successful_fallback_host_as_default_host__should_use_another_fallback_host_if_previous_fallback_request_failed_and_store_it_as_default_if_current_fallback_request_succseeded___requestTimeout_timeout__0_1_() {
        let test = Test()
        testUsesAnotherFallbackHost(.requestTimeout(timeout: 0.1), channelName: test.uniqueChannelName())
    }

    func test__085__RestClient__Host_Fallback__should_store_successful_fallback_host_as_default_host__should_use_another_fallback_host_if_previous_fallback_request_failed_and_store_it_as_default_if_current_fallback_request_succseeded___hostInternalError_code__501_() {
        let test = Test()
        testUsesAnotherFallbackHost(.hostInternalError(code: 501), channelName: test.uniqueChannelName())
    }

    // RSC8a
    func test__008__RestClient__should_use_MsgPack_binary_protocol() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        XCTAssertTrue(options.useBinaryProtocol)

        let rest = HttpClient(options: options)
        testHTTPExecutor = TestProxyHTTPExecutor(logger: .init(clientOptions: options))
        rest.internal.httpExecutor = testHTTPExecutor
        waitUntil(timeout: testTimeout) { done in
            rest.channels.get(test.uniqueChannelName(prefix: "rest")).publish(nil, data: "message") { _ in
                done()
            }
        }

        let request = try XCTUnwrap(testHTTPExecutor.requests.first, "No request found")

        switch extractBodyAsMsgPack(request) {
        case let .failure(error):
            fail(error)
        default: break
        }

        let realtime = AblyTests.newRealtime(options).client
        defer { realtime.close() }
        waitUntil(timeout: testTimeout) { done in
            realtime.channels.get(test.uniqueChannelName(prefix: "realtime")).publish(nil, data: "message") { _ in
                done()
            }
        }

        let transport = realtime.internal.transport as! TestProxyTransport
        let jsonArray: [[String: Any]] = try transport.rawDataSent.map { try JSONUtility.jsonObject(data: AblyTests.msgpackToData($0)) }
        let messageJson = jsonArray.filter { item in (item["action"] as! Int) == 15 }.last!
        let messages = messageJson["messages"] as! [[String: Any]]
        XCTAssertEqual(messages[0]["data"] as? String, "message")
    }

    // RSC8b
    func test__009__RestClient__should_use_JSON_text_protocol() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.useBinaryProtocol = false

        let rest = HttpClient(options: options)
        testHTTPExecutor = TestProxyHTTPExecutor(logger: .init(clientOptions: options))
        rest.internal.httpExecutor = testHTTPExecutor
        waitUntil(timeout: testTimeout) { done in
            rest.channels.get(test.uniqueChannelName(prefix: "rest")).publish(nil, data: "message") { _ in
                done()
            }
        }

        let request = try XCTUnwrap(testHTTPExecutor.requests.first, "No request found")

        switch extractBodyAsJSON(request) {
        case let .failure(error):
            fail(error)
        default: break
        }

        let realtime = AblyTests.newRealtime(options).client
        defer { realtime.close() }
        waitUntil(timeout: testTimeout) { done in
            realtime.channels.get(test.uniqueChannelName(prefix: "realtime")).publish(nil, data: "message") { _ in
                done()
            }
        }

        let transport = realtime.internal.transport as! TestProxyTransport
        let object = try JSONSerialization.jsonObject(with: transport.rawDataSent.first!, options: JSONSerialization.ReadingOptions(rawValue: 0))
        XCTAssertTrue(JSONSerialization.isValidJSONObject(object))
    }

    // RSC7a
    func test__010__RestClient__X_Ably_Version_must_be_included_in_all_REST_requests() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = HttpClient(options: options)
        testHTTPExecutor = TestProxyHTTPExecutor(logger: .init(clientOptions: options))
        client.internal.httpExecutor = testHTTPExecutor
        waitUntil(timeout: testTimeout) { done in
            client.channels.get(test.uniqueChannelName()).publish(nil, data: "message") { error in
                XCTAssertNil(error)
                guard let headerAblyVersion = testHTTPExecutor.requests.first?.allHTTPHeaderFields?["X-Ably-Version"] else {
                    fail("X-Ably-Version header not found"); done()
                    return
                }

                // This test should not directly validate version against Default.version(), as
                // ultimately the version header has been derived from that value.
                XCTAssertEqual(headerAblyVersion, "6")

                done()
            }
        }
    }

    // RSC7b (Deprecated in favor of RCS7d)

    // RSC7d
    func test__011__RestClient__The_Agent_library_identifier_is_composed_of_a_series_of_key__value__entries_joined_by_spaces() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = HttpClient(options: options)
        testHTTPExecutor = TestProxyHTTPExecutor(logger: .init(clientOptions: options))
        client.internal.httpExecutor = testHTTPExecutor
        let channel = client.channels.get(test.uniqueChannelName())
        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "message") { error in
                XCTAssertNil(error)
                let headerAgent = testHTTPExecutor.requests.first!.allHTTPHeaderFields?["Ably-Agent"]
                let ablyAgent = ClientInformation.agentIdentifier(withAdditionalAgents: options.agents)
                XCTAssertEqual(headerAgent, ablyAgent)
                XCTAssertTrue(headerAgent!.hasPrefix("ably-pubsub-cocoa/2.0.0"))
                done()
            }
        }
    }

    // https://github.com/ably/ably-cocoa/issues/117
    func test__012__RestClient__should_indicate_an_error_if_there_is_no_way_to_renew_the_token() throws {
        let test = Test()
        let options = try AblyTests.clientOptions(for: test)
        let tokenTtl = 0.1
        options.token = try getTestToken(for: test, ttl: tokenTtl)
        let client = HttpClient(options: options)
        waitUntil(timeout: testTimeout) { done in
            delay(tokenTtl + AblyTests.tokenExpiryTolerance) {
                client.channels.get(test.uniqueChannelName()).publish(nil, data: "message") { error in
                    guard let error = error else {
                        fail("Error is empty"); done()
                        return
                    }
                    XCTAssertEqual(error.code, Int(ARTState.requestTokenFailed.rawValue))
                    done()
                }
            }
        }
    }

    // https://github.com/ably/ably-cocoa/issues/577
    func test__013__RestClient__background_behaviour() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        waitUntil(timeout: testTimeout) { done in
            URLSession.shared.dataTask(with: URL(string: "https://ably.io")!) { _, _, _ in
                let rest = HttpClient(options: options)
                rest.channels.get(test.uniqueChannelName()).history { _, _ in
                    done()
                }
            }.resume()
        }
    }

    // https://github.com/ably/ably-cocoa/issues/589
    func test__014__RestClient__client_should_handle_error_messages_in_plaintext_and_HTML_format() {
        let request = URLRequest(url: URL(string: "https://www.example.com")!)
        waitUntil(timeout: testTimeout) { done in
            let rest = HttpClient(key: "xxxx:xxxx")
            rest.internal.execute(request, wrapperSDKAgents:nil, completion: { response, _, error in
                guard let contentType = response?.allHeaderFields["Content-Type"] as? String else {
                    fail("Response should have a Content-Type"); done(); return
                }
                expect(contentType).to(contain("text/html"))
                guard let error = error as? ErrorInfo else {
                    fail("Error is nil"); done(); return
                }
                XCTAssertEqual(error.statusCode, 200)
                XCTAssertTrue(error.message.contains("<title>Example Domain</title>"))
                done()
            })
        }
    }

    // RSC19

    // RSC19a

    func test__086__RestClient__request__method_signature_and_arguments__should_add_query_parameters() throws {
        let rest = HttpClient(key: "xxxx:xxxx")
        let mockHttpExecutor = MockHTTPExecutor()
        rest.internal.httpExecutor = mockHttpExecutor
        let params = ["foo": "1"]

        waitUntil(timeout: testTimeout) { done in
            do {
                try rest.request("patch", path: "feature", params: params, body: nil, headers: nil) { paginatedResult, error in
                    XCTAssertNil(error)
                    XCTAssertNotNil(paginatedResult)
                    done()
                }
            } catch {
                fail(error.localizedDescription)
                done()
            }
        }

        let request = try XCTUnwrap(mockHttpExecutor.requests.first, "No request found")
        let url = try XCTUnwrap(request.url, "No request url found")
        let acceptHeaderValue = try XCTUnwrap(request.allHTTPHeaderFields?["Accept"], "Accept HTTP Header is missing")

        XCTAssertEqual(request.httpMethod!.uppercased(), "PATCH")
        XCTAssertEqual(url.absoluteString, "https://rest.ably.io:443/feature?foo=1")
        XCTAssertEqual(acceptHeaderValue, "application/x-msgpack,application/json")
    }

    func test__087__RestClient__request__method_signature_and_arguments__should_add_a_HTTP_body() throws {
        let rest = HttpClient(key: "xxxx:xxxx")
        let mockHttpExecutor = MockHTTPExecutor()
        rest.internal.httpExecutor = mockHttpExecutor
        let bodyDict = ["blockchain": true]

        waitUntil(timeout: testTimeout) { done in
            do {
                try rest.request("post", path: "feature", params: nil, body: bodyDict, headers: nil) { paginatedResult, error in
                    XCTAssertNil(error)
                    XCTAssertNotNil(paginatedResult)
                    done()
                }
            } catch {
                fail(error.localizedDescription)
                done()
            }
        }

        let request = try XCTUnwrap(mockHttpExecutor.requests.first, "No requests found")
        let rawBody = try XCTUnwrap(request.httpBody, "should have a body")
        let decodedBody = try XCTUnwrap(try rest.internal.defaultEncoder.decode(rawBody), "Decode request body failed")
        let body = try XCTUnwrap(decodedBody as? NSDictionary, "Request body is invalid")

        XCTAssertTrue(try XCTUnwrap(body.value(forKey: "blockchain") as? Bool))
    }

    func test__088__RestClient__request__method_signature_and_arguments__should_add_a_HTTP_header() throws {
        let rest = HttpClient(key: "xxxx:xxxx")
        let mockHttpExecutor = MockHTTPExecutor()
        rest.internal.httpExecutor = mockHttpExecutor
        let headers = ["X-foo": "ok"]

        waitUntil(timeout: testTimeout) { done in
            do {
                try rest.request("get", path: "feature", params: nil, body: nil, headers: headers) { paginatedResult, error in
                    XCTAssertNil(error)
                    XCTAssertNotNil(paginatedResult)
                    done()
                }
            } catch {
                fail(error.localizedDescription)
                done()
            }
        }

        let request = try XCTUnwrap(mockHttpExecutor.requests.first, "No requests found")

        let authorization = request.allHTTPHeaderFields?["X-foo"]
        XCTAssertEqual(authorization, "ok")
    }

    func test__089__RestClient__request__method_signature_and_arguments__should_error_if_method_is_invalid() {
        let rest = HttpClient(key: "xxxx:xxxx")
        let mockHTTPExecutor = MockHTTPExecutor()
        rest.internal.httpExecutor = mockHTTPExecutor

        do {
            try rest.request("A", path: "feature", params: nil, body: nil, headers: nil) { _, _ in
                fail("Completion closure should not be called")
            }
        } catch let error as NSError {
            XCTAssertEqual(error.code, CustomRequestError.invalidMethod.rawValue)
            expect(error.localizedDescription).to(contain("Method isn't valid"))
        }

        do {
            try rest.request("", path: "feature", params: nil, body: nil, headers: nil) { _, _ in
                fail("Completion closure should not be called")
            }
        } catch let error as NSError {
            XCTAssertEqual(error.code, CustomRequestError.invalidMethod.rawValue)
            expect(error.localizedDescription).to(contain("Method isn't valid"))
        }
    }

    func test__090__RestClient__request__method_signature_and_arguments__should_error_if_path_is_invalid() {
        let rest = HttpClient(key: "xxxx:xxxx")
        let mockHTTPExecutor = MockHTTPExecutor()
        rest.internal.httpExecutor = mockHTTPExecutor

        do {
            try rest.request("get", path: "", params: nil, body: nil, headers: nil) { _, _ in
                fail("Completion closure should not be called")
            }
        } catch let error as NSError {
            XCTAssertEqual(error.code, CustomRequestError.invalidPath.rawValue)
            expect(error.localizedDescription).to(contain("Path cannot be empty"))
        }
    }

    func test__091__RestClient__request__method_signature_and_arguments__should_error_if_body_is_not_a_Dictionary_or_an_Array() {
        let rest = HttpClient(key: "xxxx:xxxx")
        let mockHttpExecutor = MockHTTPExecutor()
        rest.internal.httpExecutor = mockHttpExecutor

        do {
            try rest.request("get", path: "feature", params: nil, body: mockHttpExecutor, headers: nil) { _, _ in
                fail("Completion closure should not be called")
            }
        } catch let error as NSError {
            XCTAssertEqual(error.code, CustomRequestError.invalidBody.rawValue)
            expect(error.localizedDescription).to(contain("should be a Dictionary or an Array"))
        }
    }

    func test__092__RestClient__request__method_signature_and_arguments__should_do_a_request_and_receive_a_valid_response() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let rest = HttpClient(options: options)
        let channel = rest.channels.get(test.uniqueChannelName())
        waitUntil(timeout: testTimeout) { done in
            channel.publish("a", data: nil) { error in
                XCTAssertNil(error)
                done()
            }
        }

        let proxyHTTPExecutor = TestProxyHTTPExecutor(logger: .init(clientOptions: options))
        rest.internal.httpExecutor = proxyHTTPExecutor

        var capturedHttpPaginatedResponse: HTTPPaginatedResponse?
        waitUntil(timeout: testTimeout) { done in
            do {
                try rest.request("get", path: "/channels/\(channel.name)", params: nil, body: nil, headers: nil) { paginatedResponse, error in
                    XCTAssertNil(error)
                    guard let paginatedResponse = paginatedResponse else {
                        fail("PaginatedResult is empty"); done(); return
                    }
                    XCTAssertEqual(paginatedResponse.items.count, 1)
                    guard let channelDetailsDict = paginatedResponse.items.first else {
                        fail("PaginatedResult first element is missing"); done(); return
                    }
                    XCTAssertEqual(channelDetailsDict.value(forKey: "channelId") as? String, channel.name)
                    XCTAssertEqual(paginatedResponse.hasNext, false)
                    XCTAssertEqual(paginatedResponse.isLast, true)
                    XCTAssertEqual(paginatedResponse.statusCode, 200)
                    XCTAssertEqual(paginatedResponse.success, true)
                    XCTAssertEqual(paginatedResponse.errorCode, 0)
                    XCTAssertNil(paginatedResponse.errorMessage)
                    expect(paginatedResponse.headers).toNot(beEmpty())
                    capturedHttpPaginatedResponse = paginatedResponse
                    done()
                }
            } catch {
                fail(error.localizedDescription)
                done()
            }
        }
        let httpPaginatedResponse = try XCTUnwrap(capturedHttpPaginatedResponse, "waitUntil timed out before httpPaginatedResponse was set")

        let response = try XCTUnwrap(proxyHTTPExecutor.responses.first, "No responses found")

        XCTAssertEqual(response.statusCode, httpPaginatedResponse.statusCode)
        XCTAssertEqual(response.allHeaderFields as NSDictionary, httpPaginatedResponse.headers)
    }

    func test__093__RestClient__request__method_signature_and_arguments__should_handle_response_failures() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let rest = HttpClient(options: options)
        let channel = rest.channels.get(test.uniqueChannelName())
        waitUntil(timeout: testTimeout) { done in
            channel.publish("a", data: nil) { error in
                XCTAssertNil(error)
                done()
            }
        }

        let proxyHTTPExecutor = TestProxyHTTPExecutor(logger: .init(clientOptions: options))
        rest.internal.httpExecutor = proxyHTTPExecutor

        waitUntil(timeout: testTimeout) { done in
            do {
                try rest.request("get", path: "feature", params: nil, body: nil, headers: nil) { paginatedResponse, error in
                    XCTAssertNil(error)
                    guard let paginatedResponse = paginatedResponse else {
                        fail("PaginatedResult is empty"); done(); return
                    }
                    XCTAssertEqual(paginatedResponse.items.count, 0)
                    XCTAssertEqual(paginatedResponse.hasNext, false)
                    XCTAssertEqual(paginatedResponse.isLast, true)
                    XCTAssertEqual(paginatedResponse.statusCode, 404)
                    XCTAssertEqual(paginatedResponse.success, false)
                    XCTAssertEqual(paginatedResponse.errorCode, ErrorCode.notFound.intValue)
                    expect(paginatedResponse.errorMessage).to(contain("Could not find path"))
                    expect(paginatedResponse.headers).toNot(beEmpty())
                    XCTAssertEqual(paginatedResponse.headers["X-Ably-Errorcode"] as? String, "\(ErrorCode.notFound.intValue)")
                    done()
                }
            } catch {
                fail(error.localizedDescription)
                done()
            }
        }

        let response = try XCTUnwrap(proxyHTTPExecutor.responses.first, "No responses found")

        XCTAssertEqual(response.statusCode, 404)
        XCTAssertEqual(response.value(forHTTPHeaderField: "X-Ably-Errorcode"), "\(ErrorCode.notFound.intValue)")
    }

    // RSA4e
    func test__094__RestClient__if_in_the_course_of_a_REST_request_an_attempt_to_authenticate_using_authUrl_fails_due_to_a_timeout__the_request_should_result_in_an_error_with_code_40170__statusCode_401__and_a_suitable_error_message() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let token = try getTestToken(for: test)
        options.httpRequestTimeout = 3 // short timeout to make it fail faster
        options.authUrl = URL(string: "http://10.255.255.1")!
        options.authParams = [URLQueryItem]()
        options.authParams?.append(URLQueryItem(name: "type", value: "text"))
        options.authParams?.append(URLQueryItem(name: "body", value: token))

        let client = HttpClient(options: options)
        waitUntil(timeout: testTimeout) { done in
            let channel = client.channels.get(test.uniqueChannelName())
            channel.publish("test", data: "test-data") { error in
                guard let error = error else {
                    fail("Error should not be empty")
                    done()
                    return
                }
                XCTAssertEqual(error.statusCode, 401)
                XCTAssertEqual(error.code, ErrorCode.errorFromClientTokenCallback.intValue)
                done()
            }
        }
    }

    // RSC7c

    func test__095__RestClient__request_IDs__should_add__request_id__query_parameter() throws {
        let test = Test()
        let options = ClientOptions(key: "xxxx:xxxx")
        options.addRequestIds = true

        let restA = HttpClient(options: options)
        let mockHttpExecutor = MockHTTPExecutor()
        restA.internal.httpExecutor = mockHttpExecutor
        mockHttpExecutor.setSuccessResponse(
            data: try JSONSerialization.data(withJSONObject: ["serials": []], options: []),
            contentType: "application/json"
        )
        waitUntil(timeout: testTimeout) { done in
            restA.channels.get(test.uniqueChannelName()).publish(nil, data: "something") { error in
                XCTAssertNil(error)
                guard let url = mockHttpExecutor.requests.first?.url else {
                    fail("No requests found")
                    return
                }
                expect(url.query).to(contain("request_id"))
                done()
            }
        }

        mockHttpExecutor.reset()

        options.addRequestIds = false
        let restB = HttpClient(options: options)
        restB.internal.httpExecutor = mockHttpExecutor
        waitUntil(timeout: testTimeout) { done in
            restB.channels.get(test.uniqueChannelName()).publish(nil, data: "something") { error in
                XCTAssertNil(error)
                XCTAssertEqual(mockHttpExecutor.requests.count, 1)
                guard let url = mockHttpExecutor.requests.first?.url else {
                    fail("No requests found")
                    return
                }
                XCTAssertNil(url.query)
                done()
            }
        }
    }

    func test__096__RestClient__request_IDs__should_remain_the_same_if_a_request_is_retried_to_a_fallback_host() {
        let test = Test()
        let options = ClientOptions(key: "xxxx:xxxx")
        options.httpMaxRetryCount = 5
        options.addRequestIds = true
        options.logLevel = .debug

        let client = HttpClient(options: options)
        let internalLog = InternalLog(clientOptions: options)
        let mockHTTP = MockHTTP(logger: internalLog)
        testHTTPExecutor = TestProxyHTTPExecutor(http: mockHTTP, logger: internalLog)
        client.internal.httpExecutor = testHTTPExecutor
        mockHTTP.setNetworkState(network: .hostUnreachable)

        var fallbackRequests: [URLRequest] = []
        testHTTPExecutor.setListenerAfterRequest { request in
            if NSRegularExpression.match(request.url!.absoluteString, pattern: "//[a-e].ably-realtime.com") {
                fallbackRequests += [request]
            }
        }

        var requestId: String = ""
        let channel = client.channels.get(test.uniqueChannelName())
        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "something") { error in
                guard let error = error else {
                    fail("Expecting an error"); done(); return
                }
                guard let firstRequestId = extractURLQueryValue(testHTTPExecutor.requests.first?.url, key: "request_id") else {
                    fail("First request attempt doesn't have the 'request_id'."); return
                }
                requestId = firstRequestId
                expect(error.message).to(contain(requestId))
                done()
            }
        }

        expect(fallbackRequests).toNot(beEmpty())
        expect(fallbackRequests).to(allPass { extractURLQueryValue($0.url, key: "request_id") == requestId })
    }

    func test__097__RestClient__request_IDs__ErrorInfo_should_have__requestId__property() {
        let test = Test()
        let options = ClientOptions(key: "xxxx:xxxx")
        options.addRequestIds = true

        let rest = HttpClient(options: options)
        let mockHttpExecutor = MockHTTPExecutor()
        mockHttpExecutor.simulateIncomingErrorOnNextRequest(NSError(domain: "ably-test", code: ErrorCode.invalidMessageDataOrEncoding.intValue, userInfo: ["Message": "Ably test message"]))
        rest.internal.httpExecutor = mockHttpExecutor

        waitUntil(timeout: testTimeout) { done in
            rest.channels.get(test.uniqueChannelName()).publish(nil, data: "something") { error in
                XCTAssertNotNil(error)
                XCTAssertNotNil(error?.requestId)
                done()
            }
        }
    }
}
