import Testing
import SwiftUI
@testable import Contour

/// `DecisionsView.swift` is the single largest gap toward CLAUDE.md's 90% target. Per its
/// guidance, this pins the plain grouping/formatting logic already beside (or now pulled
/// out into) the view: `DecisionsViewLogic.questions`, `DecisionsView.provenanceNote`/
/// `.provenanceHelp` (already static, no production change needed), and the
/// `ReviewerState` extension's symbol/tint/label (already a plain, directly-testable type
/// defined in this file). `framing(toReview:total:)` is already covered by
/// `DecisionsBriefingTests`. The rest — cards, drill-downs, keyboard handling, the
/// one-at-a-time mode — is view bodies with no UI-testing infrastructure in this suite to
/// host them.
struct DecisionsViewTests {

    // MARK: - DecisionsViewLogic.questions

    private func consideration(_ id: String) -> Consideration {
        Consideration(id: id, question: "Q \(id)", detail: "")
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
}
