import Testing
import SwiftUI
@testable import Contour

/// `FlowsView`'s scenario-cycling, selection, drill-down and focus-publishing logic were
/// pulled out into `FlowsViewLogic` per CLAUDE.md's guidance for this file, so they're
/// directly testable against a `PRGraph` without a view instance. `FlowsView`'s own methods
/// (`apply`, `openFlow`, `select`, `drill`, `handleKey`, `publishFocus`) are thin wrappers
/// that just apply these results to `@State`, and are `private` to the view's file so they
/// stay untested here — that, plus the diagram, header and scenario tabs, is view-rendering
/// with no UI-testing infrastructure in this suite to host it.
struct FlowsViewTests {

    /// A minimal but valid graph carrying the given flows — the seam this suite uses in
    /// place of `MockAnalysisFixtures` when only `PRGraph.flows` matters.
    private func graph(flows: [FlowNode] = []) -> PRGraph {
        var g = PRGraph(pr: PRSummary(
            repo: "acme/shop", number: 1, title: "t", author: "a", state: "OPEN",
            branch: "b", baseBranch: "main", headSha: "head", baseSha: "base",
            intent: Statement(text: "intent", provenance: .claim), filesChanged: 1, additions: 1, deletions: 0
        ))
        g.flows = flows
        return g
    }

    // MARK: - scenarioOffset

    @Test func openBracketCyclesBackward() {
        #expect(FlowsViewLogic.scenarioOffset(for: "[") == -1)
    }

    @Test func closeBracketCyclesForward() {
        #expect(FlowsViewLogic.scenarioOffset(for: "]") == 1)
    }

    @Test func anyOtherKeyHasNoOffset() {
        #expect(FlowsViewLogic.scenarioOffset(for: "a") == nil)
        #expect(FlowsViewLogic.scenarioOffset(for: "") == nil)
    }

    // MARK: - nextLevel

    @Test func nextLevelFromBehaviorSkipsToTheFirstAvailableRungBelow() {
        #expect(FlowsViewLogic.nextLevel(after: .behavior, available: [.behavior, .implementation, .code]) == .implementation)
    }

    @Test func nextLevelStaysPutWhenNothingIsFurtherDown() {
        #expect(FlowsViewLogic.nextLevel(after: .code, available: [.behavior, .code]) == .code)
        #expect(FlowsViewLogic.nextLevel(after: .implementation, available: [.behavior, .implementation]) == .implementation)
    }

    @Test func nextLevelAdvancesOneRungAtATimeThroughAllAvailable() {
        let all = FlowDrillLevel.allCases
        #expect(FlowsViewLogic.nextLevel(after: .behavior, available: all) == .steps)
        #expect(FlowsViewLogic.nextLevel(after: .steps, available: all) == .implementation)
        #expect(FlowsViewLogic.nextLevel(after: .implementation, available: all) == .code)
    }

    // MARK: - condensedChangeSummary

    private func node(_ id: String, kind: FlowNodeKind = .step, change: FlowChange = .existing, label: String) -> FlowBehaviorNode {
        FlowBehaviorNode(id: id, label: label, kind: kind, change: change)
    }

    @Test func condensedSummaryIsNilWhenNothingChanged() {
        let behavior = FlowBehavior(nodes: [
            node("n1", label: "Read file"),
            node("n2", label: "Render"),
        ])
        #expect(FlowsViewLogic.condensedChangeSummary(behavior) == nil)
    }

    @Test func condensedSummaryIgnoresAChangedTrigger() {
        let behavior = FlowBehavior(nodes: [
            node("n1", kind: .trigger, change: .new, label: "Upload asset"),
        ])
        #expect(FlowsViewLogic.condensedChangeSummary(behavior) == nil)
    }

    @Test func condensedSummaryNamesUpToThreeChangedStages() {
        let behavior = FlowBehavior(nodes: [
            node("n1", change: .new, label: "A"),
            node("n2", change: .changed, label: "B"),
        ])
        #expect(FlowsViewLogic.condensedChangeSummary(behavior) == "Changes “A”, “B”.")
    }

    @Test func condensedSummaryTruncatesAtThreeAndCountsTheRest() {
        let behavior = FlowBehavior(nodes: [
            node("n1", change: .new, label: "A"),
            node("n2", change: .changed, label: "B"),
            node("n3", change: .removed, label: "C"),
            node("n4", change: .new, label: "D"),
        ])
        #expect(FlowsViewLogic.condensedChangeSummary(behavior) == "Changes “A”, “B”, “C”, and 1 more.")
    }

    // MARK: - recognizesScenarioKey

    @Test func recognizesScenarioKeyRequiresMoreThanOneFlow() {
        #expect(!FlowsViewLogic.recognizesScenarioKey("[", modifiers: [], flowCount: 1))
        #expect(FlowsViewLogic.recognizesScenarioKey("[", modifiers: [], flowCount: 2))
    }

    @Test func recognizesScenarioKeyRejectsOurModifiers() {
        #expect(!FlowsViewLogic.recognizesScenarioKey("]", modifiers: .command, flowCount: 3))
        #expect(!FlowsViewLogic.recognizesScenarioKey("]", modifiers: .control, flowCount: 3))
        #expect(!FlowsViewLogic.recognizesScenarioKey("]", modifiers: .option, flowCount: 3))
    }

    @Test func recognizesScenarioKeyAllowsOtherModifiers() {
        // Shift-] is still a bracket keypress we own; only command/control/option aren't ours.
        #expect(FlowsViewLogic.recognizesScenarioKey("]", modifiers: .shift, flowCount: 3))
    }

