import Testing
@testable import Contour

/// `AnalysisProgressViews.swift` was at 0.00% coverage — 872 lines of SwiftUI view bodies
/// with one piece of real state-derivation logic: `AnalysisDetailsView.subtitle`, which maps
/// a section's `StageStatus` to its second line of text. Pulled out to a `static func` per
/// CLAUDE.md's "views should be thin" guidance so it's testable without a live view host.
/// Everything else in this file is SwiftUI view bodies (`WorkingMark`, `StageStatusGlyph`,
/// `AnalysisIndicator`, `PipelineStagesView`, `MetricsView`, `AnalysisLogView`, the section
/// placeholder/failed/stopped views, `RevalidationBanner`, …) that render real AppKit/SwiftUI
/// content and stay untested here — there's no UI-testing infrastructure in this suite to
/// host them.
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
}
