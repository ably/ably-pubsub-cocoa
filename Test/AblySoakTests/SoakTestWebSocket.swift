import Foundation
import Ably.Private

class SoakTestWebSocketFactory: WebSocketFactory {
    func createWebSocket(with request: URLRequest, logger: InternalLog?) -> ARTWebSocket {
        return SoakTestWebSocket(urlRequest: request)
    }
}

class SoakTestRealtimeTransportFactory: RealtimeTransportFactory {
    func transport(withRest rest: ARTRestInternal, options: ARTClientOptions, resumeKey: String?, logger: InternalLog) -> ARTRealtimeTransport {
        return ARTWebSocketTransport(
            rest: rest,
            options: options,
            resumeKey: resumeKey,
            logger: logger,
            webSocketFactory: SoakTestWebSocketFactory()
        )
    }
}

class SoakTestWebSocket: NSObject, ARTWebSocket {
    var readyState: ARTWebSocketReadyState
    var delegateDispatchQueue: DispatchQueue?
    var delegate: ARTWebSocketDelegate?

    let id = nextGlobalSerial()
    let connectionId: String

    required init(urlRequest request: URLRequest) {
        readyState = .closed
        connectionId = "fakeConnection.\(id)"
        // TODO (maybe?): Extract connectionKey from params, resume conn state if
        // connectionStateTtl hasn't passed yet.
    }

    func open() {
        readyState = .connecting
        delegateDispatchQueue!.afterSeconds(between: 0.1 ... ARTDefault.realtimeRequestTimeout() + 1.0) {
            if true.times(9, outOf: 10) {
                self.readyState = .open
                self.delegate?.webSocketDidOpen?(self)

                self.doIfStillOpen(afterSecondsBetween: 0.1 ... 3.0) {
                    if true.times(9, outOf: 10) {
                        self.messageToClient(action: .connected) { m in
                            m.connectionId = self.connectionId
                            m.connectionDetails = ARTConnectionDetails(
                                clientId: "*",
                                connectionKey: "fakeConnectionKey.\(self.id))",
                                maxMessageSize: 999999999,
                                maxFrameSize: 999999999,
                                maxInboundRate: 999999999,
                                connectionStateTtl: 2.0,
                                serverId: "fakeServer",
                                maxIdleInterval: (0.0 ... 60.0).randomWithin(),
                                objectsGCGracePeriod: nil,
                                siteCode: nil
                            )
                        }
                        self.ackMessages()
                        self.sendHeartbeats()
                    } else {
                        self.messageToClient(action: .error) { m in
                            m.error = ARTErrorInfo.create(from: fakeError)
                        }
                    }
                }

                self.doIfStillOpen(afterSecondsBetween: 3.0 ... 300.0) {
                    let (code, clean) : (ARTSRStatusCode, Bool) = [
                        (.codeAbnormal, false),
                        (.codeNormal, true),
                        (.codeGoingAway, true),
                        (.codePolicyViolated, true),
                        (.codeMessageTooBig, true),
                        (.codeInternalError, true),
                    ].randomElement(using: &seededRandomNumberGenerator)!
                    self.delegate?.webSocket?(self, didCloseWithCode: code.rawValue, reason: "fake close", wasClean: clean)
                }
            } else {
                self.delegate?.webSocket?(self, didFailWithError: fakeError)
            }
        }
    }

    func sendHeartbeats() {
        doIfStillOpen(afterSecondsBetween: (2.0 ... 30.0)) {
            self.messageToClient(action: .heartbeat)
            self.sendHeartbeats()
        }
    }

    func protocolMessage(action: ARTProtocolMessageAction, setUp: (ARTProtocolMessage) -> Void = { _ in }) -> ARTProtocolMessage {
        return ARTProtocolMessage.build(action: action) { m in
            m.connectionId = self.connectionId
            // Presence members inherit their `id` from the containing protocol message,
            // and `ARTPresenceMessage.isSynthesized` reads it as `<connectionId>:…`.
            m.id = "\(self.connectionId):\(nextGlobalSerial())"
            m.timestamp = Date()
            setUp(m)
        }
    }

    func messageToClient(action: ARTProtocolMessageAction, setUp: (ARTProtocolMessage) -> Void = { _ in }) {
        let message = protocolMessage(action: action, setUp: setUp)
        self.delegate?.webSocket?(self, didReceiveMessage: message)
    }

