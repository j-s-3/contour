import Testing
@testable import Contour

/// `AnalysisProgressViews.swift` was at 0.00% coverage — 872 lines of SwiftUI view bodies
/// with one piece of real state-derivation logic: `AnalysisDetailsView.subtitle`, which maps
/// a section's `StageStatus` to its second line of text. A later pass (#102) pulled out the
/// rest of the file's state-derivation and text-formatting logic the same way, per CLAUDE.md's
/// "views should be thin" guidance, so each is testable without a live view host:
/// `AnalysisIndicatorLabel.compute` (what the toolbar indicator's label shows),
/// `AnalysisDetailsView.showsRetryButton` (when a section row's Retry button appears),
/// `RefCheckView.headline`/`overflowText`, `MetricsView.elapsedText`, and
/// `SectionPendingView.workingText`. What's left — `WorkingMark`, `StageStatusGlyph`,
/// `AnalysisLogView`, the section placeholder/failed/stopped views, `RevalidationBanner`,
/// the popover layout itself, … — is SwiftUI view bodies rendering real AppKit/SwiftUI
/// content (materials, shadows, disclosure groups, scroll-to-bottom, symbol effects,
/// `@State`-driven fades) with no state-derivation left inside them; there is no
/// UI-testing infrastructure in this suite to host them, and CLAUDE.md is explicit that
/// contrived tests on that kind of body aren't the goal.
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

    // MARK: - AnalysisIndicatorLabel.compute

    /// Pins that "N remaining" reflects the analysis stages still unsettled, not the fixed
    /// stage count, and that the default (non-revalidating) wording is "Analyzing PR…".
    @Test func indicatorLabelWhileAnalyzingCountsUnsettledAnalysisStages() {
        var state = AnalysisState()
        state.stages[.behaviorChange] = .done
        state.stages[.understanding] = .done
        // 4 of the 6 analysis stages (architecture, decisions, flows, judgment) are unsettled.
        #expect(AnalysisIndicatorLabel.compute(state: state, settled: false)
                == .analyzing(text: "Analyzing PR…", remaining: 4))
    }

    /// A revalidation (an earlier revision's analysis on screen while a new head is analyzed)
    /// gets its own wording, distinct from a first-time analysis.
    @Test func indicatorLabelWhileRevalidatingSaysUpdatingInstead() {
        var state = AnalysisState()
        state.revalidatingFrom = "abc1234"
        #expect(AnalysisIndicatorLabel.compute(state: state, settled: false)
                == .analyzing(text: "Updating analysis…", remaining: 6))
    }

    /// Stopping is the reviewer's own, most recent act (per the source comment), so it wins
    /// over a section that also failed rather than the two being reported together.
    @Test func indicatorLabelStoppedOutranksFailed() {
        var state = AnalysisState(isComplete: true)
        state.stages[.decisions] = .stopped
        state.stages[.judgment] = .failed("boom")
        #expect(AnalysisIndicatorLabel.compute(state: state, settled: false) == .stopped)
    }

    /// "1 section" vs "2 sections" — the pluralization the toolbar text depends on.
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

    /// A completed, unfailed, unstopped analysis distinguishes a cache hit from a fresh run —
    /// the one place the reviewer is told which happened.
    @Test func indicatorLabelCompleteDistinguishesCacheFromFreshAnalysis() {
        var state = AnalysisState(isComplete: true)
        #expect(AnalysisIndicatorLabel.compute(state: state, settled: false)
                == .complete(text: "Analysis complete"))
        state.fromCache = true
        #expect(AnalysisIndicatorLabel.compute(state: state, settled: false)
                == .complete(text: "Opened saved analysis"))
    }

    /// Once the indicator's own fade timer (`settled`) has fired, the label recedes to
    /// nothing rather than continuing to claim "Analysis complete".
    @Test func indicatorLabelIsNoneOnceSettled() {
        let state = AnalysisState(isComplete: true)
        #expect(AnalysisIndicatorLabel.compute(state: state, settled: true) == .none)
    }

    // MARK: - AnalysisDetailsView.showsRetryButton

    /// Every analysis stage offers Retry once it's actually retryable (failed or stopped),
    /// regardless of the section's own status.
    @Test func retryButtonShowsForAnyAnalysisStageOnceRetryable() {
        #expect(AnalysisDetailsView.showsRetryButton(stage: .decisions, status: .failed("x")))
        #expect(AnalysisDetailsView.showsRetryButton(stage: .flows, status: .stopped))
    }

    /// A context (plumbing) stage's Retry reopens the whole PR, so it stays hidden unless the
    /// section has genuinely stopped — a plain failure on a context stage doesn't show it.
    @Test func retryButtonHiddenForAFailedContextStage() {
        #expect(!AnalysisDetailsView.showsRetryButton(stage: .fetching, status: .failed("x")))
    }

    /// The one case a context stage does show Retry: the section has stopped.
    @Test func retryButtonShowsForAStoppedContextStage() {
        #expect(AnalysisDetailsView.showsRetryButton(stage: .checkingOut, status: .stopped))
    }

    // MARK: - RefCheckView.headline / overflowText

    @Test func headlineWhenEveryReferenceVerified() {
        let check = RefCheck(checked: 41, unresolvedCount: 0, unresolved: [])
        #expect(RefCheckView.headline(check) == "All 41 code references verified")
    }

    @Test func headlineWhenSomeReferencesAreUnresolved() {
        let check = RefCheck(checked: 50, unresolvedCount: 3, unresolved: ["a.swift:1-2"])
        #expect(RefCheckView.headline(check) == "3 of 50 code references couldn't be verified")
    }

    /// No overflow line once every unresolved ref is already in the listed sample.
    @Test func overflowTextIsNilWhenEveryUnresolvedRefIsListed() {
        let check = RefCheck(checked: 10, unresolvedCount: 2, unresolved: ["a:1", "b:2"])
        #expect(RefCheckView.overflowText(check) == nil)
    }

    /// "and N more" once the unresolved count exceeds the listed sample
    /// (`RefCheck.sampleLimit`) — the case that motivated `unresolved` being capped at all.
    @Test func overflowTextCountsRefsBeyondTheListedSample() {
        let check = RefCheck(checked: 30, unresolvedCount: RefCheck.sampleLimit + 5,
                              unresolved: Array(repeating: "x.swift:1", count: RefCheck.sampleLimit))
        #expect(RefCheckView.overflowText(check) == "and 5 more")
    }

    // MARK: - MetricsView.elapsedText

    @Test func elapsedTextFormatsToOneDecimalSecond() {
        var metrics = AnalysisMetrics(pr: "owner/repo#1")
        metrics.milestones[LatencyMilestone.usefulOverview.rawValue] = 12.34
        #expect(MetricsView.elapsedText(metrics, .usefulOverview) == "12.3s")
    }

    /// A milestone that hasn't landed yet reads as an em dash, not a blank or a zero.
    @Test func elapsedTextIsAnEmDashBeforeTheMilestoneLands() {
        let metrics = AnalysisMetrics(pr: "owner/repo#1")
        #expect(MetricsView.elapsedText(metrics, .flows) == "—")
    }

    // MARK: - SectionPendingView.workingText

    /// A running stage's own progress detail replaces the working label's trailing ellipsis
    /// so the two read as one sentence ("Understanding the change — 2 files inspected"),
    /// rather than stacking a second ellipsis or clause.
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

    /// Any other status (e.g. `stale`, reached only via a revalidation carry-over) falls back
    /// to the section's plain working label.
    @Test func workingTextFallsBackToWorkingLabelForOtherStatuses() {
        #expect(SectionPendingView.workingText(section: .decisions, status: .stale) == "Identifying choices…")
    }
}
