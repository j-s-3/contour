import SwiftUI
import Testing
@testable import Contour

/// `InspectorView.swift` was at 0.00% coverage; a first pass (#168) pulled
/// `changedByThisPRText` out to `InspectorContent` and covered its branches, leaving the
/// rest of the file — the section-visibility gates and the "CHANGED BY THIS PR" icon/tint —
/// still inline in the view body. Re-measured against `main` afterward, the file sat at
/// 2.15%, so this second pass pulls those out too: `kindLabelDisplay`, `showsUsedBy`,
/// `showsImplementedBy`, `showsEvidence` and `primaryRef` on `InspectorContent`, plus
/// `InspectorView.changedIconName`/`changedIconTint`. What's left in `body` — the
/// `ScrollView`/`VStack`/`ForEach`/`field`/`header` structure and its `WrapChips`/button
/// wiring — renders real SwiftUI content with no UI-testing infrastructure in this suite to
/// host it, and stays untested here as in the first pass.
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
        InspectorContent(title: "PagePublisher", kindLabel: "Component", purpose: purpose,
                          usedBy: usedBy, implementedBy: implementedBy,
                          changedByThisPR: changedByThisPR, changeClaim: changeClaim, refs: refs,
                          onShowImplementation: onShowImplementation)
    }

    // MARK: - changedByThisPRText

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

    /// Even an unchanged node can carry its own explanatory claim, and the claim still wins.
    @Test func changedByThisPRTextUsesTheClaimEvenWhenUnchanged() {
        let c = content(changedByThisPR: false, changeClaim: "Untouched; listed for context")
        #expect(c.changedByThisPRText == "Untouched; listed for context")
    }

    // MARK: - kindLabelDisplay

    private func content(title: String, kindLabel: String) -> InspectorContent {
        InspectorContent(title: title, kindLabel: kindLabel, purpose: nil, usedBy: [], implementedBy: [],
                          changedByThisPR: false, changeClaim: nil, refs: [], onShowImplementation: nil)
    }

    @Test func kindLabelDisplayIsUpperCased() {
        #expect(content(title: "t", kindLabel: "component").kindLabelDisplay == "COMPONENT")
    }

    @Test func kindLabelDisplayLeavesAnAlreadyUpperCasedLabelAlone() {
        #expect(content(title: "t", kindLabel: "FLOW").kindLabelDisplay == "FLOW")
    }

    // MARK: - showsUsedBy / showsImplementedBy / showsEvidence

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

    // MARK: - primaryRef

    @Test func primaryRefIsNilWithNoEvidence() {
        #expect(content(refs: []).primaryRef == nil)
    }

    /// "Show diff" always opens the *first* ref, even when there are several.
    @Test func primaryRefIsTheFirstRefWhenThereAreSeveral() {
        let first = CodeRef(path: "a.swift", startLine: 1, endLine: 2)
        let second = CodeRef(path: "b.swift", startLine: 3, endLine: 4)
        #expect(content(refs: [first, second]).primaryRef == first)
    }

    // MARK: - changedIconName / changedIconTint

    @Test func changedIconNameIsAFilledCheckmarkWhenChangedAndAMinusOtherwise() {
        #expect(InspectorView.changedIconName(true) == "checkmark.circle.fill")
        #expect(InspectorView.changedIconName(false) == "minus.circle")
    }

    @Test func changedIconTintIsGreenWhenChangedAndSecondaryOtherwise() {
        #expect(InspectorView.changedIconTint(true) == .green)
        #expect(InspectorView.changedIconTint(false) == .secondary)
    }
}
