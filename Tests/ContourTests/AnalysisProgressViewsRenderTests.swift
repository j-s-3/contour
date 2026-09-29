import AppKit
import Foundation
import SwiftUI
import Testing

@testable import Contour

@MainActor
struct AnalysisProgressViewsRenderTests {
    private func render<V: View>(_ view: V) -> CGSize {
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        host.layoutSubtreeIfNeeded()
        return host.fittingSize
    }

    private var mixedState: AnalysisState {
        var state = AnalysisState()
        state.revalidatingFrom = "abcdef1234567"
        state.stages[.behaviorChange] = .done
        state.stages[.understanding] = .running(detail: "reading the diff")
        state.stages[.decisions] = .failed("malformed JSON")
        state.stages[.architecture] = .stale
        state.stages[.flows] = .stopped
        return state
    }

    private var log: [PipelineProgressEntry] {
        [
            PipelineProgressEntry(stage: "Analyzing architecture", detail: "Reading GraphStore.swift"),
            PipelineProgressEntry(stage: "Analyzing flows", detail: "Tracing the request"),
        ]
    }

    private var metrics: AnalysisMetrics {
        var metrics = AnalysisMetrics(pr: "acme/shop#1")
        metrics.milestones[LatencyMilestone.usefulOverview.rawValue] = 3.25
        return metrics
    }

    @Test func workingViewsLayOut() {
        #expect(render(WorkingMark()).width > 0)
        #expect(render(WorkingLine(text: "Working…")).width > 0)
        #expect(render(WorkingLine(text: "Working…", font: .caption)).width > 0)
    }

    @Test func stageStatusGlyphLaysOutForEveryStatus() {
        let statuses: [StageStatus] = [
            .done, .running(detail: nil), .failed("x"), .stale, .stopped, .pending,
        ]
        for status in statuses {
            #expect(render(StageStatusGlyph(status: status)).width > 0)
        }
    }

    @Test func analysisIndicatorLaysOutForEveryLabel() {
        var stopped = AnalysisState(isComplete: true)
        stopped.stages[.decisions] = .stopped
        var failed = AnalysisState(isComplete: true)
        failed.stages[.judgment] = .failed("boom")
        let complete = AnalysisState(isComplete: true)
        var cached = AnalysisState(isComplete: true)
        cached.fromCache = true
        for state in [mixedState, stopped, failed, complete, cached] {
            let size = render(
                AnalysisIndicator(
                    state: state, log: log, metrics: metrics, refCheck: nil, onStop: {}, onRetry: { _ in }))
            #expect(size.width > 0)
        }
    }

    @Test func analysisDetailsViewLaysOutWithAndWithoutOptionalParts() {
        let full = render(
            AnalysisDetailsView(
                state: mixedState, log: log, metrics: metrics,
                refCheck: RefCheck(checked: 5, unresolvedCount: 1, unresolved: ["a.swift:1"]),
                onStop: {}, onRetry: { _ in }))
        let bare = render(
            AnalysisDetailsView(
                state: AnalysisState(isComplete: true), log: [], metrics: nil, refCheck: nil, onStop: nil,
                onRetry: { _ in }))
        #expect(full.height > bare.height)
        #expect(full.width == 420)
    }

    @Test func refCheckViewLaysOutWhenAllVerifiedAndWhenSomeAreNot() {
        #expect(render(RefCheckView(check: RefCheck(checked: 4))).width > 0)
        let overflowing = RefCheck(checked: 30, unresolvedCount: 25, unresolved: ["a.swift:1", "b.swift:2"])
        #expect(render(RefCheckView(check: overflowing)).width > 0)
    }

    @Test func pipelineStagesAndMetricsLayOut() {
        #expect(render(PipelineStagesView(state: mixedState)).width > 0)
        #expect(render(MetricsView(metrics: metrics)).width > 0)
    }

    @Test func analysisLogViewLaysOutWithEntriesAndEmpty() {
        #expect(render(AnalysisLogView(log: log)).width > 0)
        #expect(render(AnalysisLogView(log: [])).width > 0)
    }

    @Test func sectionPlaceholderViewsLayOut() {
        #expect(render(SectionPendingView(section: .architecture, status: .pending)).width > 0)
        #expect(
            render(
                SectionPendingView(
                    section: .whatChanged, status: .running(detail: "3 files"), known: "Adds caching")
            ).width > 0)
        #expect(render(SectionPendingView(section: .whatChanged, status: .pending, known: "")).width > 0)
        #expect(render(SectionFailedView(section: .flows, message: "boom", onRetry: {}, onAsk: {})).width > 0)
        #expect(render(SectionFailedView(section: .flows, message: "boom", onRetry: {}, onAsk: nil)).width > 0)
        #expect(render(SectionStoppedView(section: .decisions, onRetry: {})).width > 0)
    }

    @Test func pillsAndBannerLayOut() {
        #expect(render(SectionStoppedPill(onRetry: {})).width > 0)
        #expect(render(SectionProgressPill(text: "Working")).width > 0)
        let updating = render(RevalidationBanner(head: "abcdef1234567"))
        let settled = render(RevalidationBanner(head: "abcdef1234567", updating: false))
        #expect(updating.width > 0 && settled.width > 0)
    }
}
