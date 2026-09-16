import AblyPubSubDevice
import Nimble
import XCTest

class HttpAnnotationsTests: XCTestCase {
    // RSAN1
    // RSAN2
    // RSAN3
    func test__publish_delete_and_get_annotations() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.testOptions.channelNamePrefix = nil

        // Create realtime client
        let realtimeClient = ARTRealtimeClient(options: options)
        defer { realtimeClient.dispose(); realtimeClient.close() }

        // Create rest client
        let restClient = ARTHttpClient(options: options)

        // Channel name and options
        let channelName = test.uniqueChannelName(prefix: "mutable:")
        let channelOptions = ARTRealtimeChannelOptions()
        channelOptions.modes = [.publish, .subscribe, .annotationPublish, .annotationSubscribe]

        // Get realtime channel with options
        let realtimeChannel = realtimeClient.channels.get(channelName, options: channelOptions)

        // Get rest channel
        let restChannel = restClient.channels.get(channelName)

        // Message and annotation to track
        var capturedReceivedMessage: ARTMessage?
        var receivedSummary: ARTMessage!
        var capturedCreatedAnnotation: ARTAnnotation?

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(4, done: done)

            // Subscribe to messages
            realtimeChannel.subscribe { message in
                if message.action == .create {
                    capturedReceivedMessage = message

                    // When message is received, create and publish annotation via REST
                    let annotation = ARTOutboundAnnotation(
                        id: nil,
                        type: "reaction:multiple.v1",
                        clientId: nil,
                        name: "👍",
                        count: NSNumber(value: 10),
                        data: nil,
                        extras: nil
                    )

                    // RSAN1
                    restChannel.annotations.publish(for: message, annotation: annotation) { error in
                        XCTAssertNil(error)
                        partialDone()
                    }
                }
                else if message.action == .messageSummary {
                    receivedSummary = message
                    realtimeChannel.unsubscribe()

                    // Verify summary properties
                    XCTAssertEqual(receivedSummary.action, .messageSummary)
                    XCTAssertEqual(receivedSummary.serial, capturedReceivedMessage?.serial)
                    XCTAssertEqual(receivedSummary.annotations?.summary?.count, 1)

                    partialDone()
                }
            }

            // Subscribe to annotations
            realtimeChannel.annotations.subscribe { annotation in
                // only interested in the first annotation which is with action `create`
                realtimeChannel.annotations.unsubscribe()

                capturedCreatedAnnotation = annotation

                // Verify annotation properties
                XCTAssertEqual(annotation.action, .create)
                XCTAssertEqual(annotation.messageSerial, capturedReceivedMessage?.serial)
                XCTAssertEqual(annotation.type, "reaction:multiple.v1")
                XCTAssertEqual(annotation.name, "👍")
                XCTAssertEqual(annotation.count?.intValue, 10)

                // Verify it matches the message
                XCTAssertEqual(annotation.messageSerial, capturedReceivedMessage?.serial)

                partialDone()
            }

