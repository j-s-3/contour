import Foundation
import Testing
import os

@testable import Contour

struct AnalysisServiceTests {
    @Test func extractJSONObjectHandlesPlainCodeFencedAndEmbeddedJSON() {
        #expect(AnalysisService.extractJSONObject(from: #"{"a":1}"#)?["a"] as? Int == 1)
        #expect(AnalysisService.extractJSONObject(from: "```json\n{\"a\":1}\n```")?["a"] as? Int == 1)
        #expect(AnalysisService.extractJSONObject(from: "```\n{\"a\":1}\n```")?["a"] as? Int == 1)
        #expect(AnalysisService.extractJSONObject(from: "Here you go: {\"a\":1} thanks")?["a"] as? Int == 1)
        #expect(AnalysisService.extractJSONObject(from: "not json at all") == nil)
        #expect(AnalysisService.extractJSONObject(from: "{unbalanced") == nil)
    }

    @Test func analysisServiceErrorMessagesAreReviewerAndTechnicalFacing() {
        let empty = AnalysisServiceError.emptyResponse(harness: "claude")
        #expect(empty.reviewerReason == "The model didn't return an answer.")
        #expect(empty.errorDescription == "claude produced no final response for this stage")

        let notJSON = AnalysisServiceError.notJSON(harness: "pi", raw: "garbage")
        #expect(notJSON.reviewerReason == "The model's answer wasn't readable.")
        #expect(notJSON.errorDescription == "pi's response wasn't valid JSON: garbage")

        struct DummyError: Error, LocalizedError { var errorDescription: String? { "boom" } }
        let failed = AnalysisServiceError.processFailed(harness: "claude", DummyError())
        #expect(failed.reviewerReason == "claude stopped with an error.")
        #expect(failed.errorDescription == "claude invocation failed: boom")
    }

    @Test func analysisTierThinkingEffortMatchesItsWeight() {
        #expect(AnalysisTier.fast.thinking == "low")
        #expect(AnalysisTier.strong.thinking == "high")
    }

    @Test func mockOptionsFromEnvironmentIsNilWhenMockAnalysisIsUnset() {
        #expect(ProcessInfo.processInfo.environment["CONTOUR_MOCK_ANALYSIS"] != "1")
        #expect(AnalysisService.MockOptions.fromEnvironment == nil)
    }
}

struct AnalysisServiceMockPathTests {
    @Test func mockPathReturnsCannedFixtureImmediatelyWhenUnscaled() async throws {
        let service = AnalysisService(harness: PiHarness(), mock: AnalysisService.MockOptions())
        let progressLines = OSAllocatedUnfairLock(initialState: [String]())
        let result = try await service.runStage(
            prompt: "analyze", cwd: URL(fileURLWithPath: NSTemporaryDirectory()),
            tier: .fast, stage: .understanding,
            onProgress: { progress in progressLines.withLock { $0.append(progress.detail) } }
        )
        #expect(result["intent"] != nil)
        #expect(progressLines.withLock { $0 } == ["using synthetic data (CONTOUR_MOCK_ANALYSIS=1)"])
    }

    @Test func mockPathStreamsElementsOverTimeWhenLatencyIsScaled() async throws {
        let service = AnalysisService(
            harness: PiHarness(),
            mock: AnalysisService.MockOptions(latencyScale: 0.0005)
        )
        let streamed = StreamedElementBox()
        let result = try await service.runStage(
            prompt: "analyze", cwd: URL(fileURLWithPath: NSTemporaryDirectory()),
            tier: .strong, stage: .decisions, streaming: "decisions",
            onElement: { element in streamed.append(element) },
            onProgress: { _ in }
        )
        let finalDecisions = try #require(result["decisions"] as? [[String: Any]])
        #expect(!finalDecisions.isEmpty)
        #expect(streamed.count == finalDecisions.count)
    }

    @Test func mockPathScalesLatencyForNonStreamedStagesToo() async throws {
        let service = AnalysisService(
            harness: ClaudeHarness(contextDirectory: URL(fileURLWithPath: NSTemporaryDirectory())),
            mock: AnalysisService.MockOptions(latencyScale: 0.0005)
        )
        let result = try await service.runStage(
            prompt: "analyze", cwd: URL(fileURLWithPath: NSTemporaryDirectory()),
            tier: .fast, stage: .ticket, onProgress: { _ in }
        )
        #expect(result.isEmpty)
    }

    @Test func mockFailStageFailsOnlyTheFirstTimeThisProcessRunsThatStage() async throws {
        let service = AnalysisService(
            harness: PiHarness(),
            mock: AnalysisService.MockOptions(failStage: .judgment)
        )
        let cwd = URL(fileURLWithPath: NSTemporaryDirectory())

        await #expect(throws: AnalysisServiceError.self) {
            try await service.runStage(prompt: "p", cwd: cwd, tier: .strong, stage: .judgment, onProgress: { _ in })
        }
        let result = try await service.runStage(
            prompt: "p", cwd: cwd, tier: .strong, stage: .judgment, onProgress: { _ in })
        #expect(!result.isEmpty)
    }
}

private final class StreamedElementBox: @unchecked Sendable {
    private let lock = NSLock()
    private var elements: [[String: Any]] = []
    func append(_ element: [String: Any]) { lock.withLock { elements.append(element) } }
    var count: Int { lock.withLock { elements.count } }
}
