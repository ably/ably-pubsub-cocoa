import AblyPubSubDevice
import AblyPubSubDevice.Private
import Nimble
import XCTest
import AblyTestingObjC

private func testOptionsGiveDefaultAuthMethod(_ caseSetter: (ARTAuthOptions) -> Void) {
    let options = ARTClientOptions()
    caseSetter(options)

    let client = ARTHttpClient(options: options)

    XCTAssertEqual(client.auth.internal.method, ARTAuthMethod.token)
}

// Cases:
//  - useTokenAuth is specified and thus a key is not provided
//  - authCallback and authUrl are both specified
private func testStopsClientWithOptions(caseSetter: (ARTClientOptions) -> Void) {
    let options = ARTClientOptions()
    caseSetter(options)

    let exception = tryInObjC {
        _ = ARTHttpClient(options: options)
    }
    XCTAssertNotNil(exception)
}

private let currentClientId = "client_string"

private let json = "{" +
    "    \"token\": \"xxxxxx.yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy\"," +
    "    \"issued\": 1479087321934," +
    "    \"expires\": 1479087363934," +
    "    \"capability\": \"{\\\"test\\\":[\\\"publish\\\"]}\"," +
    "    \"clientId\": \"myClientId\"" +
    "}"

private func check(_ details: ARTTokenDetails) {
    XCTAssertEqual(details.token, "xxxxxx.yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy")
    XCTAssertEqual(details.issued, Date(timeIntervalSince1970: 1_479_087_321.934))
    XCTAssertEqual(details.expires, Date(timeIntervalSince1970: 1_479_087_363.934))
    XCTAssertEqual(details.capability, "{\"test\":[\"publish\"]}")
    XCTAssertEqual(details.clientId, "myClientId")
}

private let channelName = "test_JWT"
private let messageName = "message_JWT"
private func createAuthUrlTestsOptions(for test: Test) throws -> ARTClientOptions {
    let options = try AblyTests.clientOptions(for: test)
    options.authUrl = URL(string: echoServerAddress)!
    return options
}

private func createJsonEncoder() -> ARTJsonLikeEncoder {
    let encoder = ARTJsonLikeEncoder(delegate: ARTJsonEncoder(), timeProvider: SystemTimeProvider())
    encoder.delegate = ARTJsonEncoder()
    return encoder
}

private func jwtContentTypeTestsSetupDependencies(for test: Test) throws -> ARTHttpClient {
    let options = try AblyTests.clientOptions(for: test)
    let keys = try getKeys(for: test)
    options.authUrl = URL(string: echoServerAddress)!
    options.authParams = [URLQueryItem]()
    options.authParams?.append(URLQueryItem(name: "keyName", value: keys["keyName"]))
    options.authParams?.append(URLQueryItem(name: "keySecret", value: keys["keySecret"]))
    options.authParams?.append(URLQueryItem(name: "returnType", value: "jwt"))
    return ARTHttpClient(options: options)
}

class AuthTests: XCTestCase {
    enum ExpectedTokenParams {
        static let clientId = "client_from_params"
        static let ttl = 1.0
        static let capability = "{\"cansubscribe:*\":[\"subscribe\"]}"
    }

    // RSA1
    func test__003__Basic__should_work_over_HTTPS_only() throws {
        let test = Test()
        let clientOptions = try AblyTests.commonAppSetup(for: test)
        clientOptions.tls = false

        XCTAssertNotNil(tryInObjC {
            _ = ARTHttpClient(options: clientOptions)
        })
    }

    // RSA11
    func test__004__Basic__should_send_the_API_key_in_the_Authorization_header() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = ARTHttpClient(options: options)
        let testHTTPExecutor = TestProxyHTTPExecutor(logger: .init(clientOptions: options))
        client.internal.httpExecutor = testHTTPExecutor

        waitUntil(timeout: testTimeout) { done in
            client.channels.get(test.uniqueChannelName()).publish(nil, data: "message") { _ in
                done()
            }
        }

        let key64 = "\(client.internal.options.key!)"
            .data(using: .utf8)!
            .base64EncodedString(options: Data.Base64EncodingOptions(rawValue: 0))

        let expectedAuthorization = "Basic \(key64)"

        let request = try XCTUnwrap(testHTTPExecutor.requests.first, "No request found")

        let authorization = request.allHTTPHeaderFields?["Authorization"]

