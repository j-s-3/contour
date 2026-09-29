import SwiftUI
import Testing

@testable import Contour

@MainActor
struct DecisionsViewActionsTests {
    @MainActor private final class Box {
        var selectedId: String?
        var expandedIds: Set<String> = []
        var showOther = false
        var placements: [(String, Bool)] = []
        var keyboardFocusCount = 0
    }

    private func decision(_ id: String) -> DecisionNode {
        DecisionNode(
            id: id, title: id, decision: Statement(text: id, provenance: .fact), confidence: .medium)
    }

    private func actions(
        _ box: Box, ids: [String] = ["a", "b", "c"], current: String? = "a", toReview: [String] = ["a", "b", "c"]
    ) -> DecisionsViewActions {
        DecisionsViewActions(
            selectedId: Binding(get: { box.selectedId }, set: { box.selectedId = $0 }),
            expandedIds: Binding(get: { box.expandedIds }, set: { box.expandedIds = $0 }),
            showOther: Binding(get: { box.showOther }, set: { box.showOther = $0 }),
            sequenceIds: ids, currentId: current, toReview: toReview.map(decision),
            onSetToReview: { box.placements.append(($0, $1)) },
            focusKeyboard: { box.keyboardFocusCount += 1 })
    }

    @Test func toggleOtherFlipsTheFlagBothWays() {
        let box = Box()
        actions(box).toggleOther()
        #expect(box.showOther)
        actions(box).toggleOther()
        #expect(!box.showOther)
    }

    @Test func selectRecordsTheIdAndFocusesTheKeyboard() {
        let box = Box()
        actions(box).select("b")
        #expect(box.selectedId == "b")
        #expect(box.keyboardFocusCount == 1)
    }

    @Test func stepMovesWithinTheSequenceAndClampsAtTheEnds() {
        let box = Box()
        #expect(actions(box, current: "a").step(1) == "b")
        #expect(actions(box, current: "c").step(1) == "c")
        #expect(actions(box, current: "a").step(-1) == "a")
        #expect(box.keyboardFocusCount == 3)
    }

    @Test func stepOnAnEmptySequenceDoesNothing() {
        let box = Box()
        #expect(actions(box, ids: [], current: nil).step(1) == nil)
        #expect(box.selectedId == nil)
        #expect(box.keyboardFocusCount == 0)
    }

    @Test func stepBackAndForwardSelectTheNeighbours() {
        let box = Box()
        actions(box, current: "b").stepBack()
        #expect(box.selectedId == "a")
        actions(box, current: "b").stepForward()
        #expect(box.selectedId == "c")
    }

    @Test func revealOtherAndAdvanceShowsOtherDecisionsAndMovesNext() {
        let box = Box()
        actions(box, current: "b").revealOtherAndAdvance()
        #expect(box.showOther)
        #expect(box.selectedId == "c")
    }

    @Test func toggleExpandedInsertsThenRemoves() {
        let box = Box()
        actions(box).toggleExpanded("a")
        #expect(box.expandedIds == ["a"])
        actions(box).toggleExpanded("a")
        #expect(box.expandedIds.isEmpty)
    }

    @Test func removingFromReviewReportsItCollapsesItAndSelectsTheNext() {
        let box = Box()
        box.expandedIds = ["a", "b"]
        actions(box).setToReview("a", false)
        #expect(box.placements.map(\.0) == ["a"])
        #expect(box.placements.map(\.1) == [false])
        #expect(box.expandedIds == ["b"])
        #expect(box.selectedId == "b")
        #expect(box.keyboardFocusCount == 1)
    }

    @Test func addingToReviewSelectsTheAddedDecision() {
        let box = Box()
        actions(box, toReview: ["a"]).setToReview("z", true)
        #expect(box.placements.map(\.1) == [true])
        #expect(box.selectedId == "z")
    }
}
