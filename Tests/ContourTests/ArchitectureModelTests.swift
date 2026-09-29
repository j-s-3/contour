import Foundation
import Testing

@testable import Contour

struct ArchitectureModelTests {
    private func batGraph() -> PRGraph {
        var graph = ContourSampleData.publishTriggeredReindex
        graph.components = [
            ComponentNode(id: "input", title: "Input", changeKind: .unchanged),
            ComponentNode(
                id: "inspection", title: "Content Inspection", changeKind: .changed,
                delta: ResponsibilityDelta(before: "first line", after: "buffered sample")),
            ComponentNode(
                id: "classification", title: "Text / binary classification", changeKind: .changed,
                level: .component, parentId: "inspection"),
            ComponentNode(
                id: "encoding", title: "Encoding detection", changeKind: .unchanged,
                level: .component, parentId: "inspection"),
            ComponentNode(
                id: "try-new", title: "InputReader::try_new", changeKind: .changed,
                level: .implementation, parentId: "classification"),
            ComponentNode(id: "rendering", title: "Rendering", changeKind: .unchanged),
            ComponentNode(id: "terminal", title: "Terminal", changeKind: .unchanged),
        ]
        graph.architectureEdges = [
            ArchitectureEdge(
                id: "input-sample", fromId: "input", toId: "classification", label: "buffered sample",
                change: .changed, previousLabel: "first line"),
            ArchitectureEdge(id: "input-encoding", fromId: "input", toId: "encoding", label: "BOM"),
            ArchitectureEdge(id: "classify-encode", fromId: "classification", toId: "encoding", label: "text verdict"),
            ArchitectureEdge(id: "type", fromId: "inspection", toId: "rendering", label: "content type"),
            ArchitectureEdge(id: "output", fromId: "rendering", toId: "terminal", label: "formatted output"),
        ]
        graph.boundaries = [
            SystemBoundary(
                id: "bat", label: "bat process", kind: .process, componentIds: ["input", "inspection", "rendering"]),
            SystemBoundary(id: "tty", label: "Terminal", kind: .external, componentIds: ["terminal"]),
        ]
        graph.decisions = [
            DecisionNode(
                id: "how-much", title: "Inspect a buffered sample",
                decision: Statement(text: "Inspect up to 1 KB.", provenance: .fact),
                confidence: .high, componentIds: ["classification"], level: .system, significance: .high),
            DecisionNode(
                id: "impl", title: "Fallback to first line",
                decision: Statement(text: "Use the longer.", provenance: .fact),
                confidence: .high, componentIds: ["try-new"], level: .implementation, significance: .low),
        ]
        graph.flows = [
            FlowNode(
                id: "pipe", title: "Pipe data into bat",
                steps: [
                    FlowStep(id: "s1", index: 1, title: "peek", componentId: "try-new")
                ]),
            FlowNode(
                id: "render", title: "Render a file",
                steps: [
                    FlowStep(id: "s2", index: 1, title: "print", componentId: "rendering")
                ]),
        ]
        graph.pr.considerations = [
            Consideration(
                id: "chunking", headline: "Is detection that depends on pipe chunking acceptable?",
                impact: "", relatedIds: ["how-much", "input", "classification"]),
            Consideration(
                id: "explicit", headline: "Is the BOM still honored?", impact: "",
                relatedIds: ["input-encoding"]),
        ]
        return graph
    }

    @Test func systemLevelShowsTopLevelPartsWithArrowsLiftedToThem() {
        let level = batGraph().architectureLevel(path: [])
        #expect(level.primary.map(\.id) == ["input", "inspection", "rendering", "terminal"])
        #expect(level.context.isEmpty)
        let pairs = level.edges.map { "\($0.fromId)→\($0.toId)" }
        #expect(pairs == ["input→inspection", "inspection→rendering", "rendering→terminal"])
        let into = level.edges.first { $0.toId == "inspection" }
        #expect(into?.edge.id == "input-sample")
        #expect(into?.mergedIds == ["input-encoding"])
    }

    @Test func boundariesKeepOnlyWhatIsDrawn() {
        let level = batGraph().architectureLevel(path: [])
        #expect(level.boundaries.map(\.componentIds) == [["input", "inspection", "rendering"], ["terminal"]])
    }

    @Test func zoomingInShowsTheInsideWithNeighborsAsContext() {
        let level = batGraph().architectureLevel(path: ["inspection"])
        #expect(level.focus?.id == "inspection")
        #expect(level.primary.map(\.id) == ["classification", "encoding"])
        #expect(Set(level.context.map(\.id)) == ["input", "rendering"])
        let pairs = Set(level.edges.map { "\($0.fromId)→\($0.toId)" })
        #expect(pairs == ["input→classification", "input→encoding", "classification→encoding", "encoding→rendering"])
        #expect(level.boundaries.map(\.componentIds) == [["classification", "encoding"]])
    }

