import Foundation
import Observation

struct ChatMessage: Identifiable, Hashable, Sendable {
    enum Role: Hashable, Sendable { case user, assistant }

    let id = UUID()
    var role: Role
    var text: String
    var isStreaming = false
    var error: String?
}

@Observable
@MainActor
final class Conversation: Identifiable {
    let id = UUID()
    let subject: ReviewSubject
    let createdAt = Date()
    var expansions: Set<ContextExpansion> = []
    var pinnedRefs: [CodeRef] = []
    var messages: [ChatMessage] = []
    var draft = ""
    var activity: String?
    var isResponding: Bool { task != nil }

    @ObservationIgnored fileprivate var task: Task<Void, Never>?

    init(subject: ReviewSubject) {
        self.subject = subject
    }
}

@Observable
@MainActor
final class ConversationStore {
    private(set) var conversations: [Conversation] = []
    var activeId: UUID?
    var isPresented = false
    private(set) var focusRequest = 0

    var active: Conversation? { conversations.first { $0.id == activeId } }

    var discussedConsiderationIds: Set<String> {
        Set(conversations.compactMap { c in
            guard case .consideration(let id) = c.subject, c.messages.contains(where: { $0.role == .user }) else { return nil }
            return id
        })
    }

    @discardableResult
    func open(_ subject: ReviewSubject) -> Conversation {
        let conversation = conversations.first { $0.subject == subject } ?? {
            let c = Conversation(subject: subject)
            conversations.insert(c, at: 0)
            return c
        }()
        activeId = conversation.id
        isPresented = true
        focusRequest += 1
        return conversation
    }

    func close() { isPresented = false }

    func remove(_ conversation: Conversation) {
        conversation.task?.cancel()
        conversations.removeAll { $0.id == conversation.id }
        if activeId == conversation.id { activeId = conversations.first?.id }
        if conversations.isEmpty { isPresented = false }
    }

    func reset() {
        conversations.forEach { $0.task?.cancel() }
        conversations = []
        activeId = nil
        isPresented = false
    }

    func pin(_ ref: CodeRef, in conversation: Conversation) {
        guard !conversation.pinnedRefs.contains(ref) else { return }
        conversation.pinnedRefs.append(ref)
        focusRequest += 1
    }

    func cancel(_ conversation: Conversation) {
        conversation.task?.cancel()
    }

    @MainActor
    func send(_ text: String, in conversation: Conversation, graph: PRGraph, checkout: RepoCheckout?, harnessID: HarnessID?) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !conversation.isResponding else { return }
        let history = conversation.messages
        conversation.messages.append(ChatMessage(role: .user, text: question))
        conversation.messages.append(ChatMessage(role: .assistant, text: "", isStreaming: true))
        conversation.draft = ""
        let replyId = conversation.messages[conversation.messages.count - 1].id

        guard let checkout, let harnessID, let resolved = graph.resolve(conversation.subject) else {
            update(conversation, replyId) {
                $0.isStreaming = false
                $0.error = checkout == nil ? ConversationError.noCheckout.localizedDescription
                    : "No AI harness selected. Pick one in Settings (⌘,)."
            }
            return
        }

        let expansions = conversation.expansions
        let pinned = conversation.pinnedRefs
        let service = ConversationService(
            harness: HarnessFactory.make(harnessID, contextDirectory: checkout.rootDir),
            checkout: checkout
        )

        conversation.activity = "reading the review context"
        conversation.task = Task { @MainActor [weak self, weak conversation] in
            guard let conversation else { return }
            defer {
                conversation.task = nil
                conversation.activity = nil
                self?.update(conversation, replyId) { $0.isStreaming = false }
            }
            let excerpts = await Self.excerpts(for: resolved, expansions: expansions, pinned: pinned, checkout: checkout)
            let document = ChatContextBuilder.document(
                graph: graph, resolved: resolved, expansions: expansions, pinnedRefs: pinned, excerpts: excerpts
            )
            var sawToolSinceText = false
            do {
                for try await event in service.respond(
                    conversationId: conversation.id, contextDocument: document, history: history, question: question
                ) {
                    switch event {
                    case .activity(let detail):
                        conversation.activity = detail
                        sawToolSinceText = true
                    case .delta(let fragment):
                        self?.update(conversation, replyId) {
                            if sawToolSinceText { $0.text = "" }
                            $0.text += fragment
                        }
                        sawToolSinceText = false
                    case .final(let answer):
                        self?.update(conversation, replyId) { $0.text = answer }
                    }
                }
            } catch is CancellationError {
                self?.update(conversation, replyId) { if $0.text.isEmpty { $0.error = "Stopped." } }
            } catch {
                if Task.isCancelled {
                    self?.update(conversation, replyId) { if $0.text.isEmpty { $0.error = "Stopped." } }
                } else {
                    self?.update(conversation, replyId) { $0.error = error.localizedDescription }
                }
            }
        }
    }

    private func update(_ conversation: Conversation, _ id: UUID, _ change: (inout ChatMessage) -> Void) {
        guard let i = conversation.messages.firstIndex(where: { $0.id == id }) else { return }
        change(&conversation.messages[i])
    }

    static func excerpts(
        for resolved: ResolvedSubject, expansions: Set<ContextExpansion>, pinned: [CodeRef], checkout: RepoCheckout
    ) async -> [(ref: CodeRef, text: String)] {
        var refs = pinned
        if resolved.kind == .code || expansions.contains(.implementation) {
            refs += resolved.refs.prefix(6)
        }
        let repo = RepoContextService()
        var out: [(CodeRef, String)] = []
        for ref in unique(refs).prefix(8) {
            let end = min(ref.endLine, ref.startLine + 80)
            guard let result = try? await repo.readLines(
                in: checkout, path: ref.path, startLine: ref.startLine, endLine: end, contextLines: 3, side: ref.side
            ) else { continue }
            out.append((ref, result.lines.map { "\($0.number)  \($0.text)" }.joined(separator: "\n")))
        }
        return out
    }
}
