import Testing
import SwiftUI
@testable import Contour

/// `StageBoxLogic`, `BehaviorChangeDiagramMetrics`, and `CappedWidthLogic` are this file's
/// pure logic — delta/tint/help-text derivation, density-dependent sizing, and
/// `CappedWidth`'s one bit of math — pulled out of `StageBox`/`diagram`/`row`/`chain` and
/// `CappedWidth` (all private or fileprivate to the file) into top-level types so they're
/// directly testable against plain `BehaviorStageTag`/`BehaviorOutcome`/`Density` fixtures.
/// The rest — the before/after `Grid`, `ViewThatFits` density stepping, `CappedWidth`'s
/// `Layout.sizeThatFits`/`placeSubviews` (which need a real SwiftUI `Subview` to measure) —
/// is view rendering and SwiftUI layout with no UI-testing infrastructure in this suite.
struct BehaviorChangeDiagramViewTests {

    // MARK: - isDelta

    @Test func afterOnlyStageIsDeltaOnlyInTheAfterRow() {
        #expect(StageBoxLogic.isDelta(isAfter: true, tag: .afterOnly))
        #expect(!StageBoxLogic.isDelta(isAfter: false, tag: .afterOnly))
    }

    @Test func beforeOnlyStageIsDeltaOnlyInTheBeforeRow() {
        #expect(StageBoxLogic.isDelta(isAfter: false, tag: .beforeOnly))
        #expect(!StageBoxLogic.isDelta(isAfter: true, tag: .beforeOnly))
    }

    @Test func aStageInBothRowsIsNeverDelta() {
        #expect(!StageBoxLogic.isDelta(isAfter: true, tag: .both))
        #expect(!StageBoxLogic.isDelta(isAfter: false, tag: .both))
    }

    // MARK: - tint

    @Test func tintIsRedOnFailureRegardlessOfDelta() {
        #expect(StageBoxLogic.tint(outcome: .failure, isAfter: true, isDelta: false) == .red)
        #expect(StageBoxLogic.tint(outcome: .failure, isAfter: false, isDelta: true) == .red)
    }

    @Test func tintIsGreenOnSuccessRegardlessOfDelta() {
        #expect(StageBoxLogic.tint(outcome: .success, isAfter: true, isDelta: false) == .green)
    }

    @Test func tintIsGreenForANewAfterStageWithNoOutcome() {
        #expect(StageBoxLogic.tint(outcome: nil, isAfter: true, isDelta: true) == .green)
    }

    @Test func tintIsNilForAnOrdinaryStageWithNoOutcome() {
        #expect(StageBoxLogic.tint(outcome: nil, isAfter: true, isDelta: false) == nil)
        #expect(StageBoxLogic.tint(outcome: nil, isAfter: false, isDelta: true) == nil, "delta only tints green in the After row")
    }

    // MARK: - fill / stroke

    @Test func fillUsesTheTintWhenPresent() {
        #expect(StageBoxLogic.fill(tint: .red, hovered: false, isAfter: true) == Color.red.opacity(0.1))
        #expect(StageBoxLogic.fill(tint: .red, hovered: true, isAfter: true) == Color.red.opacity(0.16))
    }

    @Test func fillFallsBackToNeutralWithNoTint() {
        #expect(StageBoxLogic.fill(tint: nil, hovered: false, isAfter: true) == Color.secondary.opacity(0.07))
        #expect(StageBoxLogic.fill(tint: nil, hovered: false, isAfter: false) == Color.secondary.opacity(0.04))
        #expect(StageBoxLogic.fill(tint: nil, hovered: true, isAfter: false) == Color.secondary.opacity(0.12))
    }

    @Test func strokeUsesTheTintWhenPresent() {
        #expect(StageBoxLogic.stroke(tint: .green, isAfter: true) == Color.green.opacity(0.55))
    }

    @Test func strokeFallsBackToNeutralWithNoTint() {
        #expect(StageBoxLogic.stroke(tint: nil, isAfter: true) == Color.secondary.opacity(0.3))
        #expect(StageBoxLogic.stroke(tint: nil, isAfter: false) == Color.secondary.opacity(0.25))
    }

    // MARK: - helpText

    @Test func helpTextIsJustTheHintForAnOrdinaryStage() {
        #expect(StageBoxLogic.helpText(isDelta: false, isAfter: true, outcome: nil) == "Click to open · right-click to ask about it")
    }

    @Test func helpTextNamesANewStageInTheAfterRow() {
        #expect(StageBoxLogic.helpText(isDelta: true, isAfter: true, outcome: nil) == "New in this PR · Click to open · right-click to ask about it")
    }

    @Test func helpTextNamesARemovedStageInTheBeforeRow() {
        #expect(StageBoxLogic.helpText(isDelta: true, isAfter: false, outcome: nil) == "No longer happens · Click to open · right-click to ask about it")
    }

