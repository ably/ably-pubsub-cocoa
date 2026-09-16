import AblyPubSubDevice.Private

class MockErrorChecker: ErrorChecker {
    var isTokenError: Bool!

    func isTokenError(_ errorInfo: ErrorInfo) -> Bool {
        return isTokenError
    }
}
