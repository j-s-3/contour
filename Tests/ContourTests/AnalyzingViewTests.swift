import Foundation
import Testing

@testable import Contour

struct AnalyzingViewTests {
    @Test func everyPipelineStageHasAReviewerFacingHeadline() {
        #expect(AnalyzingView.headline(.fetching) == "Opening the pull request…")
        #expect(AnalyzingView.headline(.checkingOut) == "Opening the pull request…")
        #expect(AnalyzingView.headline(.cacheCheck) == "Opening the pull request…")
        #expect(AnalyzingView.headline(.ticket) == "Understanding the change…")
        #expect(AnalyzingView.headline(.behaviorChange) == "Understanding the change…")
        #expect(AnalyzingView.headline(.understanding) == "Understanding the change…")
        #expect(AnalyzingView.headline(.architecture) == "Analyzing architecture…")
        #expect(AnalyzingView.headline(.decisions) == "Finding the decisions it makes…")
        #expect(AnalyzingView.headline(.flows) == "Tracing the flows it touches…")
        #expect(AnalyzingView.headline(.judgment) == "Deciding what needs your judgment…")
    }

    @Test func latestDetailFallsBackToTheStageNameWithNoLogYet() {
        #expect(AnalyzingView.latestDetail(log: [], stage: .architecture) == PipelineStage.architecture.rawValue)
    }

    @Test func latestDetailShowsOnlyTheStageWhenTheLastEntryHasNoDetail() {
        let log = [PipelineProgressEntry(stage: "Analyzing architecture", detail: "")]
        #expect(AnalyzingView.latestDetail(log: log, stage: .architecture) == "Analyzing architecture")
    }

    @Test func latestDetailCombinesStageAndDetailWhenBothArePresent() {
        let log = [
            PipelineProgressEntry(stage: "Analyzing architecture", detail: ""),
            PipelineProgressEntry(stage: "Analyzing architecture", detail: "Reading GraphStore.swift"),
        ]
        #expect(
            AnalyzingView.latestDetail(log: log, stage: .architecture)
                == "Analyzing architecture — Reading GraphStore.swift")
    }
}
