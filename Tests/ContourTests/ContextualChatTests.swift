import Testing
import Foundation
@testable import Contour

/// The contract behind "the reviewer never has to explain what they are looking at":
/// clicking a thing resolves to that thing plus its parents and neighbors, and the answer's
/// citations come back as clickable links.
struct ContextualChatTests {
    let graph = ContourSampleData.publishTriggeredReindex

    // MARK: - Hierarchical resolution

    @Test func relationshipCarriesBothEndpoints() throws {
        let resolved = try #require(graph.resolve(.relationship("publish-queues")))
        #expect(resolved.kind == .relationship)
        #expect(resolved.title == "Page Publishing → Index Queue")
        #expect(Set(resolved.componentIds) == ["page-publishing", "index-queue"])
        #expect(resolved.decisionIds == ["index-on-publish"])
        // Both endpoints are described in full, not just named.
        #expect(resolved.detail.contains("Architecture part \"Page Publishing\""))
        #expect(resolved.detail.contains("Architecture part \"Index Queue\""))
        #expect(resolved.lineage.last == "Architecture")
    }

    @Test func componentKnowsItsDecisionsFlowsAndTriggers() throws {
        let resolved = try #require(graph.resolve(.component("index-queue")))
        #expect(resolved.decisionIds.contains("index-on-publish"))
        #expect(resolved.flowIds.contains("publish-index-flow"))
        #expect(resolved.summary.contains { $0.hasPrefix("Receives ") && $0.contains("from Page Publishing") })
        #expect(resolved.detailTarget == .componentDetail("index-queue"))
    }

    /// A code range brings the concept it supports along with it.
    @Test func codeReferenceResolvesToTheConceptItSupports() throws {
        let ref = CodeRef(path: "src/main/java/publishing/PagePublisher.java", startLine: 50, endLine: 60)
        let resolved = try #require(graph.resolve(.codeRef(ref)))
        #expect(resolved.kind == .code)
        #expect(resolved.decisionIds.contains("index-on-publish"))
        #expect(resolved.detail.contains("Decision \"Trigger reindexing synchronously on publish\""))
        #expect(resolved.detailTarget == .evidence(ref))
    }

    @Test func unknownSubjectsResolveToNil() {
        #expect(graph.resolve(.decision("nope")) == nil)
        #expect(graph.resolve(.flowStep(flowId: "publish-index-flow", stepId: "nope")) == nil)
    }

    // MARK: - Context document

    @Test func documentIsFocusedByDefaultAndWidensOnRequest() throws {
        let resolved = try #require(graph.resolve(.component("index-queue")))
        let narrow = ChatContextBuilder.document(graph: graph, resolved: resolved, expansions: [], pinnedRefs: [], excerpts: [])
        #expect(narrow.contains("**Index Queue** ← selected"))
        #expect(narrow.contains("[[component:index-queue]]"))
        #expect(narrow.contains("- Trigger reindexing synchronously on publish [[decision:index-on-publish]]"))
        #expect(!narrow.contains("- Rationale:"))
        #expect(!narrow.contains("Whole review model"))
        #expect(narrow.contains(PromptBuilder.contextFileName))

        let wide = ChatContextBuilder.document(
            graph: graph, resolved: resolved, expansions: [.relatedDecisions, .entirePR], pinnedRefs: [], excerpts: []
        )
        #expect(wide.contains("- Rationale: Stale search results after publishing"))
        #expect(wide.contains("Whole review model"))
    }

    @Test func pinnedCodeAndExcerptsAreIncluded() throws {
        let resolved = try #require(graph.resolve(.decision("index-on-publish")))
        let pinned = CodeRef(path: "src/Other.java", startLine: 3, endLine: 4)
        let doc = ChatContextBuilder.document(
            graph: graph, resolved: resolved, expansions: [], pinnedRefs: [pinned],
            excerpts: [(pinned, "3  int x = 1;")]
        )
        #expect(doc.contains("`src/Other.java:3-4`"))
        #expect(doc.contains("int x = 1;"))
    }