        XCTAssertEqual(authorization, expectedAuthorization)
    }

    // RSA2
    func test__005__Basic__should_be_default_when_an_API_key_is_set() {
        let client = ARTHttpClient(options: ARTClientOptions(key: "fake:key"))

        XCTAssertEqual(client.auth.internal.method, ARTAuthMethod.basic)
    }

    // RSA3

    // RSA3a
    func test__010__Token__token_auth__should_work_over_HTTP() throws {
        let test = Test()
        let options = try AblyTests.clientOptions(for: test, requestToken: true)
        options.tls = false
        let clientHTTP = ARTHttpClient(options: options)
        let testHTTPExecutor = TestProxyHTTPExecutor(logger: .init(clientOptions: options))
        clientHTTP.internal.httpExecutor = testHTTPExecutor

        waitUntil(timeout: testTimeout) { done in
            clientHTTP.channels.get(test.uniqueChannelName()).publish(nil, data: "message") { _ in
                done()
            }
        }

        let url = try XCTUnwrap(testHTTPExecutor.requests.first?.url, "No request url found")

        XCTAssertEqual(url.scheme, "http", "No HTTP support")
    }

    func test__011__Token__token_auth__should_work_over_HTTPS() throws {
        let test = Test()
        let options = try AblyTests.clientOptions(for: test, requestToken: true)
        options.tls = true
        let clientHTTPS = ARTHttpClient(options: options)
        let testHTTPExecutor = TestProxyHTTPExecutor(logger: .init(clientOptions: options))
        clientHTTPS.internal.httpExecutor = testHTTPExecutor

        waitUntil(timeout: testTimeout) { done in
            clientHTTPS.channels.get(test.uniqueChannelName()).publish(nil, data: "message") { _ in
                done()
            }
        }

        let url = try XCTUnwrap(testHTTPExecutor.requests.first?.url, "No request url found")

        XCTAssertEqual(url.scheme, "https", "No HTTPS support")
    }

    // RSA3b

    func test__012__Token__token_auth__for_REST_requests__should_send_the_token_in_the_Authorization_header() throws {
        let test = Test()
        let options = try AblyTests.clientOptions(for: test)
        options.token = try getTestToken(for: test)

        let client = ARTHttpClient(options: options)
        let testHTTPExecutor = TestProxyHTTPExecutor(logger: .init(clientOptions: options))
        client.internal.httpExecutor = testHTTPExecutor

        waitUntil(timeout: testTimeout) { done in
            client.channels.get(test.uniqueChannelName()).publish(nil, data: "message") { _ in
                done()
            }
        }

        let currentToken = try XCTUnwrap(client.internal.options.token, "No access token")

        let expectedAuthorization = "Bearer \(currentToken)"

        let request = try XCTUnwrap(testHTTPExecutor.requests.first, "No request found")

        let authorization = request.allHTTPHeaderFields?["Authorization"]

        XCTAssertEqual(authorization, expectedAuthorization)
    }

    // RSA3c

    func test__013__Token__token_auth__for_Realtime_connections__should_send_the_token_in_the_querystring_as_a_param_named_accessToken() throws {
        let test = Test()
        let options = try AblyTests.clientOptions(for: test)
        options.token = try getTestToken(for: test)
        options.autoConnect = false
        options.testOptions.transportFactory = TestProxyTransportFactory()

        let client = ARTRealtimeClient(options: options)
        defer { client.dispose(); client.close() }
        client.connect()

        if let transport = client.internal.transport as? TestProxyTransport, let query = transport.lastUrl?.query {
            expect(query).to(haveParam("accessToken", withValue: client.auth.tokenDetails?.token ?? ""))
        } else {
            XCTFail("MockTransport is not working")
        }
    }

    // RSA4

    func test__014__Token__authentication_method__should_be_default_auth_method_when_options__useTokenAuth_is_set() {
        testOptionsGiveDefaultAuthMethod { $0.useTokenAuth = true; $0.key = "fake:key" }
    }

    func test__015__Token__authentication_method__should_be_default_auth_method_when_options__authUrl_is_set() {
        testOptionsGiveDefaultAuthMethod { $0.authUrl = URL(string: "http://test.com") }
    }

    func test__016__Token__authentication_method__should_be_default_auth_method_when_options__authCallback_is_set() {
        testOptionsGiveDefaultAuthMethod { $0.authCallback = { _, _ in } }
    }

    func test__017__Token__authentication_method__should_be_default_auth_method_when_options__tokenDetails_is_set() {
        testOptionsGiveDefaultAuthMethod { $0.tokenDetails = ARTTokenDetails(token: "token") }
    }

    func test__018__Token__authentication_method__should_be_default_auth_method_when_options__token_is_set() {
        testOptionsGiveDefaultAuthMethod { $0.token = "token" }
    }

    func test__019__Token__authentication_method__should_be_default_auth_method_when_options__key_is_set() {
        testOptionsGiveDefaultAuthMethod { $0.tokenDetails = ARTTokenDetails(token: "token"); $0.key = "fake:key" }
    }

    // RSA4a
    func test__020__Token__authentication_method__should_indicate_an_error_and_not_retry_the_request_when_the_server_responds_with_a_token_error_and_there_is_no_way_to_renew_the_token() throws {
        let test = Test()
        let options = try AblyTests.clientOptions(for: test)
        options.token = try getTestToken(for: test)

        let rest = ARTHttpClient(options: options)
        // No means to renew the token is provided
        XCTAssertNil(rest.internal.options.key)
        XCTAssertNil(rest.internal.options.authCallback)
        XCTAssertNil(rest.internal.options.authUrl)
        let testHTTPExecutor = TestProxyHTTPExecutor(logger: .init(clientOptions: options))
        rest.internal.httpExecutor = testHTTPExecutor

        let channel = rest.channels.get(test.uniqueChannelName())

        testHTTPExecutor.simulateIncomingServerErrorOnNextRequest(ARTErrorCode.tokenRevoked.intValue, description: "token revoked")
        waitUntil(timeout: testTimeout) { done in
            channel.publish("message", data: nil) { error in
                guard let error = error else {
                    fail("Error is nil"); done(); return
                }
                XCTAssertEqual(UInt(error.code), ARTState.requestTokenFailed.rawValue)
                done()
            }
        }
    }

    // RSA4a
    func test__021__Token__authentication_method__should_transition_the_connection_to_the_FAILED_state_when_the_server_responds_with_a_token_error_and_there_is_no_way_to_renew_the_token() throws {
        let test = Test()
        let options = try AblyTests.clientOptions(for: test)
        let tokenTtl = 0.1
        options.tokenDetails = try getTestTokenDetails(for: test, ttl: tokenTtl)
        options.autoConnect = false
        options.testOptions.transportFactory = TestProxyTransportFactory()

        // Token will expire, expecting 40142
        waitUntil(timeout: testTimeout) { done in
            delay(tokenTtl + AblyTests.tokenExpiryTolerance) { done() }
        }

        let realtime = ARTRealtimeClient(options: options)
        defer { realtime.dispose(); realtime.close() }
        // No means to renew the token is provided
        XCTAssertNil(realtime.internal.options.key)
        XCTAssertNil(realtime.internal.options.authCallback)
        XCTAssertNil(realtime.internal.options.authUrl)

        let channel = realtime.channels.get(test.uniqueChannelName())

        waitUntil(timeout: testTimeout.multiplied(by: 2)) { done in
            realtime.connect()
            channel.publish("message", data: nil) { error in
                guard let error = error else {
                    fail("Error is nil"); done(); return
                }
                XCTAssertEqual(error.code, ARTErrorCode.tokenExpired.intValue)
                XCTAssertEqual(realtime.connection.state, ARTRealtimeConnectionState.failed)
                done()
            }
        }
    }

    // RSA4b
    func test__022__Token__authentication_method__on_token_error__reissues_token_and_retries_REST_requests() throws {
        let test = Test()
        var authCallbackCalled = 0

        let options = try AblyTests.commonAppSetup(for: test)
        options.authCallback = { _, callback in
            authCallbackCalled += 1
            getTestTokenDetails(for: test) { token, err in
                callback(token, err)
            }
        }

        let rest = ARTHttpClient(options: options)
        let testHTTPExecutor = TestProxyHTTPExecutor(logger: .init(clientOptions: options))
        rest.internal.httpExecutor = testHTTPExecutor

        let channel = rest.channels.get(test.uniqueChannelName())

        testHTTPExecutor.simulateIncomingServerErrorOnNextRequest(ARTErrorCode.tokenRevoked.intValue, description: "token revoked")

        waitUntil(timeout: testTimeout) { done in
            channel.publish("message", data: nil) { error in
                XCTAssertNil(error)
                done()
            }
        }

        // First request and a second attempt
        XCTAssertEqual(testHTTPExecutor.requests.count, 2)

        // First token issue, and then reissue on token error.
        XCTAssertEqual(authCallbackCalled, 2)
    }

    // RSA4b
    func test__023__Token__authentication_method__in_REST__if_the_token_creation_failed_or_the_subsequent_request_with_the_new_token_failed_due_to_a_token_error__then_the_request_should_result_in_an_error() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.useTokenAuth = true

        let rest = ARTHttpClient(options: options)
        let testHTTPExecutor = TestProxyHTTPExecutor(logger: .init(clientOptions: options))
        rest.internal.httpExecutor = testHTTPExecutor

        let channel = rest.channels.get(test.uniqueChannelName())

        testHTTPExecutor.setListenerAfterRequest { _ in
            testHTTPExecutor.simulateIncomingServerErrorOnNextRequest(ARTErrorCode.tokenRevoked.intValue, description: "token revoked")
        }

        testHTTPExecutor.simulateIncomingServerErrorOnNextRequest(ARTErrorCode.tokenRevoked.intValue, description: "token revoked")
        waitUntil(timeout: testTimeout) { done in
            channel.publish("message", data: nil) { error in
                guard let error = error else {
                    fail("Error is nil"); done(); return
                }
                XCTAssertEqual(error.code, ARTErrorCode.tokenRevoked.intValue)
                done()
            }
        }

        // First request and a second attempt
        XCTAssertEqual(testHTTPExecutor.requests.count, 2)
    }

    // RSA4b
    func test__024__Token__authentication_method__in_Realtime__if_the_token_creation_failed_then_the_connection_should_move_to_the_DISCONNECTED_state_and_reports_the_error() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.authCallback = { _, completion in
            completion(nil, NSError(domain: NSURLErrorDomain, code: -1003, userInfo: [NSLocalizedDescriptionKey: "A server with the specified hostname could not be found."]))
        }
        options.autoConnect = false

        let realtime = ARTRealtimeClient(options: options)
        defer { realtime.dispose(); realtime.close() }

        waitUntil(timeout: testTimeout) { done in
            realtime.connection.once(.failed) { _ in
                fail("Should not reach Failed state"); done()
            }
            realtime.connection.once(.disconnected) { stateChange in
                guard let errorInfo = stateChange.reason else {
                    fail("ErrorInfo is nil"); done(); return
                }
                expect(errorInfo.message).to(contain("server with the specified hostname could not be found"))
                done()
            }
            realtime.connect()
        }
    }

    // RSA4b
    func test__025__Token__authentication_method__in_Realtime__if_the_connection_fails_due_to_a_terminal_token_error__then_the_connection_should_move_to_the_FAILED_state_and_reports_the_error() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.authCallback = { _, completion in
            getTestToken(for: test) { result in
                switch result {
                case .success(let token):
                    let invalidToken = String(token.reversed())
                    completion(invalidToken as ARTTokenDetailsCompatible, nil)
                case .failure(let error):
                    completion(nil, error)
                }
            }
        }
        options.autoConnect = false

        let realtime = ARTRealtimeClient(options: options)
        defer { realtime.dispose(); realtime.close() }

        waitUntil(timeout: testTimeout) { done in
            realtime.connection.once(.failed) { stateChange in
                guard let errorInfo = stateChange.reason else {
                    fail("ErrorInfo is nil"); done(); return
                }
                expect(errorInfo.code).to(equal(ARTErrorCode.invalidCredentials.intValue))
                done()
            }
            realtime.connection.once(.disconnected) { _ in
                fail("Should not reach Disconnected state"); done()
            }
            realtime.connect()
        }
    }

    // RSA4b1

    func test__028__Token__authentication_method__local_token_validity_check__should_be_done_if_queryTime_is_true_and_local_time_is_in_sync_with_server() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let testKey = options.key!

        let tokenDetails = try getTestTokenDetails(for: test, key: testKey, ttl: 5.0, queryTime: true)

        options.queryTime = true
        options.tokenDetails = tokenDetails
        options.key = nil

        let rest = ARTHttpClient(options: options)
        let proxyHTTPExecutor = TestProxyHTTPExecutor(logger: .init(clientOptions: options))

        // Sync server time offset
        let authOptions = ARTAuthOptions(key: testKey)
        authOptions.queryTime = true
        waitUntil(timeout: testTimeout) { done in
            rest.auth.createTokenRequest(nil, options: authOptions, callback: { tokenRequest, error in
                XCTAssertNil(error)
                XCTAssertNotNil(tokenRequest)
                done()
            })
        }

        // Let the token expire
        waitUntil(timeout: testTimeout) { done in
            delay(5.0) {
                done()
            }
        }

        XCTAssertNotNil(rest.auth.internal.timeOffset)

        rest.internal.httpExecutor = proxyHTTPExecutor
        waitUntil(timeout: testTimeout) { done in
            rest.channels.get(test.uniqueChannelName()).history { _, error in
                guard let error = error else {
                    fail("Error is nil"); done(); return
                }
                XCTAssertEqual(error.code, Int(ARTState.requestTokenFailed.rawValue)) // no means to renew the token is provided
                XCTAssertEqual(proxyHTTPExecutor.requests.count, 0)
                done()
            }
        }

        XCTAssertNotNil(rest.auth.tokenDetails)
    }

    func test__029__Token__authentication_method__local_token_validity_check__should_NOT_be_done_if_queryTime_is_false_and_local_time_is_NOT_in_sync_with_server() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let testKey = options.key!

        let tokenDetails = try getTestTokenDetails(for: test, key: testKey, ttl: 5.0, queryTime: true)

        options.queryTime = false
        options.tokenDetails = tokenDetails
        options.key = nil

        let rest = ARTHttpClient(options: options)
        let proxyHTTPExecutor = TestProxyHTTPExecutor(logger: .init(clientOptions: options))
        rest.internal.httpExecutor = proxyHTTPExecutor

        // No server time offset
        rest.auth.internal.clearTimeOffset()

        // Let the token expire
        waitUntil(timeout: testTimeout) { done in
            delay(5.0) {
                done()
            }
        }

        waitUntil(timeout: testTimeout) { done in
            rest.channels.get(test.uniqueChannelName()).history { _, error in
                guard let error = error else {
                    fail("Error is nil"); done(); return
                }
                XCTAssertEqual(error.code, Int(ARTState.requestTokenFailed.rawValue)) // no means to renew the token is provided
                XCTAssertEqual(proxyHTTPExecutor.requests.count, 1)
                XCTAssertEqual(proxyHTTPExecutor.responses.count, 1)
                guard let response = proxyHTTPExecutor.responses.first else {
                    fail("Response is nil"); done(); return
                }
                XCTAssertEqual(response.value(forHTTPHeaderField: "X-Ably-Errorcode"), "\(ARTErrorCode.tokenExpired.intValue)")
                done()
            }
        }
    }

    // RSA4d
    func test__026__Token__authentication_method__if_a_request_by_a_realtime_client_to_an_authUrl_results_in_an_HTTP_403_the_client_library_should_transition_to_the_FAILED_state() throws {
        let test = Test()
        let options = try AblyTests.clientOptions(for: test)
        options.autoConnect = false
        options.authUrl = URL(string: "https://echo.ably.io/respondwith?status=403")!
        let realtime = ARTRealtimeClient(options: options)
        defer { realtime.dispose(); realtime.close() }

        waitUntil(timeout: testTimeout) { done in
            realtime.connection.once(.failed) { stateChange in
                XCTAssertEqual(stateChange.reason?.code, ARTErrorCode.authConfiguredProviderFailure.intValue)
                XCTAssertEqual(stateChange.reason?.statusCode, 403)
                done()
            }
            realtime.connect()
        }
    }

    // RSA4d
    func test__027__Token__authentication_method__if_an_authCallback_results_in_an_HTTP_403_the_client_library_should_transition_to_the_FAILED_state() throws {
        let test = Test()
        let options = try AblyTests.clientOptions(for: test)
        options.autoConnect = false
        var authCallbackHasBeenInvoked = false
        options.authCallback = { _, completion in
            authCallbackHasBeenInvoked = true
            completion(nil, ARTErrorInfo(domain: "io.ably.cocoa", code: ARTErrorCode.forbidden.intValue, userInfo: ["ARTErrorInfoStatusCode": 403]))
        }
        let realtime = ARTRealtimeClient(options: options)
        defer { realtime.dispose(); realtime.close() }

        waitUntil(timeout: testTimeout) { done in
            realtime.connection.once(.failed) { stateChange in
                XCTAssertTrue(authCallbackHasBeenInvoked)
                XCTAssertEqual(stateChange.reason?.code, ARTErrorCode.authConfiguredProviderFailure.intValue)
                XCTAssertEqual(stateChange.reason?.statusCode, 403)
                done()
            }
            realtime.connect()
        }
    }

    // RSA14

    func test__030__Token__options__should_stop_client_when_useTokenAuth_and_no_key_occurs() {
        testStopsClientWithOptions { $0.useTokenAuth = true }
    }

    func test__031__Token__options__should_stop_client_when_authCallback_and_authUrl_occurs() {
        testStopsClientWithOptions { $0.authCallback = { _, _ in /* nothing */ }; $0.authUrl = URL(string: "http://auth.ably.io") }
    }

    // RSA4c

    // RSA4c1 & RSA4c2
    func test__032__Token__options__if_an_attempt_by_the_realtime_client_library_to_authenticate_is_made_using_the_authUrl_or_authCallback__the_request_to_authUrl_fails__if_the_connection_is_CONNECTING__then_the_connection_attempt_should_be_treated_as_unsuccessful() throws {
        let test = Test()
        let options = try AblyTests.clientOptions(for: test)
        options.autoConnect = false
        options.authUrl = URL(string: "http://echo.ably.io")!
        let realtime = ARTRealtimeClient(options: options)
        defer { realtime.dispose(); realtime.close() }

        waitUntil(timeout: testTimeout) { done in
            realtime.connection.once(.disconnected) { stateChange in
                XCTAssertEqual(stateChange.previous, ARTRealtimeConnectionState.connecting)
                guard let errorInfo = stateChange.reason else {
                    fail("ErrorInfo is nil"); done(); return
                }
                XCTAssertEqual(errorInfo.code, ARTErrorCode.authConfiguredProviderFailure.intValue)
                done()
            }
            realtime.connect()
        }

        let errorInfo = try XCTUnwrap(realtime.connection.errorReason, "ErrorInfo is empty")

        XCTAssertEqual(errorInfo.code, ARTErrorCode.authConfiguredProviderFailure.intValue)
        expect(errorInfo.message).to(contain("body param is required"))
    }

    // RSA4c3
    func test__033__Token__options__if_an_attempt_by_the_realtime_client_library_to_authenticate_is_made_using_the_authUrl_or_authCallback__the_request_to_authUrl_fails__if_the_connection_is_CONNECTED__then_the_connection_should_remain_CONNECTED() throws {
        let test = Test()
        let token = try getTestToken(for: test)
        let options = try AblyTests.clientOptions(for: test)
        options.authUrl = URL(string: "http://echo.ably.io")!
        options.authParams = [URLQueryItem]()
        options.authParams?.append(URLQueryItem(name: "type", value: "text"))
        options.authParams?.append(URLQueryItem(name: "body", value: token))

        let realtime = ARTRealtimeClient(options: options)
        defer { realtime.dispose(); realtime.close() }

        waitUntil(timeout: testTimeout) { done in
            realtime.connection.once(.connected) { stateChange in
                XCTAssertNil(stateChange.reason)
                done()
            }
        }

        // Token reauth will fail
        realtime.internal.options.authParams = [URLQueryItem]()

        // Inject AUTH
        let authMessage = ARTProtocolMessage()
        authMessage.action = ARTProtocolMessageAction.auth
        realtime.internal.transport?.receive(authMessage)

        expect(realtime.connection.errorReason).toEventuallyNot(beNil(), timeout: testTimeout)

        let errorInfo = try XCTUnwrap(realtime.connection.errorReason, "ErrorInfo is empty")

        XCTAssertEqual(errorInfo.code, ARTErrorCode.authConfiguredProviderFailure.intValue)
        expect(errorInfo.message).to(contain("body param is required"))

        XCTAssertEqual(realtime.connection.state, ARTRealtimeConnectionState.connected)
    }

    // RSA4c1 & RSA4c2
    func test__034__Token__options__if_an_attempt_by_the_realtime_client_library_to_authenticate_is_made_using_the_authUrl_or_authCallback__the_request_to_authCallback_fails__if_the_connection_is_CONNECTING__then_the_connection_attempt_should_be_treated_as_unsuccessful() throws {
        let test = Test()
        let options = try AblyTests.clientOptions(for: test)
        options.autoConnect = false
        options.authCallback = { _, completion in
            completion(nil, NSError(domain: NSURLErrorDomain, code: -1003, userInfo: [NSLocalizedDescriptionKey: "A server with the specified hostname could not be found."]))
        }
        let realtime = ARTRealtimeClient(options: options)
        defer { realtime.dispose(); realtime.close() }

        waitUntil(timeout: testTimeout) { done in
            realtime.connection.once(.disconnected) { stateChange in
                XCTAssertEqual(stateChange.previous, ARTRealtimeConnectionState.connecting)
                guard let errorInfo = stateChange.reason else {
                    fail("ErrorInfo is nil"); done(); return
                }
                XCTAssertEqual(errorInfo.code, ARTErrorCode.authConfiguredProviderFailure.intValue)
                done()
            }
            realtime.connect()
        }

        expect(realtime.connection.state).toEventually(equal(ARTRealtimeConnectionState.disconnected), timeout: testTimeout)

        let errorInfo = try XCTUnwrap(realtime.connection.errorReason, "ErrorInfo is empty")

        XCTAssertEqual(errorInfo.code, ARTErrorCode.authConfiguredProviderFailure.intValue)
        expect(errorInfo.message).to(contain("hostname could not be found"))
    }

    // RSA4c3
    func test__035__Token__options__if_an_attempt_by_the_realtime_client_library_to_authenticate_is_made_using_the_authUrl_or_authCallback__the_request_to_authCallback_fails__if_the_connection_is_CONNECTED__then_the_connection_should_remain_CONNECTED() throws {
        let test = Test()
        let options = try AblyTests.clientOptions(for: test)
        options.authCallback = { _, completion in
            getTestTokenDetails(for: test, completion: completion)
        }
        let realtime = ARTRealtimeClient(options: options)
        defer { realtime.dispose(); realtime.close() }

        waitUntil(timeout: testTimeout) { done in
            realtime.connection.once(.connected) { stateChange in
                XCTAssertNil(stateChange.reason)
                done()
            }
        }

        // Token should renew and fail
        realtime.internal.options.authCallback = { _, completion in
            completion(nil, NSError(domain: NSURLErrorDomain, code: -1003, userInfo: [NSLocalizedDescriptionKey: "A server with the specified hostname could not be found."]))
        }

        // Inject AUTH
        let authMessage = ARTProtocolMessage()
        authMessage.action = ARTProtocolMessageAction.auth
        realtime.internal.transport?.receive(authMessage)

        expect(realtime.connection.errorReason).toEventuallyNot(beNil(), timeout: testTimeout)

        let errorInfo = try XCTUnwrap(realtime.connection.errorReason, "ErrorInfo is empty")

        XCTAssertEqual(errorInfo.code, ARTErrorCode.authConfiguredProviderFailure.intValue)
        expect(errorInfo.message).to(contain("hostname could not be found"))

        XCTAssertEqual(realtime.connection.state, ARTRealtimeConnectionState.connected)
    }

    // RSA4c1 & RSA4c2
    func test__036__Token__options__if_an_attempt_by_the_realtime_client_library_to_authenticate_is_made_using_the_authUrl_or_authCallback__the_provided_token_is_in_an_invalid_format__if_the_connection_is_CONNECTING__then_the_connection_attempt_should_be_treated_as_unsuccessful() throws {
        let test = Test()
        let options = try AblyTests.clientOptions(for: test)
        options.autoConnect = false
        options.authUrl = URL(string: "http://echo.ably.io")!
        options.authParams = [URLQueryItem]()
        options.authParams?.append(URLQueryItem(name: "type", value: "json"))
        let invalidTokenFormat = "{secret_token:xxx}"
        options.authParams?.append(URLQueryItem(name: "body", value: invalidTokenFormat))

        let realtime = ARTRealtimeClient(options: options)
        defer { realtime.dispose(); realtime.close() }

        waitUntil(timeout: testTimeout) { done in
            realtime.connection.once(.disconnected) { stateChange in
                XCTAssertEqual(stateChange.previous, ARTRealtimeConnectionState.connecting)
                guard let errorInfo = stateChange.reason else {
                    fail("ErrorInfo is nil"); done(); return
                }
                XCTAssertEqual(errorInfo.code, ARTErrorCode.authConfiguredProviderFailure.intValue)
                done()
            }
            realtime.connect()
        }

        let errorInfo = try XCTUnwrap(realtime.connection.errorReason, "ErrorInfo is empty")

        XCTAssertEqual(errorInfo.code, ARTErrorCode.authConfiguredProviderFailure.intValue)
        expect(errorInfo.message).to(contain("content response cannot be used for token request"))

        expect(realtime.connection.state).toEventually(equal(ARTRealtimeConnectionState.disconnected), timeout: testTimeout)
    }

    // RSA4c3
    func test__037__Token__options__if_an_attempt_by_the_realtime_client_library_to_authenticate_is_made_using_the_authUrl_or_authCallback__the_provided_token_is_in_an_invalid_format__if_the_connection_is_CONNECTED__then_the_connection_should_remain_CONNECTED() throws {
        let test = Test()
        let options = try AblyTests.clientOptions(for: test)
        options.authUrl = URL(string: "http://echo.ably.io")!
        options.authParams = [URLQueryItem]()
        options.authParams?.append(URLQueryItem(name: "type", value: "text"))

        let token = try getTestToken(for: test)
        options.authParams?.append(URLQueryItem(name: "body", value: token))

        let realtime = ARTRealtimeClient(options: options)
        defer { realtime.dispose(); realtime.close() }

        waitUntil(timeout: testTimeout) { done in
            realtime.connection.once(.connected) { stateChange in
                XCTAssertNil(stateChange.reason)
                done()
            }
        }

        // Token should renew and fail
        waitUntil(timeout: testTimeout) { done in
            realtime.unwrapAsync { realtime in
                realtime.options.authParams = [URLQueryItem]()
                realtime.options.authParams?.append(URLQueryItem(name: "type", value: "json"))
                let invalidTokenFormat = "{secret_token:xxx}"
                realtime.options.authParams?.append(URLQueryItem(name: "body", value: invalidTokenFormat))
                done()
            }
        }

        realtime.connection.on { stateChange in
            if stateChange.current != .connected {
                fail("Connection should remain connected")
            }
        }

        // Inject AUTH
        let authMessage = ARTProtocolMessage()
        authMessage.action = ARTProtocolMessageAction.auth
        realtime.internal.transport?.receive(authMessage)

        expect(realtime.connection.errorReason).toEventuallyNot(beNil(), timeout: testTimeout)

        let errorInfo = try XCTUnwrap(realtime.connection.errorReason, "ErrorInfo is empty")

        XCTAssertEqual(errorInfo.code, ARTErrorCode.authConfiguredProviderFailure.intValue)
        expect(errorInfo.message).to(contain("content response cannot be used for token request"))

        XCTAssertEqual(realtime.connection.state, ARTRealtimeConnectionState.connected)
    }

    // RSA4c1 & RSA4c2
    func test__038__Token__options__if_an_attempt_by_the_realtime_client_library_to_authenticate_is_made_using_the_authUrl_or_authCallback__the_attempt_times_out_after_realtimeRequestTimeout__if_the_connection_is_CONNECTING__then_the_connection_attempt_should_be_treated_as_unsuccessful() throws {
        let test = Test()
        let options = try AblyTests.clientOptions(for: test)
        options.autoConnect = false
        options.authCallback = { _, _ in
            // Ignore `completion` closure to force a time out
        }
        options.testOptions.realtimeRequestTimeout = 0.5

        let realtime = ARTRealtimeClient(options: options)
        defer { realtime.dispose(); realtime.close() }

        waitUntil(timeout: testTimeout) { done in
            realtime.connection.once(.disconnected) { stateChange in
                guard let errorInfo = stateChange.reason else {
                    fail("ErrorInfo is nil"); done(); return
                }
                XCTAssertEqual(errorInfo.code, ARTErrorCode.authConfiguredProviderFailure.intValue)
                done()
            }
            realtime.connect()
        }

        let errorInfo = try XCTUnwrap(realtime.connection.errorReason, "ErrorInfo is empty")

        XCTAssertEqual(errorInfo.code, ARTErrorCode.authConfiguredProviderFailure.intValue)
        expect(errorInfo.message).to(contain("timed out"))

        expect(realtime.connection.state).toEventually(equal(ARTRealtimeConnectionState.disconnected), timeout: testTimeout)
    }

    // RSA4c3
    func test__039__Token__options__if_an_attempt_by_the_realtime_client_library_to_authenticate_is_made_using_the_authUrl_or_authCallback__the_attempt_times_out_after_realtimeRequestTimeout__if_the_connection_is_CONNECTED__then_the_connection_should_remain_CONNECTED() throws {
        let test = Test()
        let options = try AblyTests.clientOptions(for: test)
        options.autoConnect = false
        options.authCallback = { _, completion in
            getTestTokenDetails(for: test, completion: completion)
        }

        // This needs to be sufficiently long such that we can expect to receive a CONNECTED ProtocolMessage within this duration after starting a connection attempt (there's no "correct" value since it depends on network conditions, but 1.5s seemed to work locally and in CI at time of writing). But we also don't want it to be longer than necessary since that would impact test execution time.
        options.testOptions.realtimeRequestTimeout = 1.5

        let realtime = ARTRealtimeClient(options: options)
        defer { realtime.dispose(); realtime.close() }

        waitUntil(timeout: testTimeout) { done in
            realtime.connection.once(.connected) { stateChange in
                XCTAssertNil(stateChange.reason)
                done()
            }
            realtime.connect()
        }

        // Token should renew and fail
        realtime.internal.options.authCallback = { _, _ in
            // Ignore `completion` closure to force a time out
        }

        // Inject AUTH
        let authMessage = ARTProtocolMessage()
        authMessage.action = ARTProtocolMessageAction.auth
        waitUntil(timeout: testTimeout) { done in
            realtime.unwrapAsync { realtime in
                realtime.transport?.receive(authMessage)
                done()
            }
        }

        expect(realtime.connection.errorReason).toEventuallyNot(beNil(), timeout: testTimeout)

        let errorInfo = try XCTUnwrap(realtime.connection.errorReason, "ErrorInfo is empty")

        XCTAssertEqual(errorInfo.code, ARTErrorCode.authConfiguredProviderFailure.intValue)
        expect(errorInfo.message).to(contain("timed out"))

        XCTAssertEqual(realtime.connection.state, ARTRealtimeConnectionState.connected)
    }

    // RSA15

    // RSA15a

    func test__041__Token__token_auth_and_clientId__should_check_clientId_consistency__on_rest() throws {
        let test = Test()
        let expectedClientId = "client_string"
        let options = try AblyTests.commonAppSetup(for: test)
        options.useTokenAuth = true
        options.clientId = expectedClientId

        let client = ARTHttpClient(options: options)
        let testHTTPExecutor = TestProxyHTTPExecutor(logger: .init(clientOptions: options))
        client.internal.httpExecutor = testHTTPExecutor

        waitUntil(timeout: testTimeout) { done in
            // Token
            client.auth.authorize(nil, options: nil) { tokenDetails, error in
                XCTAssertNil(error)
                XCTAssertEqual(client.auth.internal.method, ARTAuthMethod.token)
                guard let tokenDetails = tokenDetails else {
                    fail("TokenDetails is nil"); done(); return
                }
                XCTAssertEqual(tokenDetails.clientId, expectedClientId)
                done()
            }
        }

        let request = try XCTUnwrap(testHTTPExecutor.requests.first, "No request found")

        switch extractBodyAsMsgPack(request) {
        case let .failure(error):
            XCTFail(error)
        case let .success(httpBody):
            guard let requestedClientId = httpBody.unbox["clientId"] as? String else { XCTFail("No clientId field in HTTPBody"); return }
            XCTAssertEqual(requestedClientId, expectedClientId)
        }
    }

    func test__042__Token__token_auth_and_clientId__should_check_clientId_consistency__on_realtime() throws {
        let test = Test()
        let expectedClientId = "client_string"
        let options = try AblyTests.commonAppSetup(for: test)
        options.clientId = expectedClientId
        options.autoConnect = false
        options.testOptions.transportFactory = TestProxyTransportFactory()

        let client = ARTRealtimeClient(options: options)
        defer { client.dispose(); client.close() }
        client.connect()

        waitUntil(timeout: testTimeout) { done in
            client.connection.on { stateChange in
                let state = stateChange.current
                let error = stateChange.reason
                if state == .connected, error == nil {
                    let currentChannel = client.channels.get(test.uniqueChannelName())
                    currentChannel.subscribe { _ in
                        done()
                    }
                    currentChannel.publish(nil, data: "ping", callback: nil)
                }
            }
        }

        let transport = try XCTUnwrap(client.internal.transport as? TestProxyTransport, "Transport is nil")
        let connectedMessage = try XCTUnwrap(transport.protocolMessagesReceived.filter({ $0.action == .connected }).last, "No CONNECTED protocol action received")

        // CONNECTED ProtocolMessage
        XCTAssertEqual(connectedMessage.connectionDetails!.clientId, expectedClientId)
    }

    func test__043__Token__token_auth_and_clientId__should_check_clientId_consistency__with_wildcard() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.clientId = "*"
        XCTAssertNotNil(tryInObjC {
            _ = ARTHttpClient(options: options)
        })
        XCTAssertNotNil(tryInObjC {
            _ = ARTRealtimeClient(options: options)
        })
    }

    // RSA15b
    func test__040__Token__token_auth_and_clientId__should_permit_to_be_unauthenticated() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.clientId = nil

        let clientBasic = ARTHttpClient(options: options)

        waitUntil(timeout: testTimeout) { done in
            // Basic
            clientBasic.auth.authorize(nil, options: nil) { tokenDetails, error in
                XCTAssertNil(error)
                XCTAssertNil(clientBasic.auth.clientId)
                options.tokenDetails = tokenDetails
                done()
            }
        }

        let clientToken = ARTHttpClient(options: options)

        waitUntil(timeout: testTimeout) { done in
            // Last TokenDetails
            clientToken.auth.authorize(nil, options: nil) { _, error in
                XCTAssertNil(error)
                XCTAssertNil(clientToken.auth.clientId)
                done()
            }
        }
    }

    // RSA15c

    func test__044__Token__token_auth_and_clientId__Incompatible_client__with_Realtime__it_should_change_the_connection_state_to_FAILED_and_emit_an_error() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let wrongTokenDetails = try getTestTokenDetails(for: test, clientId: "wrong")

        options.clientId = "john"
        options.autoConnect = false
        options.authCallback = { _, completion in
            completion(wrongTokenDetails, nil)
        }
        let realtime = ARTRealtimeClient(options: options)
        defer { realtime.close() }

        waitUntil(timeout: testTimeout) { done in
            realtime.connection.once(.failed) { stateChange in
                XCTAssertEqual(stateChange.reason?.code, ARTErrorCode.incompatibleCredentials.intValue)
                done()
            }
            realtime.connect()
        }
    }

    func test__045__Token__token_auth_and_clientId__Incompatible_client__with_Rest__it_should_result_in_an_appropriate_error_response() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.clientId = "john"
        let rest = ARTHttpClient(options: options)

        waitUntil(timeout: testTimeout) { done in
            rest.auth.requestToken(ARTTokenParams(clientId: "wrong"), with: nil) { tokenDetails, error in
                let error = error as! ARTErrorInfo
                XCTAssertEqual(error.code, ARTErrorCode.incompatibleCredentials.intValue)
                XCTAssertNil(tokenDetails)
                done()
            }
        }
    }

    // RSA5
    func test__006__Token__TTL_should_default_to_be_omitted() {
        let tokenParams = ARTTokenParams()
        XCTAssertNil(tokenParams.ttl)
    }

    func test__007__Token__should_URL_query_be_correctly_encoded() throws {
        let tokenParams = ARTTokenParams()
        tokenParams.capability = "{\"*\":[\"*\"]}"

        let dateFormatter = ISO8601DateFormatter()
        tokenParams.timestamp = dateFormatter.date(from: "2016-10-08T22:31:00Z")

        let options = ARTClientOptions()
        options.authUrl = URL(string: "https://ably-test-suite.io")
        let rest = ARTHttpClient(options: options)
        let request = rest.auth.internal.buildRequest(options, with: tokenParams)

        let query = try XCTUnwrap(request.url?.query, "URL is empty")

        expect(query).to(haveParam("capability", withValue: "%7B%22*%22:%5B%22*%22%5D%7D"))
        expect(query).to(haveParam("timestamp", withValue: "1475965860000"))
    }

    // RSA6
    func test__008__Token__should_omit_capability_field_if_it_is_not_specified() throws {
        let test = Test()
        let tokenParams = ARTTokenParams()
        XCTAssertNil(tokenParams.capability)

        let options = try AblyTests.commonAppSetup(for: test)
        let rest = ARTHttpClient(options: options)
        let testHTTPExecutor = TestProxyHTTPExecutor(logger: .init(clientOptions: options))
        rest.internal.httpExecutor = testHTTPExecutor

        waitUntil(timeout: testTimeout) { done in
            // Token
            rest.auth.requestToken(tokenParams, with: options) { tokenDetails, error in
                if let e = error {
                    fail(e.localizedDescription); done(); return
                }
                XCTAssertNil(tokenParams.capability)
                XCTAssertEqual(tokenDetails?.capability, "{\"*\":[\"*\"]}")
                done()
            }
        }

        let request = try XCTUnwrap(testHTTPExecutor.requests.first, "No request found")

        switch extractBodyAsMsgPack(request) {
        case let .failure(error):
            fail(error)
        case let .success(httpBody):
            XCTAssertNil(httpBody.unbox["capability"])
        }
    }

    // RSA6
    func test__009__Token__should_add_capability_field_if_the_user_specifies_it() throws {
        let test = Test()
        let tokenParams = ARTTokenParams()
        tokenParams.capability = "{\"*\":[\"*\"]}"

        let options = try AblyTests.commonAppSetup(for: test)
        let rest = ARTHttpClient(options: options)
        let testHTTPExecutor = TestProxyHTTPExecutor(logger: .init(clientOptions: options))
        rest.internal.httpExecutor = testHTTPExecutor

        waitUntil(timeout: testTimeout) { done in
            // Token
            rest.auth.requestToken(tokenParams, with: options) { tokenDetails, error in
                if let e = error {
                    fail(e.localizedDescription); done(); return
                }
                XCTAssertEqual(tokenDetails?.capability, tokenParams.capability)
                done()
            }
        }

        let request = try XCTUnwrap(testHTTPExecutor.requests.first, "No request found")

        switch extractBodyAsMsgPack(request) {
        case let .failure(error):
            fail(error)
        case let .success(httpBody):
            XCTAssertEqual(httpBody.unbox["capability"] as? String, "{\"*\":[\"*\"]}")
        }
    }

    // RSA7

    // RSA7a1
    func test__046__Token__clientId_and_authenticated_clients__should_not_pass_clientId_with_published_message() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.clientId = "mary"
        let rest = ARTHttpClient(options: options)
        let testHTTPExecutor = TestProxyHTTPExecutor(logger: .init(clientOptions: options))
        rest.internal.httpExecutor = testHTTPExecutor
        let channel = rest.channels.get(test.uniqueChannelName())
        waitUntil(timeout: testTimeout) { done in
            channel.publish("foo", data: nil) { error in
                XCTAssertNil(error)
                done()
            }
        }
        switch extractBodyAsMsgPack(testHTTPExecutor.requests.last) {
        case let .failure(error):
            fail(error)
        case let .success(httpBody):
            let message = httpBody.unbox
            XCTAssertNil(message["clientId"])
            XCTAssertEqual(message["name"] as? String, "foo")
        }
    }

    // RSA7a2
    func test__047__Token__clientId_and_authenticated_clients__should_obtain_a_token_if_clientId_is_assigned() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.clientId = "client_string"

        let client = ARTHttpClient(options: options)
        let testHTTPExecutor = TestProxyHTTPExecutor(logger: .init(clientOptions: options))
        client.internal.httpExecutor = testHTTPExecutor

        waitUntil(timeout: testTimeout) { done in
            client.channels.get(test.uniqueChannelName()).publish(nil, data: "message") { error in
                if let e = error {
                    XCTFail(e.localizedDescription)
                }
                done()
            }
        }

        let authorization = testHTTPExecutor.requests.last?.allHTTPHeaderFields?["Authorization"] ?? ""

        XCTAssertNotEqual(authorization, "")
    }

    // RSA7a3
    func test__048__Token__clientId_and_authenticated_clients__should_convenience_clientId_return_a_string() throws {
        let test = Test()
        let clientOptions = try AblyTests.commonAppSetup(for: test)
        clientOptions.clientId = "String"

        XCTAssertEqual(ARTHttpClient(options: clientOptions).internal.options.clientId, "String")
    }

    // RSA7a4
    func test__049__Token__clientId_and_authenticated_clients__ClientOptions_clientId_takes_precendence_when_a_clientId_value_is_provided_in_both_ClientOptions_clientId_and_ClientOptions_defaultTokenParams() throws {
        let test = Test()
        let options = try AblyTests.clientOptions(for: test)
        options.clientId = "john"
        options.authCallback = { tokenParams, completion in
            XCTAssertEqual(tokenParams.clientId, options.clientId)
            getTestToken(for: test, clientId: tokenParams.clientId) { result in
                switch result {
                case .success(let token):
                    completion(token as ARTTokenDetailsCompatible, nil)
                case .failure(let error):
                    completion(nil, error)
                }
            }
        }
        options.defaultTokenParams = ARTTokenParams(clientId: "tester")
        let client = ARTHttpClient(options: options)
        let channel = client.channels.get(test.uniqueChannelName())

        XCTAssertEqual(client.auth.clientId, "john")
        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "message") { error in
                XCTAssertNil(error)
                channel.history { paginatedResult, _ in
                    guard let result = paginatedResult else {
                        fail("PaginatedResult is empty"); done(); return
                    }
                    guard let message = result.items.first else {
                        fail("First message does not exist"); done(); return
                    }
                    XCTAssertEqual(message.clientId, "john")
                    done()
                }
            }
        }
    }

    // RSA12

    // RSA12a
    func test__051__Token__clientId_and_authenticated_clients__Auth_clientId_attribute_is_null__identity_should_be_anonymous_for_all_operations() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        let realtime = AblyTests.newRealtime(options).client
        defer { realtime.dispose(); realtime.close() }
        XCTAssertNil(realtime.auth.clientId)

        waitUntil(timeout: testTimeout) { done in
            realtime.connection.once(.connected) { stateChange in
                XCTAssertNil(stateChange.reason)
                XCTAssertNil(realtime.auth.clientId)
                done()
            }
            realtime.connect()

            let transport = realtime.internal.transport as! TestProxyTransport
            transport.setBeforeIncomingMessageModifier { message in
                if message.action == .connected {
                    if let details = message.connectionDetails {
                        details.clientId = nil
                    }
                }
                return message
            }
        }
    }

    // RSA12b
    func test__052__Token__clientId_and_authenticated_clients__Auth_clientId_attribute_is_null__identity_may_change_and_become_identified() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.autoConnect = false
        options.token = try getTestToken(for: test, clientId: "tester")
        let realtime = ARTRealtimeClient(options: options)
        defer { realtime.dispose(); realtime.close() }
        XCTAssertNil(realtime.auth.clientId)

        waitUntil(timeout: testTimeout) { done in
            realtime.connection.once(.connecting) { stateChange in
                XCTAssertNil(stateChange.reason)
                XCTAssertNil(realtime.auth.clientId)
            }
            realtime.connection.once(.connected) { stateChange in
                XCTAssertNil(stateChange.reason)
                XCTAssertEqual(realtime.auth.clientId, "tester")
                done()
            }
            realtime.connect()
        }
    }

    // RSA7b

    // RSA7b1
    func test__053__Token__clientId_and_authenticated_clients__auth_clientId_not_null__when_clientId_attribute_is_assigned_on_client_options() throws {
        let test = Test()
        let clientOptions = try AblyTests.commonAppSetup(for: test)
        clientOptions.clientId = "Exist"

        XCTAssertEqual(ARTHttpClient(options: clientOptions).auth.clientId, "Exist")
    }

    // RSA7b2
    func test__054__Token__clientId_and_authenticated_clients__auth_clientId_not_null__when_tokenRequest_or_tokenDetails_has_clientId_not_null_or_wildcard_string() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.clientId = "client_string"
        options.useTokenAuth = true

        let client = ARTHttpClient(options: options)
        let testHTTPExecutor = TestProxyHTTPExecutor(logger: .init(clientOptions: options))
        client.internal.httpExecutor = testHTTPExecutor

        // TokenDetails
        waitUntil(timeout: testTimeout) { done in
            // Token
            client.auth.authorize(nil, options: nil) { _, error in
                XCTAssertNil(error)
                XCTAssertEqual(client.auth.internal.method, ARTAuthMethod.token)
                XCTAssertEqual(client.auth.clientId, options.clientId)
                done()
            }
        }

        // TokenRequest
        switch extractBodyAsMsgPack(testHTTPExecutor.requests.last) {
        case let .failure(error):
            XCTFail(error)
        case let .success(httpBody):
            guard let requestedClientId = httpBody.unbox["clientId"] as? String else { XCTFail("No clientId field in HTTPBody"); return }
            XCTAssertEqual(client.auth.clientId, requestedClientId)
        }
    }

    // RSA7b3
    func test__055__Token__clientId_and_authenticated_clients__auth_clientId_not_null__should_CONNECTED_ProtocolMessages_contain_a_clientId() throws {
        let test = Test()
        let options = try AblyTests.clientOptions(for: test)
        options.token = try getTestToken(for: test, clientId: "john")
        XCTAssertNil(options.clientId)
        options.autoConnect = false
        let realtime = AblyTests.newRealtime(options).client
        defer { realtime.dispose(); realtime.close() }

        waitUntil(timeout: testTimeout) { done in
            realtime.connection.once(.connected) { stateChange in
                XCTAssertNil(stateChange.reason)
                XCTAssertEqual(realtime.auth.clientId, "john")

                let transport = realtime.internal.transport as! TestProxyTransport
                let connectedProtocolMessage = transport.protocolMessagesReceived.filter { $0.action == .connected }[0]
                XCTAssertEqual(connectedProtocolMessage.connectionDetails!.clientId, "john")
                done()
            }
            realtime.connect()
        }
    }

    // RSA7b4
    func test__056__Token__clientId_and_authenticated_clients__auth_clientId_not_null__client_does_not_have_an_identity_when_a_wildcard_string_____is_present() throws {
        let test = Test()
        let options = try AblyTests.clientOptions(for: test)
        options.token = try getTestToken(for: test, clientId: "*")
        let realtime = ARTRealtimeClient(options: options)
        defer { realtime.dispose(); realtime.close() }
        waitUntil(timeout: testTimeout) { done in
            realtime.connection.on(.connected) { _ in
                XCTAssertEqual(realtime.auth.clientId, "*")
                done()
            }
        }
    }

    // RSA7c
    func test__050__Token__clientId_and_authenticated_clients__should_clientId_be_null_or_string() throws {
        let test = Test()
        let clientOptions = try AblyTests.commonAppSetup(for: test)
        clientOptions.clientId = "*"

        XCTAssertNotNil(tryInObjC {
            _ = ARTHttpClient(options: clientOptions)
        })
    }

    // RSA8

    // RSA8e
    func test__062__requestToken__arguments__should_not_merge_with_the_configured_params_and_options_but_instead_replace_all_corresponding_values__even_when__null_() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.clientId = "сlientId"
        let rest = ARTHttpClient(options: options)

        let tokenParams = ARTTokenParams()
        tokenParams.ttl = 2000
        tokenParams.capability = "{\"cansubscribe:*\":[\"subscribe\"]}"

        let precedenceOptions = try AblyTests.commonAppSetup(for: test)

        waitUntil(timeout: testTimeout) { done in
            rest.auth.requestToken(tokenParams, with: precedenceOptions) { tokenDetails, error in
                XCTAssertNil(error)
                XCTAssertNotNil(tokenDetails)
                XCTAssertEqual(tokenDetails!.capability, "{\"cansubscribe:*\":[\"subscribe\"]}")
                XCTAssertNil(tokenDetails!.clientId)
                XCTAssertEqual(tokenDetails!.expires!.timeIntervalSince1970 - tokenDetails!.issued!.timeIntervalSince1970, tokenParams.ttl as? Double)
                done()
            }
        }

        let options2 = try AblyTests.commonAppSetup(for: test)
        options2.clientId = nil
        let rest2 = ARTHttpClient(options: options2)

        let precedenceOptions2 = try AblyTests.commonAppSetup(for: test)
        precedenceOptions2.clientId = nil

        waitUntil(timeout: testTimeout) { done in
            rest2.auth.requestToken(nil, with: precedenceOptions2) { tokenDetails, error in
                XCTAssertNil(error)
                guard let tokenDetails = tokenDetails else {
                    XCTFail("tokenDetails is nil"); done(); return
                }
                XCTAssertNil(tokenDetails.clientId)
                done()
            }
        }
    }

    // RSA8e
    func test__063__requestToken__arguments__should_use_configured_defaults_if_the_object_arguments_are_omitted() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.clientId = "tester"
        let rest = ARTHttpClient(options: options)

        waitUntil(timeout: testTimeout) { done in
            rest.auth.requestToken(nil, with: nil) { tokenDetails, error in
                XCTAssertNil(error)
                XCTAssertNotNil(tokenDetails)
                XCTAssertEqual(tokenDetails!.capability, "{\"*\":[\"*\"]}")
                XCTAssertEqual(tokenDetails!.clientId, "tester")
                done()
            }
        }

        let tokenParams = ARTTokenParams()
        tokenParams.ttl = 2000
        tokenParams.capability = "{\"cansubscribe:*\":[\"subscribe\"]}"
        tokenParams.clientId = nil

        let authOptions = ARTAuthOptions()
        authOptions.key = options.key

        // Provide TokenParams and Options
        waitUntil(timeout: testTimeout) { done in
            rest.auth.requestToken(tokenParams, with: authOptions) { tokenDetails, error in
                XCTAssertNil(error)
                XCTAssertNotNil(tokenDetails)
                XCTAssertEqual(tokenDetails!.capability, "{\"cansubscribe:*\":[\"subscribe\"]}")
                XCTAssertNil(tokenDetails!.clientId)
                XCTAssertEqual(tokenDetails!.expires!.timeIntervalSince1970 - tokenDetails!.issued!.timeIntervalSince1970, tokenParams.ttl as? Double)
                done()
            }
        }

        // Provide TokenParams as null
        waitUntil(timeout: testTimeout) { done in
            rest.auth.requestToken(nil, with: authOptions) { tokenDetails, error in
                XCTAssertNil(error)
                XCTAssertNotNil(tokenDetails)
                XCTAssertEqual(tokenDetails!.capability, "{\"*\":[\"*\"]}")
                XCTAssertEqual(tokenDetails!.clientId, "tester")
                XCTAssertEqual(tokenDetails!.expires!.timeIntervalSince1970 - tokenDetails!.issued!.timeIntervalSince1970, ARTDefault.ttl())
                done()
            }
        }

        // Omit arguments
        waitUntil(timeout: testTimeout) { done in
            rest.auth.requestToken { tokenDetails, error in
                XCTAssertNil(error)
                XCTAssertNotNil(tokenDetails)
                XCTAssertEqual(tokenDetails!.capability, "{\"*\":[\"*\"]}")
                XCTAssertEqual(tokenDetails!.clientId, "tester")
                done()
            }
        }
    }

    // RSA8c

    func test__064__requestToken__authUrl__query_will_provide_a_token_string() throws {
        let test = Test()
        let testToken = try getTestToken(for: test)

        let options = try AblyTests.clientOptions(for: test)
        options.authUrl = URL(string: "http://echo.ably.io")
        XCTAssertNotNil(options.authUrl)
        // Plain text
        options.authParams = [URLQueryItem]()
        options.authParams!.append(URLQueryItem(name: "type", value: "text"))
        options.authParams!.append(URLQueryItem(name: "body", value: testToken))

        let rest = ARTHttpClient(options: options)
        let testHTTPExecutor = TestProxyHTTPExecutor(logger: .init(clientOptions: options))
        rest.internal.httpExecutor = testHTTPExecutor

        waitUntil(timeout: testTimeout) { done in
            rest.auth.requestToken(nil, with: nil, callback: { tokenDetails, error in
                XCTAssertEqual(testHTTPExecutor.requests.last?.url?.host, "echo.ably.io")
                XCTAssertNil(error)
                XCTAssertNotNil(tokenDetails)
                XCTAssertEqual(tokenDetails?.token, testToken)
                done()
            })
        }
    }

    func test__065__requestToken__authUrl__query_will_provide_a_TokenDetails() throws {
        let test = Test()
        let testTokenDetails = try XCTUnwrap(getTestTokenDetails(for: test, clientId: "tester"), "TokenDetails is empty")
        let jsonTokenDetails = try XCTUnwrap(createJsonEncoder().encode(testTokenDetails), "Invalid TokenDetails")

        let options = ARTClientOptions()
        options.authUrl = URL(string: "http://echo.ably.io")
        XCTAssertNotNil(options.authUrl)
        // JSON with TokenDetails
        options.authParams = [URLQueryItem]()
        options.authParams?.append(URLQueryItem(name: "type", value: "json"))
        options.authParams?.append(URLQueryItem(name: "body", value: jsonTokenDetails.toUTF8String))

        let rest = ARTHttpClient(options: options)
        let testHTTPExecutor = TestProxyHTTPExecutor(logger: .init(clientOptions: options))
        rest.internal.httpExecutor = testHTTPExecutor

        waitUntil(timeout: testTimeout) { done in
            rest.auth.requestToken(nil, with: nil, callback: { tokenDetails, error in
                XCTAssertEqual(testHTTPExecutor.requests.last?.url?.host, "echo.ably.io")
                XCTAssertNil(error)
                XCTAssertNotNil(tokenDetails)
                XCTAssertEqual(tokenDetails?.clientId, testTokenDetails.clientId)
                XCTAssertEqual(tokenDetails?.capability, testTokenDetails.capability)
                XCTAssertNotNil(tokenDetails?.issued)
                XCTAssertNotNil(tokenDetails?.expires)
                if let issued = tokenDetails?.issued, let testIssued = testTokenDetails.issued {
                    XCTAssertEqual(issued.compare(testIssued), ComparisonResult.orderedSame)
                }
                if let expires = tokenDetails?.expires, let testExpires = testTokenDetails.expires {
                    XCTAssertEqual(expires.compare(testExpires), ComparisonResult.orderedSame)
                }
                done()
            })
        }
    }

    func test__066__requestToken__authUrl__query_will_provide_a_TokenRequest() throws {
        let test = Test()
        let tokenParams = ARTTokenParams()
        tokenParams.capability = "{\"test\":[\"subscribe\"]}"

        let options = try AblyTests.commonAppSetup(for: test)
        options.authUrl = URL(string: "http://echo.ably.io")
        XCTAssertNotNil(options.authUrl)

        var rest = ARTHttpClient(options: options)

        var tokenRequest: ARTTokenRequest?
        waitUntil(timeout: testTimeout) { done in
            // Sandbox and valid TokenRequest
            rest.auth.createTokenRequest(tokenParams, options: nil, callback: { newTokenRequest, error in
                XCTAssertNil(error)
                tokenRequest = newTokenRequest
                done()
            })
        }

        let testTokenRequest = try XCTUnwrap(tokenRequest, "TokenRequest is empty")
        let jsonTokenRequest = try XCTUnwrap(createJsonEncoder().encode(testTokenRequest), "Invalid TokenRequest")

        // JSON with TokenRequest
        options.authParams = [URLQueryItem]()
        options.authParams?.append(URLQueryItem(name: "type", value: "json"))
        options.authParams?.append(URLQueryItem(name: "body", value: jsonTokenRequest.toUTF8String))

        rest = ARTHttpClient(options: options)
        let testHTTPExecutor = TestProxyHTTPExecutor(logger: .init(clientOptions: options))
        rest.internal.httpExecutor = testHTTPExecutor

        waitUntil(timeout: testTimeout) { done in
            rest.auth.requestToken(nil, with: nil, callback: { tokenDetails, error in
                XCTAssertEqual(testHTTPExecutor.requests.first?.url?.host, "echo.ably.io")
                XCTAssertNotEqual(testHTTPExecutor.requests.last?.url?.host, "echo.ably.io")
                XCTAssertNil(error)
                guard let tokenDetails = tokenDetails else {
                    fail("TokenDetails is empty"); done()
                    return
                }
                XCTAssertNotNil(tokenDetails.token)
                XCTAssertEqual(tokenDetails.capability, tokenParams.capability)
                done()
            })
        }
    }

    // RSA8c1a
    func test__069__requestToken__authUrl__parameters__should_be_added_to_the_URL_when_auth_method_is_GET() throws {
        let clientOptions = ARTClientOptions()
        clientOptions.authUrl = URL(string: "http://auth.ably.io")
        var authParams = [
            "param1": "value",
            "param2": "value",
            "clientId": "should not be overwritten",
        ]
        clientOptions.authParams = authParams.map {
            URLQueryItem(name: $0, value: $1)
        }
        clientOptions.authHeaders = ["X-Header-1": "foo", "X-Header-2": "bar"]
        let tokenParams = ARTTokenParams()
        tokenParams.clientId = "test"

        let rest = ARTHttpClient(options: clientOptions)
        let request = rest.auth.internal.buildRequest(clientOptions, with: tokenParams)

        for (header, expectedValue) in clientOptions.authHeaders! {
            if let value = request.allHTTPHeaderFields?[header] {
                XCTAssertEqual(value, expectedValue)
            } else {
                fail("Missing header in request: \(header), expected: \(expectedValue)")
            }
        }

        let url = try XCTUnwrap(request.url, "Request is invalid")
        let urlComponents = try XCTUnwrap(NSURLComponents(url: url, resolvingAgainstBaseURL: false), "invalid URL: \(url)")

        XCTAssertEqual(urlComponents.scheme, "http")
        XCTAssertEqual(urlComponents.host, "auth.ably.io")
        guard let queryItems = urlComponents.queryItems else {
            fail("URL without query: \(url)")
            return
        }
        for queryItem in queryItems {
            if var expectedValue = authParams[queryItem.name] {
                if queryItem.name == "clientId" {
                    expectedValue = "test"
                }
                XCTAssertEqual(queryItem.value!, expectedValue)
                authParams.removeValue(forKey: queryItem.name)
            }
        }
        expect(authParams).to(beEmpty())
    }

    // RSA8c1b
    func test__070__requestToken__authUrl__parameters__should_added_on_the_body_request_when_auth_method_is_POST() {
        let clientOptions = ARTClientOptions()
        clientOptions.authUrl = URL(string: "http://auth.ably.io")
        clientOptions.authParams = [
            URLQueryItem(name: "identifier", value: "123"),
        ]
        clientOptions.authMethod = "POST"
        clientOptions.authHeaders = ["X-Header-1": "foo", "X-Header-2": "bar"]
        let tokenParams = ARTTokenParams()
        tokenParams.ttl = 2000
        tokenParams.capability = "{\"cansubscribe:*\":[\"subscribe\"]}"

        let rest = ARTHttpClient(options: clientOptions)

        let request = rest.auth.internal.buildRequest(clientOptions, with: tokenParams)

        guard let httpBodyData = request.httpBody else {
            fail("Body is missing"); return
        }
        guard let httpBodyString = String(data: httpBodyData, encoding: .utf8) else {
            fail("Body should be a string"); return
        }

        let expectedFormEncoding = "capability=%7B%22cansubscribe%3A%2A%22%3A%5B%22subscribe%22%5D%7D&identifier=123&ttl=2000"

        XCTAssertEqual(httpBodyString, expectedFormEncoding)

        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")

        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Length"), "89")

        for (header, expectedValue) in clientOptions.authHeaders! {
            if let value = request.value(forHTTPHeaderField: header) {
                XCTAssertEqual(value, expectedValue)
            } else {
                fail("Missing header in request: \(header), expected: \(expectedValue)")
            }
        }
    }

    // RSA8c2
    func test__067__requestToken__authUrl__TokenParams_should_take_precedence_over_any_configured_authParams_when_a_name_conflict_occurs() {
        let options = ARTClientOptions()
        options.clientId = "john"
        options.authUrl = URL(string: "http://auth.ably.io")
        options.authMethod = "GET"
        options.authHeaders = ["X-Header-1": "foo1", "X-Header-2": "foo2"]
        let authParams = [
            "key": "secret",
            "clientId": "should be overridden",
        ]
        options.authParams = authParams.map { URLQueryItem(name: $0, value: $1) }

        let tokenParams = ARTTokenParams()
        tokenParams.clientId = "tester"

        let client = ARTHttpClient(options: options)
        let testHTTPExecutor = TestProxyHTTPExecutor(logger: .init(clientOptions: options))
        client.internal.httpExecutor = testHTTPExecutor

        waitUntil(timeout: testTimeout) { done in
            client.auth.requestToken(tokenParams, with: nil) { _, _ in
                let query = testHTTPExecutor.requests[0].url!.query
                expect(query).to(haveParam("clientId", withValue: tokenParams.clientId!))
                done()
            }
        }
    }

    // RSA8c3
    func test__068__requestToken__authUrl__should_override_previously_configured_parameters() {
        let clientOptions = ARTClientOptions()
        clientOptions.authUrl = URL(string: "http://auth.ably.io")
        let rest = ARTHttpClient(options: clientOptions)

        let authOptions = ARTAuthOptions()
        authOptions.authUrl = URL(string: "http://auth.ably.io")
        authOptions.authParams = [URLQueryItem(name: "ttl", value: "invalid")]
        authOptions.authParams = [URLQueryItem(name: "test", value: "1")]
        let url = rest.auth.internal.buildURL(authOptions, with: ARTTokenParams())
        expect(url.absoluteString).to(contain(URL(string: "http://auth.ably.io")?.absoluteString ?? ""))
    }

    // RSA8a
    func test__057__requestToken__implicitly_creates_a_TokenRequest_and_requests_a_token() throws {
        let test = Test()
        let rest = ARTHttpClient(options: try AblyTests.commonAppSetup(for: test))

        var createTokenRequestMethodWasCalled = false

        // Adds a block of code after `createTokenRequest` is triggered
        let token = rest.auth.internal.testSuite_injectIntoMethod(after: NSSelectorFromString("_createTokenRequest:options:callback:")) {
            createTokenRequestMethodWasCalled = true
        }
        defer { token.remove() }

        waitUntil(timeout: testTimeout) { done in
            rest.auth.requestToken(nil, with: nil, callback: { tokenDetails, error in
                XCTAssertNil(error)
                expect(tokenDetails?.token).toNot(beEmpty())
                done()
            })
        }

        XCTAssertTrue(createTokenRequestMethodWasCalled)
    }

    // RSA8b

    func test__071__requestToken__should_support_all_TokenParams__using_defaults() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.clientId = currentClientId
        let rest = ARTHttpClient(options: options)

        // Default values
        let defaultTokenParams = ARTTokenParams(clientId: currentClientId)
        defaultTokenParams.ttl = ARTDefault.ttl() as NSNumber // Set by the server.

        waitUntil(timeout: testTimeout) { done in
            rest.auth.requestToken(nil, with: nil, callback: { tokenDetails, _ in
                XCTAssertEqual(tokenDetails?.clientId, defaultTokenParams.clientId)
                XCTAssertNil(defaultTokenParams.capability)
                XCTAssertEqual(tokenDetails?.capability, "{\"*\":[\"*\"]}") // Ably supplied capabilities of the underlying key
                XCTAssertNotNil(tokenDetails?.issued)
                XCTAssertNotNil(tokenDetails?.expires)
                if let issued = tokenDetails?.issued, let expires = tokenDetails?.expires {
                    XCTAssertEqual(expires.timeIntervalSince(issued), defaultTokenParams.ttl as? TimeInterval)
                }
                done()
            })
        }
    }

    func test__072__requestToken__should_support_all_TokenParams__overriding_defaults() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.clientId = currentClientId
        let rest = ARTHttpClient(options: options)

        // Custom values
        let expectedTtl = 4800.0
        let expectedCapability = "{\"canpublish:*\":[\"publish\"]}"

        let tokenParams = ARTTokenParams(clientId: currentClientId)
        tokenParams.ttl = NSNumber(value: expectedTtl)
        tokenParams.capability = expectedCapability

        waitUntil(timeout: testTimeout) { done in
            rest.auth.requestToken(tokenParams, with: nil, callback: { tokenDetails, error in
                XCTAssertNil(error)
                XCTAssertEqual(tokenDetails?.clientId, options.clientId)
                XCTAssertEqual(tokenDetails?.capability, expectedCapability)
                XCTAssertNotNil(tokenDetails?.issued)
                XCTAssertNotNil(tokenDetails?.expires)
                if let issued = tokenDetails?.issued, let expires = tokenDetails?.expires {
                    XCTAssertEqual(expires.timeIntervalSince(issued), expectedTtl)
                }
                done()
            })
        }
    }

    // RSA8d

    func test__073__requestToken__When_authCallback_option_is_set__it_will_invoke_the_callback__with_a_token_string() throws {
        let test = Test()
        let options = try AblyTests.clientOptions(for: test)
        let expectedTokenParams = ARTTokenParams()

        options.authCallback = { tokenParams, completion in
            XCTAssertNil(tokenParams.clientId)
            completion("token_string" as ARTTokenDetailsCompatible?, nil)
        }
        let rest = ARTHttpClient(options: options)

        waitUntil(timeout: testTimeout) { done in
            rest.auth.requestToken(expectedTokenParams, with: nil) { tokenDetails, error in
                XCTAssertNil(error)
                XCTAssertEqual(tokenDetails!.token, "token_string")
                done()
            }
        }
    }

    func test__074__requestToken__When_authCallback_option_is_set__it_will_invoke_the_callback__with_a_TokenDetails() throws {
        let test = Test()
        let expectedTokenParams = ARTTokenParams()

        let options = try AblyTests.clientOptions(for: test)
        options.authCallback = { tokenParams, completion in
            XCTAssertNil(tokenParams.clientId)
            completion(ARTTokenDetails(token: "token_from_details"), nil)
        }
        let rest = ARTHttpClient(options: options)

        waitUntil(timeout: testTimeout) { done in
            rest.auth.requestToken(expectedTokenParams, with: nil) { tokenDetails, error in
                XCTAssertNil(error)
                XCTAssertEqual(tokenDetails!.token, "token_from_details")
                done()
            }
        }
    }

    func test__075__requestToken__When_authCallback_option_is_set__it_will_invoke_the_callback__with_a_TokenRequest() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let expectedTokenParams = ARTTokenParams()
        expectedTokenParams.clientId = "foo"
        var rest: ARTHttpClient!

        options.authCallback = { tokenParams, completion in
            XCTAssertTrue(tokenParams.clientId == expectedTokenParams.clientId)
            rest.auth.createTokenRequest(tokenParams, options: options) { tokenRequest, error in
                completion(tokenRequest, error)
            }
        }

        rest = ARTHttpClient(options: options)

        waitUntil(timeout: testTimeout) { done in
            rest.auth.requestToken(expectedTokenParams, with: nil) { tokenDetails, error in
                XCTAssertNil(error)
                guard let tokenDetails = tokenDetails else {
                    fail("tokenDetails is nil"); done(); return
                }
                XCTAssertEqual(tokenDetails.clientId, expectedTokenParams.clientId)
                done()
            }
        }
    }

    // RSA8f1
    func test__058__requestToken__ensure_the_message_published_does_not_have_a_clientId() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.token = try getTestToken(for: test, clientId: nil)
        let rest = ARTHttpClient(options: options)
        let testHTTPExecutor = TestProxyHTTPExecutor(logger: .init(clientOptions: options))
        rest.internal.httpExecutor = testHTTPExecutor
        let channel = rest.channels.get(test.uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            let message = ARTMessage(name: nil, data: "message without an explicit clientId")
            XCTAssertNil(message.clientId)
            channel.publish([message]) { error in
                XCTAssertNil(error)
                switch extractBodyAsMessages(testHTTPExecutor.requests.first) {
                case let .failure(error):
                    fail(error)
                case let .success(httpBody):
                    XCTAssertNil(httpBody.unbox.first!["clientId"])
                }
                channel.history { page, error in
                    XCTAssertNil(error)
                    guard let page = page else {
                        fail("Result is empty"); done(); return
                    }
                    XCTAssertEqual(page.items.count, 1)
                    XCTAssertNil((page.items[0]).clientId)
                    done()
                }
            }
        }
        XCTAssertNil(rest.auth.clientId)
    }

    // RSA8f2
    func test__059__requestToken__ensure_that_the_message_is_rejected() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.token = try getTestToken(for: test, clientId: nil)
        let rest = ARTHttpClient(options: options)
        let channel = rest.channels.get(test.uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            let message = ARTMessage(name: nil, data: "message with an explicit clientId", clientId: "john")
            channel.publish([message]) { error in
                guard let error = error else {
                    fail("Error is nil"); done(); return
                }
                XCTAssertTrue(error.code == ARTErrorCode.invalidClientId.rawValue)
                done()
            }
        }
        XCTAssertNil(rest.auth.clientId)
    }

    // RSA8f3
    func test__060__requestToken__ensure_the_message_published_with_a_wildcard_____does_not_have_a_clientId() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let rest = ARTHttpClient(options: options)

        waitUntil(timeout: testTimeout) { done in
            rest.auth.authorize(ARTTokenParams(clientId: "*"), options: nil) { _, error in
                XCTAssertNil(error)
                done()
            }
        }

        let testHTTPExecutor = TestProxyHTTPExecutor(logger: .init(clientOptions: options))
        rest.internal.httpExecutor = testHTTPExecutor
        let channel = rest.channels.get(test.uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            let message = ARTMessage(name: nil, data: "no client")
            XCTAssertNil(message.clientId)
            channel.publish([message]) { error in
                XCTAssertNil(error)
                switch extractBodyAsMessages(testHTTPExecutor.requests.first) {
                case let .failure(error):
                    fail(error)
                case let .success(httpBody):
                    XCTAssertNil(httpBody.unbox.first!["clientId"])
                }
                channel.history { page, error in
                    guard let page = page else {
                        fail("Page is empty"); done(); return
                    }
                    XCTAssertNil(error)
                    XCTAssertEqual(page.items.count, 1)
                    XCTAssertNil(page.items[0].clientId)
                    done()
                }
            }
        }
        XCTAssertEqual(rest.auth.clientId, "*")
    }

    // RSA8f4
    func test__061__requestToken__ensure_the_message_published_with_a_wildcard_____has_the_provided_clientId() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        // Request a token with a wildcard '*' value clientId
        options.token = try getTestToken(for: test, clientId: "*")
        let rest = ARTHttpClient(options: options)
        let channel = rest.channels.get(test.uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            let message = ARTMessage(name: nil, data: "message with an explicit clientId", clientId: "john")
            channel.publish([message]) { error in
                XCTAssertNil(error)
                channel.history { page, error in
                    XCTAssertNil(error)
                    guard let page = page else {
                        fail("Page is empty"); done(); return
                    }
                    guard let item = page.items.first else {
                        fail("First item does not exist"); done(); return
                    }
                    XCTAssertEqual(item.clientId, "john")
                    done()
                }
            }
        }
        XCTAssertNil(rest.auth.clientId)
    }

    // RSA9

    // RSA9h
    func test__076__createTokenRequest__should_not_merge_with_the_configured_params_and_options_but_instead_replace_all_corresponding_values__even_when__null_() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.clientId = "client_string"
        let rest = ARTHttpClient(options: options)

        let tokenParams = ARTTokenParams()
        let defaultCapability = tokenParams.capability
        XCTAssertNil(defaultCapability)

        waitUntil(timeout: testTimeout) { done in
            rest.auth.createTokenRequest(nil, options: nil) { tokenRequest, error in
                XCTAssertNil(error)
                guard let tokenRequest = tokenRequest else {
                    XCTFail("tokenRequest is nil"); done(); return
                }
                XCTAssertEqual(tokenRequest.clientId, options.clientId)
                XCTAssertNil(tokenRequest.ttl)
                XCTAssertNil(tokenRequest.capability)
                done()
            }
        }

        tokenParams.ttl = NSNumber(value: ExpectedTokenParams.ttl)
        tokenParams.capability = ExpectedTokenParams.capability
        tokenParams.clientId = nil

        let authOptions = ARTAuthOptions()
        authOptions.queryTime = true
        authOptions.key = options.key

        let mockServerDate = Date().addingTimeInterval(120)
        rest.auth.internal.testSuite_returnValue(for: NSSelectorFromString("handleServerTime:"), with: mockServerDate)

        var serverTimeRequestCount = 0
        let hook = rest.internal.testSuite_injectIntoMethod(after: #selector(rest.internal._time(withWrapperSDKAgents:completion:))) {
            serverTimeRequestCount += 1
        }
        defer { hook.remove() }

        waitUntil(timeout: testTimeout) { done in
            rest.auth.createTokenRequest(tokenParams, options: authOptions) { tokenRequest, error in
                XCTAssertNil(error)
                guard let tokenRequest = tokenRequest else {
                    XCTFail("tokenRequest is nil"); done(); return
                }
                XCTAssertNil(tokenRequest.clientId)
                expect(tokenRequest.timestamp).to(beCloseTo(mockServerDate))
                XCTAssertEqual(serverTimeRequestCount, 1)
                XCTAssertEqual(tokenRequest.ttl, ExpectedTokenParams.ttl as NSNumber)
                XCTAssertEqual(tokenRequest.capability, ExpectedTokenParams.capability)
                done()
            }
        }

        tokenParams.clientId = "newClientId"
        tokenParams.ttl = 2000
        tokenParams.capability = "{ \"test:*\":[\"test\"] }"

        waitUntil(timeout: testTimeout) { done in
            rest.auth.createTokenRequest(tokenParams, options: authOptions) { tokenRequest, error in
                XCTAssertNil(error)
                guard let tokenRequest = tokenRequest else {
                    XCTFail("tokenRequest is nil"); done(); return
                }
                XCTAssertEqual(tokenRequest.clientId, "newClientId")
                XCTAssertEqual(tokenRequest.ttl, 2000)
                XCTAssertEqual(tokenRequest.capability, "{ \"test:*\":[\"test\"] }")
                done()
            }
        }

        tokenParams.clientId = nil

        waitUntil(timeout: testTimeout) { done in
            rest.auth.createTokenRequest(tokenParams, options: authOptions) { tokenRequest, error in
                XCTAssertNil(error)
                guard let tokenRequest = tokenRequest else {
                    XCTFail("tokenRequest is nil"); done(); return
                }
                XCTAssertNil(tokenRequest.clientId)
                done()
            }
        }
    }

    func test__077__createTokenRequest__should_override_defaults_if_AuthOptions_provided() throws {
        let test = Test()
        let defaultOptions = try AblyTests.commonAppSetup(for: test)
        defaultOptions.authCallback = { _, _ in
            fail("Should not be called")
        }

        var testTokenRequest: ARTTokenRequest?
        let rest = ARTHttpClient(options: defaultOptions)
        rest.auth.createTokenRequest(nil, options: nil, callback: { tokenRequest, _ in
            testTokenRequest = tokenRequest
        })
        expect(testTokenRequest).toEventuallyNot(beNil(), timeout: testTimeout)

        var customCallbackCalled = false
        let customOptions = ARTAuthOptions()
        customOptions.authCallback = { _, completion in
            customCallbackCalled = true
            completion(testTokenRequest, nil)
        }

        waitUntil(timeout: testTimeout) { done in
            rest.auth.authorize(nil, options: customOptions) { _, error in
                XCTAssertNil(error)
                done()
            }
        }
        XCTAssertTrue(customCallbackCalled)
    }

    func test__078__createTokenRequest__should_use_defaults_if_no_AuthOptions_is_provided() throws {
        let test = Test()
        var currentTokenRequest: ARTTokenRequest?
        var callbackCalled = false

        let defaultOptions = try AblyTests.commonAppSetup(for: test)
        defaultOptions.authCallback = { _, completion in
            callbackCalled = true
            guard let tokenRequest = currentTokenRequest else {
                fail("tokenRequest is nil"); return
            }
            completion(tokenRequest, nil)
        }

        let rest = ARTHttpClient(options: defaultOptions)
        rest.auth.createTokenRequest(nil, options: nil, callback: { tokenRequest, _ in
            currentTokenRequest = tokenRequest
        })
        expect(currentTokenRequest).toEventuallyNot(beNil(), timeout: testTimeout)

        waitUntil(timeout: testTimeout) { done in
            rest.auth.authorize(nil, options: nil) { _, error in
                XCTAssertNil(error)
                done()
            }
        }
        XCTAssertTrue(callbackCalled)
    }

    func test__079__createTokenRequest__should_replace_defaults_if__nil__option_s_field_passed() throws {
        let test = Test()
        let defaultOptions = try AblyTests.commonAppSetup(for: test)
        let rest = ARTHttpClient(options: defaultOptions)

        let customOptions = ARTAuthOptions()

        waitUntil(timeout: testTimeout) { done in
            rest.auth.createTokenRequest(nil, options: customOptions) { _, error in
                guard let error = error else {
                    fail("Error is nil"); done(); return
                }
                expect(error.localizedDescription).to(contain("no key provided for signing token requests"))
                done()
            }
        }
    }

    // RSA9h
    func test__080__createTokenRequest__should_use_configured_defaults_if_the_object_arguments_are_omitted() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let rest = ARTHttpClient(options: options)

        let tokenParams = ARTTokenParams()
        tokenParams.clientId = "tester"
        tokenParams.ttl = 2000
        tokenParams.capability = "{\"foo:*\":[\"publish\"]}"

        let authOptions = ARTAuthOptions()
        authOptions.queryTime = true
        authOptions.key = options.key

        var serverTimeRequestCount = 0
        let hook = rest.internal.testSuite_injectIntoMethod(after: #selector(rest.internal._time(withWrapperSDKAgents:completion:))) {
            serverTimeRequestCount += 1
        }
        defer { hook.remove() }

        waitUntil(timeout: testTimeout) { done in
            rest.auth.createTokenRequest(tokenParams, options: authOptions) { tokenRequest, error in
                XCTAssertNil(error)
                guard let tokenRequest = tokenRequest else {
                    XCTFail("TokenRequest is nil"); done(); return
                }
                XCTAssertEqual(tokenRequest.clientId, tokenParams.clientId)
                XCTAssertEqual(tokenRequest.ttl, tokenParams.ttl)
                XCTAssertEqual(tokenRequest.capability, tokenParams.capability)
                done()
            }
        }

        waitUntil(timeout: testTimeout) { done in
            rest.auth.createTokenRequest { tokenRequest, error in
                XCTAssertNil(error)
                guard let tokenRequest = tokenRequest else {
                    XCTFail("TokenRequest is nil"); done(); return
                }
                XCTAssertNil(tokenRequest.clientId)
                XCTAssertNil(tokenRequest.ttl)
                XCTAssertNil(tokenRequest.capability)
                done()
            }
        }

        XCTAssertEqual(serverTimeRequestCount, 1)
    }

    // RSA9a
    func test__081__createTokenRequest__should_create_and_sign_a_TokenRequest() throws {
        let test = Test()
        let rest = ARTHttpClient(options: try AblyTests.commonAppSetup(for: test))
        let expectedClientId = "client_string"
        let tokenParams = ARTTokenParams(clientId: expectedClientId)

        waitUntil(timeout: testTimeout) { done in
            rest.auth.createTokenRequest(tokenParams, options: nil, callback: { tokenRequest, error in
                defer { done() }
                XCTAssertNil(error)
                guard let tokenRequest = tokenRequest else {
                    XCTFail("TokenRequest is nil"); return
                }
                expect(tokenRequest).to(beAnInstanceOf(ARTTokenRequest.self))
                XCTAssertEqual(tokenRequest.clientId, expectedClientId)
                XCTAssertNotNil(tokenRequest.mac)
                XCTAssertNotNil(tokenRequest.nonce)
            })
        }
    }

    // RSA9b
    func test__082__createTokenRequest__should_support_AuthOptions() throws {
        let test = Test()
        let rest = ARTHttpClient(options: try AblyTests.commonAppSetup(for: test))
        let auth: ARTAuth = rest.auth

        let authOptions = ARTAuthOptions(key: "key:secret")

        waitUntil(timeout: testTimeout) { done in
            auth.createTokenRequest(nil, options: authOptions, callback: { tokenRequest, error in
                defer { done() }
                XCTAssertNil(error)
                guard let tokenRequest = tokenRequest else {
                    XCTFail("TokenRequest is nil"); return
                }
                XCTAssertEqual(tokenRequest.keyName, "key")
            })
        }
    }

    // RSA9c
    func test__083__createTokenRequest__should_generate_a_unique_16_plus_character_nonce_if_none_is_provided() throws {
        let test = Test()
        let rest = ARTHttpClient(options: try AblyTests.commonAppSetup(for: test))

        waitUntil(timeout: testTimeout) { done in
            // First
            rest.auth.createTokenRequest(nil, options: nil, callback: { tokenRequest, error in
                XCTAssertNil(error)
                guard let tokenRequest1 = tokenRequest else {
                    XCTFail("TokenRequest1 is nil"); done(); return
                }
                XCTAssertEqual(tokenRequest1.nonce.count, 16)

                // Second
                rest.auth.createTokenRequest(nil, options: nil, callback: { tokenRequest, error in
                    XCTAssertNil(error)
                    guard let tokenRequest2 = tokenRequest else {
                        XCTFail("TokenRequest2 is nil"); done(); return
                    }
                    XCTAssertEqual(tokenRequest2.nonce.count, 16)

                    // Uniqueness
                    XCTAssertNotEqual(tokenRequest1.nonce, tokenRequest2.nonce)
                    done()
                })
            })
        }
    }

    // RSA9d

    func test__087__createTokenRequest__should_generate_a_timestamp__from_current_time_if_not_provided() throws {
        let test = Test()
        let rest = ARTHttpClient(options: try AblyTests.commonAppSetup(for: test))

        waitUntil(timeout: testTimeout) { done in
            rest.auth.createTokenRequest(nil, options: nil, callback: { tokenRequest, error in
                defer { done() }
                XCTAssertNil(error)
                guard let tokenRequest = tokenRequest else {
                    XCTFail("TokenRequest is nil"); return
                }
                expect(tokenRequest.timestamp).to(beCloseTo(Date(), within: 1.0))
            })
        }
    }

    func test__088__createTokenRequest__should_generate_a_timestamp__will_retrieve_the_server_time_if_queryTime_is_true() throws {
        let test = Test()
        let rest = ARTHttpClient(options: try AblyTests.commonAppSetup(for: test))

        var serverTimeRequestWasMade = false
        let block: @convention(block) (AspectInfo) -> Void = { _ in
            serverTimeRequestWasMade = true
        }

        let hook = ARTHttpClientInternal.aspect_hook(rest.internal)
        // Adds a block of code after `time` is triggered
        _ = try hook(#selector(ARTHttpClientInternal._time(withWrapperSDKAgents:completion:)), .positionBefore, unsafeBitCast(block, to: ARTHttpClientInternal.self))

        let authOptions = ARTAuthOptions()
        authOptions.queryTime = true
        authOptions.key = try AblyTests.commonAppSetup(for: test).key

        waitUntil(timeout: testTimeout) { done in
            rest.auth.createTokenRequest(nil, options: authOptions, callback: { tokenRequest, error in
                XCTAssertNil(error)
                guard let tokenRequest = tokenRequest else {
                    XCTFail("tokenRequest is nil"); done(); return
                }
                XCTAssertNotNil(tokenRequest.timestamp)
                XCTAssertTrue(serverTimeRequestWasMade)
                done()
            })
        }
    }

    // RSA9e

    func test__089__createTokenRequest__TTL__should_be_optional() throws {
        let test = Test()
        let rest = ARTHttpClient(options: try AblyTests.commonAppSetup(for: test))

        waitUntil(timeout: testTimeout) { done in
            rest.auth.createTokenRequest(nil, options: nil, callback: { tokenRequest, error in
                defer { done() }
                XCTAssertNil(error)
                guard let tokenRequest = tokenRequest else {
                    XCTFail("TokenRequest is nil"); return
                }
                // In Seconds because TTL property is a NSTimeInterval but further it does the conversion to milliseconds
                XCTAssertNil(tokenRequest.ttl)
            })
        }

        let tokenParams = ARTTokenParams()
        XCTAssertNil(tokenParams.ttl)

        let expectedTtl = TimeInterval(10)
        tokenParams.ttl = NSNumber(value: expectedTtl)

        waitUntil(timeout: testTimeout) { done in
            rest.auth.createTokenRequest(tokenParams, options: nil, callback: { tokenRequest, error in
                defer { done() }
                XCTAssertNil(error)
                guard let tokenRequest = tokenRequest else {
                    XCTFail("TokenRequest is nil"); return
                }
                XCTAssertEqual(tokenRequest.ttl as? TimeInterval, expectedTtl)
            })
        }
    }

    func test__090__createTokenRequest__TTL__should_be_specified_in_milliseconds() throws {
        let test = Test()
        let rest = ARTHttpClient(options: try AblyTests.commonAppSetup(for: test))

        let params = ARTTokenParams()
        params.ttl = NSNumber(value: 42)
        waitUntil(timeout: testTimeout) { done in
            rest.auth.createTokenRequest(params, options: nil, callback: { tokenRequest, error in
                defer { done() }
                XCTAssertNil(error)
                guard let tokenRequest = tokenRequest else {
                    XCTFail("TokenRequest is nil"); return
                }
                XCTAssertEqual(tokenRequest.ttl as? TimeInterval, 42)

                // Check if the encoder changes the TTL to milliseconds
                let encoder = rest.internal.defaultEncoder as! ARTJsonLikeEncoder
                let data = try! encoder.encode(tokenRequest)
                let jsonObject = (try! encoder.delegate!.decode(data)) as! NSDictionary
                let ttl = jsonObject["ttl"] as! NSNumber
                XCTAssertEqual(ttl as? Int64, 42 * 1000)

                // Make sure it comes back the same.
                let decoded = try! encoder.decodeTokenRequest(data)
                XCTAssertEqual(decoded.ttl as? TimeInterval, 42)
            })
        }
    }

    func test__091__createTokenRequest__TTL__should_be_valid_to_request_a_token_for_24_hours() throws {
        let test = Test()
        let rest = ARTHttpClient(options: try AblyTests.commonAppSetup(for: test))
        let tokenParams = ARTTokenParams()
        let dayInSeconds = TimeInterval(24 * 60 * 60)
        tokenParams.ttl = dayInSeconds as NSNumber

        waitUntil(timeout: testTimeout) { done in
            rest.auth.requestToken(tokenParams, with: nil) { tokenDetails, error in
                XCTAssertNil(error)
                guard let tokenDetails = tokenDetails else {
                    XCTFail("TokenDetails is nil"); done(); return
                }
                expect(tokenDetails.expires!.timeIntervalSince(tokenDetails.issued!)).to(beCloseTo(dayInSeconds))
                done()
            }
        }
    }

    // RSA9f
    func test__084__createTokenRequest__should_provide_capability_has_json_text() throws {
        let test = Test()
        let rest = ARTHttpClient(options: try AblyTests.commonAppSetup(for: test))

        let tokenParams = ARTTokenParams()
        tokenParams.capability = "{ - }"

        waitUntil(timeout: testTimeout) { done in
            rest.auth.createTokenRequest(tokenParams, options: nil, callback: { tokenRequest, error in
                defer { done() }
                guard let error = error as? NSError else {
                    XCTFail("Error is nil"); return
                }
                XCTAssertTrue(error.code == 3840) // Capability: The data couldn't be read because it isn't in the correct format.
                XCTAssertNil(tokenRequest?.capability)
            })
        }

        let expectedCapability = "{ \"cansubscribe:*\":[\"subscribe\"] }"
        tokenParams.capability = expectedCapability

        rest.auth.createTokenRequest(tokenParams, options: nil, callback: { tokenRequest, error in
            XCTAssertNil(error)
            guard let tokenRequest = tokenRequest else {
                XCTFail("TokenRequest is nil"); return
            }
            XCTAssertEqual(tokenRequest.capability, expectedCapability)
        })
    }

    // RSA9g
    func test__085__createTokenRequest__should_generate_a_valid_HMAC() throws {
        let test = Test()
        let rest = ARTHttpClient(options: try AblyTests.commonAppSetup(for: test))

        let tokenParams = ARTTokenParams(clientId: "client_string")

        waitUntil(timeout: testTimeout) { done in
            rest.auth.createTokenRequest(tokenParams, options: nil, callback: { tokenRequest, error in
                XCTAssertNil(error)
                guard let tokenRequest1 = tokenRequest else {
                    XCTFail("TokenRequest is nil"); done(); return
                }
                let signed = tokenParams.sign(rest.internal.options.key!, withNonce: tokenRequest1.nonce)
                XCTAssertEqual(tokenRequest1.mac, signed?.mac)

                rest.auth.createTokenRequest(tokenParams, options: nil, callback: { tokenRequest, error in
                    XCTAssertNil(error)
                    guard let tokenRequest2 = tokenRequest else {
                        XCTFail("TokenRequest is nil"); done(); return
                    }
                    XCTAssertNotEqual(tokenRequest2.nonce, tokenRequest1.nonce)
                    XCTAssertNotEqual(tokenRequest2.mac, tokenRequest1.mac)
                    done()
                })
            })
        }
    }

    // RSA9i
    func test__086__createTokenRequest__should_respect_all_requirements() throws {
        let test = Test()
        let rest = ARTHttpClient(options: try AblyTests.commonAppSetup(for: test))
        let expectedClientId = "client_string"
        let tokenParams = ARTTokenParams(clientId: expectedClientId)
        let expectedTtl = 6.0
        tokenParams.ttl = NSNumber(value: expectedTtl)
        let expectedCapability = "{}"
        tokenParams.capability = expectedCapability

        let authOptions = ARTAuthOptions()
        authOptions.queryTime = true
        authOptions.key = try AblyTests.commonAppSetup(for: test).key

        var serverTime: Date?
        waitUntil(timeout: testTimeout) { done in
            rest.time { date, _ in
                serverTime = date
                done()
            }
        }
        XCTAssertNotNil(serverTime, "Server time is nil")

        waitUntil(timeout: testTimeout) { done in
            rest.auth.createTokenRequest(tokenParams, options: authOptions, callback: { tokenRequest, error in
                defer { done() }
                XCTAssertNil(error)
                guard let tokenRequest = tokenRequest else {
                    XCTFail("TokenRequest is nil"); return
                }
                XCTAssertEqual(tokenRequest.clientId, expectedClientId)
                XCTAssertNotNil(tokenRequest.mac)
                XCTAssertEqual(tokenRequest.nonce.count, 16)
                XCTAssertEqual(tokenRequest.ttl as? TimeInterval, expectedTtl)
                XCTAssertEqual(tokenRequest.capability, expectedCapability)
                expect(tokenRequest.timestamp).to(beCloseTo(serverTime!, within: 6.0))
            })
        }
    }

    // RSA10

    // RSA10a
    func test__092__authorize__should_always_create_a_token() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.useTokenAuth = true
        let rest = ARTHttpClient(options: options)
        let channel = rest.channels.get(test.uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "first check") { error in
                XCTAssertNil(error)
                done()
            }
        }

        // Check that token exists
        XCTAssertEqual(rest.auth.internal.method, ARTAuthMethod.token)

        let firstTokenDetails = try XCTUnwrap(rest.auth.tokenDetails, "TokenDetails is nil")
        XCTAssertNotNil(firstTokenDetails.token)

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "second check") { error in
                XCTAssertNil(error)
                done()
            }
        }

        // Check that token has not changed
        XCTAssertEqual(rest.auth.internal.method, ARTAuthMethod.token)

        let secondTokenDetails = try XCTUnwrap(rest.auth.tokenDetails, "TokenDetails is nil")
        XCTAssertTrue(firstTokenDetails === secondTokenDetails)

        waitUntil(timeout: testTimeout) { done in
            rest.auth.authorize(nil, options: nil, callback: { tokenDetails, error in
                XCTAssertNil(error)
                guard let tokenDetails = tokenDetails else {
                    XCTFail("TokenDetails is nil"); done(); return
                }
                // Check that token has changed
                XCTAssertNotEqual(tokenDetails.token, firstTokenDetails.token)

                channel.publish(nil, data: "third check") { error in
                    XCTAssertNil(error)
                    guard let thirdTokenDetails = rest.auth.tokenDetails else {
                        fail("TokenDetails is nil"); return
                    }
                    XCTAssertEqual(thirdTokenDetails.token, tokenDetails.token)
                    done()
                }
            })
        }
    }

    // RSA10a
    func test__093__authorize__should_create_a_new_token_if_one_already_exist_and_ensure_Token_Auth_is_used_for_all_future_requests() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let testToken = try getTestToken(for: test)
        options.token = testToken
        let rest = ARTHttpClient(options: options)

        XCTAssertNotNil(rest.auth.tokenDetails?.token)
        waitUntil(timeout: testTimeout) { done in
            rest.auth.authorize(nil, options: nil, callback: { tokenDetails, error in
                guard let tokenDetails = tokenDetails else {
                    XCTFail("TokenDetails is nil"); done(); return
                }
                XCTAssertNotEqual(tokenDetails.token, testToken)
                XCTAssertEqual(rest.auth.internal.method, ARTAuthMethod.token)

                publishTestMessage(rest, channelName: test.uniqueChannelName(), completion: { error in
                    XCTAssertNil(error)
                    XCTAssertEqual(rest.auth.internal.method, ARTAuthMethod.token)
                    XCTAssertEqual(rest.auth.tokenDetails?.token, tokenDetails.token)
                    done()
                })
            })
        }
    }

    // RSA10a
    func test__094__authorize__should_create_a_token_immediately_and_ensures_Token_Auth_is_used_for_all_future_requests() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let rest = ARTHttpClient(options: options)

        XCTAssertNil(rest.auth.tokenDetails?.token)
        waitUntil(timeout: testTimeout) { done in
            rest.auth.authorize(nil, options: nil, callback: { tokenDetails, error in
                guard let tokenDetails = tokenDetails else {
                    XCTFail("TokenDetails is nil"); done(); return
                }
                XCTAssertNotNil(tokenDetails.token)
                XCTAssertEqual(rest.auth.internal.method, ARTAuthMethod.token)

                publishTestMessage(rest, channelName: test.uniqueChannelName(), completion: { error in
                    XCTAssertNil(error)
                    XCTAssertEqual(rest.auth.internal.method, ARTAuthMethod.token)
                    XCTAssertEqual(rest.auth.tokenDetails?.token, tokenDetails.token)
                    done()
                })
            })
        }
    }

    // RSA10b
    func test__095__authorize__should_supports_all_TokenParams_and_AuthOptions() throws {
        let test = Test()
        let rest = ARTHttpClient(options: try AblyTests.commonAppSetup(for: test))

        waitUntil(timeout: testTimeout) { done in
            rest.auth.authorize(ARTTokenParams(), options: ARTAuthOptions(), callback: { _, error in
                guard let error = error as? ARTErrorInfo else {
                    fail("Error is nil"); done(); return
                }
                expect(error.localizedDescription).to(contain("no means to renew the token is provided"))
                done()
            })
        }
    }

    // RSA10e
    func test__096__authorize__should_use_the_requestToken_implementation() throws {
        let test = Test()
        let rest = ARTHttpClient(options: try AblyTests.commonAppSetup(for: test))

        var requestMethodWasCalled = false
        let block: @convention(block) (AspectInfo) -> Void = { _ in
            requestMethodWasCalled = true
        }

        let hook = ARTAuthInternal.aspect_hook(rest.auth.internal)
        // Adds a block of code after `requestToken` is triggered
        let token = try hook(#selector(ARTAuthInternal._requestToken(_:with:callback:)), [], unsafeBitCast(block, to: ARTAuthInternal.self))

        XCTAssertNotNil(token)

        waitUntil(timeout: testTimeout) { done in
            rest.auth.authorize(nil, options: nil, callback: { tokenDetails, error in
                XCTAssertNil(error)
                guard let tokenDetails = tokenDetails else {
                    XCTFail("TokenDetails is nil"); done(); return
                }
                expect(tokenDetails.token).toNot(beEmpty())
                done()
            })
        }

        XCTAssertTrue(requestMethodWasCalled)
    }

    // RSA10f
    func test__097__authorize__should_return_TokenDetails_with_valid_token_metadata() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.clientId = "client_string"
        let rest = ARTHttpClient(options: options)

        waitUntil(timeout: testTimeout) { done in
            rest.auth.authorize(nil, options: nil) { tokenDetails, error in
                XCTAssertNil(error)
                guard let tokenDetails = tokenDetails else {
                    XCTFail("TokenDetails is nil"); done(); return
                }
                expect(tokenDetails).to(beAnInstanceOf(ARTTokenDetails.self))
                expect(tokenDetails.token).toNot(beEmpty())
                expect(tokenDetails.expires!.timeIntervalSinceNow).to(beGreaterThan(tokenDetails.issued!.timeIntervalSinceNow))
                XCTAssertEqual(tokenDetails.clientId, options.clientId)
                done()
            }
        }
    }

    // RSA10g

    func test__099__authorize__on_subsequent_authorisations__should_store_the_AuthOptions_with_authUrl() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let rest = ARTHttpClient(options: options)
        let testHTTPExecutor = TestProxyHTTPExecutor(logger: .init(clientOptions: options))
        rest.internal.httpExecutor = testHTTPExecutor
        let auth = rest.auth

        let token = try getTestToken(for: test)
        let authOptions = ARTAuthOptions()
        // Use authUrl for authentication with plain text token response
        authOptions.authUrl = URL(string: "http://echo.ably.io")!
        authOptions.authParams = [URLQueryItem]()
        authOptions.authParams?.append(URLQueryItem(name: "type", value: "text"))
        authOptions.authParams?.append(URLQueryItem(name: "body", value: token))
        authOptions.authHeaders = ["X-Ably": "Test"]
        authOptions.queryTime = true

        waitUntil(timeout: testTimeout) { done in
            auth.authorize(nil, options: authOptions) { tokenDetails, error in
                XCTAssertNil(error)

                guard let tokenDetails = tokenDetails else {
                    XCTFail("TokenDetails is nil"); done(); return
                }
                XCTAssertEqual(tokenDetails.token, token)

                auth.authorize(nil, options: nil) { tokenDetails, error in
                    XCTAssertNil(error)

                    guard let tokenDetails = tokenDetails else {
                        XCTFail("TokenDetails is nil"); done(); return
                    }
                    XCTAssertEqual(testHTTPExecutor.requests.last?.url?.host, "echo.ably.io")
                    XCTAssertEqual(auth.internal.options.authUrl!.host, "echo.ably.io")
                    XCTAssertEqual(auth.internal.options.authHeaders!["X-Ably"], "Test")
                    XCTAssertEqual(tokenDetails.token, token)
                    XCTAssertFalse(auth.internal.options.queryTime)
                    done()
                }
            }
        }
    }

    func test__100__authorize__on_subsequent_authorisations__should_store_the_AuthOptions_with_authCallback() throws {
        let test = Test()
        let rest = ARTHttpClient(options: try AblyTests.commonAppSetup(for: test))
        let auth = rest.auth

        var authCallbackHasBeenInvoked = false

        let authOptions = ARTAuthOptions()
        authOptions.authCallback = { _, completion in
            authCallbackHasBeenInvoked = true
            completion(ARTTokenDetails(token: "token"), nil)
        }
        authOptions.useTokenAuth = true
        authOptions.queryTime = true

        waitUntil(timeout: testTimeout) { done in
            auth.authorize(nil, options: authOptions) { _, _ in
                XCTAssertTrue(authCallbackHasBeenInvoked)

                authCallbackHasBeenInvoked = false
                let authOptions2 = ARTAuthOptions()

                auth.internal.testSuite_forceTokenToExpire()

                auth.authorize(nil, options: authOptions2) { _, _ in
                    XCTAssertFalse(authCallbackHasBeenInvoked)
                    XCTAssertFalse(auth.internal.options.useTokenAuth)
                    XCTAssertFalse(auth.internal.options.queryTime)
                    done()
                }
            }
        }
    }

    func test__101__authorize__on_subsequent_authorisations__should_not_store_queryTime() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let rest = ARTHttpClient(options: options)
        let authOptions = ARTAuthOptions()
        authOptions.key = options.key
        authOptions.queryTime = true

        var serverTimeRequestWasMade = false
        let hook = rest.internal.testSuite_injectIntoMethod(after: #selector(rest.internal._time(withWrapperSDKAgents:completion:))) {
            serverTimeRequestWasMade = true
        }
        defer { hook.remove() }

        waitUntil(timeout: testTimeout) { done in
            // First time
            rest.auth.authorize(nil, options: authOptions) { tokenDetails, error in
                XCTAssertNil(error)
                XCTAssertNotNil(tokenDetails)
                XCTAssertTrue(serverTimeRequestWasMade)
                XCTAssertFalse(rest.auth.internal.options.queryTime)
                serverTimeRequestWasMade = false

                // Second time
                rest.auth.authorize(nil, options: nil) { tokenDetails, error in
                    XCTAssertNil(error)
                    XCTAssertNotNil(tokenDetails)
                    XCTAssertFalse(serverTimeRequestWasMade)
                    XCTAssertFalse(rest.auth.internal.options.queryTime)
                    done()
                }
            }
        }
    }

    func test__102__authorize__on_subsequent_authorisations__should_store_the_TokenParams() throws {
        let test = Test()
        let rest = ARTHttpClient(options: try AblyTests.commonAppSetup(for: test))

        let tokenParams = ARTTokenParams()
        tokenParams.clientId = ExpectedTokenParams.clientId
        tokenParams.ttl = ExpectedTokenParams.ttl as NSNumber
        tokenParams.capability = ExpectedTokenParams.capability

        waitUntil(timeout: testTimeout) { done in
            rest.auth.authorize(tokenParams, options: nil) { tokenDetails, error in
                XCTAssertNil(error)
                XCTAssertNotNil(tokenDetails)
                done()
            }
        }

        waitUntil(timeout: testTimeout) { done in
            delay(tokenParams.ttl as! TimeInterval + 1.0) {
                rest.auth.authorize(nil, options: nil) { tokenDetails, error in
                    XCTAssertNil(error)
                    guard let tokenDetails = tokenDetails else {
                        XCTFail("TokenDetails is nil"); done(); return
                    }
                    XCTAssertEqual(tokenDetails.clientId, ExpectedTokenParams.clientId)
                    expect(tokenDetails.issued!.addingTimeInterval(ExpectedTokenParams.ttl)).to(beCloseTo(tokenDetails.expires!))
                    XCTAssertEqual(tokenDetails.capability, ExpectedTokenParams.capability)
                    done()
                }
            }
        }
    }

    func test__103__authorize__on_subsequent_authorisations__should_use_configured_defaults_if_the_object_arguments_are_omitted() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let rest = ARTHttpClient(options: options)

        let tokenParams = ARTTokenParams()
        tokenParams.clientId = ExpectedTokenParams.clientId
        tokenParams.ttl = ExpectedTokenParams.ttl as NSNumber
        tokenParams.capability = ExpectedTokenParams.capability

        let authOptions = ARTAuthOptions()
        var authCallbackCalled = 0
        authOptions.authCallback = { tokenParams, completion in
            XCTAssertEqual(tokenParams.clientId, ExpectedTokenParams.clientId)
            XCTAssertEqual(tokenParams.ttl as? TimeInterval, ExpectedTokenParams.ttl)
            XCTAssertEqual(tokenParams.capability, ExpectedTokenParams.capability)
            authCallbackCalled += 1
            getTestTokenDetails(for: test, key: options.key, completion: completion)
        }

        waitUntil(timeout: testTimeout) { done in
            rest.auth.authorize(tokenParams, options: authOptions) { tokenDetails, error in
                XCTAssertNil(error)
                XCTAssertNotNil(tokenDetails)
                done()
            }
        }

        waitUntil(timeout: testTimeout) { done in
            rest.auth.authorize { tokenDetails, error in
                XCTAssertNil(error)
                XCTAssertNotNil(tokenDetails)
                done()
            }
        }

        XCTAssertEqual(authCallbackCalled, 2)
    }

    // RSA10h
    func test__098__authorize__should_use_the_configured_Auth_clientId__if_not_null__by_default() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        var rest = ARTHttpClient(options: options)

        // ClientId null
        waitUntil(timeout: testTimeout) { done in
            rest.auth.authorize(nil, options: nil) { tokenDetails, error in
                XCTAssertNil(error)
                guard let tokenDetails = tokenDetails else {
                    XCTFail("TokenDetails is nil"); done(); return
                }
                XCTAssertNil(tokenDetails.clientId)
                done()
            }
        }

        options.clientId = "client_string"
        rest = ARTHttpClient(options: options)

        // ClientId not null
        waitUntil(timeout: testTimeout) { done in
            rest.auth.authorize(nil, options: nil) { tokenDetails, error in
                XCTAssertNil(error)
                guard let tokenDetails = tokenDetails else {
                    XCTFail("TokenDetails is nil"); done(); return
                }
                XCTAssertEqual(tokenDetails.clientId, options.clientId)
                done()
            }
        }
    }

    // RSA10i

    func test__104__authorize__should_adhere_to_all_requirements_relating_to__TokenParams() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.clientId = "client_string"
        let rest = ARTHttpClient(options: options)

        let tokenParams = ARTTokenParams()
        tokenParams.clientId = ExpectedTokenParams.clientId
        tokenParams.ttl = ExpectedTokenParams.ttl as NSNumber
        tokenParams.capability = ExpectedTokenParams.capability

        waitUntil(timeout: testTimeout) { done in
            rest.auth.authorize(tokenParams, options: nil) { tokenDetails, error in
                XCTAssertNil(error)
                guard let tokenDetails = tokenDetails else {
                    XCTFail("TokenDetails is nil"); done(); return
                }
                expect(tokenDetails).to(beAnInstanceOf(ARTTokenDetails.self))
                expect(tokenDetails.token).toNot(beEmpty())
                XCTAssertEqual(tokenDetails.clientId, ExpectedTokenParams.clientId)
                expect(tokenDetails.issued!.addingTimeInterval(ExpectedTokenParams.ttl)).to(beCloseTo(tokenDetails.expires!))
                XCTAssertEqual(tokenDetails.capability, ExpectedTokenParams.capability)
                done()
            }
        }
    }

    func test__105__authorize__should_adhere_to_all_requirements_relating_to__authCallback() throws {
        let test = Test()
        var currentTokenRequest: ARTTokenRequest?

        var rest = ARTHttpClient(options: try AblyTests.commonAppSetup(for: test))
        rest.auth.createTokenRequest(nil, options: nil, callback: { tokenRequest, _ in
            currentTokenRequest = tokenRequest
        })
        expect(currentTokenRequest).toEventuallyNot(beNil(), timeout: testTimeout)

        currentTokenRequest = try XCTUnwrap(currentTokenRequest, "Token request is nil")

        let options = try AblyTests.clientOptions(for: test)
        options.authCallback = { _, completion in
            completion(currentTokenRequest!, nil)
        }

        rest = ARTHttpClient(options: options)
        waitUntil(timeout: testTimeout) { done in
            rest.auth.authorize(nil, options: nil) { tokenDetails, error in
                XCTAssertNil(error)
                guard let tokenDetails = tokenDetails else {
                    XCTFail("TokenDetails is nil"); done(); return
                }
                expect(tokenDetails).to(beAnInstanceOf(ARTTokenDetails.self))
                expect(tokenDetails.token).toNot(beEmpty())
                expect(tokenDetails.expires!.timeIntervalSinceNow).to(beGreaterThan(tokenDetails.issued!.timeIntervalSinceNow))
                done()
            }
        }
    }

    func test__106__authorize__should_adhere_to_all_requirements_relating_to__authUrl() {
        let options = ARTClientOptions()
        options.authUrl = URL(string: "http://echo.ably.io")!

        let rest = ARTHttpClient(options: options)
        waitUntil(timeout: testTimeout) { done in
            rest.auth.authorize(nil, options: nil) { tokenDetails, error in
                guard let error = error as? ARTErrorInfo else {
                    fail("Error is nil"); done(); return
                }
                XCTAssertEqual(error.statusCode, 400) // Bad request
                XCTAssertNil(tokenDetails)
                done()
            }
        }
    }

    func test__107__authorize__should_adhere_to_all_requirements_relating_to__authUrl_with_json() throws {
        let test = Test()

        let tokenDetails = try XCTUnwrap(getTestTokenDetails(for: test), "TokenDetails is empty")
        let tokenDetailsData = try XCTUnwrap(createJsonEncoder().encode(tokenDetails), "Couldn't encode token details")
        let tokenDetailsJSON = try XCTUnwrap(String(data: tokenDetailsData, encoding: .utf8), "JSON TokenDetails is empty")

        let options = ARTClientOptions()
        // Use authUrl for authentication with JSON TokenDetails response
        options.authUrl = URL(string: "http://echo.ably.io")!
        options.authParams = [URLQueryItem]()
        options.authParams?.append(URLQueryItem(name: "type", value: "json"))
        options.authParams?.append(URLQueryItem(name: "body", value: "[]"))
        var rest = ARTHttpClient(options: options)

        // Invalid TokenDetails
        waitUntil(timeout: testTimeout) { done in
            rest.auth.authorize(nil, options: nil) { tokenDetails, error in
                guard let error = error else {
                    fail("Error is nil"); done(); return
                }
                XCTAssertEqual((error as! ARTErrorInfo).code, Int(ARTState.authUrlIncompatibleContent.rawValue))
                XCTAssertNil(tokenDetails)
                done()
            }
        }

        options.authParams?.removeLast()
        options.authParams?.append(URLQueryItem(name: "body", value: tokenDetailsJSON))
        rest = ARTHttpClient(options: options)

        // Valid token
        waitUntil(timeout: testTimeout) { done in
            rest.auth.authorize(nil, options: nil) { tokenDetails, error in
                XCTAssertNil(error)
                XCTAssertNotNil(tokenDetails)
                done()
            }
        }
    }

    // https://github.com/ably/ably-cocoa/issues/618
    func test__108__authorize__should_adhere_to_all_requirements_relating_to__authUrl_returning_TokenRequest_decodes_TTL_as_expected() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)

        var rest = ARTHttpClient(options: options)
        var tokenRequest: ARTTokenRequest!
        waitUntil(timeout: testTimeout) { done in
            let params = ARTTokenParams(clientId: "myClientId", nonce: "12345")
            XCTAssertNil(params.ttl)
            rest.auth.createTokenRequest(params, options: nil) { req, _ in
                XCTAssertNil(req!.ttl)
                tokenRequest = req!
                done()
            }
        }

        let tokenRequestData = try XCTUnwrap(createJsonEncoder().encode(tokenRequest), "Encode failure")
        let tokenRequestJSON = try XCTUnwrap(String(data: tokenRequestData, encoding: .utf8), "JSON Token Request is empty")

        options.authUrl = URL(string: "http://echo.ably.io")!
        options.authParams = [URLQueryItem]()
        options.authParams?.append(URLQueryItem(name: "type", value: "json"))
        options.authParams?.append(URLQueryItem(name: "body", value: tokenRequestJSON))
        options.key = nil
        rest = ARTHttpClient(options: options)

        waitUntil(timeout: testTimeout) { done in
            rest.auth.authorize(nil, options: nil) { tokenDetails, error in
                XCTAssertNil(error)
                XCTAssertNotNil(tokenDetails)
                XCTAssertEqual(tokenDetails?.clientId, "myClientId")
                done()
            }
        }
    }

    func test__109__authorize__should_adhere_to_all_requirements_relating_to__authUrl_with_plain_text() throws {
        let test = Test()
        let token = try getTestToken(for: test)
        let options = ARTClientOptions()
        // Use authUrl for authentication with plain text token response
        options.authUrl = URL(string: "http://echo.ably.io")!
        options.authParams = [URLQueryItem]()
        options.authParams?.append(URLQueryItem(name: "type", value: "text"))
        options.authParams?.append(URLQueryItem(name: "body", value: ""))
        var rest = ARTHttpClient(options: options)

        // Invalid token
        waitUntil(timeout: testTimeout) { done in
            rest.auth.authorize(nil, options: nil) { tokenDetails, error in
                XCTAssertNotNil(error)
                XCTAssertNil(tokenDetails)
                done()
            }
        }

        options.authParams?.removeLast()
        options.authParams?.append(URLQueryItem(name: "body", value: token))
        rest = ARTHttpClient(options: options)

        // Valid token
        waitUntil(timeout: testTimeout) { done in
            rest.auth.authorize(nil, options: nil) { tokenDetails, error in
                XCTAssertNil(error)
                XCTAssertNotNil(tokenDetails)
                done()
            }
        }
    }

    // RSA10j

    func test__110__authorize__when_TokenParams_and_AuthOptions_are_provided__should_supersede_configured_AuthOptions__using_key__even_if_arguments_objects_are_empty() throws {
        let test = Test()
        let defaultOptions = try AblyTests.clientOptions(for: test) // sandbox
        defaultOptions.key = "xxxx:xxxx"
        let rest = ARTHttpClient(options: defaultOptions)

        let authOptions = ARTAuthOptions()
        authOptions.key = try AblyTests.commonAppSetup(for: test).key // valid key
        let tokenParams = ARTTokenParams()
        tokenParams.ttl = 1.0

        waitUntil(timeout: testTimeout) { done in
            rest.auth.authorize(tokenParams, options: authOptions) { tokenDetails, error in
                XCTAssertNil(error)
                guard let issued = tokenDetails?.issued else {
                    fail("TokenDetails.issued is nil"); done(); return
                }
                guard let expires = tokenDetails?.expires else {
                    fail("TokenDetails.expires is nil"); done(); return
                }
                expect(issued).to(beCloseTo(expires, within: tokenParams.ttl as! TimeInterval + 0.1))
                delay(tokenParams.ttl as! TimeInterval + 0.1) {
                    done()
                }
            }
        }

        authOptions.key = nil
        // First time
        waitUntil(timeout: testTimeout) { done in
            rest.auth.authorize(nil, options: authOptions) { _, error in
                guard let error = error else {
                    fail("Error is nil"); done(); return
                }
                expect(error.localizedDescription).to(contain("no means to renew the token"))
                done()
            }
        }

        // Second time
        waitUntil(timeout: testTimeout) { done in
            rest.auth.authorize(nil, options: nil) { _, error in
                guard let error = error else {
                    fail("Error is nil"); done(); return
                }
                expect(error.localizedDescription).to(contain("no means to renew the token"))
                done()
            }
        }
    }

    func test__111__authorize__when_TokenParams_and_AuthOptions_are_provided__should_supersede_configured_AuthOptions__using_authUrl__even_if_arguments_objects_are_empty() throws {
        let test = Test()
        let rest = ARTHttpClient(options: try AblyTests.commonAppSetup(for: test))

        let testTokenDetails = try XCTUnwrap(getTestTokenDetails(for: test, ttl: 0.1))
        let tokenRequestData = try XCTUnwrap(createJsonEncoder().encode(testTokenDetails), "Encode failure")

        let authOptions = ARTAuthOptions()
        authOptions.authUrl = URL(string: "http://echo.ably.io")!
        authOptions.authParams = [URLQueryItem]()
        authOptions.authParams?.append(URLQueryItem(name: "type", value: "json"))
        authOptions.authParams?.append(URLQueryItem(name: "body", value: tokenRequestData.toUTF8String))
        authOptions.authHeaders = ["X-Ably": "Test"]

        waitUntil(timeout: testTimeout) { done in
            rest.auth.authorize(nil, options: authOptions) { tokenDetails, error in
                XCTAssertNil(error)
                guard let tokenDetails = tokenDetails else {
                    XCTFail("TokenDetails is nil"); done(); return
                }
                XCTAssertEqual(tokenDetails.token, testTokenDetails.token)
                XCTAssertNotNil(rest.auth.internal.options.authUrl)
                XCTAssertNotNil(rest.auth.internal.options.authParams)
                XCTAssertNotNil(rest.auth.internal.options.authHeaders)
                delay(0.1) { // force to use the authUrl again
                    done()
                }
            }
        }

        authOptions.authParams = nil
        authOptions.authHeaders = nil
        waitUntil(timeout: testTimeout) { done in
            rest.auth.authorize(nil, options: authOptions) { tokenDetails, error in
                guard let error = error as? ARTErrorInfo else {
                    fail("Error is nil"); done(); return
                }
                XCTAssertEqual(error.statusCode, 400)
                XCTAssertNil(tokenDetails)
                XCTAssertNil(rest.auth.internal.options.authParams)
                XCTAssertNil(rest.auth.internal.options.authHeaders)
                done()
            }
        }

        // Repeat
        waitUntil(timeout: testTimeout) { done in
            rest.auth.authorize(nil, options: nil) { tokenDetails, error in
                guard let error = error as? ARTErrorInfo else {
                    fail("Error is nil"); done(); return
                }
                XCTAssertEqual(error.statusCode, 400)
                XCTAssertNil(tokenDetails)
                XCTAssertNil(rest.auth.internal.options.authParams)
                XCTAssertNil(rest.auth.internal.options.authHeaders)
                done()
            }
        }

        authOptions.authUrl = nil
        waitUntil(timeout: testTimeout) { done in
            rest.auth.authorize(nil, options: authOptions) { tokenDetails, error in
                guard let error = error else {
                    fail("Error is nil"); done(); return
                }
                XCTAssertEqual(UInt((error as! ARTErrorInfo).code), ARTState.requestTokenFailed.rawValue)
                XCTAssertNil(tokenDetails)
                XCTAssertNil(rest.auth.internal.options.authUrl)
                XCTAssertNil(rest.auth.internal.options.authParams)
                XCTAssertNil(rest.auth.internal.options.authHeaders)
                done()
            }
        }

        // Repeat
        waitUntil(timeout: testTimeout) { done in
            rest.auth.authorize(nil, options: nil) { tokenDetails, error in
                guard let error = error else {
                    fail("Error is nil"); done(); return
                }
                XCTAssertEqual(UInt((error as! ARTErrorInfo).code), ARTState.requestTokenFailed.rawValue)
                XCTAssertNil(tokenDetails)
                XCTAssertNil(rest.auth.internal.options.authUrl)
                XCTAssertNil(rest.auth.internal.options.authParams)
                XCTAssertNil(rest.auth.internal.options.authHeaders)
                done()
            }
        }
    }

    func test__112__authorize__when_TokenParams_and_AuthOptions_are_provided__should_supersede_configured_AuthOptions__using_authCallback__even_if_arguments_objects_are_empty() throws {
        let test = Test()
        let rest = ARTHttpClient(options: try AblyTests.commonAppSetup(for: test))

        let testTokenDetails = ARTTokenDetails(token: "token", expires: Date(), issued: Date(), capability: nil, clientId: nil)
        var authCallbackHasBeenInvoked = false
        let authOptions = ARTAuthOptions()
        authOptions.authCallback = { _, completion in
            authCallbackHasBeenInvoked = true
            completion(testTokenDetails, nil)
        }

        waitUntil(timeout: testTimeout) { done in
            rest.auth.authorize(nil, options: authOptions) { tokenDetails, error in
                XCTAssertNil(error)
                XCTAssertEqual(tokenDetails?.token, "token")
                XCTAssertTrue(authCallbackHasBeenInvoked)
                XCTAssertNotNil(rest.auth.internal.options.authCallback)
                done()
            }
        }
        authCallbackHasBeenInvoked = false

        waitUntil(timeout: testTimeout) { done in
            rest.auth.authorize(nil, options: nil) { tokenDetails, error in
                XCTAssertNil(error)
                XCTAssertEqual(tokenDetails?.token, "token")
                XCTAssertTrue(authCallbackHasBeenInvoked)
                XCTAssertNotNil(rest.auth.internal.options.authCallback)
                done()
            }
        }
        authCallbackHasBeenInvoked = false

        authOptions.authCallback = nil
        waitUntil(timeout: testTimeout) { done in
            rest.auth.authorize(nil, options: authOptions) { tokenDetails, error in
                guard let error = error else {
                    fail("Error is nil"); done(); return
                }
                XCTAssertEqual(UInt((error as! ARTErrorInfo).code), ARTState.requestTokenFailed.rawValue)
                XCTAssertNil(tokenDetails)
                XCTAssertFalse(authCallbackHasBeenInvoked)
                XCTAssertNil(rest.auth.internal.options.authCallback)
                done()
            }
        }

        waitUntil(timeout: testTimeout) { done in
            rest.auth.authorize(nil, options: nil) { tokenDetails, error in
                guard let error = error else {
                    fail("Error is nil"); done(); return
                }
                XCTAssertEqual(UInt((error as! ARTErrorInfo).code), ARTState.requestTokenFailed.rawValue)
                XCTAssertNil(tokenDetails)
                XCTAssertFalse(authCallbackHasBeenInvoked)
                XCTAssertNil(rest.auth.internal.options.authCallback)
                done()
            }
        }
    }

    func test__113__authorize__when_TokenParams_and_AuthOptions_are_provided__should_supersede_configured_params_and_options_even_if_arguments_objects_are_empty() throws {
        let test = Test()
        let options = try AblyTests.clientOptions(for: test)
        options.key = "xxxx:xxxx"
        options.clientId = "client_string"
        let rest = ARTHttpClient(options: options)

        let tokenParams = ARTTokenParams(clientId: options.clientId)

        // Defaults
        waitUntil(timeout: testTimeout) { done in
            rest.auth.authorize(nil, options: nil) { tokenDetails, error in
                guard let error = error else {
                    fail("Error is nil"); done(); return
                }
                XCTAssertEqual((error as! ARTErrorInfo).code, ARTErrorCode.notFound.intValue)
                XCTAssertNil(tokenDetails)
                done()
            }
        }

        // Custom
        tokenParams.ttl = ExpectedTokenParams.ttl as NSNumber
        tokenParams.capability = ExpectedTokenParams.capability
        tokenParams.clientId = nil

        let authOptions = ARTAuthOptions()
        authOptions.key = try AblyTests.commonAppSetup(for: test).key
        authOptions.queryTime = true

        var serverTimeRequestCount = 0
        let hook = rest.internal.testSuite_injectIntoMethod(after: #selector(rest.internal._time(withWrapperSDKAgents:completion:))) {
            serverTimeRequestCount += 1
        }
        defer { hook.remove() }

        waitUntil(timeout: testTimeout) { done in
            rest.auth.authorize(tokenParams, options: authOptions) { tokenDetails, error in
                XCTAssertNil(error)
                guard let tokenDetails = tokenDetails else {
                    XCTFail("TokenDetails is nil"); done(); return
                }
                XCTAssertNil(tokenDetails.clientId)
                expect(tokenDetails.issued!.addingTimeInterval(ExpectedTokenParams.ttl)).to(beCloseTo(tokenDetails.expires!))
                XCTAssertEqual(tokenDetails.capability, ExpectedTokenParams.capability)
                XCTAssertEqual(serverTimeRequestCount, 1)
                done()
            }
        }

        rest.auth.internal.testSuite_forceTokenToExpire()

        // Subsequent authorisations
        waitUntil(timeout: testTimeout) { done in
            rest.auth.authorize(nil, options: nil) { tokenDetails, error in
                XCTAssertNil(error)
                guard let tokenDetails = tokenDetails else {
                    fail("TokenDetails is nil"); done(); return
                }
                XCTAssertNil(tokenDetails.clientId)
                expect(tokenDetails.issued!.addingTimeInterval(ExpectedTokenParams.ttl)).to(beCloseTo(tokenDetails.expires!))
                XCTAssertEqual(tokenDetails.capability, ExpectedTokenParams.capability)
                XCTAssertEqual(serverTimeRequestCount, 1)
                done()
            }
        }
    }

    func test__114__authorize__when_TokenParams_and_AuthOptions_are_provided__example__if_a_client_is_initialised_with_TokenParams_ttl_configured_with_a_custom_value__and_a_TokenParams_object_is_passed_in_as_an_argument_to__authorize_with_a_null_value_for_ttl__then_the_ttl_used_for_every_subsequent_authorization_will_be_null() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.defaultTokenParams = {
            $0.ttl = 0.1
            $0.clientId = "tester"
            return $0
        }(ARTTokenParams())

        let rest = ARTHttpClient(options: options)

        let testTokenParams = ARTTokenParams()
        testTokenParams.ttl = nil
        testTokenParams.clientId = nil

        waitUntil(timeout: testTimeout) { done in
            rest.auth.authorize(testTokenParams, options: nil) { tokenDetails, error in
                XCTAssertNil(error)
                guard let tokenDetails = tokenDetails else {
                    fail("TokenDetails is nil"); done(); return
                }
                guard let issued = tokenDetails.issued else {
                    fail("TokenDetails.issued is nil"); done(); return
                }
                guard let expires = tokenDetails.expires else {
                    fail("TokenDetails.expires is nil"); done(); return
                }
                XCTAssertNil(tokenDetails.clientId)
                // `ttl` when omitted, the default value is applied
                XCTAssertEqual(issued.addingTimeInterval(ARTDefault.ttl()), expires)
                done()
            }
        }

        // Subsequent authorization
        waitUntil(timeout: testTimeout) { done in
            rest.auth.authorize(nil, options: nil) { tokenDetails, error in
                XCTAssertNil(error)
                guard let tokenDetails = tokenDetails else {
                    fail("TokenDetails is nil"); done(); return
                }
                guard let issued = tokenDetails.issued else {
                    fail("TokenDetails.issued is nil"); done(); return
                }
                guard let expires = tokenDetails.expires else {
                    fail("TokenDetails.expires is nil"); done(); return
                }
                XCTAssertNil(tokenDetails.clientId)
                XCTAssertEqual(issued.addingTimeInterval(ARTDefault.ttl()), expires)
                done()
            }
        }
    }

    // RSA10k

    func test__115__authorize__server_time_offset__should_obtain_server_time_once_and_persist_the_offset_from_the_local_clock() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let rest = ARTHttpClient(options: options)

        let mockServerDate = Date().addingTimeInterval(120)
        rest.auth.internal.testSuite_returnValue(for: NSSelectorFromString("handleServerTime:"), with: mockServerDate)
        let currentDate = Date()

        var serverTimeRequestCount = 0
        let hook = rest.internal.testSuite_injectIntoMethod(after: #selector(rest.internal._time(withWrapperSDKAgents:completion:))) {
            serverTimeRequestCount += 1
        }
        defer { hook.remove() }

        let authOptions = ARTAuthOptions()
        authOptions.key = options.key
        authOptions.queryTime = true

        waitUntil(timeout: testTimeout) { done in
            rest.auth.authorize(nil, options: authOptions, callback: { tokenDetails, error in
                XCTAssertNil(error)
                guard tokenDetails != nil else {
                    fail("TokenDetails is nil"); done(); return
                }
                guard let timeOffset = rest.auth.internal.timeOffset?.doubleValue else {
                    fail("Server Time Offset is nil"); done(); return
                }
                XCTAssertNotEqual(timeOffset, 0)
                XCTAssertNotNil(rest.auth.internal.timeOffset)
                let calculatedServerDate = currentDate.addingTimeInterval(timeOffset)
                expect(calculatedServerDate).to(beCloseTo(mockServerDate, within: 0.9))
                XCTAssertEqual(serverTimeRequestCount, 1)
                done()
            })
        }

        rest.auth.internal.testSuite_forceTokenToExpire()

        waitUntil(timeout: testTimeout) { done in
            rest.auth.authorize(nil, options: nil) { tokenDetails, error in
                XCTAssertNil(error)
                guard tokenDetails != nil else {
                    fail("TokenDetails is nil"); done(); return
                }
                guard let timeOffset = rest.auth.internal.timeOffset?.doubleValue else {
                    fail("Server Time Offset is nil"); done(); return
                }
                XCTAssertNotEqual(timeOffset, 0)
                let calculatedServerDate = currentDate.addingTimeInterval(timeOffset)
                expect(calculatedServerDate).to(beCloseTo(mockServerDate, within: 0.9))
                XCTAssertEqual(serverTimeRequestCount, 1)
                done()
            }
        }
    }

    func test__116__authorize__server_time_offset__should_be_consistent_the_timestamp_request_with_the_server_time() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let rest = ARTHttpClient(options: options)

        let mockServerDate = Date().addingTimeInterval(120)
        rest.auth.internal.testSuite_returnValue(for: NSSelectorFromString("handleServerTime:"), with: mockServerDate)

        var serverTimeRequestCount = 0
        let hook = rest.internal.testSuite_injectIntoMethod(after: #selector(rest.internal._time(withWrapperSDKAgents:completion:))) {
            serverTimeRequestCount += 1
        }
        defer { hook.remove() }

        let authOptions = ARTAuthOptions()
        authOptions.key = options.key
        authOptions.queryTime = true

        waitUntil(timeout: testTimeout) { done in
            rest.auth.createTokenRequest(nil, options: authOptions) { tokenRequest, error in
                XCTAssertNil(error)
                guard let tokenRequest = tokenRequest else {
                    fail("TokenRequest is nil"); done(); return
                }
                guard let timeOffset = rest.auth.internal.timeOffset?.doubleValue else {
                    fail("Server Time Offset is nil"); done(); return
                }
                XCTAssertNotEqual(timeOffset, 0)
                expect(mockServerDate.timeIntervalSinceNow).to(beCloseTo(timeOffset, within: 0.1))
                expect(tokenRequest.timestamp).to(beCloseTo(mockServerDate))
                XCTAssertEqual(serverTimeRequestCount, 1)
                done()
            }
        }
    }

    func test__117__authorize__server_time_offset__should_be_possible_by_lib_Client_to_discard_the_cached_local_clock_offset() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.queryTime = true
        let rest = ARTHttpClient(options: options)

        var serverTimeRequestCount = 0
        let hook = rest.internal.testSuite_injectIntoMethod(after: #selector(rest.internal._time(withWrapperSDKAgents:completion:))) {
            serverTimeRequestCount += 1
        }
        defer { hook.remove() }

        waitUntil(timeout: testTimeout) { done in
            rest.auth.authorize(nil, options: nil) { tokenDetails, error in
                XCTAssertNil(error)
                guard let tokenDetails = tokenDetails else {
                    fail("TokenDetails is nil"); done(); return
                }
                guard let timeOffset = rest.auth.internal.timeOffset?.doubleValue else {
                    fail("Server Time Offset is nil"); done(); return
                }
                expect(timeOffset).toNot(beCloseTo(0))
                let calculatedServerDate = Date().addingTimeInterval(timeOffset)
                expect(tokenDetails.expires).to(beCloseTo(calculatedServerDate.addingTimeInterval(ARTDefault.ttl()), within: 1.0))
                XCTAssertEqual(serverTimeRequestCount, 1)
                done()
            }
        }

        #if os(iOS) || os(tvOS) || os(watchOS)
            NotificationCenter.default.post(name: UIApplication.significantTimeChangeNotification, object: nil)
        #else
            NotificationCenter.default.post(name: .NSSystemClockDidChange, object: nil)
        #endif

        rest.auth.internal.testSuite_forceTokenToExpire()

        waitUntil(timeout: testTimeout) { done in
            rest.auth.authorize(nil, options: nil) { tokenDetails, error in
                XCTAssertNil(error)
                guard tokenDetails != nil else {
                    fail("TokenDetails is nil"); done(); return
                }
                XCTAssertNil(rest.auth.internal.timeOffset)
                XCTAssertEqual(serverTimeRequestCount, 1)
                done()
            }
        }
    }

    func test__118__authorize__server_time_offset__should_use_the_local_clock_offset_to_calculate_the_server_time() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let rest = ARTHttpClient(options: options)

        let authOptions = ARTAuthOptions()
        authOptions.key = options.key
        authOptions.queryTime = false

        let fakeOffset: TimeInterval = 60 // 1 minute
        rest.auth.internal.setTimeOffset(fakeOffset)

        waitUntil(timeout: testTimeout) { done in
            rest.auth.createTokenRequest(nil, options: authOptions) { tokenRequest, error in
                XCTAssertNil(error)
                guard let tokenRequest = tokenRequest else {
                    fail("TokenRequest is nil"); done(); return
                }
                guard let timeOffset = rest.auth.internal.timeOffset?.doubleValue else {
                    fail("Server Time Offset is nil"); done(); return
                }
                XCTAssertEqual(timeOffset, fakeOffset)
                let calculatedServerDate = Date().addingTimeInterval(timeOffset)
                expect(tokenRequest.timestamp).to(beCloseTo(calculatedServerDate, within: 0.5))
                done()
            }
        }
    }

    func test__119__authorize__server_time_offset__should_request_server_time_when_queryTime_is_true_even_if_the_time_offset_is_assigned() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let rest = ARTHttpClient(options: options)

        var serverTimeRequestCount = 0
        let hook = rest.internal.testSuite_injectIntoMethod(after: #selector(rest.internal._time)) {
            serverTimeRequestCount += 1
        }
        defer { hook.remove() }

        let fakeOffset: TimeInterval = 60 // 1 minute
        rest.auth.internal.setTimeOffset(fakeOffset)

        let authOptions = ARTAuthOptions()
        authOptions.key = options.key
        authOptions.queryTime = true

        waitUntil(timeout: testTimeout) { done in
            rest.auth.authorize(nil, options: authOptions) { tokenDetails, error in
                XCTAssertNil(error)
                XCTAssertNotNil(tokenDetails)
                XCTAssertEqual(serverTimeRequestCount, 1)
                guard let timeOffset = rest.auth.internal.timeOffset?.doubleValue else {
                    fail("Server Time Offset is nil"); done(); return
                }
                XCTAssertNotEqual(timeOffset, fakeOffset)
                done()
            }
        }
    }

    func test__120__authorize__server_time_offset__should_discard_the_time_offset_in_situations_in_which_it_may_have_been_invalidated() throws {
        let test = Test()
        let rest = ARTHttpClient(options: try AblyTests.commonAppSetup(for: test))

        var discardTimeOffsetCallCount = 0
        let hook = rest.auth.internal.testSuite_injectIntoMethod(after: #selector(rest.auth.internal.discardTimeOffset)) {
            discardTimeOffsetCallCount += 1
        }
        defer { hook.remove() }

        #if os(iOS) || os(tvOS) || os(watchOS)
            // Force notification
            NotificationCenter.default.post(name: UIApplication.significantTimeChangeNotification, object: nil)

            expect(discardTimeOffsetCallCount).toEventually(equal(1), timeout: testTimeout)

            // Force notification
            NotificationCenter.default.post(name: NSLocale.currentLocaleDidChangeNotification, object: nil)
        #else
            // Force notification
            NotificationCenter.default.post(name: NSNotification.Name.NSSystemClockDidChange, object: nil)

            expect(discardTimeOffsetCallCount).toEventually(equal(1), timeout: testTimeout)

            // Force notification
            NotificationCenter.default.post(name: NSLocale.currentLocaleDidChangeNotification, object: nil)
        #endif

        expect(discardTimeOffsetCallCount).toEventually(equal(2), timeout: testTimeout)
    }

    func test__121__authorize__two_consecutive_authorizations__using_REST__should_call_each_authorize_callback() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.useTokenAuth = true
        let rest = ARTHttpClient(options: options)

        var tokenDetailsFirst: ARTTokenDetails?
        var tokenDetailsLast: ARTTokenDetails?
        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)
            rest.auth.authorize { tokenDetails, error in
                if let error = error {
                    fail(error.localizedDescription); partialDone(); return
                }
                XCTAssertNotNil(tokenDetails)
                if tokenDetailsFirst == nil {
                    tokenDetailsFirst = tokenDetails
                } else {
                    tokenDetailsLast = tokenDetails
                }
                partialDone()
            }
            rest.auth.authorize { tokenDetails, error in
                if let error = error {
                    fail(error.localizedDescription); partialDone(); return
                }
                XCTAssertNotNil(tokenDetails)
                if tokenDetailsFirst == nil {
                    tokenDetailsFirst = tokenDetails
                } else {
                    tokenDetailsLast = tokenDetails
                }
                partialDone()
            }
        }

        XCTAssertNotEqual(tokenDetailsFirst?.token, tokenDetailsLast?.token)
        XCTAssertTrue(rest.auth.tokenDetails === tokenDetailsLast)
        XCTAssertEqual(rest.auth.tokenDetails?.token, tokenDetailsLast?.token)
    }

    func test__122__authorize__two_consecutive_authorizations__using_Realtime_and_connection_is_CONNECTING__should_call_each_Realtime_authorize_callback() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.useTokenAuth = true
        let realtime = AblyTests.newRealtime(options).client
        defer { realtime.close(); realtime.dispose() }

        var connectedStateCount = 0
        realtime.connection.on(.connected) { _ in
            connectedStateCount += 1
        }

        var tokenDetailsLast: ARTTokenDetails?
        var didCancelAuthorization = false
        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)
            let callback: (ARTTokenDetails?, Error?) -> Void = { tokenDetails, error in
                if let error = error {
                    if (error as NSError).code == URLError.cancelled.rawValue {
                        XCTAssertNil(tokenDetails)
                        didCancelAuthorization = true
                    } else {
                        fail(error.localizedDescription); partialDone(); return
                    }
                } else {
                    XCTAssertNotNil(tokenDetails)
                    tokenDetailsLast = tokenDetails
                }
                partialDone()
            }
            // One of them will be canceled by the connection:
            realtime.auth.authorize(callback)
            realtime.auth.authorize(callback)
        }

        XCTAssertTrue(didCancelAuthorization)
        XCTAssertTrue(realtime.auth.tokenDetails === tokenDetailsLast)
        XCTAssertEqual(realtime.auth.tokenDetails?.token, tokenDetailsLast?.token)

        if let transport = realtime.internal.transport as? TestProxyTransport, let query = transport.lastUrl?.query {
            expect(query).to(haveParam("accessToken", withValue: realtime.auth.tokenDetails?.token ?? ""))
        } else {
            fail("MockTransport is not working")
        }

        XCTAssertEqual(connectedStateCount, 1)
    }

    func test__123__authorize__two_consecutive_authorizations__using_Realtime_and_connection_is_CONNECTED__should_call_each_Realtime_authorize_callback() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.useTokenAuth = true
        let realtime = ARTRealtimeClient(options: options)
        defer { realtime.close(); realtime.dispose() }

        waitUntil(timeout: testTimeout) { done in
            realtime.connection.once(.connected) { _ in
                done()
            }
        }

        var tokenDetailsFirst: ARTTokenDetails?
        var tokenDetailsLast: ARTTokenDetails?
        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)
            realtime.auth.authorize { tokenDetails, error in
                if let error = error {
                    fail(error.localizedDescription); partialDone(); return
                }
                XCTAssertNotNil(tokenDetails)
                if tokenDetailsFirst == nil {
                    tokenDetailsFirst = tokenDetails
                } else {
                    tokenDetailsLast = tokenDetails
                }
                partialDone()
            }
            realtime.auth.authorize { tokenDetails, error in
                if let error = error {
                    fail(error.localizedDescription); partialDone(); return
                }
                XCTAssertNotNil(tokenDetails)
                if tokenDetailsFirst == nil {
                    tokenDetailsFirst = tokenDetails
                } else {
                    tokenDetailsLast = tokenDetails
                }
                partialDone()
            }
        }

        XCTAssertNotEqual(tokenDetailsFirst?.token, tokenDetailsLast?.token)
        XCTAssertTrue(realtime.auth.tokenDetails === tokenDetailsLast)
        XCTAssertEqual(realtime.auth.tokenDetails?.token, tokenDetailsLast?.token)
    }

    func test__124__TokenParams__timestamp__if_explicitly_set__should_be_returned_by_the_getter() {
        let params = ARTTokenParams()
        params.timestamp = Date(timeIntervalSince1970: 123)
        XCTAssertEqual(params.timestamp, Date(timeIntervalSince1970: 123))
    }

    func test__125__TokenParams__timestamp__if_explicitly_set__the_value_should_stick() {
        let params = ARTTokenParams()
        params.timestamp = Date()

        waitUntil(timeout: testTimeout) { done in
            let now = Double(NSDate().artToIntegerMs())
            guard let timestamp = params.timestamp else {
                fail("timestamp is nil"); done(); return
            }
            let firstParamsTimestamp = Double((timestamp as NSDate).artToIntegerMs())
            expect(firstParamsTimestamp).to(beCloseTo(now, within: 2.5))
            delay(0.25) {
                XCTAssertEqual(Double((timestamp as NSDate).artToIntegerMs()), firstParamsTimestamp)
                done()
            }
        }
    }

    // https://github.com/ably/ably-cocoa/pull/508#discussion_r82577728
    func test__126__TokenParams__timestamp__object_has_no_timestamp_value_unless_explicitly_set() {
        let params = ARTTokenParams()
        XCTAssertNil(params.timestamp)
    }

    // RTC8
    func test__127__Reauth__should_use_authorize__force__true___to_reauth_with_a_token_with_a_different_set_of_capabilities() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let initialToken = try getTestToken(for: test, clientId: "tester", capability: "{\"restricted\":[\"*\"]}")
        options.token = initialToken
        let realtime = ARTRealtimeClient(options: options)
        defer { realtime.dispose(); realtime.close() }
        let channel = realtime.channels.get(test.uniqueChannelName())

        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                guard let error = error else {
                    fail("Error is nil"); done(); return
                }
                XCTAssertEqual(error.code, ARTErrorCode.operationNotPermittedWithProvidedCapability.intValue)
                done()
            }
        }

        let tokenParams = ARTTokenParams()
        tokenParams.capability = "{\"\(channel.name)\":[\"*\"]}"
        tokenParams.clientId = "tester"

        waitUntil(timeout: testTimeout) { done in
            realtime.auth.authorize(tokenParams, options: nil) { tokenDetails, error in
                XCTAssertNil(error)
                XCTAssertNotNil(tokenDetails)
                done()
            }
        }

        XCTAssertNotEqual(realtime.auth.tokenDetails?.token, initialToken)
        XCTAssertEqual(realtime.auth.tokenDetails?.capability, tokenParams.capability)

        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                XCTAssertNil(error)
                done()
            }
        }
    }

    // RTC8
    func test__128__Reauth__for_a_token_change_that_fails_due_to_an_incompatible_token__which_should_result_in_the_connection_entering_the_FAILED_state() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.clientId = "tester"
        options.useTokenAuth = true
        let realtime = ARTRealtimeClient(options: options)
        defer { realtime.dispose(); realtime.close() }

        waitUntil(timeout: testTimeout) { done in
            realtime.connection.on(.connected) { stateChange in
                XCTAssertNil(stateChange.reason)
                done()
            }
        }

        let tokenParams = ARTTokenParams()
        tokenParams.capability = "{\"restricted\":[\"*\"]}"
        tokenParams.clientId = "secret"

        waitUntil(timeout: testTimeout) { done in
            realtime.auth.authorize(tokenParams, options: nil) { tokenDetails, error in
                guard let error = error else {
                    fail("Error is nil"); done(); return
                }
                XCTAssertEqual((error as! ARTErrorInfo).code, ARTErrorCode.incompatibleCredentials.intValue)
                XCTAssertNil(tokenDetails)
                done()
            }
        }

        let initialToken = try XCTUnwrap(realtime.auth.tokenDetails?.token, "TokenDetails is nil")

        expect(realtime.connection.state).toEventually(equal(ARTRealtimeConnectionState.connected), timeout: testTimeout)
        XCTAssertEqual(realtime.auth.tokenDetails?.token, initialToken)
        XCTAssertNotEqual(realtime.auth.tokenDetails?.capability, tokenParams.capability)
    }

    // TK2d
    func test__129__TokenParams__timestamp_should_not_be_a_member_of_any_default_token_params() throws {
        let test = Test()
        let rest = ARTHttpClient(options: try AblyTests.commonAppSetup(for: test))
        waitUntil(timeout: testTimeout) { done in
            rest.auth.authorize(nil, options: nil) { _, error in
                XCTAssertNil(error)
                guard let defaultTokenParams = rest.auth.internal.options.defaultTokenParams else {
                    fail("DefaultTokenParams is nil"); done(); return
                }
                XCTAssertNil(defaultTokenParams.timestamp)

                var defaultTokenParamsCallCount = 0
                let hook = rest.auth.internal.options.testSuite_injectIntoMethod(after: NSSelectorFromString("defaultTokenParams")) {
                    defaultTokenParamsCallCount += 1
                }
                defer { hook.remove() }

                let newTokenParams = ARTTokenParams(options: rest.auth.internal.options)
                expect(defaultTokenParamsCallCount) > 0

                newTokenParams.timestamp = Date()
                XCTAssertNotNil(newTokenParams.timestamp)
                XCTAssertNil(defaultTokenParams.timestamp) // remain nil
                done()
            }
        }
    }

    // TE6

    enum TestCase_ReusableTestsTestTokenRequestFromJson {
        case accepts_a_string__which_should_be_interpreted_as_JSON
        case accepts_a_NSDictionary
    }

    func reusableTestsTestTokenRequestFromJson(_ json: String, testCase: TestCase_ReusableTestsTestTokenRequestFromJson, beforeEach contextBeforeEach: (() -> Void)? = nil, afterEach contextAfterEach: (() -> Void)? = nil, check: @escaping (_ request: ARTTokenRequest) -> Void) {
        func test__accepts_a_string__which_should_be_interpreted_as_JSON() {
            contextBeforeEach?()

            check(try! ARTTokenRequest.fromJson(json as ARTJsonCompatible))

            contextAfterEach?()
        }

        func test__accepts_a_NSDictionary() {
            contextBeforeEach?()

            let data = json.data(using: String.Encoding.utf8)!
            let dict = try! JSONSerialization.jsonObject(with: data, options: .mutableLeaves) as! NSDictionary
            check(try! ARTTokenRequest.fromJson(dict))

            contextAfterEach?()
        }

        switch testCase {
        case .accepts_a_string__which_should_be_interpreted_as_JSON:
            test__accepts_a_string__which_should_be_interpreted_as_JSON()
        case .accepts_a_NSDictionary:
            test__accepts_a_NSDictionary()
        }
    }

    func reusableTestsWrapper__TokenRequest__fromJson__with_TTL__reusableTestsTestTokenRequestFromJson(testCase: TestCase_ReusableTestsTestTokenRequestFromJson) {
        reusableTestsTestTokenRequestFromJson("{" +
            "    \"clientId\":\"myClientId\"," +
            "    \"mac\":\"4rr4J+JzjiCL1DoS8wq7k11Z4oTGCb1PoeN+yGjkaH4=\"," +
            "    \"capability\":\"{\\\"test\\\":[\\\"publish\\\"]}\"," +
            "    \"ttl\":42000," +
            "    \"timestamp\":1479087321934," +
            "    \"keyName\":\"xxxxxx.yyyyyy\"," +
            "    \"nonce\":\"7830658976108826\"" +
            "}", testCase: testCase) { request in
                XCTAssertEqual(request.clientId, "myClientId")
                XCTAssertEqual(request.mac, "4rr4J+JzjiCL1DoS8wq7k11Z4oTGCb1PoeN+yGjkaH4=")
                XCTAssertEqual(request.capability, "{\"test\":[\"publish\"]}")
                XCTAssertEqual(request.ttl as? TimeInterval, TimeInterval(42))
                XCTAssertEqual(request.timestamp, Date(timeIntervalSince1970: 1_479_087_321.934))
                XCTAssertEqual(request.keyName, "xxxxxx.yyyyyy")
                XCTAssertEqual(request.nonce, "7830658976108826")
            }
    }

    func test__132__TokenRequest__fromJson__with_TTL__accepts_a_string__which_should_be_interpreted_as_JSON() {
        reusableTestsWrapper__TokenRequest__fromJson__with_TTL__reusableTestsTestTokenRequestFromJson(testCase: .accepts_a_string__which_should_be_interpreted_as_JSON)
    }

    func test__133__TokenRequest__fromJson__with_TTL__accepts_a_NSDictionary() {
        reusableTestsWrapper__TokenRequest__fromJson__with_TTL__reusableTestsTestTokenRequestFromJson(testCase: .accepts_a_NSDictionary)
    }

    func reusableTestsWrapper__TokenRequest__fromJson__without_TTL__reusableTestsTestTokenRequestFromJson(testCase: TestCase_ReusableTestsTestTokenRequestFromJson) {
        reusableTestsTestTokenRequestFromJson("{" +
            "    \"mac\":\"4rr4J+JzjiCL1DoS8wq7k11Z4oTGCb1PoeN+yGjkaH4=\"," +
            "    \"capability\":\"{\\\"test\\\":[\\\"publish\\\"]}\"," +
            "    \"timestamp\":1479087321934," +
            "    \"keyName\":\"xxxxxx.yyyyyy\"," +
            "    \"nonce\":\"7830658976108826\"" +
            "}", testCase: testCase) { request in
                XCTAssertNil(request.clientId)
                XCTAssertEqual(request.mac, "4rr4J+JzjiCL1DoS8wq7k11Z4oTGCb1PoeN+yGjkaH4=")
                XCTAssertEqual(request.capability, "{\"test\":[\"publish\"]}")
                XCTAssertNil(request.ttl)
                XCTAssertEqual(request.timestamp, Date(timeIntervalSince1970: 1_479_087_321.934))
                XCTAssertEqual(request.keyName, "xxxxxx.yyyyyy")
                XCTAssertEqual(request.nonce, "7830658976108826")
            }
    }

    func test__134__TokenRequest__fromJson__without_TTL__accepts_a_string__which_should_be_interpreted_as_JSON() {
        reusableTestsWrapper__TokenRequest__fromJson__without_TTL__reusableTestsTestTokenRequestFromJson(testCase: .accepts_a_string__which_should_be_interpreted_as_JSON)
    }

    func test__135__TokenRequest__fromJson__without_TTL__accepts_a_NSDictionary() {
        reusableTestsWrapper__TokenRequest__fromJson__without_TTL__reusableTestsTestTokenRequestFromJson(testCase: .accepts_a_NSDictionary)
    }

    func test__130__TokenRequest__fromJson__rejects_invalid_JSON() {
        expect { try ARTTokenRequest.fromJson("not JSON" as ARTJsonCompatible) }.to(throwError())
    }

    func test__131__TokenRequest__fromJson__rejects_non_object_JSON() {
        expect { try ARTTokenRequest.fromJson("[]" as ARTJsonCompatible) }.to(throwError())
    }

    // TD7

    func test__136__TokenDetails__fromJson__accepts_a_string__which_should_be_interpreted_as_JSON() {
        check(try! ARTTokenDetails.fromJson(json as ARTJsonCompatible))
    }

    func test__137__TokenDetails__fromJson__accepts_a_NSDictionary() {
        let data = json.data(using: String.Encoding.utf8)!
        let dict = try! JSONSerialization.jsonObject(with: data, options: .mutableLeaves) as! NSDictionary
        check(try! ARTTokenDetails.fromJson(dict))
    }

    func test__138__TokenDetails__fromJson__rejects_invalid_JSON() {
        expect { try ARTTokenDetails.fromJson("not JSON" as ARTJsonCompatible) }.to(throwError())
    }

    func test__139__TokenDetails__fromJson__rejects_non_object_JSON() {
        expect { try ARTTokenDetails.fromJson("[]" as ARTJsonCompatible) }.to(throwError())
    }

    func test__140__JWT_and_realtime__client_initialized_with_a_JWT_token_in_ClientOptions__with_valid_credentials__pulls_stats_successfully() throws {
        let test = Test()
        let options = try AblyTests.clientOptions(for: test)
        options.token = try getJWTToken(for: test)
        let client = AblyTests.newRealtime(options).client
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            client.stats { _, error in
                XCTAssertNil(error)
                done()
            }
        }
    }

    func test__141__JWT_and_realtime__client_initialized_with_a_JWT_token_in_ClientOptions__with_invalid_credentials__fails_to_connect_with_reason__invalid_signature_() throws {
        let test = Test()
        let options = try AblyTests.clientOptions(for: test)
        options.token = try getJWTToken(for: test, invalid: true)
        options.autoConnect = false
        let client = AblyTests.newRealtime(options).client
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.failed) { stateChange in
                guard let reason = stateChange.reason else {
                    fail("Reason error is nil"); done(); return
                }
                XCTAssertEqual(reason.code, ARTErrorCode.invalidJwtFormat.intValue) // Error verifying JWT; err = Unexpected exception decoding token; err = signature verification failed. (See https://help.ably.io/error/40144 for help.)
                done()
            }
            client.connect()
        }
    }

    // RSA8g RSA8c

    func test__142__JWT_and_realtime__when_using_authUrl__with_valid_credentials__fetches_a_channels_and_posts_a_message() throws {
        let test = Test()
        let keys = try getKeys(for: test)

        let options = try createAuthUrlTestsOptions(for: test)
        options.authParams = [URLQueryItem]()
        options.authParams?.append(URLQueryItem(name: "keyName", value: keys["keyName"]))
        options.authParams?.append(URLQueryItem(name: "keySecret", value: keys["keySecret"]))
        let client = ARTRealtimeClient(options: options)

        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected, callback: { _ in
                let channel = client.channels.get(channelName)
                channel.publish(messageName, data: nil, callback: { error in
                    XCTAssertNil(error)
                    done()
                })
            })
            client.connect()
        }
    }

    func test__143__JWT_and_realtime__when_using_authUrl__with_wrong_credentials__fails_to_connect_with_reason__invalid_signature_() throws {
        let test = Test()
        let keys = try getKeys(for: test)

        let options = try createAuthUrlTestsOptions(for: test)
        options.authParams = [URLQueryItem]()
        options.authParams?.append(URLQueryItem(name: "keyName", value: keys["keyName"]))
        options.authParams?.append(URLQueryItem(name: "keySecret", value: "INVALID"))

        let client = ARTRealtimeClient(options: options)
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.disconnected) { stateChange in
                guard let reason = stateChange.reason else {
                    fail("Reason error is nil"); done(); return
                }
                XCTAssertEqual(reason.code, ARTErrorCode.invalidJwtFormat.intValue) // Error verifying JWT; err = Unexpected exception decoding token; err = signature verification failed. (See https://help.ably.io/error/40144 for help.)
                done()
            }
            client.connect()
        }
    }

    func test__144__JWT_and_realtime__when_using_authUrl__when_token_expires__receives_a_40142_error_from_the_server() throws {
        let test = Test()
        let keys = try getKeys(for: test)

        let tokenDuration = 5.0

        let options = try createAuthUrlTestsOptions(for: test)
        options.authParams = [URLQueryItem]()
        options.authParams?.append(URLQueryItem(name: "keyName", value: keys["keyName"]))
        options.authParams?.append(URLQueryItem(name: "keySecret", value: keys["keySecret"]))
        options.authParams?.append(URLQueryItem(name: "expiresIn", value: String(UInt(tokenDuration))))

        let client = ARTRealtimeClient(options: options)
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { stateChange in
                client.connection.once(.disconnected) { stateChange in
                    XCTAssertEqual(stateChange.reason?.code, ARTErrorCode.tokenExpired.intValue)
                    expect(stateChange.reason?.description).to(contain("token"))
                    expect(stateChange.reason?.description).to(contain("expire"))
                    done()
                }
            }
            client.connect()
        }
    }

    // RTC8a4

    func test__145__JWT_and_realtime__when_using_authUrl__when_the_server_sends_and_AUTH_protocol_message__client_reauths_correctly_without_going_through_a_disconnection() throws {
        let test = Test()
        let keys = try getKeys(for: test)

        // The server sends an AUTH protocol message 30 seconds before a token expires
        // We create a token that lasts 35 seconds, so there's room to receive the AUTH message
        let tokenDuration = 35.0

        let options = try createAuthUrlTestsOptions(for: test)
        options.authParams = [URLQueryItem]()
        options.authParams?.append(URLQueryItem(name: "keyName", value: keys["keyName"]))
        options.authParams?.append(URLQueryItem(name: "keySecret", value: keys["keySecret"]))
        options.authParams?.append(URLQueryItem(name: "expiresIn", value: String(UInt(tokenDuration))))
        options.autoConnect = false // Prevent auto connection so we can set the transport proxy
        options.testOptions.transportFactory = TestProxyTransportFactory()

        let client = ARTRealtimeClient(options: options)
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { _ in
                let originalToken = client.auth.tokenDetails?.token
                let transport = client.internal.transport as! TestProxyTransport

                client.connection.once(.update) { _ in
                    XCTAssertEqual(transport.protocolMessagesReceived.filter { $0.action == .auth }.count, 1)
                    XCTAssertNotEqual(originalToken, client.auth.tokenDetails?.token)
                    done()
                }
            }
            client.connect()
        }
    }

    // RSA8g

    func test__146__JWT_and_realtime__when_using_authCallback__with_valid_credentials__pulls_stats_successfully() throws {
        let test = Test()
        let options = try AblyTests.clientOptions(for: test)
        options.authCallback = { _, completion in
            let token: ARTTokenDetails
            do {
                token = .init(token: try getJWTToken(for: test)!)
            } catch {
                XCTFail("Failed to get JWT: \(error)")
                completion(nil, error)
                return
            }
            completion(token, nil)
        }
        let client = ARTRealtimeClient(options: options)
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            client.stats { _, error in
                XCTAssertNil(error)
                done()
            }
        }
    }

    func test__147__JWT_and_realtime__when_using_authCallback__with_invalid_credentials__fails_to_connect() throws {
        let test = Test()
        let options = try AblyTests.clientOptions(for: test)
        options.authCallback = { _, completion in
            let token: ARTTokenDetails
            do {
                token = .init(token: try getJWTToken(for: test, invalid: true)!)
            } catch {
                XCTFail("Failed to get JWT: \(error)")
                completion(nil, error)
                return
            }
            completion(token, nil)
        }
        let client = ARTRealtimeClient(options: options)
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.disconnected) { stateChange in
                guard let reason = stateChange.reason else {
                    fail("Reason error is nil"); done(); return
                }
                XCTAssertEqual(reason.code, ARTErrorCode.invalidJwtFormat.intValue) // Error verifying JWT; err = Unexpected exception decoding token; err = signature verification failed. (See https://help.ably.io/error/40144 for help.)
                done()
            }
            client.connect()
        }
    }

    func test__148__JWT_and_realtime__when_token_expires_and_has_a_means_to_renew__reconnects_using_authCallback_and_obtains_a_new_token() throws {
        let test = Test()
        let tokenDuration = 3.0
        let options = try AblyTests.clientOptions(for: test)
        options.useTokenAuth = true
        options.autoConnect = false
        options.authCallback = { _, completion in
            let token: ARTTokenDetails
            do {
                token = .init(token: try getJWTToken(for: test, expiresIn: Int(tokenDuration))!)
            } catch {
                XCTFail("Failed to get JWT: \(error)")
                completion(nil, error)
                return
            }
            completion(token, nil)
        }
        let client = ARTRealtimeClient(options: options)
        defer { client.dispose(); client.close() }
        var originalToken = ""
        var originalConnectionID = ""
        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { _ in
                originalToken = client.auth.tokenDetails!.token
                originalConnectionID = client.connection.id!

                client.connection.once(.disconnected) { stateChange in
                    XCTAssertEqual(stateChange.reason?.code, ARTErrorCode.tokenExpired.intValue)

                    client.connection.once(.connected) { _ in
                        XCTAssertEqual(client.connection.id, originalConnectionID)
                        XCTAssertNotEqual(client.auth.tokenDetails!.token, originalToken)
                        done()
                    }
                }
            }
            client.connect()
        }
    }

    func test__149__JWT_and_realtime__when_the_token_request_includes_a_clientId__the_clientId_is_the_same_specified_in_the_JWT_token_request() throws {
        let test = Test()
        let clientId = "JWTClientId"
        let options = try AblyTests.clientOptions(for: test)
        options.tokenDetails = ARTTokenDetails(token: try getJWTToken(for: test, clientId: clientId)!)
        let client = ARTRealtimeClient(options: options)
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            client.connection.once(.connected) { _ in
                XCTAssertEqual(client.auth.clientId, clientId)
                done()
            }
            client.connect()
        }
    }

    func test__150__JWT_and_realtime__when_the_token_request_includes_subscribe_only_capabilities__fails_to_publish_to_a_channel_with_subscribe_only_capability() throws {
        let test = Test()
        let capability = "{\"\(channelName)\":[\"subscribe\"]}"
        let options = try AblyTests.clientOptions(for: test)
        options.tokenDetails = ARTTokenDetails(token: try getJWTToken(for: test, capability: capability)!)
        // Prevent channel name to be prefixed by test-*
        options.testOptions.channelNamePrefix = nil
        let client = ARTRealtimeClient(options: options)
        defer { client.dispose(); client.close() }

        waitUntil(timeout: testTimeout) { done in
            client.channels.get(channelName).publish(messageName, data: nil, callback: { error in
                XCTAssertEqual(error?.code, ARTErrorCode.operationNotPermittedWithProvidedCapability.intValue) // Unable to perform publish (permission denied)
                done()
            })
        }
    }

    // RSA11

    // RSA11b
    func test__151__currentTokenDetails__should_hold_a__TokenDetails__instance_in_which_only_the__token__attribute_is_populated_with_that_token_string() throws {
        let test = Test()
        let token = try getTestToken(for: test)
        let rest = ARTHttpClient(token: token)
        XCTAssertEqual(rest.auth.tokenDetails?.token, token)
    }

    // RSA11c
    func test__152__currentTokenDetails__should_be_set_with_the_current_token__if_applicable__on_instantiation_and_each_time_it_is_replaced() throws {
        let test = Test()
        let rest = ARTHttpClient(options: try AblyTests.commonAppSetup(for: test))
        XCTAssertNil(rest.auth.tokenDetails)
        var authenticatedTokenDetails: ARTTokenDetails?
        waitUntil(timeout: testTimeout) { done in
            rest.auth.authorize { tokenDetails, error in
                XCTAssertNil(error)
                authenticatedTokenDetails = tokenDetails
                done()
            }
        }
        XCTAssertEqual(rest.auth.tokenDetails, authenticatedTokenDetails)
    }

    // RSA11d
    func test__153__currentTokenDetails__should_be_empty_if_there_is_no_current_token() throws {
        let test = Test()
        let rest = ARTHttpClient(options: try AblyTests.commonAppSetup(for: test))
        XCTAssertNil(rest.auth.tokenDetails)
    }

    // RSC1 RSC1a RSC1c RSA3d

    func test__154__JWT_and_rest__when_the_JWT_token_embeds_an_Ably_token__pulls_stats_successfully() throws {
        let test = Test()
        let options = try AblyTests.clientOptions(for: test)
        options.tokenDetails = ARTTokenDetails(token: try getJWTToken(for: test, jwtType: "embedded")!)
        let client = ARTHttpClient(options: options)
        waitUntil(timeout: testTimeout) { done in
            client.stats { _, error in
                XCTAssertNil(error)
                done()
            }
        }
    }

    func test__155__JWT_and_rest__when_the_JWT_token_embeds_an_Ably_token_and_it_is_requested_as_encrypted__pulls_stats_successfully() throws {
        let test = Test()
        let options = try AblyTests.clientOptions(for: test)
        options.tokenDetails = ARTTokenDetails(token: try getJWTToken(for: test, jwtType: "embedded", encrypted: 1)!)
        let client = ARTHttpClient(options: options)
        waitUntil(timeout: testTimeout) { done in
            client.stats { _, error in
                XCTAssertNil(error)
                done()
            }
        }
    }

    // RSA4f, RSA8c

    func test__156__JWT_and_rest__when_the_JWT_token_is_returned_with_application_jwt_content_type__the_client_successfully_connects_and_pulls_stats() throws {
        let test = Test()
        let client = try jwtContentTypeTestsSetupDependencies(for: test)

        waitUntil(timeout: testTimeout) { done in
            client.stats { _, error in
                XCTAssertNil(error)
                done()
            }
        }
    }

    func test__157__JWT_and_rest__when_the_JWT_token_is_returned_with_application_jwt_content_type__the_client_can_request_a_new_token_to_initilize_another_client_that_connects_and_pulls_stats() throws {
        let test = Test()
        let client = try jwtContentTypeTestsSetupDependencies(for: test)

        waitUntil(timeout: testTimeout) { done in
            client.auth.requestToken(nil, with: nil, callback: { tokenDetails, error in
                let newClientOptions: ARTClientOptions
                do {
                    newClientOptions = try AblyTests.clientOptions(for: test)
                } catch {
                    XCTFail("Got unexpected error when creating client options: \(error.localizedDescription)")
                    done()
                    return
                }
                newClientOptions.token = tokenDetails!.token
                let newClient = ARTHttpClient(options: newClientOptions)
                newClient.stats { _, error in
                    XCTAssertNil(error)
                    done()
                }
            })
        }
    }

    // https://github.com/ably/ably-cocoa/issues/849
    func test__001__should_not_force_token_auth_when_clientId_is_set() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.clientId = "foo"
        XCTAssertTrue(options.isBasicAuth())
    }

    // https://github.com/ably/ably-cocoa/issues/1093
    func test__002__should_accept_authURL_response_with_timestamp_argument_as_string() throws {
        let test = Test()
        var capturedOriginalTokenRequest: ARTTokenRequest?
        let tmpRest = ARTHttpClient(options: try AblyTests.commonAppSetup(for: test))

        let channelName = test.uniqueChannelName()
        waitUntil(timeout: testTimeout) { done in
            let tokenParams = ARTTokenParams()
            tokenParams.clientId = "john"
            tokenParams.capability = """
            {"\(channelName)":["publish","subscribe","presence","history"]}
            """
            tokenParams.ttl = 43200
            tmpRest.auth.createTokenRequest(tokenParams, options: nil) { tokenRequest, error in
                XCTAssertNil(error)
                capturedOriginalTokenRequest = tokenRequest
                done()
            }
        }
        let originalTokenRequest = try XCTUnwrap(capturedOriginalTokenRequest, "waitUntil timed out before originalTokenRequest was set")
        // "timestamp" as String
        let tokenRequestJsonString = """
        {"keyName":"\(originalTokenRequest.keyName)","timestamp":"\(String(dateToMilliseconds(originalTokenRequest.timestamp))))","clientId":"\(originalTokenRequest.clientId!)","nonce":"\(originalTokenRequest.nonce)","mac":"\(originalTokenRequest.mac)","ttl":"\(String(originalTokenRequest.ttl!.intValue * 1000)))","capability":"\(originalTokenRequest.capability!.replace("\"", withString: "\\\""))"}
        """

        let options = try AblyTests.clientOptions(for: test)
        options.authUrl = URL(string: "http://auth-test.ably.cocoa")

        let rest = ARTHttpClient(options: options)
        XCTAssertNil(rest.auth.clientId)
        #if os(iOS)
            XCTAssertNil(rest.device.clientId)
        #endif
        let testHttpExecutor = TestProxyHTTPExecutor(logger: .init(clientOptions: options))
        rest.internal.httpExecutor = testHttpExecutor
        let channel = rest.channels.get(channelName)

        testHttpExecutor.simulateIncomingPayloadOnNextRequest(tokenRequestJsonString.data(using: .utf8)!)

        waitUntil(timeout: testTimeout) { done in
            channel.publish("foo", data: nil) { error in
                XCTAssertNil(error)
                done()
            }
        }

        let requestUrl = try XCTUnwrap(testHttpExecutor.requests.first?.url, "No request url found")
        let tokenDetails = try XCTUnwrap(rest.internal.auth.tokenDetails, "Should have token details")

        XCTAssertEqual(requestUrl.host, "auth-test.ably.cocoa")
        XCTAssertEqual(tokenDetails.clientId, originalTokenRequest.clientId)
        XCTAssertNotNil(tokenDetails.token)
    }
}
