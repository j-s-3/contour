import Testing
@testable import Contour

/// `ArchitectureInspector.swift` was at 0.00% coverage. Per CLAUDE.md's guidance for this
/// file, the content-formatting logic — `eyebrow`, `unchangedLine`, `properties`,
/// `changeWord`, and `EdgeChange.color` — was pulled out to `static` functions (`eyebrow`
/// additionally takes `graph` explicitly instead of reading `self.graph`) so it's directly
/// testable. The view's `body` and its section/row builders read `GraphStore`/render real
/// SwiftUI content and stay untested here.
struct ArchitectureInspectorTests {

    private func minimalGraph(components: [ComponentNode]) -> PRGraph {
        let pr = PRSummary(
            repo: "acme/shop", number: 1, title: "t", author: "a", state: "OPEN",
            branch: "feature", baseBranch: "main", headSha: "h", baseSha: "b",
            intent: Statement(text: "x", provenance: .fact), filesChanged: 1, additions: 1, deletions: 1
        )
        return PRGraph(pr: pr, components: components)
    }

    // MARK: - eyebrow

    @Test func eyebrowNamesTheParentWhenThereIsOne() {
        let parent = ComponentNode(id: "parent", title: "Search Service", changeKind: .unchanged)
        let child = ComponentNode(id: "child", title: "Indexer", changeKind: .changed, parentId: "parent")
        let graph = minimalGraph(components: [parent, child])
        #expect(ArchitectureInspector.eyebrow(for: child, in: graph) == "Part of Search Service · Changed")
    }

    @Test func eyebrowIsJustPartWithNoParent() {
        let part = ComponentNode(id: "solo", title: "Solo", changeKind: .unchanged)
        let graph = minimalGraph(components: [part])
        #expect(ArchitectureInspector.eyebrow(for: part, in: graph) == "Part")
    }

    @Test func eyebrowTagsEveryChangeKindExceptTouchedAndUnchanged() {
        let graph = minimalGraph(components: [])
        func part(_ kind: ChangeKind) -> ComponentNode { ComponentNode(id: "p", title: "P", changeKind: kind) }
        #expect(ArchitectureInspector.eyebrow(for: part(.new), in: graph) == "Part · New")
        #expect(ArchitectureInspector.eyebrow(for: part(.changed), in: graph) == "Part · Changed")
        #expect(ArchitectureInspector.eyebrow(for: part(.removed), in: graph) == "Part · Removed")
        #expect(ArchitectureInspector.eyebrow(for: part(.touched), in: graph) == "Part")
        #expect(ArchitectureInspector.eyebrow(for: part(.unchanged), in: graph) == "Part")
    }

    // MARK: - unchangedLine

    @Test func unchangedLineDescribesEveryChangeKind() {
        func part(_ kind: ChangeKind) -> ComponentNode { ComponentNode(id: "p", title: "P", changeKind: kind) }
        #expect(ArchitectureInspector.unchangedLine(part(.new)) == "Added by this PR.")
        #expect(ArchitectureInspector.unchangedLine(part(.removed)) == "Removed by this PR.")
        #expect(ArchitectureInspector.unchangedLine(part(.changed)) == "Changed by this PR.")
        #expect(ArchitectureInspector.unchangedLine(part(.touched)) == "Not changed by this PR — drawn for context.")
        #expect(ArchitectureInspector.unchangedLine(part(.unchanged)) == "Not changed by this PR — drawn for context.")
    }

    // MARK: - properties

    private func edge(flow: EdgeFlow = .sync, trust: Bool = false, critical: Bool = false) -> ArchitectureEdge {
        ArchitectureEdge(id: "e", fromId: "a", toId: "b", label: "l", flow: flow, isTrustBoundary: trust, onCriticalPath: critical)
    }

    @Test func propertiesDescribesSyncVsAsync() {
        #expect(ArchitectureInspector.properties(edge(flow: .sync)) == "Synchronous")
        #expect(ArchitectureInspector.properties(edge(flow: .async)) == "Asynchronous")
    }

    @Test func propertiesAppendsTrustBoundaryAndCriticalPathWhenBothApply() {
        #expect(ArchitectureInspector.properties(edge(flow: .async, trust: true, critical: true))
                == "Asynchronous · crosses a trust boundary · on a critical path")
    }

    // MARK: - changeWord / EdgeChange.color

    @Test func changeWordAndColorMatchForEveryEdgeChange() {
        #expect(ArchitectureInspector.changeWord(.new) == "New" && EdgeChange.new.color == .green)
        #expect(ArchitectureInspector.changeWord(.changed) == "Changed" && EdgeChange.changed.color == .blue)
        #expect(ArchitectureInspector.changeWord(.existing) == "Existing" && EdgeChange.existing.color == .secondary)
        #expect(ArchitectureInspector.changeWord(.removed) == "Removed" && EdgeChange.removed.color == .red)
    }
}
