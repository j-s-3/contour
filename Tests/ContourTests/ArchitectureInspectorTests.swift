import SwiftUI
import Testing

@testable import Contour

struct ArchitectureInspectorTests {
    private func minimalGraph(components: [ComponentNode]) -> PRGraph {
        let pr = PRSummary(
            repo: "acme/shop", number: 1, title: "t", author: "a", state: "OPEN",
            branch: "feature", baseBranch: "main", headSha: "h", baseSha: "b",
            intent: Statement(text: "x", provenance: .fact), filesChanged: 1, additions: 1, deletions: 1
        )
        return PRGraph(pr: pr, components: components)
    }

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

    @Test func unchangedLineDescribesEveryChangeKind() {
        func part(_ kind: ChangeKind) -> ComponentNode { ComponentNode(id: "p", title: "P", changeKind: kind) }
        #expect(ArchitectureInspector.unchangedLine(part(.new)) == "Added by this PR.")
        #expect(ArchitectureInspector.unchangedLine(part(.removed)) == "Removed by this PR.")
        #expect(ArchitectureInspector.unchangedLine(part(.changed)) == "Changed by this PR.")
        #expect(ArchitectureInspector.unchangedLine(part(.touched)) == "Not changed by this PR — drawn for context.")
        #expect(ArchitectureInspector.unchangedLine(part(.unchanged)) == "Not changed by this PR — drawn for context.")
    }

    private func edge(flow: EdgeFlow = .sync, trust: Bool = false, critical: Bool = false) -> ArchitectureEdge {
        ArchitectureEdge(
            id: "e", fromId: "a", toId: "b", label: "l", flow: flow, isTrustBoundary: trust, onCriticalPath: critical)
    }

    @Test func propertiesDescribesSyncVsAsync() {
        #expect(ArchitectureInspector.properties(edge(flow: .sync)) == "Synchronous")
        #expect(ArchitectureInspector.properties(edge(flow: .async)) == "Asynchronous")
    }

