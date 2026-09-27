import Testing
import Foundation
@testable import Contour

/// "Copy review summary" turns the reviewer's marks and notes into Markdown ready to paste
/// into a GitHub review comment: what changed in one line, each judged decision with its
/// state and note, and the questions still open.
struct ReviewSummaryTests {

    private func decision(_ id: String, question: String, significance: ReviewSignificance = .high,
                          state: ReviewerState = .unreviewed, note: String = "") -> DecisionNode {
        DecisionNode(
            id: id, title: "Title \(id)",
            decision: Statement(text: "Decided \(id).", provenance: .fact),
            confidence: .medium, reviewerState: state, reviewerNote: note,
            question: question, significance: significance
        )
    }

    private func graph(_ decisions: [DecisionNode], considerations: [Consideration] = []) -> PRGraph {
        var graph = ContourSampleData.publishTriggeredReindex
        graph.decisions = decisions
        graph.pr.considerations = considerations
        graph.pr.needsJudgment = []
        graph.pr.uncertainties = []
        graph.behaviorChanges = []
        return graph
    }

    /// The whole payload, in order: the one-line change, the judged decisions most
    /// actionable first with their notes quoted beneath, then open questions.
    @Test func rendersChangeJudgedDecisionsAndOpenQuestions() {
        let g = graph([
            decision("a", question: "Should publish reindex synchronously?", state: .accepted),
            decision("b", question: "Is the queue bounded?", state: .discuss, note: "What happens under a burst?\nWe saw this before."),
            decision("c", question: "Where does retry live?", state: .questioned, note: "  Why not in the worker?  ")
        ], considerations: [
            Consideration(id: "q1", question: "Can a burst of publishes starve the queue?", detail: "", relatedIds: ["b"]),
            Consideration(id: "q2", question: "Is reindex idempotent?", detail: "", relatedIds: ["a"])
        ])

        #expect(g.reviewSummaryMarkdown == """
        **What changed:** The publish handler now enqueues an immediate reindex instead of relying on the nightly rebuild.

        ### Decisions (3 of 3 to review judged)

        - **Needs discussion** — Is the queue bounded?
          > What happens under a burst?
          > We saw this before.
        - **Questioned** — Where does retry live?
          > Why not in the worker?
        - **Looks good** — Should publish reindex synchronously?

        ### Open questions

        - Can a burst of publishes starve the queue?

        """)
    }

    /// Unjudged decisions are left out but still counted, and an empty review says so rather
    /// than rendering an empty list.
    @Test func saysSoWhenNothingIsJudged() {
        let g = graph([decision("a", question: "Q?"), decision("b", question: "R?")])
        let md = g.reviewSummaryMarkdown
        #expect(md.contains("### Decisions (0 of 2 to review judged)\n\n_No decisions judged yet._"))
        #expect(!md.contains("Q?"))
        #expect(!md.contains("Open questions"))
    }

    /// A decision outside Decisions to Review still appears once judged or annotated; a note
    /// without a mark is labeled as a note, never "Unreviewed".
    @Test func includesOtherDecisionsTheReviewerMarkedOrAnnotated() {
        let g = graph([
            decision("a", question: "Main?", state: .accepted),
            decision("b", question: "Minor?", significance: .low, state: .questioned),
            decision("c", question: "Aside?", significance: .low, note: "Worth a follow-up.")
        ])
        let md = g.reviewSummaryMarkdown
        #expect(md.contains("### Decisions (1 of 1 to review judged)"))
        #expect(md.contains("- **Questioned** — Minor?"))
        #expect(md.contains("- **Note** — Aside?\n  > Worth a follow-up."))
        #expect(!md.contains("Unreviewed"))
    }

    /// Without the plain-language "how it was solved", the PR's intent is the one line — its
    /// first sentence, code locations stripped.
    @Test func fallsBackToIntentForWhatChanged() {
        var g = graph([])
        g.pr.howItWasSolved = nil
        g.pr.intent = Statement(text: "Reindex on publish (src/publish.rs:10-20). Also tidies logging.", provenance: .claim)
        #expect(g.reviewSummaryMarkdown.hasPrefix("**What changed:** Reindex on publish.\n\n"))
    }
}
