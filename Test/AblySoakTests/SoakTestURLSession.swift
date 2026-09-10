import Foundation
import Ably.Private

class SoakTestURLSession : NSObject, ARTURLSession {
    let queue: DispatchQueue
    var cancellables: [ARTCancellable] = []

    required init(_ queue: DispatchQueue) {
        self.queue = queue
    }

    func get(_ request: URLRequest, completion callback: @escaping (HTTPURLResponse?, Data?, Error?) -> Void) -> ARTCancellable & NSObjectProtocol {
        let cancellable = CancellableInQueue(queue: queue)
        cancellables.append(cancellable)

        queue.afterSeconds(between: 0.2 ... 3.0) {
            if cancellable.cancelled {
                return
            }

            if request.url?.host != "fakeauth.com" {
                callback(nil, nil, "SoakTestURLSession: unexpected URL: \(String(describing: request.url))".asError())
                return
            }

            if true.times(1, outOf: 20) {
                callback(nil, nil, fakeError)
                return
            }

            let data = try! jsonEncoder.encode(ARTTokenDetails(
                token: "fakeToken",
                expires: Date(timeIntervalSinceNow: (0.5 ... 30.0).randomWithin()),
                issued: Date(),
                capability: nil,
                clientId: nil
            ))

            callback(HTTPURLResponse.init(
                url: request.url!,
                mimeType: "application/json",
                expectedContentLength: data.count,
                textEncodingName: nil
            ), data, nil)
        }

        return cancellable
    }

    func finishTasksAndInvalidate() {
        for cancellable in cancellables {
            cancellable.cancel()
        }
    }
}

class CancellableInQueue : NSObject, ARTCancellable {
    let queue: DispatchQueue
    var cancelled = false

    init(queue: DispatchQueue) {
        self.queue = queue
    }

    func cancel() {
        queue.async {
            self.cancelled = true
        }
    }
}
