import AblyPubSubDevice
import CommonCrypto
import Foundation
import XCTest
import Nimble
import AblyTesting
import AblyTestingObjC

import AblyPubSubDevice.Private

typealias HookToken = AspectToken

let AblyTestsErrorDomain = "test.ably.io"

class AblyTestsConfiguration: NSObject, XCTestObservation {
    override init() {
        super.init()
        XCTestObservationCenter.shared.addTestObserver(self)
    }

    private var performedPreFirstTestCaseSetup = false

    func testCaseWillStart(_ testCase: XCTestCase) {
        if !performedPreFirstTestCaseSetup {
            preFirstTestCaseSetup()
            performedPreFirstTestCaseSetup = true
        }
    }

    private func preFirstTestCaseSetup() {
        // This is code that, when we were using the Quick testing
        // framework, was inside a `configuration.beforeSuite` hook,
        // which means it runs just before the execution of the first
        // test case.
        AsyncDefaults.timeout = testTimeout
    }
}

func pathForTestResource(_ resourcePath: String) -> String {
    return Bundle.module.path(forResource: resourcePath, ofType: "")!
}

let appSetupModel: TestAppSetup = {
    do {
        return try JSONUtility.decode(path: pathForTestResource(testResourcesPath + "test-app-setup.json"))
    } catch {
        fatalError("Can't parse `test-app-setup.json` \(error)")
    }
}()

let testTimeout = DispatchTimeInterval.seconds(20)
let testResourcesPath = "ably-common/test-resources/"
let echoServerAddress = "https://echo.ably.io/createJWT"

/// Common test utilities.
class AblyTests {
    enum Error: Swift.Error {
        case timedOut
    }

    class func base64ToData(_ base64: String) -> Data {
        return Data(base64Encoded: base64, options: NSData.Base64DecodingOptions(rawValue: 0))!
    }

    class func msgpackToData(_ data: Data) -> Data {
        let decoded = try! ARTMsgPackEncoder().decode(data)
        let encoded = try! ARTJsonEncoder().encode(decoded)

        return encoded
    }

    class func checkError(_ errorInfo: ARTErrorInfo?, withAlternative message: String) {
        if let error = errorInfo {
            XCTFail("\((error ).code): \(error.message)")
        }
        else if !message.isEmpty {
            XCTFail(message)
        }
    }

    class func checkError(_ errorInfo: ARTErrorInfo?) {
        checkError(errorInfo, withAlternative: "")
    }

    /// Removes the on-disk `LocalDevice` file used by the real device storage,
    /// so a test (or suite `setUp`) starts from a clean device/state-machine
    /// slate rather than inheriting state another test persisted.
    class func clearOnDiskDeviceStorage() {
        #if os(iOS)
        let deviceFileURL = ARTLocalDeviceStorage.defaultBaseDirectoryURL().appendingPathComponent("LocalDevice.plist")
        try? FileManager.default.removeItem(at: deviceFileURL)
        #endif
    }

    static var testApplication: [String: Any]?

    struct QueueIdentity {
        let label: String
    }

    static let queueIdentityKey = DispatchSpecificKey<QueueIdentity>()

    static var queue: DispatchQueue = {
        let queue = DispatchQueue(label: "io.ably.tests", qos: .userInitiated)
        queue.setSpecific(key: queueIdentityKey, value: QueueIdentity(label: queue.label))
        return queue
    }()

    static func createUserQueue(for test: Test) -> DispatchQueue {
        let queue = DispatchQueue(label: "io.ably.tests.callbacks.\(test.id).\(UUID().uuidString)", qos: .userInitiated)
        queue.setSpecific(key: queueIdentityKey, value: QueueIdentity(label: queue.label))
        return queue
    }

    static func currentQueueLabel() -> String? {
        return DispatchQueue.getSpecific(key: queueIdentityKey)?.label
    }

    class func commonAppSetup(for test: Test, debug: Bool = false, forceNewApp: Bool = false) throws -> ARTClientOptions {
        let options = try AblyTests.clientOptions(for: test, debug: debug)
        options.testOptions.channelNamePrefix = "test-\(test.id)-\(UUID().uuidString)"

        if forceNewApp {
            testApplication = nil
        }

        let app: [String: Any]
        if let testApplication {
            app = testApplication
        } else {
            let request = NSMutableURLRequest(url: URL(string: "https://\(options.restHost):\(options.tlsPort)/apps")!)
            request.httpMethod = "POST"
            request.httpBody = try JSONUtility.encode(appSetupModel.postApps)

            request.allHTTPHeaderFields = [
                "Accept" : "application/json",
                "Content-Type" : "application/json"
            ]
            request.timeoutInterval = SandboxEnvironment.provisioningTimeout

            func provisionApp() throws -> [String: Any] {
                let (responseData, response) = try SynchronousHTTPClient().perform(request)
                guard (200 ..< 300).contains(response.statusCode) else {
                    throw NSError(domain: "AblyTests", code: response.statusCode, userInfo: [
                        NSLocalizedDescriptionKey: "POST /apps returned HTTP \(response.statusCode)",
                    ])
                }
                let body: [String: Any] = try JSONUtility.jsonObject(data: responseData)
                // Validate here so an unexpected body (e.g. a sandbox error response with a
                // 2xx status) engages the retry instead of crashing the `keys` unwrap below.
                // The body itself stays out of the error: it can contain valid API keys, and
                // test failures land in public CI logs.
                guard let keys = body["keys"] as? [[String: Any]], keys.first?["keyStr"] is String else {
                    throw NSError(domain: "AblyTests", code: 0, userInfo: [
                        NSLocalizedDescriptionKey: "POST /apps returned HTTP \(response.statusCode) with no usable keys; body fields: \(body.keys.sorted())",
                    ])
                }
                return body
            }

            // Retried against transient network stalls on CI (a single stalled request otherwise
            // fails every test sharing the app). Retrying the non-idempotent POST is safe — an
            // orphaned app from a timed-out create is auto-deleted by the sandbox after a few
            // minutes of no use.
            app = try withProvisioningRetriesSync { try provisionApp() }
            testApplication = app

            if debug {
                print(app)
            }
        }
        let keysArray = app["keys"] as! [[String: Any]]
        let key = keysArray[0]
        options.key = key["keyStr"] as? String

        return options
    }

    class func clientOptions(for test: Test, debug: Bool = false, key: String? = nil, requestToken: Bool = false) throws -> ARTClientOptions {
        let options = ARTClientOptions()
        options.environment = getEnvironment()
        if debug {
            options.logLevel = .verbose
        }
        if let key = key {
            options.key = key
        }
        if requestToken {
            options.token = try getTestToken(for: test)
        }
        options.dispatchQueue = DispatchQueue.main
        options.internalDispatchQueue = queue
        return options
    }

    class func newErrorProtocolMessage(message: String = "Fail test") -> ARTProtocolMessage {
        let protocolMessage = ARTProtocolMessage()
        protocolMessage.action = .error
        protocolMessage.error = ARTErrorInfo.create(withCode: 0, message: message)
        return protocolMessage
    }

    class func newPresenceProtocolMessage(id: String, channel: String, action: ARTPresenceAction, clientId: String, connectionId: String) -> ARTProtocolMessage {
        let protocolMessage = ARTProtocolMessage()
        protocolMessage.action = .presence
        protocolMessage.channel = channel
        protocolMessage.timestamp = Date()
        protocolMessage.presence = [
            ARTPresenceMessage(clientId: clientId, action: action, connectionId: connectionId, id: id, timestamp: Date())
        ]
        return protocolMessage
    }

    struct RealtimeTestEnvironment {
        let client: ARTRealtime
        let transportFactory: TestProxyTransportFactory
    }

    class func newRealtime(_ options: ARTClientOptions, onTransportCreated event: ((ARTRealtimeTransport) -> Void)? = nil) -> RealtimeTestEnvironment {
        let modifiedOptions = options.copy() as! ARTClientOptions

        let autoConnect = modifiedOptions.autoConnect
        modifiedOptions.autoConnect = false
        let transportFactory = TestProxyTransportFactory()
        transportFactory.transportCreatedEvent = event
        modifiedOptions.testOptions.transportFactory = transportFactory
        let realtime = ARTRealtime(options: modifiedOptions)
        realtime.internal.setReachabilityClass(TestReachability.self)
        if autoConnect {
            realtime.connect()
        }
        return .init(client: realtime, transportFactory: transportFactory)
    }

    class func newRandomString() -> String {
        return ProcessInfo.processInfo.globallyUniqueString
    }

    class func addMembersSequentiallyToChannel(_ channelName: String, members: Int = 1, startFrom: Int = 1, data: AnyObject? = nil, options: ARTClientOptions) -> ARTRealtime {
        let client = ARTRealtime(options: options)
        let channel = client.channels.get(channelName)

        waitUntil(timeout: testTimeout) { done in
            channel.attach() { _ in
                done()
            }
        }

        for i in startFrom..<startFrom+members {
            waitUntil(timeout: testTimeout) { done in
                channel.presence.enterClient("user\(i)", data: data) { _ in
                    done()
                }
            }
        }

        return client
    }

