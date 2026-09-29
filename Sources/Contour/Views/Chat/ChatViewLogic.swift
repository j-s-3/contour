import Foundation

struct ChatSummaryLine: Identifiable, Equatable {
    let id: Int
    let text: String
    var isLead: Bool { id == 0 }
}

enum ChatViewLogic {
    nonisolated static let summaryLineLimit = 4

    nonisolated static func subjectPhrase(for resolved: ResolvedSubject) -> String {
        resolved.kind == .code ? "this code" : resolved.title
    }

    nonisolated static func canSend(_ draft: String) -> Bool {
        !draft.trimmingCharacters(in: .whitespaces).isEmpty
    }

    nonisolated static func evidenceToOffer(current: NavigationTarget, pinnedRefs: [CodeRef], subject: ReviewSubject)
        -> CodeRef?
    {
        guard case .evidence(let ref) = current, !pinnedRefs.contains(ref), subject != .codeRef(ref) else { return nil }
        return ref
    }

    nonisolated static func showsContextChips(expansions: [ContextExpansion], pinnedRefs: [CodeRef]) -> Bool {
        !expansions.isEmpty || !pinnedRefs.isEmpty
    }

    nonisolated static func summaryLines(for resolved: ResolvedSubject) -> [ChatSummaryLine] {
        resolved.summary.prefix(summaryLineLimit).enumerated().map { ChatSummaryLine(id: $0.offset, text: $0.element) }
    }

    static func menuTitle(for conversation: Conversation, in graph: PRGraph) -> String {
        graph.resolve(conversation.subject)?.title ?? "Conversation"
    }

    nonisolated static func activityText(_ activity: String?) -> String {
        activity ?? "thinking"
    }

    nonisolated static func expansionSymbol(on: Bool) -> String { on ? "checkmark" : "plus" }

    nonisolated static func expansionHelp(_ expansion: ContextExpansion, on: Bool) -> String {
        on ? "Included in the next answer" : "Include \(expansion.label.lowercased()) in the next answer"
    }

    @MainActor static func toggle(_ expansion: ContextExpansion, in conversation: Conversation) {
        if conversation.expansions.contains(expansion) {
            conversation.expansions.remove(expansion)
        } else {
            conversation.expansions.insert(expansion)
        }
    }

    @MainActor static func unpin(_ ref: CodeRef, in conversation: Conversation) {
        conversation.pinnedRefs.removeAll { $0 == ref }
    }

    nonisolated static func resolvePath(_ path: String, checkoutRoot: URL?, citedPaths: [String]) -> String? {
        if let checkoutRoot, FileManager.default.fileExists(atPath: checkoutRoot.appendingPathComponent(path).path) {
            return path
        }
        if citedPaths.contains(path) { return path }
        let matches = citedPaths.filter { $0.hasSuffix("/" + path) }
        return matches.count == 1 ? matches[0] : nil
    }

    enum LinkOutcome: Equatable { case handled, system }

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
