import Testing
import SwiftUI
@testable import Contour

/// `ProvenanceBadge`/`StatementView` render `Provenance`/`Confidence` — the app's central
/// "never present an inference as a fact" invariant (§15) — so every case's label, glyph,
/// and color is pinned directly, per CLAUDE.md's guidance for this file.
struct BadgesTests {

    // MARK: - Provenance

    @Test func everyProvenanceHasItsOwnLabelAndGlyph() {
        #expect(Provenance.fact.label == "Fact")
        #expect(Provenance.claim.label == "Author")
        #expect(Provenance.interpretation.label == "AI")

        #expect(Provenance.fact.glyph == "checkmark.circle")
        #expect(Provenance.claim.glyph == "quote.bubble")
        #expect(Provenance.interpretation.glyph == "sparkles")
    }

    @Test func everyProvenanceHasItsOwnColor() {
        #expect(Provenance.fact.color == .secondary)
        #expect(Provenance.claim.color == .green)
        #expect(Provenance.interpretation.color == .purple)
    }

    // MARK: - Confidence

    @Test func confidenceLabelIsItsCapitalizedRawValue() {
        #expect(Confidence.low.label == "Low")
        #expect(Confidence.medium.label == "Medium")
        #expect(Confidence.high.label == "High")
    }

    @Test func confidenceColorRunsFromWarmestAtLowToGreenAtHigh() {
        #expect(Confidence.low.color == .orange)
        #expect(Confidence.medium.color == .yellow)
        #expect(Confidence.high.color == .green)
    }

    // MARK: - ChangeKind

    @Test func everyChangeKindHasItsOwnLabel() {
        #expect(ChangeKind.new.label == "New")
        #expect(ChangeKind.changed.label == "Changed")
        #expect(ChangeKind.touched.label == "Touched")
        #expect(ChangeKind.unchanged.label == "Context")
        #expect(ChangeKind.removed.label == "Removed")
    }

    @Test func everyChangeKindHasItsOwnColor() {
        #expect(ChangeKind.new.color == .green)
        #expect(ChangeKind.changed.color == .blue)
        #expect(ChangeKind.touched.color == .gray)
        #expect(ChangeKind.unchanged.color == .secondary)
        #expect(ChangeKind.removed.color == .red)
    }

    // MARK: - ProvenanceMark.helpText

    @MainActor
    @Test func helpTextNamesAFactPlainly() {
        #expect(ProvenanceMark.helpText(provenance: .fact, confidence: nil, source: nil) == "Observed fact")
    }

    @MainActor
    @Test func helpTextNamesAClaimAsTheAuthors() {
        #expect(ProvenanceMark.helpText(provenance: .claim, confidence: nil, source: nil) == "The author's claim")
    }

    /// An interpretation without a confidence (a decision brief's narrative prose, say)
    /// still reads as an inference, just without a confidence qualifier.
    @MainActor
    @Test func helpTextNamesAnInterpretationAsAnInferenceEvenWithoutConfidence() {
        #expect(ProvenanceMark.helpText(provenance: .interpretation, confidence: nil, source: nil) == "AI inference")
    }

    @MainActor
    @Test func helpTextAppendsTheConfidenceLevelLowercasedForAnInterpretation() {
        #expect(ProvenanceMark.helpText(provenance: .interpretation, confidence: .high, source: nil)
                == "AI inference · high confidence")
    }

    @MainActor
    @Test func helpTextAppendsANonEmptySourceButNotAnEmptyOne() {
        #expect(ProvenanceMark.helpText(provenance: .fact, confidence: nil, source: "PagePublisher.java:50")
                == "Observed fact — PagePublisher.java:50")
        #expect(ProvenanceMark.helpText(provenance: .fact, confidence: nil, source: "") == "Observed fact")
    }

    // MARK: - FlowLayout.wrap
    //
    // `sizeThatFits`/`placeSubviews` themselves need real SwiftUI `Subviews`, which this
    // suite has no infrastructure to construct (no ViewInspector or similar dependency),
    // so the row-breaking math they share is pulled out to a static function taking plain
    // `CGSize`s, mirroring the `BehaviorDiagramLayoutEngine` pattern for layout math.

    /// Chips that fit within `maxWidth` stay on one row, left to right with `spacing`
    /// between them, and the reported height is just the tallest chip's.
    @Test func wrapKeepsChipsOnOneRowWhenTheyFit() {
        let sizes = [CGSize(width: 40, height: 10), CGSize(width: 50, height: 20)]
        let result = FlowLayout.wrap(sizes: sizes, spacing: 6, maxWidth: 200)
        #expect(result.origins == [CGPoint(x: 0, y: 0), CGPoint(x: 46, y: 0)])
        #expect(result.size == CGSize(width: 200, height: 20))
    }

    /// A chip that would overflow `maxWidth` starts a new row, dropped below the previous
    /// row's tallest chip plus `spacing` — the "wraps instead of forcing horizontal
    /// scroll" behavior `WrapChips`'s doc comment promises.
    @Test func wrapBreaksToANewRowWhenAChipWouldOverflow() {
        let sizes = [CGSize(width: 80, height: 10), CGSize(width: 80, height: 30), CGSize(width: 10, height: 5)]
        let result = FlowLayout.wrap(sizes: sizes, spacing: 6, maxWidth: 100)
        #expect(result.origins == [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 16), CGPoint(x: 86, y: 16)])
        #expect(result.size == CGSize(width: 100, height: 46))
    }

    /// A single chip wider than `maxWidth` still gets placed on its own row rather than
    /// wrapping forever: the overflow check only fires once a row already has something.
    @Test func wrapDoesNotLoopOnAChipWiderThanMaxWidth() {
        let result = FlowLayout.wrap(sizes: [CGSize(width: 500, height: 12)], spacing: 6, maxWidth: 100)
        #expect(result.origins == [CGPoint(x: 0, y: 0)])
        #expect(result.size == CGSize(width: 100, height: 12))
    }

    /// No chips lays out to empty origins rather than crashing on an empty loop —
    /// `WrapChips` is called with `refs: []` when a statement has no code references.
    /// With no width proposed the reported size is exactly zero; with a finite width it's
    /// that width at zero height, since a `Layout` still reports the width it was offered.
    @Test func wrapOfNoChipsHasEmptyOrigins() {
        let unconstrained = FlowLayout.wrap(sizes: [], spacing: 6, maxWidth: .infinity)
        #expect(unconstrained.origins.isEmpty)
        #expect(unconstrained.size == .zero)

        let constrained = FlowLayout.wrap(sizes: [], spacing: 6, maxWidth: 100)
        #expect(constrained.origins.isEmpty)
        #expect(constrained.size == CGSize(width: 100, height: 0))
    }

    /// With no width proposed (`maxWidth` infinite, as `sizeThatFits` passes when the
    /// proposal has no width) chips never wrap, and the reported width is exactly how far
    /// they reach rather than `.infinity`.
    @Test func wrapWithInfiniteMaxWidthNeverBreaksAndReportsActualWidth() {
        let sizes = [CGSize(width: 40, height: 10), CGSize(width: 50, height: 20), CGSize(width: 30, height: 5)]
        let result = FlowLayout.wrap(sizes: sizes, spacing: 6, maxWidth: .infinity)
        #expect(result.origins == [CGPoint(x: 0, y: 0), CGPoint(x: 46, y: 0), CGPoint(x: 102, y: 0)])
        #expect(result.size == CGSize(width: 138, height: 20))
    }
}
