import SwiftUI
import Testing

@testable import Contour

struct BadgesTests {
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

    @MainActor
    @Test func helpTextNamesAFactPlainly() {
        #expect(ProvenanceMark.helpText(provenance: .fact, confidence: nil, source: nil) == "Observed fact")
    }

    @MainActor
    @Test func helpTextNamesAClaimAsTheAuthors() {
        #expect(ProvenanceMark.helpText(provenance: .claim, confidence: nil, source: nil) == "The author's claim")
    }

    @MainActor
    @Test func helpTextNamesAnInterpretationAsAnInferenceEvenWithoutConfidence() {
        #expect(ProvenanceMark.helpText(provenance: .interpretation, confidence: nil, source: nil) == "AI inference")
    }

    @MainActor
    @Test func helpTextAppendsTheConfidenceLevelLowercasedForAnInterpretation() {
        #expect(
            ProvenanceMark.helpText(provenance: .interpretation, confidence: .high, source: nil)
                == "AI inference · high confidence")
    }

    @MainActor
    @Test func helpTextAppendsANonEmptySourceButNotAnEmptyOne() {
        #expect(
            ProvenanceMark.helpText(provenance: .fact, confidence: nil, source: "PagePublisher.java:50")
                == "Observed fact — PagePublisher.java:50")
        #expect(ProvenanceMark.helpText(provenance: .fact, confidence: nil, source: "") == "Observed fact")
    }

    @Test func wrapKeepsChipsOnOneRowWhenTheyFit() {
        let sizes = [CGSize(width: 40, height: 10), CGSize(width: 50, height: 20)]
        let result = FlowLayout.wrap(sizes: sizes, spacing: 6, maxWidth: 200)
        #expect(result.origins == [CGPoint(x: 0, y: 0), CGPoint(x: 46, y: 0)])
        #expect(result.size == CGSize(width: 200, height: 20))
    }

    @Test func wrapBreaksToANewRowWhenAChipWouldOverflow() {
        let sizes = [CGSize(width: 80, height: 10), CGSize(width: 80, height: 30), CGSize(width: 10, height: 5)]
        let result = FlowLayout.wrap(sizes: sizes, spacing: 6, maxWidth: 100)
        #expect(result.origins == [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 16), CGPoint(x: 86, y: 16)])
        #expect(result.size == CGSize(width: 100, height: 46))
    }

    @Test func wrapDoesNotLoopOnAChipWiderThanMaxWidth() {
        let result = FlowLayout.wrap(sizes: [CGSize(width: 500, height: 12)], spacing: 6, maxWidth: 100)
        #expect(result.origins == [CGPoint(x: 0, y: 0)])
        #expect(result.size == CGSize(width: 100, height: 12))
    }

    @Test func wrapOfNoChipsHasEmptyOrigins() {
        let unconstrained = FlowLayout.wrap(sizes: [], spacing: 6, maxWidth: .infinity)
        #expect(unconstrained.origins.isEmpty)
        #expect(unconstrained.size == .zero)

        let constrained = FlowLayout.wrap(sizes: [], spacing: 6, maxWidth: 100)
        #expect(constrained.origins.isEmpty)
        #expect(constrained.size == CGSize(width: 100, height: 0))
    }

    @Test func wrapWithInfiniteMaxWidthNeverBreaksAndReportsActualWidth() {
        let sizes = [CGSize(width: 40, height: 10), CGSize(width: 50, height: 20), CGSize(width: 30, height: 5)]
        let result = FlowLayout.wrap(sizes: sizes, spacing: 6, maxWidth: .infinity)
        #expect(result.origins == [CGPoint(x: 0, y: 0), CGPoint(x: 46, y: 0), CGPoint(x: 102, y: 0)])
        #expect(result.size == CGSize(width: 138, height: 20))
    }
}