    func close(withCode code: Int, reason: String?) {
        readyState = .closing
        delegateDispatchQueue!.afterSeconds(between: 0.1 ... 3.0) {
            if self.readyState != .closing {
                return
            }
            self.readyState = .closed
        }
    }

    var pendingSerials: [NSNumber] = []

    func ackMessages() {
        doIfStillOpen(afterSecondsBetween: 0.1 ... 3.0) {
            self.ackMessages()

            if self.pendingSerials.count == 0 {
                return
            }

            if true.times(1, outOf: 5) {
                self.messageToClient(action: .ack) { m in
                    m.msgSerial = self.pendingSerials.first!
                    m.count = Int32(self.pendingSerials.count)
                }
            } else {
                self.messageToClient(action: .nack) { m in
                    m.msgSerial = self.pendingSerials.first!
                    m.count = Int32(self.pendingSerials.count)
                    m.error = ARTErrorInfo.create(from: fakeError)
                }
            }
            self.pendingSerials.removeAll()
        }
    }

    func send(_ msgPackEncodedMessage: Any?) {
        let message = try! msgPackEncoder.decodeProtocolMessage(msgPackEncodedMessage as! Data)

        switch message.action {
        case .close:
            doIfStillOpen(afterSecondsBetween: 0.1 ... 3.0) {
                self.messageToClient(action: .closed)
                self.doIfStillOpen(afterSecondsBetween: 0.1 ... 0.5) {
                    self.delegate?.webSocket?(self, didCloseWithCode: 1000, reason: nil, wasClean: true)
                }
            }
        case .message:
            delegateDispatchQueue!.async {
                self.pendingSerials.append(message.msgSerial!)
            }
        case .attach:
            doIfStillOpen(afterSecondsBetween: 0.1 ... 3.0) {
                let serial: Int64
                if let s = self.serialForAttachedChannel[message.channel!] {
                    serial = s
                } else {
                    if true.times(1, outOf: 10) {
                        self.messageToClient(action: .error) { m in
                            m.channel = message.channel
                            m.error = ARTErrorInfo.create(from: fakeError)
                        }
                        return
                    }

                    serial = -1
                    self.serialForAttachedChannel[message.channel!] = -1
                }

                let hasPresence = true.times(4, outOf: 5)

                self.messageToClient(action: .attached) { m in
                    m.channel = message.channel
                    m.channelSerial = "somethingsomething:\(serial)"
                    if hasPresence {
                        m.flags = m.flags | Int64(ARTProtocolMessageFlag.hasPresence.rawValue)
                    }
                }

                if hasPresence {
                    self.startPresenceSync(channel: message.channel!)
                }

                self.sendMessages(channel: message.channel!)
                self.sendPresenceMessages(channel: message.channel!)
            }
        case .detach:
            doIfStillOpen(afterSecondsBetween: 0.1 ... 3.0) {
                self.messageToClient(action: .detached) { m in
                    m.channel = message.channel
                    if true.times(1, outOf: 5) {
                        m.error = ARTErrorInfo.create(from: fakeError)
                    }
                }

                self.serialForAttachedChannel.removeValue(forKey: message.channel!)
            }
        case .auth:
            doIfStillOpen(afterSecondsBetween: 0.1 ... 3.0) {
                if true.times(1, outOf: 10) {
                    self.messageToClient(action: .error) { m in
                        m.error = authError()
                    }
                } else {
                    self.messageToClient(action: .connected)
                }
            }
        default:
            break
        }
    }

    var serialForAttachedChannel: [String: Int64] = [:]

    func nextMessageToClient(forChannel channel: String, action: ARTProtocolMessageAction, setUp: (ARTProtocolMessage) -> Void = { _ in }) {
        guard var channelSerial = self.serialForAttachedChannel[channel] else {
            return
        }
        channelSerial += 1
        self.serialForAttachedChannel[channel] = channelSerial

        messageToClient(action: action) { m in
            m.channel = channel
            m.channelSerial = "somethingsomething:\(channelSerial)"
            setUp(m)
        }
    }

    func sendMessages(channel: String) {
        doIfStillOpen(afterSecondsBetween: 0.1 ... 2.0) {
            self.nextMessageToClient(forChannel: channel, action: .message) { m in
                m.messages = [ARTMessage(
                    name: "fakeMessage",
                    data: randomMessageData()
                )]
            }

            self.sendMessages(channel: channel)
        }
    }

