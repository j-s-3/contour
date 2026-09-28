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
}
