import Foundation
import Testing

@testable import Contour

@MainActor
struct ConversationStoreTests {
    struct Failure: LocalizedError {
        var errorDescription: String? { "the harness fell over" }
    }

    let graph = ContourSampleData.publishTriggeredReindex
    let checkout = RepoCheckout(
        rootDir: FileManager.default.temporaryDirectory, headSha: "h", baseSha: "b", symbolIndexPath: nil)

    private func scripted(
        _ events: [ConversationEvent], finishing error: (any Error)? = nil
    ) -> ConversationStore.Responder {
        { _, _, _, _, _, _ in
            AsyncThrowingStream { continuation in
                for event in events { continuation.yield(event) }
                continuation.finish(throwing: error)
            }
        }
    }

    private func settle(_ conversation: Conversation) async {
        while conversation.isResponding { try? await Task.sleep(for: .milliseconds(2)) }
    }

    private func ask(
        _ store: ConversationStore, _ question: String = "Why?", in conversation: Conversation
    ) async {
        store.send(question, in: conversation, graph: graph, checkout: checkout, harnessID: .claude)
        await settle(conversation)
    }

    @Test func sendAppendsTheQuestionThenStreamsTheAnswerIntoTheReply() async {
        let store = ConversationStore(
            responder: scripted([.delta("Because "), .delta("queues."), .final("Because queues.")]))
        let conversation = store.open(.decision("index-on-publish"))
        conversation.draft = "typed"

        store.send("  Why?  ", in: conversation, graph: graph, checkout: checkout, harnessID: .claude)
        #expect(conversation.draft.isEmpty)
        #expect(conversation.isResponding)
        #expect(conversation.activity == "reading the review context")
        #expect(conversation.messages.map(\.role) == [.user, .assistant])
        #expect(conversation.messages[0].text == "Why?")
        #expect(conversation.messages[1].isStreaming)

        await settle(conversation)
        #expect(conversation.messages[1].text == "Because queues.")
        #expect(!conversation.messages[1].isStreaming)
        #expect(conversation.messages[1].error == nil)
        #expect(conversation.activity == nil)
    }

    @Test func aDeltaAfterAToolCallReplacesTheEarlierNarration() async {
        let store = ConversationStore(
            responder: scripted([
                .delta("Let me look. "), .activity("reading a.swift"), .delta("Found it."), .delta(" Done."),
            ])
        )
        let conversation = store.open(.decision("index-on-publish"))
        await ask(store, in: conversation)
        #expect(conversation.messages[1].text == "Found it. Done.")
    }

    @Test func aFinalAnswerOverridesWhateverStreamed() async {
        let store = ConversationStore(responder: scripted([.delta("draft"), .final("authoritative")]))
        let conversation = store.open(.decision("index-on-publish"))
        await ask(store, in: conversation)
        #expect(conversation.messages[1].text == "authoritative")
    }

    @Test func aFailureIsRecordedOnTheReplyAndKeepsPartialText() async {
        let store = ConversationStore(responder: scripted([.delta("partial")], finishing: Failure()))
        let conversation = store.open(.decision("index-on-publish"))
        await ask(store, in: conversation)
        #expect(conversation.messages[1].error == "the harness fell over")
        #expect(conversation.messages[1].text == "partial")
        #expect(!conversation.messages[1].isStreaming)
        #expect(!conversation.isResponding)
    }

    @Test func aCancellationErrorBeforeAnyTextReadsAsStopped() async {
        let store = ConversationStore(responder: scripted([], finishing: CancellationError()))
        let conversation = store.open(.decision("index-on-publish"))
        await ask(store, in: conversation)
        #expect(conversation.messages[1].error == "Stopped.")
    }

    @Test func aCancellationErrorAfterSomeTextKeepsTheTextWithoutAnError() async {
        let store = ConversationStore(responder: scripted([.delta("half an answer")], finishing: CancellationError()))
        let conversation = store.open(.decision("index-on-publish"))
        await ask(store, in: conversation)
        #expect(conversation.messages[1].text == "half an answer")
        #expect(conversation.messages[1].error == nil)
    }

    @Test func stoppingMidStreamReportsStoppedEvenWhenTheStreamFailsWithAnotherError() async {
        let gate = GatedStream()
        let store = ConversationStore(responder: { _, _, _, _, _, _ in gate.stream })
        let conversation = store.open(.decision("index-on-publish"))
        store.send("Why?", in: conversation, graph: graph, checkout: checkout, harnessID: .pi)

        store.cancel(conversation)
        gate.fail(Failure())
        await settle(conversation)
        #expect(conversation.messages[1].error == "Stopped.")
    }

