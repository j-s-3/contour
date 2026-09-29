import SwiftUI

enum DecisionsViewLogic {
    static func questions(from all: [Consideration], leadingWith arrivedFromConsiderationId: String?) -> [Consideration] {
        guard let lead = arrivedFromConsiderationId, let item = all.first(where: { $0.id == lead }) else { return all }
        return [item] + all.filter { $0.id != lead }
    }

    nonisolated static func provenanceNote(_ s: Statement) -> String {
        switch s.provenance {
        case .claim: return "Author rationale"
        case .fact: return "Observed"
        case .interpretation: return "AI inference"
        }
    }

    static func provenanceHelp(_ s: Statement) -> String {
        var text = PRGraph.provenanceLabel(s.provenance, s.confidence)
        if let source = s.source, !source.isEmpty { text += " — \(source)" }
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    enum KeyAction: Equatable {
        case step(Int)
        case judge(ReviewerState)
        case toggleExpanded
        case ignored
    }

    nonisolated static func keyAction(isArrowDown: Bool, isArrowUp: Bool, character: String,
                                       modifiersBlockShortcuts: Bool, noteFieldFocused: Bool,
                                       hasSelection: Bool, selectionIsToReview: Bool) -> KeyAction {
        guard !noteFieldFocused, !modifiersBlockShortcuts else { return .ignored }
        if isArrowDown { return .step(1) }
        if isArrowUp { return .step(-1) }
        guard hasSelection else { return .ignored }
        let key = character.lowercased()
        if ["a", "q", "c"].contains(key), !selectionIsToReview { return .ignored }
        switch key {
        case "j": return .step(1)
        case "k": return .step(-1)
        case "a": return .judge(.accepted)
        case "q": return .judge(.questioned)
        case "c": return .judge(.discuss)
        case "m", " ": return .toggleExpanded
        default: return .ignored
        }
    }

    nonisolated static func stepId(in ids: [String], currentId: String?, delta: Int) -> String? {
        guard !ids.isEmpty else { return nil }
        let current = currentId.flatMap { ids.firstIndex(of: $0) } ?? 0
        let next = min(max(current + delta, 0), ids.count - 1)
        return ids[next]
    }

    nonisolated static func nextAfterAccepting(sequence: [DecisionNode], decisionId: String) -> String? {
        guard let at = sequence.firstIndex(where: { $0.id == decisionId }) else { return nil }
        let after = sequence[sequence.index(after: at)...]
        return (after.first { $0.reviewerState == .unreviewed } ?? after.first)?.id
    }

    nonisolated static func selectionAfterTogglingReview(toReview: [DecisionNode], decisionId: String,
                                                          addingToReview: Bool) -> String? {
        guard !addingToReview else { return decisionId }
        let next = toReview.drop { $0.id != decisionId }.dropFirst().first
        return (next ?? toReview.first { $0.id != decisionId })?.id
    }

    nonisolated static func arrivalSelection(decisionId: String?, decisionExists: Bool, isOtherDecision: Bool,
                                              existingSelectedId: String?, fallbackId: String?)
        -> (selectedId: String?, revealOther: Bool) {
        guard let id = decisionId, decisionExists else {
            return (existingSelectedId ?? fallbackId, false)
        }
        return (id, isOtherDecision)
    }

    nonisolated static func otherShown(showOther: Bool, toReviewIsEmpty: Bool) -> Bool {
        showOther || toReviewIsEmpty
    }

    nonisolated static func sequence(toReview: [DecisionNode], other: [DecisionNode], otherShown: Bool) -> [DecisionNode] {
        toReview + (otherShown ? other : [])
    }

    nonisolated static func otherToggleTitle(showOther: Bool, count: Int) -> String {
        if showOther { return "Hide lower-impact decisions" }
        return count == 1 ? "Show 1 lower-impact decision" : "Show \(count) lower-impact decisions"
    }

    struct OneAtATimeStep: Equatable {
        var label: String
        var canGoPrevious: Bool
        var canGoNext: Bool
        var offersOtherDecisions: Bool
    }

    nonisolated static func oneAtATimeStep(index: Int, count: Int, otherCount: Int, otherShown: Bool) -> OneAtATimeStep {
        let last = index == count - 1
        return OneAtATimeStep(label: "\(index + 1) of \(count)",
                              canGoPrevious: index > 0,
                              canGoNext: !last,
                              offersOtherDecisions: otherCount > 0 && !otherShown && last)
    }

    nonisolated static func whyLabel(hasShape: Bool, hasTradeoff: Bool) -> String {
        !hasShape && !hasTradeoff ? "Why" : "Why this side?"
    }

    nonisolated static func showsNoteField(state: ReviewerState, note: String) -> Bool {
        state == .questioned || !note.isEmpty
    }

    nonisolated static func chosenSummary(_ brief: DecisionBrief) -> String {
        guard let chosen = brief.chosen else { return brief.answer }
        return chosen.label + (chosen.detail.map { " — \($0)" } ?? "")
    }

    nonisolated static func reviewButtonHelp(isOn: Bool, target: ReviewerState, title: String, shortcut: String) -> String {
        isOn ? "\(target.label) — click to clear (\(shortcut))" : "\(title) (\(shortcut))"
    }

    enum DotFill: Equatable {
        case pending
        case discussed
        case judged(ReviewerState)
    }

    nonisolated static func progressDotFill(resolved: Bool, state: ReviewerState) -> DotFill {
        if !resolved { return .pending }
        return state == .unreviewed ? .discussed : .judged(state)
    }

    nonisolated static func tradeoffsTitle(count: Int) -> String {
        count == 1 ? "What it traded" : "What it traded (\(count))"
    }

    nonisolated static func edgeTitle(from: String, to: String) -> String { "\(from) → \(to)" }

    nonisolated static func drillDownFooter(level: String, confidence: String) -> String {
        "\(level)-level choice · analysis confidence \(confidence.lowercased())"
    }

    nonisolated static func favorsSecondDimension(_ position: Double) -> Bool { position >= 0.5 }

    nonisolated static func knobOffset(trackWidth: Double, position: Double) -> Double {
        6 + (trackWidth - 22) * position
    }

    nonisolated static func connectorOpacities(index: Int, count: Int) -> (leading: Double, trailing: Double) {
        (index == 0 ? 0 : 0.3, index == count - 1 ? 0 : 0.3)
    }

    nonisolated static func labelAlignment(_ alignment: TextAlignment, index: Int) -> TextAlignment {
        alignment == .leading && index == 1 ? .trailing : alignment
    }

    nonisolated static func impactsSummary(_ impacts: [DecisionImpact]) -> String {
        impacts.prefix(3).map(\.label).joined(separator: " · ")
    }

    nonisolated static func badgeTint(for state: ReviewerState) -> Color {
        state == .unreviewed ? .secondary : state.tint
    }

    nonisolated static func tradeoffHelp(_ tradeoff: DecisionTradeoff) -> String {
        (tradeoff.explanation?.text ?? "Leans toward \(tradeoff.chosenDimension)") + " — right-click to ask about it"
    }

    nonisolated static func beforeAfterParts(from label: String) -> [String] {
        label.components(separatedBy: CharacterSet(charactersIn: "→>"))
            .map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "-")) }
            .filter { !$0.isEmpty }
    }
}
