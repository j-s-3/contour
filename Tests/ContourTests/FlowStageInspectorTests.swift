import Testing
import SwiftUI
@testable import Contour

/// `FlowDrillLevel` is already a plain, directly-testable type beside the view (per
/// CLAUDE.md's guidance for this file); `kindLabel` was pulled out of `FlowStageInspector`
/// into a static function so it's testable without a view instance. This pins both: every
/// drill level's label and ordering, `available(for:in:graph:)`'s branch conditions, and
/// every `FlowNodeKind`'s chip label.
struct FlowStageInspectorTests {

    // MARK: - FlowDrillLevel.label

    @Test func everyDrillLevelHasItsOwnLabel() {
        #expect(FlowDrillLevel.behavior.label == "Behavior")
        #expect(FlowDrillLevel.steps.label == "Steps")
        #expect(FlowDrillLevel.implementation.label == "Implementation")
        #expect(FlowDrillLevel.code.label == "Code")
    }

    @Test func drillLevelsOrderFromBehaviorToCode() {
        #expect(FlowDrillLevel.behavior < FlowDrillLevel.steps)
        #expect(FlowDrillLevel.steps < FlowDrillLevel.implementation)
        #expect(FlowDrillLevel.implementation < FlowDrillLevel.code)
        #expect(!(FlowDrillLevel.code < FlowDrillLevel.behavior))
    }

    @Test func drillLevelIdMatchesItsRawValue() {
        for level in FlowDrillLevel.allCases {
            #expect(level.id == level.rawValue)
        }
    }

    // MARK: - FlowDrillLevel.available

    private func graph(flows: [FlowNode] = []) -> PRGraph {
        var g = PRGraph(pr: PRSummary(
            repo: "acme/shop", number: 1, title: "t", author: "a", state: "OPEN",
            branch: "b", baseBranch: "main", headSha: "head", baseSha: "base",
            intent: Statement(text: "intent", provenance: .claim), filesChanged: 1, additions: 1, deletions: 0
        ))
        g.flows = flows
        return g
    }

    @Test func availableAlwaysIncludesBehavior() {
        let node = FlowBehaviorNode(id: "n1", label: "Do thing")
        let flow = FlowNode(id: "f1", title: "Flow")
        #expect(FlowDrillLevel.available(for: node, in: flow, graph: graph(flows: [flow])) == [.behavior])
    }

    @Test func availableIncludesStepsOnlyWhenSubstepsArePresent() {
        let withSubsteps = FlowBehaviorNode(id: "n1", label: "Do thing", substeps: ["a", "b"])
        let flow = FlowNode(id: "f1", title: "Flow")
        #expect(FlowDrillLevel.available(for: withSubsteps, in: flow, graph: graph(flows: [flow])).contains(.steps))

        let withoutSubsteps = FlowBehaviorNode(id: "n1", label: "Do thing")
        #expect(!FlowDrillLevel.available(for: withoutSubsteps, in: flow, graph: graph(flows: [flow])).contains(.steps))
    }

    @Test func availableIncludesImplementationWhenStepsResolveOrComponentIdIsSet() {
        let step = FlowStep(id: "s1", index: 0, title: "Step one")
        let flow = FlowNode(id: "f1", title: "Flow", steps: [step])

        let withResolvedSteps = FlowBehaviorNode(id: "n1", label: "Do thing", stepIds: ["s1"])
        #expect(FlowDrillLevel.available(for: withResolvedSteps, in: flow, graph: graph(flows: [flow])).contains(.implementation))

        let withComponentId = FlowBehaviorNode(id: "n1", label: "Do thing", componentId: "c1")
        #expect(FlowDrillLevel.available(for: withComponentId, in: flow, graph: graph(flows: [flow])).contains(.implementation))

        let withNeither = FlowBehaviorNode(id: "n1", label: "Do thing")
        #expect(!FlowDrillLevel.available(for: withNeither, in: flow, graph: graph(flows: [flow])).contains(.implementation))
    }

