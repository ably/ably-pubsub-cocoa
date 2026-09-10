import Ably
import Foundation

/// The `OBJECT_SYNC` sync cursor, as extracted from a `channelSerial` per RTO5a1 and RTO5a4.
internal struct SyncCursor {
    internal var sequenceID: String
    /// `nil` in the case where the objects sync sequence is complete (RTO5a4).
    internal var cursorValue: String?

    internal enum Error: Swift.Error {
        case channelSerialDoesNotMatchExpectedFormat(String)
    }

    /// Creates a `SyncCursor` from the `channelSerial` of an `OBJECT_SYNC` `ProtocolMessage`.
    ///
    /// Per RTO5a1–RTO5a5 the `channelSerial` is a two-part identifier `<sequence id>:<cursor value>`:
    /// everything up to the first colon is the sequence id (RTO5a1) and an empty cursor value marks the
    /// end of the sync sequence (RTO5a4).
    ///
    /// A `channelSerial` that lacks a colon separator is malformed. Per RTO5a6 such a `channelSerial`
    /// must be treated as if it were absent (RTO5a5); we surface the malformed case as a thrown ``Error``
    /// so the caller can apply that handling.
    internal init(channelSerial: String) throws(ARTErrorInfo) {
        let scanner = Scanner(string: channelSerial)
        scanner.charactersToBeSkipped = nil

        // RTO5a1: everything up to the first colon is the sequence id.
        let sequenceID = scanner.scanUpToString(":") ?? ""

        // RTO5a6: a serial with no colon separator (e.g. "sequence123") is malformed.
        guard scanner.scanString(":") != nil else {
            throw LiveObjectsError.other(Error.channelSerialDoesNotMatchExpectedFormat(channelSerial)).toARTErrorInfo()
        }

        // RTO5a1: everything after the colon is the cursor value; empty marks the end of the sequence (RTO5a4).
        let remainingString = channelSerial[scanner.currentIndex...]
        let cursorValue = remainingString.isEmpty ? nil : String(remainingString)

        self.sequenceID = sequenceID
        self.cursorValue = cursorValue
    }

    /// Whether this cursor represents the end of the sync sequence, per RTO5a4.
    internal var isEndOfSequence: Bool {
        cursorValue == nil
    }
}
