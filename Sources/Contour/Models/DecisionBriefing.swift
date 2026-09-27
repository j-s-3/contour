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

    // MARK: - Where the reviewer's attention goes

    /// The decisions worth the reviewer's conscious judgment, most significant first — shown
    /// by default, with judgment buttons. Significance decides this, never abstraction
    /// level: an implementation choice about failure semantics belongs here, a
    /// component-ownership choice with no behavioral consequence doesn't. The reviewer's own
    /// placement overrides the analysis; decisions they added come last.
    var decisionsToReview: [DecisionNode] {
        let proposed = decisions.filter { $0.reviewerPlacement == nil && significance(of: $0) == .high }
        let added = decisions.filter { $0.reviewerPlacement == .review }
        return proposed + added
    }

    /// Everything else the analysis found: still inspectable, askable and promotable, but
    /// collapsed so it never competes for attention.
    var otherDecisions: [DecisionNode] {
        let review = Set(decisionsToReview.map(\.id))
        return decisions
            .filter { !review.contains($0.id) }
            .sorted { significance(of: $0) > significance(of: $1) }
    }

    func isToReview(_ d: DecisionNode) -> Bool {
        d.reviewerPlacement.map { $0 == .review } ?? (significance(of: d) == .high)
    }

    /// Moves a decision into or out of Decisions to Review. Moving it back to where the
    /// analysis put it clears the override rather than recording a redundant one.
    mutating func setToReview(_ toReview: Bool, forDecision id: String) {
        guard let i = decisions.firstIndex(where: { $0.id == id }) else { return }
        let proposed = significance(of: decisions[i]) == .high
        decisions[i].reviewerPlacement = toReview == proposed ? nil : (toReview ? .review : .other)
    }

    /// How much a decision deserves the reviewer's judgment, from every signal available.
    ///
    /// The decisions stage assesses it directly. Graphs from before that assessment infer it
    /// from the decision's primary tradeoff: a choice that moves substantially toward one side
    /// of a real tension is likely consequential, one with no tradeoff likely isn't. Either
    /// way, an Overview question reviewed on the decision raises it a step — the Overview
    /// asking about a choice is strong evidence it deserves attention — without making every
    /// decision it mentions a review item.
    func significance(of d: DecisionNode) -> ReviewSignificance {
        let base = d.significance ?? Self.inferredSignificance(d)
        return overviewQuestions(reviewedOn: d.id).isEmpty ? base : base.raised
    }

    /// Where a tradeoff's chosen position must be, at least, from the middle for the choice to
    /// count as a substantial move toward one side.
    static let substantialLean = 0.25

    static func inferredSignificance(_ d: DecisionNode) -> ReviewSignificance {
        guard let tradeoff = d.primaryTradeoff else { return .low }
        return abs(tradeoff.chosenPosition - 0.5) >= substantialLean ? .high : .medium
    }

    /// Why a decision is where it is, in a sentence — "why this is highlighted" for a decision
    /// to review, "why it's here" for the rest. The analysis's own reason when it gave one.
    func attentionReason(for d: DecisionNode) -> String {
        if let reason = d.significanceReason { return reason }
        let asked = !overviewQuestions(reviewedOn: d.id).isEmpty
        let tradeoff = d.primaryTradeoff
        let leans = tradeoff.map { abs($0.chosenPosition - 0.5) >= Self.substantialLean } ?? false
        if isToReview(d) {
            if let tradeoff, leans {
                return "Leans hard toward \(tradeoff.chosenDimension) at the cost of \(tradeoff.otherDimension)"
                    + (asked ? ", and the Overview asks about it." : ".")
            }
            return asked ? "The Overview raises a question about it." : "No specific consequence was identified."
        }
        if asked { return "The Overview asks about it, but no substantial tradeoff was identified." }
        if tradeoff != nil { return "A modest tradeoff with limited downstream consequence." }
        return "No material tradeoff or consequence identified."
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
        // Flows the decision is pinned in first, then flows through the components it shapes.
        let pinned = flowAppearances(ofDecision: d.id).map(\.flow.id)
        let flows = unique(pinned + d.componentIds.flatMap { flows(traversing: $0).map(\.id) }).compactMap(flow)
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
