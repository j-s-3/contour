import Testing
import Foundation
@testable import Contour

/// Flows draw what happens at runtime and how the PR changed it — from the behavior model the
/// flows stage writes, and for older graphs by condensing their story steps.
struct FlowBehaviorTests {

    /// The captured bat#3877 run, which predates the behavior model.
    private func fixtureGraph() throws -> PRGraph {
        let arch = try StageDecoding.decode(StageDecoding.ArchitectureResult.self, from: MockAnalysisFixtures.response(for: .architecture))
        let decisions = try StageDecoding.decode(StageDecoding.DecisionsResult.self, from: MockAnalysisFixtures.response(for: .decisions))
        let flows = try StageDecoding.decode(StageDecoding.FlowsResult.self, from: MockAnalysisFixtures.response(for: .flows))
        let judgment = try StageDecoding.decode(StageDecoding.JudgmentResult.self, from: MockAnalysisFixtures.response(for: .judgment))
        var graph = ContourSampleData.publishTriggeredReindex
        graph.components = arch.components
        graph.architectureEdges = arch.edges
        graph.decisions = decisions.decisions
        graph.flows = flows.flows
        graph.entryPoints = flows.entryPoints
        graph.pr.considerations = judgment.considerations
        return graph
    }

    // MARK: - Decoding

    @Test func aMalformedStageOrDanglingEdgeDropsOnlyItself() throws {
        let json = """
        {"id": "f", "title": "Open a file", "behavior": {
          "summary": "bat samples the input and classifies it.",
          "nodes": [
            {"id": "t", "label": "Open a file", "kind": "trigger"},
            {"id": "s", "label": "Inspect sample", "kind": "teleport", "change": "changed", "before": "first line", "after": "up to 1 KB"},
            {"label": "no id"}
          ],
          "edges": [
            {"fromId": "t", "toId": "s", "label": "  "},
            {"fromId": "s", "toId": "missing"}
          ]
        }}
        """
        let flow = try JSONDecoder().decode(FlowNode.self, from: Data(json.utf8))
        let behavior = try #require(flow.behavior)
        #expect(behavior.nodes.map(\.id) == ["t", "s"])
        #expect(behavior.nodes[1].kind == .step)
        #expect(behavior.nodes[1].change == .changed)
        #expect(behavior.edges.count == 1)
        #expect(behavior.edges[0].label == nil)
    }

    @Test func aBehaviorWithNoStagesFallsBackToTheCondensedOne() throws {
        let json = #"{"id": "f", "title": "x", "behavior": {"nodes": []}, "storySteps": [{"text": "Do it", "provenance": "fact"}]}"#
        let flow = try JSONDecoder().decode(FlowNode.self, from: Data(json.utf8))
        #expect(flow.behavior == nil)
    }

    @Test func beforeAndAfterAreCoherentSnapshots() {
        let behavior = FlowBehavior(
            nodes: [
                FlowBehaviorNode(id: "a", label: "Input", kind: .trigger),
                FlowBehaviorNode(id: "old", label: "Inspect first line", change: .removed),
                FlowBehaviorNode(id: "new", label: "Inspect buffered sample", change: .new),
                FlowBehaviorNode(id: "c", label: "Classify")
            ],
            edges: [
                FlowBehaviorEdge(fromId: "a", toId: "old", change: .removed),
                FlowBehaviorEdge(fromId: "old", toId: "c", change: .removed),
                FlowBehaviorEdge(fromId: "a", toId: "new", change: .new),
                FlowBehaviorEdge(fromId: "new", toId: "c", change: .new)
            ]
        )
        #expect(behavior.visible(in: .before).nodes.map(\.id) == ["a", "old", "c"])
        #expect(behavior.visible(in: .after).nodes.map(\.id) == ["a", "new", "c"])
        #expect(behavior.visible(in: .after).edges.allSatisfy { $0.change == .new })
        #expect(behavior.visible(in: .delta).nodes.count == 4)
    }

    // MARK: - Older graphs

    @Test func olderFlowsAreNamedByTheirTriggerNotTheirCallChain() throws {
        let graph = try fixtureGraph()
        let file = try #require(graph.flow("flow-cli-file-binary-detection"))
        #expect(graph.scenarioTitle(for: file) == "bat <file>")
        var modern = file
        modern.behavior = FlowBehavior(nodes: [FlowBehaviorNode(id: "t", label: "Open a file", kind: .trigger)])
        modern.title = "Open a file"
        #expect(graph.scenarioTitle(for: modern) == "Open a file")
    }

