import SwiftUI
import Testing

@testable import Contour

struct DecisionsViewTests {
    private func consideration(_ id: String) -> Consideration {
        Consideration(id: id, headline: "Q \(id)", impact: "")
    }

    private func decision(_ id: String, state: ReviewerState = .unreviewed) -> DecisionNode {
        DecisionNode(
            id: id, title: "Decision \(id)",
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
        let action = DecisionsViewLogic.keyAction(
            isArrowDown: false, isArrowUp: false, character: "j",
            modifiersBlockShortcuts: true, noteFieldFocused: false,
            hasSelection: true, selectionIsToReview: true)
        #expect(action == .ignored)
    }

    @Test func keyActionIgnoresEverythingWhileTheNoteFieldIsFocused() {
        let action = DecisionsViewLogic.keyAction(
            isArrowDown: true, isArrowUp: false, character: "",
            modifiersBlockShortcuts: false, noteFieldFocused: true,
            hasSelection: true, selectionIsToReview: true)
        #expect(action == .ignored)
    }

    @Test func keyActionStepsOnArrowsWithoutRequiringASelection() {
        #expect(
            DecisionsViewLogic.keyAction(
                isArrowDown: true, isArrowUp: false, character: "",
                modifiersBlockShortcuts: false, noteFieldFocused: false,
                hasSelection: false, selectionIsToReview: false) == .step(1))
        #expect(
            DecisionsViewLogic.keyAction(
                isArrowDown: false, isArrowUp: true, character: "",
                modifiersBlockShortcuts: false, noteFieldFocused: false,
                hasSelection: false, selectionIsToReview: false) == .step(-1))
    }

    @Test func keyActionIgnoresJAndKWithNoSelection() {
        #expect(
            DecisionsViewLogic.keyAction(
                isArrowDown: false, isArrowUp: false, character: "j",
                modifiersBlockShortcuts: false, noteFieldFocused: false,
                hasSelection: false, selectionIsToReview: false) == .ignored)
    }

    @Test func keyActionMapsJAndKToStep() {
        #expect(
            DecisionsViewLogic.keyAction(
                isArrowDown: false, isArrowUp: false, character: "j",
                modifiersBlockShortcuts: false, noteFieldFocused: false,
                hasSelection: true, selectionIsToReview: false) == .step(1))
        #expect(
            DecisionsViewLogic.keyAction(
                isArrowDown: false, isArrowUp: false, character: "K",
                modifiersBlockShortcuts: false, noteFieldFocused: false,
                hasSelection: true, selectionIsToReview: false) == .step(-1))
    }

    @Test func keyActionIgnoresAQAndCWhenTheSelectionIsNotToReview() {
        for key in ["a", "q", "c"] {
            let action = DecisionsViewLogic.keyAction(
                isArrowDown: false, isArrowUp: false, character: key,
                modifiersBlockShortcuts: false, noteFieldFocused: false,
                hasSelection: true, selectionIsToReview: false)
            #expect(action == .ignored)
        }
    }

    @Test func keyActionMapsAQAndCToTheirJudgment() {
        #expect(
            DecisionsViewLogic.keyAction(
                isArrowDown: false, isArrowUp: false, character: "a",
                modifiersBlockShortcuts: false, noteFieldFocused: false,
                hasSelection: true, selectionIsToReview: true) == .judge(.accepted))
        #expect(
            DecisionsViewLogic.keyAction(
                isArrowDown: false, isArrowUp: false, character: "Q",
                modifiersBlockShortcuts: false, noteFieldFocused: false,
                hasSelection: true, selectionIsToReview: true) == .judge(.questioned))
        #expect(
            DecisionsViewLogic.keyAction(
                isArrowDown: false, isArrowUp: false, character: "c",
                modifiersBlockShortcuts: false, noteFieldFocused: false,
                hasSelection: true, selectionIsToReview: true) == .judge(.discuss))
    }

    @Test func keyActionMapsMAndSpaceToToggleExpandedEvenWhenNotToReview() {
        #expect(
            DecisionsViewLogic.keyAction(
                isArrowDown: false, isArrowUp: false, character: "m",
                modifiersBlockShortcuts: false, noteFieldFocused: false,
                hasSelection: true, selectionIsToReview: false) == .toggleExpanded)
        #expect(
            DecisionsViewLogic.keyAction(
                isArrowDown: false, isArrowUp: false, character: " ",
                modifiersBlockShortcuts: false, noteFieldFocused: false,
                hasSelection: true, selectionIsToReview: false) == .toggleExpanded)
    }

    @Test func keyActionIgnoresAnyOtherCharacter() {
        let action = DecisionsViewLogic.keyAction(
            isArrowDown: false, isArrowUp: false, character: "z",
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
        let sequence = [
            decision("a", state: .accepted), decision("b", state: .accepted),
            decision("c", state: .unreviewed), decision("d", state: .unreviewed),
        ]
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
        #expect(
            DecisionsViewLogic.selectionAfterTogglingReview(toReview: toReview, decisionId: "c", addingToReview: true)
                == "c")
    }

    @Test func selectionAfterRemovingFromReviewMovesToTheNextOneToReview() {
        let toReview = [decision("a"), decision("b"), decision("c")]
        #expect(
            DecisionsViewLogic.selectionAfterTogglingReview(toReview: toReview, decisionId: "a", addingToReview: false)
                == "b")
    }

    @Test func selectionAfterRemovingTheLastOneToReviewFallsBackToAnyOtherRemaining() {
        let toReview = [decision("a"), decision("b"), decision("c")]
        #expect(
            DecisionsViewLogic.selectionAfterTogglingReview(toReview: toReview, decisionId: "c", addingToReview: false)
                == "a")
    }

    @Test func selectionAfterRemovingTheOnlyDecisionToReviewIsNil() {
        #expect(
            DecisionsViewLogic.selectionAfterTogglingReview(
                toReview: [decision("a")], decisionId: "a", addingToReview: false) == nil)
    }

    @Test func arrivalSelectionSelectsAndRevealsOtherWhenTheTargetIsAnOtherDecision() {
        let plan = DecisionsViewLogic.arrivalSelection(
            decisionId: "x", decisionExists: true, isOtherDecision: true,
            existingSelectedId: nil, fallbackId: "a")
        #expect(plan.selectedId == "x")
        #expect(plan.revealOther)
    }

    @Test func arrivalSelectionSelectsWithoutRevealingWhenTheTargetIsAlreadyInTheList() {
        let plan = DecisionsViewLogic.arrivalSelection(
            decisionId: "x", decisionExists: true, isOtherDecision: false,
            existingSelectedId: nil, fallbackId: "a")
        #expect(plan.selectedId == "x")
        #expect(!plan.revealOther)
    }

    @Test func arrivalSelectionKeepsTheExistingSelectionWhenNoTargetIsGiven() {
        let plan = DecisionsViewLogic.arrivalSelection(
            decisionId: nil, decisionExists: false, isOtherDecision: false,
            existingSelectedId: "already-selected", fallbackId: "a")
        #expect(plan.selectedId == "already-selected")
        #expect(!plan.revealOther)
    }

    @Test func arrivalSelectionFallsBackToTheFirstSequenceIdWhenNothingWasSelectedAndTheTargetDoesntExist() {
        let plan = DecisionsViewLogic.arrivalSelection(
            decisionId: "gone", decisionExists: false, isOtherDecision: false,
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
        let tradeoff = DecisionTradeoff(
            dimensionA: "speed", dimensionB: "safety", chosenPosition: 1,
            explanation: Statement(text: "Chose safety because of X", provenance: .claim))
        #expect(DecisionsViewLogic.tradeoffHelp(tradeoff) == "Chose safety because of X — right-click to ask about it")
    }

    @Test func tradeoffHelpFallsBackToNamingTheChosenSide() {
        let tradeoff = DecisionTradeoff(dimensionA: "speed", dimensionB: "safety", chosenPosition: 1)
        #expect(DecisionsViewLogic.tradeoffHelp(tradeoff) == "Leans toward safety — right-click to ask about it")
    }

    @Test func beforeAfterPartsSplitsOnTheUnicodeArrowAndTrimsWhitespace() {
        #expect(
            DecisionsViewLogic.beforeAfterParts(from: "Reader → Inspector → Printer")
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

    private func brief(options: [DecisionOption] = [], answer: String = "the answer") -> DecisionBrief {
        DecisionBrief(
            question: "Q?", shape: nil, options: options, answer: answer, insteadOf: nil, why: nil, tradeoff: nil)
    }

    @Test func otherDecisionsOpenByDefaultOnlyWhenNothingIsToReview() {
        #expect(DecisionsViewLogic.otherShown(showOther: false, toReviewIsEmpty: true))
        #expect(DecisionsViewLogic.otherShown(showOther: true, toReviewIsEmpty: false))
        #expect(!DecisionsViewLogic.otherShown(showOther: false, toReviewIsEmpty: false))
    }

    @Test func sequenceAppendsOtherDecisionsOnlyOnceShown() {
        let review = [decision("r1"), decision("r2")]
        let other = [decision("o1")]
        #expect(
            DecisionsViewLogic.sequence(toReview: review, other: other, otherShown: false).map(\.id) == ["r1", "r2"])
        #expect(
            DecisionsViewLogic.sequence(toReview: review, other: other, otherShown: true).map(\.id) == [
                "r1", "r2", "o1",
            ])
    }

    @Test func otherToggleTitlePluralizesAndFlipsWhenShown() {
        #expect(DecisionsViewLogic.otherToggleTitle(showOther: true, count: 3) == "Hide lower-impact decisions")
        #expect(DecisionsViewLogic.otherToggleTitle(showOther: false, count: 1) == "Show 1 lower-impact decision")
        #expect(DecisionsViewLogic.otherToggleTitle(showOther: false, count: 4) == "Show 4 lower-impact decisions")
    }

    @Test func oneAtATimeStepDisablesEndsAndOffersOthersAtTheEnd() {
        let first = DecisionsViewLogic.oneAtATimeStep(index: 0, count: 3, otherCount: 2, otherShown: false)
        #expect(first == .init(label: "1 of 3", canGoPrevious: false, canGoNext: true, offersOtherDecisions: false))
        let last = DecisionsViewLogic.oneAtATimeStep(index: 2, count: 3, otherCount: 2, otherShown: false)
        #expect(last == .init(label: "3 of 3", canGoPrevious: true, canGoNext: false, offersOtherDecisions: true))
        #expect(
            !DecisionsViewLogic.oneAtATimeStep(index: 2, count: 3, otherCount: 2, otherShown: true).offersOtherDecisions
        )
        #expect(
            !DecisionsViewLogic.oneAtATimeStep(index: 2, count: 3, otherCount: 0, otherShown: false)
                .offersOtherDecisions)
    }

    @Test func whyLabelIsPlainWhenNothingAboveItDrewAChoice() {
        #expect(DecisionsViewLogic.whyLabel(hasShape: false, hasTradeoff: false) == "Why")
        #expect(DecisionsViewLogic.whyLabel(hasShape: true, hasTradeoff: false) == "Why this side?")
        #expect(DecisionsViewLogic.whyLabel(hasShape: false, hasTradeoff: true) == "Why this side?")
    }

    @Test func noteFieldShowsWhenQuestionedOrWhenANoteExists() {
        #expect(DecisionsViewLogic.showsNoteField(state: .questioned, note: ""))
        #expect(DecisionsViewLogic.showsNoteField(state: .accepted, note: "hmm"))
        #expect(!DecisionsViewLogic.showsNoteField(state: .accepted, note: ""))
    }

    @Test func chosenSummaryPrefersTheChosenOptionThenTheAnswer() {
        let withDetail = brief(options: [
            DecisionOption(label: "A"), DecisionOption(label: "B", detail: "faster", chosen: true),
        ])
        #expect(DecisionsViewLogic.chosenSummary(withDetail) == "B — faster")
        let noDetail = brief(options: [DecisionOption(label: "B", chosen: true)])
        #expect(DecisionsViewLogic.chosenSummary(noDetail) == "B")
        #expect(
            DecisionsViewLogic.chosenSummary(brief(options: [DecisionOption(label: "A")], answer: "Did X")) == "Did X")
    }

    @Test func reviewButtonHelpOffersClearingOnlyWhenOn() {
        #expect(
            DecisionsViewLogic.reviewButtonHelp(isOn: false, target: .accepted, title: "Looks good", shortcut: "A")
                == "Looks good (A)")
        #expect(
            DecisionsViewLogic.reviewButtonHelp(isOn: true, target: .accepted, title: "Looks good", shortcut: "A")
                == "\(ReviewerState.accepted.label) — click to clear (A)")
    }

    @Test func progressDotFillDistinguishesPendingDiscussedAndJudged() {
        #expect(DecisionsViewLogic.progressDotFill(resolved: false, state: .accepted) == .pending)
        #expect(DecisionsViewLogic.progressDotFill(resolved: true, state: .unreviewed) == .discussed)
        #expect(DecisionsViewLogic.progressDotFill(resolved: true, state: .questioned) == .judged(.questioned))
    }

    @Test func drillDownTextHelpersFormatCountsEdgesAndFooter() {
        #expect(DecisionsViewLogic.tradeoffsTitle(count: 1) == "What it traded")
        #expect(DecisionsViewLogic.tradeoffsTitle(count: 3) == "What it traded (3)")
        #expect(DecisionsViewLogic.edgeTitle(from: "A", to: "B") == "A → B")
        #expect(
            DecisionsViewLogic.drillDownFooter(level: "Design", confidence: "High")
                == "Design-level choice · analysis confidence high")
    }

    @Test func spectrumFavorsTheSecondDimensionFromTheMidpointUp() {
        #expect(!DecisionsViewLogic.favorsSecondDimension(0.49))
        #expect(DecisionsViewLogic.favorsSecondDimension(0.5))
    }

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
