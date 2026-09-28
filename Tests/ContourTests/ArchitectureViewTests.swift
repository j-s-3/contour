import Testing
@testable import Contour

/// `ArchitectureView.swift` was at 0.00% coverage. Per CLAUDE.md's "extract layout/
/// selection/formatting logic" guidance, `boxes`/`arrows`/`containers` — the real state-
/// derivation logic that turns a `PRGraph`/`ArchLevel`/`DiagramMode` into what the drawing
/// shows — were pulled out to `static` functions taking `graph`/`mode` explicitly instead
/// of reading `self.graph`/`self.mode`. The private instance methods now just forward, so
/// the view body is unchanged. `ChangeKind.emphasis`/`EdgeChange.emphasis`/
/// `ArchitecturalImpact.color` were already internal. The view's `body`, header/breadcrumb/
/// legend builders, and the zoom/selection methods (`@State`/`@Environment`-driven) stay
/// untested — no UI-testing infrastructure in this suite to host them.
struct ArchitectureViewTests {

    private func minimalGraph(components: [ComponentNode], boundaries: [SystemBoundary] = []) -> PRGraph {
        let pr = PRSummary(
            repo: "acme/shop", number: 1, title: "t", author: "a", state: "OPEN",
            branch: "feature", baseBranch: "main", headSha: "h", baseSha: "b",
            intent: Statement(text: "x", provenance: .fact), filesChanged: 1, additions: 1, deletions: 1
        )
        return PRGraph(pr: pr, components: components, boundaries: boundaries)
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
}
