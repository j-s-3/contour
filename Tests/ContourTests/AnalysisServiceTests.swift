import Foundation
import Testing
@testable import Contour

/// `AnalysisService.swift` was at 52.63% line coverage. Everything that goes through the
/// mock-harness seam (`MockOptions`, used throughout `PipelineConcurrencyTests`) returns
/// its canned response directly, so it never reaches `extractJSONObject` or constructs
/// `AnalysisServiceError.notJSON`/`.processFailed` with a real underlying error — and the
/// real (non-mock) harness-invoking path isn't safely testable here (see the
/// `ConversationService`/`ConversationStore` coverage PRs for why: it would mean faking a
/// `pi`/`claude` executable on `PATH`, which risks `EnvironmentProbe`/`Preferences` tests
/// elsewhere in the suite that detect installed harnesses via the real `PATH`). These pin
/// the pure pieces directly instead.
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
}
