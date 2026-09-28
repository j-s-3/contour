import Testing
@testable import Contour

/// `ArchitectureView.swift` was at 0.00% coverage, then 16.11% after #160 pulled `boxes`/
/// `arrows`/`containers` out to `static` functions taking `graph`/`mode` explicitly instead
/// of reading `self.graph`/`self.mode`. This suite continues that extraction (per CLAUDE.md's
/// "extract layout/selection/formatting logic" guidance) for the rest of the instance methods
/// that were still reading `@State`/`@Environment` directly: `zoom(into:)`/`zoom(to:)`,
/// `reveal(_:)`, `dropHiddenSelection()`, `publishFocus()` and the legend's badge derivation
/// each now delegate to a `nonisolated static func` that takes the relevant state as
/// parameters and returns what should change, leaving only the `path`/`selection`/`actions`
/// mutation itself in the view. `arrows` also picked up the `nonisolated` #185 missed (it
/// wasn't yet called from a nonisolated context when that pass ran). The view's `body`,
/// header/breadcrumb builders, and the `@FocusState`/`@Binding`/animation glue that's left in
/// `zoom(to:)`/`reveal(_:)`/`dropHiddenSelection()`/`publishFocus()` stay untested — no
/// UI-testing infrastructure in this suite to host them.
struct ArchitectureViewTests {

    private func minimalGraph(components: [ComponentNode], boundaries: [SystemBoundary] = [],
                               edges: [ArchitectureEdge] = [], decisions: [DecisionNode] = [],
                               considerations: [Consideration]? = nil) -> PRGraph {
        let pr = PRSummary(
            repo: "acme/shop", number: 1, title: "t", author: "a", state: "OPEN",
            branch: "feature", baseBranch: "main", headSha: "h", baseSha: "b",
            intent: Statement(text: "x", provenance: .fact), filesChanged: 1, additions: 1, deletions: 1,
            considerations: considerations
        )
        return PRGraph(pr: pr, components: components, decisions: decisions, architectureEdges: edges, boundaries: boundaries)
    }

    // MARK: - boxes: before/after filtering

    @Test func boxesExcludeNewPartsInBeforeModeAndRemovedPartsInAfterMode() {
        let graph = minimalGraph(components: [
            ComponentNode(id: "new-part", title: "New", changeKind: .new),
            ComponentNode(id: "removed-part", title: "Removed", changeKind: .removed),
        ])
        let level = graph.architectureLevel(path: [])

        #expect(ArchitectureView.boxes(level, graph: graph, mode: .before).map(\.id) == ["removed-part"])
        #expect(ArchitectureView.boxes(level, graph: graph, mode: .after).map(\.id) == ["new-part"])
        #expect(Set(ArchitectureView.boxes(level, graph: graph, mode: .delta).map(\.id)) == Set(["new-part", "removed-part"]))
    }

    // MARK: - boxes: emphasis only applies in delta mode

    @Test func emphasisReflectsChangeKindOnlyInDeltaMode() {
        let graph = minimalGraph(components: [ComponentNode(id: "p", title: "P", changeKind: .new)])
        let level = graph.architectureLevel(path: [])

        #expect(ArchitectureView.boxes(level, graph: graph, mode: .delta).first?.emphasis == .added)
        #expect(ArchitectureView.boxes(level, graph: graph, mode: .after).first?.emphasis == .context)
    }

    // MARK: - boxes: the change phrase follows the selected mode

    @Test func changePhraseFollowsTheSelectedMode() {
        let part = ComponentNode(id: "p", title: "P", changeKind: .changed,
                                  delta: ResponsibilityDelta(before: "old", after: "new"))
        let graph = minimalGraph(components: [part])
        let level = graph.architectureLevel(path: [])

        let delta = ArchitectureView.boxes(level, graph: graph, mode: .delta).first
        #expect(delta?.changeBefore == "old" && delta?.changeAfter == "new")

        let before = ArchitectureView.boxes(level, graph: graph, mode: .before).first
        #expect(before?.changeBefore == "old" && before?.changeAfter == nil)

        let after = ArchitectureView.boxes(level, graph: graph, mode: .after).first
        #expect(after?.changeBefore == nil && after?.changeAfter == "new")
    }

    // MARK: - boxes: hasInside

