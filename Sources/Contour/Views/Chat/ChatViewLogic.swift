import Foundation

/// One line of the "You are discussing" card. The first line is the lead (title-weight);
/// the rest are secondary.
struct ChatSummaryLine: Identifiable, Equatable {
    let id: Int
    let text: String
    var isLead: Bool { id == 0 }
}

/// The pure logic behind `ContextualChatView`, kept beside it so the view stays a thin
/// reader of `GraphStore` / `ConversationStore`. Everything here is directly testable
/// without hosting SwiftUI.
enum ChatViewLogic {
    /// How many summary lines the context card shows.
    nonisolated static let summaryLineLimit = 4

    /// The noun used in "Ask about …" prompts: a code range has no title of its own, so
    /// the composer and the suggestions header both fall back to a generic phrase for it.
    nonisolated static func subjectPhrase(for resolved: ResolvedSubject) -> String {
        resolved.kind == .code ? "this code" : resolved.title
    }

    /// Whether the composer's send affordance is enabled: a draft that's only spaces or
    /// tabs has nothing to send.
    nonisolated static func canSend(_ draft: String) -> Bool {
        !draft.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// The code reference to offer pinning via "Include the code you're viewing", if any.
    /// Only offered when the reviewer is looking at evidence that isn't already pinned to
    /// this thread and isn't the thread's own subject (that would be a redundant button).
    nonisolated static func evidenceToOffer(current: NavigationTarget, pinnedRefs: [CodeRef], subject: ReviewSubject) -> CodeRef? {
        guard case .evidence(let ref) = current, !pinnedRefs.contains(ref), subject != .codeRef(ref) else { return nil }
        return ref
    }

    /// Whether the pinned-refs / expansion chip row has anything to show.
    nonisolated static func showsContextChips(expansions: [ContextExpansion], pinnedRefs: [CodeRef]) -> Bool {
        !expansions.isEmpty || !pinnedRefs.isEmpty
    }

    /// The first few summary lines of the resolved subject, the first flagged as the lead.
    nonisolated static func summaryLines(for resolved: ResolvedSubject) -> [ChatSummaryLine] {
        resolved.summary.prefix(summaryLineLimit).enumerated().map { ChatSummaryLine(id: $0.offset, text: $0.element) }
    }

    /// The title a conversation gets in the conversations menu.
    static func menuTitle(for conversation: Conversation, in graph: PRGraph) -> String {
        graph.resolve(conversation.subject)?.title ?? "Conversation"
    }

    /// The activity caption under a streaming answer.
    nonisolated static func activityText(_ activity: String?) -> String {
        activity ?? "thinking"
    }

    nonisolated static func expansionSymbol(on: Bool) -> String { on ? "checkmark" : "plus" }

    nonisolated static func expansionHelp(_ expansion: ContextExpansion, on: Bool) -> String {
        on ? "Included in the next answer" : "Include \(expansion.label.lowercased()) in the next answer"
    }

    /// Flips an expansion chip on or off for the next answer.
    @MainActor static func toggle(_ expansion: ContextExpansion, in conversation: Conversation) {
        if conversation.expansions.contains(expansion) {
            conversation.expansions.remove(expansion)
        } else {
            conversation.expansions.insert(expansion)
        }
    }

    /// Removes a pinned code reference from the conversation.
    @MainActor static func unpin(_ ref: CodeRef, in conversation: Conversation) {
        conversation.pinnedRefs.removeAll { $0 == ref }
    }

    /// Accepts a cited path when it is a real file in the checkout, or when it uniquely
    /// names a file the review model cites (models often write just `Listener.java:353`).
    nonisolated static func resolvePath(_ path: String, checkoutRoot: URL?, citedPaths: [String]) -> String? {
        if let checkoutRoot, FileManager.default.fileExists(atPath: checkoutRoot.appendingPathComponent(path).path) {
            return path
        }
        if citedPaths.contains(path) { return path }
        let matches = citedPaths.filter { $0.hasSuffix("/" + path) }
        return matches.count == 1 ? matches[0] : nil
    }

    enum LinkOutcome: Equatable { case handled, system }

    /// Routes a tapped link: code citations open the evidence, node links open the node's
    /// detail page, anything else is left to the system.
    @MainActor
    static func handle(_ url: URL, store: GraphStore, graph: PRGraph) -> LinkOutcome {
        guard let target = ChatLinks.target(for: url) else { return .system }
        switch target {
        case .code(let ref):
            store.navigate(to: .evidence(ref))
        case .node(let subject):
            if let destination = graph.resolve(subject)?.detailTarget { store.navigate(to: destination) }
        }
        return .handled
    }
}