    class func addMembersSequentiallyToChannel(_ channelName: String, members: Int = 1, startFrom: Int = 1, data: AnyObject? = nil, options: ARTClientOptions, done: @escaping ()->()) -> ARTRealtime {
        let client = ARTRealtime(options: options)
        let channel = client.channels.get(channelName)

        class Total {
            static var count: Int = 0
        }

        Total.count = 0
        channel.attach() { _ in
            for i in startFrom..<startFrom+members {
                channel.presence.enterClient("user\(i)", data: data) { _ in
                    Total.count += 1
                    if Total.count == members {
                        done()
                    }
                }
            }
        }

        return client
    }

    class func splitDone(_ howMany: Int, file: StaticString = #file, line: UInt = #line, done: @escaping () -> Void) -> (() -> Void) {
        var left = howMany
        return {
            left -= 1
            if left == 0 {
                done()
            } else if left < 0 {
                XCTFail("splitDone called more than the expected \(howMany) times", file: file, line: line)
            }
        }
    }

    class func waitFor<T>(timeout: DispatchTimeInterval, file: FileString = #file, line: UInt = #line, f: @escaping (@escaping (T?) -> Void) -> Void) throws -> T {
        var value: T?
        waitUntil(timeout: timeout, file: file, line: line) { done in
            f() { v in
                value = v
                done()
            }
        }
        guard let value else {
            throw Error.timedOut
        }
        return value
    }

    class func wait(for expectations: [XCTestExpectation], timeout dispatchInterval: DispatchTimeInterval = testTimeout, file: Nimble.FileString = #file, line: UInt = #line) {
        let result = XCTWaiter.wait(
            for: expectations,
            timeout: dispatchInterval.toTimeInterval(),
            enforceOrder: true
        )

        let title: String = "Waiter of expectations \(expectations.map({ $0.description }))"
        switch result {
        case .timedOut:
            fail(title + " timed out (\(dispatchInterval)).", file: file, line: line)
        case .invertedFulfillment:
            fail(title + " shouldn't receive a fulfillment.", file: file, line: line)
        case .interrupted:
            fail(title + " got interrupted.", file: file, line: line)
        case .incorrectOrder:
            fail(title + " failed with incorrect order.", file: file, line: line)
        case .completed:
            break //completed successfully
        default:
            preconditionFailure("XCTWaiter.Result.\(String(describing: result)) not implemented")
        }
    }

    // MARK: Crypto

    struct CryptoTestItem {

        struct TestMessage {
            let name: String
            let data: String
            let encoding: String
        }

        let encoded: TestMessage
        let encrypted: TestMessage

        init(object: CryptoData.Item) {
            let encodedJson = object.encoded
            encoded = TestMessage(name: encodedJson.name, data: encodedJson.data, encoding: encodedJson.encoding ?? "")
            let encryptedJson = object.encrypted
            encrypted = TestMessage(name: encryptedJson.name, data: encryptedJson.data, encoding: encryptedJson.encoding)
        }

    }

    class func loadCryptoTestRawData(_ fileName: String) -> (key: Data, iv: Data, jsonItems: [CryptoData.Item]) {
        let file = testResourcesPath + fileName + ".json";
        let json: CryptoData = try! JSONUtility.decode(path: pathForTestResource(file))

        let keyData = Data(base64Encoded: json.key, options: Data.Base64DecodingOptions(rawValue: 0))!
        let ivData = Data(base64Encoded: json.iv, options: Data.Base64DecodingOptions(rawValue: 0))!

        return (keyData, ivData, json.items)
    }

    class func loadCryptoTestData(_ fileName: String) -> (key: Data, iv: Data, items: [CryptoTestItem]) {
        let (keyData, ivData, jsonItems) = loadCryptoTestRawData(fileName)
        let items = jsonItems.map{ $0 }.map(CryptoTestItem.init)
        return (keyData, ivData, items)
    }

    /// Given a sequence of jitter coefficients, returns a sequence of retry delays as defined by RTB1. The first element of the sequence is the delay before the first retry, and so on.
    ///
    /// We use "AnySequence<Double>" instead of "some Sequence<Double>", because the compiler tells us "'some' return types are only available in iOS 13.0.0 or newer".
    class func expectedRetryDelays<T: Sequence<Double>>(forTimeout timeout: TimeInterval, jitterCoefficients: T) ->  AnySequence<Double> {
        let backoffCoefficients = BackoffCoefficients()

        let sequence = zip(backoffCoefficients, jitterCoefficients).lazy.map { backoffCoefficient, jitterCoefficient in
            timeout * backoffCoefficient * jitterCoefficient
        }

        return .init(sequence)
    }

    /**
     Tests that wait for the Ably service to consider a token as having expired by waiting for its `ttl` to elapse should wait this additional tolerance (arbitarily chosen) to compensate for clock differences between different Ably servers.
     */
    static let tokenExpiryTolerance: TimeInterval = 2
}

/// A helper class for performing HTTP requests synchronously in tests.
class SynchronousHTTPClient: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
    private static let delegateQueue = DispatchQueue(label: "io.ably.tests.NSURLSessionServerTrustSync", qos: .userInitiated)

    @discardableResult
    func perform(_ request: NSMutableURLRequest) throws -> (Data, HTTPURLResponse) {
        var callbackData: Data?
        var callbackResponse: URLResponse?
        var callbackError: Error?
        var requestCompleted = false

        let configuration = URLSessionConfiguration.default
        let queue = OperationQueue()
        queue.underlyingQueue = Self.delegateQueue
        let session = Foundation.URLSession(configuration:configuration, delegate:self, delegateQueue:queue)

        let task = session.dataTask(with: request as URLRequest, completionHandler: { data, response, error in
            callbackData = data
            callbackResponse = response
            callbackError = error
            requestCompleted = true
        })
        task.resume()

        while !requestCompleted {
            CFRunLoopRunInMode(CFRunLoopMode.defaultMode, CFTimeInterval(0.1), Bool(truncating: 0))
        }

        if let callbackError {
            throw callbackError
        }

        guard let httpResponse = callbackResponse as? HTTPURLResponse else {
            fatalError("Expected HTTPURLResponse, got \(String(describing: callbackResponse))")
        }

        guard let callbackData else {
            fatalError("Expected to have a response body")
        }

        return (callbackData, httpResponse)
    }
}

extension Date {
    func isBefore(_ other: Date) -> Bool {
        return self.compare(other) == ComparisonResult.orderedAscending
    }
}

// MARK: ARTAuthOptions Equatable

func ==(lhs: ARTAuthOptions, rhs: ARTAuthOptions) -> Bool {
    return lhs.token == rhs.token &&
        lhs.authMethod == rhs.authMethod &&
        lhs.authUrl == rhs.authUrl &&
        lhs.key == rhs.key
}

func ==(lhs: ARTJsonCompatible?, rhs: ARTJsonCompatible?) -> Bool {
    guard let lhs = lhs else {
        return rhs == nil
    }
    guard let rhs = rhs else {
        return false
    }
    do {
        return NSDictionary(dictionary: try lhs.toJSON()).isEqual(to: try rhs.toJSON())
    } catch {
        return false
    }
}

// MARK: Publish message class

class PublishTestMessage {

    var completion: ((ARTErrorInfo?) -> Void)? = nil
    var error: ARTErrorInfo? = nil

    init(client: ARTRest, channelName: String, failOnError: Bool = true, completion: ((ARTErrorInfo?) -> Void)? = nil) {
        client.channels.get(channelName).publish(nil, data: "message") { error in
            self.error = error
            if let callback = completion {
                callback(error)
            }
            else if failOnError, let e = error {
                XCTFail("Got error '\(e)'")
            }
        }
    }

    init(client: ARTRealtime, channelName: String, failOnError: Bool = true, completion: ((ARTErrorInfo?) -> Void)? = nil) {
        let complete: (ARTErrorInfo?) -> Void = { errorInfo in
            // ARTErrorInfo to NSError
            self.error = errorInfo

            if let callback = completion {
                callback(self.error)
            }
            else if failOnError, let e = self.error {
                XCTFail("Got error '\(e)'")
            }
        }

        client.connection.on { stateChange in
            let state = stateChange.current
            if state == .connected {
                let channel = client.channels.get(channelName)
                channel.on { stateChange in
                    switch stateChange.current {
                    case .attached:
                        channel.publish(nil, data: "message") { errorInfo in
                            complete(errorInfo)
                        }
                    case .failed:
                        complete(stateChange.reason)
                    default:
                        break
                    }
                }
                channel.attach()
            }
        }
    }

}

/// Rest - Publish message
@discardableResult func publishTestMessage(_ rest: ARTRest, channelName: String, completion: Optional<(ARTErrorInfo?)->()>) -> PublishTestMessage {
    return PublishTestMessage(client: rest, channelName: channelName, failOnError: false, completion: completion)
}

@discardableResult func publishTestMessage(_ rest: ARTRest, channelName: String, failOnError: Bool = true) -> PublishTestMessage {
    return PublishTestMessage(client: rest, channelName: channelName, failOnError: failOnError)
}

/// Realtime - Publish message with callback
/// (publishes if connection state changes to CONNECTED and channel state changes to ATTACHED)
@discardableResult func publishFirstTestMessage(_ realtime: ARTRealtime, channelName: String, completion: Optional<(ARTErrorInfo?)->()>) -> PublishTestMessage {
    return PublishTestMessage(client: realtime, channelName: channelName, failOnError: false, completion: completion)
}

