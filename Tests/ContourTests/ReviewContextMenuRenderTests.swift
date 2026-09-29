import AppKit
import SwiftUI
import Testing

@testable import Contour

@MainActor
@Suite(.serialized)
struct ReviewContextMenuRenderTests {
    private func graph() -> PRGraph {
        var graph = ContourSampleData.publishTriggeredReindex
        let first = graph.decisions[0]
        graph.decisions.append(
            DecisionNode(
                id: "second", title: "Second", decision: Statement(text: "x", provenance: .fact),
                confidence: .high, refs: first.refs, componentIds: first.componentIds))
        return graph
    }

    private func subjects(in graph: PRGraph) -> [ReviewSubject] {
        var all: [ReviewSubject] = [.pullRequest]
        all += graph.components.map { .component($0.id) }
        for decision in graph.decisions {
            all.append(.decision(decision.id))
            all += decision.tradeoffs.indices.map { .tradeoff(decisionId: decision.id, index: $0) }
            all += decision.options.indices.map { .decisionOption(decisionId: decision.id, index: $0) }
            all += decision.refs.map { .codeRef($0) }
        }
        for flow in graph.flows {
            all.append(.flow(flow.id))
            all += flow.steps.map { .flowStep(flowId: flow.id, stepId: $0.id) }
        }
        return all
    }

    private func render(_ view: some View) {
        _ = NSApplication.shared
        let host = NSHostingView(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 600),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.animationBehavior = .none
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderBack(nil)
        for _ in 0..<2 {
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        window.close()
    }

    private func actions(_ graph: PRGraph?) -> ReviewActions {
        ReviewActions(graph: graph, prURL: "https://github.com/acme/shop/pull/7")
    }

    private func compactGraph() -> PRGraph {
        var graph = ContourSampleData.publishTriggeredReindex
        let refs = [
            CodeRef(path: "a.swift", startLine: 1, endLine: 2), CodeRef(path: "b.swift", startLine: 3, endLine: 3),
        ]
        graph.components = [ComponentNode(id: "c1", title: "C1", changeKind: .unchanged)]
        graph.decisions = [
            DecisionNode(
                id: "d1", title: "D1", decision: Statement(text: "x", provenance: .fact), confidence: .high,
                refs: refs, componentIds: ["c1"])
        ]
        graph.flows = [FlowNode(id: "f1", title: "F1"), FlowNode(id: "f2", title: "F2")]
        return graph
    }

    @Test func rendersSingleAndMultipleRelatedItemsAndRefs() {
        let graph = compactGraph()
        for subject: ReviewSubject in [.pullRequest, .decision("d1"), .component("c1")] {
            #expect(graph.resolve(subject) != nil)
            render(
                ReviewContextMenuContent(subject: subject, extra: EmptyView()).environment(
                    \.reviewActions, actions(graph)))
        }
    }

    @Test func rendersTheMenuForEverySubjectKindInTheSampleGraph() {
        let graph = graph()
        let all = subjects(in: graph)
        #expect(all.count > 5)
        for subject in all {
            render(Color.clear.environment(\.reviewActions, actions(graph)).reviewContextMenu(subject))
            render(
                ReviewContextMenuContent(subject: subject, extra: Text("Extra"))
                    .environment(\.reviewActions, actions(graph)))
        }
    }

    @Test func rendersNothingWithoutAGraph() {
        render(
            ReviewContextMenuContent(subject: .pullRequest, extra: EmptyView())
                .environment(\.reviewActions, actions(nil)))
    }

    @Test func rendersNothingForASubjectTheGraphCannotResolve() {
        render(
            ReviewContextMenuContent(subject: .decision("missing"), extra: EmptyView())
                .environment(\.reviewActions, actions(graph())))
    }

    @Test func rendersTheExtraViewBuilderOverload() {
        render(
            Color.clear.environment(\.reviewActions, actions(graph()))
                .reviewContextMenu(.pullRequest) { Text("Extra") })
    }
}
