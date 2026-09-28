import Foundation
import os
import Testing
@testable import Contour

/// `extractJSONObject`, the three `AnalysisServiceError` message pairs, and `AnalysisTier`
/// aren't reachable through the mock-harness seam (`MockOptions`, used throughout
/// `PipelineConcurrencyTests` and `AnalysisServiceMockPathTests` below) — a mocked stage
/// returns its canned response directly and never reaches `extractJSONObject`, and its one
/// failure mode (`CONTOUR_MOCK_FAIL_STAGE`) only ever throws `.emptyResponse`, never
/// `.notJSON`/`.processFailed` with a real underlying error. These pin the pure pieces
/// directly instead.
struct AnalysisServiceTests {

    @Test func extractJSONObjectHandlesPlainCodeFencedAndEmbeddedJSON() {
        #expect(AnalysisService.extractJSONObject(from: #"{"a":1}"#)?["a"] as? Int == 1)
        #expect(AnalysisService.extractJSONObject(from: "```json\n{\"a\":1}\n```")?["a"] as? Int == 1)
        #expect(AnalysisService.extractJSONObject(from: "```\n{\"a\":1}\n```")?["a"] as? Int == 1)
        // No fences, but the model wrapped the object in prose anyway.
        #expect(AnalysisService.extractJSONObject(from: "Here you go: {\"a\":1} thanks")?["a"] as? Int == 1)
        #expect(AnalysisService.extractJSONObject(from: "not json at all") == nil)
        #expect(AnalysisService.extractJSONObject(from: "{unbalanced") == nil)
    }

    /// `reviewerReason` is what the UI shows; `errorDescription` is the technical account
    /// that stays in the log — both need pinning for all three cases, not just the one
    /// (`notJSON`) the failure-message test happened to check `errorDescription` for.
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

    /// `MockOptions.fromEnvironment` is what `runStageOnce` consults when a caller (the real
    /// pipeline) passes no explicit override. It must not be exercised by mutating
    /// `CONTOUR_MOCK_ANALYSIS` (see this suite's doc comment on why), but the ambient test
    /// process never sets it, so this pins the "mock mode is off" branch: nil, not a crash
    /// or a stale value from some other suite.
    @Test func mockOptionsFromEnvironmentIsNilWhenMockAnalysisIsUnset() {
        #expect(ProcessInfo.processInfo.environment["CONTOUR_MOCK_ANALYSIS"] != "1")
        #expect(AnalysisService.MockOptions.fromEnvironment == nil)
    }
}

/// `runStage`/`runStageOnce`'s real (non-mock) branch invokes `Shell.stream(harness.executable, ...)`,
/// and `executable` resolves through `HarnessID.executable` via a protocol-extension default that
/// isn't part of `Harness`'s requirements — a conforming test type can't override it, so the only
/// way to exercise that branch is to actually spawn `pi`/`claude` off `PATH`. That's exactly what
/// `HarnessContractTests`'s convention (and the ConversationService/ConversationStore coverage
/// PRs) says not to do. `MockOptions`, though, is a seam built for tests: passed to `init(mock:)`
/// it bypasses the environment (and `Shell.stream`) entirely, so this suite drives every branch
/// reachable through it — the immediate-response path, `simulateLatency`'s streamed and
/// non-streamed timing, and the fail-once-per-process `CONTOUR_MOCK_FAIL_STAGE` escape hatch —
/// none of which PR #143 reached.
struct AnalysisServiceMockPathTests {

    /// With no latency scale, the mock path returns the canned fixture immediately (no
    /// `Task.sleep`) and still reports the "using synthetic data" progress line the UI relies
    /// on to tell a reviewer why analysis finished suspiciously fast.
    @Test func mockPathReturnsCannedFixtureImmediatelyWhenUnscaled() async throws {
        let service = AnalysisService(harness: PiHarness(), mock: AnalysisService.MockOptions())
        // `onProgress` is `@Sendable`, so the lines it collects need a lock rather than a
        // captured `var`.
        let progressLines = OSAllocatedUnfairLock(initialState: [String]())
        let result = try await service.runStage(
            prompt: "analyze", cwd: URL(fileURLWithPath: NSTemporaryDirectory()),
            tier: .fast, stage: .understanding,
            onProgress: { progress in progressLines.withLock { $0.append(progress.detail) } }
        )
        #expect(result["intent"] != nil)
        #expect(progressLines.withLock { $0 } == ["using synthetic data (CONTOUR_MOCK_ANALYSIS=1)"])
    }

