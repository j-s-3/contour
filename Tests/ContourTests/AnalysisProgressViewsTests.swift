import Testing
@testable import Contour

struct AnalysisProgressViewsTests {
    @Test func subtitleForARunningStageFallsBackToTheSectionsWorkingLabelWhenNoDetail() {
        #expect(AnalysisDetailsView.subtitle(.architecture, .running(detail: nil)) == "Mapping system change…")
    }

    @Test func subtitleForARunningStagePrefersItsOwnDetailOverTheWorkingLabel() {
        #expect(AnalysisDetailsView.subtitle(.flows, .running(detail: "2 flows found so far")) == "2 flows found so far")
    }

    @Test func subtitleForAFailedStageIsTheFailureMessage() {
        #expect(AnalysisDetailsView.subtitle(.decisions, .failed("model returned malformed JSON")) == "model returned malformed JSON")
    }

    @Test func subtitleForEveryRemainingStatus() {
        #expect(AnalysisDetailsView.subtitle(.context, .stale) == "From the previous revision")
        #expect(AnalysisDetailsView.subtitle(.context, .stopped) == "Stopped")
        #expect(AnalysisDetailsView.subtitle(.context, .pending) == "Waiting")
        #expect(AnalysisDetailsView.subtitle(.context, .done) == nil, "a done section has nothing more to say")
    }

    @Test func indicatorLabelWhileAnalyzingCountsUnsettledAnalysisStages() {
        var state = AnalysisState()
        state.stages[.behaviorChange] = .done
        state.stages[.understanding] = .done
        #expect(AnalysisIndicatorLabel.compute(state: state, settled: false)
                == .analyzing(text: "Analyzing PR…", remaining: 4))
    }

    @Test func indicatorLabelWhileRevalidatingSaysUpdatingInstead() {
        var state = AnalysisState()
        state.revalidatingFrom = "abc1234"
        #expect(AnalysisIndicatorLabel.compute(state: state, settled: false)
                == .analyzing(text: "Updating analysis…", remaining: 6))
    }

    @Test func indicatorLabelStoppedOutranksFailed() {
        var state = AnalysisState(isComplete: true)
        state.stages[.decisions] = .stopped
        state.stages[.judgment] = .failed("boom")
        #expect(AnalysisIndicatorLabel.compute(state: state, settled: false) == .stopped)
    }

    @Test func indicatorLabelFailedCountIsPluralizedCorrectly() {
        var single = AnalysisState(isComplete: true)
        single.stages[.judgment] = .failed("boom")
        #expect(AnalysisIndicatorLabel.compute(state: single, settled: false)
                == .failed(text: "1 section couldn't be analyzed"))

        var plural = AnalysisState(isComplete: true)
        plural.stages[.judgment] = .failed("boom")
        plural.stages[.decisions] = .failed("also boom")
        #expect(AnalysisIndicatorLabel.compute(state: plural, settled: false)
                == .failed(text: "2 sections couldn't be analyzed"))
    }

    @Test func indicatorLabelCompleteDistinguishesCacheFromFreshAnalysis() {
        var state = AnalysisState(isComplete: true)
        #expect(AnalysisIndicatorLabel.compute(state: state, settled: false)
                == .complete(text: "Analysis complete"))
        state.fromCache = true
        #expect(AnalysisIndicatorLabel.compute(state: state, settled: false)
                == .complete(text: "Opened saved analysis"))
    }

    @Test func indicatorLabelIsNoneOnceSettled() {
        let state = AnalysisState(isComplete: true)
        #expect(AnalysisIndicatorLabel.compute(state: state, settled: true) == .none)
    }

    @Test func retryButtonShowsForAnyAnalysisStageOnceRetryable() {
        #expect(AnalysisDetailsView.showsRetryButton(stage: .decisions, status: .failed("x")))
        #expect(AnalysisDetailsView.showsRetryButton(stage: .flows, status: .stopped))
    }

    @Test func retryButtonHiddenForAFailedContextStage() {
        #expect(!AnalysisDetailsView.showsRetryButton(stage: .fetching, status: .failed("x")))
    }

    @Test func retryButtonShowsForAStoppedContextStage() {
        #expect(AnalysisDetailsView.showsRetryButton(stage: .checkingOut, status: .stopped))
    }

    @Test func headlineWhenEveryReferenceVerified() {
        let check = RefCheck(checked: 41, unresolvedCount: 0, unresolved: [])
        #expect(RefCheckView.headline(check) == "All 41 code references verified")
    }

    @Test func headlineWhenSomeReferencesAreUnresolved() {
        let check = RefCheck(checked: 50, unresolvedCount: 3, unresolved: ["a.swift:1-2"])
        #expect(RefCheckView.headline(check) == "3 of 50 code references couldn't be verified")
    }

    @Test func overflowTextIsNilWhenEveryUnresolvedRefIsListed() {
        let check = RefCheck(checked: 10, unresolvedCount: 2, unresolved: ["a:1", "b:2"])
        #expect(RefCheckView.overflowText(check) == nil)
    }

    @Test func overflowTextCountsRefsBeyondTheListedSample() {
        let check = RefCheck(checked: 30, unresolvedCount: RefCheck.sampleLimit + 5,
                              unresolved: Array(repeating: "x.swift:1", count: RefCheck.sampleLimit))
        #expect(RefCheckView.overflowText(check) == "and 5 more")
    }

    @Test func elapsedTextFormatsToOneDecimalSecond() {
        var metrics = AnalysisMetrics(pr: "owner/repo#1")
        metrics.milestones[LatencyMilestone.usefulOverview.rawValue] = 12.34
        #expect(MetricsView.elapsedText(metrics, .usefulOverview) == "12.3s")
    }

    @Test func elapsedTextIsAnEmDashBeforeTheMilestoneLands() {
        let metrics = AnalysisMetrics(pr: "owner/repo#1")
        #expect(MetricsView.elapsedText(metrics, .flows) == "—")
    }

    @Test func workingTextFoldsARunningStagesDetailOntoTheWorkingLabel() {
        #expect(SectionPendingView.workingText(section: .whatChanged, status: .running(detail: "2 files inspected"))
                == "Understanding the change — 2 files inspected")
    }

    @Test func workingTextFallsBackToTheWorkingLabelWhenRunningWithNoDetail() {
        #expect(SectionPendingView.workingText(section: .architecture, status: .running(detail: nil))
                == "Mapping system change…")
    }

    @Test func workingTextIsWaitingToStartWhilePending() {
        #expect(SectionPendingView.workingText(section: .flows, status: .pending) == "Waiting to start…")
    }

    @Test func workingTextFallsBackToWorkingLabelForOtherStatuses() {
        #expect(SectionPendingView.workingText(section: .decisions, status: .stale) == "Identifying choices…")
    }
}
