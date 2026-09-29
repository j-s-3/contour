import AppKit
import SwiftUI
import Testing

@testable import Contour

@MainActor
struct InspectorViewRenderTests {

    private func host(_ content: InspectorContent?) -> NSHostingView<InspectorView> {
        let hosting = NSHostingView(rootView: InspectorView(content: content, onOpenEvidence: { _ in }))
        hosting.frame = NSRect(x: 0, y: 0, width: 360, height: 700)
        hosting.layoutSubtreeIfNeeded()
        return hosting
    }

    @Test func emptySelectionRenders() {
        #expect(host(nil).fittingSize.width >= 0)
    }

    @Test func fullyPopulatedContentRenders() {
        let content = InspectorContent(
            title: "PagePublisher", kindLabel: "Component",
            purpose: Statement(text: "Publishes pages.", provenance: .fact),
            usedBy: ["Scheduler", "Editor"], implementedBy: ["PagePublisher.publish"],
            changedByThisPR: true, changeClaim: "Reworked retries",
            refs: [CodeRef(path: "Sources/A.swift", startLine: 1, endLine: 9)],
            onShowImplementation: {})
        #expect(host(content).fittingSize.width >= 0)
    }

    @Test func minimalContentRenders() {
        let content = InspectorContent(title: "Bare", kindLabel: "Part", changedByThisPR: false)
        #expect(host(content).fittingSize.width >= 0)
    }

    @Test func changedIconReflectsChangeState() {
        #expect(InspectorView.changedIconName(true) == "checkmark.circle.fill")
        #expect(InspectorView.changedIconName(false) == "minus.circle")
        #expect(InspectorView.changedIconTint(true) == .green)
        #expect(InspectorView.changedIconTint(false) == .secondary)
    }
}
