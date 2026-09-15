import Foundation
import AblyPubSubDevice
import AblyPubSubDevice.Private

/// A `Sendable` description of a server-to-client protocol message that a test injects via
/// `MockWebSocket.sendToClient(_:)` / `sendToClientAndClose(_:)`.
struct ProtocolMessage: Sendable {

    private enum Kind: Sendable {
        case connected(connectionId: String, connectionKey: String, maxIdleInterval: TimeInterval, connectionStateTtl: TimeInterval)
        case attached(channel: String, channelSerial: String)
        case error(code: Int, statusCode: Int, message: String)
        case ack(msgSerial: Int, count: Int)
        case closed
    }

    private let kind: Kind

    /// A ready-to-use default `CONNECTED` message (ably-java's `CONNECTED_MESSAGE`) so most tests
    /// don't hand-build one: connectionId `test-connection-id`, key `test-connection-key`,
    /// TTL 120 s, max-idle 15 s. A value type, so it is always a fresh instance.
    static var connectedMessage: ProtocolMessage {
        .connected(connectionId: "test-connection-id", connectionKey: "test-connection-key")
    }

    /// A `CONNECTED` message carrying connection details (UTS `ProtocolMessage(action: CONNECTED, ...)`).
    static func connected(connectionId: String,
                          connectionKey: String,
                          maxIdleInterval: TimeInterval = 15,
                          connectionStateTtl: TimeInterval = 120) -> ProtocolMessage {
        .init(kind: .connected(connectionId: connectionId, connectionKey: connectionKey, maxIdleInterval: maxIdleInterval, connectionStateTtl: connectionStateTtl))
    }

    /// An `ATTACHED` message for a channel (UTS `ProtocolMessage(action: ATTACHED, ...)`).
    static func attached(channel: String, channelSerial: String) -> ProtocolMessage {
        .init(kind: .attached(channel: channel, channelSerial: channelSerial))
    }

    /// An `ERROR` message (UTS `ProtocolMessage(action: ERROR, error: ErrorInfo(...))`).
    static func error(code: Int, statusCode: Int, message: String) -> ProtocolMessage {
        .init(kind: .error(code: code, statusCode: statusCode, message: message))
    }

    /// An `ACK` message (UTS `ProtocolMessage(action: ACK, msgSerial: ..., count: ...)`).
    static func ack(msgSerial: Int, count: Int) -> ProtocolMessage {
        .init(kind: .ack(msgSerial: msgSerial, count: count))
    }

    /// A `CLOSED` message (UTS `ProtocolMessage(action: CLOSED)`).
    static func closed() -> ProtocolMessage {
        .init(kind: .closed)
    }

    /// Builds the concrete `ARTProtocolMessage`. Call on the delegate queue, at delivery time.
    func makeProtocolMessage() -> ARTProtocolMessage {
        let message = ARTProtocolMessage()
        switch kind {
        case let .connected(connectionId, connectionKey, maxIdleInterval, connectionStateTtl):
            message.action = .connected
            message.connectionId = connectionId
            message.connectionKey = connectionKey
            message.connectionDetails = ARTConnectionDetails(
                clientId: nil,
                connectionKey: connectionKey,
                maxMessageSize: 0,
                maxFrameSize: 0,
                maxInboundRate: 0,
                connectionStateTtl: connectionStateTtl,
                serverId: "",
                maxIdleInterval: maxIdleInterval,
                objectsGCGracePeriod: nil,
                siteCode: nil
            )
        case let .attached(channel, channelSerial):
            message.action = .attached
            message.channel = channel
            message.channelSerial = channelSerial
        case let .error(code, statusCode, text):
            message.action = .error
            message.error = ARTErrorInfo.create(withCode: code, status: statusCode, message: text)
        case let .ack(msgSerial, count):
            message.action = .ack
            message.msgSerial = NSNumber(value: msgSerial)
            message.count = Int32(count)
        case .closed:
            message.action = .closed
        }
        return message
    }
}
