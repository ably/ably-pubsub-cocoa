import Foundation

/// Dot-delimited path <-> segment-list conversions for the path-based public API.
///
/// A `PathObject` stores its path as an ordered `[String]` of raw segments (RTPO2a); backslash
/// escaping lives only at the two string boundaries: ``join(_:)`` renders the stored segments as the
/// dot-delimited `path()` string (RTPO4b — dots inside a segment escaped), and ``parse(_:)`` splits a
/// user-supplied dot-delimited `at()` argument back into segments (RTPO6b). The stored segments are
/// never re-parsed, so a segment may contain any character (including a backslash) without ambiguity.
///
/// This mirrors ably-js's path-escaping (`_escapePath` / `at`) exactly, so the rendered path string
/// agrees byte-for-byte across SDKs.
internal enum PathSegments {
    /// RTPO6b — split `path` on unescaped dots; `\.` yields a literal dot; any other `\x` keeps the
    /// backslash; a trailing lone `\` is kept. `""` parses to one empty segment. Manual scanner (no
    /// regex lookbehind), matching ably-js's path-escaping behaviour.
    internal static func parse(_ path: String) -> [String] {
        var segments: [String] = []
        var currentSegment = ""
        var escaping = false
        for char in path {
            if escaping {
                // Only an escaped dot is unescaped; every other `\x` keeps the backslash, replicating
                // ably-js's `.replace(/\\\./g, '.')` (which unescapes escaped dots only).
                if char != "." {
                    currentSegment.append("\\")
                }
                currentSegment.append(char)
                escaping = false
                continue
            }
            switch char {
            case "\\":
                escaping = true
            case ".":
                segments.append(currentSegment)
                currentSegment = ""
            default:
                currentSegment.append(char)
            }
        }
        if escaping {
            currentSegment.append("\\")
        }
        segments.append(currentSegment)
        return segments
    }

    /// RTPO4a/RTPO4b — render the stored segments as the dot-delimited `path()` string, escaping only
    /// dots inside a segment (ably-js `_escapePath`). Empty list -> `""` (RTPO4c).
    internal static func join(_ segments: [String]) -> String {
        segments
            .map { $0.replacingOccurrences(of: ".", with: "\\.") }
            .joined(separator: ".")
    }
}
