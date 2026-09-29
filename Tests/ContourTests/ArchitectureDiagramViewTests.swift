import Foundation
import SwiftUI
import Testing

@testable import Contour

struct ArchitectureDiagramViewTests {
    @Test func everyEmphasisHasItsOwnColorAndWord() {
        #expect(ArchEmphasis.context.color == .secondary && ArchEmphasis.context.word == "Context")
        #expect(ArchEmphasis.changed.color == .blue && ArchEmphasis.changed.word == "Changed")
        #expect(ArchEmphasis.added.color == .green && ArchEmphasis.added.word == "New")
        #expect(ArchEmphasis.removed.color == .red && ArchEmphasis.removed.word == "Removed")
    }

    private func box(emphasis: ArchEmphasis = .context, before: String? = nil, after: String? = nil) -> ArchBox {
        ArchBox(id: "b", title: "Box", emphasis: emphasis, changeBefore: before, changeAfter: after)
    }

    @Test func showsChangeIsTrueWhenEitherSideOfTheChangeIsSet() {
        #expect(box(before: "old").showsChange)
        #expect(box(after: "new").showsChange)
        #expect(box(before: "old", after: "new").showsChange)
    }

    @Test func showsChangeIsTrueForAnyNonContextEmphasisEvenWithNoPhrase() {
        #expect(box(emphasis: .added).showsChange)
        #expect(box(emphasis: .changed).showsChange)
        #expect(box(emphasis: .removed).showsChange)
    }

    @Test func showsChangeIsFalseForAQuietUnchangedBox() {
        #expect(!box().showsChange)
    }

    @Test func boxSizeUsesTheNeighborWidthOnlyWhenMarkedAsANeighbor() {
        var plain = box()
        plain.isNeighbor = false
        var neighbor = box()
        neighbor.isNeighbor = true
        #expect(ArchMetrics.size(of: plain).width == ArchMetrics.boxWidth)
        #expect(ArchMetrics.size(of: neighbor).width == ArchMetrics.neighborWidth)
    }

    @Test func boxSizeGrowsAsContentIsAdded() {
        let bare = ArchMetrics.size(of: box())

        var withPurpose = box()
        withPurpose.purpose = "Handles the thing"
        #expect(ArchMetrics.size(of: withPurpose).height > bare.height)

        var withChange = box(before: "old", after: "new")
        #expect(ArchMetrics.size(of: withChange).height > bare.height)

        var withDecision = box()
        withDecision.decision = "Why it works this way"
        #expect(ArchMetrics.size(of: withDecision).height > bare.height)

        var withQuestion = box()
        withQuestion.questions = 1
        #expect(ArchMetrics.size(of: withQuestion).height > bare.height)
    }

    @Test func neighborBoxSizeIgnoresEverythingButTheTitle() {
        var neighbor = box(before: "old", after: "new")
        neighbor.isNeighbor = true
        neighbor.purpose = "ignored"
        neighbor.decision = "ignored"
        neighbor.questions = 3
        let plainNeighbor = box()
        var plainNeighborNeighbor = plainNeighbor
        plainNeighborNeighbor.isNeighbor = true
        #expect(ArchMetrics.size(of: neighbor).height == ArchMetrics.size(of: plainNeighborNeighbor).height)
    }

    private func arrow(label: String = "calls", questions: Int = 0, decisions: Int = 0, isAsync: Bool = false)
        -> ArchArrow
    {
        ArchArrow(
            id: "a", fromId: "x", toId: "y", label: label, emphasis: .context, isAsync: isAsync, questions: questions,
            decisions: decisions)
    }

    @Test func arrowSizeGrowsWithGlyphsAndALongerLabel() {
        let bare = ArchMetrics.size(of: arrow())
        #expect(ArchMetrics.size(of: arrow(questions: 1)).width > bare.width)
        #expect(ArchMetrics.size(of: arrow(decisions: 1)).width > bare.width)
        #expect(ArchMetrics.size(of: arrow(isAsync: true)).width > bare.width)
        #expect(ArchMetrics.size(of: arrow(label: "a much, much longer label than the short one")).width >= bare.width)
    }

    @Test func arrowSizeGrowsToFitAPreviousLabel() {
        let bare = ArchMetrics.size(of: arrow())
        var withPrevious = arrow()
        withPrevious.previousLabel = "used to call"
        #expect(ArchMetrics.size(of: withPrevious).height > bare.height)
    }

    @Test func measureWidthGrowsWithLongerText() {
        #expect(ArchMetrics.measureWidth("hi", size: 12) < ArchMetrics.measureWidth("hello there, friend", size: 12))
    }

