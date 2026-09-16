import AblyPubSubDevice
import Nimble
import XCTest

@testable import AblyPubSubDevice

class MessageUpdatesDeletesTests: XCTestCase {

    // MARK: - Test Environment

    private enum TestEnvironment {
        case rest(client: ARTHttpClient, testHTTPExecutor: TestProxyHTTPExecutor, channelName: String)
        case realtime(client: ARTRealtimeClient, testHTTPExecutor: TestProxyHTTPExecutor, channelName: String)

        var channel: ARTChannelProtocol {
            switch self {
            case .rest(let client, _, let channelName):
                return client.channels.get(channelName)
            case .realtime(let client, _, let channelName):
                return client.channels.get(channelName)
            }
        }

        var realtimeClient: ARTRealtimeClient? {
            switch self {
            case .rest(_, _, _):
                return nil
            case .realtime(let client, _, _):
                return client
            }
        }

        var requests: [URLRequest] {
            switch self {
            case .rest(_, let testHTTPExecutor, _),
                 .realtime(_, let testHTTPExecutor, _):
                return testHTTPExecutor.requests
            }
        }

        static func rest(_ test: Test) throws -> TestEnvironment {
            let options = try AblyTests.commonAppSetup(for: test)
            options.testOptions.channelNamePrefix = nil
            let client = ARTHttpClient(options: options)
            let testHTTPExecutor = TestProxyHTTPExecutor(logger: .init(clientOptions: options))
            client.internal.httpExecutor = testHTTPExecutor
            let channelName = test.uniqueChannelName(prefix: "mutable:") // updates and deletes don't work without this prefix on a channel name
            return .rest(client: client, testHTTPExecutor: testHTTPExecutor, channelName: channelName)
        }

        static func realtime(_ test: Test) throws -> TestEnvironment {
            let options = try AblyTests.commonAppSetup(for: test)
            options.testOptions.channelNamePrefix = nil
            let client = ARTRealtimeClient(options: options)
            let testHTTPExecutor = TestProxyHTTPExecutor(logger: .init(clientOptions: options))
            client.internal.rest.httpExecutor = testHTTPExecutor
            let channelName = test.uniqueChannelName(prefix: "mutable:")
            return .realtime(client: client, testHTTPExecutor: testHTTPExecutor, channelName: channelName)
        }
    }

    // These `waitUntil*HistoryBecomesAvailable*` functions are needed to wait when the published message makes its way to the database.
    // If you post a message and receive it on a realtime channel and then try to fetch it via `history:`, `getMessageWithSerial:` or  `getMessageVersions:`, the request will fail with ~20% of chance.

    private func waitUntilHistoryBecomesAvailableOnChannel(_ channel: ARTChannelProtocol) -> ARTMessage {
        var firstMessage: ARTMessage!
        while firstMessage == nil {
            sleep(1) // wait before to increase the chance of the first request
            waitUntil(timeout: testTimeout) { done in
                channel.history { result, _ in
                    firstMessage = result?.items.first
                    done()
                }
            }
        }
        return firstMessage
    }

    private func waitUntilEditingHistoryBecomesAvailableForMessageSerial(_ serial: String, onChannel channel: ARTChannelProtocol) -> [ARTMessage] {
        var versions: [ARTMessage] = []
        while versions.count == 0 {
            sleep(1) // wait before to increase the chance of the first request
            waitUntil(timeout: testTimeout) { done in
                channel.getMessageVersions(withSerial: serial) { result, error in
                    XCTAssertNil(error)
                    versions = result?.items ?? []
                    done()
                }
            }
        }
        return versions
    }

