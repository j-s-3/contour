import Testing
import SwiftUI
@testable import Contour

/// `BehaviorDiagramLayout` is already the pure-type pattern CLAUDE.md points to for this
/// file (covered by its own tests); this pins the remaining Before/After/Delta styling
/// rules, pulled out of `BehaviorDiagramView`/`StageBox` into `BehaviorDiagramLogic`, plus
/// the already-plain `FlowChange`/`FlowAnnotation.Kind` extensions and `glyph(_:)` — none
/// of which needed a production change beyond the extraction itself.
struct BehaviorDiagramViewTests {

    // MARK: - FlowChange

    @Test func everyFlowChangeHasItsOwnColor() {
        #expect(FlowChange.new.color == .green)
        #expect(FlowChange.changed.color == .blue)
        #expect(FlowChange.existing.color == .secondary)
        #expect(FlowChange.removed.color == .red)
    }

    @Test func onlyAnActualChangeHasATag() {
        #expect(FlowChange.new.tag == "NEW")
        #expect(FlowChange.changed.tag == "CHANGED")
        #expect(FlowChange.removed.tag == "REMOVED")
        #expect(FlowChange.existing.tag == nil)
    }

    // MARK: - FlowAnnotation.Kind

    @Test func decisionAndQuestionAnnotationsHaveDistinctStyling() {
        #expect(FlowAnnotation.Kind.decision.color == .teal)
        #expect(FlowAnnotation.Kind.question.color == .orange)
        #expect(FlowAnnotation.Kind.decision.symbol == "diamond")
        #expect(FlowAnnotation.Kind.question.symbol == "exclamationmark.triangle.fill")
        #expect(FlowAnnotation.Kind.decision.caption == "DECISION")
        #expect(FlowAnnotation.Kind.question.caption == "REVIEW QUESTION")
    }

    // MARK: - BehaviorDiagramView.glyph

    @Test func everyBoundaryKindHasItsOwnGlyph() {
        #expect(BehaviorDiagramView.glyph(.application) == "square.dashed")
        #expect(BehaviorDiagramView.glyph(.process) == "cpu")
        #expect(BehaviorDiagramView.glyph(.service) == "server.rack")
        #expect(BehaviorDiagramView.glyph(.datastore) == "cylinder.split.1x2")
        #expect(BehaviorDiagramView.glyph(.external) == "globe")
        #expect(BehaviorDiagramView.glyph(.trust) == "lock.shield")
        #expect(BehaviorDiagramView.glyph(.network) == "network")
        #expect(BehaviorDiagramView.glyph(.asyncBoundary) == "clock.arrow.circlepath")
    }

    // MARK: - BehaviorDiagramLogic

    @Test func fadesOnlyAnUnchangedElementInDeltaMode() {
        #expect(BehaviorDiagramLogic.fades(mode: .delta, change: .existing))
        #expect(!BehaviorDiagramLogic.fades(mode: .delta, change: .changed))
        #expect(!BehaviorDiagramLogic.fades(mode: .before, change: .existing))
        #expect(!BehaviorDiagramLogic.fades(mode: .after, change: .existing))
    }

    @Test func emphasizesOnlyAChangedElementInDeltaMode() {
        #expect(BehaviorDiagramLogic.emphasized(mode: .delta, change: .new))
        #expect(BehaviorDiagramLogic.emphasized(mode: .delta, change: .changed))
        #expect(BehaviorDiagramLogic.emphasized(mode: .delta, change: .removed))
        #expect(!BehaviorDiagramLogic.emphasized(mode: .delta, change: .existing))
        #expect(!BehaviorDiagramLogic.emphasized(mode: .before, change: .new))
    }

    @Test func tintIsTheChangesColorOnlyInDeltaForAnActualChange() {
        #expect(BehaviorDiagramLogic.tint(mode: .delta, change: .new) == .green)
        #expect(BehaviorDiagramLogic.tint(mode: .delta, change: .existing) == nil)
        #expect(BehaviorDiagramLogic.tint(mode: .before, change: .new) == nil)
        #expect(BehaviorDiagramLogic.tint(mode: .after, change: .removed) == nil)
    }

    @Test func dashMarksARemovedElementInDeltaOrAnExternalCallAlways() {
        #expect(BehaviorDiagramLogic.dash(mode: .delta, change: .removed, kind: .step) == [4, 3])
        #expect(BehaviorDiagramLogic.dash(mode: .before, change: .existing, kind: .external) == [5, 3])
        #expect(BehaviorDiagramLogic.dash(mode: .delta, change: .existing, kind: .step).isEmpty)
    }

    /// A removed external call is drawn removed (dash pattern takes priority over the
    /// always-dashed external style, though both happen to dash the connection).
    @Test func dashPrefersTheRemovedPatternOverTheExternalPatternWhenBothApply() {
        #expect(BehaviorDiagramLogic.dash(mode: .delta, change: .removed, kind: .external) == [4, 3])
    }
}
