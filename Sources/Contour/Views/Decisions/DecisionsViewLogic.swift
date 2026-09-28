import SwiftUI

/// Pure grouping/ordering logic pulled out of this file's views (per CLAUDE.md's guidance)
/// so it's directly testable without a live view.
enum DecisionsViewLogic {
    /// Reorders a decision's Overview questions so the one the reviewer arrived from leads,
    /// leaving the rest in their original order.
    static func questions(from all: [Consideration], leadingWith arrivedFromConsiderationId: String?) -> [Consideration] {
        guard let lead = arrivedFromConsiderationId, let item = all.first(where: { $0.id == lead }) else { return all }
        return [item] + all.filter { $0.id != lead }
    }

    /// Provenance is metadata: a quiet note after the why, not a badge in front of it.
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

    // MARK: - Keyboard shortcuts

    /// What a keypress in the Decisions lens should do, decided from plain inputs rather than
    /// `KeyPress` itself so it's directly testable. Mirrors `DecisionsView.handleKey`.
    enum KeyAction: Equatable {
        case step(Int)
        case judge(ReviewerState)
        case toggleExpanded
        case ignored
    }

    /// - Parameters:
    ///   - isArrowDown/isArrowUp: the two keys handled before any selection is required.
    ///   - character: the pressed key's characters, lowercased by the caller for j/k/a/q/c/m.
    ///   - modifiersBlockShortcuts: true when Command/Control/Option was held — never ours.
    ///   - noteFieldFocused: a reviewer note field has focus, so typing isn't a shortcut.
    ///   - hasSelection: a decision is currently selected.
    ///   - selectionIsToReview: the selected decision is one being reviewed — A/Q/C only ever
    ///     judge those; an Other Decision must be added to review first.
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

    // MARK: - Navigation / selection math

    /// Where `step(_:)` moves: `delta` positions from `currentId` in `ids`, clamped to the
    /// ends. Nil when there's nothing to select.
    nonisolated static func stepId(in ids: [String], currentId: String?, delta: Int) -> String? {
        guard !ids.isEmpty else { return nil }
        let current = currentId.flatMap { ids.firstIndex(of: $0) } ?? 0
        let next = min(max(current + delta, 0), ids.count - 1)
        return ids[next]
    }

    /// After accepting a decision, the review moves on: the next still-`unreviewed` decision
    /// after it in the sequence, or failing that the next one at all, or nil past the end.
    nonisolated static func nextAfterAccepting(sequence: [DecisionNode], decisionId: String) -> String? {
        guard let at = sequence.firstIndex(where: { $0.id == decisionId }) else { return nil }
        let after = sequence[sequence.index(after: at)...]
        return (after.first { $0.reviewerState == .unreviewed } ?? after.first)?.id
    }

    /// Where selection lands after toggling a decision's review placement: itself when added,
    /// or the next decision still to review (falling back to any other one) when removed.
    nonisolated static func selectionAfterTogglingReview(toReview: [DecisionNode], decisionId: String,
                                                          addingToReview: Bool) -> String? {
        guard !addingToReview else { return decisionId }
        let next = toReview.drop { $0.id != decisionId }.dropFirst().first
        return (next ?? toReview.first { $0.id != decisionId })?.id
    }

    /// What `arrive(_:)` should do with navigation's requested decision: reveal Other
    /// Decisions and select it when it exists, otherwise leave the current selection alone
    /// (defaulting it only when nothing was selected yet).
    nonisolated static func arrivalSelection(decisionId: String?, decisionExists: Bool, isOtherDecision: Bool,
                                              existingSelectedId: String?, fallbackId: String?)
        -> (selectedId: String?, revealOther: Bool) {
        guard let id = decisionId, decisionExists else {
            return (existingSelectedId ?? fallbackId, false)
        }
        return (id, isOtherDecision)
    }

    // MARK: - Layout state

    /// Other Decisions open by default only when nothing was proposed for review.
    nonisolated static func otherShown(showOther: Bool, toReviewIsEmpty: Bool) -> Bool {
        showOther || toReviewIsEmpty
    }

    /// The review sequence J/K walks: decisions to review, then other decisions once shown.
    nonisolated static func sequence(toReview: [DecisionNode], other: [DecisionNode], otherShown: Bool) -> [DecisionNode] {
        toReview + (otherShown ? other : [])
    }

    /// The disclosure button under "OTHER DECISIONS".
    nonisolated static func otherToggleTitle(showOther: Bool, count: Int) -> String {
        if showOther { return "Hide lower-impact decisions" }
        return count == 1 ? "Show 1 lower-impact decision" : "Show \(count) lower-impact decisions"
    }

    /// The one-at-a-time footer: where the reviewer is in the sequence and which controls apply.
    struct OneAtATimeStep: Equatable {
        var label: String
        var canGoPrevious: Bool
        var canGoNext: Bool
        /// At the end of the sequence with Other Decisions still hidden: offer to open them.
        var offersOtherDecisions: Bool
    }

