@testable import AblyLiveObjects
import AblyPubSubDevice
import Foundation
import Testing

/// Values that survive `Double` → JSON text → `Double` only if the text is parsed exactly: they are
/// the ones `JSONSerialization` hands back as an `NSDecimalNumber` whose `doubleValue` lands one or
/// two ULP away from what was written. A subset of the list in `NSNumberExactDoubleValueTests`; three
/// is enough for tests that each pay for a sandbox round trip.
///
/// At file scope so that the suite's `@Test(arguments:)` attributes can refer to it.
private let impreciselyConvertedValues: [Double] = [
    0.015034388851090229,
    0.023942638935083197,
    0.050053335337711245,
]

/// Checks that a `Double` written into the graph comes back bit-for-bit identical after a round trip
/// through the Ably system.
///
/// This is the integration-level counterpart of `NSNumberExactDoubleValueTests`, covering the reason
/// the SDK reads wire numbers through `NSNumber.art_doubleValue`. Reverting any of those reads to
/// `doubleValue` fails the JSON tests here.
///
/// The MessagePack tests pass either way — a float64 on the wire decodes to a plain `NSNumber` that
/// already holds the closest `Double` — and are here to pin that down.
@Suite(.tags(.integration), .serialized)
struct NumberPrecisionTests {
    @Test(arguments: impreciselyConvertedValues)
    func mapNumberSurvivesJSONRoundTrip(value: Double) async throws {
        try await Self.checkMapNumberSurvivesRoundTrip(value: value, useBinaryProtocol: false)
    }

    @Test(arguments: impreciselyConvertedValues)
    func mapNumberSurvivesMessagePackRoundTrip(value: Double) async throws {
        try await Self.checkMapNumberSurvivesRoundTrip(value: value, useBinaryProtocol: true)
    }

    @Test(arguments: impreciselyConvertedValues)
    func counterValueSurvivesJSONRoundTrip(value: Double) async throws {
        try await Self.checkCounterValueSurvivesRoundTrip(value: value, useBinaryProtocol: false)
    }

    @Test(arguments: impreciselyConvertedValues)
    func counterValueSurvivesMessagePackRoundTrip(value: Double) async throws {
        try await Self.checkCounterValueSurvivesRoundTrip(value: value, useBinaryProtocol: true)
    }

    // MARK: - Round trips

    /// Covers the `ObjectsMapEntry.data.number` read (RTLM5d2d).
    private static func checkMapNumberSurvivesRoundTrip(
        value: Double,
        useBinaryProtocol: Bool,
        sourceLocation: SourceLocation = #_sourceLocation,
    ) async throws {
        try await withRootMap(useBinaryProtocol: useBinaryProtocol) { root in
            try await root.set(key: "number", value: .primitive(.number(value)))

            try await waitUntil("the value is in the graph", sourceLocation: sourceLocation) {
                try root.get(key: "number").asPrimitive().value() != nil
            }

            let actual = try root.get(key: "number").asPrimitive().value()?.numberValue
            #expect(actual == value, sourceLocation: sourceLocation)
        }
    }

    /// Covers the `counterCreate.count` (RTLC6c, RTLC16a) and `counterInc.number` (RTLC9f) reads. The
    /// same value serves as both the initial count and the increment; doubling it is exact in binary
    /// floating point, so a misread of either read still shows up in the final count.
    private static func checkCounterValueSurvivesRoundTrip(
        value: Double,
        useBinaryProtocol: Bool,
        sourceLocation: SourceLocation = #_sourceLocation,
    ) async throws {
        try await withRootMap(useBinaryProtocol: useBinaryProtocol) { root in
            try await root.set(key: "counter", value: .liveCounter(.create(initialCount: value)))
            let counter = root.get(key: "counter").asLiveCounter()

            try await waitUntil("the counter is in the graph", sourceLocation: sourceLocation) {
                try counter.value() != nil
            }

            // The initial count reaches us as ObjectState.counter.count in the OBJECT_SYNC, or as
            // ObjectOperation.counterCreate.count in the echoed OBJECT
            let countAfterCreate = try counter.value()
            #expect(countAfterCreate == value, sourceLocation: sourceLocation)

            try await counter.increment(amount: value)

            try await waitUntil("the increment has been applied", sourceLocation: sourceLocation) {
                try counter.value() != value
            }

            // The increment reaches us as ObjectOperation.counterInc.number
            let countAfterIncrement = try counter.value()
            #expect(countAfterIncrement == value + value, sourceLocation: sourceLocation)
        }
    }

    // MARK: - Helpers

    /// Creates a sandbox client, attaches to a fresh channel, and calls `body` with the channel's root
    /// map. Holds on to the client (which the path object does not) until `body` returns.
    private static func withRootMap(
        useBinaryProtocol: Bool,
        _ body: (any LiveMapPathObject) async throws -> Void,
    ) async throws {
        let realtime = try await ClientHelper.realtimeWithObjects(options: .init(useBinaryProtocol: useBinaryProtocol))
        defer { realtime.close() }

        let channel = realtime.channels.get(UUID().uuidString, options: ClientHelper.channelOptionsWithObjects())
        try await channel.attachAsync()

        let root = try await channel.object.get()
        try await body(root)
    }

    /// Polls `condition` until it holds, recording a failure if it does not do so within `timeout`.
    /// `set` and `increment` return once the operation has been ACKed, which is before the echoed
    /// OBJECT message that puts the value into the graph has been applied — hence the wait.
    private static func waitUntil(
        _ description: String,
        timeout: TimeInterval = 10,
        sourceLocation: SourceLocation = #_sourceLocation,
        _ condition: () throws -> Bool,
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if try condition() {
                return
            }
            try await Task.sleep(nanoseconds: 50 * NSEC_PER_MSEC)
        }

        Issue.record("Timed out after \(timeout)s waiting for: \(description)", sourceLocation: sourceLocation)
    }
}
