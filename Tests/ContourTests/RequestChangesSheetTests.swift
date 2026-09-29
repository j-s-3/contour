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
