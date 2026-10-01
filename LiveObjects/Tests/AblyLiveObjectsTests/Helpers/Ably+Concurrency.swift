import AblyPubSubDevice

// Helpers for using ably-cocoa with Swift concurrency and typed throws.

extension RealtimeChannelProtocol {
    func attachAsync() async throws(ErrorInfo) {
        try await withCheckedContinuation { (continuation: CheckedContinuation<Result<Void, ErrorInfo>, _>) in
            attach { error in
                if let error {
                    continuation.resume(returning: .failure(error))
                } else {
                    continuation.resume(returning: .success(()))
                }
            }
        }.get()
    }

    func detachAsync() async throws(ErrorInfo) {
        try await withCheckedContinuation { (continuation: CheckedContinuation<Result<Void, ErrorInfo>, _>) in
            detach { error in
                if let error {
                    continuation.resume(returning: .failure(error))
                } else {
                    continuation.resume(returning: .success(()))
                }
            }
        }.get()
    }
}

extension HttpClientProtocol {
    func requestAsync(_ method: String, path: String, params: [String: String]?, body: Any?, headers: [String: String]?) async throws(ErrorInfo) -> HTTPPaginatedResponse {
        try await withCheckedContinuation { (continuation: CheckedContinuation<Result<HTTPPaginatedResponse, ErrorInfo>, _>) in
            request(method, path: path, params: params, body: body, headers: headers) { response, error in
                if let error {
                    continuation.resume(returning: .failure(error))
                } else if let response {
                    continuation.resume(returning: .success(response))
                } else {
                    preconditionFailure("There is no error, so expected a response")
                }
            }
        }.get()
    }
}

extension ConnectionProtocol {
    @discardableResult
    func onceAsync(_ event: RealtimeConnectionEvent) async -> ConnectionStateChange {
        await withCheckedContinuation { continuation in
            once(event) { stateChange in
                continuation.resume(returning: stateChange)
            }
        }
    }
}
