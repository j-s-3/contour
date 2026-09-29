import Foundation

struct StreamingArrayExtractor {
    let key: String

    private var buffer: [UInt8] = []
    private var cursor = 0
    private var inArray = false
    private var finished = false
    private var depth = 0
    private var inString = false
    private var escaped = false
    private var elementStart: Int?
    private var keySearchOffset = 0

    private var keyPatternOverlap: Int { key.utf8.count + 128 }

    init(key: String) {
        self.key = key
    }

    mutating func consume(_ fragment: String) -> [[String: Any]] {
        guard !finished else { return [] }
        buffer.append(contentsOf: fragment.utf8)

        if !inArray {
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
                finished = true
                return out
            default:
                break
            }
        }
        return out
    }
}
