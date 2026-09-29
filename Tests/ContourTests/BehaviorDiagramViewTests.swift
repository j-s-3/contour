import Foundation
import Testing
import SwiftUI
@testable import Contour

struct BehaviorDiagramViewTests {
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

    @Test func decisionAndQuestionAnnotationsHaveDistinctStyling() {
        #expect(FlowAnnotation.Kind.decision.color == .teal)
        #expect(FlowAnnotation.Kind.question.color == .orange)
        #expect(FlowAnnotation.Kind.decision.symbol == "diamond")
        #expect(FlowAnnotation.Kind.question.symbol == "exclamationmark.triangle.fill")
        #expect(FlowAnnotation.Kind.decision.caption == "DECISION")
        #expect(FlowAnnotation.Kind.question.caption == "REVIEW QUESTION")
    }

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

    @Test func dashPrefersTheRemovedPatternOverTheExternalPatternWhenBothApply() {
        #expect(BehaviorDiagramLogic.dash(mode: .delta, change: .removed, kind: .external) == [4, 3])
    }

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
        #expect(BehaviorDiagramLogic.stageStroke(mode: .delta, change: .new, kind: .step, isSelected: true) == .accentColor)
        #expect(BehaviorDiagramLogic.stageStroke(mode: .delta, change: .new, kind: .external, isSelected: false)
                == Color.green.opacity(0.85))
        #expect(BehaviorDiagramLogic.stageStroke(mode: .before, change: .existing, kind: .external, isSelected: false)
                == Color.purple.opacity(0.55))
        #expect(BehaviorDiagramLogic.stageStroke(mode: .before, change: .existing, kind: .step, isSelected: false)
                == Color.secondary.opacity(0.4))
    }

    @Test func strokeWidthIsWidestWhenSelectedThenWhenTinted() {
        #expect(BehaviorDiagramLogic.stageStrokeWidth(isSelected: true, isTinted: false) == 2.4)
        #expect(BehaviorDiagramLogic.stageStrokeWidth(isSelected: true, isTinted: true) == 2.4)
        #expect(BehaviorDiagramLogic.stageStrokeWidth(isSelected: false, isTinted: true) == 1.8)
        #expect(BehaviorDiagramLogic.stageStrokeWidth(isSelected: false, isTinted: false) == 1)
    }

    @Test func onlyExternalDatastoreAndSubflowStagesGetAKindCaption() {
        #expect(BehaviorDiagramLogic.stageCaption(kind: .external, subflowTitle: nil)?.text == "EXTERNAL")
        #expect(BehaviorDiagramLogic.stageCaption(kind: .datastore, subflowTitle: nil)?.text == "STORAGE")
        #expect(BehaviorDiagramLogic.stageCaption(kind: .step, subflowTitle: nil) == nil)
        #expect(BehaviorDiagramLogic.stageCaption(kind: .trigger, subflowTitle: nil) == nil)
        #expect(BehaviorDiagramLogic.stageCaption(kind: .decision, subflowTitle: nil) == nil)
        #expect(BehaviorDiagramLogic.stageCaption(kind: .outcome, subflowTitle: nil) == nil)
    }

    @Test func subflowCaptionGrowsAnArrowOnlyWhenItsTargetHasATitle() {
        #expect(BehaviorDiagramLogic.stageCaption(kind: .subflow, subflowTitle: nil)?.text == "SHARED FLOW")
        #expect(BehaviorDiagramLogic.stageCaption(kind: .subflow, subflowTitle: "Checkout")?.text == "SHARED FLOW ↗")
    }

    @Test func helpTextAssemblesDetailChangeAndUncertaintyBeforeTheStandingHint() {
        let text = BehaviorDiagramLogic.stageHelpText(detail: "Reads the uploaded file", change: .changed, isUncertain: true)
        #expect(text == "Reads the uploaded file\nChanged by this PR\nInferred, not traced in the code\n"
                + "Click to inspect · double-click to go deeper · right-click to ask")
    }

    @Test func helpTextIsJustTheStandingHintWhenThereIsNothingElseToSay() {
        #expect(BehaviorDiagramLogic.stageHelpText(detail: nil, change: .existing, isUncertain: false)
                == "Click to inspect · double-click to go deeper · right-click to ask")
    }

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

    @Test func changeDetailIsNoneWhenTheModesOwnSideIsMissing() {
        #expect(BehaviorDiagramLogic.changeDetailContent(mode: .before, change: .changed, before: nil, after: "up to 1 KB") == .none)
        #expect(BehaviorDiagramLogic.changeDetailContent(mode: .after, change: .changed, before: "first line", after: nil) == .none)
        #expect(BehaviorDiagramLogic.changeDetailContent(mode: .delta, change: .changed, before: nil, after: nil) == .none)
    }

    @Test func hoveringEntersClaimTheHoveredIdRegardlessOfWhatWasHoveredBefore() {
        #expect(BehaviorDiagramLogic.hoverUpdate(current: nil, id: "a", isHovering: true) == "a")
        #expect(BehaviorDiagramLogic.hoverUpdate(current: "b", id: "a", isHovering: true) == "a")
    }

    @Test func hoverLeaveOnlyClearsTheIdItNames() {
        #expect(BehaviorDiagramLogic.hoverUpdate(current: "a", id: "a", isHovering: false) == nil)
        #expect(BehaviorDiagramLogic.hoverUpdate(current: "b", id: "a", isHovering: false) == "b")
        #expect(BehaviorDiagramLogic.hoverUpdate(current: nil, id: "a", isHovering: false) == nil)
    }

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

    @Test func edgeOpacityFollowsFadeThenExistingThenFullStrength() {
        #expect(BehaviorDiagramLogic.edgeOpacity(mode: .delta, change: .existing) == 0.35)
        #expect(BehaviorDiagramLogic.edgeOpacity(mode: .before, change: .existing) == 0.6)
        #expect(BehaviorDiagramLogic.edgeOpacity(mode: .delta, change: .new) == 0.95)
    }

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

    @Test func arrowHeadWingsSitPerpendicularToAHorizontalShaft() {
        let wings = BehaviorDiagramLogic.arrowHeadWings(from: CGPoint(x: 0, y: 0), tip: CGPoint(x: 10, y: 0), size: 4)
        #expect(abs(wings.left.x - 6) < 0.0001 && abs(wings.left.y - 2) < 0.0001)
        #expect(abs(wings.right.x - 6) < 0.0001 && abs(wings.right.y - (-2)) < 0.0001)
    }

    @Test func arrowHeadWingsSitPerpendicularToAVerticalShaft() {
        let wings = BehaviorDiagramLogic.arrowHeadWings(from: CGPoint(x: 0, y: 0), tip: CGPoint(x: 0, y: 10), size: 4)
        #expect(abs(wings.left.x - (-2)) < 0.0001 && abs(wings.left.y - 6) < 0.0001)
        #expect(abs(wings.right.x - 2) < 0.0001 && abs(wings.right.y - 6) < 0.0001)
    }
}