    @Test func stoppingAfterTextArrivedLeavesNoError() async {
        let gate = GatedStream()
        let store = ConversationStore(responder: { _, _, _, _, _, _ in gate.stream })
        let conversation = store.open(.decision("index-on-publish"))
        store.send("Why?", in: conversation, graph: graph, checkout: checkout, harnessID: .pi)

        gate.yield(.delta("some"))
        while conversation.messages[1].text.isEmpty { try? await Task.sleep(for: .milliseconds(2)) }
        store.cancel(conversation)
        gate.fail(Failure())
        await settle(conversation)
        #expect(conversation.messages[1].text == "some")
        #expect(conversation.messages[1].error == nil)
    }

    @Test func aSecondQuestionWhileRespondingIsIgnored() async {
        let gate = GatedStream()
        let store = ConversationStore(responder: { _, _, _, _, _, _ in gate.stream })
        let conversation = store.open(.decision("index-on-publish"))
        store.send("First", in: conversation, graph: graph, checkout: checkout, harnessID: .pi)
        store.send("Second", in: conversation, graph: graph, checkout: checkout, harnessID: .pi)
        #expect(conversation.messages.count == 2)

        gate.yield(.final("ok"))
        gate.finish()
        await settle(conversation)
        #expect(conversation.messages[1].text == "ok")
    }

    @Test func priorTurnsAreHandedToTheResponderAsHistory() async {
        let echo: ConversationStore.Responder = { _, _, history, question, harnessID, _ in
            AsyncThrowingStream { continuation in
                continuation.yield(.final("\(history.count)|\(question)|\(harnessID.rawValue)"))
                continuation.finish()
            }
        }
        let store = ConversationStore(responder: echo)
        let conversation = store.open(.decision("index-on-publish"))
        await ask(store, "one", in: conversation)
        await ask(store, "two", in: conversation)
        #expect(conversation.messages.count == 4)
        #expect(conversation.messages[1].text == "0|one|claude")
        #expect(conversation.messages[3].text == "2|two|claude")
    }

    @Test func theResponderReceivesTheContextDocumentForTheSelectedSubject() async {
        let box = DocumentBox()
        let capture: ConversationStore.Responder = { _, contextDocument, _, _, _, _ in
            box.set(contextDocument)
            return AsyncThrowingStream { $0.finish() }
        }
        let store = ConversationStore(responder: capture)
        let conversation = store.open(.decision("index-on-publish"))
        await ask(store, in: conversation)
        #expect(box.value?.contains("← selected (Decision)") == true)
    }

    @Test func removingAConversationMidStreamCancelsItsTask() async {
        let gate = GatedStream()
        let store = ConversationStore(responder: { _, _, _, _, _, _ in gate.stream })
        let conversation = store.open(.decision("index-on-publish"))
        store.send("Why?", in: conversation, graph: graph, checkout: checkout, harnessID: .pi)
        store.remove(conversation)
        gate.finish()
        await settle(conversation)
        #expect(store.conversations.isEmpty)
    }

    @Test func resetCancelsEveryInFlightTask() async {
        let gate = GatedStream()
        let store = ConversationStore(responder: { _, _, _, _, _, _ in gate.stream })
        let conversation = store.open(.decision("index-on-publish"))
        store.send("Why?", in: conversation, graph: graph, checkout: checkout, harnessID: .pi)
        store.reset()
        gate.finish()
        await settle(conversation)
        #expect(store.conversations.isEmpty)
    }

    @Test func openingTheSameSubjectTwiceReusesTheThreadAndRequestsFocus() {
        let store = ConversationStore()
        let first = store.open(.decision("d1"))
        let focus = store.focusRequest
        let again = store.open(.decision("d1"))
        #expect(first === again)
        #expect(store.conversations.count == 1)
        #expect(store.active === first)
        #expect(store.focusRequest == focus + 1)
    }
}

final class DocumentBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String?
    var value: String? { lock.withLock { stored } }
    func set(_ text: String) { lock.withLock { stored = text } }
}

final class GatedStream: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncThrowingStream<ConversationEvent, Error>.Continuation?
    private(set) var stream: AsyncThrowingStream<ConversationEvent, Error>!

    init() {
        var captured: AsyncThrowingStream<ConversationEvent, Error>.Continuation?
        stream = AsyncThrowingStream { captured = $0 }
        continuation = captured
    }

    func yield(_ event: ConversationEvent) { lock.withLock { _ = continuation?.yield(event) } }
    func finish() { lock.withLock { continuation?.finish() } }
    func fail(_ error: any Error) { lock.withLock { continuation?.finish(throwing: error) } }
}
