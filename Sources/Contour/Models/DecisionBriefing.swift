import Foundation

/// A decision as the Decisions lens draws it by default: the question, the options with the
/// chosen one marked, a short why, and the tradeoff the choice made. Everything else on
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
    /// The tradeoff drawn under the choice. Nil when the options were themselves derived
    /// from the tradeoff's poles, so the same axis isn't drawn twice.
    var tradeoff: TradeoffNode?

    var chosen: DecisionOption? { options.first { $0.chosen } }
}

/// The Decisions model, resolved from whatever the graph has.
///
/// New analyses carry `question`/`options`/`why` written to a budget by the decisions stage.
/// Older cached graphs (and the captured mock fixtures) only have the verbose record, so
/// it is condensed here instead — the same approach as `thingsToThinkAbout`: the tradeoff's
/// two poles stand in for the options, and the first rationale sentence, code locations
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
        let tradeoff = tradeoffs(for: d.id).first
        let why = d.why ?? d.rationale.first.map(Self.condensedWhy)
        let answer = Self.firstSentence(d.decision.text)
        let insteadOf = d.alternatives.first.map { Self.firstSentence($0.text) }
        let question = d.question.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 } ?? d.title

        let explicit = d.options.filter { !$0.label.trimmingCharacters(in: .whitespaces).isEmpty }
        if explicit.count >= 2, explicit.contains(where: \.chosen) {
            // A "binary" choice with three options is really a list; anything else the model
            // picked is honored.
            let shape: DecisionShape
            switch d.shape {
            case .threshold?: shape = .threshold
            case .options?: shape = .options
            default: shape = explicit.count == 2 ? .binary : .options
            }
            return DecisionBrief(question: question, shape: shape, options: explicit, answer: answer,
                                 insteadOf: insteadOf, why: why, tradeoff: tradeoff)
        }

        if let tradeoff {
            let leansB = tradeoff.poleAWeight >= 0.5
            let options = [
                DecisionOption(label: tradeoff.poleA, chosen: !leansB),
                DecisionOption(label: tradeoff.poleB, chosen: leansB)
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