    @Test func implementationNodesAreNeverBoxes() {
        let graph = batGraph()
        #expect(
            !graph.architectureLevel(path: ["inspection", "classification"]).primary.contains { $0.id == "try-new" })
        #expect(graph.drawablePart(for: "try-new")?.id == "classification")
        #expect(graph.architecturePath(showing: "try-new") == ["inspection"])
        #expect(graph.architecturePath(showing: "rendering") == [])
        #expect(graph.implementation(of: "classification").nodes.map(\.id) == ["try-new"])
    }

    @Test func flowsAndDecisionsIncludeEverythingInsideAPart() {
        let graph = batGraph()
        #expect(graph.flows(through: "inspection").map(\.id) == ["pipe"])
        #expect(graph.decisions(within: "inspection").map(\.id) == ["how-much", "impl"])
    }

    @Test func onlyDecisionsToReviewAreMarkedOnTheDrawing() {
        let graph = batGraph()
        let anchors = graph.decisionAnchors(on: graph.architectureLevel(path: []))
        #expect(anchors[.node("inspection")]?.map(\.id) == ["how-much"])
        #expect(anchors.values.flatMap { $0 }.count == 1)
    }

    @Test func questionsAreMarkedWhereTheConcernLives() {
        let graph = batGraph()
        let anchors = graph.questionAnchors(on: graph.architectureLevel(path: []))
        #expect(anchors[.edge("input-sample")]?.map(\.id) == ["chunking", "explicit"])

        let inside = graph.questionAnchors(on: graph.architectureLevel(path: ["inspection"]))
        #expect(inside[.edge("input-sample")]?.map(\.id) == ["chunking"])
        #expect(inside[.edge("input-encoding")]?.map(\.id) == ["explicit"])
    }

    @Test func olderGraphsStillDraw() {
        var graph = ContourSampleData.publishTriggeredReindex
        graph.components = [
            ComponentNode(id: "a", title: "A", changeKind: .changed, implementedBy: ["Impl"]),
            ComponentNode(id: "b", title: "B", changeKind: .unchanged),
            ComponentNode(id: "impl", title: "Impl", changeKind: .changed, dependsOnIds: ["a"], level: .implementation),
        ]
        graph.architectureEdges = []
        graph.components[0].dependsOnIds = ["b"]
        let level = graph.architectureLevel(path: [])
        #expect(level.primary.map(\.id) == ["a", "b"])
        #expect(level.edges.map { "\($0.fromId)→\($0.toId)" } == ["a→b"])
        #expect(graph.drawablePart(for: "impl")?.id == "a")
    }

    @Test func askingAboutAPartCarriesItsArchitecturalContext() throws {
        var graph = batGraph()
        graph.architecture = ArchitectureAssessment(impact: .low, headline: "No structural change")
        let resolved = try #require(graph.resolve(.component("inspection")))
        #expect(resolved.detail.contains("What this PR changed about it: first line → buffered sample"))
        #expect(resolved.detail.contains("Parts inside it: Text / binary classification, Encoding detection"))
        #expect(resolved.detail.contains("overall architectural impact: low — No structural change"))
        #expect(
            resolved.detail.contains(
                "Overview question about this part: Is detection that depends on pipe chunking acceptable?"))
        #expect(resolved.flowIds == ["pipe"])
        #expect(resolved.decisionIds == ["how-much", "impl"])

        let child = try #require(graph.resolve(.component("classification")))
        #expect(child.lineage.last == "Content Inspection")
        #expect(child.detail.contains("Implemented by: InputReader::try_new"))
    }

    @Test func askingAboutARelationshipSaysWhatCrossesIt() throws {
        let graph = batGraph()
        let resolved = try #require(graph.resolve(.relationship("input-sample")))
        #expect(resolved.summary.contains { $0.hasPrefix("first line → buffered sample") })
        #expect(resolved.detail.contains("previously carried: first line"))
        #expect(
            resolved.detail.contains(
                "Overview question about this relationship: Is detection that depends on pipe chunking acceptable?"))
    }

    @Test func assessmentDecodesLeniently() throws {
        let json = #"{"impact": "sideways", "headline": "No structural change"}"#
        let assessment = try JSONDecoder().decode(ArchitectureAssessment.self, from: Data(json.utf8))
        #expect(assessment.impact == .low)
        #expect(assessment.headline == "No structural change")

        let arch = try StageDecoding.decode(
            StageDecoding.ArchitectureResult.self,
            from: [
                "components": [],
                "architecture": [
                    "impact": "none", "headline": "Same",
                    "explanation": ["text": "Unchanged.", "provenance": "interpretation"],
                ],
            ])
        #expect(arch.architecture?.impact == ArchitecturalImpact.none)
        #expect(arch.architectureImpact?.text == "Unchanged.")
    }
}
