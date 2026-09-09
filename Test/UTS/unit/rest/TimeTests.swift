import Testing
import Foundation
import Ably
import Ably.Private

/// Time API (RSC16)
/// Derived from https://github.com/ably/specification/blob/main/uts/rest/unit/time.md
@Suite(.serialized)
final class TimeTests: UTSTestCase {

    // UTS: rest/unit/RSC16/returns-server-time-0
    @Test
    func test_RSC16_returns_server_time() async throws {
        // Setup
        let capturedRequests = Captured<PendingHTTPRequest>()
        let serverTimeMs = 1_704_067_200_000 // 2024-01-01 00:00:00 UTC

        let mockHTTP = MockHTTPClient(
            onConnectionAttempt: { connection in connection.respondWithSuccess() },
            onRequest: { request in
                capturedRequests.append(request)
                request.respondWith(status: 200, body: [serverTimeMs])
            }
        )
        installMock(mockHTTP)

        let rest = makeRest { options in options.key = "app.key:secret" }

        // Test Steps
        let result = try await awaitTime(rest)

        // Assertions
        // Result should be a DateTime matching the server timestamp
        // ASSERT result IS DateTime
        #expect(Int(result.timeIntervalSince1970 * 1000) == serverTimeMs)

        // Verify correct endpoint was called
        #expect(capturedRequests.count == 1)
        let request = capturedRequests[0]
        #expect(request.method == "GET")
        #expect(request.url.path == "/time")
    }

    // UTS: rest/unit/RSC16/request-format-get-time-1
    @Test
    func test_RSC16_request_format_get_time() async throws {
        // Setup
        let capturedRequests = Captured<PendingHTTPRequest>()

        let mockHTTP = MockHTTPClient(
            onConnectionAttempt: { connection in connection.respondWithSuccess() },
            onRequest: { request in
                capturedRequests.append(request)
                request.respondWith(status: 200, body: [1_704_067_200_000])
            }
        )
        installMock(mockHTTP)

        let rest = makeRest { options in options.key = "app.key:secret" }

        // Test Steps
        _ = try await awaitTime(rest)

        // Assertions
        #expect(capturedRequests.count == 1)
        let request = capturedRequests[0]

        // Should be GET request to /time
        #expect(request.method == "GET")
        #expect(request.url.path == "/time")

        // Should have standard Ably headers
        #expect(request.headers["X-Ably-Version"] != nil)
        #expect(request.headers["Ably-Agent"] != nil)
    }

    // UTS: rest/unit/RSC16/no-auth-required-2
    @Test
    func test_RSC16_no_auth_required() async throws {
        // Setup
        let capturedRequests = Captured<PendingHTTPRequest>()

        let mockHTTP = MockHTTPClient(
            onConnectionAttempt: { connection in connection.respondWithSuccess() },
            onRequest: { request in
                capturedRequests.append(request)
                request.respondWith(status: 200, body: [1_704_067_200_000])
            }
        )
        installMock(mockHTTP)

        // Client has credentials, but time() should not use them
        let rest = makeRest { options in options.key = "app.key:secret" }

        // Test Steps
        let result = try await awaitTime(rest)

        // Assertions
        // Should succeed
        // ASSERT result IS DateTime
        #expect(result.timeIntervalSince1970 > 0)

        // Request should not have Authorization header even though client has credentials
        #expect(capturedRequests.count == 1)
        let request = capturedRequests[0]
        #expect(request.headers["Authorization"] == nil)
    }

    // UTS: rest/unit/RSC16/works-without-tls-3
    @Test
    func test_RSC16_works_without_tls() async throws {
        // Setup
        let capturedRequests = Captured<PendingHTTPRequest>()

        let mockHTTP = MockHTTPClient(
            onConnectionAttempt: { connection in connection.respondWithSuccess() },
            onRequest: { request in
                capturedRequests.append(request)
                request.respondWith(status: 200, body: [1_704_067_200_000])
            }
        )
        installMock(mockHTTP)

        // Client with API key but using token auth to avoid RSC18 restriction
        // on authenticated operations. time() should still work over HTTP.
        let rest = makeRest { options in
            options.key = "app.key:secret"
            options.tls = false
            options.useTokenAuth = true
        }

        // Test Steps
        let result = try await awaitTime(rest)

        // Assertions
        // Should succeed without sending authentication over HTTP
        // ASSERT result IS DateTime
        #expect(result.timeIntervalSince1970 > 0)

        // Request should use HTTP (not HTTPS)
        #expect(capturedRequests.count == 1)
        let request = capturedRequests[0]
        #expect(request.url.scheme == "http")

        // Request should not have Authorization header
        #expect(request.headers["Authorization"] == nil)
    }

    // UTS: rest/unit/RSC16/error-propagated-4
    @Test
    func test_RSC16_error_propagated() async throws {
        // Setup
        let mockHTTP = MockHTTPClient(
            onConnectionAttempt: { connection in connection.respondWithSuccess() },
            onRequest: { request in
                request.respondWith(status: 500, body: [
                    "error": [
                        "message": "Internal server error",
                        "code": 50000,
                        "statusCode": 500,
                    ],
                ])
            }
        )
        installMock(mockHTTP)

        let rest = makeRest { options in options.key = "app.key:secret" }

        // Test Steps
        // AWAIT client.time() FAILS WITH error
        let error = try await awaitTimeError(rest)
        #expect(error.statusCode == 500)
        #expect(error.code == 50000)
    }
}

// MARK: - time() continuation helpers

extension TimeTests {
    /// Bridges the completion-handler `time:` API (UTS `AWAIT client.time()`, success path).
    func awaitTime(_ rest: ARTRest, sourceLocation: SourceLocation = #_sourceLocation) async throws -> Date {
        let (date, failure): (Date?, String?) = await withCheckedContinuation { continuation in
            rest.time { date, error in
                continuation.resume(returning: (date, error.map { "\($0)" }))
            }
        }

        if let failure {
            Issue.record("time() failed unexpectedly: \(failure)", sourceLocation: sourceLocation)
        }

        return try #require(date, "time() returned no date", sourceLocation: sourceLocation)
    }

    /// Bridges the completion-handler `time:` API (UTS `AWAIT client.time() FAILS WITH error`).
    func awaitTimeError(_ rest: ARTRest, sourceLocation: SourceLocation = #_sourceLocation) async throws -> ARTErrorInfo {
        let (error, unexpectedDate): (ARTErrorInfo?, String?) = await withCheckedContinuation { continuation in
            rest.time { date, error in
                if let error {
                    continuation.resume(returning: (error as? ARTErrorInfo ?? ARTErrorInfo.create(from: error), nil))
                } else {
                    continuation.resume(returning: (nil, String(describing: date)))
                }
            }
        }

        if let unexpectedDate {
            Issue.record("time() succeeded unexpectedly with date \(unexpectedDate)", sourceLocation: sourceLocation)
        }

        return try #require(error, "time() returned no error", sourceLocation: sourceLocation)
    }
}
