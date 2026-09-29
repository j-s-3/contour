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

    @Test func mockOptionsParseLatencyScaleAndFailStageFromEnvironment() {
        let parsed = AnalysisService.MockOptions.parse([
            "CONTOUR_MOCK_LATENCY": "0.5", "CONTOUR_MOCK_FAIL_STAGE": "judgment",
        ])
        #expect(parsed.latencyScale == 0.5)
        #expect(parsed.failStage == .judgment)
    }

    @Test func mockOptionsIgnoreNonPositiveLatencyAndUnknownStages() {
        let parsed = AnalysisService.MockOptions.parse([
            "CONTOUR_MOCK_LATENCY": "0", "CONTOUR_MOCK_FAIL_STAGE": "nonsense",
        ])
        #expect(parsed.latencyScale == nil)
        #expect(parsed.failStage == nil)
        #expect(AnalysisService.MockOptions.parse([:]).latencyScale == nil)
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

struct AnalysisServiceHarnessPathTests {
    private let cwd = URL(fileURLWithPath: NSTemporaryDirectory())
    private let items = #"{"items":[{"n":1},{"n":2}]}"#

    private func run(
        _ harness: ScriptedHarness, streaming: String? = nil,
        onElement: @escaping @Sendable ([String: Any]) -> Void = { _ in },
        onProgress: @escaping @Sendable (AnalysisProgress) -> Void = { _ in }
    ) async throws -> [String: Any] {
        try await AnalysisService(harness: harness).runStage(
            prompt: "p", cwd: cwd, tier: .fast, stage: .understanding, streaming: streaming,
            onElement: onElement, onProgress: onProgress)
    }

    @Test func finalTextFromTheHarnessStreamIsParsedIntoTheStageResponse() async throws {
        let lines = OSAllocatedUnfairLock(initialState: [String]())
        let result = try await run(
            ScriptedHarness(script: "printf 'P:reading\\n'; printf 'ignored\\n'; printf 'F:%s\\n' '{\"a\":1}'"),
            onProgress: { progress in lines.withLock { $0.append(progress.detail) } })
        #expect(result["a"] as? Int == 1)
        #expect(lines.withLock { $0 } == ["reading"])
    }

    @Test func streamingStagesEmitArrayElementsFromTextDeltas() async throws {
        let seen = OSAllocatedUnfairLock(initialState: [Int]())
        let script = "printf 'D:%s\\n' '\(items)'; printf 'F:%s\\n' '\(items)'"
        let result = try await run(
            ScriptedHarness(script: script), streaming: "items",
            onElement: { element in
                if let n = element["n"] as? Int { seen.withLock { $0.append(n) } }
            })
        #expect(seen.withLock { $0 } == [1, 2])
        #expect((result["items"] as? [[String: Any]])?.count == 2)
    }

    @Test func emptyFinalTextThrowsEmptyResponse() async {
        do {
            _ = try await run(ScriptedHarness(script: "printf 'F:\\n'"))
            Issue.record("expected failure")
        } catch AnalysisServiceError.emptyResponse(let name) {
            #expect(name == "pi")
        } catch {
            Issue.record("unexpected \(error)")
        }
    }

    @Test func missingFinalTextThrowsAnAnalysisServiceError() async {
        await #expect(throws: AnalysisServiceError.self) {
            try await run(ScriptedHarness(script: "printf 'P:hi\\n'; exit 3"))
        }
    }

    @Test func argumentBuildingFailuresPropagate() async {
        await #expect(throws: HarnessError.self) {
            try await run(ScriptedHarness(script: "true", failArguments: true))
        }
    }

    @Test func malformedJSONIsRetriedOnceAndThenSucceeds() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("analysis-retry-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let marker = dir.appendingPathComponent("seen").path
        let script =
            "if [ -e '\(marker)' ]; then printf 'F:%s\\n' '{\"ok\":true}'; "
            + "else touch '\(marker)'; printf 'F:not json\\n'; fi"
        let lines = OSAllocatedUnfairLock(initialState: [String]())
        let result = try await run(
            ScriptedHarness(script: script),
            onProgress: { progress in lines.withLock { $0.append(progress.detail) } })
        #expect(result["ok"] as? Bool == true)
        #expect(lines.withLock { $0 } == ["model returned malformed JSON, retrying once"])
    }

    @Test func malformedJSONTwiceSurfacesNotJSON() async {
        do {
            _ = try await run(ScriptedHarness(script: "printf 'F:still not json\\n'"))
            Issue.record("expected failure")
        } catch AnalysisServiceError.notJSON(let name, let raw) {
            #expect(name == "pi")
            #expect(raw == "still not json")
        } catch {
            Issue.record("unexpected \(error)")
        }
    }

    @Test func stageDumpIsWrittenWhenRequestedByEnvironment() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("analysis-dump-\(UUID().uuidString)", isDirectory: true)
        defer {
            unsetenv("CONTOUR_DUMP_STAGES")
            try? FileManager.default.removeItem(at: dir)
        }
        setenv("CONTOUR_DUMP_STAGES", dir.path, 1)
        _ = try await run(ScriptedHarness(script: "printf 'F:%s\\n' '{\"a\":1}'"))
        unsetenv("CONTOUR_DUMP_STAGES")
        let data = try Data(contentsOf: dir.appendingPathComponent("understanding.json"))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?["a"] as? Int == 1)
    }
}