    private func _test__rest_and_realtime__getMessage(_ testEnvironment: TestEnvironment) throws {
        let channel = testEnvironment.channel

        // First publish a message
        waitUntil(timeout: testTimeout) { done in
            channel.publish("chat-message", data: "test message") { error in
                XCTAssertNil(error)
                done()
            }
        }

        let publishedMessage = waitUntilHistoryBecomesAvailableOnChannel(channel)
        guard let publishedMessageSerial = publishedMessage.serial else {
            XCTFail("publishedMessage's serial is nil")
            return
        }

        var capturedRetrievedMessage: ARTMessage?

        // RSL11a: Get the message by serial string
        waitUntil(timeout: testTimeout) { done in
            channel.getMessageWithSerial(publishedMessageSerial) { message, error in
                XCTAssertNil(error)
                capturedRetrievedMessage = message
                done()
            }
        }
        let retrievedMessage = try XCTUnwrap(capturedRetrievedMessage, "waitUntil timed out before retrievedMessage was set")

        // RSL11b: Verify GET request to correct endpoint
        guard let request = testEnvironment.requests.last, let requestUrl = request.url else {
            XCTFail("No HTTP request was made")
            return
        }

        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertTrue(requestUrl.path.contains("/channels/\(channel.name)/messages/\(publishedMessageSerial)"))

        // RSL11c: Returns the decoded Message object

        XCTAssertNotNil(retrievedMessage)
        XCTAssertEqual(retrievedMessage.serial, publishedMessageSerial)
        XCTAssertEqual(retrievedMessage.name, "chat-message")
        XCTAssertEqual(retrievedMessage.data as? String, "test message")
    }

    private func _test__rest_and_realtime__updateMessage__and__getMessageVersions(_ testEnvironment: TestEnvironment) throws {
        let channel = testEnvironment.channel

        // First publish a message
        waitUntil(timeout: testTimeout) { done in
            channel.publish("chat-message", data: "hello world") { error in
                XCTAssertNil(error)
                done()
            }
        }

        let publishedMessage = waitUntilHistoryBecomesAvailableOnChannel(channel)
        guard let publishedMessageSerial = publishedMessage.serial else {
            XCTFail("publishedMessage's serial is nil")
            return
        }

        // Update data
        let messageUpdate = publishedMessage.copy() as! ARTMessage
        messageUpdate.data = "hello world!"

        // RSL15a: optional MessageOperation object
        let operation = ARTMessageOperation(clientId: "updater-client", descriptionText: "Editing message text", metadata: ["newValue": "hello world!"])

        // RSL15a: optional params
        let params: [String: ARTStringifiable] = ["param1": .withString("value1")]

        var updateResult: ARTUpdateDeleteResult?
        waitUntil(timeout: testTimeout) { done in
            channel.update(messageUpdate, operation: operation, params: params) { result, error in
                XCTAssertNil(error)
                updateResult = result
                done()
            }
        }

        if case .rest = testEnvironment {
            // RSL15b: Verify PATCH request to correct endpoint
            guard let request = testEnvironment.requests.last, let requestUrl = request.url else {
                XCTFail("No HTTP request was made")
                return
            }

            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertTrue(requestUrl.path.contains("/channels/\(channel.name)/messages/\(publishedMessageSerial)"))

            // RSL15f: Verify params in querystring
            XCTAssertTrue(requestUrl.query?.contains("param1=value1") ?? false)

            // RSL15b: Verify request body - encoded Message object

            var bodyDict: [String: Any]!

            switch extractBodyAsMsgPack(request) {
            case let .failure(error):
                XCTFail(error); return
            case let .success(httpBody):
                // RSL15d: The body must be encoded to the appropriate format per RSC8
                bodyDict = try XCTUnwrap(httpBody.unbox as? [String: Any])
                XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-msgpack")
            }

            // Verify message fields are present
            XCTAssertEqual(bodyDict["serial"] as? String, publishedMessageSerial)
            XCTAssertEqual(bodyDict["name"] as? String, "chat-message")
            XCTAssertEqual(bodyDict["data"] as? String, "hello world!")

            // RSL15b1: action field (1 = MESSAGE_UPDATE)
            XCTAssertEqual(bodyDict["action"] as? Int, 1)

            // RSL15b7: version field contains operation data
            if let versionDict = bodyDict["version"] as? [String: Any] {
                XCTAssertEqual(versionDict["clientId"] as? String, "updater-client")
                XCTAssertEqual(versionDict["description"] as? String, "Editing message text")
                XCTAssertEqual((versionDict["metadata"] as? [String: String])?["newValue"], "hello world!")
            } else {
                XCTFail("Version should be present in request body")
            }
        }

        var capturedUpdatedMessage: ARTMessage?

        // Fetch the updated message (poll getMessageWithSerial until it returns the updated message)
        while capturedUpdatedMessage == nil || capturedUpdatedMessage!.version?.serial == publishedMessage.version?.serial {
            // Get the updated message by serial string
            waitUntil(timeout: testTimeout) { done in
                channel.getMessageWithSerial(publishedMessageSerial) { message, error in
                    XCTAssertNil(error)
                    capturedUpdatedMessage = message
                    done()
                }
            }
        }
        let updatedMessage = try XCTUnwrap(capturedUpdatedMessage, "waitUntil timed out before updatedMessage was set")

        XCTAssertNotNil(updatedMessage)
        XCTAssertEqual(updatedMessage.serial, publishedMessageSerial)
        XCTAssertEqual(updatedMessage.name, "chat-message")
        XCTAssertEqual(updatedMessage.data as? String, "hello world!")
        XCTAssertEqual(updatedMessage.action, .update)

        // Verify version properties
        XCTAssertNotNil(updatedMessage.version)
        XCTAssertNotNil(updatedMessage.version?.serial)
        XCTAssertTrue(updatedMessage.version!.serial! > publishedMessageSerial)
        XCTAssertNotNil(updatedMessage.version?.timestamp)
        XCTAssertTrue(updatedMessage.version!.timestamp! > publishedMessage.timestamp!)
        XCTAssertEqual(updatedMessage.version?.clientId, "updater-client")
        XCTAssertEqual(updatedMessage.version?.descriptionText, "Editing message text")
        XCTAssertEqual(updatedMessage.version?.metadata, ["newValue": "hello world!"])

        // Check the contents of updateMessage's returned UpdateDeleteResult
        let unwrappedUpdateResult = try XCTUnwrap(updateResult)
        XCTAssertEqual(updatedMessage.version?.serial, unwrappedUpdateResult.versionSerial)

        // RSL14a: Get versions by serial string
        let versions = waitUntilEditingHistoryBecomesAvailableForMessageSerial(publishedMessageSerial, onChannel: channel)

        XCTAssertEqual(versions.count, 2)
        XCTAssertEqual(versions[0].data as? String, "hello world")
        XCTAssertEqual(versions[1].data as? String, "hello world!")
    }

