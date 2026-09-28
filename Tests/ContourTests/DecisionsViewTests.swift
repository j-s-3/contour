import Testing
import SwiftUI
@testable import Contour

/// `DecisionsView.swift` is the single largest gap toward CLAUDE.md's 90% target (issue
/// #119). Per its guidance, this pins the plain grouping/formatting/state-transition logic
/// pulled out of the view into `DecisionsViewLogic`: question reordering, provenance text,
/// keyboard-shortcut dispatch (`keyAction`), the J/K/accept/add-remove selection math that
/// used to live inline in `handleKey`/`step`/`judge`/`setToReview`/`arrive`, and small
/// presentation helpers (`impactsSummary`, `badgeTint`, `tradeoffHelp`,
/// `beforeAfterParts`) — plus the `ReviewerState` extension's symbol/tint/label (already a
/// plain, directly-testable type defined in this file). `framing(toReview:total:)` is
/// already covered by `DecisionsBriefingTests`. What remains untested is the SwiftUI view
/// bodies themselves (cards, drill-downs, the one-at-a-time layout, animations, focus and
/// scroll side effects) — this suite has no UI-testing/snapshot infrastructure to host
/// those, so they're an accepted, irreducible gap.
struct DecisionsViewTests {

    // MARK: - Fixtures

    private func consideration(_ id: String) -> Consideration {
        Consideration(id: id, question: "Q \(id)", detail: "")
    }

    /// A minimal decision with just enough set to exercise ordering/state-transition logic.
    private func decision(_ id: String, state: ReviewerState = .unreviewed) -> DecisionNode {
        DecisionNode(id: id, title: "Decision \(id)",
                     decision: Statement(text: "did \(id)", provenance: .fact),
                     confidence: .medium, reviewerState: state)
    }

    // MARK: - DecisionsViewLogic.questions

    @Test func questionsKeepsTheOriginalOrderWithNoArrival() {
        let all = [consideration("a"), consideration("b"), consideration("c")]
        #expect(DecisionsViewLogic.questions(from: all, leadingWith: nil).map(\.id) == ["a", "b", "c"])
    }

    @Test func questionsMovesTheArrivedFromQuestionToTheFront() {
        let all = [consideration("a"), consideration("b"), consideration("c")]
        #expect(DecisionsViewLogic.questions(from: all, leadingWith: "c").map(\.id) == ["c", "a", "b"])
    }

    @Test func questionsIsUnaffectedWhenTheArrivedFromIdIsntAmongThem() {
        let all = [consideration("a"), consideration("b")]
        #expect(DecisionsViewLogic.questions(from: all, leadingWith: "does-not-exist").map(\.id) == ["a", "b"])
    }

    @Test func questionsOnEmptyInputStaysEmpty() {
        #expect(DecisionsViewLogic.questions(from: [], leadingWith: "x").isEmpty)
    }

    // MARK: - DecisionsViewLogic.provenanceNote / provenanceHelp

    @Test func provenanceNoteNamesEachProvenanceBriefly() {
        #expect(DecisionsViewLogic.provenanceNote(Statement(text: "x", provenance: .claim)) == "Author rationale")
        #expect(DecisionsViewLogic.provenanceNote(Statement(text: "x", provenance: .fact)) == "Observed")
        #expect(DecisionsViewLogic.provenanceNote(Statement(text: "x", provenance: .interpretation)) == "AI inference")
    }

    @Test func provenanceHelpCapitalizesTheFirstLetter() {
        #expect(DecisionsViewLogic.provenanceHelp(Statement(text: "x", provenance: .fact)) == "Observed fact")
        #expect(DecisionsViewLogic.provenanceHelp(Statement(text: "x", provenance: .claim)) == "Author's claim")
    }

    @Test func provenanceHelpAppendsTheConfidenceAndSourceWhenPresent() {
        let s = Statement(text: "x", provenance: .interpretation, confidence: .high, source: "PagePublisher.java:50")
        #expect(DecisionsViewLogic.provenanceHelp(s) == "AI inference, high confidence — PagePublisher.java:50")
    }

