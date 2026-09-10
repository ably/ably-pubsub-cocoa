import Foundation
import XCTest
import Ably.Private

let randomSeed: Int = 13
let concurrentConnections: Int = 100
let runTime: TimeInterval = 60 * 20

/// Drives `concurrentConnections` realtime clients for `runTime` seconds against faked
/// transports, and passes if none of them crashes or trips an assertion.
///
/// The run takes twenty minutes, so it is skipped unless `RUN_SOAK_TEST` is set in the
/// environment. Nothing in CI sets it; run the test by hand with
/// `RUN_SOAK_TEST=1 swift test --filter AblySoakTests`.
class SoakTest: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false

        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["RUN_SOAK_TEST"] != nil,
            "Set RUN_SOAK_TEST to run the soak test."
        )
    }

    func testSoak() {
        ARTHttp.setURLSessionClass(SoakTestURLSession.self)

        let shouldStop = DispatchQueue(label: "io.ably.soakTest.shouldStop").syncValue(false)

        for i in (0 ..< concurrentConnections) {
            let queue = DispatchQueue(label: "io.ably.soakTest.\(i)")
            let internalQueue = DispatchQueue(label: "io.ably.soakTest.internal.\(i)")

            queue.async {
                let options: ARTClientOptions = {
                    if true.times(1, outOf: 2) {
                        return ARTClientOptions(key: "fake:key")
                    } else {
                        let options = ARTClientOptions()
                        options.authUrl = NSURL(string: "http://fakeauth.com") as URL?
                        return options
                    }
                }()
                options.autoConnect = false
                options.logLevel = .error
                options.dispatchQueue = queue
                options.internalDispatchQueue = internalQueue
                options.testOptions.transportFactory = SoakTestRealtimeTransportFactory()
                let realtime = ARTRealtime(options: options)
                realtime.internal.setReachabilityClass(SoakTestReachability.self)

                realtime.connection.on { stateChange in
                    print("got connection notification; error: \(String(describing: stateChange.reason))")
                }

                realtimeOperations(realtime: realtime, queue: queue, shouldStop: shouldStop.get)
                channelsOperations(realtime: realtime, queue: queue)
            }
        }

        Thread.sleep(forTimeInterval: runTime)

        shouldStop.set(true)
    }
}

extension DispatchQueue {
    func syncValue<T>(_ value: T) -> SyncValue<T> {
        return SyncValue(queue: self, value: value)
    }
}

/// A value read and written under a serial queue. Every holder of a `SyncValue`
/// shares one box, so a write is visible through the `get` references already
/// handed to other queues.
final class SyncValue<T> {
    private let queue: DispatchQueue
    private var value: T

    init(queue: DispatchQueue, value: T) {
        self.queue = queue
        self.value = value
    }

    func get() -> T {
        var value: T? = nil
        queue.sync {
            value = self.value
        }
        return value!
    }

    func set(_ value: T) {
        queue.sync {
            self.value = value
        }
    }
}

func realtimeOperations(realtime: ARTRealtime, queue: DispatchQueue, shouldStop: @escaping () -> Bool) {
    if shouldStop() {
        return
    }

    queue.afterSeconds(between: 0.1 ... 1.0) {
        realtimeOperations(realtime: realtime, queue: queue, shouldStop: shouldStop)
    }

    queue.afterSeconds(between: 0.1 ... 10.0) {
        if !shouldStop() {
            realtime.connect()
        }
    }

    if true.times(1, outOf: 20) {
        queue.afterSeconds(between: 0.0 ... 120.0) {
            realtime.close()
        }
    }

    queue.afterSeconds(between: 0.1 ... 3.0) {
        realtime.ping { error in
            print("pinged; error: \(String(describing: error))")
        }
    }
}

