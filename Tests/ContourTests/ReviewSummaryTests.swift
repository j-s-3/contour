import Foundation
import Testing

@testable import Contour

struct ReviewSummaryTests {
    private func decision(
        _ id: String, question: String, significance: ReviewSignificance = .high,
        state: ReviewerState = .unreviewed, note: String = ""
    ) -> DecisionNode {
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

    @Test func rendersChangeJudgedDecisionsAndOpenQuestions() {
        let g = graph(
            [
                decision("a", question: "Should publish reindex synchronously?", state: .accepted),
                decision(
                    "b", question: "Is the queue bounded?", state: .discuss,
                    note: "What happens under a burst?\nWe saw this before."),
                decision(
                    "c", question: "Where does retry live?", state: .questioned, note: "  Why not in the worker?  "),
            ],
            considerations: [
                Consideration(
                    id: "q1", headline: "Can a burst of publishes starve the queue?", impact: "", relatedIds: ["b"]),
                Consideration(id: "q2", headline: "Is reindex idempotent?", impact: "", relatedIds: ["a"]),
            ])

        #expect(
            g.reviewSummaryMarkdown == """
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

    @Test func saysSoWhenNothingIsJudged() {
        let g = graph([decision("a", question: "Q?"), decision("b", question: "R?")])
        let md = g.reviewSummaryMarkdown
        #expect(md.contains("### Decisions (0 of 2 to review judged)\n\n_No decisions judged yet._"))
        #expect(!md.contains("Q?"))
        #expect(!md.contains("Open questions"))
    }

    @Test func includesOtherDecisionsTheReviewerMarkedOrAnnotated() {
        let g = graph([
            decision("a", question: "Main?", state: .accepted),
            decision("b", question: "Minor?", significance: .low, state: .questioned),
            decision("c", question: "Aside?", significance: .low, note: "Worth a follow-up."),
        ])
        let md = g.reviewSummaryMarkdown
        #expect(md.contains("### Decisions (1 of 1 to review judged)"))
        #expect(md.contains("- **Questioned** — Minor?"))
        #expect(md.contains("- **Note** — Aside?\n  > Worth a follow-up."))
        #expect(!md.contains("Unreviewed"))
    }

    @Test func fallsBackToIntentForWhatChanged() {
        var g = graph([])
        g.pr.howItWasSolved = nil
        g.pr.intent = Statement(
            text: "Reindex on publish (src/publish.rs:10-20). Also tidies logging.", provenance: .claim)
        #expect(g.reviewSummaryMarkdown.hasPrefix("**What changed:** Reindex on publish.\n\n"))
    }
}
