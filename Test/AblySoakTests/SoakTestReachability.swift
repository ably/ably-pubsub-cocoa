import Foundation
import Ably.Private

class SoakTestReachability : NSObject, ARTReachability {
    let queue: DispatchQueue
    var callback: ((Bool) -> Void)?
    var isReachable = true

    required init(logger: InternalLog, queue: DispatchQueue) {
        self.queue = queue
        super.init()
        waitAndToggle()
    }

    func listen(forHost host: String, callback: @escaping (Bool) -> Void) {
        self.callback = callback
    }

    func off() {
        self.callback = nil
    }

    func waitAndToggle() {
        queue.afterSeconds(between: (0.1 ... 60.0 * 5)) {
            self.isReachable = !self.isReachable

            if let callback = self.callback {
                callback(self.isReachable)
            }

            self.waitAndToggle()
        }
    }
}
