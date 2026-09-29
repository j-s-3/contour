import Foundation
import SwiftUI
import Testing

@testable import Contour

@MainActor
struct ContextualChatTests {
    let graph = ContourSampleData.publishTriggeredReindex

    @Test func relationshipCarriesBothEndpoints() throws {
        let resolved = try #require(graph.resolve(.relationship("publish-queues")))
        #expect(resolved.kind == .relationship)
        #expect(resolved.title == "Page Publishing → Index Queue")
        #expect(Set(resolved.componentIds) == ["page-publishing", "index-queue"])
        #expect(resolved.decisionIds == ["index-on-publish"])
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

    @Test func resolvesOptionsTradeoffsStoryStepsFlowNodesAndConsequences() throws {
        let option = try #require(graph.resolve(.decisionOption(decisionId: "index-on-publish", index: 1)))
        #expect(option.kind == .option)
        #expect(option.title == "fresh results")

        let tradeoff = try #require(graph.resolve(.tradeoff(decisionId: "index-on-publish", index: 0)))
        #expect(tradeoff.kind == .tradeoff)
        #expect(tradeoff.title == "fast publish vs. fresh results")

        let story = try #require(graph.resolve(.storyStep(flowId: "publish-index-flow", index: 0)))
        #expect(story.kind == .flowStep)
        #expect(story.title == "Publish page")

        let node = try #require(graph.resolve(.flowNode(flowId: "publish-index-flow", nodeId: "queue")))
        #expect(node.kind == .flowStep)
        #expect(node.title == "Queue reindex job")

        let consequence = try #require(graph.resolve(.behaviorConsequence(changeId: "immediate-reindex")))
        #expect(consequence.kind == .statement)
        #expect(consequence.title.hasPrefix("Consequence:"))

        #expect(graph.resolve(.decisionOption(decisionId: "index-on-publish", index: 99)) == nil)
        #expect(graph.resolve(.tradeoff(decisionId: "index-on-publish", index: 99)) == nil)
        #expect(graph.resolve(.storyStep(flowId: "publish-index-flow", index: 99)) == nil)
        #expect(graph.resolve(.flowNode(flowId: "publish-index-flow", nodeId: "nope")) == nil)
    }

    @Test func describeAndLabelHelpersFormatConsistently() {
        #expect(PRGraph.flowChangeLabel(.new) == "New in this PR")
        #expect(PRGraph.flowChangeLabel(.changed) == "Changed by this PR")
        #expect(PRGraph.flowChangeLabel(.existing) == "Unchanged")
        #expect(PRGraph.flowChangeLabel(.removed) == "Removed by this PR")

        #expect(PRGraph.edgeChangeLabel(.new) == "new in this PR")
        #expect(PRGraph.edgeChangeLabel(.changed) == "changed by this PR")
        #expect(PRGraph.edgeChangeLabel(.existing) == "existing")
        #expect(PRGraph.edgeChangeLabel(.removed) == "removed by this PR")

        #expect(PRGraph.provenanceLabel(.fact, nil) == "observed fact")
        #expect(PRGraph.provenanceLabel(.claim, nil) == "author's claim")
        #expect(PRGraph.provenanceLabel(.interpretation, .high) == "AI inference, high confidence")
        #expect(PRGraph.provenanceLabel(.interpretation, nil) == "AI inference")

        #expect(PRGraph.oneLine("first\nsecond") == "first")
        #expect(PRGraph.oneLine("   \n") == nil)
        #expect(PRGraph.oneLine("") == nil)

        let statement = Statement(text: "Stale results were reported.", provenance: .claim, source: "PR description")
        #expect(PRGraph.describe(statement) == "Stale results were reported. (author's claim) [source: PR description]")
    }

    @Test func considerationAndFlowStepResolveAndConsiderationsReachArchitectureQuestions() throws {
        var withQuestion = graph
        withQuestion.pr.considerations = [
            Consideration(
                id: "burst-handling", question: "Can the queue absorb a burst of publishes?",
                detail: "No load test covers this.", relatedIds: ["index-queue", "publish-queues"]
            )
        ]

        let consideration = try #require(withQuestion.resolve(.consideration("burst-handling")))
        #expect(consideration.kind == .consideration)
        #expect(consideration.title == "Can the queue absorb a burst of publishes?")
        #expect(consideration.componentIds == ["index-queue"])

        let component = try #require(withQuestion.resolve(.component("index-queue")))
        #expect(
            component.detail.contains("Overview question about this part: Can the queue absorb a burst of publishes?"))

        let relationship = try #require(withQuestion.resolve(.relationship("publish-queues")))
        #expect(
            relationship.detail.contains(
                "Overview question about this relationship: Can the queue absorb a burst of publishes?"))