    @Test func olderFlowsCondenseToATriggerAndTheirStorySteps() throws {
        let graph = try fixtureGraph()
        let file = try #require(graph.flow("flow-cli-file-binary-detection"))
        let behavior = graph.behavior(for: file)
        #expect(behavior.nodes.first?.kind == .trigger)
        #expect(behavior.nodes.count == file.storySteps.count + 1)
        #expect(behavior.nodes.last?.kind == .outcome)
        #expect(behavior.edges.count == behavior.nodes.count - 1)
        // Every implementation step lands under exactly one stage.
        #expect(behavior.nodes.flatMap(\.stepIds).count == file.steps.count)
        // Opening the file is context; peeking at the buffer is what this PR added.
        #expect(behavior.nodes[1].change == .existing)
        #expect(behavior.nodes[2].change != .existing)
        #expect(behavior.nodes[2].stepIds.contains("snapshot-prefix"))
        // Classification lands on the classify stage, not the fallback before it.
        let classify = try #require(behavior.nodes.first { $0.label.hasPrefix("Classify") })
        #expect(classify.stepIds.contains("classify-content"))
    }

    @Test func decisionsAppearAtThePointTheyShapeTheFlow() throws {
        let graph = try fixtureGraph()
        let file = try #require(graph.flow("flow-cli-file-binary-detection"))
        let behavior = graph.behavior(for: file)
        let decisions = graph.annotations(for: file).filter { $0.kind == .decision }
        #expect(Set(decisions.map(\.targetId)) == ["inspect-first-kb-not-first-line", "non-blocking-buffered-snapshot"])
        // Pinned to a changed stage, never to unchanged context.
        for annotation in decisions {
            #expect(behavior.node(annotation.nodeId)?.change != .existing)
        }
        // Implementation details stay out of the diagram.
        #expect(!decisions.contains { $0.targetId == "skip-read-on-empty-input" })
    }

    @Test func aReviewQuestionAppearsOnlyInTheFlowItConcerns() throws {
        let graph = try fixtureGraph()
        let file = try #require(graph.flow("flow-cli-file-binary-detection"))
        let stdin = try #require(graph.flow("flow-stdin-custom-reader-detection"))
        let chunking = "short-first-read-misses-binary"
        #expect(graph.annotations(for: stdin).contains { $0.kind == .question && $0.targetId == chunking })
        #expect(!graph.annotations(for: file).contains { $0.kind == .question && $0.targetId == chunking })
    }

    @Test func anAnchoredQuestionSitsExactlyWhereTheJudgmentStagePutIt() throws {
        var graph = try fixtureGraph()
        let index = try #require(graph.flows.firstIndex { $0.id == "flow-stdin-custom-reader-detection" })
        graph.flows[index].behavior = FlowBehavior(
            nodes: [
                FlowBehaviorNode(id: "pipe", label: "Pipe input", kind: .trigger),
                FlowBehaviorNode(id: "inspect", label: "Inspect buffered data", change: .changed),
                FlowBehaviorNode(id: "classify", label: "Classify")
            ],
            edges: [FlowBehaviorEdge(fromId: "pipe", toId: "inspect"), FlowBehaviorEdge(fromId: "inspect", toId: "classify")]
        )
        let q = try #require(graph.pr.considerations?.firstIndex { $0.id == "short-first-read-misses-binary" })
        graph.pr.considerations?[q].flowAnchors = [FlowAnchor(flowId: "flow-stdin-custom-reader-detection", nodeId: "classify")]
        let annotation = graph.annotations(for: graph.flows[index]).first { $0.targetId == "short-first-read-misses-binary" }
        #expect(annotation?.nodeId == "classify")
    }

    @Test func aDecisionKnowsWhichFlowsItAppearsIn() throws {
        let graph = try fixtureGraph()
        let appearances = graph.flowAppearances(ofDecision: "non-blocking-buffered-snapshot")
        #expect(appearances.map(\.flow.id).contains("flow-stdin-custom-reader-detection"))
    }

    // MARK: - Convergence

    @Test func flowsThatHandOffToASharedStageAreFound() {
        var graph = ContourSampleData.publishTriggeredReindex
        let shared = FlowNode(id: "reconcile", title: "Reconcile repository",
                              behavior: FlowBehavior(nodes: [FlowBehaviorNode(id: "t", label: "Reconcile", kind: .trigger)]))
        let upload = FlowNode(id: "upload", title: "Upload asset", behavior: FlowBehavior(nodes: [
            FlowBehaviorNode(id: "t", label: "Upload asset", kind: .trigger),
            FlowBehaviorNode(id: "r", label: "Reconcile repository", kind: .subflow, subflowId: "reconcile")
        ]))
        graph.flows += [shared, upload]
        #expect(graph.flowsConverging(into: "reconcile").map(\.id) == ["upload"])
        #expect(graph.flowsConverging(into: "upload").isEmpty)
    }
}
