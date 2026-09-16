#if os(iOS)
import AblyPubSubDevice
import Nimble
import XCTest

private var rest: HttpClient!
private var mockHttpExecutor: MockHTTPExecutor!
private var storage: MockDeviceStorage!
private var localDevice: LocalDevice!

private let recipient = [
    "clientId": "bob",
]

private let payload = [
    "notification": [
        "title": "Welcome",
    ],
]

private let quxChannelName = "pushenabled:qux"

private let subscription = PushChannelSubscription(clientId: "newClient", channel: quxChannelName)

class PushAdminTests: XCTestCase {
    private static let deviceDetails: DeviceDetails = {
        let deviceDetails = DeviceDetails(id: "testDeviceDetails")
        deviceDetails.platform = "ios"
        deviceDetails.formFactor = "phone"
        deviceDetails.metadata = [String : String]()
        deviceDetails.push.recipient = [
            "transportType": "apns",
            "deviceToken": "foo",
        ]
        return deviceDetails
    }()

    private static let deviceDetails1ClientA: DeviceDetails = {
        let deviceDetails = DeviceDetails(id: "deviceDetails1ClientA")
        deviceDetails.platform = "android"
        deviceDetails.formFactor = "tablet"
        deviceDetails.clientId = "clientA"
        deviceDetails.metadata = [String : String]()
        deviceDetails.push.recipient = [
            "transportType": "gcm",
            "registrationToken": "qux",
        ]
        return deviceDetails
    }()

    private static let deviceDetails2ClientA: DeviceDetails = {
        let deviceDetails = DeviceDetails(id: "deviceDetails2ClientA")
        deviceDetails.platform = "android"
        deviceDetails.formFactor = "tablet"
        deviceDetails.clientId = "clientA"
        deviceDetails.metadata = [String : String]()
        deviceDetails.push.recipient = [
            "transportType": "gcm",
            "registrationToken": "qux",
        ]
        return deviceDetails
    }()

    private static let deviceDetails3ClientB: DeviceDetails = {
        let deviceDetails = DeviceDetails(id: "deviceDetails3ClientB")
        deviceDetails.platform = "android"
        deviceDetails.formFactor = "tablet"
        deviceDetails.clientId = "clientB"
        deviceDetails.metadata = [String : String]()
        deviceDetails.push.recipient = [
            "transportType": "gcm",
            "registrationToken": "qux",
        ]
        return deviceDetails
    }()

    private static let allDeviceDetails: [DeviceDetails] = [
        deviceDetails,
        deviceDetails1ClientA,
        deviceDetails2ClientA,
        deviceDetails3ClientB,
    ]

    private static let subscriptionFooDevice1 = PushChannelSubscription(deviceId: "deviceDetails1ClientA", channel: "pushenabled:foo")
    private static let subscriptionFooDevice2 = PushChannelSubscription(deviceId: "deviceDetails2ClientA", channel: "pushenabled:foo")
    private static let subscriptionBarDevice2 = PushChannelSubscription(deviceId: "deviceDetails2ClientA", channel: "pushenabled:bar")
    private static let subscriptionFooClientA = PushChannelSubscription(clientId: "clientA", channel: "pushenabled:foo")
    private static let subscriptionFooClientB = PushChannelSubscription(clientId: "clientB", channel: "pushenabled:foo")
    private static let subscriptionBarClientB = PushChannelSubscription(clientId: "clientB", channel: "pushenabled:bar")

    private static let allSubscriptions: [PushChannelSubscription] = [
        subscriptionFooDevice1,
        subscriptionFooDevice2,
        subscriptionBarDevice2,
        subscriptionFooClientA,
        subscriptionFooClientB,
        subscriptionBarClientB,
    ]

    private static let allSubscriptionsChannels: [String] = {
        var seen = Set<String>()
        return allSubscriptions.filter { seen.insert($0.channel).inserted }.map { $0.channel }
    }()

    override class func setUp() {
        super.setUp()
        let test = Test() // a slight abuse of the meaning of Test, but we only have one instance of +setUp so doesn't seem worth worrying over
        let options: ClientOptions
        do {
            options = try AblyTests.commonAppSetup(for: test)
        } catch {
            fatalError("commonAppSetup failed: \(error)")
        }
        options.pushFullWait = true
        options.dispatchQueue = AblyTests.createUserQueue(for: test)
        let rest = HttpClient(options: options)
        rest.internal.storage = MockDeviceStorage()
        let group = DispatchGroup()

        for device in allDeviceDetails {
            group.enter()
            rest.push.admin.deviceRegistrations.save(device) { error in
                assert(error == nil, error?.message ?? "no message")
                group.leave()
            }
        }
        group.wait()

        for subscription in allSubscriptions {
            group.enter()
            rest.push.admin.channelSubscriptions.save(subscription) { error in
                assert(error == nil, error?.message ?? "no message")
                group.leave()
            }
        }

        group.wait()
    }

