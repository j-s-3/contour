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
    //
    // The fixtures are regenerated from real runs, so these find things by what they are —
    // the file flow, the stdin flow, the step this PR added — rather than by captured ids.

    private func fileFlow(_ graph: PRGraph) throws -> FlowNode {
        try #require(graph.flows.first { $0.id.contains("file") })
    }
    private func stdinFlow(_ graph: PRGraph) throws -> FlowNode {
        try #require(graph.flows.first { $0.id.contains("stdin") })
    }
    /// The review question that names the stdin flow: binary bytes arriving after a short
    /// first read on a pipe.
    private func pipeQuestion(_ graph: PRGraph) throws -> Consideration {
        let stdin = try stdinFlow(graph)
        return try #require(graph.thingsToThinkAbout.first { $0.relatedIds.contains(stdin.id) })
    }

    @Test func olderFlowsAreNamedByTheirTriggerNotTheirCallChain() throws {
        let graph = try fixtureGraph()
        let file = try fileFlow(graph)
        #expect(file.title.contains("->"))
        #expect(graph.scenarioTitle(for: file) == "bat <file>")
        var modern = file
        modern.behavior = FlowBehavior(nodes: [FlowBehaviorNode(id: "t", label: "Open a file", kind: .trigger)])
        modern.title = "Open a file"
        #expect(graph.scenarioTitle(for: modern) == "Open a file")
    }

    @Test func olderFlowsCondenseToATriggerAndTheirStorySteps() throws {
        let graph = try fixtureGraph()
        let file = try fileFlow(graph)
        let behavior = graph.behavior(for: file)
        #expect(behavior.nodes.first?.kind == .trigger)
        #expect(behavior.nodes.count == file.storySteps.count + 1)
        #expect(behavior.nodes.last?.kind == .outcome)
        #expect(behavior.edges.count == behavior.nodes.count - 1)
        // Every implementation step lands under exactly one stage, in trace order.
        #expect(behavior.nodes.flatMap(\.stepIds) == file.steps.map(\.id))
        // Opening the file is context; the step this PR added marks its stage as changed.
        #expect(behavior.nodes[1].change == .existing)
        let added = try #require(file.steps.first { $0.changeKind == .new })
        let addedStage = try #require(behavior.nodes.first { $0.stepIds.contains(added.id) })
        #expect(addedStage.change != .existing)
        #expect(addedStage.id != behavior.nodes[1].id)
        // Classification lands on the classify stage, not the fallback before it.
        let classify = try #require(file.steps.first { $0.title.localizedCaseInsensitiveContains("classify") })
        let classifyStage = try #require(behavior.nodes.first { $0.stepIds.contains(classify.id) })
        #expect(classifyStage.label.localizedCaseInsensitiveContains("classif"))
    }

    @Test func decisionsAppearAtThePointTheyShapeTheFlow() throws {
        let graph = try fixtureGraph()
        let file = try fileFlow(graph)
        let behavior = graph.behavior(for: file)
        let decisions = graph.annotations(for: file).filter { $0.kind == .decision }
        // The design decisions, and only those — implementation details stay out of the diagram.
        #expect(Set(decisions.map(\.targetId)) == Set(graph.primaryDecisions.map(\.id)))
        #expect(!graph.implementationDecisions.isEmpty)
        // Pinned to a changed stage, never to unchanged context.
        for annotation in decisions {
            #expect(behavior.node(annotation.nodeId)?.change != .existing)
        }
    }

    @Test func aReviewQuestionAppearsOnlyInTheFlowItConcerns() throws {
        let graph = try fixtureGraph()
        let question = try pipeQuestion(graph)
        #expect(graph.annotations(for: try stdinFlow(graph)).contains { $0.kind == .question && $0.targetId == question.id })
        #expect(!graph.annotations(for: try fileFlow(graph)).contains { $0.kind == .question && $0.targetId == question.id })
    }

    @Test func anAnchoredQuestionSitsExactlyWhereTheJudgmentStagePutIt() throws {
        var graph = try fixtureGraph()
        let stdin = try stdinFlow(graph)
        let question = try pipeQuestion(graph)
        let index = try #require(graph.flows.firstIndex { $0.id == stdin.id })
        graph.flows[index].behavior = FlowBehavior(
            nodes: [
                FlowBehaviorNode(id: "pipe", label: "Pipe input", kind: .trigger),
                FlowBehaviorNode(id: "inspect", label: "Inspect buffered data", change: .changed),
                FlowBehaviorNode(id: "classify", label: "Classify")
            ],
            edges: [FlowBehaviorEdge(fromId: "pipe", toId: "inspect"), FlowBehaviorEdge(fromId: "inspect", toId: "classify")]
        )
        let q = try #require(graph.pr.considerations?.firstIndex { $0.id == question.id })
        graph.pr.considerations?[q].flowAnchors = [FlowAnchor(flowId: stdin.id, nodeId: "classify")]
        let annotation = graph.annotations(for: graph.flows[index]).first { $0.targetId == question.id }
        #expect(annotation?.nodeId == "classify")
    }

    @Test func aDecisionKnowsWhichFlowsItAppearsIn() throws {
        let graph = try fixtureGraph()
        let decisionId = try #require(graph.reviewDecisionId(for: try pipeQuestion(graph)))
        #expect(graph.flowAppearances(ofDecision: decisionId).map(\.flow.id).contains(try stdinFlow(graph).id))
    }

    // MARK: - Layout

    private func sampleLayout(_ mode: FlowMode) throws -> (BehaviorDiagramLayout, FlowBehavior) {
        let graph = ContourSampleData.publishTriggeredReindex
        let flow = try #require(graph.flow("publish-index-flow"))
        let behavior = graph.behavior(for: flow).visible(in: mode)
        let ids = Set(behavior.nodes.map(\.id))
        let notes = graph.annotations(for: flow).filter { ids.contains($0.nodeId) }
        return (BehaviorDiagramLayoutEngine.layout(behavior, mode: mode, annotations: notes), behavior)
    }

    @Test func executionReadsTopToBottom() throws {
        for mode in FlowMode.allCases {
            let (layout, behavior) = try sampleLayout(mode)
            #expect(layout.nodes.count == behavior.nodes.count)
            let trigger = try #require(layout.node("publish"))
            #expect(layout.nodes.allSatisfy { $0.frame.minY >= trigger.frame.minY })
            for edge in behavior.edges {
                let a = try #require(layout.node(edge.fromId)), b = try #require(layout.node(edge.toId))
                #expect(b.frame.minY > a.frame.maxY, "\(edge.id) should point down in \(mode)")
                let placed = try #require(layout.edges.first { $0.id == edge.id })
                #expect(placed.points.first == CGPoint(x: a.frame.midX, y: a.frame.maxY))
                #expect(placed.points.last == CGPoint(x: b.frame.midX, y: b.frame.minY))
            }
        }
    }

    @Test func branchesSitSideBySideAndNothingOverlaps() throws {
        let (layout, _) = try sampleLayout(.delta)
        let yes = try #require(layout.node("searchable")), no = try #require(layout.node("retry"))
        #expect(yes.frame.minY == no.frame.minY)
        #expect(!yes.frame.intersects(no.frame))
        // The branch point sits centered over its two outcomes.
        let branch = try #require(layout.node("ok"))
        #expect(abs(branch.frame.midX - (yes.frame.midX + no.frame.midX) / 2) < 1)
        // In Delta the removed and new paths run side by side too.
        #expect(try #require(layout.node("nightly")).frame.minY == (try #require(layout.node("queue"))).frame.minY)

        let boxes = layout.nodes.map(\.frame) + layout.annotations.map(\.frame)
        for (i, a) in boxes.enumerated() {
            for b in boxes[(i + 1)...] { #expect(!a.intersects(b)) }
        }
        #expect(layout.edges.first { $0.edge.label == "Yes" }?.labelPoint != nil)
    }

    @Test func aDecisionNoteHangsOffTheStageItShapes() throws {
        let (layout, _) = try sampleLayout(.after)
        let note = try #require(layout.annotations.first { $0.annotation.targetId == "index-on-publish" })
        let queue = try #require(layout.node("queue"))
        let next = try #require(layout.node("rebuild"))
        #expect(note.frame.minX > queue.frame.midX)
        #expect(note.frame.minY > queue.frame.maxY && note.frame.maxY < next.frame.minY)
    }

    @Test func aCrowdedStageShowsAFewNotesAndCountsTheRest() throws {
        let graph = ContourSampleData.publishTriggeredReindex
        let flow = try #require(graph.flow("publish-index-flow"))
        let behavior = graph.behavior(for: flow).visible(in: .delta)
        let notes = (0..<5).map { i in
            FlowAnnotation(kind: i < 2 ? .decision : .question, targetId: "note-\(i)", nodeId: "queue",
                           text: "A note long enough to wrap onto a second line in the diagram \(i)")
        }
        let cap = BehaviorDiagramLayoutEngine.maxNotesPerStage
        let layout = BehaviorDiagramLayoutEngine.layout(behavior, mode: .delta, annotations: notes)
        #expect(layout.annotations.count == cap)
        #expect(layout.overflow.first { $0.nodeId == "queue" }?.count == notes.count - cap)
        // Nothing hangs into the next stage.
        let next = try #require(layout.node("rebuild"))
        #expect(layout.overflow.allSatisfy { $0.frame.maxY < next.frame.minY })
        #expect(layout.annotations.allSatisfy { $0.frame.maxY < next.frame.minY })
    }

    @Test func boundariesContainTheirStages() throws {
        let (layout, behavior) = try sampleLayout(.delta)
        for placed in layout.boundaries {
            for node in behavior.nodes where node.boundaryId == placed.id {
                #expect(placed.frame.contains(try #require(layout.node(node.id)).frame))
            }
        }
    }

    // MARK: - Chat and prompts

    @Test func askingAboutAStageSendsItsNeighborhood() throws {
        let graph = ContourSampleData.publishTriggeredReindex
        let resolved = try #require(graph.resolve(.flowNode(flowId: "publish-index-flow", nodeId: "queue")))
        #expect(resolved.kind == .flowStep)
        #expect(resolved.lineage.last == "Publish a page")
        #expect(resolved.decisionIds == ["index-on-publish"])
        #expect(resolved.detail.contains("Comes after: Save page revision"))
        #expect(resolved.detail.contains("Leads to: Rebuild search entry"))
        #expect(resolved.detail.contains("enqueue index job"))
        #expect(resolved.detailTarget == .flowNodeDetail(flowId: "publish-index-flow", nodeId: "queue"))
        #expect(ChatContextBuilder.suggestions(for: resolved).contains("What changed at this step?"))
        #expect(graph.resolve(.flowNode(flowId: "publish-index-flow", nodeId: "nope")) == nil)
    }

    @Test func theFlowsStageIsAskedForBehaviorAndTheJudgmentStageForAnchors() {
        let graph = ContourSampleData.publishTriggeredReindex
        let flows = PromptBuilder.flowsPrompt(components: graph.components, entryHints: [])
        // Decisions are pinned to stages afterwards (GraphLinker), so the flows stage no
        // longer waits for them — or sees them.
        #expect(!flows.contains("- index-on-publish:"))
        #expect(!flows.contains("decisionIds"))
        #expect(flows.contains("\"behavior\""))
        #expect(flows.contains("4-8 conceptual stages"))
        #expect(PromptBuilder.judgmentPrompt(graphSoFar: "{}").contains("flowAnchors"))
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