    @Test func suggestionsAndExpansionsFitTheKind() throws {
        let decision = try #require(graph.resolve(.decision("index-on-publish")))
        #expect(ChatContextBuilder.suggestions(for: decision).first == "Why was this chosen?")
        #expect(!ChatContextBuilder.availableExpansions(for: decision).contains(.relatedDecisions))

        let flow = try #require(graph.resolve(.flow("publish-index-flow")))
        #expect(ChatContextBuilder.suggestions(for: flow).first == "Walk me through this")
        #expect(!ChatContextBuilder.availableExpansions(for: flow).contains(.relatedFlows))
    }

    @Test func turnPromptReplaysTheConversation() {
        let history = [
            ChatMessage(role: .user, text: "Why is this synchronous?"),
            ChatMessage(role: .assistant, text: "Because of a race with the scheduler."),
        ]
        let prompt = ConversationService.turnPrompt(history: history, question: "What other process?")
        #expect(prompt.contains("Reviewer: Why is this synchronous?"))
        #expect(prompt.contains("You: Because of a race with the scheduler."))
        #expect(prompt.hasSuffix("Reviewer's question: What other process?"))
    }

    // MARK: - Links

    private func linkify(_ text: String) -> String {
        ChatLinks.linkify(
            text,
            resolve: { path in
                let known = ["src/main/java/queue/IndexQueue.java"]
                return known.contains(path) ? path : known.first { $0.hasSuffix("/" + path) }
            },
            title: graph.linkTitle
        )
    }

    @Test func codeCitationsBecomeLinksThatRoundTrip() throws {
        let out = linkify("It enqueues here `IndexQueue.java:12-20` before returning.")
        #expect(out.contains("[`IndexQueue.java:12–20`](contour://code?"))
        let urlString = try #require(out.range(of: #"contour://code\?[^)]+"#, options: .regularExpression).map { String(out[$0]) })
        let target = ChatLinks.target(for: try #require(URL(string: urlString)))
        #expect(target == .code(CodeRef(path: "src/main/java/queue/IndexQueue.java", startLine: 12, endLine: 20)))
    }

    @Test func unknownPathsAndHostsStayProse() {
        let text = "See example.com:8080 and `Missing.java:3`."
        #expect(linkify(text) == text)
    }

    @Test func reviewModelReferencesBecomeTitledLinks() throws {
        let out = linkify("This follows from [[decision:index-on-publish]].")
        #expect(out.contains("[Trigger reindexing synchronously on publish](contour://node?"))
        let urlString = try #require(out.range(of: #"contour://node\?[^)]+"#, options: .regularExpression).map { String(out[$0]) })
        #expect(ChatLinks.target(for: try #require(URL(string: urlString))) == .node(.decision("index-on-publish")))
        // An id that doesn't exist is left as written rather than linking nowhere.
        #expect(linkify("[[decision:ghost]]") == "[[decision:ghost]]")
    }

    @Test func linkifyingIsIdempotent() {
        let once = linkify("`IndexQueue.java:12` and [[flow:publish-index-flow]]")
        #expect(linkify(once) == once)
    }

    // MARK: - Markdown blocks

    @Test func markdownBlocksSplitAsExpected() {
        let blocks = ChatMarkdownView.blocks("""
        ## Short answer
        It runs inline
        on upload.

        - first
        2. second
        ```
        let x = 1
        ```
        """)
        #expect(blocks == [
            .heading("Short answer"),
            .paragraph("It runs inline on upload."),
            .bullet("first"),
            .numbered("2.", "second"),
            .code("let x = 1"),
        ])
    }

    // MARK: - Review progress

    /// Only a thread the reviewer wrote in counts as talking a question through — opening
    /// one, or asking about something that isn't an Overview question, doesn't.
    @Test @MainActor func aQuestionIsDiscussedOnceTheReviewerAsksAboutIt() {
        let store = ConversationStore()
        store.open(.consideration("opened"))
        let asked = store.open(.consideration("asked"))
        asked.messages.append(ChatMessage(role: .user, text: "Is this safe?"))
        let onDecision = store.open(.decision("index-on-publish"))
        onDecision.messages.append(ChatMessage(role: .user, text: "Why?"))
        #expect(store.discussedConsiderationIds == ["asked"])
    }
}