/// Realtime - Publish message
/// (publishes if connection state changes to CONNECTED and channel state changes to ATTACHED)
@discardableResult func publishFirstTestMessage(_ realtime: ARTRealtime, channelName: String, failOnError: Bool = true) -> PublishTestMessage {
    return PublishTestMessage(client: realtime, channelName: channelName, failOnError: failOnError)
}

/// Access Token
func getTestToken(for test: Test, key: String? = nil, clientId: String? = nil, capability: String? = nil, ttl: TimeInterval? = nil, file: FileString = #file, line: UInt = #line) throws -> String {
    return try getTestTokenDetails(for: test, key: key, clientId: clientId, capability: capability, ttl: ttl, file: file, line: line).token
}

func getTestToken(for test: Test, key: String? = nil, clientId: String? = nil, capability: String? = nil, ttl: TimeInterval? = nil, file: FileString = #file, line: UInt = #line, completion: @escaping (Swift.Result<String, Error>) -> Void) {
    getTestTokenDetails(for: test, key: key, clientId: clientId, capability: capability, ttl: ttl) { result in
        completion(result.map(\.token))
    }
}

/// Access TokenDetails
func getTestTokenDetails(for test: Test, key: String? = nil, clientId: String? = nil, capability: String? = nil, ttl: TimeInterval? = nil, queryTime: Bool? = nil, completion: @escaping (Swift.Result<ARTTokenDetails, Error>) -> Void) {
    let options: ARTClientOptions
    if let key = key {
        do {
            options = try AblyTests.clientOptions(for: test)
        } catch {
            completion(.failure(error))
            return
        }
        options.key = key
    }
    else {
        do {
            options = try AblyTests.commonAppSetup(for: test)
        } catch {
            completion(.failure(error))
            return
        }
    }
    if let queryTime = queryTime {
        options.queryTime = queryTime
    }

    let client = ARTRest(options: options)

    var tokenParams: ARTTokenParams? = nil
    if let capability = capability {
        tokenParams = ARTTokenParams()
        tokenParams!.capability = capability
    }
    if let ttl = ttl {
        if tokenParams == nil { tokenParams = ARTTokenParams() }
        tokenParams!.ttl = NSNumber(value: ttl)
    }
    if let clientId = clientId {
        if tokenParams == nil { tokenParams = ARTTokenParams() }
        tokenParams!.clientId = clientId
    }

    client.auth.requestToken(tokenParams, with: nil) { details, error in
        _ = client // Hold reference to client, since requestToken is async and will lose it.
        if let error {
            completion(.failure(error))
        } else if let details {
            completion(.success(details))
        } else {
            fatalError("Got neither details nor error")
        }
    }
}

func getTestTokenDetails(for test: Test, key: String? = nil, clientId: String? = nil, capability: String? = nil, ttl: TimeInterval? = nil, queryTime: Bool? = nil, completion: @escaping (ARTTokenDetails?, Error?) -> Void) {
    getTestTokenDetails(for: test, key: key, clientId: clientId, capability: capability, ttl: ttl, queryTime: queryTime) { result in
        switch result {
        case .success(let tokenDetails):
            completion(tokenDetails, nil)
        case .failure(let error):
            completion(nil, error)
        }
    }
}

func getTestTokenDetails(for test: Test, key: String? = nil, clientId: String? = nil, capability: String? = nil, ttl: TimeInterval? = nil, queryTime: Bool? = nil, file: FileString = #file, line: UInt = #line) throws -> ARTTokenDetails {
    let result = try AblyTests.waitFor(timeout: testTimeout, file: file, line: line) { value in
        getTestTokenDetails(for: test, key: key, clientId: clientId, capability: capability, ttl: ttl, queryTime: queryTime) { result in
            value(result)
        }
    }

    return try result.get()
}

// Gets a JWT for use in tests. By default this will sign the token locally, but for some cases (e.g. embedded JWTs), it will use
// the echoserver that has this functionality.
func getJWTToken(for test: Test, invalid: Bool = false, expiresIn: Int = 3600, clientId: String = "testClientIDiOS", capability: String = "{\"*\":[\"*\"]}", jwtType: String = "", encrypted: Int = 0, extraClaims: [String: Any] = [:]) throws -> String? {
    let options = try AblyTests.commonAppSetup(for: test)
    guard let components = options.key?.components(separatedBy: ":"), let keyName = components.first, var keySecret = components.last else {
        fail("Invalid API key: \(options.key ?? "nil")")
        return nil
    }
    if invalid {
        keySecret = "invalid"
    }

    if !jwtType.isEmpty {
        precondition(extraClaims.isEmpty, "extraClaims are not supported for the embedded JWT (echo-server) path")
        return try getEmbeddedJWTTokenViaEchoServer(keyName: keyName, keySecret: keySecret, expiresIn: expiresIn, clientId: clientId, capability: capability, jwtType: jwtType, encrypted: encrypted)
    }

    precondition(encrypted == 0, "encrypted is not supported for the local JWT signing path")

    let now = Int(Date().timeIntervalSince1970)
    var claims: [String: Any] = [
        "iat": now,
        "exp": now + expiresIn,
        "x-ably-capability": capability,
        "x-ably-clientId": clientId,
    ]
    for (key, value) in extraClaims {
        claims[key] = value
    }
    return try signJWT(claims: claims, keyName: keyName, keySecret: keySecret)
}

private func getEmbeddedJWTTokenViaEchoServer(keyName: String, keySecret: String, expiresIn: Int, clientId: String, capability: String, jwtType: String, encrypted: Int) throws -> String? {
    var urlComponents = URLComponents(string: echoServerAddress)
    urlComponents?.queryItems = [
        URLQueryItem(name: "keyName", value: keyName),
        URLQueryItem(name: "keySecret", value: keySecret),
        URLQueryItem(name: "expiresIn", value: String(expiresIn)),
        URLQueryItem(name: "clientId", value: clientId),
        URLQueryItem(name: "capability", value: capability),
        URLQueryItem(name: "jwtType", value: jwtType),
        URLQueryItem(name: "encrypted", value: String(encrypted)),
        URLQueryItem(name: "environment", value: getEnvironment()),
    ]

    let request = NSMutableURLRequest(url: urlComponents!.url!)
    // Retried against transient network stalls on CI (idempotent GET to the echo server). A
    // non-2xx body must not be returned as a "JWT", so the status check lives inside the retried
    // closure; the error deliberately omits the URL, whose query string carries the key secret.
    let responseData = try withProvisioningRetriesSync { () throws -> Data in
        let (data, response) = try SynchronousHTTPClient().perform(request)
        guard (200 ..< 300).contains(response.statusCode) else {
            throw NSError(domain: "AblyTests", code: response.statusCode, userInfo: [
                NSLocalizedDescriptionKey: "GET /createJWT (echo server) returned HTTP \(response.statusCode)",
            ])
        }
        return data
    }
    return String(data: responseData, encoding: String.Encoding.utf8)
}

func signJWT(claims: [String: Any], keyName: String, keySecret: String) throws -> String {
    let header: [String: Any] = [
        "typ": "JWT",
        "alg": "HS256",
        "kid": keyName,
    ]

    let headerData = try JSONSerialization.data(withJSONObject: header)
    let claimsData = try JSONSerialization.data(withJSONObject: claims)

    let headerBase64 = base64urlEncode(headerData)
    let claimsBase64 = base64urlEncode(claimsData)

    let signingInput = "\(headerBase64).\(claimsBase64)"
    guard let signingInputData = signingInput.data(using: .utf8),
          let keyData = keySecret.data(using: .utf8) else {
        throw NSError(domain: AblyTestsErrorDomain, code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to encode JWT signing input"])
    }

    var hmac = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    signingInputData.withUnsafeBytes { inputBytes in
        keyData.withUnsafeBytes { keyBytes in
            CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256),
                   keyBytes.baseAddress, keyData.count,
                   inputBytes.baseAddress, signingInputData.count,
                   &hmac)
        }
    }
    let signatureBase64 = base64urlEncode(Data(hmac))

    return "\(headerBase64).\(claimsBase64).\(signatureBase64)"
}

func base64urlEncode(_ data: Data) -> String {
    return data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

func getKeys(for test: Test) throws -> Dictionary<String, String> {
    let options = try AblyTests.commonAppSetup(for: test)
    guard let components = options.key?.components(separatedBy: ":"), let keyName = components.first, let keySecret = components.last else {
        fatalError("Invalid API key)")
    }
    return ["keyName": keyName, "keySecret": keySecret]
}

public func delay(_ seconds: TimeInterval, closure: @escaping () -> Void) {
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: closure)
}

public func getEnvironment() -> String {
    let b = Bundle(for: AblyTests.self)
    guard let env = b.infoDictionary!["ABLY_ENV"] as? String, env.count > 0 else {
        return "sandbox"
    }
    return env
}

public func buildMessagesThatExceedMaxMessageSize() -> [ARTMessage] {
    var messages = [ARTMessage]()
    for index in 0...5000 {
        let m = ARTMessage(name: "name-\(index)", data: "data-\(index)")
        messages.append(m)
    }
    return messages
}

public func buildStringThatExceedMaxMessageSize() -> String {
    var name = ""
    for index in 0...10000 {
        name += "name-\(index)"
    }
    return name
}

