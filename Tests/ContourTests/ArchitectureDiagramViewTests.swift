import Foundation
import SwiftUI
import Testing
@testable import Contour

/// `ArchitectureDiagramView.swift` was at 0.00% coverage. Per CLAUDE.md's guidance for this
/// file (mirroring `GraphLayout`'s pattern), the pure pieces beside the view — `ArchEmphasis`,
/// `ArchBox.showsChange`, `ArchMetrics`'s text-measurement math, and `roundedPath`'s geometry
/// — are all already internal, not private, so they're directly testable with no production
/// changes needed. The view's `body`, `canvas`, `boxView`/`labelView`/`containerView`, and
/// `draw(_:_:in:)` render real SwiftUI/AppKit content and stay untested here.
///
/// A second pass (issue #103, reopened at 14.35%) found more inline logic still worth
/// extracting on the same pattern: which orientation the diagram lays out in moved to
/// `GraphLayoutEngine.bestFit` beside the rest of the layout math, and the arrow's stroke
/// style, dash pattern, arrowhead geometry and hover-state transition moved to the new
/// `ArchDrawingLogic`, alongside `ArchContainer.isExternalBoundary`/`tint`. Those additions
/// are covered below; the render-only surface they were extracted from stays untested.
struct ArchitectureDiagramViewTests {

    // MARK: - ArchEmphasis

    @Test func everyEmphasisHasItsOwnColorAndWord() {
        #expect(ArchEmphasis.context.color == .secondary && ArchEmphasis.context.word == "Context")
        #expect(ArchEmphasis.changed.color == .blue && ArchEmphasis.changed.word == "Changed")
        #expect(ArchEmphasis.added.color == .green && ArchEmphasis.added.word == "New")
        #expect(ArchEmphasis.removed.color == .red && ArchEmphasis.removed.word == "Removed")
    }

    // MARK: - ArchBox.showsChange

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

    // MARK: - ArchMetrics.size(of: ArchBox)

    @Test func boxSizeUsesTheNeighborWidthOnlyWhenMarkedAsANeighbor() {
        var plain = box()
        plain.isNeighbor = false
        var neighbor = box()
        neighbor.isNeighbor = true
        #expect(ArchMetrics.size(of: plain).width == ArchMetrics.boxWidth)
        #expect(ArchMetrics.size(of: neighbor).width == ArchMetrics.neighborWidth)
    }

    /// More content — a purpose line, a change phrase, a decision, a question — can only
    /// grow a box, never shrink it, since each section adds its own height on top.
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

    /// A neighbor box is drawn small and quiet: none of the extra sections apply, so its
    /// size doesn't grow no matter what the box otherwise carries.
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

    // MARK: - ArchMetrics.size(of: ArchArrow)

