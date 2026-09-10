import Foundation

internal extension NSNumber {
    /// The `Double` closest to this number's value, which `doubleValue` does not always give.
    ///
    /// `JSONSerialization.jsonObject` does not represent every JSON number as a `Double`. A number
    /// whose text needs more than about 16 significant digits comes back as an `NSDecimalNumber`
    /// holding the exact decimal, and `NSDecimalNumber`'s conversion to binary floating point is not
    /// correctly rounded: it can land one unit in the last place away from the nearest `Double`.
    ///
    /// ```
    /// text          0.015034388851090229
    /// .stringValue  0.015034388851090229   exact
    /// .doubleValue  0.015034388851090227   one ULP low
    /// Double(text)  0.015034388851090229   correctly rounded
    /// ```
    ///
    /// Every other bridge Foundation offers — `Double(truncating:)`, `Double(exactly:)`, `as? Double` —
    /// shares that conversion and is wrong on exactly the same values. `Double(exactly:)` is worth
    /// singling out: it never returns `nil` for these, so it reports success while handing back a
    /// rounded value.
    ///
    /// The exact digits survive in the decimal representation, so the way out is to read them back as
    /// text and let `Double(_: String)`, which is correctly rounded, do the conversion.
    ///
    /// This only makes a difference when the JSON protocol is in use, that is when
    /// `ARTClientOptions.useBinaryProtocol` is `false` (it defaults to `true`). Under MessagePack a
    /// number arrives as a float64 and is decoded into a plain `NSNumber` that already holds the
    /// closest `Double`, so nothing here changes the value; there is no decimal text to misread.
    ///
    /// `NSNumberExactDoubleValueTests` covers this property and the `JSONValue` bridge above it;
    /// `NumberPrecisionTests` covers the whole round trip through the Ably system, and its JSON tests
    /// fail if any of the SDK's reads go back to `doubleValue`.
    ///
    /// The `NSDecimalNumber` test is not defensive. For an ordinary `NSNumber`, which already holds a
    /// `Double`, `stringValue` rounds to 16 significant digits and loses precision that `doubleValue`
    /// would have preserved — `greatestFiniteMagnitude` comes back as `1.797693134862316e+308`, which
    /// re-parses to infinity — so the text route must not be taken unconditionally.
    var art_doubleValue: Double {
        // Only NSDecimalNumber holds digits that `doubleValue` cannot see; for anything else it is
        // already the closest Double, and the textual route would be a downgrade.
        guard self is NSDecimalNumber, let exact = Double(stringValue) else {
            return doubleValue
        }

        return exact
    }
}