class Box<T> {
    let unbox: T
    init(_ value: T) {
        self.unbox = value
    }
}

enum Result<T> {
    case success(Box<T>)
    case failure(String)
    /// Constructs a success wrapping a `value`.
    init(value: Box<T>) {
        self = .success(value)
    }
    /// Constructs a failure wrapping an `error`.
    init(error: String) {
        self = .failure(error)
    }
}

func extractURL(_ request: URLRequest?) -> Result<URL> {
    guard let request = request
        else { return Result(error: "No request found") }

    guard let url = request.url
        else { return Result(error: "Request has no URL defined") }

    return Result.success(Box(url))
}

func extractBodyAsJSON(_ request: URLRequest?) -> Result<NSDictionary> {
    guard let request = request
        else { return Result(error: "No request found") }

    guard let bodyData = request.httpBody
        else { return Result(error: "No HTTPBody") }

    guard let json = try? JSONSerialization.jsonObject(with: bodyData, options: .mutableLeaves)
        else { return Result(error: "Invalid json") }

    guard let httpBody = json as? NSDictionary
        else { return Result(error: "HTTPBody has invalid format") }

    return Result.success(Box(httpBody))
}

func extractBodyAsMsgPack(_ request: URLRequest?) -> Result<NSDictionary> {
    guard let request = request
        else { return Result(error: "No request found") }

    guard let bodyData = request.httpBody
        else { return Result(error: "No HTTPBody") }

    let json: Any
    do {
        json = try ARTMsgPackEncoder().decode(bodyData)
    } catch {
        return Result(error: error.localizedDescription)
    }

    guard let httpBody = json as? NSDictionary
        else { return Result(error: "expected dictionary, got \(type(of: (json) as AnyObject)): \(json)") }

    return Result.success(Box(httpBody))
}

func extractBodyAsMessages(_ request: URLRequest?) -> Result<[NSDictionary]> {
    guard let request = request
        else { return Result(error: "No request found") }

    guard let bodyData = request.httpBody
        else { return Result(error: "No HTTPBody") }

    let json: Any
    do {
        json = try ARTMsgPackEncoder().decode(bodyData)
    } catch {
        return Result(error: error.localizedDescription)
    }

    guard let httpBody = json as? NSArray
        else { return Result(error: "expected array, got \(type(of: (json) as AnyObject)): \(json)") }

    return Result.success(Box(httpBody.map{$0 as! NSDictionary}))
}

func extractURLQueryValue(_ url: URL?, key name: String) -> String? {
    guard let query = url?.query else {
        return nil
    }
    let queryItems = query.components(separatedBy: "&")
    for item in queryItems {
        let param = item.components(separatedBy: "=")
        if param.first == name {
            return param.last
        }
    }
    return nil
}

enum FakeNetworkResponse {
    case noInternet
    case hostUnreachable
    case requestTimeout(timeout: TimeInterval)
    case hostInternalError(code: Int)
    case host400BadRequest
    case arbitraryError

    var error: NSError {
        switch self {
        case .noInternet:
            return NSError(domain: NSPOSIXErrorDomain, code: 50, userInfo: [NSLocalizedDescriptionKey: "network is down", NSLocalizedFailureReasonErrorKey: AblyTestsErrorDomain + ".FakeNetworkResponse"])
        case .hostUnreachable:
            return NSError(domain: kCFErrorDomainCFNetwork as String, code: 2, userInfo: [NSLocalizedDescriptionKey: "host unreachable", NSLocalizedFailureReasonErrorKey: AblyTestsErrorDomain + ".FakeNetworkResponse"])
        case .requestTimeout:
            return NSError(domain: "com.squareup.SocketRocket", code: 504, userInfo: [NSLocalizedDescriptionKey: "timed out", NSLocalizedFailureReasonErrorKey: AblyTestsErrorDomain + ".FakeNetworkResponse"])
        case .hostInternalError(let code):
            return NSError(domain: AblyTestsErrorDomain, code: code, userInfo: [NSLocalizedDescriptionKey: "internal error", NSLocalizedFailureReasonErrorKey: AblyTestsErrorDomain + ".FakeNetworkResponse"])
        case .host400BadRequest:
            return NSError(domain: AblyTestsErrorDomain, code: 400, userInfo: [NSLocalizedDescriptionKey: "bad request", NSLocalizedFailureReasonErrorKey: AblyTestsErrorDomain + ".FakeNetworkResponse"])
        case .arbitraryError:
            return NSError(domain: AblyTestsErrorDomain, code: 1, userInfo: [NSLocalizedDescriptionKey: "error from FakeNetworkResponse.arbitraryError"])
        }
    }

    func transportError(for url: URL) -> ARTRealtimeTransportError {
        switch self {
        case .noInternet:
            return ARTRealtimeTransportError(error: error, type: .noInternet, url: url)
        case .hostUnreachable:
            return ARTRealtimeTransportError(error: error, type: .hostUnreachable, url: url)
        case .requestTimeout:
            return ARTRealtimeTransportError(error: error, type: .timeout, url: url)
        case .hostInternalError(let code):
            return ARTRealtimeTransportError(error: error, badResponseCode: code, url: url)
        case .host400BadRequest:
            return ARTRealtimeTransportError(error: error, badResponseCode: 400, url: url)
        case .arbitraryError:
            return ARTRealtimeTransportError(error: error, type: .other, url: url)
        }
    }
}

class MockHTTP: ARTHttp {

    enum Rule {
        case host(name: String)
        case resetAfter(numberOfRequests: Int)
    }

    private var networkState: FakeNetworkResponse?
    private var rule: Rule?
    private var count: Int = 0
    private var successResponseData: (data: Data?, contentType: String)?

    init(logger: InternalLog) {
        super.init(queue: AblyTests.queue, logger: logger)
    }

    func setNetworkState(network: FakeNetworkResponse, resetAfter numberOfRequests: Int) {
        queue.async {
            self.networkState = network
            self.rule = .resetAfter(numberOfRequests: numberOfRequests)
            self.count = numberOfRequests
        }
    }

    func setNetworkState(network: FakeNetworkResponse) {
        queue.async {
            self.networkState = network
            self.rule = nil
        }
    }

    func setNetworkState(network: FakeNetworkResponse, forHost host: String) {
        queue.async {
            self.networkState = network
            self.rule = .host(name: host)
        }
    }

    /// Sets the response data to be returned for successful (non-error) requests.
    ///
    /// This configures what MockHTTP returns when no error state is active (i.e., when
    /// `networkState` is `nil` or after `resetAfter` count is exhausted). This is independent
    /// of the error simulation logic controlled by `networkState` and `rule`.
    ///
    /// - Parameters:
    ///   - data: The response body data to return. Pass `nil` for no response body.
    ///   - contentType: The Content-Type header value (e.g., "application/json").
    ///
    /// - Important: You must provide the content-type that matches how your data is encoded.
    ///   There is no default - the caller knows their payload format.
    ///
    /// - Note: This setting persists across the "resetAfter" logic. Set it once at test
    ///   setup and it will apply to all successful requests throughout the test.
    ///
    /// - Note: This does NOT affect error cases (`.hostUnreachable`, `.hostInternalError`, etc.).
    ///   Those continue to return their configured error responses.
    func setSuccessResponse(data: Data?, contentType: String) {
        queue.sync {
            self.successResponseData = (data, contentType)
        }
    }

    override public func execute(_ request: URLRequest, completion callback: ((HTTPURLResponse?, Data?, Error?) -> Void)? = nil) -> (ARTCancellable & NSObjectProtocol)? {
        queue.async {
            switch self.rule {
            case .none:
                self.performRequest(state: self.networkState, requestCallback: callback)
            case .host(let name):
                if request.url?.host == name {
                    self.performRequest(state: self.networkState, requestCallback: callback)
                }
                else {
                    self.performRequest(state: nil, requestCallback: callback)
                }
            case .resetAfter:
                self.count -= 1
                self.performRequest(state: self.networkState, requestCallback: callback)

                if self.count == 0 {
                    self.networkState = nil
                    self.rule = nil
                }
                else if self.count < 0 {
                    fatalError("Out of sync")
                }
            }
        }
        return nil
    }

    func performRequest(state: FakeNetworkResponse?, requestCallback: ((HTTPURLResponse?, Data?, Error?) -> Void)? = nil) {
        switch state {
        case .none:
            if let successResponseData {
                let response = HTTPURLResponse(
                    url: URL(string: "http://cocoa.test.suite")!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": successResponseData.contentType]
                )
                requestCallback?(response, successResponseData.data, nil)
            } else {
                // Default response: no response if success response not configured
                requestCallback?(nil, nil, nil)
            }
        case .noInternet:
            requestCallback?(nil, nil, NSError(domain: NSURLErrorDomain, code: -1009, userInfo: [NSLocalizedDescriptionKey: "The Internet connection appears to be offline."]))
        case .hostUnreachable:
            requestCallback?(nil, nil, NSError(domain: NSURLErrorDomain, code: -1003, userInfo: [NSLocalizedDescriptionKey: "A server with the specified hostname could not be found."]))
        case .requestTimeout(let timeout):
            self.queue.asyncAfter(deadline: .now() + timeout) {
                requestCallback?(nil, nil, NSError(domain: NSURLErrorDomain, code: -1001, userInfo: [NSLocalizedDescriptionKey: "The request timed out."]))
            }
        case .hostInternalError(let code):
            requestCallback?(HTTPURLResponse(url: URL(string: "http://cocoa.test.suite")!, statusCode: code, httpVersion: nil, headerFields: nil), nil, nil)
        case .host400BadRequest:
            requestCallback?(HTTPURLResponse(url: URL(string: "http://cocoa.test.suite")!, statusCode: 400, httpVersion: nil, headerFields: nil), nil, nil)
        case .arbitraryError:
            requestCallback?(nil, nil, NSError(domain: AblyTestsErrorDomain, code: 1, userInfo: [NSLocalizedDescriptionKey: "error from FakeNetworkResponse.arbitraryError"]))
        }
    }

}

