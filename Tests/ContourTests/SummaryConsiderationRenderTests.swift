import AppKit
import SwiftUI
import Testing

@testable import Contour

@MainActor
struct SummaryConsiderationRenderTests {
    private func render(
        _ graph: PRGraph, analysis: AnalysisState = AnalysisState(isComplete: true), width: CGFloat = 1100
    ) -> NSSize {
        let host = NSHostingView(rootView: SummaryView(graph: graph, analysis: analysis) { _ in })
        host.frame = NSRect(x: 0, y: 0, width: width, height: 900)
        host.layoutSubtreeIfNeeded()
        return host.fittingSize
    }

    private func graph(with considerations: [Consideration]) -> PRGraph {
        var graph = ContourSampleData.publishTriggeredReindex
        graph.pr.considerations = considerations
        return graph
    }

    @Test func rowsWithCategoryImpactAndDecisionRender() {
        let items = [
            Consideration(
                id: "a", category: .errorHandling, judgmentType: .confirmIntent,
                headline: "Token failures behave differently from other GitHub read failures",
                impact: "An authentication failure fails the whole operation.",
                decision: "Should authentication failures fail the operation?"),
            Consideration(
                id: "b", category: .compatibility, headline: "A limit copies a dependency's internal value",
                impact: "An upgrade could silently change behavior.", decision: "Confirm the dependency's limit.",
                kind: .question),
        ]
        #expect(render(graph(with: items)).height > 0)
    }

    @Test func rowsWithoutCategoryImpactOrDecisionRender() {
        #expect(render(graph(with: [Consideration(id: "a", headline: "Is this safe?", impact: "")])).height > 0)
    }

    @Test func theCapturedFixtureConsiderationsRenderAtANarrowWidth() throws {
        let judgment = try StageDecoding.decode(
            StageDecoding.JudgmentResult.self, from: MockAnalysisFixtures.response(for: .judgment))
        #expect(
            judgment.considerations.allSatisfy { $0.category != nil && $0.judgmentType != nil && $0.decision != nil })
        #expect(render(graph(with: judgment.considerations), width: 700).height > 0)
    }

    @Test func theJudgmentPlaceholderRendersWhileJudgmentIsRunning() {
        var analysis = AnalysisState()
        analysis.stages[.judgment] = .running(detail: nil)
        var graph = ContourSampleData.publishTriggeredReindex
        graph.pr.considerations = nil
        #expect(graph.thingsToThinkAbout(during: analysis) == nil)
        #expect(render(graph, analysis: analysis).height > 0)
    }
}