    nonisolated static func oneAtATimeStep(index: Int, count: Int, otherCount: Int, otherShown: Bool) -> OneAtATimeStep {
        let last = index == count - 1
        return OneAtATimeStep(label: "\(index + 1) of \(count)",
                              canGoPrevious: index > 0,
                              canGoNext: !last,
                              offersOtherDecisions: otherCount > 0 && !otherShown && last)
    }

    // MARK: - Card and row text

    /// The label on a card's reasoning row: plain "Why" when nothing above it drew a choice.
    nonisolated static func whyLabel(hasShape: Bool, hasTradeoff: Bool) -> String {
        !hasShape && !hasTradeoff ? "Why" : "Why this side?"
    }

    /// The note field is there once a decision is questioned, or once it holds a note.
    nonisolated static func showsNoteField(state: ReviewerState, note: String) -> Bool {
        state == .questioned || !note.isEmpty
    }

    /// An Other Decision row's "Chosen" line: the chosen option and its detail, else the answer.
    nonisolated static func chosenSummary(_ brief: DecisionBrief) -> String {
        guard let chosen = brief.chosen else { return brief.answer }
        return chosen.label + (chosen.detail.map { " — \($0)" } ?? "")
    }

    /// Tooltip on a Looks good / Question / Discuss button.
    nonisolated static func reviewButtonHelp(isOn: Bool, target: ReviewerState, title: String, shortcut: String) -> String {
        isOn ? "\(target.label) — click to clear (\(shortcut))" : "\(title) (\(shortcut))"
    }

    /// What a progress dot is drawn as.
    enum DotFill: Equatable {
        case pending
        /// Resolved by discussing it, with no judgment recorded on its decision.
        case discussed
        case judged(ReviewerState)
    }

    nonisolated static func progressDotFill(resolved: Bool, state: ReviewerState) -> DotFill {
        if !resolved { return .pending }
        return state == .unreviewed ? .discussed : .judged(state)
    }

    // MARK: - Drill-down text

    nonisolated static func tradeoffsTitle(count: Int) -> String {
        count == 1 ? "What it traded" : "What it traded (\(count))"
    }

    nonisolated static func edgeTitle(from: String, to: String) -> String { "\(from) → \(to)" }

    nonisolated static func drillDownFooter(level: String, confidence: String) -> String {
        "\(level)-level choice · analysis confidence \(confidence.lowercased())"
    }

    // MARK: - Tradeoff spectrum geometry

    /// Whether the chosen side is dimension B (the emphasized label and the knob's half).
    nonisolated static func favorsSecondDimension(_ position: Double) -> Bool { position >= 0.5 }

    /// The knob's x offset along a track of `width`: 6pt inset, 22pt of knob and arrow margin.
    nonisolated static func knobOffset(trackWidth: Double, position: Double) -> Double {
        6 + (trackWidth - 22) * position
    }

    // MARK: - Choice drawing

    /// Opacity of the two halves of a threshold option's connector: the first option has no
    /// line on its left, the last none on its right.
    nonisolated static func connectorOpacities(index: Int, count: Int) -> (leading: Double, trailing: Double) {
        (index == 0 ? 0 : 0.3, index == count - 1 ? 0 : 0.3)
    }

    /// Text alignment for a binary option's label: the second one hugs the right edge.
    nonisolated static func labelAlignment(_ alignment: TextAlignment, index: Int) -> TextAlignment {
        alignment == .leading && index == 1 ? .trailing : alignment
    }

    // MARK: - Presentation

    /// The impacts line under a decision's question — its top few, joined for one glance.
    nonisolated static func impactsSummary(_ impacts: [DecisionImpact]) -> String {
        impacts.prefix(3).map(\.label).joined(separator: " · ")
    }

    /// The tint behind a decision's numbered badge: neutral until it's judged.
    nonisolated static func badgeTint(for state: ReviewerState) -> Color {
        state == .unreviewed ? .secondary : state.tint
    }

    /// `TradeoffSpectrum`'s tooltip: the model's own explanation, or a plain fallback naming
    /// which side the choice leans toward.
    nonisolated static func tradeoffHelp(_ tradeoff: DecisionTradeoff) -> String {
        (tradeoff.explanation?.text ?? "Leans toward \(tradeoff.chosenDimension)") + " — right-click to ask about it"
    }

    /// Splits a before/after option's label ("Reader → Printer") on any `→` or `>` into its
    /// chain of parts, trimming surrounding whitespace and stray leading/trailing dashes
    /// from each one, and dropping empties left by adjacent separators.
    nonisolated static func beforeAfterParts(from label: String) -> [String] {
        label.components(separatedBy: CharacterSet(charactersIn: "→>"))
            .map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "-")) }
            .filter { !$0.isEmpty }
    }
}
