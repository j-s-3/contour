import Testing
import SwiftUI
@testable import Contour

/// `StageBoxLogic` is the delta/tint/help-text derivation CLAUDE.md calls out for this
/// file, pulled out of `StageBox` (private to the file) into a top-level enum so it's
/// directly testable against plain `BehaviorStageTag`/`BehaviorOutcome` fixtures. The rest
/// — the before/after grid, density stepping, `CappedWidth`'s `Layout` implementation — is
/// view rendering and SwiftUI layout with no UI-testing infrastructure in this suite.
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
}
