import Foundation
import Testing

@testable import Contour

struct ScriptedHarness: Harness {
    var script: String
    var failArguments = false

    var id: HarnessID { .pi }
    var executable: String { "/bin/sh" }

    func arguments(
        prompt: String, contextFile: String, tier: AnalysisTier, systemPrompt: String
    ) throws -> [String] {
        if failArguments {
            throw HarnessError.contextFileUnreadable(contextFile, underlying: CocoaError(.fileNoSuchFile))
        }
        return ["-c", script]
    }

    func interpret(_ line: String) -> HarnessEvent? {
        if line.hasPrefix("P:") { return .progress(String(line.dropFirst(2))) }
        if line.hasPrefix("D:") { return .textDelta(String(line.dropFirst(2))) }
        if line.hasPrefix("F:") { return .finalText(String(line.dropFirst(2))) }
        return nil
    }
}

struct ConversationServiceRespondTests {
    private func makeRoot() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("conv-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func service(_ harness: ScriptedHarness, root: URL) -> ConversationService {
        ConversationService(
            harness: harness,
            checkout: RepoCheckout(rootDir: root, headSha: "h", baseSha: "b", symbolIndexPath: nil))
    }

    private func collect(_ stream: AsyncThrowingStream<ConversationEvent, Error>) async throws -> [ConversationEvent] {
        var events: [ConversationEvent] = []
        for try await event in stream { events.append(event) }
        return events
    }

    @Test func respondStreamsActivityDeltasAndTheFinalAnswerAndWritesTheContextFile() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        let harness = ScriptedHarness(script: "printf 'P:reading\\nD:Hel\\nD:lo\\nignored\\nF:Hello\\n'")
        let events = try await collect(
            service(harness, root: root).respond(
                conversationId: id, contextDocument: "the context", history: [], question: "Hi?"))
        #expect(events == [.activity("reading"), .delta("Hel"), .delta("lo"), .final("Hello")])
        let file = root.appendingPathComponent(".contour-chat-\(id.uuidString.prefix(8)).md")
        #expect(try String(contentsOf: file, encoding: .utf8) == "the context")
    }

    @Test func respondFailsWithEmptyResponseWhenNoFinalTextArrives() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let harness = ScriptedHarness(script: "printf 'D:partial\\n'")
        do {
            _ = try await collect(
                service(harness, root: root).respond(
                    conversationId: UUID(), contextDocument: "c", history: [], question: "?"))
            Issue.record("expected an error")
        } catch let error as ConversationError {
            #expect(error.errorDescription == "pi finished without an answer.")
        }
    }

    @Test func respondFailsWithEmptyResponseWhenTheFinalTextIsEmpty() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let harness = ScriptedHarness(script: "printf 'F:\\n'")
        await #expect(throws: ConversationError.self) {
            _ = try await collect(
                service(harness, root: root).respond(
                    conversationId: UUID(), contextDocument: "c", history: [], question: "?"))
        }
    }

    @Test func respondSurfacesAnArgumentBuildingFailure() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let harness = ScriptedHarness(script: "true", failArguments: true)
        await #expect(throws: HarnessError.self) {
            _ = try await collect(
                service(harness, root: root).respond(
                    conversationId: UUID(), contextDocument: "c", history: [], question: "?"))
        }
    }

    @Test func respondSurfacesAFailureToWriteTheContextFile() async throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("absent-\(UUID().uuidString)")
        let harness = ScriptedHarness(script: "true")
        await #expect(throws: (any Error).self) {
            _ = try await collect(
                service(harness, root: missing).respond(
                    conversationId: UUID(), contextDocument: "c", history: [], question: "?"))
        }
    }

    @Test func stoppingConsumptionEarlyEndsTheStreamAfterTheFirstEvent() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let harness = ScriptedHarness(script: "printf 'P:first\\n'; sleep 30")
        let stream = service(harness, root: root).respond(
            conversationId: UUID(), contextDocument: "c", history: [], question: "?")
        var first: ConversationEvent?
        for try await event in stream {
            first = event
            break
        }
        #expect(first == .activity("first"))
    }
}
