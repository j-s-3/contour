import SwiftUI
import Testing

@testable import Contour

@MainActor
struct SummaryViewRenderTests {

    private func render<V: View>(_ view: V) -> NSImage? {
        let renderer = ImageRenderer(content: view.frame(width: 900, height: 1400))
        renderer.scale = 1
        return renderer.nsImage
    }

    private func summary(_ graph: PRGraph, _ analysis: AnalysisState, discussed: Set<String> = []) -> some View {
        SummaryView(graph: graph, analysis: analysis, discussed: discussed, onRetry: { _ in }, navigate: { _ in })
    }

    private func state(_ status: StageStatus, complete: Bool = false) -> AnalysisState {
        var analysis = AnalysisState(isComplete: complete)
        for stage in PipelineStage.analysis { analysis.stages[stage] = status }
        return analysis
    }

    @Test func rendersAFinishedAnalysis() {
        #expect(render(summary(ContourSampleData.publishTriggeredReindex, AnalysisState(isComplete: true))) != nil)
    }

    @Test func rendersWhileEveryStageIsStillRunning() {
        var graph = ContourSampleData.publishTriggeredReindex
        graph.behaviorChanges = []
        #expect(render(summary(graph, state(.running(detail: "2 found so far")))) != nil)
    }

    @Test func rendersFailedAndStoppedStagesWithRetryLines() {
        var graph = ContourSampleData.publishTriggeredReindex
        graph.behaviorChanges = []
        graph.pr.considerations = nil
        #expect(render(summary(graph, state(.failed("boom")))) != nil)
        #expect(render(summary(graph, state(.stopped))) != nil)
    }

    @Test func rendersTheFallbackWhenNoBeforeAfterWasExtracted() {
        var graph = ContourSampleData.publishTriggeredReindex
        graph.behaviorChanges = []
        #expect(render(summary(graph, state(.done, complete: true))) != nil)
        graph.pr.problemToBeSolved = nil
        #expect(render(summary(graph, state(.done, complete: true))) != nil)
    }

    @Test func rendersRevalidatingAndManyConsiderations() {
        var graph = ContourSampleData.publishTriggeredReindex
        graph.pr.considerations = (1...8).map {
            Consideration(
                id: "c\($0)", question: "Question \($0)?", detail: "Detail \($0)", explanation: "Because \($0).")
        }
        var analysis = state(.done, complete: true)
        analysis.stages[.judgment] = .running(detail: nil)
        analysis.revalidatingFrom = "abc123"
        #expect(render(summary(graph, analysis, discussed: ["c1"])) != nil)
        analysis.stages[.judgment] = .failed("x")
        #expect(render(summary(graph, analysis)) != nil)
        analysis.stages[.judgment] = .stopped
        #expect(render(summary(graph, analysis)) != nil)
    }

    @Test func rendersTheTicketChipAndOtherBehaviorChanges() {
        var graph = ContourSampleData.publishTriggeredReindex
        graph.pr.ticket = TicketInfo(
            kind: .jira, key: "DOC-1", summary: "Reindex", description: "", url: "https://example.com/DOC-1")
        graph.behaviorChanges.append(BehaviorChange(id: "extra", title: "A second change"))
        #expect(render(summary(graph, AnalysisState(isComplete: true))) != nil)
        graph.pr.ticket?.kind = .github
        graph.pr.ticket?.url = ""
        #expect(render(summary(graph, AnalysisState(isComplete: true))) != nil)
    }

    @Test func rendersAnExpandedConsiderationRow() {
        let graph = ContourSampleData.publishTriggeredReindex
        let related = (graph.decisions.map(\.id) + graph.components.map(\.id) + graph.flows.map(\.id))
        let item = Consideration(
            id: "c", question: "Is it fine?", detail: "Detail.", kind: .question,
            explanation: "Because.", relatedIds: related + ["missing"],
            refs: [CodeRef(path: "a.swift", startLine: 1, endLine: 2)]
        )
        for expanded in [true, false] {
            for resolved in [true, false] {
                let row = ConsiderationRow(
                    number: 1, item: item, graph: graph, isResolved: resolved,
                    isExpanded: expanded, onToggle: {}, onReview: {}, navigate: { _ in })
                #expect(render(row) != nil)
            }
        }
        let bare = Consideration(id: "d", question: "Q?", detail: "")
        #expect(
            render(
                ConsiderationRow(
                    number: 2, item: bare, graph: graph, isResolved: false, isExpanded: true,
                    onToggle: {}, onReview: {}, navigate: { _ in })) != nil)
    }

    @Test func rendersAnExploreTile() {
        #expect(
            render(ExploreTile(title: "Flows", detail: "3 traced", symbol: "arrow.triangle.branch", action: {})) != nil)
    }
}
