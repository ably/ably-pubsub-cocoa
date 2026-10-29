@testable import AblyLiveObjects
@testable import AblyLiveObjectsTesting
import AblyPubSubDevice
import Testing

/// Tests for `SyncCursor`'s parsing of an `OBJECT_SYNC` `channelSerial` (RTO5a1, RTO5a4).
///
/// A `channelSerial` with no colon separator is malformed (handling unspecified by RTO5a); parsing it
/// throws. The resulting behaviour is exercised end-to-end in
/// `InternalDefaultRealtimeObjectsTests.HandleObjectSyncProtocolMessageTests`.
struct SyncCursorTests {
    // The parsing described in RTO5a1: `<sequence id>:<cursor value>`.
    @Test
    func validChannelSerialWithCursorValue() throws {
        // Given
        let channelSerial = "sequence123:cursor456"

        // When
        let cursor = try SyncCursor(channelSerial: channelSerial)

        // Then
        #expect(cursor.sequenceID == "sequence123")
        #expect(cursor.cursorValue == "cursor456")
        #expect(!cursor.isEndOfSequence)
    }

    // RTO5a4: the sequence is complete once the cursor is empty, i.e. `<sequence id>:`.
    @Test
    func validChannelSerialAtEndOfSequence() throws {
        // Given
        let channelSerial = "sequence123:"

        // When
        let cursor = try SyncCursor(channelSerial: channelSerial)

        // Then
        #expect(cursor.sequenceID == "sequence123")
        #expect(cursor.cursorValue == nil)
        #expect(cursor.isEndOfSequence)
    }

    // A channelSerial with no colon separator does not conform to RTO5a1, so parsing throws.
    @Test
    func invalidChannelSerialWithoutColon() {
        // Given
        let channelSerial = "sequence123"

        // When/Then
        do {
            _ = try SyncCursor(channelSerial: channelSerial)
            Issue.record("Expected error was not thrown")
        } catch {
            guard let liveObjectsError = error.testsOnly_underlyingLiveObjectsError,
                  case .other(SyncCursor.Error.channelSerialDoesNotMatchExpectedFormat) = liveObjectsError
            else {
                Issue.record("Expected channelSerialDoesNotMatchExpectedFormat error")
                return
            }
        }
    }

    // An empty channelSerial has no colon separator either, so parsing throws.
    @Test
    func invalidEmptyChannelSerial() {
        // Given
        let channelSerial = ""

        // When/Then
        do {
            _ = try SyncCursor(channelSerial: channelSerial)
            Issue.record("Expected error was not thrown")
        } catch {
            guard let liveObjectsError = error.testsOnly_underlyingLiveObjectsError,
                  case .other(SyncCursor.Error.channelSerialDoesNotMatchExpectedFormat) = liveObjectsError
            else {
                Issue.record("Expected channelSerialDoesNotMatchExpectedFormat error")
                return
            }
        }
    }

    // The spec does not rule out an empty sequence id, so we accept it (everything before the first
    // colon is the sequence id, RTO5a1).
    @Test
    func validChannelSerialWithEmptySequenceID() throws {
        // Given
        let channelSerial = ":cursor456"

        // When
        let cursor = try SyncCursor(channelSerial: channelSerial)

        // Then
        // swiftlint:disable:next empty_string
        #expect(cursor.sequenceID == "")
        #expect(cursor.cursorValue == "cursor456")
        #expect(!cursor.isEndOfSequence)
    }

    // As above, an empty sequence id is accepted even when the cursor is also empty.
    @Test
    func validChannelSerialWithEmptySequenceIDAtEndOfSequence() throws {
        // Given
        let channelSerial = ":"

        // When
        let cursor = try SyncCursor(channelSerial: channelSerial)

        // Then
        // swiftlint:disable:next empty_string
        #expect(cursor.sequenceID == "")
        #expect(cursor.cursorValue == nil)
        #expect(cursor.isEndOfSequence)
    }
}
