import Testing
import SwiftUI
@testable import Contour

struct DecisionsViewTests {
    private func consideration(_ id: String) -> Consideration {
        Consideration(id: id, question: "Q \(id)", detail: "")
    }

    private func decision(_ id: String, state: ReviewerState = .unreviewed) -> DecisionNode {
        DecisionNode(id: id, title: "Decision \(id)",
                     decision: Statement(text: "did \(id)", provenance: .fact),
                     confidence: .medium, reviewerState: state)
    }

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

    @Test func keyActionIgnoresCommandControlOrOptionModifiers() {
        let action = DecisionsViewLogic.keyAction(isArrowDown: false, isArrowUp: false, character: "j",
                                                    modifiersBlockShortcuts: true, noteFieldFocused: false,
                                                    hasSelection: true, selectionIsToReview: true)
        #expect(action == .ignored)
    }

    @Test func keyActionIgnoresEverythingWhileTheNoteFieldIsFocused() {
        let action = DecisionsViewLogic.keyAction(isArrowDown: true, isArrowUp: false, character: "",
                                                    modifiersBlockShortcuts: false, noteFieldFocused: true,
                                                    hasSelection: true, selectionIsToReview: true)
        #expect(action == .ignored)
    }

    @Test func keyActionStepsOnArrowsWithoutRequiringASelection() {
        #expect(DecisionsViewLogic.keyAction(isArrowDown: true, isArrowUp: false, character: "",
                                              modifiersBlockShortcuts: false, noteFieldFocused: false,
                                              hasSelection: false, selectionIsToReview: false) == .step(1))
        #expect(DecisionsViewLogic.keyAction(isArrowDown: false, isArrowUp: true, character: "",
                                              modifiersBlockShortcuts: false, noteFieldFocused: false,
                                              hasSelection: false, selectionIsToReview: false) == .step(-1))
    }

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
        #expect(DecisionsViewLogic.stepId(in: ["a", "b"], currentId: "not-there", delta: 1) == "b")
    }

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

    @Test func selectionAfterAddingToReviewSelectsTheDecisionItself() {
        let toReview = [decision("a"), decision("b")]
        #expect(DecisionsViewLogic.selectionAfterTogglingReview(toReview: toReview, decisionId: "c", addingToReview: true) == "c")
    }

    @Test func selectionAfterRemovingFromReviewMovesToTheNextOneToReview() {
        let toReview = [decision("a"), decision("b"), decision("c")]
        #expect(DecisionsViewLogic.selectionAfterTogglingReview(toReview: toReview, decisionId: "a", addingToReview: false) == "b")
    }

    @Test func selectionAfterRemovingTheLastOneToReviewFallsBackToAnyOtherRemaining() {
        let toReview = [decision("a"), decision("b"), decision("c")]
        #expect(DecisionsViewLogic.selectionAfterTogglingReview(toReview: toReview, decisionId: "c", addingToReview: false) == "a")
    }

    @Test func selectionAfterRemovingTheOnlyDecisionToReviewIsNil() {
        #expect(DecisionsViewLogic.selectionAfterTogglingReview(toReview: [decision("a")], decisionId: "a", addingToReview: false) == nil)
    }

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

    @Test func beforeAfterPartsAlsoSplitsOnAGreaterThanSign() {
        #expect(DecisionsViewLogic.beforeAfterParts(from: "Reader>Printer") == ["Reader", "Printer"])
    }

    @Test func beforeAfterPartsTrimsDashesFlushAgainstTheText() {
        #expect(DecisionsViewLogic.beforeAfterParts(from: "-Reader- → -Printer-") == ["Reader", "Printer"])
    }

    @Test func beforeAfterPartsDropsEmptyPartsFromAdjacentSeparators() {
        #expect(DecisionsViewLogic.beforeAfterParts(from: "A →→ B") == ["A", "B"])
    }

    @Test func beforeAfterPartsOnALabelWithNoSeparatorIsTheWholeLabel() {
        #expect(DecisionsViewLogic.beforeAfterParts(from: "Single stage") == ["Single stage"])
    }
}
