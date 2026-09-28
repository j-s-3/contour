import Testing
@testable import Contour

/// `RequestChangesSheet.swift`'s own logic is `submit` and `showsPlaceholder`; the
/// comment-required validation that gates its button lives in `PRReview.isReady`, already
/// covered by `PRReviewTests`, per CLAUDE.md's guidance for this file. Everything else in
/// the file is declarative SwiftUI layout with no hosting environment under `swift test`
/// (see `AppDelegateTests.swift`'s note on `ContourApp.body`/`ReviewCommands.body` for the
/// same constraint), so those lines are accepted as unreachable from a unit test — per
/// issue #116, that's the deliberate stopping point for this file, not an oversight.
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
        RequestChangesSheet.submit(comment: "x", onSubmit: { _ in order.append("submit") }, dismiss: { order.append("dismiss") })
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
}