    private func _test__rest_and_realtime__deleteMessage(_ testEnvironment: TestEnvironment) throws {
        let channel = testEnvironment.channel

        // First publish a message
        waitUntil(timeout: testTimeout) { done in
            channel.publish("chat-message", data: "test text") { error in
                XCTAssertNil(error)
                done()
            }
        }

        let publishedMessage = waitUntilHistoryBecomesAvailableOnChannel(channel)
        guard let publishedMessageSerial = publishedMessage.serial else {
            XCTFail("publishedMessage's serial is nil")
            return
        }

        // Create message for delete with fields
        let messageDelete = publishedMessage.copy() as! ARTMessage
        messageDelete.serial = publishedMessageSerial
        messageDelete.data = ""

        // RSL15a: optional MessageOperation object
        let operation = ARTMessageOperation(clientId: "deleter-client", descriptionText: "Test delete operation", metadata: ["reason": "inappropriate content"])

        // RSL15a: optional params
        let params: [String: ARTStringifiable] = ["deleteParam": .withString("deleteValue")]

        var deleteResult: ARTUpdateDeleteResult?
        waitUntil(timeout: testTimeout) { done in
            channel.delete(messageDelete, operation: operation, params: params) { result, error in
                XCTAssertNil(error)
                deleteResult = result
                done()
            }
        }

        if case .rest = testEnvironment {
            // RSL15b: Verify PATCH request to correct endpoint
            guard let request = testEnvironment.requests.last, let requestUrl = request.url else {
                XCTFail("No HTTP request was made")
                return
            }

            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertTrue(requestUrl.path.contains("/channels/\(channel.name)/messages/\(publishedMessageSerial)"))

            // RSL15f: Verify params in querystring
            XCTAssertTrue(request.url?.query?.contains("deleteParam=deleteValue") ?? false)

            // RSL15b: Verify request body - encoded Message object

            var bodyDict: [String: Any]!

            switch extractBodyAsMsgPack(request) {
            case let .failure(error):
                XCTFail(error)
            case let .success(httpBody):
                // RSL15d: The body must be encoded to the appropriate format per RSC8
                bodyDict = try XCTUnwrap(httpBody.unbox as? [String: Any])
                XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-msgpack")
            }

            // Verify message fields are present
            XCTAssertEqual(bodyDict["serial"] as? String, publishedMessageSerial)
            XCTAssertEqual(bodyDict["name"] as? String, "chat-message")
            XCTAssertEqual(bodyDict["data"] as? String, "")

            // RSL15b1: action field (2 = MESSAGE_DELETE)
            XCTAssertEqual(bodyDict["action"] as? Int, 2)

            // RSL15b7: version field contains operation data
            if let versionDict = bodyDict["version"] as? [String: Any] {
                XCTAssertEqual(versionDict["clientId"] as? String, "deleter-client")
                XCTAssertEqual(versionDict["description"] as? String, "Test delete operation")
                XCTAssertEqual((versionDict["metadata"] as? [String: String])?["reason"], "inappropriate content")
            } else {
                XCTFail("Version should be present in request body")
            }
        }

        var updatedMessage: ARTMessage?

        // Fetch the updated message (poll getMessageWithSerial until it returns the updated message)
        while updatedMessage == nil || updatedMessage!.version?.serial == publishedMessage.version?.serial {
            // Get the updated message by serial string
            waitUntil(timeout: testTimeout) { done in
                channel.getMessageWithSerial(publishedMessageSerial) { message, error in
                    XCTAssertNil(error)
                    updatedMessage = message
                    done()
                }
            }
        }

        guard let updatedMessage else {
            XCTFail("updatedMessage is nil")
            return
        }

        XCTAssertNotNil(updatedMessage)
        XCTAssertEqual(updatedMessage.serial, publishedMessageSerial)
        XCTAssertEqual(updatedMessage.name, "chat-message")
        XCTAssertEqual(updatedMessage.data as? String, "")
        XCTAssertEqual(updatedMessage.action, .delete)

        // Verify version properties
        XCTAssertNotNil(updatedMessage.version)
        XCTAssertNotNil(updatedMessage.version?.serial)
        XCTAssertTrue(updatedMessage.version!.serial! > publishedMessageSerial)
        XCTAssertNotNil(updatedMessage.version?.timestamp)
        XCTAssertTrue(updatedMessage.version!.timestamp! > publishedMessage.timestamp!)
        XCTAssertEqual(updatedMessage.version?.clientId, "deleter-client")
        XCTAssertEqual(updatedMessage.version?.descriptionText, "Test delete operation")
        XCTAssertEqual(updatedMessage.version?.metadata, ["reason": "inappropriate content"])

        // Check the contents of deleteMessage's returned UpdateDeleteResult
        let unwrappedDeleteResult = try XCTUnwrap(deleteResult)
        XCTAssertEqual(updatedMessage.version?.serial, unwrappedDeleteResult.versionSerial)
    }