    @Test func helpTextAppendsTheOutcome() {
        #expect(StageBoxLogic.helpText(isDelta: false, isAfter: true, outcome: .failure) == "Fails · Click to open · right-click to ask about it")
        #expect(StageBoxLogic.helpText(isDelta: false, isAfter: true, outcome: .success) == "Succeeds · Click to open · right-click to ask about it")
    }

    @Test func helpTextCombinesDeltaAndOutcome() {
        #expect(StageBoxLogic.helpText(isDelta: true, isAfter: true, outcome: .success) == "New in this PR · Succeeds · Click to open · right-click to ask about it")
    }

    // MARK: - strokeStyle

    @Test func strokeStyleIsThinAndSolidForAnOrdinaryStage() {
        let style = StageBoxLogic.strokeStyle(isDelta: false, hasOutcome: false, isAfter: true)
        #expect(style.lineWidth == 1)
        #expect(style.dash == [])
    }

    @Test func strokeStyleThickensForADeltaOrAnOutcome() {
        #expect(StageBoxLogic.strokeStyle(isDelta: true, hasOutcome: false, isAfter: true).lineWidth == 1.2)
        #expect(StageBoxLogic.strokeStyle(isDelta: false, hasOutcome: true, isAfter: true).lineWidth == 1.2)
    }

    @Test func strokeStyleDashesOnlyARemovedStageInTheBeforeRow() {
        #expect(StageBoxLogic.strokeStyle(isDelta: true, hasOutcome: false, isAfter: false).dash == [4, 3])
        #expect(StageBoxLogic.strokeStyle(isDelta: true, hasOutcome: false, isAfter: true).dash == [],
                "a new stage in the After row is a delta but never dashes")
        #expect(StageBoxLogic.strokeStyle(isDelta: false, hasOutcome: true, isAfter: false).dash == [],
                "an outcome alone (not a delta) never dashes")
    }

    // MARK: - BehaviorChangeDiagramMetrics

    /// Regular density is the roomiest setting; every other case steps down together, since
    /// the doc comment on `Density` promises Before and After stay in step.
    @Test func gridSpacingStepsDownTogetherOffRegular() {
        let regular = BehaviorChangeDiagramMetrics.gridSpacing(for: .regular)
        #expect(regular.horizontal == 18)
        #expect(regular.vertical == 16)

        for density: BehaviorChangeDiagramView.Density in [.tight, .wrapped] {
            let spacing = BehaviorChangeDiagramMetrics.gridSpacing(for: density)
            #expect(spacing.horizontal == 12)
            #expect(spacing.vertical == 10)
        }
    }

    @Test func labelWidthIsWiderOnlyAtRegularDensity() {
        #expect(BehaviorChangeDiagramMetrics.labelWidth(for: .regular) == 56)
        #expect(BehaviorChangeDiagramMetrics.labelWidth(for: .tight) == 48)
        #expect(BehaviorChangeDiagramMetrics.labelWidth(for: .wrapped) == 48)
    }

    @Test func arrowFontSizeIsLargerOnlyAtRegularDensity() {
        #expect(BehaviorChangeDiagramMetrics.arrowFontSize(for: .regular) == 13)
        #expect(BehaviorChangeDiagramMetrics.arrowFontSize(for: .tight) == 11)
        #expect(BehaviorChangeDiagramMetrics.arrowFontSize(for: .wrapped) == 11)
    }

    /// Unlike the other metrics (which only distinguish regular from everything denser),
    /// the arrow's padding has three distinct steps — one per `Density` case.
    @Test func arrowHorizontalPaddingHasThreeDistinctSteps() {
        #expect(BehaviorChangeDiagramMetrics.arrowHorizontalPadding(for: .regular) == 10)
        #expect(BehaviorChangeDiagramMetrics.arrowHorizontalPadding(for: .tight) == 6)
        #expect(BehaviorChangeDiagramMetrics.arrowHorizontalPadding(for: .wrapped) == 4)
    }

    @Test func boxPaddingIsLargerOnlyAtRegularDensity() {
        #expect(BehaviorChangeDiagramMetrics.boxHorizontalPadding(for: .regular) == 14)
        #expect(BehaviorChangeDiagramMetrics.boxHorizontalPadding(for: .tight) == 10)
        #expect(BehaviorChangeDiagramMetrics.boxHorizontalPadding(for: .wrapped) == 10)

        #expect(BehaviorChangeDiagramMetrics.boxVerticalPadding(for: .regular) == 10)
        #expect(BehaviorChangeDiagramMetrics.boxVerticalPadding(for: .tight) == 6)
        #expect(BehaviorChangeDiagramMetrics.boxVerticalPadding(for: .wrapped) == 6)
    }

    // MARK: - CappedWidthLogic

    @Test func cappedWidthPassesThroughAWidthAtOrUnderTheCap() {
        #expect(CappedWidthLogic.cap(naturalWidth: 40, at: 88) == 40)
        #expect(CappedWidthLogic.cap(naturalWidth: 88, at: 88) == 88)
    }

    @Test func cappedWidthClampsAWiderWidth() {
        #expect(CappedWidthLogic.cap(naturalWidth: 240, at: 88) == 88)
    }
}
