import SwiftUI
import Testing
@testable import Contour

/// `ArchitectureDiagramView.swift` was at 0.00% coverage. Per CLAUDE.md's guidance for this
/// file (mirroring `GraphLayout`'s pattern), the pure pieces beside the view — `ArchEmphasis`,
/// `ArchBox.showsChange`, `ArchMetrics`'s text-measurement math, and `roundedPath`'s geometry
/// — are all already internal, not private, so they're directly testable with no production
/// changes needed. The view's `body`, `canvas`, `boxView`/`labelView`/`containerView`, and
/// `draw(_:_:in:)` render real SwiftUI/AppKit content and stay untested here.
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
}