    @Test func propertiesAppendsTrustBoundaryAndCriticalPathWhenBothApply() {
        #expect(
            ArchitectureInspector.properties(edge(flow: .async, trust: true, critical: true))
                == "Asynchronous · crosses a trust boundary · on a critical path")
    }

    @Test func changeWordAndColorMatchForEveryEdgeChange() {
        #expect(ArchitectureInspector.changeWord(.new) == "New" && EdgeChange.new.color == .green)
        #expect(ArchitectureInspector.changeWord(.changed) == "Changed" && EdgeChange.changed.color == .blue)
        #expect(ArchitectureInspector.changeWord(.existing) == "Existing" && EdgeChange.existing.color == .secondary)
        #expect(ArchitectureInspector.changeWord(.removed) == "Removed" && EdgeChange.removed.color == .red)
    }

    @Test func showsUnchangedNoteWhenThereIsNoDeltaAtAll() {
        let part = ComponentNode(id: "p", title: "P", changeKind: .unchanged)
        #expect(ArchitectureInspector.showsUnchangedNote(part))
    }

    @Test func showsUnchangedNoteWhenOnlyOneSideOfBeforeAfterIsPresent() {
        let onlyBefore = ComponentNode(
            id: "p", title: "P", changeKind: .changed,
            delta: ResponsibilityDelta(before: "old", after: nil))
        let onlyAfter = ComponentNode(
            id: "p", title: "P", changeKind: .changed,
            delta: ResponsibilityDelta(before: nil, after: "new"))
        #expect(ArchitectureInspector.showsUnchangedNote(onlyBefore))
        #expect(ArchitectureInspector.showsUnchangedNote(onlyAfter))
    }

    @Test func doesNotShowUnchangedNoteWithASummaryOrACompleteBeforeAfterPair() {
        let withSummary = ComponentNode(
            id: "p", title: "P", changeKind: .changed,
            delta: ResponsibilityDelta(summary: Statement(text: "x", provenance: .fact)))
        let withPair = ComponentNode(
            id: "p", title: "P", changeKind: .changed,
            delta: ResponsibilityDelta(before: "old", after: "new"))
        #expect(!ArchitectureInspector.showsUnchangedNote(withSummary))
        #expect(!ArchitectureInspector.showsUnchangedNote(withPair))
    }

    @Test func connectionIconPointsDownForIncomingAndUpForOutgoing() {
        #expect(ArchitectureInspector.connectionIcon(direction: "from") == "arrow.down.right")
        #expect(ArchitectureInspector.connectionIcon(direction: "to") == "arrow.up.right")
    }

    @Test func connectionLabelFallsBackToAnEmDashWhenUnlabeled() {
        #expect(ArchitectureInspector.connectionLabel(edge(flow: .sync)) == "l")
        #expect(
            ArchitectureInspector.connectionLabel(
                ArchitectureEdge(fromId: "a", toId: "b", label: "")) == "—")
    }

    @Test func connectionLabelWeightAndColorAreQuietOnlyForExisting() {
        #expect(ArchitectureInspector.connectionLabelWeight(.existing) == .regular)
        #expect(ArchitectureInspector.connectionLabelColor(.existing) == .primary)
        #expect(ArchitectureInspector.connectionLabelWeight(.new) == .semibold)
        #expect(ArchitectureInspector.connectionLabelColor(.new) == EdgeChange.new.color)
    }

    @Test func connectionCaptionJoinsDirectionAndTitle() {
        #expect(ArchitectureInspector.connectionCaption(direction: "from", otherTitle: "Indexer") == "from Indexer")
    }

    @Test func relationshipEyebrowIsUnqualifiedOnlyForExisting() {
        #expect(ArchitectureInspector.relationshipEyebrow(.existing) == "Relationship")
        #expect(ArchitectureInspector.relationshipEyebrow(.new) == "Relationship · New")
        #expect(ArchitectureInspector.relationshipEyebrow(.changed) == "Relationship · Changed")
        #expect(ArchitectureInspector.relationshipEyebrow(.removed) == "Relationship · Removed")
    }

    @Test func crossesLabelFallsBackToNotLabeled() {
        #expect(ArchitectureInspector.crossesLabel(edge(flow: .sync)) == "l")
        #expect(
            ArchitectureInspector.crossesLabel(ArchitectureEdge(fromId: "a", toId: "b", label: "")) == "Not labeled")
    }

    @Test func relationshipThisPRNotePrefersANonEmptyNote() {
        var e = edge(flow: .sync)
        e.note = "Now buffers the upload."
        e.change = .existing
        let note = ArchitectureInspector.relationshipThisPRNote(e)
        #expect(note?.text == "Now buffers the upload.")
        #expect(note?.isFallback == false)
    }

    @Test func relationshipThisPRNoteFallsBackForAnExistingRelationshipWithNoNote() {
        var e = edge(flow: .sync)
        e.note = nil
        e.change = .existing
        let note = ArchitectureInspector.relationshipThisPRNote(e)
        #expect(note?.text == "Not changed by this PR — drawn for context.")
        #expect(note?.isFallback == true)
    }

    @Test func relationshipThisPRNoteIsNilForANewRelationshipWithNoNote() {
        var e = edge(flow: .sync)
        e.note = nil
        e.change = .new
        #expect(ArchitectureInspector.relationshipThisPRNote(e) == nil)
    }

    @Test func relationshipThisPRNoteTreatsAnEmptyNoteAsAbsent() {
        var e = edge(flow: .sync)
        e.note = ""
        e.change = .new
        #expect(ArchitectureInspector.relationshipThisPRNote(e) == nil)
    }

    @Test func foldedEdgeLineFormatsAnArrowBetweenTitles() {
        #expect(
            ArchitectureInspector.foldedEdgeLine(fromTitle: "Web", toTitle: "API", label: "request")
                == "Web → API: request")
    }

    @Test func sharedFlowsKeepsOnlyFlowsPresentOnBothSidesInToFlowsOrder() {
        let f1 = FlowNode(id: "f1", title: "Checkout")
        let f2 = FlowNode(id: "f2", title: "Search")
        let f3 = FlowNode(id: "f3", title: "Signup")
        let shared = ArchitectureInspector.sharedFlows([f2, f1], [f3, f1, f2])
        #expect(shared.map(\.id) == ["f1", "f2"])
    }

    @Test func sharedFlowsIsEmptyWithNoOverlap() {
        let f1 = FlowNode(id: "f1", title: "Checkout")
        let f2 = FlowNode(id: "f2", title: "Search")
        #expect(ArchitectureInspector.sharedFlows([f1], [f2]).isEmpty)
    }

    @Test func implementationCountLabelIsNilWhenThereIsNothingToCount() {
        #expect(ArchitectureInspector.implementationCountLabel(nodeCount: 0, nameCount: 0) == nil)
    }

    @Test func implementationCountLabelIsSingularForExactlyOne() {
        #expect(
            ArchitectureInspector.implementationCountLabel(nodeCount: 1, nameCount: 0) == "1 implementation component")
        #expect(
            ArchitectureInspector.implementationCountLabel(nodeCount: 0, nameCount: 1) == "1 implementation component")
    }

    @Test func implementationCountLabelIsPluralForMoreThanOneAndSumsBothCounts() {
        #expect(
            ArchitectureInspector.implementationCountLabel(nodeCount: 2, nameCount: 1) == "3 implementation components")
    }

    @Test func mergedRefsDeduplicatesPartAndImplementationRefsInOrder() {
        let a = CodeRef(path: "a.swift", startLine: 1, endLine: 1)
        let b = CodeRef(path: "b.swift", startLine: 2, endLine: 2)
        #expect(ArchitectureInspector.mergedRefs(partRefs: [a, b], implRefs: [b, a]) == [a, b])
    }

    @Test func mergedRefsIsEmptyWhenBothSidesAreEmpty() {
        #expect(ArchitectureInspector.mergedRefs(partRefs: [], implRefs: []).isEmpty)
    }
}