struct ErrorSimulator {
    let value: Int
    let description: String
    let serverId = "server-test-suite"
    var statusCode: Int = 401
    var shouldPerformRequest: Bool = false
    let stubData: Data?

    init(value: Int, description: String, statusCode: Int, shouldPerformRequest: Bool, stubData: Data?) {
        self.value = value
        self.description = description
        self.statusCode = statusCode
        self.shouldPerformRequest = shouldPerformRequest
        self.stubData = stubData
    }

    init(value: Int, description: String, statusCode: Int, shouldPerformRequest: Bool, stubDataDict: [String: Any]? = nil) {
        self.value = value
        self.description = description
        self.statusCode = statusCode
        self.shouldPerformRequest = shouldPerformRequest
        if let stubDataDict {
            self.stubData = stubDataDict.data()
        } else {
            let jsonObject: [String: Any] = [
                "error": [
                    "statusCode": self.statusCode,
                    "code": self.value,
                    "message": self.description,
                    "serverId": self.serverId,
                ]
            ]
            self.stubData = jsonObject.data()
        }
    }

    func stubResponse(_ url: URL) -> HTTPURLResponse? {
        return HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: [
            "Content-Length": String(stubData?.count ?? 0),
            "Content-Type": "application/json",
            "X-Ably-Errorcode": String(value),
            "X-Ably-Errormessage": description,
            "X-Ably-Serverid": serverId,
            ]
        )
    }
}

extension [String: Any] {
    func data() -> Data? {
        try? JSONSerialization.data(withJSONObject: self, options: JSONSerialization.WritingOptions.init(rawValue: 0))
    }
}

class MockHTTPExecutor: NSObject, ARTHTTPExecutor {

    fileprivate var errorSimulator: NSError?
    private var successResponseData: (data: Data?, contentType: String)?

    private(set) var logger = InternalLog(logger: MockVersion2Log())
    var requests: [URLRequest] = []

    func execute(_ request: URLRequest, completion callback: ((HTTPURLResponse?, Data?, Error?) -> Void)? = nil) -> (ARTCancellable & NSObjectProtocol)? {
        self.requests.append(request)

        if let simulatedError = errorSimulator, var _ = request.url {
            defer { errorSimulator = nil }
            callback?(nil, nil, simulatedError)
            return nil
        }

        if let successResponseData {
            let headerFields = [
                "X-Ably-HTTPExecutor": "MockHTTPExecutor",
                "Content-Type": successResponseData.contentType
            ]
            callback?(HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: headerFields), successResponseData.data, nil)
        } else {
            // Default response: 200 OK with no body if success response not configured
            callback?(HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["X-Ably-HTTPExecutor": "MockHTTPExecutor"]), nil, nil)
        }
        return nil
    }

    func simulateIncomingErrorOnNextRequest(_ error: NSError) {
        errorSimulator = error
    }

    /// Sets the response data to be returned for successful requests.
    ///
    /// - Parameters:
    ///   - data: The response body data to return. Pass `nil` for no response body.
    ///   - contentType: The Content-Type header value (e.g., "application/json").
    ///
    /// - Important: You must provide the content-type that matches how your data is encoded.
    ///   There is no default - the caller knows their payload format.
    func setSuccessResponse(data: Data?, contentType: String) {
        successResponseData = (data, contentType)
    }

    func reset() {
        requests.removeAll()
    }

}

/// Records each request and response for test purpose.
class TestProxyHTTPExecutor: NSObject, ARTHTTPExecutor {

    typealias HTTPExecutorCallback = (HTTPURLResponse?, Data?, Error?) -> Void

    private(set) var http: ARTHttp
    private(set) var logger: InternalLog

    private var errorSimulator: ErrorSimulator?

    private var _requests: [URLRequest] = []
    var requests: [URLRequest] {
        var result: [URLRequest] = []
        http.queue.sync {
            result = self._requests
        }
        return result
    }

    private var _responses: [HTTPURLResponse] = []
    var responses: [HTTPURLResponse] {
        var result: [HTTPURLResponse] = []
        http.queue.sync {
            result = self._responses
        }
        return result
    }

    private var callbackBeforeRequest: ((URLRequest) -> Void)?
    private var callbackAfterRequest: ((URLRequest) -> Void)?
    private var callbackProcessingDataResponse: ((Data?) -> Data)?

    init(logger: InternalLog) {
        self.logger = logger
        self.http = ARTHttp(queue: AblyTests.queue, logger: logger)
    }

    init(http: ARTHttp, logger: InternalLog) {
        self.logger = logger
        self.http = http
    }

    public func setHTTP(http: ARTHttp) {
        self.http.queue.async {
            self.http = http
        }
    }

    func setListenerAfterRequest(_ callback: ((URLRequest) -> Void)?) {
        http.queue.sync {
            self.callbackAfterRequest = callback
        }
    }

    func setListenerBeforeRequest(_ callback: ((URLRequest) -> Void)?) {
        http.queue.sync {
            self.callbackBeforeRequest = callback
        }
    }

    func setListenerProcessingDataResponse(_ callback: ((Data?) -> Data)?) {
        http.queue.sync {
            self.callbackProcessingDataResponse = callback
        }
    }

    public func execute(_ request: URLRequest, completion callback: HTTPExecutorCallback? = nil) -> (ARTCancellable & NSObjectProtocol)? {
        self._requests.append(request)

        if let performEvent = callbackBeforeRequest {
            DispatchQueue.main.async {
                performEvent(request)
            }
        }

        if let simulatedError = errorSimulator, let requestURL = request.url {
            defer {
                errorSimulator = nil
            }
            if simulatedError.shouldPerformRequest {
                return http.execute(request, completion: { response, data, error in
                    callback?(simulatedError.stubResponse(requestURL), simulatedError.stubData, nil)
                })
            }
            else {
                callback?(simulatedError.stubResponse(requestURL), simulatedError.stubData, nil)
                return nil
            }
        }

        let task = http.execute(request, completion: { response, data, error in
            if let httpResponse = response {
                DispatchQueue.main.async {
                    self._responses.append(httpResponse)
                }
            }
            if let performEvent = self.callbackProcessingDataResponse {
                DispatchQueue.main.async { [weak self] in
                    let result = performEvent(data)
                    self?.http.queue.async {
                        callback?(response, result, error)
                    }
                }
            }
            else {
                callback?(response, data, error)
            }
        })

        if let performEvent = callbackAfterRequest {
            DispatchQueue.main.async {
                performEvent(request)
            }
        }

        return task
    }

    func simulateIncomingServerErrorOnNextRequest(_ errorValue: Int, statusCode: Int = 401, description: String, data: [String: Any]? = nil) {
        http.queue.sync {
            errorSimulator = ErrorSimulator(value: errorValue, description: description, statusCode: statusCode, shouldPerformRequest: false, stubDataDict: data)
        }
    }

    func simulateIncomingServerErrorOnNextRequest(_ error: ErrorSimulator) {
        http.queue.sync {
            errorSimulator = error
        }
    }

    func simulateIncomingPayloadOnNextRequest(_ data: Data) {
        http.queue.sync {
            errorSimulator = ErrorSimulator(value: 0, description: "", statusCode: 200, shouldPerformRequest: false, stubData: data)
        }
    }
}

/// Records each message for test purpose.
class TestProxyTransport: ARTWebSocketTransport {
    /// The factory that created this TestProxyTransport instance.
    private weak var _factory: TestProxyTransportFactory?
    private var factory: TestProxyTransportFactory {
        guard let _factory else {
            preconditionFailure("Tried to fetch factory but it's already been deallocated")
        }
        return _factory
    }

    init(factory: TestProxyTransportFactory, rest: ARTRestInternal, options: ARTClientOptions, resumeKey: String?, logger: InternalLog) {
        self._factory = factory
        super.init(
            rest: rest,
            options: options,
            resumeKey: resumeKey,
            logger: logger,
            webSocketFactory: DefaultWebSocketFactory()
        )
    }

    fileprivate(set) var lastUrl: URL?

    private var _protocolMessagesReceived: [ARTProtocolMessage] = []
    var protocolMessagesReceived: [ARTProtocolMessage] {
        var result: [ARTProtocolMessage] = []
        queue.sync {
            result = self._protocolMessagesReceived
        }
        return result
    }

    private var _protocolMessagesSent: [ARTProtocolMessage] = []
    var protocolMessagesSent: [ARTProtocolMessage] {
        var result: [ARTProtocolMessage] = []
        queue.sync {
            result = self._protocolMessagesSent
        }
        return result
    }