    func sendPresenceMessages(channel: String) {
        doIfStillOpen(afterSecondsBetween: 0.1 ... 2.0) {
            let presence = ARTPresenceMessage()
            presence.clientId = "someone.\(nextGlobalSerial())"
            presence.data = randomMessageData()
            presence.action = .enter

            self.nextMessageToClient(forChannel: channel, action: .presence) { m in
                m.presence = [presence]
            }

            self.sendPresenceMessages(channel: channel)

            self.updatePresence(channel: channel, clientId: presence.clientId!)
        }
    }

    func updatePresence(channel: String, clientId: String) {
        doIfStillOpen(afterSecondsBetween: 0.1 ... 10.0) {
            let presence = ARTPresenceMessage()
            presence.clientId = clientId

            if true.times(3, outOf: 4) {
                presence.action = .update
                presence.data = randomMessageData()
            } else {
                presence.action = .leave
            }

            self.nextMessageToClient(forChannel: channel, action: .presence) { m in
                m.presence = [presence]
            }

            if presence.action == .update {
                self.updatePresence(channel: channel, clientId: clientId)
            }
        }
    }

    func startPresenceSync(channel: String) {
        let numMembers = Int((1 ... 10).randomWithin())
        let members = (1 ... numMembers).map { "member\($0)" }
        let memberPages = Array(Groups(of: 3, outOf: members))
        var iter = memberPages.enumerated().makeIterator()

        sendPresenceSyncs(next: { iter.next() }, numPages: memberPages.count)
    }

    func sendPresenceSyncs(next: @escaping () -> (Int, [String])?, numPages: Int) {
        guard let (i, page) = next() else {
            return
        }

        var cursor: String
        let isLast = i == numPages - 1
        if isLast {
            cursor = ""
        } else {
            cursor = "page\(i)"
        }

        doIfStillOpen(afterSecondsBetween: (0.1 ... 1.0)) {
            self.messageToClient(action: .sync) { m in
                m.channelSerial = "somethingsomething:\(cursor)"
                m.presence = page.map { member in
                    let message = ARTPresenceMessage()
                    message.clientId = member
                    message.action = .present
                    return message
                }
            }

            self.sendPresenceSyncs(next: next, numPages: numPages)
        }
    }

    func doIfStillOpen(afterSecondsBetween between: ClosedRange<TimeInterval>, execute: @escaping () -> Void) {
        delegateDispatchQueue!.afterSeconds(between: between) {
            if self.readyState != .open {
                return
            }
            execute()
        }
    }
}

let jsonEncoder = ARTJsonLikeEncoder(delegate: ARTJsonEncoder(), timeProvider: SystemTimeProvider())
let msgPackEncoder = ARTJsonLikeEncoder(delegate: ARTMsgPackEncoder(), timeProvider: SystemTimeProvider())

extension String {
    func asError(code: Int = 1) -> NSError {
        return NSError(domain: "io.ably", code: code, userInfo: [NSLocalizedDescriptionKey: self])
    }
}

let fakeError = "fake error for soak test".asError()

func authError() -> ARTErrorInfo {
    return ARTErrorInfo.create(from: "fake auth error".asError(code: 40140))
}

func serialSequence(label: String, first: Int64 = 0) -> (() -> Int64) {
    let queue = DispatchQueue(label: "io.ably.soakTest.\(label)")
    var serial: Int64 = first

    return {
        var assigned: Int64!
        queue.sync {
            assigned = serial
            serial += 1
        }
        return assigned
    }
}

let nextGlobalSerial = serialSequence(label: "globalSerial")

extension ARTProtocolMessage {
    class func build(action: ARTProtocolMessageAction, setUp: (ARTProtocolMessage) -> Void) -> ARTProtocolMessage {
        let m = ARTProtocolMessage()
        m.action = action
        m.id = "fakeProtocolMessage.\(nextGlobalSerial())"
        setUp(m)
        return m
    }
}

private class Groups<S: Sequence>: Sequence, IteratorProtocol {
    typealias Element = [S.Element]

    let perGroup: Int
    var outOf: S.Iterator
    var done = false

    required init(of: Int, outOf: S) {
        self.perGroup = of
        self.outOf = outOf.makeIterator()
    }

    func next() -> Element? {
        if done {
            return nil
        }

        var group: [S.Element]?

        for _ in 0 ..< perGroup {
            guard let next = outOf.next() else {
                done = true
                break
            }

            if group == nil {
                group = []
            }
            group!.append(next)
        }

        return group
    }
}


