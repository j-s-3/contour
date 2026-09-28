import Testing
import Foundation
@testable import Contour

/// Fills the gap this repo's coverage series left in `ConversationService.swift`:
/// `turnPrompt`'s history-limit/empty-history/empty-message/per-message-length branches,
/// `mockResponse`'s no-selection and no-code-ref fallbacks, and `respond(...)`'s
/// `CONTOUR_MOCK_ANALYSIS=1` short-circuit (previously only `mockResponse` itself was
/// called directly, never `respond`). The real-harness path in `respond` still isn't
/// exercised: it shells out to a real `pi`/`claude` executable, and this suite never fakes
/// those on `PATH` (per the established `HarnessContractTests` convention — replay
/// captured streams instead of spawning a real CLI).
@Suite(.serialized)
struct ConversationServiceTests {

    // MARK: - turnPrompt

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

    // MARK: - mockResponse fallbacks

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

    // MARK: - respond() mock short-circuit

    @Test func respondShortCircuitsToMockResponseWhenMockAnalysisIsEnabled() async throws {
        setenv("CONTOUR_MOCK_ANALYSIS", "1", 1)
        defer { unsetenv("CONTOUR_MOCK_ANALYSIS") }

        let service = ConversationService(
            harness: ClaudeHarness(),
            checkout: RepoCheckout(rootDir: URL(fileURLWithPath: "/nonexistent"), headSha: "head", baseSha: "base")
        )
        let doc = "## Where the reviewer is\n- **Retry logic** ← selected (Architecture)"
        var sawActivity = false
        var final: String?
        for try await event in service.respond(conversationId: UUID(), contextDocument: doc, history: [], question: "Why retry?") {
            switch event {
            case .activity: sawActivity = true
            case .final(let text): final = text
            case .delta: break
            }
        }
        #expect(sawActivity)
        let unwrapped = try #require(final)
        #expect(unwrapped.contains("Retry logic"))
        #expect(unwrapped.contains("Why retry?"))
    }
}
