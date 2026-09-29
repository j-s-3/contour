import Foundation

struct DecisionBrief: Hashable {
    var question: String
    var shape: DecisionShape?
    var options: [DecisionOption]
    var answer: String
    var insteadOf: String?
    var why: Statement?
    var tradeoff: DecisionTradeoff?

    var chosen: DecisionOption? { options.first { $0.chosen } }
}

extension PRGraph {
    var decisionsToReview: [DecisionNode] {
        let proposed = decisions.filter { $0.reviewerPlacement == nil && significance(of: $0) == .high }
        let added = decisions.filter { $0.reviewerPlacement == .review }
        return proposed + added
    }

    var otherDecisions: [DecisionNode] {
        let review = Set(decisionsToReview.map(\.id))
        return decisions
            .filter { !review.contains($0.id) }
            .sorted { significance(of: $0) > significance(of: $1) }
    }

    func isToReview(_ d: DecisionNode) -> Bool {
        d.reviewerPlacement.map { $0 == .review } ?? (significance(of: d) == .high)
    }

    mutating func setToReview(_ toReview: Bool, forDecision id: String) {
        guard let i = decisions.firstIndex(where: { $0.id == id }) else { return }
        let proposed = significance(of: decisions[i]) == .high
        decisions[i].reviewerPlacement = toReview == proposed ? nil : (toReview ? .review : .other)
    }

    func significance(of d: DecisionNode) -> ReviewSignificance {
        let base = d.significance ?? Self.inferredSignificance(d)
        return overviewQuestions(reviewedOn: d.id).isEmpty ? base : base.raised
    }

    static let substantialLean = 0.25

    static func inferredSignificance(_ d: DecisionNode) -> ReviewSignificance {
        guard let tradeoff = d.primaryTradeoff else { return .low }
        return abs(tradeoff.chosenPosition - 0.5) >= substantialLean ? .high : .medium
    }

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

    func reviewDecisionId(for item: Consideration) -> String? {
        item.relatedIds.first { decision($0) != nil }
    }

    func overviewQuestions(reviewedOn decisionId: String) -> [Consideration] {
        thingsToThinkAbout.filter { reviewDecisionId(for: $0) == decisionId }
    }

    func affects(_ d: DecisionNode) -> (components: [ComponentNode], edges: [ArchitectureEdge], flows: [FlowNode]) {
        let components = d.componentIds.compactMap(component)
        let edges = resolvedEdges.filter { edge in decisions(forEdge: edge).contains { $0.id == d.id } }
        let pinned = flowAppearances(ofDecision: d.id).map(\.flow.id)
        let flows = unique(pinned + d.componentIds.flatMap { flows(traversing: $0).map(\.id) }).compactMap(flow)
        return (components, edges, flows)
    }

    static func restates(_ t: DecisionTradeoff, _ options: [DecisionOption]) -> Bool {
        func norm(_ s: String) -> String { s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) }
        let said = Set(options.flatMap { [$0.label] + [$0.detail].compactMap { $0 } }.map(norm))
        return said.contains(norm(t.dimensionA)) && said.contains(norm(t.dimensionB))
    }

    static func condensedWhy(_ statement: Statement) -> Statement {
        var s = statement
        s.text = firstSentence(statement.text)
        return s
    }

    static func firstSentence(_ text: String) -> String {
        splitSentences(stripCodeLocations(text)).first ?? text
    }
}

extension DecisionNode {
    var primaryTradeoff: DecisionTradeoff? {
        tradeoffs.first { $0.prominence == .primary } ?? tradeoffs.first
    }

    var secondaryTradeoffs: [DecisionTradeoff] {
        guard let primary = primaryTradeoff else { return [] }
        var rest = tradeoffs
        if let i = rest.firstIndex(of: primary) { rest.remove(at: i) }
        return rest
    }

    var allRefs: [CodeRef] { unique(refs + tradeoffs.flatMap(\.refs)) }
}