    private func _test__rest_and_realtime__appendMessage(_ testEnvironment: TestEnvironment) throws {
        let channel = testEnvironment.channel

        // First publish a message
        waitUntil(timeout: testTimeout) { done in
            channel.publish("chat-message", data: "Hello") { error in
                XCTAssertNil(error)
                done()
            }
        }

        let publishedMessage = waitUntilHistoryBecomesAvailableOnChannel(channel)
        guard let publishedMessageSerial = publishedMessage.serial else {
            XCTFail("publishedMessage's serial is nil")
            return
        }

        // Create message for append with fields
        let messageAppend = publishedMessage.copy() as! ARTMessage
        messageAppend.serial = publishedMessageSerial
        messageAppend.data = " world!"

        // RSL15a: optional MessageOperation object
        let operation = ARTMessageOperation(clientId: "appender-client", descriptionText: "Test append operation", metadata: ["reason": "further LLM tokens"])

        // RSL15a: optional params
        let params: [String: ARTStringifiable] = ["appendParam": .withString("appendValue")]

        var appendResult: ARTUpdateDeleteResult?
        waitUntil(timeout: testTimeout) { done in
            channel.append(messageAppend, operation: operation, params: params) { updateDeleteResult, error in
                XCTAssertNil(error)
                appendResult = updateDeleteResult
                done()
            }
        }

        if case .rest = testEnvironment {
            // RSL15b: Verify PATCH request to correct endpoint
            guard let request = testEnvironment.requests.last, let requestUrl = request.url else {
                XCTFail("No HTTP request was made")
                return
            }

            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertTrue(requestUrl.path.contains("/channels/\(channel.name)/messages/\(publishedMessageSerial)"))

            // RSL15f: Verify params in querystring
            XCTAssertTrue(request.url?.query?.contains("appendParam=appendValue") ?? false)

            // RSL15b: Verify request body - encoded Message object

            var bodyDict: [String: Any]!

            switch extractBodyAsMsgPack(request) {
            case let .failure(error):
                XCTFail(error)
            case let .success(httpBody):
                // RSL15d: The body must be encoded to the appropriate format per RSC8
                bodyDict = try XCTUnwrap(httpBody.unbox as? [String: Any])
                XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-msgpack")
            }

            // Verify message fields are present
            XCTAssertEqual(bodyDict["serial"] as? String, publishedMessageSerial)
            XCTAssertEqual(bodyDict["name"] as? String, "chat-message")
            XCTAssertEqual(bodyDict["data"] as? String, " world!")

            // RSL15b1: action field (5 = MESSAGE_APPEND)
            XCTAssertEqual(bodyDict["action"] as? Int, 5)

            // RSL15b7: version field contains operation data
            if let versionDict = bodyDict["version"] as? [String: Any] {
                XCTAssertEqual(versionDict["clientId"] as? String, "appender-client")
                XCTAssertEqual(versionDict["description"] as? String, "Test append operation")
                XCTAssertEqual((versionDict["metadata"] as? [String: String])?["reason"], "further LLM tokens")
            } else {
                XCTFail("Version should be present in request body")
            }
        }

        let unwrappedAppendResult = try XCTUnwrap(appendResult)

        var updatedMessage: ARTMessage?

        // Fetch the updated message (poll getMessageWithSerial until it returns the updated message)
        while updatedMessage == nil || updatedMessage!.version?.serial == publishedMessage.version?.serial {
            // Get the updated message by serial string
            waitUntil(timeout: testTimeout) { done in
                channel.getMessageWithSerial(publishedMessageSerial) { message, error in
                    XCTAssertNil(error)
                    updatedMessage = message
                    done()
                }
            }
        }

        guard let updatedMessage else {
            XCTFail("updatedMessage is nil")
            return
        }

        XCTAssertNotNil(updatedMessage)
        XCTAssertEqual(updatedMessage.serial, publishedMessageSerial)
        XCTAssertEqual(updatedMessage.name, "chat-message")
        // Check that the data we requested to append (" world!") was successfully appended to the original message's data ("Hello")
        XCTAssertEqual(updatedMessage.data as? String, "Hello world!")
        XCTAssertEqual(updatedMessage.action, .update)

        // Verify version properties
        XCTAssertNotNil(updatedMessage.version)
        XCTAssertNotNil(updatedMessage.version?.serial)
        XCTAssertTrue(updatedMessage.version!.serial! > publishedMessageSerial)
        XCTAssertNotNil(updatedMessage.version?.timestamp)
        XCTAssertTrue(updatedMessage.version!.timestamp! > publishedMessage.timestamp!)
        XCTAssertEqual(updatedMessage.version?.clientId, "appender-client")
        XCTAssertEqual(updatedMessage.version?.descriptionText, "Test append operation")
        XCTAssertEqual(updatedMessage.version?.metadata, ["reason": "further LLM tokens"])

        // Check the contents of appendMessage's returned UpdateDeleteResult
        XCTAssertEqual(updatedMessage.version?.serial, unwrappedAppendResult.versionSerial)
    }