    private var _protocolMessagesSentIgnored: [ARTProtocolMessage] = []
    var protocolMessagesSentIgnored: [ARTProtocolMessage] {
        var result: [ARTProtocolMessage] = []
        queue.sync {
            result = self._protocolMessagesSentIgnored
        }
        return result
    }

    fileprivate(set) var rawDataSent = [Data]()
    fileprivate(set) var rawDataReceived = [Data]()

    private var replacingAcksWithNacks: ARTErrorInfo?

    var ignoreWebSocket = false
    var ignoreSends = false
    var actionsIgnored = [ARTProtocolMessageAction]()

    var queue: DispatchQueue {
        return websocket?.delegateDispatchQueue ?? AblyTests.queue
    }

    private var callbackBeforeProcessingIncomingMessage: ((ARTProtocolMessage) -> Void)?
    private var callbackAfterProcessingIncomingMessage: ((ARTProtocolMessage) -> Void)?
    private var callbackBeforeProcessingOutgoingMessage: ((ARTProtocolMessage) -> Void)?
    private var callbackBeforeIncomingMessageModifier: ((ARTProtocolMessage) -> ARTProtocolMessage?)?
    private var callbackAfterIncomingMessageModifier: ((ARTProtocolMessage) -> ARTProtocolMessage?)?

    func setListenerBeforeProcessingIncomingMessage(_ callback: ((ARTProtocolMessage) -> Void)?) {
        queue.sync {
            self.callbackBeforeProcessingIncomingMessage = callback
        }
    }

    func setListenerAfterProcessingIncomingMessage(_ callback: ((ARTProtocolMessage) -> Void)?) {
        queue.sync {
            self.callbackAfterProcessingIncomingMessage = callback
        }
    }

    func setListenerBeforeProcessingOutgoingMessage(_ callback: ((ARTProtocolMessage) -> Void)?) {
        queue.sync {
            self.callbackBeforeProcessingOutgoingMessage = callback
        }
    }

    /// The modifier will be called on the internal queue.
    ///
    /// If `callback` returns nil, the message will be ignored.
    func setBeforeIncomingMessageModifier(_ callback: ((ARTProtocolMessage) -> ARTProtocolMessage?)?) {
        self.callbackBeforeIncomingMessageModifier = callback
    }

    /// The modifier will be called on the internal queue.
    ///
    /// If `callback` returns nil, the message will be ignored.
    func setAfterIncomingMessageModifier(_ callback: ((ARTProtocolMessage) -> ARTProtocolMessage?)?) {
        self.callbackAfterIncomingMessageModifier = callback
    }

    func enableReplaceAcksWithNacks(with errorInfo: ARTErrorInfo) {
        queue.sync {
            self.replacingAcksWithNacks = errorInfo
        }
    }

    func disableReplaceAcksWithNacks() {
        queue.sync {
            self.replacingAcksWithNacks = nil
        }
    }

    func emulateTokenRevokationBeforeConnected() {
        setBeforeIncomingMessageModifier { protocolMessage in
            if protocolMessage.action == .connected {
                protocolMessage.action = .disconnected
                protocolMessage.error = .create(withCode: ARTErrorCode.tokenRevoked.intValue, status: 401, message: "Test token revokation")
            }
            return protocolMessage
        }
    }

    // MARK: ARTWebSocket

    override func openWebSocket() {
        if let fakeResponse = factory.fakeNetworkResponse {
            // Skip calling -open on the underlying ARTWebSocket and instead simulate an error

            func performFakeConnectionError(_ secondsForDelay: TimeInterval, error: ARTRealtimeTransportError) {
                self.queue.asyncAfter(deadline: .now() + secondsForDelay) {
                    self.delegate?.realtimeTransportFailed(self, withError: error)
                }
            }

            guard let url = self.lastUrl else {
                fatalError("MockNetworkResponse: lastUrl should not be nil")
            }

            switch fakeResponse {
            case .noInternet,
                 .hostUnreachable,
                 .hostInternalError,
                 .host400BadRequest,
                 .arbitraryError:
                performFakeConnectionError(0.1, error: fakeResponse.transportError(for: url))
            case .requestTimeout(let timeout):
                performFakeConnectionError(0.1 + timeout, error: fakeResponse.transportError(for: url))
            }
        } else {
            // Call -open on the underlying ARTWebSocket
            super.openWebSocket()
        }

        performNetworkConnectEvent()
    }

    private func performNetworkConnectEvent() {
        guard let networkConnectEventHandler = factory.networkConnectEvent else {
            return
        }
        if let lastUrl = self.lastUrl {
            networkConnectEventHandler(self, lastUrl)
        }
        else {
            queue.asyncAfter(deadline: .now() + 0.1) {
                // Repeat until `lastUrl` is assigned.
                self.performNetworkConnectEvent()
            }
        }
    }

    override func setupWebSocket(_ params: [String: URLQueryItem], with options: ARTClientOptions, resumeKey: String?) -> URL {
        let url = super.setupWebSocket(params, with: options, resumeKey: resumeKey)
        lastUrl = url
        return url
    }

    func send(_ message: ARTProtocolMessage) {
        let data = try! encoder.encode(message)
        send(data, withSource: message)
    }

    @discardableResult
    override func send(_ data: Data, withSource decodedObject: Any?) -> Bool {
        if let networkAnswer = factory.fakeNetworkResponse, let ws = self.websocket {
            // Ignore it because it should fake a failure.
            self.webSocket(ws, didFailWithError: networkAnswer.error)
            return false
        }

        if let msg = decodedObject as? ARTProtocolMessage {
            if ignoreSends {
                _protocolMessagesSentIgnored.append(msg)
                return false
            }
            _protocolMessagesSent.append(msg)
            if let performEvent = callbackBeforeProcessingOutgoingMessage {
                DispatchQueue.main.async {
                    performEvent(msg)
                }
            }
        }
        rawDataSent.append(data)
        return super.send(data, withSource: decodedObject)
    }

    override func receive(_ original: ARTProtocolMessage) {
        if original.action == .ack || original.action == .presence {
            if let error = replacingAcksWithNacks {
                original.action = .nack
                original.error = error
            }
        }
        _protocolMessagesReceived.append(original)
        if actionsIgnored.contains(original.action) {
            return
        }
        if let performEvent = callbackBeforeProcessingIncomingMessage {
            DispatchQueue.main.async {
                performEvent(original)
            }
        }
        var msg = original
        if let performEvent = callbackBeforeIncomingMessageModifier {
            guard let modifiedMsg = performEvent(msg) else {
                return
            }
            msg = modifiedMsg
        }
        super.receive(msg)
        if let performEvent = callbackAfterIncomingMessageModifier {
            guard let modifiedMsg = performEvent(msg) else {
                return
            }
            msg = modifiedMsg
        }
        if let performEvent = callbackAfterProcessingIncomingMessage {
            DispatchQueue.main.async {
                performEvent(msg)
            }
        }
    }

    override func receive(with data: Data) -> ARTProtocolMessage? {
        rawDataReceived.append(data)
        return super.receive(with: data)
    }

    override func webSocketDidOpen(_ webSocket: ARTWebSocket) {
        if !ignoreWebSocket {
            super.webSocketDidOpen(webSocket)
        }
    }

    override func webSocket(_ webSocket: ARTWebSocket, didFailWithError error: Error) {
        if !ignoreWebSocket {
            super.webSocket(webSocket, didFailWithError: error)
        }
    }

    override func webSocket(_ webSocket: ARTWebSocket, didReceiveMessage message: Any?) {
        if let networkAnswer = factory.fakeNetworkResponse, let ws = self.websocket {
            // Ignore it because it should fake a failure.
            self.webSocket(ws, didFailWithError: networkAnswer.error)
            return
        }

        if !ignoreWebSocket {
            super.webSocket(webSocket, didReceiveMessage: message as Any)
        }
    }

    override func webSocket(_ webSocket: ARTWebSocket, didCloseWithCode code: Int, reason: String?, wasClean: Bool) {
        if !ignoreWebSocket {
            super.webSocket(webSocket, didCloseWithCode: code, reason: reason, wasClean: wasClean)
        }
    }

    // MARK: Helpers

    func simulateTransportSuccess(clientId: String? = nil) {
        self.ignoreWebSocket = true
        let msg = ARTProtocolMessage()
        msg.action = .connected
        msg.connectionId = "x-xxxxxxxx"
        msg.connectionKey = "xxxxxxx-xxxxxxxxxxxxxx-xxxxxxxx"
        msg.connectionDetails = ARTConnectionDetails(clientId: clientId, connectionKey: "a8c10!t-3D0O4ejwTdvLkl-b33a8c10", maxMessageSize: 16384, maxFrameSize: 262144, maxInboundRate: 250, connectionStateTtl: 60, serverId: "testServerId", maxIdleInterval: 15000, objectsGCGracePeriod: 86_400_000, siteCode: nil)
        super.receive(msg)
    }

}


// MARK: - Extensions

extension Sequence where Iterator.Element == Data {

    func toMsgPackArray<T>() -> [T] {
        let msgPackEncoder = ARTMsgPackEncoder()
        return map({ try! msgPackEncoder.decode($0) as! T })
    }

}

