import Foundation

/// The reviewer's judgment, rendered as Markdown to paste into a GitHub review comment: what
/// changed in one line, each decision they judged with its state and note, and the Overview
/// questions no "Looks good" has settled yet. Posting reviews is deferred (§8); when it
/// lands, this is the payload it sends.
extension PRGraph {
    var reviewSummaryMarkdown: String {
        var sections: [String] = []

        if let changed = whatChangedLine {
            sections.append("**What changed:** \(changed)")
        }

        let toReview = decisionsToReview
        var decisionsSection = "### Decisions"
        if !toReview.isEmpty {
            let judgedCount = toReview.filter { $0.reviewerState != .unreviewed }.count
            decisionsSection += " (\(judgedCount) of \(toReview.count) to review judged)"
        }
        let judged = judgedDecisions
        if judged.isEmpty {
            decisionsSection += "\n\n_No decisions judged yet._"
        } else {
            decisionsSection += "\n\n" + judged.map(summaryItem).joined(separator: "\n")
        }
        sections.append(decisionsSection)

        let open = openQuestions
        if !open.isEmpty {
            sections.append("### Open questions\n\n" + open.map { "- \($0.question)" }.joined(separator: "\n"))
        }

        return sections.joined(separator: "\n\n") + "\n"
    }

    /// The plain-language "how it was solved" when the analysis has it, else the PR's intent —
    /// first sentence only, code locations stripped.
    private var whatChangedLine: String? {
        let text = pr.howItWasSolved?.text ?? pr.intent.text
        let line = Self.firstSentence(text).trimmingCharacters(in: .whitespacesAndNewlines)
        return line.isEmpty ? nil : line
    }

    /// Decisions the reviewer marked or annotated, the ones that need a response first, in
    /// the order Decisions shows them within each state.
    private var judgedDecisions: [DecisionNode] {
        let ordered = decisionsToReview + otherDecisions
        let marked = ordered.filter { $0.reviewerState != .unreviewed || !Self.trimmedNote($0).isEmpty }
        return marked.enumerated()
            .sorted { ($0.element.reviewerState.summaryRank, $0.offset) < ($1.element.reviewerState.summaryRank, $1.offset) }
            .map(\.element)
    }

    /// Overview questions whose decision the reviewer hasn't accepted — the ones still open.
    private var openQuestions: [Consideration] {
        thingsToThinkAbout.filter { item in
            guard let id = reviewDecisionId(for: item), let d = decision(id) else { return true }
            return d.reviewerState != .accepted
        }
    }

    private func summaryItem(_ d: DecisionNode) -> String {
        let label = d.reviewerState == .unreviewed ? "Note" : d.reviewerState.label
        var item = "- **\(label)** — \(brief(for: d).question)"
        let note = Self.trimmedNote(d)
        if !note.isEmpty {
            // Quoted and indented under the bullet so a multi-line note stays one list item.
            item += "\n" + note.components(separatedBy: .newlines)
                .map { $0.isEmpty ? "  >" : "  > \($0)" }
                .joined(separator: "\n")
        }
        return item
    }

    private static func trimmedNote(_ d: DecisionNode) -> String {
        d.reviewerNote.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension ReviewerState {
    /// Needs discussion, then questioned, then accepted: what the author must answer first.
    var summaryRank: Int {
        switch self {
        case .discuss: return 0
        case .questioned: return 1
        case .accepted: return 2
        case .unreviewed: return 3
        }
    }
}