    // MARK: - RSL11: RestChannel#getMessage function

    // RSL11a: Takes a first argument of a serial string of the message to be retrieved
    // RSL11b: The SDK must send a GET request to the endpoint /channels/{channelName}/messages/{serial}
    // RSL11c: Returns the decoded Message object for the specified message serial
    func test__RSL11__getMessage() throws {
        let test = Test()
        try _test__rest_and_realtime__getMessage(.rest(test))
    }

    // MARK: - RTL28: RealtimeChannel#getMessage function

    // RTL28: same as RestChannel#getMessage
    func test__RTL28__getMessage() throws {
        let test = Test()
        let env = try TestEnvironment.realtime(test)
        defer {
            env.realtimeClient?.close()
        }
        try _test__rest_and_realtime__getMessage(env)
    }

    // MARK: - RSL15: RestChannel#updateMessage function

    // RSL15a: Takes a first argument of a Message object (which must contain a populated serial field), optional MessageOperation, and optional params
    // RSL15b: The SDK must send a PATCH to /channels/{channelName}/messages/{serial}
    // RSL15b1: Request body includes action field set to MESSAGE_UPDATE
    // RSL15b7: Request body includes version field from MessageOperation
    // RSL15c: The SDK must not mutate the user-supplied Message object
    // RSL15d: The body must be encoded to the appropriate format per RSC8
    // RSL14b: The SDK must send a GET request to the endpoint
    // RSL14c: Returns a PaginatedResult<Message>
    func test__RSL15__RSL14__updateMessage__and__getMessageVersions() throws {
        let test = Test()
        try _test__rest_and_realtime__updateMessage__and__getMessageVersions(.rest(test))
    }

