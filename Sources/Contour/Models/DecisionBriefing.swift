import Foundation

/// A decision as the Decisions lens draws it by default: the question, the options with the
/// chosen one marked, the tradeoff the choice made, and why it landed on that side — one
/// visual unit, read as choice → alternative → tradeoff → rationale. Everything else on
/// `DecisionNode` is drill-down.
struct DecisionBrief: Hashable {
    var question: String
    /// Nil when there's nothing to draw — the lens falls back to `answer`/`insteadOf` lines.
    var shape: DecisionShape?
    var options: [DecisionOption]
    /// First sentence of what was decided, for graphs that carry no options.
    var answer: String
    /// First sentence of the leading alternative, for graphs that carry no options.
    var insteadOf: String?
    var why: Statement?
    /// The tradeoff drawn under the choice. Nil when there is none, or when the options
    /// already say it — they were derived from it, or name the same two qualities — so the
    /// same axis is never drawn twice.
    var tradeoff: DecisionTradeoff?

    var chosen: DecisionOption? { options.first { $0.chosen } }
}

/// The Decisions model, resolved from whatever the graph has.
///
/// New analyses carry `question`/`options`/`why` written to a budget by the decisions stage.
/// Older cached graphs (and the captured mock fixtures) only have the verbose record, so
/// it is condensed here instead — the same approach as `thingsToThinkAbout`: the primary
/// tradeoff's two dimensions stand in for the options, and the first rationale sentence, code locations
/// stripped, stands in for the why.
extension PRGraph {

    /// Decisions a staff engineer would weigh — shown by default and counted by review
    /// progress. When the analysis marked everything as implementation detail, everything
    /// counts rather than nothing.
    var primaryDecisions: [DecisionNode] {
        let system = decisions.filter { $0.level <= .system }
        return system.isEmpty ? decisions : system
    }

    /// Implementation choices: collapsed by default, never competing with the design choices.
    var implementationDecisions: [DecisionNode] {
        let primary = Set(primaryDecisions.map(\.id))
        return decisions.filter { !primary.contains($0.id) }
    }

    func brief(for d: DecisionNode) -> DecisionBrief {
        let tradeoff = d.primaryTradeoff
        let why = d.why ?? d.rationale.first.map(Self.condensedWhy)
        let answer = Self.firstSentence(d.decision.text)
        let insteadOf = d.alternatives.first.map { Self.firstSentence($0.text) }
        let question = d.question.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 } ?? d.title

        let explicit = d.options.filter { !$0.label.trimmingCharacters(in: .whitespaces).isEmpty }
        if explicit.count >= 2, explicit.contains(where: \.chosen) {
            // A "binary" choice with three options is really a list; anything else the model
            // picked is honored.
            // A before/after diagram needs exactly the old structure and the new, chosen one.
            let shape: DecisionShape
            switch d.shape {
            case .threshold?: shape = .threshold
            case .options?: shape = .options
            case .beforeAfter? where explicit.count == 2 && explicit[1].chosen: shape = .beforeAfter
            default: shape = explicit.count == 2 ? .binary : .options
            }
            let drawn = tradeoff.flatMap { Self.restates($0, explicit) ? nil : $0 }
            return DecisionBrief(question: question, shape: shape, options: explicit, answer: answer,
                                 insteadOf: insteadOf, why: why, tradeoff: drawn)
        }

        if let tradeoff {
            let leansB = tradeoff.chosenPosition >= 0.5
            let options = [
                DecisionOption(label: tradeoff.dimensionA, chosen: !leansB),
                DecisionOption(label: tradeoff.dimensionB, chosen: leansB)
            ]
            return DecisionBrief(question: question, shape: .binary, options: options, answer: answer,
                                 insteadOf: insteadOf, why: why, tradeoff: nil)
        }

        return DecisionBrief(question: question, shape: nil, options: [], answer: answer,
                             insteadOf: insteadOf, why: why, tradeoff: nil)
    }

    /// The decision an Overview question is reviewed on — its first related decision, which
    /// is where the Overview's "Review →" goes. Each question belongs to exactly one decision,
    /// so Overview and Decisions show the same question in exactly one place.
    func reviewDecisionId(for item: Consideration) -> String? {
        item.relatedIds.first { decision($0) != nil }
    }

    /// The Overview questions that are reviewed on this decision.
    func overviewQuestions(reviewedOn decisionId: String) -> [Consideration] {
        thingsToThinkAbout.filter { reviewDecisionId(for: $0) == decisionId }
    }

    /// What a decision reaches in the rest of the review graph: the architecture it shapes,
    /// the relationships that embody it, and the flows that pass through it.
    func affects(_ d: DecisionNode) -> (components: [ComponentNode], edges: [ArchitectureEdge], flows: [FlowNode]) {
        let components = d.componentIds.compactMap(component)
        let edges = resolvedEdges.filter { edge in decisions(forEdge: edge).contains { $0.id == d.id } }
        let flows = unique(d.componentIds.flatMap { flows(traversing: $0).map(\.id) }).compactMap(flow)
        return (components, edges, flows)
    }

    /// True when the options already communicate the tradeoff: both of its dimensions are
    /// just option labels or the properties they buy, so a second line would repeat the first.
    static func restates(_ t: DecisionTradeoff, _ options: [DecisionOption]) -> Bool {
        func norm(_ s: String) -> String { s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) }
        let said = Set(options.flatMap { [$0.label] + [$0.detail].compactMap { $0 } }.map(norm))
        return said.contains(norm(t.dimensionA)) && said.contains(norm(t.dimensionB))
    }

    // MARK: - Condensing

    static func condensedWhy(_ statement: Statement) -> Statement {
        var s = statement
        s.text = firstSentence(statement.text)
        return s
    }

    /// First sentence, code locations stripped — a headline, not a report.
    static func firstSentence(_ text: String) -> String {
        splitSentences(stripCodeLocations(text)).first ?? text
    }
}

extension DecisionNode {
    /// The tension that makes this decision worth reviewing, drawn on the decision itself:
    /// the tradeoff marked primary, or the first one when none is.
    var primaryTradeoff: DecisionTradeoff? {
        tradeoffs.first { $0.prominence == .primary } ?? tradeoffs.first
    }

    /// Every tradeoff except the one drawn by default.
    var secondaryTradeoffs: [DecisionTradeoff] {
        guard let primary = primaryTradeoff else { return [] }
        var rest = tradeoffs
        if let i = rest.firstIndex(of: primary) { rest.remove(at: i) }
        return rest
    }

    /// Everything this decision cites: its own evidence plus its tradeoffs'.
    var allRefs: [CodeRef] { unique(refs + tradeoffs.flatMap(\.refs)) }
}
