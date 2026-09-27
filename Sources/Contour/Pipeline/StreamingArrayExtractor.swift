import Foundation

/// Pulls complete elements out of one top-level JSON array while the model is still writing
/// the object that contains it, so a decision or flow can be shown the moment the model
/// finishes writing it instead of when the whole stage returns (§ progressive analysis).
///
/// Deliberately narrow: it looks for `"<key>": [` and then yields each balanced `{…}` inside
/// that array, tracking strings and escapes so braces inside prose don't count. It never
/// decides anything — the stage's final text is still parsed in full and is authoritative;
/// these elements are a preview of it, appended in the order the model wrote them.
///
/// Scans UTF-8 bytes with integer offsets: every structural character is ASCII, so a
/// multi-byte character can never be mistaken for one, and offsets stay valid as the
/// buffer grows (a `String.Index` carries no such promise across appends).
struct StreamingArrayExtractor {
    let key: String

    private var buffer: [UInt8] = []
    /// Where scanning resumes. Everything before it has been consumed.
    private var cursor = 0
    private var inArray = false
    private var finished = false
    private var depth = 0
    private var inString = false
    private var escaped = false
    private var elementStart: Int?
    /// How much of `buffer` has already been searched for the key, before it's found. Only
    /// bytes at or after `keySearchOffset - keyPatternOverlap` are re-scanned on the next
    /// `consume`, so the total work across every fragment stays linear in the stream's
    /// length instead of re-decoding and re-searching the whole buffer on every call (which
    /// was quadratic: O(fragments × buffer size)).
    private var keySearchOffset = 0

    /// Enough bytes to cover `"key": [`, with generous slack for whitespace (or
    /// pretty-printed indentation/newlines) a model might put around the colon, so a match
    /// spanning the last search's boundary is never missed. A larger constant here only
    /// adds a fixed amount of re-scanned work per `consume` call, not a factor of the
    /// stream's total length, so it stays cheap to be generous.
    private var keyPatternOverlap: Int { key.utf8.count + 128 }

    init(key: String) {
        self.key = key
    }

    /// Feeds a fragment of streamed text and returns any elements completed by it.
    mutating func consume(_ fragment: String) -> [[String: Any]] {
        guard !finished else { return [] }
        buffer.append(contentsOf: fragment.utf8)

        if !inArray {
            // `"key"` then optional whitespace, a colon, optional whitespace, and `[`. Only
            // the unsearched tail (plus a small overlap) is decoded and matched, not the
            // whole buffer — see `keySearchOffset`.
            let searchStart = max(0, keySearchOffset - keyPatternOverlap)
            let text = String(decoding: buffer[searchStart...], as: UTF8.self)
            guard let range = text.range(of: #""\#(key)"\s*:\s*\["#, options: .regularExpression) else {
                keySearchOffset = buffer.count
                return []
            }
            inArray = true
            cursor = searchStart + text.utf8.distance(from: text.utf8.startIndex, to: range.upperBound)
        }

        var out: [[String: Any]] = []
        while cursor < buffer.count {
            let byte = buffer[cursor]
            defer { cursor += 1 }
            if inString {
                if escaped { escaped = false }
                else if byte == UInt8(ascii: "\\") { escaped = true }
                else if byte == UInt8(ascii: "\"") { inString = false }
                continue
            }
            switch byte {
            case UInt8(ascii: "\""):
                inString = true
            case UInt8(ascii: "{"):
                if depth == 0 { elementStart = cursor }
                depth += 1
            case UInt8(ascii: "}"):
                depth -= 1
                if depth == 0, let start = elementStart {
                    let data = Data(buffer[start...cursor])
                    if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        out.append(object)
                    }
                    elementStart = nil
                }
            case UInt8(ascii: "]") where depth == 0:
                // The array ended; nothing after it is ours.
                finished = true
                return out
            default:
                break
            }
        }
        return out
    }
}