    private func arrow(label: String = "calls", questions: Int = 0, decisions: Int = 0, isAsync: Bool = false) -> ArchArrow {
        ArchArrow(id: "a", fromId: "x", toId: "y", label: label, emphasis: .context, isAsync: isAsync, questions: questions, decisions: decisions)
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

    // MARK: - ArchMetrics.measure / measureWidth

    @Test func measureWidthGrowsWithLongerText() {
        #expect(ArchMetrics.measureWidth("hi", size: 12) < ArchMetrics.measureWidth("hello there, friend", size: 12))
    }

    @Test func measureWidthOfEmptyTextIsZero() {
        #expect(ArchMetrics.measureWidth("", size: 12) == 0)
    }

    @Test func measureClampsToTheRequestedLineCount() {
        let oneLine = ArchMetrics.measure("word", size: 12, width: 200, lines: 1)
        let unclamped = ArchMetrics.measure("a rather long sentence that will wrap across several lines of text", size: 12, width: 40, lines: 100)
        #expect(unclamped > oneLine, "wrapped text spanning many lines measures taller than one short line")

        let clamped = ArchMetrics.measure("a rather long sentence that will wrap across several lines of text", size: 12, width: 40, lines: 1)
        #expect(clamped <= oneLine + 1, "clamped to 1 line, it can't measure taller than any other 1-line text at the same size")
    }

    // MARK: - ArchitectureDiagramView.roundedPath

    @Test func roundedPathEndsExactlyAtTheLastPoint() {
        let straight = ArchitectureDiagramView.roundedPath([CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0)])
        #expect(straight.currentPoint == CGPoint(x: 10, y: 0))

        let corner = ArchitectureDiagramView.roundedPath([CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 10)])
        #expect(corner.currentPoint == CGPoint(x: 10, y: 10))
    }

    @Test func roundedPathOfASinglePointIsJustAMove() {
        let path = ArchitectureDiagramView.roundedPath([CGPoint(x: 3, y: 4)])
        #expect(path.currentPoint == CGPoint(x: 3, y: 4))
    }

    // MARK: - ArchContainer.isExternalBoundary / tint

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

    /// A trust boundary is flagged orange no matter whether it's the one focused on, since
    /// that color means something specific (a security boundary) that focus mustn't mask.
    @Test func trustBoundaryTintIsAlwaysOrange() {
        #expect(container(kind: .trust, isFocus: false).tint == .orange)
        #expect(container(kind: .trust, isFocus: true).tint == .orange)
    }

    @Test func nonTrustBoundaryTintFollowsFocus() {
        #expect(container(kind: .process, isFocus: true).tint == .accentColor)
        #expect(container(kind: .process, isFocus: false).tint == .secondary)
    }

    // MARK: - ArchDrawingLogic.strokeStyle / dashPattern

    @Test func strokeStyleWidensAndColorsByEmphasis() {
        #expect(ArchDrawingLogic.strokeStyle(for: .context).color == Color.secondary.opacity(0.55))
        #expect(ArchDrawingLogic.strokeStyle(for: .context).width == 1.4)
        #expect(ArchDrawingLogic.strokeStyle(for: .changed).color == .blue)
        #expect(ArchDrawingLogic.strokeStyle(for: .changed).width == 2.4)
        #expect(ArchDrawingLogic.strokeStyle(for: .added).color == .green)
        #expect(ArchDrawingLogic.strokeStyle(for: .added).width == 2.6)
        #expect(ArchDrawingLogic.strokeStyle(for: .removed).color == Color.red.opacity(0.8))
        #expect(ArchDrawingLogic.strokeStyle(for: .removed).width == 1.8)
        // Context, the quietest emphasis, is always the thinnest line.
        let widths = [ArchEmphasis.changed, .added, .removed].map { ArchDrawingLogic.strokeStyle(for: $0).width }
        #expect(widths.allSatisfy { $0 > ArchDrawingLogic.strokeStyle(for: .context).width })
    }

    /// A removed relationship keeps reading as removed even when it was also async — the
    /// two dash patterns can't both show, and "this is gone" matters more than "this was async".
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

    // MARK: - ArchDrawingLogic.arrowheadTriangle

    /// The arrowhead is symmetric around the line it caps: both back corners sit the same
    /// distance from the tip, straddling the line's direction evenly.
    @Test func arrowheadTriangleIsSymmetricAroundTheLine() {
        let triangle = ArchDrawingLogic.arrowheadTriangle(tip: CGPoint(x: 100, y: 0), from: CGPoint(x: 0, y: 0), size: 10)
        #expect(triangle.tip == CGPoint(x: 100, y: 0))
        // Pointing along +x, the back corners land symmetric above and below the tip's row.
        #expect(abs(triangle.left.x - triangle.right.x) < 0.0001)
        #expect(triangle.left.y == -triangle.right.y)
        let leftDistance = hypot(triangle.left.x - triangle.tip.x, triangle.left.y - triangle.tip.y)
        let rightDistance = hypot(triangle.right.x - triangle.tip.x, triangle.right.y - triangle.tip.y)
        #expect(abs(leftDistance - rightDistance) < 0.0001)
    }

    /// A bigger `size` makes a bigger arrowhead: both back corners move further from the tip.
    @Test func arrowheadTriangleGrowsWithSize() {
        let small = ArchDrawingLogic.arrowheadTriangle(tip: CGPoint(x: 50, y: 50), from: CGPoint(x: 0, y: 50), size: 4)
        let big = ArchDrawingLogic.arrowheadTriangle(tip: CGPoint(x: 50, y: 50), from: CGPoint(x: 0, y: 50), size: 20)
        func distanceFromTip(_ p: CGPoint, _ tip: CGPoint) -> CGFloat { hypot(p.x - tip.x, p.y - tip.y) }
        #expect(distanceFromTip(big.left, big.tip) > distanceFromTip(small.left, small.tip))
    }

    // MARK: - ArchDrawingLogic.hoverUpdate

    /// Pins the hover-toggle rule: entering always sets the hover, but leaving only clears it
    /// if this anchor is still the one hovered — a fast pointer move onto a sibling box fires
    /// that sibling's "entered" before this box's "left", so this box's "left" must not
    /// clobber the sibling's hover.
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

    // MARK: - GraphLayoutEngine.bestFit

    /// One box far smaller than the available pane already fits left-to-right, so the guard
    /// returns it immediately at full scale without ever computing the vertical alternative.
    @Test func bestFitKeepsAcrossWhenItAlreadyFits() {
        let nodes = [GraphLayoutEngine.NodeSpec(id: "a", size: CGSize(width: 100, height: 60))]
        let (layout, fit) = GraphLayoutEngine.bestFit(nodes: nodes, edges: [], groups: [], available: CGSize(width: 5000, height: 5000))
        let across = GraphLayoutEngine.layout(nodes: nodes, edges: [], groups: [], vertical: false)
        #expect(fit == 1)
        #expect(layout.size.width == across.size.width && layout.size.height == across.size.height)
    }

    private func chain(count: Int) -> (nodes: [GraphLayoutEngine.NodeSpec], edges: [GraphLayoutEngine.EdgeSpec]) {
        let nodes = (0..<count).map { GraphLayoutEngine.NodeSpec(id: "n\($0)", size: CGSize(width: 224, height: 50)) }
        let edges = (0..<count - 1).map {
            GraphLayoutEngine.EdgeSpec(id: "e\($0)", fromId: "n\($0)", toId: "n\($0 + 1)", labelSize: CGSize(width: 20, height: 10))
        }
        return (nodes, edges)
    }

    /// A left-to-right chain of wide, short boxes lays out wide-and-short across, but
    /// narrow-and-tall down (the same boxes, just stacked). Sizing the pane to exactly fit
    /// the vertical layout — which the horizontal one doesn't come close to fitting — forces
    /// the "clearly better vertically" branch, without hardcoding either layout's geometry.
    @Test func bestFitSwitchesToDownWhenItFitsSubstantiallyBetter() {
        let (nodes, edges) = chain(count: 4)
        let down = GraphLayoutEngine.layout(nodes: nodes, edges: edges, groups: [], vertical: true)
        let (layout, fit) = GraphLayoutEngine.bestFit(nodes: nodes, edges: edges, groups: [], available: down.size)
        #expect(fit == 1)
        #expect(layout.size.width == down.size.width && layout.size.height == down.size.height)
    }

    /// Scaling the pane down from the across layout's own bounding box, keeping its aspect
    /// ratio, guarantees `fit(across)` equals that scale exactly — while the down layout, a
    /// very differently-shaped box, fits far worse in a pane shaped like the wide one. That
    /// keeps the across orientation even though it doesn't fill the pane, pinning the "not
    /// enough of an edge to flip to down" half of the tie-break.
    @Test func bestFitKeepsAcrossWhenDownIsNotSubstantiallyBetter() {
        let (nodes, edges) = chain(count: 4)
        let across = GraphLayoutEngine.layout(nodes: nodes, edges: edges, groups: [], vertical: false)
        let available = CGSize(width: across.size.width * 0.5, height: across.size.height * 0.5)
        let (layout, fit) = GraphLayoutEngine.bestFit(nodes: nodes, edges: edges, groups: [], available: available)
        #expect(fit == 0.5)
        #expect(layout.size.width == across.size.width && layout.size.height == across.size.height)
    }
}
