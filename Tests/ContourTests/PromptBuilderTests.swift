import Testing

@testable import Contour

struct PromptBuilderTests {
    private func context(
        comments: [String] = [], reviews: [String] = [], commits: [CommitInfo] = [], diff: String = "+x"
    ) -> RawPRContext {
        RawPRContext(
            url: "https://github.com/octo/widgets/pull/7", owner: "octo", repo: "widgets", number: 7,
            title: "Add thing", body: "Because reasons", author: "a", state: "OPEN", headRefName: "feature",
            baseRefName: "main", headSha: "abcdef1234567890", baseSha: "0123456789abcdef",
            isCrossRepository: false, headCloneURL: "", additions: 1, deletions: 0, changedFiles: 2,
            files: ["a.swift", "b.swift"], commits: commits, comments: comments, reviews: reviews, diff: diff)
    }

    @Test func contextFileOmitsCommentAndReviewSectionsWhenThereAreNone() {
        let text = PromptBuilder.contextFileContents(context())
        #expect(!text.contains("## Comments"))
        #expect(!text.contains("## Review bodies"))
        #expect(text.contains("Changed files (2): a.swift, b.swift"))
        #expect(text.contains("## Description\nBecause reasons"))
    }

    @Test func contextFileListsCommentsReviewsAndShortenedCommitShas() {
        let commit = CommitInfo(sha: "abcdef1234567890", message: "fix", author: "bob")
        let text = PromptBuilder.contextFileContents(
            context(comments: ["looks odd"], reviews: ["please rename"], commits: [commit]))
        #expect(text.contains("- abcdef12 (bob): fix"))
        #expect(text.contains("## Comments\n- looks odd\n"))
        #expect(text.contains("## Review bodies\n- please rename\n"))
    }

    @Test func contextFileTruncatesTheDiffAt120000Characters() {
        let text = PromptBuilder.contextFileContents(context(diff: String(repeating: "y", count: 130_000)))
        #expect(text.contains(String(repeating: "y", count: 120_000)))
        #expect(!text.contains(String(repeating: "y", count: 120_001)))
    }

    @Test func understandingPromptCitesAJiraTicketAsAJiraTicket() {
        let ticket = TicketInfo(kind: .jira, key: "ABC-1", summary: "Sum", description: "Desc", url: "u")
        let text = PromptBuilder.understandingPrompt(ticket: ticket)
        #expect(text.contains("A Jira ticket is linked to this PR: ABC-1 — Sum"))
        #expect(text.contains("Desc"))
    }

    @Test func understandingPromptCitesAGitHubTicketAsAnIssue() {
        let ticket = TicketInfo(kind: .github, key: "#9", summary: "Sum", description: "Desc", url: "u")
        #expect(PromptBuilder.understandingPrompt(ticket: ticket).contains("A GitHub issue is linked to this PR: #9"))
    }

    @Test func understandingPromptSaysWhenNoIssueWasFound() {
        #expect(PromptBuilder.understandingPrompt(ticket: nil).contains("No linked issue was found"))
    }

    @Test func componentOutlineNestsChildrenSkipsImplementationAndKeepsOrphans() {
        let parts = [
            ComponentNode(id: "a", title: "A", changeKind: .changed),
            ComponentNode(id: "a1", title: "A1", changeKind: .new, level: .component, parentId: "a"),
            ComponentNode(id: "a1i", title: "Impl", changeKind: .new, level: .implementation, parentId: "a1"),
            ComponentNode(id: "z", title: "Z", changeKind: .new, level: .component, parentId: "missing"),
            ComponentNode(id: "zi", title: "ZI", changeKind: .new, level: .implementation, parentId: "missing"),
        ]
        #expect(PromptBuilder.componentOutline(parts) == "- a: A\n  - a1: A1\n- z: Z")
    }

    @Test func stagePromptsAreNonEmptyAndEmbedTheirInputs() {
        let parts = [ComponentNode(id: "a", title: "A", changeKind: .changed)]
        #expect(PromptBuilder.behaviorChangePrompt().contains("behaviorChanges"))
        #expect(PromptBuilder.architecturePrompt().contains("architectureImpact"))
        #expect(PromptBuilder.decisionsPrompt().contains("Do NOT invent rationale"))
        #expect(PromptBuilder.flowsPrompt(components: parts).contains("- a: A"))
        #expect(PromptBuilder.judgmentPrompt(graphSoFar: "{\"k\":1}").contains("{\"k\":1}"))
    }

    @Test func judgmentPromptAsksForOneNeutralJudgmentPerItemWithoutAQuota() {
        let text = PromptBuilder.judgmentPrompt(graphSoFar: "{}")
        for rule in ["ONE JUDGMENT RULE", "COHERENCE RULE", "HUMAN-VALUE RULE", "NEUTRALITY RULE", "ABSTRACTION RULE"] {
            #expect(text.contains(rule))
        }
        #expect(text.contains("There is no quota"))
        #expect(text.contains(#""judgment": "...?""#))
        #expect(!text.contains(#""decision": "...?""#))
    }

    @Test func judgmentPromptAsksForADecisionBriefWithContextBeforeTheQuestion() {
        let text = PromptBuilder.judgmentPrompt(graphSoFar: "{}").split(whereSeparator: \.isWhitespace).joined(
            separator: " ")
        for phrase in [
            "DECISION BRIEF",
            "FIRST work out what a knowledgeable engineer who has not read the diff would need to know",
            "and only then the judgment question",
            "answerable from the headline, context, impact and tradeoff alone",
            "CERTAINTY RULE: do not manufacture certainty",
            "list what you inferred or could not confirm in assumptions",
            "Do not manufacture one",
            "Quality test, applied to every card before you return it",
            "engineer who has NOT read the diff and has only read this card",
            "1. What is the system doing? 2. What happens in the relevant edge case? 3. Why does this matter? "
                + "4. What are the meaningful alternatives or tradeoffs? 5. What exactly are they being asked to judge?",
            "If not, improve the card before returning it",
        ] {
            #expect(text.contains(phrase), "missing: \(phrase)")
        }
    }

    @Test func judgmentPromptTemplateOrdersTheBriefFieldsBeforeTheJudgment() throws {
        let text = PromptBuilder.judgmentPrompt(graphSoFar: "{}")
        let fields = [
            #""headline": "...""#, #""context": "...""#, #""impact": "...""#, #""tradeoff": "..."|null"#,
            #""moreContext": "..."|null"#, #""judgment": "...?""#, #""evidence": "...""#, #""assumptions": ["..."]"#,
        ]
        let positions = try fields.map { try #require(text.range(of: $0)).lowerBound }
        #expect(positions == positions.sorted())
        let implications = try #require(text.range(of: #""implications": [{"text""#)).lowerBound
        #expect(implications < positions[0])
    }
}