    // MARK: - RTL32: RealtimeChannel#updateMessage function

    // RTL32
    // RTL31: RealtimeChannel#getMessageVersions function: same as RestChannel#getMessageVersions
    func test__RTL32__RTL31__updateMessage__and__getMessageVersions() throws {
        let test = Test()
        let env = try TestEnvironment.realtime(test)
        defer {
            env.realtimeClient?.close()
        }
        try _test__rest_and_realtime__updateMessage__and__getMessageVersions(env)
    }

    // MARK: - RSL15: RestChannel#deleteMessage function

    // RSL15a: Takes a first argument of a Message object (which must contain a populated serial field), optional MessageOperation, and optional params
    // RSL15b: The SDK must send a PATCH to /channels/{channelName}/messages/{serial}
    // RSL15b1: Request body includes action field set to MESSAGE_DELETE
    // RSL15b7: Request body includes version field from MessageOperation
    // RSL15c: The SDK must not mutate the user-supplied Message object
    // RSL15d: The body must be encoded to the appropriate format per RSC8
    func test__RSL15__deleteMessage() throws {
        let test = Test()
        try _test__rest_and_realtime__deleteMessage(.rest(test))
    }

    // MARK: - RTL32: RealtimeChannel#deleteMessage function

    // RTL32
    func test__RTL32__deleteMessage() throws {
        let test = Test()
        let env = try TestEnvironment.realtime(test)
        defer {
            env.realtimeClient?.close()
        }
        try _test__rest_and_realtime__deleteMessage(env)
    }

    // MARK: - RSL15: RestChannel#appendMessage function

    func test__RSL15__appendMessage() throws {
        let test = Test()
        try _test__rest_and_realtime__appendMessage(.rest(test))
    }

    // MARK: - RTL32: RealtimeChannel#appendMessage function

    // RTL32
    func test__RTL32__appendMessage() throws {
        let test = Test()
        let env = try TestEnvironment.realtime(test)
        defer {
            env.realtimeClient?.close()
        }
        try _test__rest_and_realtime__appendMessage(env)
    }

    func test_subscribeToAppends() throws {
        // Given: A realtime channel that supports mutable messages
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.testOptions.channelNamePrefix = nil
        let client = ARTRealtimeClient(options: options)
        defer { client.close() }
        let channelName = test.uniqueChannelName(prefix: "mutable:")
        let channel = client.channels.get(channelName)

        waitUntil(timeout: testTimeout) { done in
            channel.attach { error in
                XCTAssertNil(error)
                done()
            }
        }

        // When: An update is appended to a message via appendMessage()

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: "Hello") { error in
                XCTAssertNil(error)
                done()
            }
        }

        let publishedMessage = waitUntilHistoryBecomesAvailableOnChannel(channel)
        var updatedMessage: ARTMessage?

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)

            channel.subscribe { message in
                updatedMessage = message
                partialDone()
            }

            publishedMessage.data = " world!"
            channel.append(publishedMessage, operation: nil, params: nil) { _, error in
                print("Append completed")
                XCTAssertNil(error)
                partialDone()
            }
        }

        // Then: The realtime channel emits a message with action APPEND
        XCTAssertEqual(updatedMessage?.data as? String, " world!")
        XCTAssertEqual(updatedMessage?.action, .append)
    }
}
