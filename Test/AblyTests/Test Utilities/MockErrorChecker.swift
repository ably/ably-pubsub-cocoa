import AblyPubSubDevice.Private

class MockErrorChecker: ErrorChecker {
    var isTokenError: Bool!

    func isTokenError(_ errorInfo: ARTErrorInfo) -> Bool {
        return isTokenError
    }
}
