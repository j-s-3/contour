import Testing
import SwiftUI
@testable import Contour

/// `FlowsView`'s scenario-cycling, drill-down selection, and change-summary condensation
/// were pulled out into `FlowsViewLogic` per CLAUDE.md's guidance for this file, so they're
/// directly testable without a `PRGraph` or a view instance. The rest — the diagram, header,
/// scenario tabs, keyboard focus wiring — is view-rendering with no UI-testing infrastructure
/// in this suite to host it.
struct FlowsViewTests {

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
}
