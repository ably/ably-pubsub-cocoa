import AblyPubSubDevice
import Nimble
import XCTest
import AblyTestingObjC

class HttpClientPresenceTests: XCTestCase {
    // RSP3

    // RSP3a
    func test__002__Presence__get__should_return_a_PaginatedResult_page_containing_the_first_page_of_members() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = HttpClient(options: options)
        let channelName = test.uniqueChannelName()
        let channel = client.channels.get(channelName)

        var disposable = [RealtimeClient]()
        defer {
            for clientItem in disposable {
                clientItem.dispose()
                clientItem.close()
            }
        }

        let expectedData = "online"
        let expectedPattern = "^user(\\d+)$"

        // Load 150 members (2 pages)
        disposable += [AblyTests.addMembersSequentiallyToChannel(channelName, members: 150, data: expectedData as AnyObject?, options: options)]

        waitUntil(timeout: testTimeout) { done in
            channel.presence.get { membersPage, error in
                XCTAssertNil(error)

                let membersPage = membersPage!
                expect(membersPage).to(beAnInstanceOf(PaginatedResult<PresenceMessage>.self))
                XCTAssertEqual(membersPage.items.count, 100)

                let members = membersPage.items
                expect(members).to(allPass { member in
                    NSRegularExpression.match(member.clientId, pattern: expectedPattern)
                        && (member.data as? String) == expectedData
                })

                XCTAssertTrue(membersPage.hasNext)
                XCTAssertFalse(membersPage.isLast)

                membersPage.next { nextPage, error in
                    XCTAssertNil(error)
                    let nextPage = nextPage!
                    expect(nextPage).to(beAnInstanceOf(PaginatedResult<PresenceMessage>.self))
                    XCTAssertEqual(nextPage.items.count, 50)

                    let members = nextPage.items
                    expect(members).to(allPass { member in
                        NSRegularExpression.match(member.clientId, pattern: expectedPattern)
                            && (member.data as? String) == expectedData
                    })

                    XCTAssertFalse(nextPage.hasNext)
                    XCTAssertTrue(nextPage.isLast)
                    done()
                }
            }
        }
    }

    // RSP3a1
    func test__003__Presence__get__limit_should_support_up_to_1000_items() throws {
        let test = Test()
        let client = HttpClient(options: try AblyTests.commonAppSetup(for: test))
        let channel = client.channels.get(test.uniqueChannelName())

        let query = PresenceQuery()
        XCTAssertEqual(query.limit, 100)

        query.limit = 1001
        expect { try channel.presence.get(query, callback: { _, _ in }) }.to(throwError())

        query.limit = 1000
        expect { try channel.presence.get(query, callback: { _, _ in }) }.toNot(throwError())
    }

    // RSP3a2
    func test__004__Presence__get__clientId_should_filter_members_by_the_provided_clientId() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let channelName = test.uniqueChannelName()

        let client = HttpClient(options: options)
        let channel = client.channels.get(channelName)

        let realtime = RealtimeClient(options: options)
        defer { realtime.close() }
        let realtimeChannel = realtime.channels.get(channelName)

        realtimeChannel.presence.enterClient("ana", data: "mobile")
        realtimeChannel.presence.enterClient("john", data: "web")
        realtimeChannel.presence.enterClient("casey", data: "mobile")

        expect(realtimeChannel.internal.presence.members).toEventually(haveCount(3), timeout: testTimeout)

        let query = PresenceQuery()
        query.clientId = "john"

        waitUntil(timeout: testTimeout) { done in
            expect {
                try channel.presence.get(query) { membersPage, error in
                    XCTAssertNil(error)
                    XCTAssertEqual(membersPage!.items.count, 1)
                    let member = membersPage!.items[0]
                    XCTAssertEqual(member.clientId, "john")
                    XCTAssertEqual(member.data as? NSObject, "web" as NSObject?)
                    done()
                }
            }.toNot(throwError())
        }
    }

    // RSP3a3
    func test__005__Presence__get__connectionId_should_filter_members_by_the_provided_connectionId() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = HttpClient(options: options)

        let channelName = test.uniqueChannelName()
        let channel = client.channels.get(channelName)

        var disposable = [RealtimeClient]()
        defer {
            for clientItem in disposable {
                clientItem.dispose()
                clientItem.close()
            }
        }

        // One connection
        disposable += [AblyTests.addMembersSequentiallyToChannel(channelName, members: 6, options: options)]

        // Another connection
        disposable += [AblyTests.addMembersSequentiallyToChannel(channelName, members: 3, startFrom: 7, options: options)]

        let query = RealtimePresenceQuery()
        // Return all members from last connection (connectionId from the last connection)
        query.connectionId = disposable.last!.connection.id!

        waitUntil(timeout: testTimeout) { done in
            expect {
                try channel.presence.get(query) { membersPage, error in
                    XCTAssertNil(error)
                    XCTAssertEqual(membersPage!.items.count, 3)
                    XCTAssertFalse(membersPage!.hasNext)
                    XCTAssertTrue(membersPage!.isLast)
                    expect(membersPage!.items).to(allPass { member in
                        return NSRegularExpression.match(member.clientId, pattern: "^user(7|8|9)")
                    })
                    done()
                }
            }.toNot(throwError())
        }
    }

    // RSP4

    // RSP4a
    func test__006__Presence__history__should_return_a_PaginatedResult_page_containing_the_first_page_of_members() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = HttpClient(options: options)

        let channelName = test.uniqueChannelName()
        let channel = client.channels.get(channelName)

        var realtime: RealtimeClient!
        defer { realtime.dispose(); realtime.close() }

        let expectedData = "online"
        let expectedPattern = "^user(\\d+)$"
        realtime = AblyTests.addMembersSequentiallyToChannel(channelName, members: 150, data: expectedData as AnyObject?, options: options)

        waitUntil(timeout: testTimeout) { done in
            channel.presence.history { membersPage, error in
                XCTAssertNil(error)
                guard let membersPage = membersPage else {
                    fail("Page is empty"); done(); return
                }
                expect(membersPage).to(beAnInstanceOf(PaginatedResult<PresenceMessage>.self))
                XCTAssertEqual(membersPage.items.count, 100)

                let members = membersPage.items
                expect(members).to(allPass { member in
                    NSRegularExpression.match(member.clientId, pattern: expectedPattern)
                        && (member.data as? String) == expectedData
                })

                XCTAssertTrue(membersPage.hasNext)
                XCTAssertFalse(membersPage.isLast)

                membersPage.next { nextPage, error in
                    XCTAssertNil(error)
                    guard let nextPage = nextPage else {
                        fail("nextPage is empty"); done(); return
                    }
                    expect(nextPage).to(beAnInstanceOf(PaginatedResult<PresenceMessage>.self))
                    XCTAssertEqual(nextPage.items.count, 50)

                    let members = nextPage.items
                    expect(members).to(allPass { member in
                        NSRegularExpression.match(member.clientId, pattern: expectedPattern)
                            && (member.data as? String) == expectedData
                    })

                    XCTAssertFalse(nextPage.hasNext)
                    XCTAssertTrue(nextPage.isLast)
                    done()
                }
            }
        }
    }

    // RSP4

    // RSP4b

    // RSP4b2
    func test__007__Presence__history__query_argument__direction_should_change_the_order_of_the_members() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = HttpClient(options: options)

        let channelName = test.uniqueChannelName()
        let channel = client.channels.get(channelName)

        var disposable = [RealtimeClient]()
        defer {
            for clientItem in disposable {
                clientItem.dispose()
                clientItem.close()
            }
        }

        disposable += [AblyTests.addMembersSequentiallyToChannel(channelName, members: 10, data: nil, options: options)]

        let query = DataQuery()
        XCTAssertEqual(query.direction, QueryDirection.backwards)

        waitUntil(timeout: testTimeout) { done in
            expect {
                try channel.presence.history(query) { membersPage, error in
                    XCTAssertNil(error)
                    let firstMember = membersPage!.items.first!
                    XCTAssertEqual(firstMember.clientId, "user10")
                    let lastMember = membersPage!.items.last!
                    XCTAssertEqual(lastMember.clientId, "user1")
                    done()
                }
            }.toNot(throwError())
        }

        query.direction = .forwards

        waitUntil(timeout: testTimeout) { done in
            expect {
                try channel.presence.history(query) { membersPage, error in
                    XCTAssertNil(error)
                    let firstMember = membersPage!.items.first!
                    XCTAssertEqual(firstMember.clientId, "user1")
                    let lastMember = membersPage!.items.last!
                    XCTAssertEqual(lastMember.clientId, "user10")
                    done()
                }
            }.toNot(throwError())
        }
    }

    // RSP4

    // RSP4b

    // RSP4b3
    func test__009__Presence__history__query_argument__limit_supports_up_to_1000_members() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = HttpClient(options: options)

        let channelName = test.uniqueChannelName()
        let channel = client.channels.get(channelName)

        var realtime: RealtimeClient!
        defer { realtime.dispose(); realtime.close() }
        realtime = AblyTests.addMembersSequentiallyToChannel(channelName, members: 1, options: options)

        let query = DataQuery()
        XCTAssertEqual(query.limit, 100)
        query.limit = 1

        waitUntil(timeout: testTimeout) { done in
            expect {
                try channel.presence.history(query) { membersPage, error in
                    XCTAssertNil(error)
                    XCTAssertEqual(membersPage!.items.count, 1)
                    XCTAssertFalse(membersPage!.hasNext)
                    XCTAssertTrue(membersPage!.isLast)
                    done()
                }
            }.toNot(throwError())
        }

        query.limit = 1001

        expect { try channel.presence.history(query) { _, _ in } }.to(throwError { (error: Error) in
            XCTAssertEqual(error._code, DataQueryError.limit.rawValue)
        })
    }

    // RSP3a3
    func test__008__Presence__history__connectionId_should_filter_members_by_the_provided_connectionId() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = HttpClient(options: options)

        let channelName = test.uniqueChannelName()
        let channel = client.channels.get(channelName)

        var disposable = [RealtimeClient]()
        defer {
            for clientItem in disposable {
                clientItem.dispose()
                clientItem.close()
            }
        }

        // One connection
        disposable += [AblyTests.addMembersSequentiallyToChannel(channelName, members: 6, options: options)]

        // Another connection
        disposable += [AblyTests.addMembersSequentiallyToChannel(channelName, members: 3, startFrom: 7, options: options)]

        let query = RealtimePresenceQuery()
        // Return all members from last connection (connectionId from the last connection)
        query.connectionId = disposable.last!.connection.id!

        waitUntil(timeout: testTimeout) { done in
            expect {
                try channel.presence.get(query) { membersPage, error in
                    XCTAssertNil(error)
                    XCTAssertEqual(membersPage!.items.count, 3)
                    XCTAssertFalse(membersPage!.hasNext)
                    XCTAssertTrue(membersPage!.isLast)
                    expect(membersPage!.items).to(allPass { member in
                        return NSRegularExpression.match(member.clientId, pattern: "^user(7|8|9)")
                    })
                    done()
                }
            }.toNot(throwError())
        }
    }

    // RSP4

    // RSP4b

    // RSP4b1
    func test__010__Presence__history__query_argument__start_and_end_should_filter_members_between_those_two_times() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = HttpClient(options: options)

        let channelName = test.uniqueChannelName()
        let channel = client.channels.get(channelName)

        var disposable = [RealtimeClient]()
        defer {
            for clientItem in disposable {
                clientItem.dispose()
                clientItem.close()
            }
        }

        let query = DataQuery()

        disposable += [AblyTests.addMembersSequentiallyToChannel(channelName, members: 25, options: options)]

        waitUntil(timeout: testTimeout) { done in
            client.time { time, error in
                XCTAssertNil(error)
                query.start = time
                done()
            }
        }

        waitUntil(timeout: testTimeout) { done in
            delay(1.5) { done() }
        }

        disposable += [AblyTests.addMembersSequentiallyToChannel(channelName, members: 3, options: options)]

        waitUntil(timeout: testTimeout) { done in
            client.time { time, error in
                XCTAssertNil(error)
                query.end = time
                done()
            }
        }

        disposable += [AblyTests.addMembersSequentiallyToChannel(channelName, members: 10, options: options)]

        waitUntil(timeout: testTimeout) { done in
            expect {
                try channel.presence.history(query) { membersPage, error in
                    XCTAssertNil(error)
                    XCTAssertEqual(membersPage!.items.count, 3)
                    done()
                }
            }.toNot(throwError())
        }
    }

    // RSP4b1
    func test__011__Presence__history__query_argument__start_must_be_equal_to_or_less_than_end_and_is_unaffected_by_the_request_direction() throws {
        let test = Test()
        let client = HttpClient(options: try AblyTests.commonAppSetup(for: test))
        let channel = client.channels.get(test.uniqueChannelName())

        let query = DataQuery()
        query.direction = .backwards
        query.end = NSDate() as Date
        query.start = query.end!.addingTimeInterval(10.0)

        expect { try channel.presence.history(query) { _, _ in } }.to(throwError { (error: Error) in
            XCTAssertEqual(error._code, DataQueryError.timestampRange.rawValue)
        })

        query.direction = .forwards

        expect { try channel.presence.history(query) { _, _ in } }.to(throwError { (error: Error) in
            XCTAssertEqual(error._code, DataQueryError.timestampRange.rawValue)
        })
    }

    // RSP5
    func test__001__Presence__presence_messages_retrieved_are_decoded_in_the_same_way_that_messages_are_decoded() throws {
        let test = Test()
        let options = try AblyTests.commonAppSetup(for: test)
        let client = HttpClient(options: options)

        let channelName = test.uniqueChannelName()
        let channel = client.channels.get(channelName)

        let expectedData = ["test": 1]

        waitUntil(timeout: testTimeout) { done in
            channel.publish(nil, data: expectedData) { _ in done() }
        }

        let realtime = RealtimeClient(options: options)
        defer { realtime.dispose(); realtime.close() }
        waitUntil(timeout: testTimeout) { done in
            let partialDone = AblyTests.splitDone(2, done: done)
            let channel = realtime.channels.get(channelName)
            channel.presence.enterClient("john", data: expectedData) { _ in
                partialDone()
            }
            channel.presence.subscribe { _ in
                channel.presence.unsubscribe()
                partialDone()
            }
        }

        typealias Done = () -> Void
        func checkReceivedMessage<T: BaseMessage>(_ done: @escaping Done) -> (PaginatedResult<T>?, ErrorInfo?) -> Void {
            return { membersPage, error in
                XCTAssertNil(error)
                let member = membersPage!.items[0]
                XCTAssertEqual(member.data as? NSDictionary, expectedData as NSDictionary?)
                done()
            }
        }

        var decodeNumberOfCalls = 0
        let hook = channel.internal.dataEncoder.testSuite_injectIntoMethod(after: #selector(ARTDataEncoder.decode(_:encoding:))) {
            decodeNumberOfCalls += 1
        }
        defer { hook.remove() }

        waitUntil(timeout: testTimeout) { done in
            channel.history(checkReceivedMessage(done))
        }

        waitUntil(timeout: testTimeout) { done in
            channel.presence.history(checkReceivedMessage(done))
        }

        XCTAssertEqual(decodeNumberOfCalls, 2)
    }
}
