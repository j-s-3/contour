import Testing
import SwiftUI
import AppKit
@testable import Contour

/// `FlowStageInspector`'s body and rung builders are SwiftUI view code with no logic left to
/// extract (selection and formatting live in `FlowStageInspectorLogic`). This suite hosts the
/// real view in an `NSHostingView` and lays it out for every stage of the sample flow at every
/// drill level, so each rung's builder actually runs against realistic graph data. It pins
/// that no combination of stage and rung traps while building or laying out, which is the
/// regression the pure-logic tests cannot see (a rung reaching for a field the graph lacks).
@MainActor
struct FlowStageInspectorRenderTests {

    private func host(_ graph: PRGraph, flow: FlowNode, node: FlowBehaviorNode, level: FlowDrillLevel) -> NSHostingView<FlowStageInspector> {
        let view = FlowStageInspector(
            graph: graph, flow: flow, node: node, level: .constant(level),
            onSelectNode: { _ in }, onOpenEvidence: { _ in }, onOpenFlow: { _ in }, onClose: {}
        )
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 420, height: 800)
        hosting.layoutSubtreeIfNeeded()
        return hosting
    }

    @Test func everyStageRendersAtEveryDrillLevel() throws {
        let graph = ContourSampleData.publishTriggeredReindex
        let flow = try #require(graph.flows.first)
        var rendered = 0
        for node in graph.behavior(for: flow).nodes {
            for level in FlowDrillLevel.allCases {
                let hosting = host(graph, flow: flow, node: node, level: level)
                #expect(hosting.fittingSize.width >= 0)
                rendered += 1
            }
        }
        #expect(rendered == graph.behavior(for: flow).nodes.count * FlowDrillLevel.allCases.count)
    }

    @Test func uncertainSubflowStageRenders() throws {
        var graph = ContourSampleData.publishTriggeredReindex
        let flow = try #require(graph.flows.first)
        graph.flows.append(FlowNode(id: "shared-flow", title: "Shared flow"))
        let node = FlowBehaviorNode(
            id: "sub", label: "Call shared", kind: .subflow, detail: "Delegates.",
            change: .changed, before: "old", after: "new", substeps: ["one", "two"],
            subflowId: "shared-flow", provenance: .interpretation, confidence: .low
        )
        for level in FlowDrillLevel.allCases {
            _ = host(graph, flow: flow, node: node, level: level)
        }
    }
}