    @Test func measureWidthOfEmptyTextIsZero() {
        #expect(ArchMetrics.measureWidth("", size: 12) == 0)
    }

    @Test func measureClampsToTheRequestedLineCount() {
        let oneLine = ArchMetrics.measure("word", size: 12, width: 200, lines: 1)
        let unclamped = ArchMetrics.measure(
            "a rather long sentence that will wrap across several lines of text", size: 12, width: 40, lines: 100)
        #expect(unclamped > oneLine, "wrapped text spanning many lines measures taller than one short line")

        let clamped = ArchMetrics.measure(
            "a rather long sentence that will wrap across several lines of text", size: 12, width: 40, lines: 1)
        #expect(
            clamped <= oneLine + 1,
            "clamped to 1 line, it can't measure taller than any other 1-line text at the same size")
    }

    @Test func roundedPathEndsExactlyAtTheLastPoint() {
        let straight = ArchitectureDiagramView.roundedPath([CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0)])
        #expect(straight.currentPoint == CGPoint(x: 10, y: 0))

        let corner = ArchitectureDiagramView.roundedPath([
            CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 10),
        ])
        #expect(corner.currentPoint == CGPoint(x: 10, y: 10))
    }

    @Test func roundedPathOfASinglePointIsJustAMove() {
        let path = ArchitectureDiagramView.roundedPath([CGPoint(x: 3, y: 4)])
        #expect(path.currentPoint == CGPoint(x: 3, y: 4))
    }

    private func container(kind: BoundaryKind, isFocus: Bool = false) -> ArchContainer {
        ArchContainer(id: "c", label: "Container", kind: kind, memberIds: [], isFocus: isFocus)
    }

    @Test func onlyExternalTrustAndNetworkBoundariesAreDrawnDashed() {
        #expect(container(kind: .external).isExternalBoundary)
        #expect(container(kind: .trust).isExternalBoundary)
        #expect(container(kind: .network).isExternalBoundary)
        #expect(!container(kind: .process).isExternalBoundary)
        #expect(!container(kind: .application).isExternalBoundary)
    }

    @Test func trustBoundaryTintIsAlwaysOrange() {
        #expect(container(kind: .trust, isFocus: false).tint == .orange)
        #expect(container(kind: .trust, isFocus: true).tint == .orange)
    }

    @Test func nonTrustBoundaryTintFollowsFocus() {
        #expect(container(kind: .process, isFocus: true).tint == .accentColor)
        #expect(container(kind: .process, isFocus: false).tint == .secondary)
    }

    @Test func strokeStyleWidensAndColorsByEmphasis() {
        #expect(ArchDrawingLogic.strokeStyle(for: .context).color == Color.secondary.opacity(0.55))
        #expect(ArchDrawingLogic.strokeStyle(for: .context).width == 1.4)
        #expect(ArchDrawingLogic.strokeStyle(for: .changed).color == .blue)
        #expect(ArchDrawingLogic.strokeStyle(for: .changed).width == 2.4)
        #expect(ArchDrawingLogic.strokeStyle(for: .added).color == .green)
        #expect(ArchDrawingLogic.strokeStyle(for: .added).width == 2.6)
        #expect(ArchDrawingLogic.strokeStyle(for: .removed).color == Color.red.opacity(0.8))
        #expect(ArchDrawingLogic.strokeStyle(for: .removed).width == 1.8)
        let widths = [ArchEmphasis.changed, .added, .removed].map { ArchDrawingLogic.strokeStyle(for: $0).width }
        #expect(widths.allSatisfy { $0 > ArchDrawingLogic.strokeStyle(for: .context).width })
    }

    @Test func removedDashPatternWinsOverAsync() {
        #expect(ArchDrawingLogic.dashPattern(for: arrow(isAsync: false)) == [])
        var asyncArrow = arrow(isAsync: true)
        #expect(ArchDrawingLogic.dashPattern(for: asyncArrow) == [7, 5])
        asyncArrow.emphasis = .removed
        #expect(ArchDrawingLogic.dashPattern(for: asyncArrow) == [4, 4])
        var removedOnly = arrow(isAsync: false)
        removedOnly.emphasis = .removed
        #expect(ArchDrawingLogic.dashPattern(for: removedOnly) == [4, 4])
    }

    @Test func arrowheadTriangleIsSymmetricAroundTheLine() {
        let triangle = ArchDrawingLogic.arrowheadTriangle(
            tip: CGPoint(x: 100, y: 0), from: CGPoint(x: 0, y: 0), size: 10)
        #expect(triangle.tip == CGPoint(x: 100, y: 0))
        #expect(abs(triangle.left.x - triangle.right.x) < 0.0001)
        #expect(triangle.left.y == -triangle.right.y)
        let leftDistance = hypot(triangle.left.x - triangle.tip.x, triangle.left.y - triangle.tip.y)
        let rightDistance = hypot(triangle.right.x - triangle.tip.x, triangle.right.y - triangle.tip.y)
        #expect(abs(leftDistance - rightDistance) < 0.0001)
    }

    @Test func arrowheadTriangleGrowsWithSize() {
        let small = ArchDrawingLogic.arrowheadTriangle(tip: CGPoint(x: 50, y: 50), from: CGPoint(x: 0, y: 50), size: 4)
        let big = ArchDrawingLogic.arrowheadTriangle(tip: CGPoint(x: 50, y: 50), from: CGPoint(x: 0, y: 50), size: 20)
        func distanceFromTip(_ p: CGPoint, _ tip: CGPoint) -> CGFloat { hypot(p.x - tip.x, p.y - tip.y) }
        #expect(distanceFromTip(big.left, big.tip) > distanceFromTip(small.left, small.tip))
    }

    @Test func hoverUpdateEnteringAlwaysSetsTheAnchor() {
        #expect(ArchDrawingLogic.hoverUpdate(current: nil, anchor: .node("a"), isHovering: true) == .node("a"))
        #expect(ArchDrawingLogic.hoverUpdate(current: .node("b"), anchor: .node("a"), isHovering: true) == .node("a"))
    }

    @Test func hoverUpdateLeavingClearsOnlyIfStillTheHoveredAnchor() {
        #expect(ArchDrawingLogic.hoverUpdate(current: .node("a"), anchor: .node("a"), isHovering: false) == nil)
    }

    @Test func hoverUpdateLeavingLeavesADifferentHoverAlone() {
        #expect(ArchDrawingLogic.hoverUpdate(current: .node("b"), anchor: .node("a"), isHovering: false) == .node("b"))
        #expect(ArchDrawingLogic.hoverUpdate(current: nil, anchor: .node("a"), isHovering: false) == nil)
    }

    @Test func bestFitKeepsAcrossWhenItAlreadyFits() {
        let nodes = [GraphLayoutEngine.NodeSpec(id: "a", size: CGSize(width: 100, height: 60))]
        let (layout, fit) = GraphLayoutEngine.bestFit(
            nodes: nodes, edges: [], groups: [], available: CGSize(width: 5000, height: 5000))
        let across = GraphLayoutEngine.layout(nodes: nodes, edges: [], groups: [], vertical: false)
        #expect(fit == 1)
        #expect(layout.size.width == across.size.width && layout.size.height == across.size.height)
    }

    private func chain(count: Int) -> (nodes: [GraphLayoutEngine.NodeSpec], edges: [GraphLayoutEngine.EdgeSpec]) {
        let nodes = (0..<count).map { GraphLayoutEngine.NodeSpec(id: "n\($0)", size: CGSize(width: 224, height: 50)) }
        let edges = (0..<count - 1).map {
            GraphLayoutEngine.EdgeSpec(
                id: "e\($0)", fromId: "n\($0)", toId: "n\($0 + 1)", labelSize: CGSize(width: 20, height: 10))
        }
        return (nodes, edges)
    }

    @Test func bestFitSwitchesToDownWhenItFitsSubstantiallyBetter() {
        let (nodes, edges) = chain(count: 4)
        let down = GraphLayoutEngine.layout(nodes: nodes, edges: edges, groups: [], vertical: true)
        let (layout, fit) = GraphLayoutEngine.bestFit(nodes: nodes, edges: edges, groups: [], available: down.size)
        #expect(fit == 1)
        #expect(layout.size.width == down.size.width && layout.size.height == down.size.height)
    }

    @Test func bestFitKeepsAcrossWhenDownIsNotSubstantiallyBetter() {
        let (nodes, edges) = chain(count: 4)
        let across = GraphLayoutEngine.layout(nodes: nodes, edges: edges, groups: [], vertical: false)
        let available = CGSize(width: across.size.width * 0.5, height: across.size.height * 0.5)
        let (layout, fit) = GraphLayoutEngine.bestFit(nodes: nodes, edges: edges, groups: [], available: available)
        #expect(fit == 0.5)
        #expect(layout.size.width == across.size.width && layout.size.height == across.size.height)
    }
}