    @Test func provenanceHelpOmitsAnEmptySource() {
        let s = Statement(text: "x", provenance: .fact, source: "")
        #expect(DecisionsViewLogic.provenanceHelp(s) == "Observed fact")
    }

    // MARK: - ReviewerState (symbol / tint / chipLabel)

    @Test func everyReviewerStateHasItsOwnSymbol() {
        #expect(ReviewerState.unreviewed.symbol == "circle")
        #expect(ReviewerState.accepted.symbol == "checkmark")
        #expect(ReviewerState.questioned.symbol == "questionmark")
        #expect(ReviewerState.discuss.symbol == "bubble.left.and.bubble.right")
    }

    @Test func everyReviewerStateHasItsOwnChipLabel() {
        #expect(ReviewerState.unreviewed.chipLabel == "Unreviewed")
        #expect(ReviewerState.accepted.chipLabel == "Reviewed")
        #expect(ReviewerState.questioned.chipLabel == "Question")
        #expect(ReviewerState.discuss.chipLabel == "Discussing")
    }

    @Test func everyReviewerStateHasItsOwnTint() {
        #expect(ReviewerState.unreviewed.tint == .secondary)
        #expect(ReviewerState.accepted.tint == .green)
        #expect(ReviewerState.questioned.tint == .orange)
        #expect(ReviewerState.discuss.tint == .blue)
    }

    // MARK: - DecisionsViewLogic.keyAction

    /// Any modifier that isn't Shift takes the keypress away from us, whatever the key.
    @Test func keyActionIgnoresCommandControlOrOptionModifiers() {
        let action = DecisionsViewLogic.keyAction(isArrowDown: false, isArrowUp: false, character: "j",
                                                    modifiersBlockShortcuts: true, noteFieldFocused: false,
                                                    hasSelection: true, selectionIsToReview: true)
        #expect(action == .ignored)
    }

    /// Typing into the reviewer-note field is never a shortcut, even down/up arrow.
    @Test func keyActionIgnoresEverythingWhileTheNoteFieldIsFocused() {
        let action = DecisionsViewLogic.keyAction(isArrowDown: true, isArrowUp: false, character: "",
                                                    modifiersBlockShortcuts: false, noteFieldFocused: true,
                                                    hasSelection: true, selectionIsToReview: true)
        #expect(action == .ignored)
    }

