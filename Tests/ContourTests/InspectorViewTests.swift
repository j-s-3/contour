import SwiftUI
import Testing

@testable import Contour

struct InspectorViewTests {
    private func content(
        purpose: Statement? = nil,
        usedBy: [String] = [],
        implementedBy: [String] = [],
        changedByThisPR: Bool = false,
        changeClaim: String? = nil,
        refs: [CodeRef] = [],
        onShowImplementation: (() -> Void)? = nil
    ) -> InspectorContent {
        InspectorContent(
            title: "PagePublisher", kindLabel: "Component", purpose: purpose,
            usedBy: usedBy, implementedBy: implementedBy,
            changedByThisPR: changedByThisPR, changeClaim: changeClaim, refs: refs,
            onShowImplementation: onShowImplementation)
    }

    @Test func changedByThisPRTextFallsBackToYesWhenChangedWithNoClaim() {
        #expect(content(changedByThisPR: true).changedByThisPRText == "Yes")
    }

    @Test func changedByThisPRTextFallsBackToNoWhenUnchangedWithNoClaim() {
        #expect(content(changedByThisPR: false).changedByThisPRText == "No")
    }

    @Test func changedByThisPRTextPrefersTheAuthorsOwnClaimWhenChanged() {
        let c = content(changedByThisPR: true, changeClaim: "Refactored, not behaviorally changed")
        #expect(c.changedByThisPRText == "Refactored, not behaviorally changed")
    }

    @Test func changedByThisPRTextUsesTheClaimEvenWhenUnchanged() {
        let c = content(changedByThisPR: false, changeClaim: "Untouched; listed for context")
        #expect(c.changedByThisPRText == "Untouched; listed for context")
    }

    private func content(title: String, kindLabel: String) -> InspectorContent {
        InspectorContent(
            title: title, kindLabel: kindLabel, purpose: nil, usedBy: [], implementedBy: [],
            changedByThisPR: false, changeClaim: nil, refs: [], onShowImplementation: nil)
    }

    @Test func kindLabelDisplayIsUpperCased() {
        #expect(content(title: "t", kindLabel: "component").kindLabelDisplay == "COMPONENT")
    }

    @Test func kindLabelDisplayLeavesAnAlreadyUpperCasedLabelAlone() {
        #expect(content(title: "t", kindLabel: "FLOW").kindLabelDisplay == "FLOW")
    }

    @Test func showsUsedByIsFalseWhenEmptyAndTrueOtherwise() {
        #expect(!content(usedBy: []).showsUsedBy)
        #expect(content(usedBy: ["Router"]).showsUsedBy)
    }

    @Test func showsImplementedByIsFalseWhenEmptyAndTrueOtherwise() {
        #expect(!content(implementedBy: []).showsImplementedBy)
        #expect(content(implementedBy: ["PagePublisher.swift:12"]).showsImplementedBy)
    }

    @Test func showsEvidenceIsFalseWhenEmptyAndTrueOtherwise() {
        let ref = CodeRef(path: "a.swift", startLine: 1, endLine: 2)
        #expect(!content(refs: []).showsEvidence)
        #expect(content(refs: [ref]).showsEvidence)
    }

    @Test func primaryRefIsNilWithNoEvidence() {
        #expect(content(refs: []).primaryRef == nil)
    }

    @Test func primaryRefIsTheFirstRefWhenThereAreSeveral() {
        let first = CodeRef(path: "a.swift", startLine: 1, endLine: 2)
        let second = CodeRef(path: "b.swift", startLine: 3, endLine: 4)
        #expect(content(refs: [first, second]).primaryRef == first)
    }

    @Test func changedIconNameIsAFilledCheckmarkWhenChangedAndAMinusOtherwise() {
        #expect(InspectorView.changedIconName(true) == "checkmark.circle.fill")
        #expect(InspectorView.changedIconName(false) == "minus.circle")
    }

    @Test func changedIconTintIsGreenWhenChangedAndSecondaryOtherwise() {
        #expect(InspectorView.changedIconTint(true) == .green)
        #expect(InspectorView.changedIconTint(false) == .secondary)
    }
}