    /// `CONTOUR_MOCK_LATENCY` makes a mock stage take real (scaled) time and, for a streamed
    /// stage, hand elements to `onElement` one at a time instead of all at once — the whole
    /// point of `simulateLatency`. A tiny scale keeps this fast while still exercising the
    /// per-element sleep loop and the `.decisions` case of its stage/seconds switch.
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
        // Every element handed to `onElement` as it "streamed" must also be in the final,
        // authoritative array — the design invariant that the stream is a preview, never a
        // second source of truth.
        #expect(streamed.count == finalDecisions.count)
    }

    /// A non-streamed stage (no `streaming:` key) still goes through `simulateLatency`, just
    /// with zero elements to hand out — this pins that path (and the "unlisted stage" default
    /// branch of its per-stage `seconds` switch) separately from the streamed case above.
    @Test func mockPathScalesLatencyForNonStreamedStagesToo() async throws {
        let service = AnalysisService(
            harness: ClaudeHarness(contextDirectory: URL(fileURLWithPath: NSTemporaryDirectory())),
            mock: AnalysisService.MockOptions(latencyScale: 0.0005)
        )
        let result = try await service.runStage(
            prompt: "analyze", cwd: URL(fileURLWithPath: NSTemporaryDirectory()),
            tier: .fast, stage: .ticket, onProgress: { _ in }
        )
        // `.ticket` isn't one of `MockAnalysisFixtures`' known stages, so its canned response
        // is the documented empty-object fallback.
        #expect(result.isEmpty)
    }

    /// `CONTOUR_MOCK_FAIL_STAGE` fails a stage exactly once *per process*, not once per call,
    /// so a reviewer can watch a section fail and then retry it without a real broken model.
    /// `.judgment` is used here rather than `.decisions` (which `PipelineConcurrencyTests`
    /// already spends its one-time failure on) so the two suites don't race for the same
    /// entry in the shared, process-wide `mockFailures` set.
    @Test func mockFailStageFailsOnlyTheFirstTimeThisProcessRunsThatStage() async throws {
        let service = AnalysisService(
            harness: PiHarness(),
            mock: AnalysisService.MockOptions(failStage: .judgment)
        )
        let cwd = URL(fileURLWithPath: NSTemporaryDirectory())

        await #expect(throws: AnalysisServiceError.self) {
            try await service.runStage(prompt: "p", cwd: cwd, tier: .strong, stage: .judgment, onProgress: { _ in })
        }
        // Second call for the same stage in this process: `mockFailures.insert` no longer
        // reports a fresh insertion, so this time it must succeed normally.
        let result = try await service.runStage(prompt: "p", cwd: cwd, tier: .strong, stage: .judgment, onProgress: { _ in })
        #expect(!result.isEmpty)
    }
}

/// `onElement` is declared `@escaping @Sendable ([String: Any]) -> Void`, and `[String: Any]`
/// doesn't itself conform to `Sendable` (`Any` doesn't), so the elements collected from it
/// can't sit behind `OSAllocatedUnfairLock` the way `AnalysisService`'s own `mockFailures`
/// does. A hand-rolled `@unchecked Sendable` box with a plain lock — the same pattern
/// `Support/ShellProcess.swift`'s `DataBox` uses for the same reason — sidesteps that.
private final class StreamedElementBox: @unchecked Sendable {
    private let lock = NSLock()
    private var elements: [[String: Any]] = []
    func append(_ element: [String: Any]) { lock.withLock { elements.append(element) } }
    var count: Int { lock.withLock { elements.count } }
}
