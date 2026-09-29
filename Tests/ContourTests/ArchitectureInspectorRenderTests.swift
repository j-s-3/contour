import AppKit
import SwiftUI
import Testing

@testable import Contour

@MainActor
struct ArchitectureInspectorRenderTests {
    private func host(_ graph: PRGraph, path: [String], anchor: ArchAnchor) -> NSHostingView<some View> {
        let level = graph.architectureLevel(path: path)
        let view = ArchitectureInspector(
            graph: graph, level: level, anchor: anchor,
            onSelect: { _ in }, onZoomIn: { _ in }, onClose: {}
        )
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 420, height: 900)
        hosting.layoutSubtreeIfNeeded()
        return hosting
    }

    private func richGraph() -> PRGraph {
        var graph = ContourSampleData.publishTriggeredReindex
        let ref = CodeRef(path: "src/A.swift", startLine: 1, endLine: 5)
        let topId = graph.topLevelParts.first?.id
        graph.components.append(
            ComponentNode(
                id: "impl-a", title: "PublisherImpl", changeKind: .changed, refs: [ref],
                level: .component, parentId: topId))
        if let first = graph.components.firstIndex(where: { $0.id == topId }) {
            graph.components[first].implementedBy.append("ExtraNamedImpl")
            graph.components[first].refs = [ref]
            graph.components[first].delta = ResponsibilityDelta(before: "old", after: "new")
        }
        graph.architectureEdges = graph.resolvedEdges
        graph.architectureEdges[1].previousLabel = "calls index()"
        graph.architectureEdges.append(
            ArchitectureEdge(
                id: "publish-updates-search-again", fromId: "page-publishing", toId: "search-service",
                label: "also updates", flow: .async, change: .existing))
        graph.architectureEdges.append(
            ArchitectureEdge(
                id: "unlabeled", fromId: "search-service", toId: "index-queue", label: "", change: .removed))
        graph.pr.considerations = [
            Consideration(
                id: "q-part", headline: "Is the queue durable?", impact: "d", relatedIds: ["index-queue"]),
            Consideration(
                id: "q-edge", headline: "Does reindex block?", impact: "d", relatedIds: ["queue-indexes"]),
            Consideration(
                id: "q-edge-2", headline: "Is publish fast?", impact: "d", relatedIds: ["publish-queues"]),
        ]
        return graph
    }

    private func allPaths(_ graph: PRGraph) -> [[String]] {
        [[]] + graph.architectureParts.map { [$0.id] }
    }

    @Test func everyNodeAnchorRendersAtEveryLevel() {
        let graph = richGraph()
        var rendered = 0
        for path in allPaths(graph) {
            for node in graph.architectureLevel(path: path).nodes {
                let hosting = host(graph, path: path, anchor: .node(node.id))
                #expect(hosting.fittingSize.width >= 0)
                rendered += 1
            }
        }
        #expect(rendered > 0)
    }

    @Test func everyEdgeAnchorRendersAtEveryLevel() {
        let graph = richGraph()
        var rendered = 0
        for path in allPaths(graph) {
            for edge in graph.architectureLevel(path: path).edges {
                _ = host(graph, path: path, anchor: .edge(edge.id))
                rendered += 1
            }
        }
        #expect(rendered > 0)
    }

    @Test func anchorsThatNoLongerExistRenderEmpty() {
        let graph = richGraph()
        _ = host(graph, path: [], anchor: .node("missing"))
        _ = host(graph, path: [], anchor: .edge("missing"))
    }
}