    /// Down/up arrow step even with no selection yet — `stepId` tolerates a nil current id.
    @Test func keyActionStepsOnArrowsWithoutRequiringASelection() {
        #expect(DecisionsViewLogic.keyAction(isArrowDown: true, isArrowUp: false, character: "",
                                              modifiersBlockShortcuts: false, noteFieldFocused: false,
                                              hasSelection: false, selectionIsToReview: false) == .step(1))
        #expect(DecisionsViewLogic.keyAction(isArrowDown: false, isArrowUp: true, character: "",
                                              modifiersBlockShortcuts: false, noteFieldFocused: false,
                                              hasSelection: false, selectionIsToReview: false) == .step(-1))
    }

    /// j/k (unlike the arrow keys) need a selection: they're character shortcuts, gated by
    /// the same `hasSelection` guard as a/q/c/m.
    @Test func keyActionIgnoresJAndKWithNoSelection() {
        #expect(DecisionsViewLogic.keyAction(isArrowDown: false, isArrowUp: false, character: "j",
                                              modifiersBlockShortcuts: false, noteFieldFocused: false,
                                              hasSelection: false, selectionIsToReview: false) == .ignored)
    }

    @Test func keyActionMapsJAndKToStep() {
        #expect(DecisionsViewLogic.keyAction(isArrowDown: false, isArrowUp: false, character: "j",
                                              modifiersBlockShortcuts: false, noteFieldFocused: false,
                                              hasSelection: true, selectionIsToReview: false) == .step(1))
        #expect(DecisionsViewLogic.keyAction(isArrowDown: false, isArrowUp: false, character: "K",
                                              modifiersBlockShortcuts: false, noteFieldFocused: false,
                                              hasSelection: true, selectionIsToReview: false) == .step(-1))
    }

    /// A/Q/C only judge a decision that's actually in Decisions to Review — an Other
    /// Decision must be added to review first.
    @Test func keyActionIgnoresAQAndCWhenTheSelectionIsNotToReview() {
        for key in ["a", "q", "c"] {
            let action = DecisionsViewLogic.keyAction(isArrowDown: false, isArrowUp: false, character: key,
                                                        modifiersBlockShortcuts: false, noteFieldFocused: false,
                                                        hasSelection: true, selectionIsToReview: false)
            #expect(action == .ignored)
        }
    }

    @Test func keyActionMapsAQAndCToTheirJudgment() {
        #expect(DecisionsViewLogic.keyAction(isArrowDown: false, isArrowUp: false, character: "a",
                                              modifiersBlockShortcuts: false, noteFieldFocused: false,
                                              hasSelection: true, selectionIsToReview: true) == .judge(.accepted))
        #expect(DecisionsViewLogic.keyAction(isArrowDown: false, isArrowUp: false, character: "Q",
                                              modifiersBlockShortcuts: false, noteFieldFocused: false,
                                              hasSelection: true, selectionIsToReview: true) == .judge(.questioned))
        #expect(DecisionsViewLogic.keyAction(isArrowDown: false, isArrowUp: false, character: "c",
                                              modifiersBlockShortcuts: false, noteFieldFocused: false,
                                              hasSelection: true, selectionIsToReview: true) == .judge(.discuss))
    }

    /// M and Space both toggle More…/Less — and toggling doesn't require being "to review".
    @Test func keyActionMapsMAndSpaceToToggleExpandedEvenWhenNotToReview() {
        #expect(DecisionsViewLogic.keyAction(isArrowDown: false, isArrowUp: false, character: "m",
                                              modifiersBlockShortcuts: false, noteFieldFocused: false,
                                              hasSelection: true, selectionIsToReview: false) == .toggleExpanded)
        #expect(DecisionsViewLogic.keyAction(isArrowDown: false, isArrowUp: false, character: " ",
                                              modifiersBlockShortcuts: false, noteFieldFocused: false,
                                              hasSelection: true, selectionIsToReview: false) == .toggleExpanded)
    }

    @Test func keyActionIgnoresAnyOtherCharacter() {
        let action = DecisionsViewLogic.keyAction(isArrowDown: false, isArrowUp: false, character: "z",
                                                    modifiersBlockShortcuts: false, noteFieldFocused: false,
                                                    hasSelection: true, selectionIsToReview: true)
        #expect(action == .ignored)
    }

    // MARK: - DecisionsViewLogic.stepId

    @Test func stepIdAdvancesByDeltaClampedToTheEnds() {
        let ids = ["a", "b", "c"]
        #expect(DecisionsViewLogic.stepId(in: ids, currentId: "a", delta: 1) == "b")
        #expect(DecisionsViewLogic.stepId(in: ids, currentId: "c", delta: 1) == "c")
        #expect(DecisionsViewLogic.stepId(in: ids, currentId: "a", delta: -1) == "a")
        #expect(DecisionsViewLogic.stepId(in: ids, currentId: "c", delta: -1) == "b")
    }

    @Test func stepIdDefaultsToTheFirstIdWhenNothingIsCurrentlySelected() {
        #expect(DecisionsViewLogic.stepId(in: ["a", "b"], currentId: nil, delta: 1) == "b")
    }

    @Test func stepIdIsNilWhenThereAreNoIds() {
        #expect(DecisionsViewLogic.stepId(in: [], currentId: nil, delta: 1) == nil)
    }

    @Test func stepIdTreatsAnUnknownCurrentIdAsTheStart() {
        // firstIndex(of:) returns nil for an id not in the list, falling back to index 0.
        #expect(DecisionsViewLogic.stepId(in: ["a", "b"], currentId: "not-there", delta: 1) == "b")
    }

    // MARK: - DecisionsViewLogic.nextAfterAccepting

    @Test func nextAfterAcceptingPrefersTheNextUnreviewedDecision() {
        let sequence = [decision("a", state: .accepted), decision("b", state: .accepted),
                         decision("c", state: .unreviewed), decision("d", state: .unreviewed)]
        #expect(DecisionsViewLogic.nextAfterAccepting(sequence: sequence, decisionId: "a") == "c")
    }

    @Test func nextAfterAcceptingFallsBackToTheNextDecisionWhenNoneAreUnreviewed() {
        let sequence = [decision("a"), decision("b", state: .accepted), decision("c", state: .questioned)]
        #expect(DecisionsViewLogic.nextAfterAccepting(sequence: sequence, decisionId: "a") == "b")
    }

    @Test func nextAfterAcceptingIsNilAtTheEndOfTheSequence() {
        let sequence = [decision("a"), decision("b")]
        #expect(DecisionsViewLogic.nextAfterAccepting(sequence: sequence, decisionId: "b") == nil)
    }

    @Test func nextAfterAcceptingIsNilWhenTheDecisionIsntInTheSequence() {
        #expect(DecisionsViewLogic.nextAfterAccepting(sequence: [decision("a")], decisionId: "missing") == nil)
    }

    // MARK: - DecisionsViewLogic.selectionAfterTogglingReview

    @Test func selectionAfterAddingToReviewSelectsTheDecisionItself() {
        let toReview = [decision("a"), decision("b")]
        #expect(DecisionsViewLogic.selectionAfterTogglingReview(toReview: toReview, decisionId: "c", addingToReview: true) == "c")
    }

    @Test func selectionAfterRemovingFromReviewMovesToTheNextOneToReview() {
        let toReview = [decision("a"), decision("b"), decision("c")]
        #expect(DecisionsViewLogic.selectionAfterTogglingReview(toReview: toReview, decisionId: "a", addingToReview: false) == "b")
    }

    @Test func selectionAfterRemovingTheLastOneToReviewFallsBackToAnyOtherRemaining() {
        // Removing the last item in the list: `drop{...}.dropFirst().first` finds nothing
        // after it, so it falls back to the first remaining decision that isn't this one.
        let toReview = [decision("a"), decision("b"), decision("c")]
        #expect(DecisionsViewLogic.selectionAfterTogglingReview(toReview: toReview, decisionId: "c", addingToReview: false) == "a")
    }

    @Test func selectionAfterRemovingTheOnlyDecisionToReviewIsNil() {
        #expect(DecisionsViewLogic.selectionAfterTogglingReview(toReview: [decision("a")], decisionId: "a", addingToReview: false) == nil)
    }

    // MARK: - DecisionsViewLogic.arrivalSelection

    @Test func arrivalSelectionSelectsAndRevealsOtherWhenTheTargetIsAnOtherDecision() {
        let plan = DecisionsViewLogic.arrivalSelection(decisionId: "x", decisionExists: true, isOtherDecision: true,
                                                         existingSelectedId: nil, fallbackId: "a")
        #expect(plan.selectedId == "x")
        #expect(plan.revealOther)
    }

    @Test func arrivalSelectionSelectsWithoutRevealingWhenTheTargetIsAlreadyInTheList() {
        let plan = DecisionsViewLogic.arrivalSelection(decisionId: "x", decisionExists: true, isOtherDecision: false,
                                                         existingSelectedId: nil, fallbackId: "a")
        #expect(plan.selectedId == "x")
        #expect(!plan.revealOther)
    }

    @Test func arrivalSelectionKeepsTheExistingSelectionWhenNoTargetIsGiven() {
        let plan = DecisionsViewLogic.arrivalSelection(decisionId: nil, decisionExists: false, isOtherDecision: false,
                                                         existingSelectedId: "already-selected", fallbackId: "a")
        #expect(plan.selectedId == "already-selected")
        #expect(!plan.revealOther)
    }

    @Test func arrivalSelectionFallsBackToTheFirstSequenceIdWhenNothingWasSelectedAndTheTargetDoesntExist() {
        let plan = DecisionsViewLogic.arrivalSelection(decisionId: "gone", decisionExists: false, isOtherDecision: false,
                                                         existingSelectedId: nil, fallbackId: "a")
        #expect(plan.selectedId == "a")
        #expect(!plan.revealOther)
    }

    // MARK: - DecisionsViewLogic.impactsSummary / badgeTint / tradeoffHelp / beforeAfterParts

    @Test func impactsSummaryJoinsUpToThreeLabelsWithAMiddleDot() {
        #expect(DecisionsViewLogic.impactsSummary([.security, .performance]) == "security · performance")
        #expect(DecisionsViewLogic.impactsSummary([.dataIntegrity]) == "data integrity")
    }

    @Test func impactsSummaryTakesOnlyTheFirstThree() {
        let all: [DecisionImpact] = [.correctness, .security, .reliability, .performance]
        #expect(DecisionsViewLogic.impactsSummary(all) == "correctness · security · reliability")
    }

    @Test func impactsSummaryOfNoImpactsIsEmpty() {
        #expect(DecisionsViewLogic.impactsSummary([]) == "")
    }

    @Test func badgeTintIsSecondaryOnlyWhenUnreviewed() {
        #expect(DecisionsViewLogic.badgeTint(for: .unreviewed) == .secondary)
        #expect(DecisionsViewLogic.badgeTint(for: .accepted) == ReviewerState.accepted.tint)
        #expect(DecisionsViewLogic.badgeTint(for: .questioned) == ReviewerState.questioned.tint)
        #expect(DecisionsViewLogic.badgeTint(for: .discuss) == ReviewerState.discuss.tint)
    }

    @Test func tradeoffHelpPrefersTheModelsExplanation() {
        let tradeoff = DecisionTradeoff(dimensionA: "speed", dimensionB: "safety", chosenPosition: 1,
                                         explanation: Statement(text: "Chose safety because of X", provenance: .claim))
        #expect(DecisionsViewLogic.tradeoffHelp(tradeoff) == "Chose safety because of X — right-click to ask about it")
    }

    @Test func tradeoffHelpFallsBackToNamingTheChosenSide() {
        let tradeoff = DecisionTradeoff(dimensionA: "speed", dimensionB: "safety", chosenPosition: 1)
        #expect(DecisionsViewLogic.tradeoffHelp(tradeoff) == "Leans toward safety — right-click to ask about it")
    }

    @Test func beforeAfterPartsSplitsOnTheUnicodeArrowAndTrimsWhitespace() {
        #expect(DecisionsViewLogic.beforeAfterParts(from: "Reader → Inspector → Printer")
                == ["Reader", "Inspector", "Printer"])
    }

    /// `>` (an ASCII stand-in for the arrow) splits too.
    @Test func beforeAfterPartsAlsoSplitsOnAGreaterThanSign() {
        #expect(DecisionsViewLogic.beforeAfterParts(from: "Reader>Printer") == ["Reader", "Printer"])
    }

    /// A dash right against the text (no space) is trimmed once whitespace-trimming has
    /// exposed it at the edge of the part.
    @Test func beforeAfterPartsTrimsDashesFlushAgainstTheText() {
        #expect(DecisionsViewLogic.beforeAfterParts(from: "-Reader- → -Printer-") == ["Reader", "Printer"])
    }

    @Test func beforeAfterPartsDropsEmptyPartsFromAdjacentSeparators() {
        #expect(DecisionsViewLogic.beforeAfterParts(from: "A →→ B") == ["A", "B"])
    }

    @Test func beforeAfterPartsOnALabelWithNoSeparatorIsTheWholeLabel() {
        #expect(DecisionsViewLogic.beforeAfterParts(from: "Single stage") == ["Single stage"])
    }

    // MARK: - Layout state (split out of DecisionsView's computed properties and body)

    private func brief(options: [DecisionOption] = [], answer: String = "the answer") -> DecisionBrief {
        DecisionBrief(question: "Q?", shape: nil, options: options, answer: answer, insteadOf: nil, why: nil, tradeoff: nil)
    }

    /// Other Decisions must open by themselves when nothing was proposed for review, else the
    /// lens would show an empty list with the analysis' findings hidden behind a button.
    @Test func otherDecisionsOpenByDefaultOnlyWhenNothingIsToReview() {
        #expect(DecisionsViewLogic.otherShown(showOther: false, toReviewIsEmpty: true))
        #expect(DecisionsViewLogic.otherShown(showOther: true, toReviewIsEmpty: false))
        #expect(!DecisionsViewLogic.otherShown(showOther: false, toReviewIsEmpty: false))
    }

    /// J/K only walks Other Decisions once they're visible, so it never lands on a hidden row.
    @Test func sequenceAppendsOtherDecisionsOnlyOnceShown() {
        let review = [decision("r1"), decision("r2")], other = [decision("o1")]
        #expect(DecisionsViewLogic.sequence(toReview: review, other: other, otherShown: false).map(\.id) == ["r1", "r2"])
        #expect(DecisionsViewLogic.sequence(toReview: review, other: other, otherShown: true).map(\.id) == ["r1", "r2", "o1"])
    }

    @Test func otherToggleTitlePluralizesAndFlipsWhenShown() {
        #expect(DecisionsViewLogic.otherToggleTitle(showOther: true, count: 3) == "Hide lower-impact decisions")
        #expect(DecisionsViewLogic.otherToggleTitle(showOther: false, count: 1) == "Show 1 lower-impact decision")
        #expect(DecisionsViewLogic.otherToggleTitle(showOther: false, count: 4) == "Show 4 lower-impact decisions")
    }

    /// The one-at-a-time footer must disable Previous on the first card and Next on the last,
    /// and offer the hidden Other Decisions only at the very end.
    @Test func oneAtATimeStepDisablesEndsAndOffersOthersAtTheEnd() {
        let first = DecisionsViewLogic.oneAtATimeStep(index: 0, count: 3, otherCount: 2, otherShown: false)
        #expect(first == .init(label: "1 of 3", canGoPrevious: false, canGoNext: true, offersOtherDecisions: false))
        let last = DecisionsViewLogic.oneAtATimeStep(index: 2, count: 3, otherCount: 2, otherShown: false)
        #expect(last == .init(label: "3 of 3", canGoPrevious: true, canGoNext: false, offersOtherDecisions: true))
        #expect(!DecisionsViewLogic.oneAtATimeStep(index: 2, count: 3, otherCount: 2, otherShown: true).offersOtherDecisions)
        #expect(!DecisionsViewLogic.oneAtATimeStep(index: 2, count: 3, otherCount: 0, otherShown: false).offersOtherDecisions)
    }

    // MARK: - Card and row text

    @Test func whyLabelIsPlainWhenNothingAboveItDrewAChoice() {
        #expect(DecisionsViewLogic.whyLabel(hasShape: false, hasTradeoff: false) == "Why")
        #expect(DecisionsViewLogic.whyLabel(hasShape: true, hasTradeoff: false) == "Why this side?")
        #expect(DecisionsViewLogic.whyLabel(hasShape: false, hasTradeoff: true) == "Why this side?")
    }

    /// A questioned decision needs somewhere to write the question; a note already written
    /// must stay visible even if the state was later changed.
    @Test func noteFieldShowsWhenQuestionedOrWhenANoteExists() {
        #expect(DecisionsViewLogic.showsNoteField(state: .questioned, note: ""))
        #expect(DecisionsViewLogic.showsNoteField(state: .accepted, note: "hmm"))
        #expect(!DecisionsViewLogic.showsNoteField(state: .accepted, note: ""))
    }

    @Test func chosenSummaryPrefersTheChosenOptionThenTheAnswer() {
        let withDetail = brief(options: [DecisionOption(label: "A"), DecisionOption(label: "B", detail: "faster", chosen: true)])
        #expect(DecisionsViewLogic.chosenSummary(withDetail) == "B — faster")
        let noDetail = brief(options: [DecisionOption(label: "B", chosen: true)])
        #expect(DecisionsViewLogic.chosenSummary(noDetail) == "B")
        #expect(DecisionsViewLogic.chosenSummary(brief(options: [DecisionOption(label: "A")], answer: "Did X")) == "Did X")
    }

    @Test func reviewButtonHelpOffersClearingOnlyWhenOn() {
        #expect(DecisionsViewLogic.reviewButtonHelp(isOn: false, target: .accepted, title: "Looks good", shortcut: "A")
                == "Looks good (A)")
        #expect(DecisionsViewLogic.reviewButtonHelp(isOn: true, target: .accepted, title: "Looks good", shortcut: "A")
                == "\(ReviewerState.accepted.label) — click to clear (A)")
    }

    /// Discussed-only resolution is green; a recorded judgment wins so the dot matches its card.
    @Test func progressDotFillDistinguishesPendingDiscussedAndJudged() {
        #expect(DecisionsViewLogic.progressDotFill(resolved: false, state: .accepted) == .pending)
        #expect(DecisionsViewLogic.progressDotFill(resolved: true, state: .unreviewed) == .discussed)
        #expect(DecisionsViewLogic.progressDotFill(resolved: true, state: .questioned) == .judged(.questioned))
    }

    // MARK: - Drill-down text

    @Test func drillDownTextHelpersFormatCountsEdgesAndFooter() {
        #expect(DecisionsViewLogic.tradeoffsTitle(count: 1) == "What it traded")
        #expect(DecisionsViewLogic.tradeoffsTitle(count: 3) == "What it traded (3)")
        #expect(DecisionsViewLogic.edgeTitle(from: "A", to: "B") == "A → B")
        #expect(DecisionsViewLogic.drillDownFooter(level: "Design", confidence: "High")
                == "Design-level choice · analysis confidence high")
    }

    // MARK: - Spectrum and choice geometry

    /// The 0.5 midpoint counts as the second dimension, matching the emphasized label and knob.
    @Test func spectrumFavorsTheSecondDimensionFromTheMidpointUp() {
        #expect(!DecisionsViewLogic.favorsSecondDimension(0.49))
        #expect(DecisionsViewLogic.favorsSecondDimension(0.5))
    }

    /// The knob travels from the 6pt inset at 0 to the far end (minus its own margin) at 1.
    @Test func knobOffsetSpansTheTrack() {
        #expect(DecisionsViewLogic.knobOffset(trackWidth: 150, position: 0) == 6)
        #expect(DecisionsViewLogic.knobOffset(trackWidth: 150, position: 1) == 134)
        #expect(DecisionsViewLogic.knobOffset(trackWidth: 150, position: 0.5) == 70)
    }

    @Test func connectorHidesTheOuterHalvesOfTheFirstAndLastOption() {
        #expect(DecisionsViewLogic.connectorOpacities(index: 0, count: 3) == (0, 0.3))
        #expect(DecisionsViewLogic.connectorOpacities(index: 1, count: 3) == (0.3, 0.3))
        #expect(DecisionsViewLogic.connectorOpacities(index: 2, count: 3) == (0.3, 0))
    }

    @Test func labelAlignmentRightAlignsOnlyTheSecondLeadingLabel() {
        #expect(DecisionsViewLogic.labelAlignment(.leading, index: 1) == .trailing)
        #expect(DecisionsViewLogic.labelAlignment(.leading, index: 0) == .leading)
        #expect(DecisionsViewLogic.labelAlignment(.center, index: 1) == .center)
    }
}
