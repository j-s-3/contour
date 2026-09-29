import Foundation
import Testing

@testable import Contour

struct ConversationServiceTests {
    @Test func turnPromptWithNoHistoryOmitsTheConversationBlock() {
        let prompt = ConversationService.turnPrompt(history: [], question: "What changed?")
        #expect(!prompt.contains("<conversation_so_far>"))
        #expect(prompt == "Reviewer's question: What changed?")
    }

    @Test func turnPromptDropsMessagesWithEmptyText() {
        let history = [
            ChatMessage(role: .user, text: "Real question"),
            ChatMessage(role: .assistant, text: ""),
        ]
        let prompt = ConversationService.turnPrompt(history: history, question: "Follow-up?")
        #expect(prompt.contains("Reviewer: Real question"))
        #expect(!prompt.contains("You: \n"))
    }

    @Test func turnPromptKeepsOnlyTheMostRecentMessagesUpToTheHistoryLimit() {
        let history = (1...(ConversationService.historyLimit + 3)).map {
            ChatMessage(role: .user, text: "message \($0)")
        }
        let prompt = ConversationService.turnPrompt(history: history, question: "?")
        #expect(!prompt.contains("message 1\n"))
        #expect(!prompt.contains("message 3\n"))
        #expect(prompt.contains("message 4"))
        #expect(prompt.contains("message \(ConversationService.historyLimit + 3)"))
    }

    @Test func turnPromptTruncatesAnOverlongMessage() {
        let long = String(repeating: "x", count: 5_000)
        let history = [ChatMessage(role: .user, text: long)]
        let prompt = ConversationService.turnPrompt(history: history, question: "?")
        #expect(!prompt.contains(long))
        #expect(prompt.contains(String(repeating: "x", count: 4_000)))
    }

    @Test func mockResponseFallsBackToThisWithNoSelectedLine() async throws {
        let doc = "## Nothing selected here\njust prose"
        var final: String?
        for try await event in ConversationService.mockResponse(contextDocument: doc, question: "Why?") {
            if case .final(let text) = event { final = text }
        }
        let unwrapped = try #require(final)
        #expect(unwrapped.contains("about **this**"))
    }

    @Test func mockResponseOmitsTheCodeExampleWithNoRefInTheDocument() async throws {
        let doc = "## Where the reviewer is\n- **Index Queue** ← selected (Architecture)\n\nNo refs here."
        var final: String?
        for try await event in ConversationService.mockResponse(contextDocument: doc, question: "Why?") {
            if case .final(let text) = event { final = text }
        }
        let unwrapped = try #require(final)
        #expect(unwrapped.contains("then point at the code."))
        #expect(!unwrapped.contains("for example"))
    }
}