func + <K,V> (left: Dictionary<K,V>, right: Dictionary<K,V>?) -> Dictionary<K,V> {
    guard let right = right else { return left }
    return left.reduce(right) {
        var new = $0 as [K:V]
        new.updateValue($1.1, forKey: $1.0)
        return new
    }
}

func += <K,V> (left: inout Dictionary<K,V>, right: Dictionary<K,V>?) {
    guard let right = right else { return }
    right.forEach { key, value in
        left.updateValue(value, forKey: key)
    }
}

extension Collection {

    /// Returns the element at the specified index iff it is within bounds, otherwise nil.
    public func at(_ i: Index) -> Iterator.Element? {
        return (i >= startIndex && i < endIndex) ? self[i] : nil
    }

}

extension Dictionary {

    /// Returns the element at the specified index iff it is within bounds, otherwise nil.
    public func at(_ key: Key) -> Iterator.Element? {
        guard let index = index(forKey: key) else {
            return nil
        }
        return at(index)
    }

}

extension ARTMessage {

    open override func isEqual(_ object: Any?) -> Bool {
        if let other = object as? ARTMessage {
            return self.name == other.name &&
                self.encoding == other.encoding &&
                self.data as! NSObject == other.data as! NSObject
        }

        return super.isEqual(object)
    }

}

extension NSObject {

    var toBase64: String {
        return (try? JSONSerialization.data(withJSONObject: self, options: JSONSerialization.WritingOptions(rawValue: 0)).base64EncodedString(options: NSData.Base64EncodingOptions(rawValue: 0))) ?? ""
    }

}

extension Data {

    var toBase64: String {
        return self.base64EncodedString(options: NSData.Base64EncodingOptions(rawValue: 0))
    }

    var toUTF8String: String {
        return String(data: self, encoding: .utf8)!
    }

    var bytes: [UInt8]{
        return [UInt8](self)
    }

    var hexString: String {
        var result = ""

        for byte in bytes {
            result += String(format: "%02x", UInt(byte))
        }

        return result.uppercased()
    }

}

extension NSData {

    var hexString: String {
        var result = ""

        var bytes = [UInt8](repeating: 0, count: length)
        getBytes(&bytes, length: length)

        for byte in bytes {
            result += String(format: "%02x", UInt(byte))
        }

        return result.uppercased()
    }

}

extension NSRegularExpression {

    class func match(_ value: String?, pattern: String) -> Bool {
        guard let value = value else {
            return false
        }
        let options = NSRegularExpression.Options()
        let regex = try! NSRegularExpression(pattern: pattern, options: options)
        let range = NSMakeRange(0, value.lengthOfBytes(using: String.Encoding.utf8))
        return regex.rangeOfFirstMatch(in: value, options: [], range: range).location != NSNotFound
    }

    class func extract(_ value: String?, pattern: String) -> String? {
        guard let value = value else {
            return nil
        }
        let options = NSRegularExpression.Options()
        let regex = try! NSRegularExpression(pattern: pattern, options: options)
        let range = NSMakeRange(0, value.lengthOfBytes(using: String.Encoding.utf8))
        let result = regex.firstMatch(in: value, options: [], range: range)
        guard let textRange = result?.range(at: 0) else { return nil }
        let convertedRange =  value.index(value.startIndex, offsetBy: textRange.location)..<value.index(value.startIndex, offsetBy: textRange.location+textRange.length)
        return String(value[convertedRange.lowerBound..<convertedRange.upperBound])
    }

}

extension String {

    func replace(_ value: String, withString string: String) -> String {
        return self.replacingOccurrences(of: value, with: string, options: NSString.CompareOptions.literal, range: nil)
    }

}

extension ARTRealtime {

    var transportFactory: TestProxyTransportFactory? {
        self.internal.options.testOptions.transportFactory as? TestProxyTransportFactory
    }

    func simulateLostConnection() {
        self.internal.onDisconnected()
    }

    func simulateLostConnectionAndState() {
        //1. Abruptly disconnect
        //2. Change the `Connection#id` and `Connection#key` before the client
        //   library attempts to reconnect and resume the connection
        self.connection.internal.setId("lost")
        self.connection.internal.setKey("xxxxx!xxxxxxx-xxxxxxxx-xxxxxxxx")
        self.internal.onDisconnected()
    }

    func simulateSuspended(beforeSuspension beforeSuspensionCallback: @escaping (_ done: @escaping () -> ()) -> Void) {
        waitUntil(timeout: testTimeout) { done in
            self.connection.once(.disconnected) { _ in
                beforeSuspensionCallback(done)
                self.internal.onSuspended()
            }
            self.internal.onDisconnected()
        }
    }

    func simulateNoInternetConnection(transportFactory: TestProxyTransportFactory) {
        guard let reachability = self.internal.reachability as? TestReachability else {
            fatalError("Expected test reachability")
        }

        AblyTests.queue.async {
            transportFactory.fakeNetworkResponse = .noInternet
            reachability.simulate(false)
        }
    }

    func simulateNoInternetConnection(during timeout: TimeInterval? = nil) {
        guard let transportFactory = self.transportFactory else {
            fatalError("Expected test TestProxyTransportFactory")
        }
        simulateNoInternetConnection(transportFactory: transportFactory)
        if let timeout {
            simulateRestoreInternetConnection(after: timeout, transportFactory: transportFactory)
        }
    }

    func simulateRestoreInternetConnection(after seconds: TimeInterval? = nil, transportFactory: TestProxyTransportFactory) {
        guard let reachability = self.internal.reachability as? TestReachability else {
            fatalError("Expected test reachability")
        }

        AblyTests.queue.asyncAfter(deadline: .now() + (seconds ?? 0)) {
            transportFactory.fakeNetworkResponse = nil
            reachability.simulate(true)
        }
    }

    func simulateRestoreInternetConnection(after seconds: TimeInterval? = nil) {
        guard let transportFactory = self.transportFactory else {
            fatalError("Expected test TestProxyTransportFactory")
        }
        simulateRestoreInternetConnection(after: seconds, transportFactory: transportFactory)
    }

    @discardableResult
    func waitUntilConnected() -> Bool {
        var connected = false
        waitUntil(timeout: testTimeout) { done in
            self.connection.once(.connected) { _ in
                connected = true
                done()
            }
        }
        return connected
    }

    func waitForPendingMessages() {
        expect(self.internal.pendingMessages).toEventually(haveCount(0),timeout: testTimeout)
    }

    func overrideConnectionStateTTL(_ ttl: TimeInterval) -> HookToken {
        return self.internal.testSuite_injectIntoMethod(before: NSSelectorFromString("connectionStateTtl")) {
            self.internal.connectionStateTtl = ttl
        }
    }

    func dispose() {
        let names = self.channels.map({ ($0 as! ARTRealtimeChannel).name })
        for name in names {
            self.channels.release(name)
        }
        self.connection.off()
    }

    func requestPresenceSyncForChannel(_ channel: ARTRealtimeChannel) {
        let syncMessage = ARTProtocolMessage()
        syncMessage.action = .sync
        syncMessage.channel = channel.name
        guard let transport = self.internal.transport as? TestProxyTransport else {
            fail("TestProxyTransport is not set"); return
        }
        transport.send(syncMessage)
    }
}

extension ARTWebSocketTransport {

    func simulateIncomingNormalClose() {
        let CLOSE_NORMAL = 1000
        self.setState(ARTRealtimeTransportState.closing)
        let webSocketDelegate = self as ARTWebSocketDelegate
        webSocketDelegate.webSocket?(self.websocket!, didCloseWithCode: CLOSE_NORMAL, reason: "", wasClean: true)
    }

    func simulateIncomingAbruptlyClose() {
        let CLOSE_ABNORMAL = 1006
        let webSocketDelegate = self as ARTWebSocketDelegate
        webSocketDelegate.webSocket?(self.websocket!, didCloseWithCode: CLOSE_ABNORMAL, reason: "connection was closed abnormally", wasClean: false)
    }

    func simulateIncomingError() {
        // Simulate receiving an ERROR ProtocolMessage, which should put a client into the FAILED state (per RTN15i)
        let protocolMessage = ARTProtocolMessage()
        protocolMessage.action = .error
        protocolMessage.error = ARTErrorInfo.create(withCode: 50000 /* arbitrarily chosen */, message: "Fail test")
        receive(protocolMessage)
    }
}

extension ARTAuthInternal {

    func testSuite_forceTokenToExpire(_ file: StaticString = #file, line: UInt = #line) {
        guard let tokenDetails = self.tokenDetails else {
            XCTFail("TokenDetails is nil", file: file, line: line)
            return
        }
        self.setTokenDetails(ARTTokenDetails(
            token: tokenDetails.token,
            expires: Date().addingTimeInterval(-1.0),
            issued: Date().addingTimeInterval(-1.0),
            capability: tokenDetails.capability,
            clientId: tokenDetails.clientId
            )
        )
    }

}

extension ARTPresenceMessage {

    convenience init(clientId: String, action: ARTPresenceAction, connectionId: String, id: String, timestamp: Date = Date()) {
        self.init()
        self.action = action
        self.clientId = clientId
        self.connectionId = connectionId
        self.id = id
        self.timestamp = timestamp
    }

}

extension ARTMessage {

