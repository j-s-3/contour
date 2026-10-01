import AppKit
import Foundation
import SwiftUI
import Testing

@testable import Contour

@MainActor
@Suite(.serialized)
struct AnalyzingViewRenderTests {
    private func render<V: View>(_ view: V) -> CGSize {
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        host.layoutSubtreeIfNeeded()
        return host.fittingSize
    }

    private struct NamespaceHost<Content: View>: View {
        @Namespace var ns
        let content: (Namespace.ID) -> Content
        var body: some View { content(ns) }
    }

    @Observable
    fileprivate final class LogModel {
        var log: [PipelineProgressEntry] = [PipelineProgressEntry(stage: "Opening", detail: "Fetching")]
    }

    fileprivate struct ConsoleHost: View {
        let model: LogModel
        var body: some View { AnalysisConsoleView(log: model.log) }
    }

    private func settle(_ view: NSView) {
        for _ in 0..<4 {
            view.layoutSubtreeIfNeeded()
            view.displayIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
    }

    @Test func analyzingViewLaysOut() {
        let log = [PipelineProgressEntry(stage: "Analyzing architecture", detail: "Reading GraphStore.swift")]
        for stage in [PipelineStage.fetching, .architecture, .judgment] {
            _ = render(NamespaceHost { AnalyzingView(stage: stage, log: log, markNamespace: $0) })
        }
        _ = render(NamespaceHost { AnalyzingView(stage: .fetching, log: [], markNamespace: $0) })
    }

    @Test func analysisConsoleLaysOutAndShowsWhenExpanded() {
        let log = [
            PipelineProgressEntry(stage: "Opening", detail: "Fetching"),
            PipelineProgressEntry(stage: "Analyzing architecture", detail: "Reading GraphStore.swift"),
        ]
        _ = render(AnalysisConsoleView(log: log))

        let key = "showsAnalysisActivity"
        let previous = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.set(true, forKey: key)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        _ = render(NamespaceHost { AnalyzingView(stage: .architecture, log: log, markNamespace: $0) })
    }

    @Test func failedViewLaysOut() {
        _ = render(FailedView(message: "Couldn't reach GitHub.", onRetry: {}, onOpenDifferent: {}))
    }

    @Test func consoleFollowsNewEntriesAsTheyArrive() {
        let model = LogModel()
        let hosting = NSHostingView(rootView: ConsoleHost(model: model))
        let window = HeadlessWindow(size: NSSize(width: 600, height: 300), styleMask: [.titled, .closable])
        window.contentView = hosting
        window.orderBack(nil)
        settle(hosting)
        model.log.append(PipelineProgressEntry(stage: "Analyzing architecture", detail: "Reading GraphStore.swift"))
        settle(hosting)
        #expect(model.log.count == 2)
        window.close()
    }
}
