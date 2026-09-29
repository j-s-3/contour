import Foundation

extension PRGraph {
    var thingsToThinkAbout: [Consideration] {
        if let considerations = pr.considerations, !considerations.isEmpty {
            return considerations
        }
        var out: [Consideration] = []
        if let q = dominantBehaviorChange?.humanQuestion {
            out.append(Self.condense(q, id: "human-question", kind: .concern))
        }
        for (i, s) in pr.needsJudgment.enumerated() {
            out.append(Self.condense(s, id: "judgment-\(i)", kind: .concern))
        }
        for (i, s) in pr.uncertainties.enumerated() {
            out.append(Self.condense(s, id: "uncertainty-\(i)", kind: .question))
        }
        return out
    }

    func thingsToThinkAbout(during analysis: AnalysisState) -> [Consideration]? {
        let judgment = analysis.status(.judgment)
        guard analysis.isComplete || judgment.isSettled || judgment == .stale else { return nil }
        return thingsToThinkAbout
    }

    static func condense(_ statement: Statement, id: String, kind: ConsiderationKind) -> Consideration {
        let sentences = splitSentences(stripCodeLocations(statement.text))
        let questionIndex = sentences.firstIndex { $0.hasSuffix("?") }
        let headlineIndex = questionIndex ?? 0
        let headline = sentences.indices.contains(headlineIndex) ? sentences[headlineIndex] : statement.text
        let rest = sentences.enumerated().filter { $0.offset != headlineIndex }.map(\.element)
        return Consideration(
            id: id,
            question: headline,
            detail: rest.first ?? "",
            kind: kind,
            provenance: statement.provenance,
            confidence: statement.confidence,
            explanation: rest.count > 1 ? statement.text : nil
        )
    }

    static func stripCodeLocations(_ text: String) -> String {
        let parenthesized = #"\s*\((?:[^()]*?[\w./-]+\.[A-Za-z0-9]+:\d+[^()]*)\)"#
        let bare = #"\s*(?:\b(?:at|in|from)\s+)?`?[\w./-]+\.[A-Za-z][A-Za-z0-9]*:\d+(?:[-–]\d+)?`?"#
        var stripped = text.replacingOccurrences(of: parenthesized, with: "", options: .regularExpression)
        stripped = stripped.replacingOccurrences(of: bare, with: "", options: .regularExpression)
        stripped = stripped.replacingOccurrences(of: #"\s+([,;:]|\.(?!\.))"#, with: "$1", options: .regularExpression)
        return stripped.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
    }

    private static let abbreviations: Set<String> = ["e.g.", "i.e.", "etc.", "vs.", "cf.", "approx."]

    static func splitSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        var current = ""
        let chars = Array(text)
        for (i, ch) in chars.enumerated() {
            current.append(ch)
            let lastWord = current.split(whereSeparator: \.isWhitespace).last.map { String($0).lowercased() } ?? ""
            let atBoundary = ".?!".contains(ch) && (i + 1 == chars.count || chars[i + 1].isWhitespace)
                && !abbreviations.contains(lastWord.trimmingCharacters(in: CharacterSet(charactersIn: "(")))
                && !lastWord.hasSuffix("..")
                && current.filter({ $0 == "`" }).count % 2 == 0
            if atBoundary {
                let trimmed = current.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { sentences.append(trimmed) }
                current = ""
            }
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { sentences.append(tail) }
        return sentences
    }
}