    @Test func hasInsideIsTrueOnlyForATopLevelPartWithChildren() {
        let parent = ComponentNode(id: "parent", title: "Parent", changeKind: .unchanged)
        let child = ComponentNode(id: "child", title: "Child", changeKind: .unchanged, parentId: "parent")
        let leaf = ComponentNode(id: "leaf", title: "Leaf", changeKind: .unchanged)
        let graph = minimalGraph(components: [parent, child, leaf])
        let level = graph.architectureLevel(path: [])

        let boxes = ArchitectureView.boxes(level, graph: graph, mode: .delta)
        #expect(boxes.first { $0.id == "parent" }?.hasInside == true)
        #expect(boxes.first { $0.id == "leaf" }?.hasInside == false)
    }

    // MARK: - containers

    @Test func containersIncludeOnlyMembersActuallyDrawn() {
        let a = ComponentNode(id: "a", title: "A", changeKind: .unchanged)
        let boundary = SystemBoundary(id: "boundary-1", label: "Trust zone", kind: .trust, componentIds: ["a"])
        let graph = minimalGraph(components: [a], boundaries: [boundary])
        let level = graph.architectureLevel(path: [])

        let containers = ArchitectureView.containers(level, graph: graph, mode: .delta)
        #expect(containers.count == 1)
        #expect(containers.first?.memberIds == ["a"])
        #expect(containers.first?.kind == .trust)
    }

    @Test func containersDropBoundariesWithNoDrawnMembers() {
        let boundary = SystemBoundary(id: "boundary-1", label: "Empty", componentIds: ["nowhere"])
        let graph = minimalGraph(components: [], boundaries: [boundary])
        let level = graph.architectureLevel(path: [])
        #expect(ArchitectureView.containers(level, graph: graph, mode: .delta).isEmpty)
    }

    // MARK: - ChangeKind / EdgeChange / ArchitecturalImpact

    @Test func everyChangeKindMapsToItsArchEmphasis() {
        #expect(ChangeKind.new.emphasis == .added)
        #expect(ChangeKind.changed.emphasis == .changed)
        #expect(ChangeKind.removed.emphasis == .removed)
        #expect(ChangeKind.touched.emphasis == .context)
        #expect(ChangeKind.unchanged.emphasis == .context)
    }

    @Test func everyEdgeChangeMapsToItsArchEmphasis() {
        #expect(EdgeChange.new.emphasis == .added)
        #expect(EdgeChange.changed.emphasis == .changed)
        #expect(EdgeChange.removed.emphasis == .removed)
        #expect(EdgeChange.existing.emphasis == .context)
    }

    @Test func everyArchitecturalImpactHasAColor() {
        #expect(ArchitecturalImpact.none.color == .secondary)
        #expect(ArchitecturalImpact.low.color == .blue)
        #expect(ArchitecturalImpact.moderate.color == .orange)
        #expect(ArchitecturalImpact.significant.color == .red)
    }

    // MARK: - legendInfo

    @Test func legendInfoIsNilOutsideDeltaMode() {
        let part = ComponentNode(id: "p", title: "P", changeKind: .new)
        let graph = minimalGraph(components: [part])
        let level = graph.architectureLevel(path: [])
        #expect(ArchitectureView.legendInfo(level, graph: graph, mode: .before) == nil)
        #expect(ArchitectureView.legendInfo(level, graph: graph, mode: .after) == nil)
    }

    @Test func legendInfoIsNilWhenNothingChangedAtThisLevel() {
        let part = ComponentNode(id: "p", title: "P", changeKind: .unchanged)
        let graph = minimalGraph(components: [part])
        let level = graph.architectureLevel(path: [])
        #expect(ArchitectureView.legendInfo(level, graph: graph, mode: .delta) == nil)
    }

    @Test func legendInfoListsTheChangeKindsPresentInFixedOrder() {
        let removed = ComponentNode(id: "r", title: "R", changeKind: .removed)
        let added = ComponentNode(id: "n", title: "N", changeKind: .new)
        let graph = minimalGraph(components: [removed, added])
        let level = graph.architectureLevel(path: [])
        let info = ArchitectureView.legendInfo(level, graph: graph, mode: .delta)
        #expect(info?.kinds == [.added, .removed])
        #expect(info?.hasDecision == false)
        #expect(info?.hasQuestion == false)
        #expect(info?.hasAsync == false)
    }

    @Test func legendInfoFlagsAnAsynchronousArrow() {
        let a = ComponentNode(id: "a", title: "A", changeKind: .unchanged)
        let b = ComponentNode(id: "b", title: "B", changeKind: .unchanged)
        let edge = ArchitectureEdge(id: "e1", fromId: "a", toId: "b", label: "publishes", flow: .async, change: .new)
        let graph = minimalGraph(components: [a, b], edges: [edge])
        let level = graph.architectureLevel(path: [])
        #expect(ArchitectureView.legendInfo(level, graph: graph, mode: .delta)?.hasAsync == true)
    }

