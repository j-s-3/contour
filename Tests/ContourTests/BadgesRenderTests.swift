import AppKit
import SwiftUI
import Testing

@testable import Contour

@MainActor
struct BadgesRenderTests {
    private func render<V: View>(_ view: V, width: CGFloat = 400) -> CGSize {
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(x: 0, y: 0, width: width, height: 300)
        host.layoutSubtreeIfNeeded()
        return host.fittingSize
    }

    @Test func provenanceBadgeShowsConfidenceOnlyForInterpretations() {
        let plain = render(ProvenanceBadge(provenance: .fact, confidence: .high))
        let ignoredConfidence = render(ProvenanceBadge(provenance: .fact, confidence: nil))
        #expect(plain == ignoredConfidence)

        let bare = render(ProvenanceBadge(provenance: .interpretation, confidence: nil))
        for confidence in [Confidence.low, .medium, .high] {
            let withConfidence = render(ProvenanceBadge(provenance: .interpretation, confidence: confidence))
            #expect(withConfidence.width > bare.width)
        }
    }

    @Test func provenanceMarkRendersForEveryProvenanceWithAndWithoutSource() {
        for provenance in [Provenance.fact, .claim, .interpretation] {
            let size = render(ProvenanceMark(provenance: provenance, confidence: .medium))
            #expect(size.width > 0 && size.height > 0)
            _ = render(ProvenanceMark(provenance: provenance, confidence: nil, source: "Foo.swift:1"))
        }
    }

    @Test func statementViewShowsItsSourceOnlyWhenNonEmpty() {
        let withSource = render(
            StatementView(statement: Statement(text: "Adds a cache", provenance: .claim, source: "PR description")))
        let emptySource = render(
            StatementView(statement: Statement(text: "Adds a cache", provenance: .claim, source: "")))
        let noSource = render(StatementView(statement: Statement(text: "Adds a cache", provenance: .claim)))
        #expect(withSource.height > noSource.height)
        #expect(emptySource == noSource)
        _ = render(
            StatementView(statement: Statement(text: "Guess", provenance: .interpretation, confidence: .low)))
    }

    @Test func changeKindBadgeRendersForEveryKind() {
        for kind in [ChangeKind.new, .changed, .touched, .unchanged, .removed] {
            let size = render(ChangeKindBadge(kind: kind))
            #expect(size.width > 0 && size.height > 0)
        }
    }

    @Test func codeRefChipAndWrapChipsRenderEveryRef() {
        let refs = (1...6).map { CodeRef(path: "Sources/File\($0).swift", startLine: $0, endLine: $0 + 3) }
        let chip = render(CodeRefChip(ref: refs[0], action: {}))
        #expect(chip.width > 0 && chip.height > 0)

        let wide = render(WrapChips(refs) { CodeRefChip(ref: $0, action: {}) }.frame(width: 2000))
        let narrow = render(WrapChips(refs) { CodeRefChip(ref: $0, action: {}) }.frame(width: 200))
        #expect(narrow.height > wide.height)
    }
}
