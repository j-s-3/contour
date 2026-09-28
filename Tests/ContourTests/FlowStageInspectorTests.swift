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
}