    @Test func legendInfoFlagsAPartMarkedWithADecisionToReview() {
        let part = ComponentNode(id: "p", title: "P", changeKind: .changed)
        let decision = DecisionNode(id: "d1", title: "D", decision: Statement(text: "x", provenance: .fact),
                                     confidence: .medium, componentIds: ["p"], significance: .high)
        let graph = minimalGraph(components: [part], decisions: [decision])
        let level = graph.architectureLevel(path: [])
        #expect(ArchitectureView.legendInfo(level, graph: graph, mode: .delta)?.hasDecision == true)
    }

    @Test func legendInfoFlagsAPartMarkedWithAReviewQuestion() {
        let part = ComponentNode(id: "p", title: "P", changeKind: .changed)
        let consideration = Consideration(id: "c1", question: "Why?", detail: "", relatedIds: ["p"])
        let graph = minimalGraph(components: [part], considerations: [consideration])
        let level = graph.architectureLevel(path: [])
        #expect(ArchitectureView.legendInfo(level, graph: graph, mode: .delta)?.hasQuestion == true)
    }

    // MARK: - zoomTarget

    @Test func zoomTargetReturnsAncestryWhenThePartHasChildren() {
        let parent = ComponentNode(id: "parent", title: "Parent", changeKind: .unchanged)
        let child = ComponentNode(id: "child", title: "Child", changeKind: .unchanged, parentId: "parent")
        let graph = minimalGraph(components: [parent, child])
        #expect(ArchitectureView.zoomTarget(into: "parent", graph: graph) == ["parent"])
    }

    @Test func zoomTargetIsNilWhenThePartHasNoChildrenToZoomInto() {
        let leaf = ComponentNode(id: "leaf", title: "Leaf", changeKind: .unchanged)
        let graph = minimalGraph(components: [leaf])
        #expect(ArchitectureView.zoomTarget(into: "leaf", graph: graph) == nil)
    }

    // MARK: - selectionAfterZoom

    @Test func selectionAfterZoomKeepsThePreviousFocusWhenStillDrawnAtTheNewPath() {
        let parent = ComponentNode(id: "parent", title: "Parent", changeKind: .unchanged)
        let child = ComponentNode(id: "child", title: "Child", changeKind: .unchanged, parentId: "parent")
        let graph = minimalGraph(components: [parent, child])
        // Zooming out from "parent" back to the top level, where "parent" is still a drawn box.
        #expect(ArchitectureView.selectionAfterZoom(from: ["parent"], to: [], graph: graph) == .node("parent"))
    }

    @Test func selectionAfterZoomDropsThePreviousFocusWhenNoLongerDrawn() {
        let a = ComponentNode(id: "a", title: "A", changeKind: .unchanged)
        let b = ComponentNode(id: "b", title: "B", changeKind: .unchanged)
        let graph = minimalGraph(components: [a, b])
        // Zooming from "a" into "b": "a" isn't inside "b" and no edge connects them, so it
        // isn't drawn at the new level at all.
        #expect(ArchitectureView.selectionAfterZoom(from: ["a"], to: ["b"], graph: graph) == nil)
    }

    @Test func selectionAfterZoomIsNilWithNoPreviousFocus() {
        let graph = minimalGraph(components: [ComponentNode(id: "a", title: "A", changeKind: .unchanged)])
        #expect(ArchitectureView.selectionAfterZoom(from: [], to: [], graph: graph) == nil)
    }

    // MARK: - revealTarget

    @Test func revealTargetForANodeZoomsToItsAncestryAndSelectsIt() {
        let parent = ComponentNode(id: "parent", title: "Parent", changeKind: .unchanged)
        let child = ComponentNode(id: "child", title: "Child", changeKind: .unchanged, parentId: "parent")
        let graph = minimalGraph(components: [parent, child])
        let target = ArchitectureView.revealTarget(.node("child"), graph: graph)
        #expect(target?.path == ["parent"])
        #expect(target?.selection == .node("child"))
    }

    @Test func revealTargetIsNilForANodeThatDoesNotResolve() {
        let graph = minimalGraph(components: [])
        #expect(ArchitectureView.revealTarget(.node("ghost"), graph: graph) == nil)
    }

