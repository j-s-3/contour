import Testing
@testable import Contour

/// `InspectorContent.changedByThisPRText` is `InspectorView.swift`'s one piece of real
/// content-selection/formatting logic, per CLAUDE.md's guidance for this file; the rest is
/// view bodies with no UI-testing infrastructure in this suite to host them.
struct InspectorViewTests {
    private func content(changedByThisPR: Bool, changeClaim: String? = nil) -> InspectorContent {
        InspectorContent(title: "PagePublisher", kindLabel: "Component", purpose: nil,
                          changedByThisPR: changedByThisPR, changeClaim: changeClaim)
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

    /// Even an unchanged node can carry its own explanatory claim, and the claim still wins.
    @Test func changedByThisPRTextUsesTheClaimEvenWhenUnchanged() {
        let c = content(changedByThisPR: false, changeClaim: "Untouched; listed for context")
        #expect(c.changedByThisPRText == "Untouched; listed for context")
    }
}
