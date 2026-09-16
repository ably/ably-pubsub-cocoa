import AblyPubSubDevice
import Nimble
import XCTest

private let options: ARTClientOptions = {
    let options = ARTClientOptions(key: "fake:key")
    options.autoConnect = false
    return options
}()

class ObjectLifetimesTests: XCTestCase {
    // XCTest invokes this method before executing the first test in the test suite. We use it to ensure that the global variables are initialized at the same moment, and in the same order, as they would have been when we used the Quick testing framework.
    override class var defaultTestSuite: XCTestSuite {
        _ = options

        return super.defaultTestSuite
    }

    func test__001__ObjectLifetimes__user_code_releases_public_object__the_object_s_internal_child_s_back_reference_is_released_too() {
        var realtime: ARTRealtime? = ARTRealtime(options: options)
        weak var internalRealtime: ARTRealtimeInternal? = realtime!.internal
        weak var internalConn: ARTConnectionInternal? = realtime!.connection.internal
        weak var internalRest: ARTHttpClientInternal? = realtime!.internal.rest

        waitUntil(timeout: testTimeout) { done in
            options.internalDispatchQueue.async {
                realtime = nil // Schedule deallocation for later in this queue
                XCTAssertNotNil(internalConn) // Deallocation still hasn't happened.
                XCTAssertNotNil(internalRealtime)
                XCTAssertNotNil(internalRest)
                done()
            }
        }

        // Deallocation should happen here.

        waitUntil(timeout: testTimeout) { done in
            options.internalDispatchQueue.async {
                XCTAssertNil(internalConn)
                XCTAssertNil(internalRealtime)
                XCTAssertNil(internalRest)
                done()
            }
        }
    }

    func test__002__ObjectLifetimes__user_code_holds_only_reference_to_public_object_s_public_child__still_can_access_parent_s_internal_object() {
        let conn = ARTRealtime(options: options).connection

        waitUntil(timeout: testTimeout) { done in
            conn.ping { _ in
                done()
            }
        }
    }

    func test__003__ObjectLifetimes__user_code_holds_only_reference_to_public_object_s_public_child__when_it_s_released__schedules_async_release_of_parent_s_internal_object_in_internal_queue() {
        var conn: ARTConnection? = ARTRealtime(options: options).connection
        weak var weakConn = conn!.internal_nosync

        waitUntil(timeout: testTimeout) { done in
            options.internalDispatchQueue.async {
                conn = nil // Schedule deallocation for later in this queue
                XCTAssertNotNil(weakConn) // Deallocation still hasn't happened.
                done()
            }
        }

        // Deallocation should happen here.

        waitUntil(timeout: testTimeout) { done in
            options.internalDispatchQueue.async {
                XCTAssertNil(weakConn)
                done()
            }
        }
    }

    func test__004__ObjectLifetimes__when_user_leaves_Realtime_open__still_works() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)

        var client: ARTRealtime? = ARTRealtime(options: options)

        weak var weakClient = client!.internal
        XCTAssertNotNil(weakClient)
        defer { client?.close() }

        let channelName = test.uniqueChannelName()
        waitUntil(timeout: testTimeout) { done in
            client!.channels.get(channelName).subscribe(attachCallback: { _ in
                client = nil
                ARTHttpClient(options: options).channels.get(channelName).publish(nil, data: "bar")
            }, callback: { msg in
                XCTAssertEqual(msg.data as? String, "bar")
                done()
            })
        }
    }

    func test__005__ObjectLifetimes__when_Realtime_is_closed_and_user_loses_its_reference__channels_don_t_leak() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)

        var client: ARTRealtime? = ARTRealtime(options: options)
        weak var weakClient = client!.internal

        var channel: ARTRealtimeChannel? = client!.channels.get(test.uniqueChannelName())
        weak var weakChannel = channel!.internal

        waitUntil(timeout: testTimeout) { done in
            channel!.attach { errorInfo in
                XCTAssertNil(errorInfo)
                done()
            }
        }

        waitUntil(timeout: testTimeout) { done in
            client!.connection.on(.closed) { _ in
                done()
            }
            client!.close()
        }

        waitUntil(timeout: testTimeout) { done in
            AblyTests.queue.async {
                client = nil // should enqueue a release
                channel = nil // should enqueue a release
                done()
            }
        }

        waitUntil(timeout: testTimeout) { done in
            AblyTests.queue.async {
                XCTAssertNil(weakClient)
                XCTAssertNil(weakChannel)
                done()
            }
        }
    }
}
