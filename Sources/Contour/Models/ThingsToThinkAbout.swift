import Foundation

/// The Overview's "Things to think about" list, resolved from whatever the graph has.
///
/// New analyses carry `pr.considerations` — short, question-shaped items written to a
/// budget by the judgment stage. Older cached graphs (and the captured mock fixtures) only
/// have the verbose `needsJudgment`/`uncertainties` paragraphs plus the behavior change's
/// `humanQuestion`, so those are condensed here instead: first sentence as the headline,
/// code locations stripped, the rest kept as drill-down `explanation`. The analysis
/// engine's own taxonomy (judgment vs. uncertainty) survives only as `kind`, which picks a
/// glyph — it never dictates the layout.
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

    /// Splits a paragraph into a scannable headline and a short supporting sentence.
    /// A paragraph that asks a question leads with that question, since the question is
    /// what the reviewer is being asked to think about.
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

    /// "(src/input.rs:272-290)" and friends belong in the code viewer, not a headline.
    static func stripCodeLocations(_ text: String) -> String {
        let parenthesized = #"\s*\((?:[^()]*?[\w./-]+\.[A-Za-z0-9]+:\d+[^()]*)\)"#
        // "The unit test at src/input.rs:435-455 checks…" → "The unit test checks…"
        let bare = #"\s*(?:\b(?:at|in|from)\s+)?`?[\w./-]+\.[A-Za-z][A-Za-z0-9]*:\d+(?:[-–]\d+)?`?"#
        var stripped = text.replacingOccurrences(of: parenthesized, with: "", options: .regularExpression)
        stripped = stripped.replacingOccurrences(of: bare, with: "", options: .regularExpression)
        stripped = stripped.replacingOccurrences(of: #"\s+([,;:]|\.(?!\.))"#, with: "$1", options: .regularExpression)
        return stripped.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
    }

    /// Abbreviations that end in a period without ending the sentence.
    private static let abbreviations: Set<String> = ["e.g.", "i.e.", "etc.", "vs.", "cf.", "approx."]

    /// Sentence split on terminal punctuation followed by whitespace. Deliberately naive:
    /// decimal numbers and file extensions don't end in ". " so they survive.
    static func splitSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        var current = ""
        let chars = Array(text)
        for (i, ch) in chars.enumerated() {
            current.append(ch)
            let lastWord = current.split(whereSeparator: \.isWhitespace).last.map { String($0).lowercased() } ?? ""
            let atBoundary = ".?!".contains(ch) && (i + 1 == chars.count || chars[i + 1].isWhitespace)
                && !abbreviations.contains(lastWord.trimmingCharacters(in: CharacterSet(charactersIn: "(")))
                && !lastWord.hasSuffix("..")                                   // an ellipsis
                && current.filter({ $0 == "`" }).count % 2 == 0                // inside `inline code`
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