        let step = try #require(graph.resolve(.flowStep(flowId: "publish-index-flow", stepId: "step-enqueue")))
        #expect(step.kind == .flowStep)
        #expect(step.title == "enqueue index job")
        #expect(step.componentIds == ["index-queue"])
        #expect(step.detailTarget == .flowDetail("publish-index-flow"))
    }

    @Test func describeDecisionAndBehaviorChangeCoverEveryOptionalField() {
        let decision = DecisionNode(
            id: "d", title: "Use a queue", decision: Statement(text: "Queued.", provenance: .fact),
            rationale: [Statement(text: "Faster.", provenance: .fact)],
            alternatives: [Statement(text: "Inline call.", provenance: .interpretation, confidence: .low)],
            consequences: [Statement(text: "Extra hop.", provenance: .interpretation, confidence: .low)],
            confidence: .high,
            tradeoffs: [DecisionTradeoff(dimensionA: "speed", dimensionB: "freshness", chosenPosition: 0.5)],
            componentIds: [],
            reviewerState: .accepted, reviewerNote: "Makes sense.",
            level: .system, question: "Should this be queued?",
            why: Statement(text: "Avoids blocking the publish path.", provenance: .claim, source: "author"),
            significance: .high, impacts: [.correctness, .performance],
            significanceReason: "Changes the failure mode."
        )
        let described = PRGraph.describe(decision)
        #expect(described.contains("Review significance: high; impacts"))
        #expect(described.contains("Changes the failure mode."))
        #expect(described.contains("Question it answers: Should this be queued?"))
        #expect(described.contains("Why (short): Avoids blocking the publish path."))
        #expect(described.contains("Reviewer marked it: Looks good"))
        #expect(described.contains("Reviewer note: Makes sense."))

        let change = BehaviorChange(
            id: "c", title: "Reindex sooner",
            humanQuestion: Statement(
                text: "Is the queue durable across a restart?", provenance: .interpretation, confidence: .medium)
        )
        #expect(PRGraph.describe(change).contains("Open question: Is the queue durable across a restart?"))
    }

    @Test func documentIsFocusedByDefaultAndWidensOnRequest() throws {
        let resolved = try #require(graph.resolve(.component("index-queue")))
        let narrow = ChatContextBuilder.document(
            graph: graph, resolved: resolved, expansions: [], pinnedRefs: [], excerpts: [])
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

    @Test func conversationErrorMessagesAreReviewerFacing() {
        #expect(
            ConversationError.noCheckout.errorDescription
                == "There's no local checkout for this PR, so there's nothing to ask about yet.")
        #expect(ConversationError.emptyResponse(harness: "pi").errorDescription == "pi finished without an answer.")
    }

    @Test func systemPromptCarriesTheUntrustedContentAndLinkingRules() {
        #expect(ConversationService.systemPrompt.contains("UNTRUSTED_PR_CONTENT"))
        #expect(ConversationService.systemPrompt.contains("[[kind:id]]"))
    }

    @Test func mockResponseStreamsActivityThenDeltasThenFinal() async throws {
        let doc = """
            ## Where the reviewer is
            - **Index Queue** ← selected (Architecture)

            ## Code references for this context
            - `src/main/java/queue/IndexQueue.java:1-30`
            """
        var events: [ConversationEvent] = []
        for try await event in ConversationService.mockResponse(contextDocument: doc, question: "Why queued?") {
            events.append(event)
        }
        guard case .activity = events.first else {
            Issue.record("expected activity first")
            return
        }
        guard case .final(let final) = events.last else {
            Issue.record("expected final last")
            return
        }
        #expect(
            events.dropFirst().dropLast().allSatisfy {
                if case .delta = $0 { return true } else { return false }
            })
        #expect(final.contains("Index Queue"))
        #expect(final.contains("src/main/java/queue/IndexQueue.java:1-30"))
        #expect(final.contains("Why queued?"))
    }

    private func stub(
        _ kind: SubjectKind, subject: ReviewSubject = .pullRequest,
        decisionIds: [String] = [], flowIds: [String] = [], refs: [CodeRef] = []
    ) -> ResolvedSubject {
        ResolvedSubject(
            subject: subject, kind: kind, title: "t", lineage: [], summary: [], detail: "d",
            decisionIds: decisionIds, flowIds: flowIds, refs: refs
        )
    }

    @Test func suggestionsCoverEveryKind() {
        #expect(ChatContextBuilder.suggestions(for: stub(.component)).first == "Why is this its own part?")
        #expect(ChatContextBuilder.suggestions(for: stub(.relationship)).first == "What crosses here, and why?")
        #expect(ChatContextBuilder.suggestions(for: stub(.decision)).first == "Why was this chosen?")
        #expect(ChatContextBuilder.suggestions(for: stub(.option)).first == "Why did they choose this?")
        #expect(ChatContextBuilder.suggestions(for: stub(.tradeoff)).first == "Why did the PR choose this side?")
        #expect(ChatContextBuilder.suggestions(for: stub(.flow)).first == "Walk me through this")
        let flowNodeStep = stub(.flowStep, subject: .flowNode(flowId: "f", nodeId: "n"))
        #expect(ChatContextBuilder.suggestions(for: flowNodeStep)[1] == "What changed at this step?")
        let plainStep = stub(.flowStep, subject: .flowStep(flowId: "f", stepId: "s"))
        #expect(ChatContextBuilder.suggestions(for: plainStep)[1] == "What can fail at this step?")
        #expect(ChatContextBuilder.suggestions(for: stub(.behavior)).first == "Why did this change?")
        #expect(ChatContextBuilder.suggestions(for: stub(.stage)).first == "Why did this change?")
        #expect(ChatContextBuilder.suggestions(for: stub(.statement)).first == "Is this actually true?")
        #expect(ChatContextBuilder.suggestions(for: stub(.consideration)).first == "Why does this matter?")
        #expect(ChatContextBuilder.suggestions(for: stub(.entryPoint)).first == "What triggers this?")
        #expect(ChatContextBuilder.suggestions(for: stub(.code)).first == "Why this line?")
        #expect(ChatContextBuilder.suggestions(for: stub(.pullRequest)).first == "Summarize this PR")
    }

    @Test func availableExpansionsGateOnKindAndData() {
        let noData = stub(.component)
        #expect(ChatContextBuilder.availableExpansions(for: noData) == [.entirePR])

        let withDecisions = stub(.component, decisionIds: ["d1"])
        #expect(ChatContextBuilder.availableExpansions(for: withDecisions).contains(.relatedDecisions))
        let decisionItself = stub(.decision, decisionIds: ["d1"])
        #expect(!ChatContextBuilder.availableExpansions(for: decisionItself).contains(.relatedDecisions))
        let optionItself = stub(.option, decisionIds: ["d1"])
        #expect(!ChatContextBuilder.availableExpansions(for: optionItself).contains(.relatedDecisions))

        let withFlows = stub(.component, flowIds: ["f1"])
        #expect(ChatContextBuilder.availableExpansions(for: withFlows).contains(.relatedFlows))
        let flowItself = stub(.flow, flowIds: ["f1"])
        #expect(!ChatContextBuilder.availableExpansions(for: flowItself).contains(.relatedFlows))

        let withRefs = stub(.component, refs: [CodeRef(path: "a.swift", startLine: 1, endLine: 2)])
        #expect(ChatContextBuilder.availableExpansions(for: withRefs).contains(.implementation))
        let codeItself = stub(.code, refs: [CodeRef(path: "a.swift", startLine: 1, endLine: 2)])
        #expect(!ChatContextBuilder.availableExpansions(for: codeItself).contains(.implementation))

        let pr = stub(.pullRequest)
        #expect(!ChatContextBuilder.availableExpansions(for: pr).contains(.entirePR))
    }

    @Test func linkTokenCoversEveryReviewSubjectCase() {
        #expect(ChatContextBuilder.linkToken(for: .component("c")) == "[[component:c]]")
        #expect(ChatContextBuilder.linkToken(for: .relationship("r")) == "[[relationship:r]]")
        #expect(ChatContextBuilder.linkToken(for: .decision("d")) == "[[decision:d]]")
        #expect(ChatContextBuilder.linkToken(for: .decisionOption(decisionId: "d", index: 0)) == "[[decision:d]]")
        #expect(ChatContextBuilder.linkToken(for: .tradeoff(decisionId: "d", index: 0)) == "[[decision:d]]")
        #expect(ChatContextBuilder.linkToken(for: .flow("f")) == "[[flow:f]]")
        #expect(ChatContextBuilder.linkToken(for: .flowStep(flowId: "f", stepId: "s")) == "[[flow:f]]")
        #expect(ChatContextBuilder.linkToken(for: .storyStep(flowId: "f", index: 0)) == "[[flow:f]]")
        #expect(ChatContextBuilder.linkToken(for: .flowNode(flowId: "f", nodeId: "n")) == "[[flow:f]]")

        #expect(ChatContextBuilder.linkToken(for: .pullRequest) == nil)
        #expect(ChatContextBuilder.linkToken(for: .behaviorChange("b")) == nil)
        #expect(ChatContextBuilder.linkToken(for: .behaviorStage(changeId: "b", stageId: "s")) == nil)
        #expect(ChatContextBuilder.linkToken(for: .behaviorWhy(changeId: "b")) == nil)
        #expect(ChatContextBuilder.linkToken(for: .behaviorConsequence(changeId: "b")) == nil)
        #expect(ChatContextBuilder.linkToken(for: .consideration("c")) == nil)
        #expect(ChatContextBuilder.linkToken(for: .entryPoint("e")) == nil)
        #expect(ChatContextBuilder.linkToken(for: .codeRef(CodeRef(path: "a.swift", startLine: 1, endLine: 2))) == nil)
    }

    @Test func documentBuildsForFlowsEntryPointsAndBehaviorChanges() throws {
        let flow = try #require(graph.resolve(.flow("publish-index-flow")))
        let flowDoc = ChatContextBuilder.document(
            graph: graph, resolved: flow, expansions: [], pinnedRefs: [], excerpts: [])
        #expect(flowDoc.contains("**Publish a page** ← selected"))

        let entry = try #require(graph.resolve(.entryPoint("publish-endpoint")))
        let entryDoc = ChatContextBuilder.document(
            graph: graph, resolved: entry, expansions: [], pinnedRefs: [], excerpts: [])
        #expect(entryDoc.contains("PUT /pages/{slug}"))

        let change = try #require(graph.resolve(.behaviorChange("immediate-reindex")))
        let changeDoc = ChatContextBuilder.document(
            graph: graph, resolved: change, expansions: [], pinnedRefs: [], excerpts: [])
        #expect(changeDoc.contains("Publishing now triggers reindexing immediately"))

        let firstStageId = try #require(
            graph.behaviorChanges.first(where: { $0.id == "immediate-reindex" })?.before.first?.id)
        let stage = try #require(graph.resolve(.behaviorStage(changeId: "immediate-reindex", stageId: firstStageId)))
        #expect(stage.kind == .stage)
        let stageDoc = ChatContextBuilder.document(
            graph: graph, resolved: stage, expansions: [], pinnedRefs: [], excerpts: [])
        #expect(stageDoc.contains("Publish page"))

        let why = try #require(graph.resolve(.behaviorWhy(changeId: "immediate-reindex")))
        #expect(why.kind == .statement)
    }

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
        let urlString = try #require(
            out.range(of: #"contour://code\?[^)]+"#, options: .regularExpression).map { String(out[$0]) })
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
        let urlString = try #require(
            out.range(of: #"contour://node\?[^)]+"#, options: .regularExpression).map { String(out[$0]) })
        #expect(ChatLinks.target(for: try #require(URL(string: urlString))) == .node(.decision("index-on-publish")))
        #expect(linkify("[[decision:ghost]]") == "[[decision:ghost]]")
    }

    @Test func linkifyingIsIdempotent() {
        let once = linkify("`IndexQueue.java:12` and [[flow:publish-index-flow]]")
        #expect(linkify(once) == once)
    }

    @Test func urlForCodeRefRoundTripsEveryField() throws {
        let ref = CodeRef(path: "a/B.java", startLine: 3, endLine: 9, side: .base)
        let url = try #require(ChatLinks.url(for: ref))
        #expect(ChatLinks.target(for: url) == .code(ref))
    }

    @Test func urlForNodeRoundTripsKindAndId() throws {
        let url = try #require(ChatLinks.url(kind: "decision", id: "abc"))
        #expect(ChatLinks.target(for: url) == .node(.decision("abc")))
    }

    @Test func targetDeclinesUnrecognizedOrIncompleteURLs() throws {
        #expect(ChatLinks.target(for: try #require(URL(string: "https://example.com"))) == nil)
        #expect(ChatLinks.target(for: try #require(URL(string: "contour://other"))) == nil)
        #expect(ChatLinks.target(for: try #require(URL(string: "contour://code?path=a.swift"))) == nil)
        #expect(ChatLinks.target(for: try #require(URL(string: "contour://node?kind=bogus&id=x"))) == nil)
    }

    @Test func subjectMapsEveryKnownKindCaseInsensitivelyAndRejectsUnknown() {
        #expect(ChatLinks.subject(kind: "component", id: "c") == .component("c"))
        #expect(ChatLinks.subject(kind: "relationship", id: "r") == .relationship("r"))
        #expect(ChatLinks.subject(kind: "edge", id: "r") == .relationship("r"))
        #expect(ChatLinks.subject(kind: "decision", id: "d") == .decision("d"))
        #expect(ChatLinks.subject(kind: "flow", id: "f") == .flow("f"))
        #expect(ChatLinks.subject(kind: "entry", id: "e") == .entryPoint("e"))
        #expect(ChatLinks.subject(kind: "entrypoint", id: "e") == .entryPoint("e"))
        #expect(ChatLinks.subject(kind: "COMPONENT", id: "c") == .component("c"))
        #expect(ChatLinks.subject(kind: "nonsense", id: "x") == nil)
    }

    @Test func linkifyEscapesBracketsInTitles() {
        let out = ChatLinks.linkify(
            "See [[decision:x]].",
            resolve: { _ in nil },
            title: { _ in "Use [fast path]" }
        )
        #expect(out == "See [Use \\[fast path\\]](contour://node?kind=decision&id=x).")
    }

    @Test func resolvePathAcceptsARealFileInTheCheckout() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "content".write(to: dir.appendingPathComponent("a.swift"), atomically: true, encoding: .utf8)
        #expect(ChatViewLogic.resolvePath("a.swift", checkoutRoot: dir, citedPaths: []) == "a.swift")
    }

    @Test func resolvePathAcceptsAPathTheModelCitedDirectly() {
        #expect(
            ChatViewLogic.resolvePath("src/a.swift", checkoutRoot: nil, citedPaths: ["src/a.swift"]) == "src/a.swift")
    }

    @Test func resolvePathAcceptsABareNameThatUniquelySuffixMatchesACitedPath() {
        let cited = ["src/main/Listener.java"]
        #expect(
            ChatViewLogic.resolvePath("Listener.java", checkoutRoot: nil, citedPaths: cited) == "src/main/Listener.java"
        )
    }

    @Test func resolvePathDeclinesAnAmbiguousSuffixMatch() {
        let cited = ["a/Listener.java", "b/Listener.java"]
        #expect(ChatViewLogic.resolvePath("Listener.java", checkoutRoot: nil, citedPaths: cited) == nil)
    }

    @Test func resolvePathDeclinesAnUnknownPath() {
        #expect(ChatViewLogic.resolvePath("Nope.java", checkoutRoot: nil, citedPaths: ["src/a.swift"]) == nil)
    }

    @Test @MainActor func handleNavigatesToTheCodeReferenceForACodeLink() throws {
        let store = GraphStore()
        let ref = CodeRef(path: "a.swift", startLine: 1, endLine: 2)
        let url = try #require(ChatLinks.url(for: ref))
        _ = ChatViewLogic.handle(url, store: store, graph: graph)
        #expect(store.current == .evidence(ref))
    }

    @Test @MainActor func handleNavigatesToADecisionsDetailTargetForANodeLink() throws {
        let store = GraphStore()
        let url = try #require(ChatLinks.url(kind: "decision", id: "index-on-publish"))
        _ = ChatViewLogic.handle(url, store: store, graph: graph)
        #expect(store.current == .decisionDetail("index-on-publish"))
    }

    @Test @MainActor func handleDoesNotNavigateForADanglingNodeReference() throws {
        let store = GraphStore()
        let url = try #require(ChatLinks.url(kind: "decision", id: "does-not-exist"))
        _ = ChatViewLogic.handle(url, store: store, graph: graph)
        #expect(store.current == .summary, "nothing to navigate to, so the path is unchanged")
    }

    @Test @MainActor func handleDoesNotNavigateForAnUnrecognizedURL() throws {
        let store = GraphStore()
        let url = try #require(URL(string: "https://example.com"))
        _ = ChatViewLogic.handle(url, store: store, graph: graph)
        #expect(store.current == .summary)
    }

    @Test func subjectPhraseFallsBackForCodeAndUsesTheTitleOtherwise() {
        #expect(ChatViewLogic.subjectPhrase(for: stub(.code)) == "this code")
        #expect(ChatViewLogic.subjectPhrase(for: stub(.decision)) == "t")
    }

    @Test func canSendRejectsWhitespaceOnlyDraftsAndAcceptsRealText() {
        #expect(!ChatViewLogic.canSend(""))
        #expect(!ChatViewLogic.canSend("   \t"))
        #expect(ChatViewLogic.canSend("Why?"))
        #expect(ChatViewLogic.canSend("  Why?  "))
    }

    @Test func evidenceToOfferGatesOnLookingAtCodeNotAlreadyPinnedAndNotTheThreadsOwnSubject() {
        let ref = CodeRef(path: "a.swift", startLine: 1, endLine: 2)
        #expect(ChatViewLogic.evidenceToOffer(current: .evidence(ref), pinnedRefs: [], subject: .decision("d")) == ref)
        #expect(ChatViewLogic.evidenceToOffer(current: .summary, pinnedRefs: [], subject: .decision("d")) == nil)
        #expect(
            ChatViewLogic.evidenceToOffer(current: .evidence(ref), pinnedRefs: [ref], subject: .decision("d")) == nil)
        #expect(ChatViewLogic.evidenceToOffer(current: .evidence(ref), pinnedRefs: [], subject: .codeRef(ref)) == nil)
    }

    @Test func showsContextChipsIsFalseOnlyWhenBothExpansionsAndPinsAreEmpty() {
        #expect(!ChatViewLogic.showsContextChips(expansions: [], pinnedRefs: []))
        #expect(ChatViewLogic.showsContextChips(expansions: [.entirePR], pinnedRefs: []))
        #expect(
            ChatViewLogic.showsContextChips(
                expansions: [], pinnedRefs: [CodeRef(path: "a.swift", startLine: 1, endLine: 2)]
            ))
    }

    @Test @MainActor func handleReportsHandledOnlyForContourLinks() throws {
        let store = GraphStore()
        let ref = CodeRef(path: "a.swift", startLine: 1, endLine: 2)
        #expect(ChatViewLogic.handle(try #require(ChatLinks.url(for: ref)), store: store, graph: graph) == .handled)
        #expect(
            ChatViewLogic.handle(try #require(URL(string: "https://example.com")), store: store, graph: graph)
                == .system)
    }

    @Test func summaryLinesCapAtFourAndFlagOnlyTheFirstAsLead() {
        var resolved = stub(.decision)
        #expect(ChatViewLogic.summaryLines(for: resolved).isEmpty)
        resolved = ResolvedSubject(
            subject: .pullRequest, kind: .decision, title: "t", lineage: [], summary: ["a", "b", "c", "d", "e"],
            detail: "d", decisionIds: [], flowIds: [], refs: []
        )
        let lines = ChatViewLogic.summaryLines(for: resolved)
        #expect(lines.map(\.text) == ["a", "b", "c", "d"])
        #expect(lines.map(\.isLead) == [true, false, false, false])
    }

    @Test @MainActor func menuTitleUsesTheSubjectTitleOrAGenericFallback() {
        let known = Conversation(subject: .decision("index-on-publish"))
        #expect(ChatViewLogic.menuTitle(for: known, in: graph) == graph.resolve(.decision("index-on-publish"))?.title)
        #expect(ChatViewLogic.menuTitle(for: Conversation(subject: .decision("nope")), in: graph) == "Conversation")
    }

    @Test func activityTextDefaultsToThinking() {
        #expect(ChatViewLogic.activityText(nil) == "thinking")
        #expect(ChatViewLogic.activityText("Reading Foo.swift") == "Reading Foo.swift")
    }

    @Test @MainActor func togglingAnExpansionFlipsItAndTheChipCopyFollows() {
        let conversation = Conversation(subject: .pullRequest)
        ChatViewLogic.toggle(.entirePR, in: conversation)
        #expect(conversation.expansions.contains(.entirePR))
        ChatViewLogic.toggle(.entirePR, in: conversation)
        #expect(conversation.expansions.isEmpty)
        #expect(ChatViewLogic.expansionSymbol(on: true) == "checkmark")
        #expect(ChatViewLogic.expansionSymbol(on: false) == "plus")
        #expect(ChatViewLogic.expansionHelp(.entirePR, on: true) == "Included in the next answer")
        #expect(
            ChatViewLogic.expansionHelp(.entirePR, on: false)
                == "Include \(ContextExpansion.entirePR.label.lowercased()) in the next answer")
    }

    @Test @MainActor func unpinRemovesOnlyTheChosenRef() {
        let a = CodeRef(path: "a.swift", startLine: 1, endLine: 2)
        let b = CodeRef(path: "b.swift", startLine: 3, endLine: 4)
        let conversation = Conversation(subject: .pullRequest)
        conversation.pinnedRefs = [a, b]
        ChatViewLogic.unpin(a, in: conversation)
        #expect(conversation.pinnedRefs == [b])
    }

    @Test func citedPathsPoolsRefsFromEverySource() {
        let paths = graph.citedPaths
        #expect(paths.contains("src/main/java/publishing/PagePublisher.java"))
        #expect(paths.contains("src/main/java/queue/IndexQueue.java"))
        #expect(paths.contains("src/main/java/rest/PageResource.java"))
    }

    @Test func linkTitleNamesBothEndpointsOfARelationship() {
        #expect(graph.linkTitle(.relationship("publish-queues")) == "Page Publishing → Index Queue")
        #expect(graph.linkTitle(.relationship("nope")) == nil)
    }

    @Test func markdownBlocksSplitAsExpected() {
        let blocks = ChatMarkdownView.blocks(
            """
            ## Short answer
            It runs inline
            on upload.

            - first
            2. second
            ```
            let x = 1
            ```
            """)
        #expect(
            blocks == [
                .heading("Short answer"),
                .paragraph("It runs inline on upload."),
                .bullet("first"),
                .numbered("2.", "second"),
                .code("let x = 1"),
            ])
    }

    @Test func everyBulletMarkerIsRecognized() {
        #expect(ChatMarkdownView.blocks("- dash") == [.bullet("dash")])
        #expect(ChatMarkdownView.blocks("* star") == [.bullet("star")])
        #expect(ChatMarkdownView.blocks("• dot") == [.bullet("dot")])
    }

    @Test func blankLinesSeparateParagraphsAndJoinLinesWithinOne() {
        let blocks = ChatMarkdownView.blocks("First line\nsecond line\n\nSecond paragraph")
        #expect(blocks == [.paragraph("First line second line"), .paragraph("Second paragraph")])
    }

    @Test func anUnterminatedCodeFenceAtTheEndStillRendersAsCode() {
        let blocks = ChatMarkdownView.blocks("Before\n```\nlet x = 1\nlet y = 2")
        #expect(blocks == [.paragraph("Before"), .code("let x = 1\nlet y = 2")])
    }

    @Test func headingStripsAnyNumberOfHashesAndSurroundingWhitespace() {
        #expect(ChatMarkdownView.blocks("### Title") == [.heading("Title")])
        #expect(ChatMarkdownView.blocks("#No space") == [.heading("No space")])
    }

    @Test func numberedMarkerRequiresDigitsThenDotThenSpace() {
        #expect(ChatMarkdownView.blocks("1. first") == [.numbered("1.", "first")])
        #expect(ChatMarkdownView.blocks("Version 1.5 shipped") == [.paragraph("Version 1.5 shipped")])
        #expect(ChatMarkdownView.blocks("abc. not numbered") == [.paragraph("abc. not numbered")])
    }

    @Test func emptyTextProducesNoBlocks() {
        #expect(ChatMarkdownView.blocks("") == [])
        #expect(ChatMarkdownView.blocks("   \n\n  ") == [])
    }

    @Test func attributedTextRendersPlainTextUnchanged() {
        let result = ChatMarkdownView.attributedText(for: "hello world", linkify: { $0 })
        #expect(String(result.characters) == "hello world")
    }

    @Test func attributedTextParsesInlineMarkdownEmphasis() {
        let result = ChatMarkdownView.attributedText(for: "**bold** and *italic*", linkify: { $0 })
        #expect(String(result.characters) == "bold and italic")
    }

    @Test func attributedTextAppliesLinkifyBeforeParsingSoLinksBecomeClickable() {
        let result = ChatMarkdownView.attributedText(
            for: "see docs", linkify: { _ in "[see docs](https://example.com/x)" }
        )
        #expect(String(result.characters) == "see docs")
        #expect(result.runs.contains { $0.link == URL(string: "https://example.com/x") })
    }

    @Test func aQuestionIsDiscussedOnceTheReviewerAsksAboutIt() {
        let store = ConversationStore()
        store.open(.consideration("opened"))
        let asked = store.open(.consideration("asked"))
        asked.messages.append(ChatMessage(role: .user, text: "Is this safe?"))
        let onDecision = store.open(.decision("index-on-publish"))
        onDecision.messages.append(ChatMessage(role: .user, text: "Why?"))
        #expect(store.discussedConsiderationIds == ["asked"])
    }

    @Test func closeHidesTheSheetWithoutClearingThreads() {
        let store = ConversationStore()
        store.open(.decision("d1"))
        store.close()
        #expect(!store.isPresented)
        #expect(store.conversations.count == 1)
    }

    @Test func removingTheActiveConversationFallsBackToAnotherOrNone() {
        let store = ConversationStore()
        let first = store.open(.decision("d1"))
        let second = store.open(.decision("d2"))
        #expect(store.activeId == second.id)

        store.remove(first)
        #expect(store.activeId == second.id, "removing a non-active thread leaves activeId alone")

        store.remove(second)
        #expect(store.activeId == nil)
        #expect(!store.isPresented, "the sheet closes once the last thread is gone")
    }

    @Test func resetDropsEveryThreadAndClosesTheSheet() {
        let store = ConversationStore()
        store.open(.decision("d1"))
        store.open(.decision("d2"))
        store.reset()
        #expect(store.conversations.isEmpty)
        #expect(store.activeId == nil)
        #expect(!store.isPresented)
    }

    @Test func pinningIsIdempotentAndBumpsFocusOnlyOnce() {
        let store = ConversationStore()
        let conversation = store.open(.decision("d1"))
        let ref = CodeRef(path: "a.swift", startLine: 1, endLine: 2)
        store.pin(ref, in: conversation)
        #expect(conversation.pinnedRefs == [ref])
        let focusAfterFirstPin = store.focusRequest
        store.pin(ref, in: conversation)
        #expect(conversation.pinnedRefs == [ref], "pinning the same ref twice must not duplicate it")
        #expect(store.focusRequest == focusAfterFirstPin, "a no-op pin must not steal focus again")
    }

    @Test func cancelingAnIdleConversationIsANoOp() {
        let store = ConversationStore()
        let conversation = store.open(.decision("d1"))
        store.cancel(conversation)
        #expect(!conversation.isResponding)
    }

    @Test @MainActor func sendRecordsAnErrorWhenPrerequisitesAreMissing() {
        let store = ConversationStore()
        let checkout = RepoCheckout(rootDir: URL(fileURLWithPath: "/tmp"), headSha: "a", baseSha: "b")

        let noCheckout = store.open(.decision("index-on-publish"))
        store.send("Why?", in: noCheckout, graph: graph, checkout: nil, harnessID: .pi)
        #expect(noCheckout.messages.count == 2)
        #expect(noCheckout.messages.last?.error == ConversationError.noCheckout.localizedDescription)
        #expect(noCheckout.messages.last?.isStreaming == false)
        #expect(!noCheckout.isResponding)

        let noHarness = store.open(.component("index-queue"))
        store.send("Why?", in: noHarness, graph: graph, checkout: checkout, harnessID: nil)
        #expect(noHarness.messages.last?.error == "No AI harness selected. Pick one in Settings (⌘,).")

        let unresolvable = store.open(.decision("nope"))
        store.send("Why?", in: unresolvable, graph: graph, checkout: checkout, harnessID: .pi)
        #expect(unresolvable.messages.last?.error == "No AI harness selected. Pick one in Settings (⌘,).")
    }

    @Test @MainActor func sendIgnoresABlankQuestion() {
        let store = ConversationStore()
        let conversation = store.open(.decision("index-on-publish"))
        store.send("   \n  ", in: conversation, graph: graph, checkout: nil, harnessID: nil)
        #expect(conversation.messages.isEmpty)
    }

    private func excerptCheckout() -> (checkout: RepoCheckout, ref: CodeRef) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let lines = (1...20).map { "line \($0)" }
        try! lines.joined(separator: "\n").write(
            to: dir.appendingPathComponent("a.swift"), atomically: true, encoding: .utf8)
        let checkout = RepoCheckout(rootDir: dir, headSha: "h", baseSha: "b", symbolIndexPath: nil)
        return (checkout, CodeRef(path: "a.swift", startLine: 5, endLine: 6))
    }

    @Test func excerptsIsEmptyWithNoPinsNoCodeKindAndNoImplementationExpansion() async {
        let (checkout, ref) = excerptCheckout()
        defer { try? FileManager.default.removeItem(at: checkout.rootDir) }
        let resolved = stub(.decision, refs: [ref])
        let excerpts = await ConversationStore.excerpts(for: resolved, expansions: [], pinned: [], checkout: checkout)
        #expect(excerpts.isEmpty)
    }

    @Test func excerptsIncludesPinnedRefsRegardlessOfKind() async {
        let (checkout, ref) = excerptCheckout()
        defer { try? FileManager.default.removeItem(at: checkout.rootDir) }
        let resolved = stub(.decision)
        let excerpts = await ConversationStore.excerpts(
            for: resolved, expansions: [], pinned: [ref], checkout: checkout)
        #expect(excerpts.count == 1)
        #expect(excerpts[0].ref == ref)
        #expect(excerpts[0].text.contains("line 5"))
    }

    @Test func excerptsIncludesTheSubjectsOwnRefsWhenKindIsCode() async {
        let (checkout, ref) = excerptCheckout()
        defer { try? FileManager.default.removeItem(at: checkout.rootDir) }
        let resolved = stub(.code, refs: [ref])
        let excerpts = await ConversationStore.excerpts(for: resolved, expansions: [], pinned: [], checkout: checkout)
        #expect(excerpts.count == 1)
        #expect(excerpts[0].ref == ref)
    }

    @Test func excerptsIncludesTheSubjectsOwnRefsUnderTheImplementationExpansion() async {
        let (checkout, ref) = excerptCheckout()
        defer { try? FileManager.default.removeItem(at: checkout.rootDir) }
        let resolved = stub(.decision, refs: [ref])
        let excerpts = await ConversationStore.excerpts(
            for: resolved, expansions: [.implementation], pinned: [], checkout: checkout)
        #expect(excerpts.count == 1)
        #expect(excerpts[0].ref == ref)
    }
}
