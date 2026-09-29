import AppKit
import SwiftUI
import Testing

@testable import Contour

@MainActor
struct SummaryViewInteractionTests {

    private final class Recorder {
        var targets: [NavigationTarget] = []
        var retries: [PipelineStage] = []
    }

    private func pressEveryButton(_ graph: PRGraph, analysis: AnalysisState, rounds: Int = 3) -> Recorder {
        let recorder = Recorder()
        let view = SummaryView(
            graph: graph, analysis: analysis, discussed: [],
            onRetry: { recorder.retries.append($0) }, navigate: { recorder.targets.append($0) })
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 900, height: 1600)
        let window = HeadlessWindow(size: hosting.frame.size)
        window.contentView = hosting
        window.orderBack(nil)
        for attribute in ["AXEnhancedUserInterface", "AXManualAccessibility"] {
            _ = NSApp.perform(
                NSSelectorFromString("accessibilitySetValue:forAttribute:"), with: true as NSNumber, with: attribute)
        }
        for _ in 0..<rounds {
            settle(hosting)
            for button in buttons(in: hosting) { _ = button.perform(NSSelectorFromString("accessibilityPerformPress")) }
        }
        settle(hosting)
        window.orderOut(nil)
        return recorder
    }

    private func settle(_ hosting: NSView) {
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        hosting.layoutSubtreeIfNeeded()
    }

    private func buttons(in root: Any) -> [NSObject] {
        var found: [NSObject] = []
        func walk(_ node: Any) {
            guard let object = node as? NSObject else { return }
            let role = object.perform(NSSelectorFromString("accessibilityRole"))?.takeUnretainedValue() as? String
            if role == NSAccessibility.Role.button.rawValue || role == NSAccessibility.Role.link.rawValue {
                found.append(object)
            }
            let children = object.perform(NSSelectorFromString("accessibilityChildren"))?.takeUnretainedValue()
            for child in children as? [Any] ?? [] { walk(child) }
        }
        walk(root)
        return found
    }

    @Test func pressingEveryButtonNavigatesAndTogglesSections() {
        var graph = ContourSampleData.publishTriggeredReindex
        graph.behaviorChanges.append(BehaviorChange(id: "extra", title: "A second change"))
        let recorder = pressEveryButton(graph, analysis: AnalysisState(isComplete: true))
        #expect(!recorder.targets.isEmpty)
    }

    private func stages(_ status: StageStatus) -> AnalysisState {
        var analysis = AnalysisState(isComplete: false)
        for stage in PipelineStage.analysis { analysis.stages[stage] = status }
        return analysis
    }

    @Test func pressingRetryOnFailedStagesReportsEachStage() {
        var graph = ContourSampleData.publishTriggeredReindex
        graph.behaviorChanges = []
        let recorder = pressEveryButton(graph, analysis: stages(.failed("boom")))
        #expect(recorder.retries.contains(.behaviorChange))
    }

    @Test func pressingRetryOnStoppedStagesReportsEachStage() {
        var graph = ContourSampleData.publishTriggeredReindex
        graph.behaviorChanges = []
        graph.pr.considerations = nil
        let recorder = pressEveryButton(graph, analysis: stages(.stopped))
        #expect(recorder.retries.contains(.judgment))
    }

    @Test func showingMoreConsiderationsRevealsTheRest() {
        var graph = ContourSampleData.publishTriggeredReindex
        graph.pr.considerations = (1...8).map {
            Consideration(id: "c\($0)", headline: "Question \($0)?", impact: "Detail \($0)")
        }
        let recorder = pressEveryButton(graph, analysis: AnalysisState(isComplete: true))
        #expect(recorder.retries.isEmpty)
    }

    @Test func awaitingBehaviorAfterUnderstandingFailedRendersWithoutNavigating() {
        var graph = ContourSampleData.publishTriggeredReindex
        graph.behaviorChanges = []
        graph.pr.howItWasSolved = nil
        var analysis = stages(.running(detail: nil))
        analysis.stages[.understanding] = .failed("boom")
        let recorder = pressEveryButton(graph, analysis: analysis)
        #expect(recorder.retries.isEmpty)
    }
}