    convenience init(id: String, name: String? = nil, data: Any) {
        self.init(name: name, data: data)
        self.id = id
    }

}
#if hasFeature(RetroactiveAttribute)
extension ARTRealtimeConnectionState : @retroactive CustomStringConvertible {
    public var description : String {
        return ARTRealtimeConnectionStateToStr(self)
    }
}

extension ARTRealtimeConnectionEvent : @retroactive CustomStringConvertible {
    public var description : String {
        return ARTRealtimeConnectionEventToStr(self)
    }
}

extension ARTProtocolMessageAction : @retroactive CustomStringConvertible {
    public var description : String {
        return ARTProtocolMessageActionToStr(self)
    }
}

extension ARTRealtimeChannelState : @retroactive CustomStringConvertible {
    public var description : String {
        return ARTRealtimeChannelStateToStr(self)
    }
}

extension ARTChannelEvent : @retroactive CustomStringConvertible {
    public var description : String {
        return ARTChannelEventToStr(self)
    }
}

extension ARTPresenceAction : @retroactive CustomStringConvertible {
    public var description : String {
        return ARTPresenceActionToStr(self)
    }
}

#else

extension ARTRealtimeConnectionState : CustomStringConvertible {
    public var description : String {
        return ARTRealtimeConnectionStateToStr(self)
    }
}

extension ARTRealtimeConnectionEvent : CustomStringConvertible {
    public var description : String {
        return ARTRealtimeConnectionEventToStr(self)
    }
}

extension ARTProtocolMessageAction : CustomStringConvertible {
    public var description : String {
        return ARTProtocolMessageActionToStr(self)
    }
}

extension ARTRealtimeChannelState : CustomStringConvertible {
    public var description : String {
        return ARTRealtimeChannelStateToStr(self)
    }
}

extension ARTChannelEvent : CustomStringConvertible {
    public var description : String {
        return ARTChannelEventToStr(self)
    }
}

extension ARTPresenceAction : CustomStringConvertible {
    public var description : String {
        return ARTPresenceActionToStr(self)
    }
}

#endif

// MARK: - Custom Nimble Matchers

/// A Nimble matcher that succeeds when two dates are quite the same.
public func beCloseTo(_ expectedValue: Date) -> Nimble.Predicate<Date> {
    let errorMessage = "be close to <\(expectedValue)> (within 0.5)"
    return Predicate.simple(errorMessage) { actualExpression in
        guard let actualValue = try actualExpression.evaluate() else {
            return .fail
        }
        if abs(actualValue.timeIntervalSince1970 - expectedValue.timeIntervalSince1970) < 0.5 {
            return .matches
        }
        return .doesNotMatch
    }
}

/// A Nimble matcher that succeeds when a param exists.
public func haveParam(_ key: String, withValue expectedValue: String? = nil) -> Nimble.Predicate<String> {
    let errorMessage = "param <\(key)=\(expectedValue ?? "nil")> exists"
    return Predicate.simple(errorMessage) { actualExpression in
        guard let actualValue = try actualExpression.evaluate() else {
            return .fail
        }
        let queryItems = actualValue.components(separatedBy: "&")
        for item in queryItems {
            let param = item.components(separatedBy: "=")
            if let currentKey = param.first, let currentValue = param.last, currentKey == key && currentValue == expectedValue {
                return .matches
            }
        }
        return .doesNotMatch
    }
}

/// A Nimble matcher that succeeds when a param value starts with a particular string.
public func haveParam(_ key: String, hasPrefix expectedValue: String) -> Nimble.Predicate<String> {
    let errorMessage = "param <\(key)> has prefix \(expectedValue)"
    return Predicate.simple(errorMessage) { actualExpression in
        guard let actualValue = try actualExpression.evaluate() else {
            return .fail
        }
        let queryItems = actualValue.components(separatedBy: "&")
        for item in queryItems {
            let param = item.components(separatedBy: "=")
            if let currentKey = param.first, let currentValue = param.last, currentKey == key && currentValue.hasPrefix(expectedValue) {
                return .matches
            }
        }
        return .doesNotMatch
    }
}


// http://stackoverflow.com/a/26502285/818420
extension String {

    /// Create `NSData` from hexadecimal string representation
    ///
    /// This takes a hexadecimal representation and creates a `NSData` object. Note, if the string has any spaces or non-hex characters (e.g. starts with '<' and with a '>'), those are ignored and only hex characters are processed.
    ///
    /// - returns: Data represented by this hexadecimal string.

    func dataFromHexadecimalString() -> Data? {
        let data = NSMutableData(capacity: self.count / 2)

        let regex = try! NSRegularExpression(pattern: "[0-9a-f]{1,2}", options: .caseInsensitive)
        regex.enumerateMatches(in: self, options: [], range: NSMakeRange(0, self.count)) { match, flags, stop in
            let byteString = (self as NSString).substring(with: match!.range)
            var num = UInt8(byteString, radix: 16)
            data?.append(&num, length: 1)
        }

        return data as Data?
    }
}

@objc class TestReachability : NSObject, ARTReachability {
    var host: String?
    var callback: ((Bool) -> Void)?
    var queue: DispatchQueue

    required init(logger: InternalLog, queue: DispatchQueue) {
        self.queue = queue
    }

    func listen(forHost host: String, callback: @escaping (Bool) -> Void) {
        self.host = host
        self.callback = callback
    }

    func off() {
        self.host = nil
        self.callback = nil
    }

    func simulate(_ reachable: Bool) {
        self.queue.async {
            self.callback!(reachable)
        }
    }
}

extension HTTPURLResponse {

    /**
     This is broken since Swift 3. The access is now case-sensitive.
     Regression: HTTPURLResponse allHeaderFields is now case-sensitive
     https://bugs.swift.org/browse/SR-2429
     - Returns: A dictionary containing all the HTTP header fields of the
     receiver.
     */
    var objc_allHeaderFields: NSDictionary {
        // Disables bridging and calls the Objective-C implementation
        //of the private NSDictionary subclass in CFNetwork directly
        return allHeaderFields as NSDictionary
    }

    /**
     The value which corresponds to the given header
     field. Note that, in keeping with the HTTP RFC, HTTP header field
     names are case-insensitive.
     - Parameter field: the header field name to use for the lookup (case-insensitive).
     */
    func value(forHTTPHeaderField field: String) -> String? {
        return objc_allHeaderFields.object(forKey: field) as? String
    }

}

extension ARTHTTPPaginatedResponse {

    var headers: NSDictionary {
        return response.objc_allHeaderFields
    }
}

protocol ARTHasInternal {
    associatedtype Internal
    func unwrapAsync(_: @escaping (Internal) -> ())
}

extension ARTRealtime: ARTHasInternal {
    typealias Internal = ARTRealtimeInternal
    func unwrapAsync(_ use: @escaping (Internal) -> ()) {
        self.internalAsync(use)
    }
}

extension DispatchTimeInterval {
    /// Convert dispatch time interval to older style time interval for use with XCTest APIs.
    func toTimeInterval() -> TimeInterval {
        // Based on: https://stackoverflow.com/a/47716381/392847
        switch self {
        case .seconds(let value):
            return Double(value)
        case .milliseconds(let value):
            return Double(value) * 0.001
        case .microseconds(let value):
            return Double(value) * 0.000001
        case .nanoseconds(let value):
            return Double(value) * 0.000000001
        case .never:
            return Double.greatestFiniteMagnitude;
        @unknown default:
            fatalError("Unhandled DispatchTimeInterval unit.")
        }
    }

    /// Return a new dispatch time interval computed from this one, multipled by the supplied amount.
    func multiplied(by multiplier: Double) -> DispatchTimeInterval {
        switch self {
        case .seconds(let value):
            return .seconds(Int(Double(value) * multiplier))
        case .milliseconds(let value):
            return .milliseconds(Int(Double(value) * multiplier))
        case .microseconds(let value):
            return .microseconds(Int(Double(value) * multiplier))
        case .nanoseconds(let value):
            return .nanoseconds(Int(Double(value) * multiplier))
        case .never:
            return .never
        @unknown default:
            fatalError("Unhandled DispatchTimeInterval unit.")
        }
    }

    /// Return a new dispatch time interval computed from this one, incremented by the supplied amount, to no less than millisecond precision.
    func incremented(by interval: TimeInterval) -> DispatchTimeInterval {
        // interval is a TimeInterval which is a Double which is in SECONDS
        switch self {
        case .seconds(let value):
            // rounding to millisecond precision, which is fine for the purposes of our test needs
            return .milliseconds(Int(1000.0 * (Double(value) + interval)))
        case .milliseconds(let value):
            let millisecondIncrement = interval * 1000.0
            return .milliseconds(Int(Double(value) + millisecondIncrement))
        case .microseconds(let value):
            let microsecondIncrement = interval * 1000000.0
            return .microseconds(Int(Double(value) + microsecondIncrement))
        case .nanoseconds(let value):
            let nanosecondIncrement = interval * 1000000000.0
            return .nanoseconds(Int(Double(value) + nanosecondIncrement))
        case .never:
            return .never
        @unknown default:
            fatalError("Unhandled DispatchTimeInterval unit.")
        }
    }
}

extension ARTErrorCode {

    var intValue: NSInteger {
        return NSInteger(rawValue)
    }
}