            // Wait for channel to be attached before publishing
            realtimeChannel.once(.attached) { stateChange in
                // Publish a message
                let message = ARTMessage(name: "test", data: "test message")
                realtimeChannel.publish([message])
                partialDone()
            }
            realtimeChannel.attach()
        }
        let receivedMessage = try XCTUnwrap(capturedReceivedMessage, "waitUntil timed out before receivedMessage was set")
        let createdAnnotation = try XCTUnwrap(capturedCreatedAnnotation, "waitUntil timed out before createdAnnotation was set")

        // RSAN2: Now delete the annotation
        waitUntil(timeout: testTimeout) { done in
            let deleteAnnotation = ARTOutboundAnnotation(
                id: nil,
                type: createdAnnotation.type,
                clientId: nil,
                name: createdAnnotation.name,
                count: createdAnnotation.count,
                data: nil,
                extras: nil
            )
            restChannel.annotations.delete(for: receivedMessage, annotation: deleteAnnotation) { error in
                XCTAssertNil(error)
                done()
            }
        }

        // After the annotations are published (and received via realtime), check it through the rest request:

        guard let messageSerial = receivedMessage.serial else {
            XCTFail("Message serial should not be nil")
            return
        }

        // Comment form ably-js 'annotations.test.js':
        // > Temporary anti-flake measure; can be removed after summary loop implements
        // > annotation resume (CHA-887)
        sleep(2)

        waitUntil(timeout: testTimeout) { done in
            // RSAN3
            restChannel.annotations.getForMessageSerial(messageSerial, query: .init()) { paginatedResult, error in
                XCTAssertNil(error)

                guard let annotations = paginatedResult?.items, annotations.count == 2 else {
                    XCTFail("Should contain two annotations.")
                    return
                }
                XCTAssertEqual(annotations[0].action, .create)
                XCTAssertEqual(annotations[0].type, "reaction:multiple.v1")
                XCTAssertEqual(annotations[0].name, "👍")
                XCTAssertEqual(annotations[0].count?.intValue, 10)

                XCTAssertEqual(annotations[1].action, .delete)
                XCTAssertEqual(annotations[1].type, "reaction:multiple.v1")
                XCTAssertEqual(annotations[1].name, "👍")
                XCTAssertEqual(annotations[1].count?.intValue, 10)

                done()
            }
        }
    }

    // RSAN1c4
    func test__idempotent_publishing_should_publish_annotation_with_implicit_id_only_once() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.testOptions.channelNamePrefix = nil
        options.idempotentRestPublishing = true // for visibility, true by default

        // Create realtime client
        let realtimeClient = ARTRealtimeClient(options: options)
        defer { realtimeClient.dispose(); realtimeClient.close() }

        // Create rest client
        let restClient = ARTHttpClient(options: options)

        // Channel name and options
        let channelName = test.uniqueChannelName(prefix: "mutable:")
        let channelOptions = ARTRealtimeChannelOptions()
        channelOptions.modes = [.publish, .subscribe, .annotationPublish, .annotationSubscribe]

        // Get realtime channel with options
        let realtimeChannel = realtimeClient.channels.get(channelName, options: channelOptions)

        // Get rest channel
        let restChannel = restClient.channels.get(channelName)

        // Message and annotation to track
        var capturedReceivedMessage: ARTMessage?
        var capturedCreatedAnnotation: ARTAnnotation?

        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(3, done: done)

            // Subscribe to messages
            realtimeChannel.subscribe { message in
                if message.action == .create {
                    capturedReceivedMessage = message

                    // When message is received, create and publish annotation via REST
                    let annotation = ARTOutboundAnnotation(
                        id: nil,
                        type: "reaction:multiple.v1",
                        clientId: nil,
                        name: "👍",
                        count: NSNumber(value: 10),
                        data: nil,
                        extras: nil
                    )

                    // RSAN1
                    restChannel.annotations.publish(for: message, annotation: annotation) { error in
                        XCTAssertNil(error)
                        partialDone()
                    }
                }
            }

            // Subscribe to annotations
            realtimeChannel.annotations.subscribe { annotation in
                capturedCreatedAnnotation = annotation

                // Verify annotation properties
                XCTAssertNotNil(annotation.id)
                XCTAssertEqual(annotation.action, .create)
                XCTAssertEqual(annotation.messageSerial, capturedReceivedMessage?.serial)
                XCTAssertEqual(annotation.type, "reaction:multiple.v1")
                XCTAssertEqual(annotation.name, "👍")
                XCTAssertEqual(annotation.count?.intValue, 10)
                XCTAssertEqual(annotation.messageSerial, capturedReceivedMessage?.serial)

                partialDone()
            }

            // Wait for channel to be attached before publishing
            realtimeChannel.once(.attached) { stateChange in
                // Publish a message
                let message = ARTMessage(name: "test", data: "test message")
                realtimeChannel.publish([message])
                partialDone()
            }
            realtimeChannel.attach()
        }
        let receivedMessage = try XCTUnwrap(capturedReceivedMessage, "waitUntil timed out before receivedMessage was set")
        let createdAnnotation = try XCTUnwrap(capturedCreatedAnnotation, "waitUntil timed out before createdAnnotation was set")

        // RSAN1c4: Now publish the created annotation again (to verify idempotent publishing)
        waitUntil(timeout: testTimeout) { done in
            // Convert the received ARTAnnotation to ARTOutboundAnnotation for publishing with the same ID
            let outboundAnnotation = ARTOutboundAnnotation(
                id: createdAnnotation.id,
                type: createdAnnotation.type,
                clientId: createdAnnotation.clientId,
                name: createdAnnotation.name,
                count: createdAnnotation.count,
                data: createdAnnotation.data,
                extras: createdAnnotation.extras
            )
            restChannel.annotations.publish(for: receivedMessage, annotation: outboundAnnotation) { error in
                XCTAssertNil(error) // no error, server ignores duplicate
                done()
            }
        }

        // After the annotations are published (and received via realtime), check it through the rest request:

        guard let messageSerial = receivedMessage.serial else {
            XCTFail("Message serial should not be nil")
            return
        }

        // Comment form ably-js 'annotations.test.js':
        // > Temporary anti-flake measure; can be removed after summary loop implements
        // > annotation resume (CHA-887)
        sleep(2)

        waitUntil(timeout: testTimeout) { done in
            // RSAN3
            restChannel.annotations.getForMessageSerial(messageSerial, query: .init()) { paginatedResult, error in
                XCTAssertNil(error)

                guard let annotations = paginatedResult?.items, annotations.count == 1 else {
                    XCTFail("Should contain only one annotation.")
                    return
                }
                XCTAssertEqual(annotations[0].id, createdAnnotation.id)
                XCTAssertEqual(annotations[0].action, .create)
                XCTAssertEqual(annotations[0].type, "reaction:multiple.v1")
                XCTAssertEqual(annotations[0].name, "👍")
                XCTAssertEqual(annotations[0].count?.intValue, 10)

                done()
            }
        }
    }

    // RSAN1a4
    func test__publish_annotation_exceeding_max_message_size() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.testOptions.channelNamePrefix = nil

        let restClient = ARTHttpClient(options: options)
        let channel = restClient.channels.get(test.uniqueChannelName(prefix: "mutable:"))

        let largeString = String(repeating: "f", count: ARTDefault.maxMessageSize() + 100) // Create a string larger than maxMessageSize

        waitUntil(timeout: testTimeout) { done in
            // Create an annotation with the large string as name
            let annotation = ARTOutboundAnnotation(
                id: nil,
                type: "test",
                clientId: nil,
                name: largeString,
                count: NSNumber(value: 1),
                data: nil,
                extras: nil
            )

            // Try to publish the annotation
            channel.annotations.publish(forMessageSerial: "test", annotation: annotation) { error in
                // Verify error code and message
                XCTAssertNotNil(error)
                XCTAssertEqual(error?.code, 40009)
                XCTAssertTrue(error?.message.contains("exceeds maxMessageSize") ?? false)
                done()
            }
        }
    }

    // The annotations object must read the channel's data encoder at encode time rather
    // than capturing it at construction, so that a cipher added by setOptions after the
    // channel was created is still applied to annotation data. Mirrors the realtime test
    // in RealtimeAnnotationsTests; only the publish path is asserted here because the REST
    // decode path already read the encoder live.
    func test__annotation_data_uses_a_cipher_added_by_setOptions_after_channel_creation() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        options.testOptions.channelNamePrefix = nil

        // Realtime client only to publish the message that gets annotated, since the
        // annotation needs a message serial.
        let realtimeClient = ARTRealtimeClient(options: options)
        defer { realtimeClient.dispose(); realtimeClient.close() }

        let restClient = ARTHttpClient(options: options)
        let testHTTPExecutor = TestProxyHTTPExecutor(logger: .init(clientOptions: options))
        restClient.internal.httpExecutor = testHTTPExecutor

        let channelName = test.uniqueChannelName(prefix: "mutable:")

        let realtimeChannelOptions = ARTRealtimeChannelOptions()
        realtimeChannelOptions.modes = [.publish, .subscribe, .annotationPublish, .annotationSubscribe]
        let realtimeChannel = realtimeClient.channels.get(channelName, options: realtimeChannelOptions)

        // Create the REST channel with no cipher, so the annotations object would capture a
        // cipher-less encoder if it cached one.
        let restChannel = restClient.channels.get(channelName)

        // Now add a cipher. `ARTHttpChannel.setOptions` is not visible from Swift — the ObjC
        // importer folds it into the read-only `options` property — so go through
        // `channels.get`, which applies the options to the already-created channel via
        // `setOptions_nosync:`: the same path, recreating the channel's data encoder.
        let key = ARTCrypto.generateRandomKey()
        _ = restClient.channels.get(channelName, options: ARTChannelOptions(cipherKey: key as ARTCipherKeyCompatible))

        let annotationData = "secret annotation data"

        waitUntil(timeout: testTimeout) { done in
            realtimeChannel.subscribe { message in
                guard message.action == .create else {
                    return
                }
                realtimeChannel.unsubscribe()

                // multiple.v1 because an anonymous client may only publish the
                // multiple.v1 and total.v1 aggregation methods
                let annotation = ARTOutboundAnnotation(
                    id: nil,
                    type: "reaction:multiple.v1",
                    clientId: nil,
                    name: "👍",
                    count: 1,
                    data: annotationData,
                    extras: nil
                )
                restChannel.annotations.publish(for: message, annotation: annotation) { error in
                    XCTAssertNil(error)
                    done()
                }
            }

            realtimeChannel.publish([ARTMessage(name: "test", data: "test message")])
        }

        // Assert on the body that went on the wire: a stale cipher-less encoder would have
        // POSTed the data as plaintext, with no cipher in the encoding.
        let request = try XCTUnwrap(
            testHTTPExecutor.requests.last { $0.url?.path.hasSuffix("/annotations") == true },
            "No annotation publish request found"
        )
        let rawBody = try XCTUnwrap(request.httpBody, "Annotation publish request should have a body")
        let decodedBody = try XCTUnwrap(restClient.internal.defaultEncoder.decode(rawBody), "Decode request body failed")
        let publishedAnnotations = try XCTUnwrap(decodedBody as? [NSDictionary], "Request body is invalid")
        let publishedAnnotation = try XCTUnwrap(publishedAnnotations.first, "Request body contained no annotation")

        let encoding = publishedAnnotation.value(forKey: "encoding") as? String
        XCTAssertTrue(
            encoding?.contains("cipher+aes-256-cbc") == true,
            "Expected published annotation data to be encrypted, got encoding \(encoding ?? "nil")"
        )
        XCTAssertNotEqual(publishedAnnotation.value(forKey: "data") as? String, annotationData)
    }
}