    @Test func availableIncludesCodeOnlyWhenSomeRefExistsOnNodeOrItsSteps() {
        let ref = CodeRef(path: "Foo.swift", startLine: 1, endLine: 2)
        let flow = FlowNode(id: "f1", title: "Flow")

        let withNodeRef = FlowBehaviorNode(id: "n1", label: "Do thing", refs: [ref])
        #expect(FlowDrillLevel.available(for: withNodeRef, in: flow, graph: graph(flows: [flow])).contains(.code))

        let step = FlowStep(id: "s1", index: 0, title: "Step one", refs: [ref])
        let flowWithStepRefs = FlowNode(id: "f1", title: "Flow", steps: [step])
        let withStepRef = FlowBehaviorNode(id: "n1", label: "Do thing", stepIds: ["s1"])
        #expect(FlowDrillLevel.available(for: withStepRef, in: flowWithStepRefs, graph: graph(flows: [flowWithStepRefs])).contains(.code))

        let withNoRefs = FlowBehaviorNode(id: "n1", label: "Do thing")
        #expect(!FlowDrillLevel.available(for: withNoRefs, in: flow, graph: graph(flows: [flow])).contains(.code))
    }

    @Test func availableCombinesAllApplicableRungs() {
        let ref = CodeRef(path: "Foo.swift", startLine: 1, endLine: 2)
        let step = FlowStep(id: "s1", index: 0, title: "Step one", refs: [ref])
        let flow = FlowNode(id: "f1", title: "Flow", steps: [step])
        let node = FlowBehaviorNode(id: "n1", label: "Do thing", substeps: ["a"], stepIds: ["s1"])
        #expect(FlowDrillLevel.available(for: node, in: flow, graph: graph(flows: [flow])) == [.behavior, .steps, .implementation, .code])
    }

    // MARK: - FlowStageInspector.kindLabel

    @Test func everyFlowNodeKindHasItsOwnChipLabel() {
        #expect(FlowStageInspector.kindLabel(for: .trigger) == "Trigger")
        #expect(FlowStageInspector.kindLabel(for: .step) == "Stage")
        #expect(FlowStageInspector.kindLabel(for: .decision) == "Branch point")
        #expect(FlowStageInspector.kindLabel(for: .outcome) == "Outcome")
        #expect(FlowStageInspector.kindLabel(for: .external) == "External system")
        #expect(FlowStageInspector.kindLabel(for: .datastore) == "Storage")
        #expect(FlowStageInspector.kindLabel(for: .subflow) == "Shared flow")
    }

    // MARK: - FlowStageInspectorLogic.refs

    /// Pins that evidence is deduplicated and that the node's own refs sort ahead of the
    /// refs traced through its implementation steps (order the "Code" rung relies on).
    @Test func refsCombinesNodeAndStepRefsAndDedupes() {
        let a = CodeRef(path: "A.swift", startLine: 1, endLine: 2)
        let b = CodeRef(path: "B.swift", startLine: 3, endLine: 4)
        let node = FlowBehaviorNode(id: "n1", label: "Do thing", refs: [a])
        let step = FlowStep(id: "s1", index: 0, title: "Step one", refs: [a, b])

        let refs = FlowStageInspectorLogic.refs(node: node, steps: [step])
        #expect(refs == [a, b])
    }

    @Test func refsIsEmptyWhenNeitherNodeNorStepsHaveAny() {
        let node = FlowBehaviorNode(id: "n1", label: "Do thing")
        #expect(FlowStageInspectorLogic.refs(node: node, steps: []).isEmpty)
    }

    // MARK: - FlowStageInspectorLogic.notes(forNodeId:)

    /// Notes pinned to other stages in the same flow must not bleed into this stage's rung.
    @Test func notesForNodeIdKeepsOnlyThisStagesAnnotations() {
        let mine = FlowAnnotation(kind: .decision, targetId: "d1", nodeId: "n1", text: "Chose X")
        let theirs = FlowAnnotation(kind: .decision, targetId: "d2", nodeId: "n2", text: "Chose Y")
        #expect(FlowStageInspectorLogic.notes([mine, theirs], forNodeId: "n1") == [mine])
        #expect(FlowStageInspectorLogic.notes([mine, theirs], forNodeId: "n3").isEmpty)
    }

    // MARK: - FlowStageInspectorLogic.notes(kind:)