    override class func tearDown() {
        let test = Test() // a slight abuse of the meaning of Test, but we only have one instance of +tearDown so doesn't seem worth worrying over
        let options: ClientOptions
        do {
            options = try AblyTests.commonAppSetup(for: test)
        } catch {
            fatalError("commonAppSetup failed: \(error)")
        }
        options.dispatchQueue = AblyTests.createUserQueue(for: test)
        let rest = HttpClient(options: options)
        rest.internal.storage = MockDeviceStorage()
        let group = DispatchGroup()

        for device in allDeviceDetails {
            group.enter()
            rest.push.admin.deviceRegistrations.remove(device.id) { _ in
                group.leave()
            }
        }

        for subscription in allSubscriptions {
            group.enter()
            rest.push.admin.channelSubscriptions.remove(subscription) { _ in
                group.leave()
            }
        }

        super.tearDown()
    }

    // XCTest invokes this method before executing the first test in the test suite. We use it to ensure that the global variables are initialized at the same moment, and in the same order, as they would have been when we used the Quick testing framework.
    override class var defaultTestSuite: XCTestSuite {
        _ = rest
        _ = mockHttpExecutor
        _ = storage
        _ = localDevice
        _ = recipient
        _ = payload
        _ = quxChannelName
        _ = subscription

        return super.defaultTestSuite
    }

    override func setUp() {
        super.setUp()

        rest = HttpClient(key: "xxxx:xxxx")
        mockHttpExecutor = MockHTTPExecutor()
        rest.internal.httpExecutor = mockHttpExecutor
        storage = MockDeviceStorage()
        rest.internal.storage = storage
        rest.internal.setupLocalDevice_nosync()
        localDevice = rest.device
    }

    // RSH1a

    func test__001__publish__should_perform_an_HTTP_request_to__push_publish() throws {
        waitUntil(timeout: testTimeout) { done in
            rest.push.admin.publish(recipient, data: payload) { error in
                XCTAssertNil(error)
                done()
            }
        }

        let request = try XCTUnwrap(mockHttpExecutor.requests.first, "No request found")
        let url = try XCTUnwrap(request.url, "No request url found")

        expect(url.absoluteString).to(contain("/push/publish"))

        switch extractBodyAsMsgPack(request) {
        case let .failure(error):
            XCTFail(error)
        case let .success(httpBody):
            guard let bodyRecipient = httpBody.unbox["recipient"] as? [String: String] else {
                fail("recipient is missing"); return
            }
            XCTAssertEqual(bodyRecipient, recipient)

            guard let bodyPayload = httpBody.unbox["notification"] as? [String: String] else {
                fail("notification is missing"); return
            }
            XCTAssertEqual(bodyPayload, payload["notification"])
        }
    }