func channelsOperations(realtime: ARTRealtime, queue: DispatchQueue) {
    queue.afterSeconds(between: 0.1 ... 1.0) {
        if realtime.connection.state == .closed {
            return
        }
        channelsOperations(realtime: realtime, queue: queue)

        let channel = realtime.channels.get("channel.\(Int((0 ... 100).randomWithin()))")

        queue.afterSeconds(between: 0.1 ... 1) {
            channel.attach { error in
                print("\(channel.name): attached; error: \(String(describing: error))")
            }
        }

        queue.afterSeconds(between: 0.1 ... 60) {
            channel.detach { error in
                print("\(channel.name): detached; error: \(String(describing: error))")
            }
        }

        queue.afterSeconds(between: 0.3 ... 2) {
            channel.subscribe { message in
                print("\(channel.name): got message: \(message)")
            }
        }

        queue.afterSeconds(between: 0.5 ... 3) {
            channel.publish("fakeMessage", data: randomMessageData()) { error in
                    print("\(channel.name): got message ack; error: \(String(describing: error))")
            }
        }

        queue.afterSeconds(between: 0.3 ... 2) {
            channel.presence.subscribe { message in
                print("\(channel.name): got presence message: \(message)")
            }
        }

        queue.afterSeconds(between: 0.5 ... 3) {
            presenceCycle(channel: channel, queue: queue)
        }

        queue.afterSeconds(between: 0.1 ... 1) {
            realtime.channels.exists(channel.name)
        }

        queue.afterSeconds(between: 0.1 ... 2) {
            realtime.channels.release(channel.name) { error in
                print("\(channel.name): released; error: \(String(describing: error))")
            }
        }

        if true.times(1, outOf: 10) {
            for channel in realtime.channels {
                _ = channel
            }
        }
    }
}

func presenceCycle(channel: ARTRealtimeChannel, queue: DispatchQueue) {
    let client = "presenceClient.\(nextGlobalSerial())"
    channel.presence.enterClient(client, data: randomMessageData()) { error in
        print("\(channel.name): got enter ack; error: \(String(describing: error))")
        guard error == nil else {
           return
        }
        queue.afterSeconds(between: 0.5 ... 3) {
            channel.presence.updateClient(client, data: randomMessageData()) { error in
                print("\(channel.name): got update ack; error: \(String(describing: error))")
                guard error == nil else {
                   return
                }
                queue.afterSeconds(between: 0.5 ... 3) {
                    channel.presence.leaveClient(client, data: randomMessageData()) { error in
                        print("\(channel.name): got leave ack; error: \(String(describing: error))")
                        guard error == nil else {
                           return
                        }
                    }
                }
            }
        }
    }
}

extension ARTRealtimeChannels: @retroactive Sequence {
    public func makeIterator() -> NSFastEnumerationIterator {
        return NSFastEnumerationIterator(self.iterate())
    }
}

let messageFixtures: [Any] = [
    "a string",
    ["some", ["values": 456]],
]

func randomMessageData() -> Any {
    return messageFixtures.randomElement(using: &seededRandomNumberGenerator)!
}

var randDouble : () -> Double = {
    srand48(randomSeed)
    return { drand48() }
}()

class SeededRandomNumberGenerator : RandomNumberGenerator {
    func next() -> UInt64 {
        return UInt64((0 ... UInt64.max).randomWithin())
    }
}

var seededRandomNumberGenerator = SeededRandomNumberGenerator()

extension ClosedRange where Bound : BinaryFloatingPoint {
    func randomWithin() -> Double {
        return Double(lowerBound) + Double(upperBound - lowerBound) * randDouble()
    }
}

extension ClosedRange where Bound : BinaryInteger {
    func randomWithin() -> Double {
        return (Double(self.lowerBound) ... Double(self.upperBound)).randomWithin()
    }
}

extension Double {
    func secondsFromNow() -> DispatchTime {
        return DispatchTime.now() + .milliseconds(Int(self * 1000))
    }
}

extension DispatchQueue {
    func afterSeconds(between secondsRange: ClosedRange<Double>, execute: @escaping () -> Void) {
        self.asyncAfter(deadline: secondsRange.randomWithin().secondsFromNow(), execute: execute)
    }
}

extension Bool {
    func times(_ times: Int, outOf: Int) -> Bool {
        if (0 ... outOf).randomWithin() < Double(times) {
            return self
        } else {
            return !self
        }
    }
}