    /// Decisions and review questions are shown under separate headings; this pins that the
    /// split by kind doesn't cross-contaminate either list.
    @Test func notesByKindSeparatesDecisionsFromQuestions() {
        let decision = FlowAnnotation(kind: .decision, targetId: "d1", nodeId: "n1", text: "Chose X")
        let question = FlowAnnotation(kind: .question, targetId: "q1", nodeId: "n1", text: "Why not Y?")
        let notes = [decision, question]

        #expect(FlowStageInspectorLogic.notes(notes, kind: .decision) == [decision])
        #expect(FlowStageInspectorLogic.notes(notes, kind: .question) == [question])
    }

    // MARK: - FlowStageInspectorLogic.neighbors

    /// A stage's "In the flow" rung shows what led in (incoming edges' source stages) and
    /// what it leads to (outgoing edges paired with their destination stages), each edge
    /// carrying its branch label along for display.
    @Test func neighborsPairsOutgoingEdgesWithTheirDestinationStages() {
        let trigger = FlowBehaviorNode(id: "trigger", label: "Upload starts")
        let middle = FlowBehaviorNode(id: "middle", label: "Inspect content")
        let outcomeA = FlowBehaviorNode(id: "a", label: "Render")
        let outcomeB = FlowBehaviorNode(id: "b", label: "Reject")
        let behavior = FlowBehavior(
            nodes: [trigger, middle, outcomeA, outcomeB],
            edges: [
                FlowBehaviorEdge(fromId: "trigger", toId: "middle"),
                FlowBehaviorEdge(fromId: "middle", toId: "a", label: "Text"),
                FlowBehaviorEdge(fromId: "middle", toId: "b", label: "Binary"),
            ]
        )

        let (previous, next) = FlowStageInspectorLogic.neighbors(of: "middle", in: behavior)
        #expect(previous == [trigger])
        #expect(next.map(\.node) == [outcomeA, outcomeB])
        #expect(next.map(\.edge.label) == ["Text", "Binary"])
    }

    @Test func neighborsIsEmptyForAnIsolatedStage() {
        let node = FlowBehaviorNode(id: "n1", label: "Alone")
        let behavior = FlowBehavior(nodes: [node], edges: [])
        let (previous, next) = FlowStageInspectorLogic.neighbors(of: "n1", in: behavior)
        #expect(previous.isEmpty)
        #expect(next.isEmpty)
    }

    /// An edge pointing at a stage id that isn't in the behavior graph (a bad id from the
    /// model) is dropped rather than surfaced as a neighbor with no data.
    @Test func neighborsDropsEdgesToUnresolvableStages() {
        let node = FlowBehaviorNode(id: "n1", label: "Stage")
        let behavior = FlowBehavior(nodes: [node], edges: [FlowBehaviorEdge(fromId: "n1", toId: "ghost")])
        let (_, next) = FlowStageInspectorLogic.neighbors(of: "n1", in: behavior)
        #expect(next.isEmpty)
    }

    // MARK: - FlowStageInspectorLogic.levelAfterNodeChange

    /// Selecting a new stage keeps the current rung when it still has something on it, so
    /// jumping between two stages both showing "Implementation" doesn't reset the view.
    @Test func levelAfterNodeChangeKeepsCurrentLevelWhenStillAvailable() {
        let result = FlowStageInspectorLogic.levelAfterNodeChange(
            current: .implementation, available: [.behavior, .implementation]
        )
        #expect(result == .implementation)
    }

    /// Selecting a stage with nothing on the current rung (e.g. jumping from a stage with
    /// steps to one without) falls back to Behavior, which is always available.
    @Test func levelAfterNodeChangeFallsBackToBehaviorWhenCurrentLevelDisappears() {
        let result = FlowStageInspectorLogic.levelAfterNodeChange(current: .steps, available: [.behavior])
        #expect(result == .behavior)
    }

    @Test func levelAfterNodeChangeIsANoOpWhenAlreadyOnBehavior() {
        let result = FlowStageInspectorLogic.levelAfterNodeChange(current: .behavior, available: [.behavior])
        #expect(result == .behavior)
    }
}