    @Test func recognizesScenarioKeyRejectsUnrecognizedCharacters() {
        #expect(!FlowsViewLogic.recognizesScenarioKey("x", modifiers: [], flowCount: 3))
    }

    // MARK: - currentFlow

    private func flow(_ id: String, title: String = "Flow") -> FlowNode { FlowNode(id: id, title: title) }

    @Test func currentFlowIsTheSelectedOne() {
        let g = graph(flows: [flow("f1"), flow("f2")])
        #expect(FlowsViewLogic.currentFlow(in: g, selectedFlowId: "f2")?.id == "f2")
    }

    @Test func currentFlowFallsBackToTheFirstWhenNothingIsSelected() {
        let g = graph(flows: [flow("f1"), flow("f2")])
        #expect(FlowsViewLogic.currentFlow(in: g, selectedFlowId: nil)?.id == "f1")
    }

    @Test func currentFlowFallsBackToTheFirstWhenTheSelectionIsStale() {
        let g = graph(flows: [flow("f1"), flow("f2")])
        #expect(FlowsViewLogic.currentFlow(in: g, selectedFlowId: "gone")?.id == "f1")
    }

    @Test func currentFlowIsNilWhenThereAreNoFlows() {
        #expect(FlowsViewLogic.currentFlow(in: graph(), selectedFlowId: nil) == nil)
    }

    // MARK: - applying (Focus)

    @Test func applyingAKnownFocusSelectsItsFlowAndNodeAtBehaviorLevel() {
        let g = graph(flows: [flow("f1"), flow("f2")])
        let result = FlowsViewLogic.applying(FlowsView.Focus(flowId: "f2", nodeId: "n1"), to: g)
        #expect(result?.selectedFlowId == "f2")
        #expect(result?.selectedNodeId == "n1")
        #expect(result?.level == .behavior)
    }

    @Test func applyingAFocusWithNoNodeClearsTheNodeSelection() {
        let g = graph(flows: [flow("f1")])
        let result = FlowsViewLogic.applying(FlowsView.Focus(flowId: "f1"), to: g)
        #expect(result?.selectedNodeId == nil)
    }

    @Test func applyingNilFocusChangesNothing() {
        #expect(FlowsViewLogic.applying(nil, to: graph(flows: [flow("f1")])) == nil)
    }

    @Test func applyingAFocusForAnUnknownFlowChangesNothing() {
        let g = graph(flows: [flow("f1")])
        #expect(FlowsViewLogic.applying(FlowsView.Focus(flowId: "gone"), to: g) == nil)
    }

    // MARK: - opening

    @Test func openingAKnownFlowSelectsItAndClearsTheNode() {
        let g = graph(flows: [flow("f1"), flow("f2")])
        let result = FlowsViewLogic.opening("f2", in: g)
        #expect(result?.selectedFlowId == "f2")
        #expect(result?.selectedNodeId == nil)
    }

    @Test func openingAnUnknownFlowIsIgnored() {
        #expect(FlowsViewLogic.opening("gone", in: graph(flows: [flow("f1")])) == nil)
    }

    // MARK: - selecting

    @Test func selectingADifferentNodeResetsTheLevelToBehavior() {
        let result = FlowsViewLogic.selecting(node("n2", label: "B"), currentSelectedNodeId: "n1")
        #expect(result.nodeId == "n2")
        #expect(result.level == .behavior)
    }

    @Test func reselectingTheSameNodeLeavesTheLevelAlone() {
        let result = FlowsViewLogic.selecting(node("n1", label: "A"), currentSelectedNodeId: "n1")
        #expect(result.nodeId == "n1")
        #expect(result.level == nil)
    }

    @Test func selectingNilClearsTheSelectionAndResetsTheLevel() {
        let result = FlowsViewLogic.selecting(nil, currentSelectedNodeId: "n1")
        #expect(result.nodeId == nil)
        #expect(result.level == .behavior)
    }

    // MARK: - drilling

    @Test func drillingANewlySelectedStageOpensAtTheFirstRungBelowBehavior() {
        let result = FlowsViewLogic.drilling(
            node("n2", label: "B"), currentSelectedNodeId: "n1", currentLevel: .code,
            available: [.behavior, .steps, .implementation]
        )
        #expect(result.nodeId == "n2")
        #expect(result.level == .steps)
    }

    @Test func drillingTheSameStageAgainStepsOneRungDownFromTheCurrentLevel() {
        let result = FlowsViewLogic.drilling(
            node("n1", label: "A"), currentSelectedNodeId: "n1", currentLevel: .steps,
            available: [.behavior, .steps, .implementation, .code]
        )
        #expect(result.nodeId == "n1")
        #expect(result.level == .implementation)
    }

    @Test func drillingStaysAtTheDeepestAvailableRung() {
        let result = FlowsViewLogic.drilling(
            node("n1", label: "A"), currentSelectedNodeId: "n1", currentLevel: .code,
            available: [.behavior, .code]
        )
        #expect(result.level == .code)
    }

    // MARK: - focusToPublish

    @Test func focusToPublishIsNilWhenThereIsNoFlow() {
        #expect(FlowsViewLogic.focusToPublish(flow: nil, node: nil) == nil)
    }

    @Test func focusToPublishNamesTheFlowWhenNoStageIsSelected() {
        #expect(FlowsViewLogic.focusToPublish(flow: flow("f1"), node: nil) == .flow("f1"))
    }

    @Test func focusToPublishNamesTheStageWhenOneIsSelected() {
        let n = node("n1", label: "A")
        #expect(FlowsViewLogic.focusToPublish(flow: flow("f1"), node: n) == .flowNode(flowId: "f1", nodeId: "n1"))
    }
}
