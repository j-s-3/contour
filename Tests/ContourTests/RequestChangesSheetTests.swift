import Testing
@testable import Contour

/// `RequestChangesSheet.swift`'s only logic of its own is the submit action; the
/// comment-required validation that gates its button lives in `PRReview.isReady`, already
/// covered by `PRReviewTests`, per CLAUDE.md's guidance for this file.
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
}
