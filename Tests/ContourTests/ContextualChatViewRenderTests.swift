import Testing
import SwiftUI
import AppKit
@testable import Contour

/// `ContextualChatView`'s body and builders are SwiftUI view code with no logic left to
/// extract (derivations live in `ChatViewLogic`). This suite hosts the real view in an
/// `NSHostingView` over `ContourSampleData` and lays it out for the empty state and for
/// threads on every kind of subject, in every message state (user, streaming, errored,
/// assistant markdown), so each builder actually runs. It pins that none of those
/// combinations traps while building or laying out.
@MainActor
struct ContextualChatViewRenderTests {
    let graph = ContourSampleData.publishTriggeredReindex

    private func layout(_ store: GraphStore) -> NSHostingView<ContextualChatView> {
        let hosting = NSHostingView(rootView: ContextualChatView(store: store, graph: graph))
        hosting.frame = NSRect(x: 0, y: 0, width: 380, height: 800)
        hosting.layoutSubtreeIfNeeded()
        return hosting
    }

    @Test func rendersTheEmptyStateWithNoConversation() {
        let hosting = layout(GraphStore())
        #expect(hosting.fittingSize.width >= 0)
    }

    @Test func rendersAFreshThreadWithSuggestionsForEverySubjectKind() throws {
        let ref = CodeRef(path: "src/main/java/publishing/PagePublisher.java", startLine: 50, endLine: 60)
        var subjects: [ReviewSubject] = [.pullRequest, .codeRef(ref)]
        subjects += graph.decisions.map { .decision($0.id) }
        subjects += graph.components.map { .component($0.id) }
        subjects += graph.architectureEdges.map { .relationship($0.id) }
        subjects += graph.flows.map { .flow($0.id) }
        for subject in subjects {
            let store = GraphStore()
            store.conversations.open(subject)
            _ = layout(store)
        }
    }

    @Test func rendersMessagesInEveryState() throws {
        let store = GraphStore()
        let conversation = store.conversations.open(.decision("index-on-publish"))
        let ref = CodeRef(path: "src/main/java/publishing/PagePublisher.java", startLine: 50, endLine: 60)
        conversation.pinnedRefs = [ref]
        conversation.expansions = [.entirePR]
        conversation.draft = "Why?"
        conversation.activity = "reading Foo.swift"
        conversation.messages = [
            ChatMessage(role: .user, text: "Why was this chosen?"),
            ChatMessage(role: .assistant, text: "See `PagePublisher.java:50` and **bold**.\n- item"),
            ChatMessage(role: .assistant, text: "", isStreaming: true),
            ChatMessage(role: .assistant, text: "partial", isStreaming: true),
            ChatMessage(role: .assistant, text: "", error: "Something failed"),
        ]
        _ = layout(store)
    }

    /// With several conversations and the reviewer looking at unpinned evidence, the menu,
    /// the "Include the code you're viewing" offer and the stop button all render.
    @Test func rendersMultipleThreadsTheEvidenceOfferAndTheRespondingComposer() throws {
        let store = GraphStore()
        store.conversations.open(.pullRequest)
        let conversation = store.conversations.open(.decision("index-on-publish"))
        store.conversations.open(.decision("nope"))
        store.conversations.activeId = conversation.id
        store.navigate(to: .evidence(CodeRef(path: "a.swift", startLine: 1, endLine: 2)))
        _ = layout(store)

        // Sending with no checkout records an error reply rather than running a harness.
        store.conversations.send("What changed?", in: conversation, graph: graph, checkout: nil, harnessID: nil)
        #expect(conversation.messages.count == 2)
        _ = layout(store)
    }

    /// The conversations menu builds its items lazily, so the items are hosted directly:
    /// the active thread gets the checkmark row and the "Close" row is offered.
    @Test func rendersTheConversationMenuItems() {
        let store = GraphStore()
        store.conversations.open(.pullRequest)
        store.conversations.open(.decision("index-on-publish"))
        let view = ContextualChatView(store: store, graph: graph)
        let hosting = NSHostingView(rootView: view.conversationMenuContent)
        hosting.frame = NSRect(x: 0, y: 0, width: 300, height: 300)
        hosting.layoutSubtreeIfNeeded()
        #expect(hosting.fittingSize.width >= 0)
    }

    /// Appending messages to a hosted thread fires the scroll-to-bottom `onChange`
    /// handlers once the run loop turns; they must not trap.
    @Test func newMessagesInAHostedThreadTriggerTheScrollHandlers() {
        let store = GraphStore()
        let conversation = store.conversations.open(.pullRequest)
        let hosting = layout(store)
        conversation.messages.append(ChatMessage(role: .user, text: "hi"))
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        conversation.messages[0].text = "hello"
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        hosting.layoutSubtreeIfNeeded()
        #expect(hosting.fittingSize.width >= 0)
    }

    /// The view's link handler delegates to `ChatViewLogic`: a Contour link navigates,
    /// anything else is passed to the system and leaves navigation alone.
    @Test func handleNavigatesForContourLinksAndDefersOthersToTheSystem() throws {
        let store = GraphStore()
        let view = ContextualChatView(store: store, graph: graph)
        let ref = CodeRef(path: "a.swift", startLine: 1, endLine: 2)
        _ = view.handle(try #require(ChatLinks.url(for: ref)))
        #expect(store.current == .evidence(ref))
        _ = view.handle(try #require(URL(string: "https://example.com")))
        #expect(store.current == .evidence(ref))
    }

    @Test func staleActiveConversationFallsBackToTheEmptyState() {
        let store = GraphStore()
        store.conversations.open(.decision("nope"))
        _ = layout(store)
    }
}