    func test__002__publish__should_publish_successfully() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let realtime = RealtimeClient(options: options)
        defer { realtime.dispose(); realtime.close() }
        let channel = realtime.channels.get("pushenabled:\(test.uniqueChannelName())") // works with pure test.uniqueChannelName() as well
        let publishObject = ["transportType": "ablyChannel",
                             "channel": channel.name,
                             "ablyKey": options.key!,
                             "ablyUrl": "https://\(options.restHost)"]

        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                XCTAssertNil(error)
                done()
            }
        }

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)
            channel.subscribe("__ably_push__") { message in
                guard let data = message.data as? String else {
                    fail("Failure in reading returned data"); partialDone(); return
                }
                expect(data).to(contain("foo"))
                partialDone()
            }
            realtime.push.admin.publish(publishObject, data: ["data": ["foo": "bar"]]) { error in
                XCTAssertNil(error)
                partialDone()
            }
        }
    }

    func test__003__publish__should_fail_with_a_bad_recipient() throws {
        let test = Test()
        let realtime = RealtimeClient(options: try AblyTests.commonAppSetup(for: test))
        defer { realtime.dispose(); realtime.close() }
        let channel = realtime.channels.get("pushenabled:\(test.uniqueChannelName())") // works with pure test.uniqueChannelName() as well

        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                XCTAssertNil(error)
                done()
            }
        }

        waitUntil(timeout: testTimeout) { done in
            channel.subscribe("__ably_push__") { _ in
                fail("Should not be called")
            }
            realtime.push.admin.publish(["foo": "bar"], data: ["data": ["foo": "bar"]]) { error in
                guard let error = error else {
                    fail("Error is missing"); done(); return
                }
                XCTAssertEqual(error.statusCode, 400)
                XCTAssertTrue(error.code == ErrorCode.badRequest.rawValue) // recipient must contain a 'deviceId', 'clientId', or 'transportType'
                done()
            }
        }
    }

    func test__004__publish__should_fail_with_an_empty_recipient() throws {
        let test = Test()
        let realtime = RealtimeClient(options: try AblyTests.commonAppSetup(for: test))
        defer { realtime.dispose(); realtime.close() }
        let channel = realtime.channels.get("pushenabled:\(test.uniqueChannelName())") // works with pure test.uniqueChannelName() as well

        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                XCTAssertNil(error)
                done()
            }
        }

        waitUntil(timeout: testTimeout) { done in
            channel.subscribe("__ably_push__") { _ in
                fail("Should not be called")
            }
            realtime.push.admin.publish([:], data: ["data": ["foo": "bar"]]) { error in
                guard let error = error else {
                    fail("Error is missing"); done(); return
                }
                expect(error.message.lowercased()).to(contain("recipient is missing"))
                done()
            }
        }
    }

    func test__005__publish__should_fail_with_an_empty_payload() throws {
        let test = Test()
        let realtime = RealtimeClient(options: try AblyTests.commonAppSetup(for: test))
        defer { realtime.dispose(); realtime.close() }
        let channel = realtime.channels.get("pushenabled:\(test.uniqueChannelName())") // works with pure test.uniqueChannelName() as well

        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                XCTAssertNil(error)
                done()
            }
        }

        waitUntil(timeout: testTimeout) { done in
            channel.subscribe("__ably_push__") { _ in
                fail("Should not be called")
            }
            realtime.push.admin.publish(["ablyChannel": channel.name], data: [:]) { error in
                guard let error = error else {
                    fail("Error is missing"); done(); return
                }
                expect(error.message.lowercased()).to(contain("data payload is missing"))
                done()
            }
        }
    }

    // RSH1b1

    func test__006__Device_Registrations__get__should_return_a_device() throws {
        let test = Test()
        let realtime = RealtimeClient(options: try AblyTests.commonAppSetup(for: test))
        defer { realtime.dispose(); realtime.close() }
        waitUntil(timeout: testTimeout) { done in
            realtime.push.admin.deviceRegistrations.get("testDeviceDetails") { device, error in
                guard let device = device else {
                    fail("Device is missing"); done(); return
                }
                XCTAssertEqual(device, Self.deviceDetails)
                XCTAssertNil(error)
                done()
            }
        }
    }

    func test__007__Device_Registrations__get__should_not_return_a_device_if_it_doesnt_exist() throws {
        let test = Test()
        let realtime = RealtimeClient(options: try AblyTests.commonAppSetup(for: test))
        defer { realtime.dispose(); realtime.close() }
        waitUntil(timeout: testTimeout) { done in
            realtime.push.admin.deviceRegistrations.get("madeup") { device, error in
                XCTAssertNil(device)
                guard let error = error else {
                    fail("Error should not be empty"); done(); return
                }
                XCTAssertEqual(error.statusCode, 404)
                XCTAssertTrue(error.code == ErrorCode.notFound.rawValue)
                done()
            }
        }
    }

    func test__008__Device_Registrations__get__push_device_authentication__should_include_DeviceIdentityToken_HTTP_header() throws {
        let test = Test()
        let realtime = RealtimeClient(options: try AblyTests.commonAppSetup(for: test))
        defer { realtime.dispose(); realtime.close() }
        realtime.internal.rest.httpExecutor = mockHttpExecutor

        let testIdentityTokenDetails = DeviceIdentityTokenDetails(
            token: "123456",
            issued: Date(),
            expires: Date.distantFuture,
            capability: "",
            clientId: ""
        )

        XCTAssertNil(localDevice.identityTokenDetails)
        realtime.internal.rest.device.setAndPersistIdentityTokenDetails(testIdentityTokenDetails)
        defer { realtime.internal.rest.device.setAndPersistIdentityTokenDetails(nil) }

        waitUntil(timeout: testTimeout) { done in
            realtime.push.admin.deviceRegistrations.get(localDevice.id) { _, _ in
                done()
            }
        }

        let request = try XCTUnwrap(mockHttpExecutor.requests.first, "No request found")
        let authorization = request.allHTTPHeaderFields?["X-Ably-DeviceToken"]

        XCTAssertEqual(authorization, testIdentityTokenDetails.token.base64Encoded())
    }

    func test__009__Device_Registrations__get__push_device_authentication__should_include_DeviceSecret_HTTP_header() throws {
        let test = Test()
        let realtime = RealtimeClient(options: try AblyTests.commonAppSetup(for: test))
        defer { realtime.dispose(); realtime.close() }
        realtime.internal.rest.httpExecutor = mockHttpExecutor

        waitUntil(timeout: testTimeout) { done in
            realtime.push.admin.deviceRegistrations.get(localDevice.id) { _, _ in
                done()
            }
        }

        let request = try XCTUnwrap(mockHttpExecutor.requests.first, "No request found")
        let authorization = request.allHTTPHeaderFields?["X-Ably-DeviceSecret"]

        XCTAssertEqual(authorization, localDevice.secret)
    }

    // RSH1b2

    func test__010__Device_Registrations__list__should_list_devices_by_id() throws {
        let test = Test()
        let realtime = RealtimeClient(options: try AblyTests.commonAppSetup(for: test))
        defer { realtime.dispose(); realtime.close() }
        waitUntil(timeout: testTimeout) { done in
            realtime.push.admin.deviceRegistrations.list(["deviceId": "testDeviceDetails"]) { result, error in
                guard let result = result else {
                    fail("PaginatedResult should not be empty"); done(); return
                }
                XCTAssertEqual(result.items.count, 1)
                XCTAssertNil(error)
                done()
            }
        }
    }

    func test__011__Device_Registrations__list__should_list_devices_by_client_id() throws {
        let test = Test()
        let realtime = RealtimeClient(options: try AblyTests.commonAppSetup(for: test))
        defer { realtime.dispose(); realtime.close() }
        waitUntil(timeout: testTimeout) { done in
            realtime.push.admin.deviceRegistrations.list(["clientId": "clientA"]) { result, error in
                guard let result = result else {
                    fail("PaginatedResult should not be empty"); done(); return
                }
                XCTAssertEqual(result.items.count, Self.allDeviceDetails.filter { $0.clientId == "clientA" }.count)
                XCTAssertNil(error)
                done()
            }
        }
    }

    func test__012__Device_Registrations__list__should_list_devices_sorted() throws {
        let test = Test()
        let realtime = RealtimeClient(options: try AblyTests.commonAppSetup(for: test))
        defer { realtime.dispose(); realtime.close() }
        waitUntil(timeout: testTimeout) { done in
            realtime.push.admin.deviceRegistrations.list(["direction": "forwards"]) { result, error in
                guard let result = result else {
                    fail("PaginatedResult should not be empty"); done(); return
                }
                XCTAssertEqual(result.items.count, Self.allDeviceDetails.count)
                XCTAssertNil(error)
                done()
            }
        }
    }

    func test__013__Device_Registrations__list__should_return_an_empty_list_when_id_does_not_exist() throws {
        let test = Test()
        let realtime = RealtimeClient(options: try AblyTests.commonAppSetup(for: test))
        defer { realtime.dispose(); realtime.close() }
        waitUntil(timeout: testTimeout) { done in
            realtime.push.admin.deviceRegistrations.list(["deviceId": "madeup"]) { result, error in
                guard let result = result else {
                    fail("PaginatedResult should not be empty"); done(); return
                }
                XCTAssertEqual(result.items.count, 0)
                XCTAssertNil(error)
                done()
            }
        }
    }

    // RSH1b4

    func test__014__Device_Registrations__remove__should_unregister_a_device() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.pushFullWait = true
        let realtime = RealtimeClient(options: options)
        defer { realtime.dispose(); realtime.close() }
        realtime.internal.rest.httpExecutor = mockHttpExecutor
        waitUntil(timeout: testTimeout) { done in
            realtime.push.admin.deviceRegistrations.remove(Self.deviceDetails.id) { error in
                XCTAssertNil(error)
                done()
            }
        }

        let request = try XCTUnwrap(mockHttpExecutor.requests.first, "No request found")

        XCTAssertEqual(request.httpMethod, "DELETE")
        XCTAssertNil(request.allHTTPHeaderFields?["X-Ably-DeviceToken"])
        XCTAssertNil(request.allHTTPHeaderFields?["X-Ably-DeviceSecret"])
    }

    // RSH1b3

    func test__015__Device_Registrations__save__should_register_a_device() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.pushFullWait = true
        let realtime = RealtimeClient(options: options)
        defer { realtime.dispose(); realtime.close() }
        realtime.internal.rest.httpExecutor = mockHttpExecutor
        waitUntil(timeout: testTimeout) { done in
            realtime.push.admin.deviceRegistrations.save(Self.deviceDetails) { error in
                XCTAssertNil(error)
                done()
            }
        }

        let request = try XCTUnwrap(mockHttpExecutor.requests.first, "No request found")

        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertNil(request.allHTTPHeaderFields?["X-Ably-DeviceToken"])
        XCTAssertNil(request.allHTTPHeaderFields?["X-Ably-DeviceSecret"])
    }

    func test__016__Device_Registrations__save__push_device_authentication__should_include_DeviceIdentityToken_HTTP_header() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.pushFullWait = true
        let realtime = RealtimeClient(options: options)
        defer { realtime.dispose(); realtime.close() }
        realtime.internal.rest.httpExecutor = mockHttpExecutor

        let testIdentityTokenDetails = DeviceIdentityTokenDetails(
            token: "123456",
            issued: Date(),
            expires: Date.distantFuture,
            capability: "",
            clientId: ""
        )

        XCTAssertNil(localDevice.identityTokenDetails)
        realtime.internal.rest.device.setAndPersistIdentityTokenDetails(testIdentityTokenDetails)
        defer { realtime.internal.rest.device.setAndPersistIdentityTokenDetails(nil) }

        waitUntil(timeout: testTimeout) { done in
            realtime.push.admin.deviceRegistrations.save(localDevice) { error in
                XCTAssertNil(error)
                done()
            }
        }

        let request = try XCTUnwrap(mockHttpExecutor.requests.first, "No request found")
        let authorization = request.allHTTPHeaderFields?["X-Ably-DeviceToken"]

        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(authorization, testIdentityTokenDetails.token.base64Encoded())
    }

    func test__017__Device_Registrations__save__push_device_authentication__should_include_DeviceSecret_HTTP_header() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.pushFullWait = true
        let realtime = RealtimeClient(options: options)
        defer { realtime.dispose(); realtime.close() }
        realtime.internal.rest.httpExecutor = mockHttpExecutor

        waitUntil(timeout: testTimeout) { done in
            realtime.push.admin.deviceRegistrations.save(localDevice) { error in
                XCTAssertNil(error)
                done()
            }
        }

        let request = try XCTUnwrap(mockHttpExecutor.requests.first, "No request found")
        let authorization = request.allHTTPHeaderFields?["X-Ably-DeviceSecret"]

        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(authorization, localDevice.secret)
    }

    // RSH1b5

    func test__018__Device_Registrations__removeWhere__should_unregister_a_device() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.pushFullWait = true
        let realtime = RealtimeClient(options: options)
        defer { realtime.dispose(); realtime.close() }

        let params = [
            "clientId": "clientA",
        ]

        let expectedRemoved = Self.allDeviceDetails.filter { $0.clientId == "clientA" }

        waitUntil(timeout: testTimeout) { done in
            realtime.push.admin.deviceRegistrations.list(params) { result, error in
                guard let result = result else {
                    fail("PaginatedResult should not be nil"); done(); return
                }
                expect(result.items).to(contain(expectedRemoved))
                XCTAssertNil(error)
                done()
            }
        }

        realtime.internal.rest.httpExecutor = mockHttpExecutor

        waitUntil(timeout: testTimeout) { done in
            realtime.push.admin.deviceRegistrations.removeWhere(params) { error in
                XCTAssertNil(error)
                done()
            }
        }

        let request = try XCTUnwrap(mockHttpExecutor.requests.first, "No request found")

        XCTAssertEqual(request.httpMethod, "DELETE")
        XCTAssertNil(request.allHTTPHeaderFields?["X-Ably-DeviceToken"])
        XCTAssertNil(request.allHTTPHeaderFields?["X-Ably-DeviceSecret"])

        waitUntil(timeout: testTimeout) { done in
            realtime.push.admin.deviceRegistrations.list(params) { result, error in
                guard let result = result else {
                    fail("PaginatedResult should not be nil"); done(); return
                }
                XCTAssertEqual(result.items.count, 0)
                XCTAssertNil(error)
                done()
            }
        }

        // --- Restore state for next tests ---

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(expectedRemoved.count, done: done)
            for removedDevice in expectedRemoved {
                realtime.push.admin.deviceRegistrations.save(removedDevice) { error in
                    XCTAssertNil(error)
                    partialDone()
                }
            }
        }

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)
            realtime.push.admin.channelSubscriptions.save(Self.subscriptionFooDevice2) { error in
                XCTAssertNil(error)
                partialDone()
            }
            realtime.push.admin.channelSubscriptions.save(Self.subscriptionBarDevice2) { error in
                XCTAssertNil(error)
                partialDone()
            }
        }
    }

    // RSH1c3

    func test__019__Channel_Subscriptions__save__should_add_a_subscription() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let realtime = RealtimeClient(options: options)
        defer { realtime.dispose(); realtime.close() }
        let testProxyHTTPExecutor = TestProxyHTTPExecutor(logger: .init(clientOptions: options))
        realtime.internal.rest.httpExecutor = testProxyHTTPExecutor

        waitUntil(timeout: testTimeout) { done in
            realtime.push.admin.channelSubscriptions.save(subscription) { error in
                XCTAssertNil(error)
                done()
            }
        }

        let request = try XCTUnwrap(testProxyHTTPExecutor.requests.first, "No request found")

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertNil(request.allHTTPHeaderFields?["X-Ably-DeviceToken"])
        XCTAssertNil(request.allHTTPHeaderFields?["X-Ably-DeviceSecret"])
    }

    func test__020__Channel_Subscriptions__save__should_update_a_subscription() throws {
        let test = Test()
        let realtime = RealtimeClient(options: try AblyTests.commonAppSetup(for: test))
        defer { realtime.dispose(); realtime.close() }
        let updateSubscription = PushChannelSubscription(clientId: subscription.clientId!, channel: "pushenabled:foo")
        waitUntil(timeout: testTimeout) { done in
            realtime.push.admin.channelSubscriptions.save(updateSubscription) { error in
                XCTAssertNil(error)
                done()
            }
        }
    }

    func test__021__Channel_Subscriptions__save__should_fail_with_a_bad_recipient() throws {
        let test = Test()
        let realtime = RealtimeClient(options: try AblyTests.commonAppSetup(for: test))
        defer { realtime.dispose(); realtime.close() }
        let invalidSubscription = PushChannelSubscription(deviceId: "madeup", channel: "pushenabled:foo")
        waitUntil(timeout: testTimeout) { done in
            realtime.push.admin.channelSubscriptions.save(invalidSubscription) { error in
                guard let error = error else {
                    fail("Error is nil"); done(); return
                }
                XCTAssertEqual(error.statusCode, 400)
                XCTAssertTrue(error.code == ErrorCode.badRequest.rawValue) // registration for device madeup doesn't exist
                done()
            }
        }
    }

    func test__022__Channel_Subscriptions__save__push_device_authentication__should_include_DeviceIdentityToken_HTTP_header() throws {
        let test = Test()
        let realtime = RealtimeClient(options: try AblyTests.commonAppSetup(for: test))
        defer { realtime.dispose(); realtime.close() }
        realtime.internal.rest.httpExecutor = mockHttpExecutor

        let testIdentityTokenDetails = DeviceIdentityTokenDetails(
            token: "123456",
            issued: Date(),
            expires: Date.distantFuture,
            capability: "",
            clientId: ""
        )

        XCTAssertNil(localDevice.identityTokenDetails)
        realtime.internal.rest.device.setAndPersistIdentityTokenDetails(testIdentityTokenDetails)
        defer { realtime.internal.rest.device.setAndPersistIdentityTokenDetails(nil) }

        let subscription = PushChannelSubscription(deviceId: localDevice.id, channel: quxChannelName)

        waitUntil(timeout: testTimeout) { done in
            realtime.push.admin.channelSubscriptions.save(subscription) { error in
                XCTAssertNil(error)
                done()
            }
        }

        let request = try XCTUnwrap(mockHttpExecutor.requests.first, "No request found")
        let authorization = request.allHTTPHeaderFields?["X-Ably-DeviceToken"]

        XCTAssertEqual(authorization, testIdentityTokenDetails.token.base64Encoded())
    }

    func test__023__Channel_Subscriptions__save__push_device_authentication__should_include_DeviceSecret_HTTP_header() throws {
        let test = Test()
        let realtime = RealtimeClient(options: try AblyTests.commonAppSetup(for: test))
        defer { realtime.dispose(); realtime.close() }
        realtime.internal.rest.httpExecutor = mockHttpExecutor

        let subscription = PushChannelSubscription(deviceId: localDevice.id, channel: quxChannelName)

        waitUntil(timeout: testTimeout) { done in
            realtime.push.admin.channelSubscriptions.save(subscription) { error in
                XCTAssertNil(error)
                done()
            }
        }

        let request = try XCTUnwrap(mockHttpExecutor.requests.first, "No request found")
        let authorization = request.allHTTPHeaderFields?["X-Ably-DeviceSecret"]

        XCTAssertEqual(authorization, localDevice.secret)
    }

    // RSH1c1

    func test__024__Channel_Subscriptions__list__should_receive_a_list_of_subscriptions() throws {
        let test = Test()
        let realtime = RealtimeClient(options: try AblyTests.commonAppSetup(for: test))
        defer { realtime.dispose(); realtime.close() }
        waitUntil(timeout: testTimeout) { done in
            realtime.push.admin.channelSubscriptions.save(subscription) { error in
                XCTAssertNil(error)
                realtime.push.admin.channelSubscriptions.list(["channel": quxChannelName]) { result, error in
                    guard let result = result else {
                        fail("PaginatedResult should not be empty"); done(); return
                    }
                    XCTAssertEqual(result.items.count, 1)
                    XCTAssertNil(error)
                    done()
                }
            }
        }
    }

    // RSH1c2

    func test__025__Channel_Subscriptions__listChannels__should_receive_a_list_of_subscriptions() throws {
        let test = Test()
        let realtime = RealtimeClient(options: try AblyTests.commonAppSetup(for: test))
        defer { realtime.dispose(); realtime.close() }
        waitUntil(timeout: testTimeout) { done in
            realtime.push.admin.channelSubscriptions.listChannels { result, error in
                XCTAssertNil(error)
                guard let result = result else {
                    fail("PaginatedResult should not be empty"); done(); return
                }
                expect(result.items as [String]).to(contain(Self.allSubscriptionsChannels + [subscription.channel]))
                done()
            }
        }
    }

    // RSH1c4

    func test__026__Channel_Subscriptions__remove__should_remove_a_subscription() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let realtime = RealtimeClient(options: options)
        defer { realtime.dispose(); realtime.close() }
        let testProxyHTTPExecutor = TestProxyHTTPExecutor(logger: .init(clientOptions: options))
        realtime.internal.rest.httpExecutor = testProxyHTTPExecutor

        waitUntil(timeout: testTimeout) { done in
            realtime.push.admin.channelSubscriptions.remove(subscription) { error in
                XCTAssertNil(error)
                done()
            }
        }

        let request = try XCTUnwrap(testProxyHTTPExecutor.requests.first, "No request found")

        XCTAssertEqual(request.httpMethod, "DELETE")
        XCTAssertNil(request.allHTTPHeaderFields?["X-Ably-DeviceToken"])
        XCTAssertNil(request.allHTTPHeaderFields?["X-Ably-DeviceSecret"])

        waitUntil(timeout: testTimeout) { done in
            realtime.push.admin.channelSubscriptions.list(["channel": quxChannelName]) { result, error in
                guard let result = result else {
                    fail("PaginatedResult should not be empty"); done(); return
                }
                XCTAssertEqual(result.items.count, 0)
                XCTAssertNil(error)
                done()
            }
        }
    }

    func test__027__Channel_Subscriptions__remove__push_device_authentication__should_include_DeviceIdentityToken_HTTP_header() throws {
        let test = Test()
        let realtime = RealtimeClient(options: try AblyTests.commonAppSetup(for: test))
        defer { realtime.dispose(); realtime.close() }
        realtime.internal.rest.httpExecutor = mockHttpExecutor

        let testIdentityTokenDetails = DeviceIdentityTokenDetails(
            token: "123456",
            issued: Date(),
            expires: Date.distantFuture,
            capability: "",
            clientId: ""
        )

        XCTAssertNil(localDevice.identityTokenDetails)
        realtime.internal.rest.device.setAndPersistIdentityTokenDetails(testIdentityTokenDetails)
        defer { realtime.internal.rest.device.setAndPersistIdentityTokenDetails(nil) }

        let subscription = PushChannelSubscription(deviceId: localDevice.id, channel: quxChannelName)

        waitUntil(timeout: testTimeout) { done in
            realtime.push.admin.channelSubscriptions.remove(subscription) { error in
                XCTAssertNil(error)
                done()
            }
        }

        let request = try XCTUnwrap(mockHttpExecutor.requests.first, "No request found")
        let authorization = request.allHTTPHeaderFields?["X-Ably-DeviceToken"]

        XCTAssertEqual(authorization, testIdentityTokenDetails.token.base64Encoded())
    }

    func test__028__Channel_Subscriptions__remove__push_device_authentication__should_include_DeviceSecret_HTTP_header() throws {
        let test = Test()
        let realtime = RealtimeClient(options: try AblyTests.commonAppSetup(for: test))
        defer { realtime.dispose(); realtime.close() }
        realtime.internal.rest.httpExecutor = mockHttpExecutor

        let subscription = PushChannelSubscription(deviceId: localDevice.id, channel: quxChannelName)

        waitUntil(timeout: testTimeout) { done in
            realtime.push.admin.channelSubscriptions.remove(subscription) { error in
                XCTAssertNil(error)
                done()
            }
        }

        let request = try XCTUnwrap(mockHttpExecutor.requests.first, "No request found")
        let authorization = request.allHTTPHeaderFields?["X-Ably-DeviceSecret"]

        XCTAssertEqual(authorization, localDevice.secret)
    }

    // RSH1c5

    func test__029__Channel_Subscriptions__removeWhere__should_remove_by_cliendId() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.pushFullWait = true
        let realtime = RealtimeClient(options: options)
        defer { realtime.dispose(); realtime.close() }

        let params = [
            "clientId": "clientB",
        ]

        let expectedRemoved = [
            Self.subscriptionFooClientB,
            Self.subscriptionBarClientB,
        ]

        waitUntil(timeout: testTimeout) { done in
            realtime.push.admin.channelSubscriptions.list(params) { result, error in
                guard let result = result else {
                    fail("PaginatedResult should not be empty"); done(); return
                }
                expect(result.items).to(contain(expectedRemoved))
                XCTAssertNil(error)
                done()
            }
        }

        waitUntil(timeout: testTimeout) { done in
            realtime.push.admin.channelSubscriptions.removeWhere(params) { error in
                XCTAssertNil(error)
                done()
            }
        }

        waitUntil(timeout: testTimeout) { done in
            realtime.push.admin.channelSubscriptions.list(params) { result, error in
                guard let result = result else {
                    fail("PaginatedResult should not be empty"); done(); return
                }
                XCTAssertEqual(result.items.count, 0)
                XCTAssertNil(error)
                done()
            }
        }

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(expectedRemoved.count, done: done)
            for removedSubscription in expectedRemoved {
                realtime.push.admin.channelSubscriptions.save(removedSubscription) { error in
                    XCTAssertNil(error)
                    partialDone()
                }
            }
        }
    }

    func test__030__Channel_Subscriptions__removeWhere__should_remove_by_cliendId_and_channel() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.pushFullWait = true
        let realtime = RealtimeClient(options: options)
        defer { realtime.dispose(); realtime.close() }

        let params = [
            "clientId": "clientB",
            "channel": "pushenabled:foo",
        ]

        let expectedRemoved = [
            Self.subscriptionFooClientB,
        ]

        waitUntil(timeout: testTimeout) { done in
            realtime.push.admin.channelSubscriptions.list(params) { result, error in
                guard let result = result else {
                    fail("PaginatedResult should not be empty"); done(); return
                }
                expect(result.items).to(contain(expectedRemoved))
                XCTAssertNil(error)
                done()
            }
        }

        waitUntil(timeout: testTimeout) { done in
            realtime.push.admin.channelSubscriptions.removeWhere(params) { error in
                XCTAssertNil(error)
                done()
            }
        }

        waitUntil(timeout: testTimeout) { done in
            realtime.push.admin.channelSubscriptions.list(params) { result, error in
                guard let result = result else {
                    fail("PaginatedResult should not be empty"); done(); return
                }
                XCTAssertEqual(result.items.count, 0)
                XCTAssertNil(error)
                done()
            }
        }
    }

    func test__031__Channel_Subscriptions__removeWhere__should_remove_by_deviceId() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.pushFullWait = true
        let realtime = RealtimeClient(options: options)
        defer { realtime.dispose(); realtime.close() }

        let params = [
            "deviceId": "deviceDetails2ClientA",
        ]

        let expectedRemoved = [
            Self.subscriptionFooDevice2,
            Self.subscriptionBarDevice2,
        ]

        waitUntil(timeout: testTimeout) { done in
            realtime.push.admin.channelSubscriptions.list(params) { result, error in
                guard let result = result else {
                    fail("PaginatedResult should not be empty"); done(); return
                }
                expect(result.items).to(contain(expectedRemoved))
                XCTAssertNil(error)
                done()
            }
        }

        waitUntil(timeout: testTimeout) { done in
            realtime.push.admin.channelSubscriptions.removeWhere(params) { error in
                XCTAssertNil(error)
                done()
            }
        }

        waitUntil(timeout: testTimeout) { done in
            realtime.push.admin.channelSubscriptions.list(params) { result, error in
                guard let result = result else {
                    fail("PaginatedResult should not be empty"); done(); return
                }
                XCTAssertEqual(result.items.count, 0)
                XCTAssertNil(error)
                done()
            }
        }
    }

    func test__032__Channel_Subscriptions__removeWhere__should_not_remove_by_inexistent_deviceId() throws {
        let test = Test()
        let realtime = RealtimeClient(options: try AblyTests.commonAppSetup(for: test))
        defer { realtime.dispose(); realtime.close() }

        let params = [
            "deviceId": "madeup",
        ]

        waitUntil(timeout: testTimeout) { done in
            realtime.push.admin.channelSubscriptions.list(params) { result, error in
                guard let result = result else {
                    fail("PaginatedResult should not be empty"); done(); return
                }
                XCTAssertEqual(result.items.count, 0)
                XCTAssertNil(error)
                done()
            }
        }

        waitUntil(timeout: testTimeout) { done in
            realtime.push.admin.channelSubscriptions.removeWhere(params) { error in
                XCTAssertNil(error)
                done()
            }
        }
    }

    func test__033__local_device__should_include_an_id_and_a_secret() {
        XCTAssertNotNil(localDevice.id)
        XCTAssertNotNil(localDevice.secret)
        XCTAssertNil(localDevice.identityTokenDetails)
    }
}
#endif
