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

/// One contextual thread, anchored to the thing it was opened on. The subject never
/// changes — asking about something else opens (or returns to) that thing's own thread —
/// so every conversation keeps the context it started with.
/// `@MainActor` for the same reason as `GraphStore`: `send(_:in:...)`'s background `Task`
/// and this store's other mutating methods (`open`, `remove`, `pin`, ...) touch the same
/// stored properties, so leaving only `send` isolated is a real cross-thread race once
/// anything drives both concurrently, not just a theoretical one.
@Observable
@MainActor
final class Conversation: Identifiable {
    let id = UUID()
    let subject: ReviewSubject
    let createdAt = Date()
    var expansions: Set<ContextExpansion> = []
    /// Code ranges the reviewer explicitly brought into this thread ("Why this line?").
    var pinnedRefs: [CodeRef] = []
    var messages: [ChatMessage] = []
    var draft = ""
    /// The live progress line while the harness works, nil when idle.
    var activity: String?
    var isResponding: Bool { task != nil }

    @ObservationIgnored fileprivate var task: Task<Void, Never>?

    init(subject: ReviewSubject) {
        self.subject = subject
    }
}

/// Every contextual conversation for the PR under review. Lives as long as the review
/// session (reset when a new PR loads), independent of navigation — moving around the
/// review, opening code, and coming back never loses a thread.
@Observable
@MainActor
final class ConversationStore {
    private(set) var conversations: [Conversation] = []
    var activeId: UUID?
    var isPresented = false
    /// Bumped whenever the composer should take focus (opening a thread, asking again).
    private(set) var focusRequest = 0

    var active: Conversation? { conversations.first { $0.id == activeId } }

    /// The Overview questions the reviewer has actually asked about — a thread they wrote
    /// in, not one merely opened. A question with no decision to judge it on is resolved
    /// this way (`PRGraph.isResolved`).
    var discussedConsiderationIds: Set<String> {
        Set(conversations.compactMap { c in
            guard case .consideration(let id) = c.subject, c.messages.contains(where: { $0.role == .user }) else { return nil }
            return id
        })
    }

    /// Opens the thread for a subject, reusing an existing one so asking about the same
    /// box twice continues the same conversation instead of starting over.
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

    /// Sends one question. The context document is rebuilt from the graph every turn, so a
    /// reviewer who expands scope or pins a line mid-thread gets it on the very next answer.
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
            // Text streamed before a tool call is the model thinking aloud ("let me check
            // the listener"); the real answer comes after the last tool call. So a new
            // tool call clears the preview rather than appending to it.
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

    /// Code is only inlined when the reviewer is looking at code: a pinned range, a code
    /// reference subject, or the Implementation expansion. Everything else is left for the
    /// harness to read on demand, which keeps the first answer at the concept's level.
    private static func excerpts(
        for resolved: ResolvedSubject, expansions: Set<ContextExpansion>, pinned: [CodeRef], checkout: RepoCheckout
    ) async -> [(ref: CodeRef, text: String)] {
        var refs = pinned
        if resolved.kind == .code || expansions.contains(.implementation) {
            refs += resolved.refs.prefix(6)
        }
        let repo = RepoContextService()
        var out: [(CodeRef, String)] = []
        for ref in unique(refs).prefix(8) {
            // Clamp pathological ranges: an excerpt is a view of the code, not the file.
            let end = min(ref.endLine, ref.startLine + 80)
            guard let result = try? await repo.readLines(
                in: checkout, path: ref.path, startLine: ref.startLine, endLine: end, contextLines: 3, side: ref.side
            ) else { continue }
            out.append((ref, result.lines.map { "\($0.number)  \($0.text)" }.joined(separator: "\n")))
        }
        return out
    }
}