    @Test func revealTargetForAnEdgeUsesTheOutermostLevelWhereItIsItsOwnArrow() {
        let parent = ComponentNode(id: "parent", title: "Parent", changeKind: .unchanged)
        let childA = ComponentNode(id: "childA", title: "A", changeKind: .unchanged, parentId: "parent")
        let childB = ComponentNode(id: "childB", title: "B", changeKind: .unchanged, parentId: "parent")
        let edge = ArchitectureEdge(id: "e1", fromId: "childA", toId: "childB", label: "uses")
        let graph = minimalGraph(components: [parent, childA, childB], edges: [edge])
        // Both endpoints collapse to "parent" at the top level, so this arrow only becomes its
        // own edge once the reviewer is zoomed into "parent".
        let target = ArchitectureView.revealTarget(.edge("e1"), graph: graph)
        #expect(target?.path == ["parent"])
        #expect(target?.selection == .edge("e1"))
    }

    @Test func revealTargetForATopLevelEdgeStaysAtTheRoot() {
        let a = ComponentNode(id: "a", title: "A", changeKind: .unchanged)
        let b = ComponentNode(id: "b", title: "B", changeKind: .unchanged)
        let edge = ArchitectureEdge(id: "e1", fromId: "a", toId: "b", label: "uses")
        let graph = minimalGraph(components: [a, b], edges: [edge])
        let target = ArchitectureView.revealTarget(.edge("e1"), graph: graph)
        #expect(target?.path == [])
        #expect(target?.selection == .edge("e1"))
    }

    @Test func revealTargetIsNilForAnEdgeThatNoLongerExists() {
        let graph = minimalGraph(components: [])
        #expect(ArchitectureView.revealTarget(.edge("ghost"), graph: graph) == nil)
    }

    // MARK: - selectionAfterHidingCheck

    @Test func selectionAfterHidingCheckIsNilWhenNothingIsSelected() {
        let graph = minimalGraph(components: [])
        let level = graph.architectureLevel(path: [])
        #expect(ArchitectureView.selectionAfterHidingCheck(nil, level: level, graph: graph, mode: .delta) == nil)
    }

    @Test func selectionAfterHidingCheckKeepsANodeStillDrawn() {
        let part = ComponentNode(id: "p", title: "P", changeKind: .unchanged)
        let graph = minimalGraph(components: [part])
        let level = graph.architectureLevel(path: [])
        #expect(ArchitectureView.selectionAfterHidingCheck(.node("p"), level: level, graph: graph, mode: .delta) == .node("p"))
    }

    @Test func selectionAfterHidingCheckDropsANodeHiddenByTheMode() {
        // A newly-added part is excluded from Before mode's boxes.
        let part = ComponentNode(id: "p", title: "P", changeKind: .new)
        let graph = minimalGraph(components: [part])
        let level = graph.architectureLevel(path: [])
        #expect(ArchitectureView.selectionAfterHidingCheck(.node("p"), level: level, graph: graph, mode: .before) == nil)
    }

    @Test func selectionAfterHidingCheckDropsAnEdgeHiddenByTheMode() {
        let a = ComponentNode(id: "a", title: "A", changeKind: .unchanged)
        let b = ComponentNode(id: "b", title: "B", changeKind: .unchanged)
        let edge = ArchitectureEdge(id: "e1", fromId: "a", toId: "b", label: "uses", change: .new)
        let graph = minimalGraph(components: [a, b], edges: [edge])
        let level = graph.architectureLevel(path: [])
        #expect(ArchitectureView.selectionAfterHidingCheck(.edge("e1"), level: level, graph: graph, mode: .before) == nil)
    }

    // MARK: - focusSubject

    @Test func focusSubjectForANodeSelectionIsItsComponent() {
        #expect(ArchitectureView.focusSubject(selection: .node("p"), path: []) == .component("p"))
    }

    @Test func focusSubjectForAnEdgeSelectionIsItsRelationship() {
        #expect(ArchitectureView.focusSubject(selection: .edge("e1"), path: ["p"]) == .relationship("e1"))
    }

    @Test func focusSubjectWithNoSelectionFallsBackToThePartBeingZoomedInto() {
        #expect(ArchitectureView.focusSubject(selection: nil, path: ["parent", "child"]) == .component("child"))
    }

    @Test func focusSubjectIsNilAtTheRootWithNoSelectionAndNoPath() {
        #expect(ArchitectureView.focusSubject(selection: nil, path: []) == nil)
    }
}
