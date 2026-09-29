import AppKit
import SwiftUI
import Testing

@testable import Contour

struct RequestChangesSheetTests {
    @MainActor
    @Test func submitPassesTheCommentToOnSubmit() {
        var submitted: String?
        RequestChangesSheet.submit(comment: "Handle the nil case", onSubmit: { submitted = $0 }, dismiss: {})
        #expect(submitted == "Handle the nil case")
    }

    @MainActor
    @Test func submitCallsOnSubmitBeforeDismissing() {
        var order: [String] = []
        RequestChangesSheet.submit(
            comment: "x", onSubmit: { _ in order.append("submit") }, dismiss: { order.append("dismiss") })
        #expect(order == ["submit", "dismiss"])
    }

    @MainActor
    @Test func showsPlaceholderWhenTheCommentIsEmpty() {
        #expect(RequestChangesSheet.showsPlaceholder(comment: ""))
    }

    @MainActor
    @Test func hidesPlaceholderOnceTheReviewerHasTypedSomething() {
        #expect(!RequestChangesSheet.showsPlaceholder(comment: "Handle the nil case"))
    }

    @MainActor
    @Test func sheetLaysOutInsideAWindowWithItsFixedWidth() {
        let sheet = RequestChangesSheet(title: "Request changes on #7", onSubmit: { _ in })
        let host = NSHostingView(rootView: sheet)
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 480, height: 320), styleMask: [.titled], backing: .buffered,
            defer: false)
        window.contentView = host
        window.orderBack(nil)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        host.layoutSubtreeIfNeeded()
        #expect(host.fittingSize.width == 440)
        let escape = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
            context: nil, characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", isARepeat: false,
            keyCode: 53)
        if let escape { _ = window.performKeyEquivalent(with: escape) }
        window.orderOut(nil)
    }
}
