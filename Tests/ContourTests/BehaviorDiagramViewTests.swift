import Foundation
import Testing
import SwiftUI
@testable import Contour

/// `BehaviorDiagramLayout` is already the pure-type pattern CLAUDE.md points to for this
/// file (covered by its own tests); this pins the Before/After/Delta styling rules, hover
/// bookkeeping, and stage/edge/boundary appearance math, pulled out of `BehaviorDiagramView`
/// and the file-`private` `StageBox` into the internal `BehaviorDiagramLogic` enum so a test
/// in another file can reach them, plus the already-plain `FlowChange`/`FlowAnnotation.Kind`
/// extensions and `glyph(_:)`. What's left in the view bodies — `Canvas` drawing, `GeometryReader`
/// layout, `ScrollView`/`ForEach` composition, hit-testing and gesture wiring — has no seam this
/// repo's suite can reach without UI-rendering infrastructure, which it doesn't have; see the PR
/// description for the honest remaining gap.
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

    // MARK: - StageBox.fill / .stroke / .strokeWidth
    //
    // `StageBox` is `private` to the file (invisible even to `@testable import`) and every one
    // of its members is implicitly `@MainActor`, so these were pulled into `BehaviorDiagramLogic`
    // as plain functions that take the same inputs explicitly — the pattern CLAUDE.md asks for.

    @Test func stageFillUsesTheChangesTintOnlyInDelta() {
        #expect(BehaviorDiagramLogic.stageFill(mode: .delta, change: .new, kind: .step, isHovered: false)
                == Color.green.opacity(0.08))
        #expect(BehaviorDiagramLogic.stageFill(mode: .delta, change: .new, kind: .step, isHovered: true)
                == Color.green.opacity(0.14))
        #expect(BehaviorDiagramLogic.stageFill(mode: .before, change: .new, kind: .step, isHovered: false)
                != Color.green.opacity(0.08))
    }

    @Test func stageFillFallsBackToKindWhenUntinted() {
        #expect(BehaviorDiagramLogic.stageFill(mode: .before, change: .existing, kind: .decision, isHovered: false)
                == Color.secondary.opacity(0.05))
        #expect(BehaviorDiagramLogic.stageFill(mode: .before, change: .existing, kind: .decision, isHovered: true)
                == Color.secondary.opacity(0.1))
        #expect(BehaviorDiagramLogic.stageFill(mode: .before, change: .existing, kind: .outcome, isHovered: false)
                == Color.secondary.opacity(0.07))
        #expect(BehaviorDiagramLogic.stageFill(mode: .before, change: .existing, kind: .step, isHovered: false)
                == Color(nsColor: .controlBackgroundColor).opacity(1))
    }

    @Test func stageStrokeSelectionOutranksTintOutranksExternalOutranksPlain() {
        // Selection wins even over a tint.
        #expect(BehaviorDiagramLogic.stageStroke(mode: .delta, change: .new, kind: .step, isSelected: true) == .accentColor)
        // A tint (Delta + an actual change) wins over the external-call color.
        #expect(BehaviorDiagramLogic.stageStroke(mode: .delta, change: .new, kind: .external, isSelected: false)
                == Color.green.opacity(0.85))
        // No tint: an external call gets its own color.
        #expect(BehaviorDiagramLogic.stageStroke(mode: .before, change: .existing, kind: .external, isSelected: false)
                == Color.purple.opacity(0.55))
        // Nothing special: the plain neutral border.
        #expect(BehaviorDiagramLogic.stageStroke(mode: .before, change: .existing, kind: .step, isSelected: false)
                == Color.secondary.opacity(0.4))
    }

    @Test func strokeWidthIsWidestWhenSelectedThenWhenTinted() {
        #expect(BehaviorDiagramLogic.stageStrokeWidth(isSelected: true, isTinted: false) == 2.4)
        #expect(BehaviorDiagramLogic.stageStrokeWidth(isSelected: true, isTinted: true) == 2.4)
        #expect(BehaviorDiagramLogic.stageStrokeWidth(isSelected: false, isTinted: true) == 1.8)
        #expect(BehaviorDiagramLogic.stageStrokeWidth(isSelected: false, isTinted: false) == 1)
    }

    // MARK: - StageBox.caption

    @Test func onlyExternalDatastoreAndSubflowStagesGetAKindCaption() {
        #expect(BehaviorDiagramLogic.stageCaption(kind: .external, subflowTitle: nil)?.text == "EXTERNAL")
        #expect(BehaviorDiagramLogic.stageCaption(kind: .datastore, subflowTitle: nil)?.text == "STORAGE")
        #expect(BehaviorDiagramLogic.stageCaption(kind: .step, subflowTitle: nil) == nil)
        #expect(BehaviorDiagramLogic.stageCaption(kind: .trigger, subflowTitle: nil) == nil)
        #expect(BehaviorDiagramLogic.stageCaption(kind: .decision, subflowTitle: nil) == nil)
        #expect(BehaviorDiagramLogic.stageCaption(kind: .outcome, subflowTitle: nil) == nil)
    }

    /// A subflow's caption only grows the "↗ opens elsewhere" arrow once a title for the target
    /// flow actually resolved; with none, it reads as a plain shared-flow label.
    @Test func subflowCaptionGrowsAnArrowOnlyWhenItsTargetHasATitle() {
        #expect(BehaviorDiagramLogic.stageCaption(kind: .subflow, subflowTitle: nil)?.text == "SHARED FLOW")
        #expect(BehaviorDiagramLogic.stageCaption(kind: .subflow, subflowTitle: "Checkout")?.text == "SHARED FLOW ↗")
    }

    // MARK: - StageBox.helpText

    @Test func helpTextAssemblesDetailChangeAndUncertaintyBeforeTheStandingHint() {
        let text = BehaviorDiagramLogic.stageHelpText(detail: "Reads the uploaded file", change: .changed, isUncertain: true)
        #expect(text == "Reads the uploaded file\nChanged by this PR\nInferred, not traced in the code\n"
                + "Click to inspect · double-click to go deeper · right-click to ask")
    }

    /// An unchanged, traced stage with no detail sentence still gets the standing hint alone.
    @Test func helpTextIsJustTheStandingHintWhenThereIsNothingElseToSay() {
        #expect(BehaviorDiagramLogic.stageHelpText(detail: nil, change: .existing, isUncertain: false)
                == "Click to inspect · double-click to go deeper · right-click to ask")
    }

    // MARK: - StageBox.changeDetail

    @Test func changeDetailIsNoneForAnUnchangedOrNewStage() {
        #expect(BehaviorDiagramLogic.changeDetailContent(mode: .delta, change: .existing, before: "a", after: "b") == .none)
        #expect(BehaviorDiagramLogic.changeDetailContent(mode: .delta, change: .new, before: nil, after: "b") == .none)
    }

    @Test func changeDetailShowsBothSidesInDeltaWhenEitherSurvived() {
        #expect(BehaviorDiagramLogic.changeDetailContent(mode: .delta, change: .changed, before: "first line", after: "up to 1 KB")
                == .beforeAndAfter(before: "first line", after: "up to 1 KB"))
        #expect(BehaviorDiagramLogic.changeDetailContent(mode: .delta, change: .changed, before: nil, after: "up to 1 KB")
                == .beforeAndAfter(before: nil, after: "up to 1 KB"))
    }

    @Test func changeDetailShowsOneSideInBeforeOrAfterMode() {
        #expect(BehaviorDiagramLogic.changeDetailContent(mode: .before, change: .changed, before: "first line", after: "up to 1 KB")
                == .beforeOnly("first line"))
        #expect(BehaviorDiagramLogic.changeDetailContent(mode: .after, change: .changed, before: "first line", after: "up to 1 KB")
                == .afterOnly("up to 1 KB"))
    }

    /// A changed stage with nothing recorded for the side on screen shows nothing, rather than
    /// an empty grid row or a crash on the force-unwrap this replaced.
    @Test func changeDetailIsNoneWhenTheModesOwnSideIsMissing() {
        #expect(BehaviorDiagramLogic.changeDetailContent(mode: .before, change: .changed, before: nil, after: "up to 1 KB") == .none)
        #expect(BehaviorDiagramLogic.changeDetailContent(mode: .after, change: .changed, before: "first line", after: nil) == .none)
        #expect(BehaviorDiagramLogic.changeDetailContent(mode: .delta, change: .changed, before: nil, after: nil) == .none)
    }

    // MARK: - Hover

    @Test func hoveringEntersClaimTheHoveredIdRegardlessOfWhatWasHoveredBefore() {
        #expect(BehaviorDiagramLogic.hoverUpdate(current: nil, id: "a", isHovering: true) == "a")
        #expect(BehaviorDiagramLogic.hoverUpdate(current: "b", id: "a", isHovering: true) == "a")
    }

    /// A leave event only clears the id it names; a stale leave for a stage the pointer already
    /// left (its hover moved straight to another stage) must never clobber the current one.
    @Test func hoverLeaveOnlyClearsTheIdItNames() {
        #expect(BehaviorDiagramLogic.hoverUpdate(current: "a", id: "a", isHovering: false) == nil)
        #expect(BehaviorDiagramLogic.hoverUpdate(current: "b", id: "a", isHovering: false) == "b")
        #expect(BehaviorDiagramLogic.hoverUpdate(current: nil, id: "a", isHovering: false) == nil)
    }

    // MARK: - Boundaries

    @Test func trustAndExternalBoundariesDrawOutsideEverythingElseDrawsInside() {
        let trust = BehaviorDiagramLogic.boundaryStyle(kind: .trust)
        #expect(trust.outside && trust.tint == .orange)
        let external = BehaviorDiagramLogic.boundaryStyle(kind: .external)
        #expect(external.outside && external.tint == .purple)
        let application = BehaviorDiagramLogic.boundaryStyle(kind: .application)
        #expect(!application.outside && application.tint == .secondary)
        let service = BehaviorDiagramLogic.boundaryStyle(kind: .service)
        #expect(!service.outside && service.tint == .secondary)
    }

    @Test func boundaryLabelMarksOnlyAnOutsideSystemAsExternal() {
        #expect(BehaviorDiagramLogic.boundaryLabelText(kind: .external, label: "Payments API") == "External · PAYMENTS API")
        #expect(BehaviorDiagramLogic.boundaryLabelText(kind: .application, label: "Contour") == "CONTOUR")
    }

    // MARK: - Edges

    @Test func edgeOpacityFollowsFadeThenExistingThenFullStrength() {
        #expect(BehaviorDiagramLogic.edgeOpacity(mode: .delta, change: .existing) == 0.35)
        #expect(BehaviorDiagramLogic.edgeOpacity(mode: .before, change: .existing) == 0.6)
        #expect(BehaviorDiagramLogic.edgeOpacity(mode: .delta, change: .new) == 0.95)
    }

    /// A removed async edge dashes as removed, not async — the two patterns would otherwise
    /// disagree, and "gone" is the fact that matters more to a reviewer than "was async".
    @Test func edgeDashRemovedWinsOverAsyncWhenBothApply() {
        #expect(BehaviorDiagramLogic.edgeDash(flow: .async, change: .existing) == [6, 4])
        #expect(BehaviorDiagramLogic.edgeDash(flow: .sync, change: .removed) == [3, 3])
        #expect(BehaviorDiagramLogic.edgeDash(flow: .async, change: .removed) == [3, 3])
        #expect(BehaviorDiagramLogic.edgeDash(flow: .sync, change: .existing).isEmpty)
    }

    @Test func edgeWidthAndArrowSizeEmphasizeAnyActualChange() {
        #expect(BehaviorDiagramLogic.edgeWidth(change: .existing) == 1.3)
        #expect(BehaviorDiagramLogic.edgeWidth(change: .new) == 2.2)
        #expect(BehaviorDiagramLogic.edgeArrowSize(change: .existing) == 8)
        #expect(BehaviorDiagramLogic.edgeArrowSize(change: .new) == 10)
    }

    /// A horizontal arrow (pointing along +x) backs up `size` points and its wings sit
    /// perpendicular, `size / 2` above and below — worked out by hand to pin the geometry.
    @Test func arrowHeadWingsSitPerpendicularToAHorizontalShaft() {
        let wings = BehaviorDiagramLogic.arrowHeadWings(from: CGPoint(x: 0, y: 0), tip: CGPoint(x: 10, y: 0), size: 4)
        #expect(abs(wings.left.x - 6) < 0.0001 && abs(wings.left.y - 2) < 0.0001)
        #expect(abs(wings.right.x - 6) < 0.0001 && abs(wings.right.y - (-2)) < 0.0001)
    }

    /// A vertical arrow (pointing along +y) backs up along y, and its wings sit `size / 2` to
    /// either side of x — the same shape, rotated a quarter turn.
    @Test func arrowHeadWingsSitPerpendicularToAVerticalShaft() {
        let wings = BehaviorDiagramLogic.arrowHeadWings(from: CGPoint(x: 0, y: 0), tip: CGPoint(x: 0, y: 10), size: 4)
        #expect(abs(wings.left.x - (-2)) < 0.0001 && abs(wings.left.y - 6) < 0.0001)
        #expect(abs(wings.right.x - 2) < 0.0001 && abs(wings.right.y - 6) < 0.0001)
    }
}
