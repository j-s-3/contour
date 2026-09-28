import XCTest
@testable import Contour

final class PRReviewTests: XCTestCase {
    func testOnlyAnOpenPRCanBeReviewed() {
        XCTAssertTrue(PRReview.canReview(prState: "OPEN", ghAvailable: true))
        XCTAssertTrue(PRReview.canReview(prState: "open", ghAvailable: true))
        XCTAssertFalse(PRReview.canReview(prState: "MERGED", ghAvailable: true))
        XCTAssertFalse(PRReview.canReview(prState: "CLOSED", ghAvailable: true))
    }

    /// The anonymous REST source can't write, so reviewing needs `gh`.
    func testReviewingNeedsGH() {
        XCTAssertFalse(PRReview.canReview(prState: "OPEN", ghAvailable: false))
    }

    func testSubmitsAnApprovingReviewThroughGH() {
        let url = "https://github.com/j-s-3/contour/pull/10"
        XCTAssertEqual(PRReview.arguments(prURL: url, verdict: .approve), ["pr", "review", url, "--approve"])
    }

    func testRequestsChangesWithTheReviewersComment() {
        let url = "https://github.com/j-s-3/contour/pull/10"
        XCTAssertEqual(
            PRReview.arguments(prURL: url, verdict: .requestChanges, comment: "Handle the nil case"),
            ["pr", "review", url, "--request-changes", "--body", "Handle the nil case"]
        )
    }

    /// GitHub rejects a request for changes that doesn't say what to change.
    func testRequestingChangesNeedsAComment() {
        XCTAssertFalse(PRReview.isReady(.requestChanges, comment: ""))
        XCTAssertFalse(PRReview.isReady(.requestChanges, comment: "  \n "))
        XCTAssertTrue(PRReview.isReady(.requestChanges, comment: "Handle the nil case"))
        XCTAssertTrue(PRReview.isReady(.approve, comment: ""))
    }

    /// `mockEnabled` is an injected override rather than reading `CONTOUR_MOCK_ANALYSIS`
    /// directly, so this exercises the short-circuit branch without touching the process
    /// environment (which `AnalysisCache` also reads, and which Swift Testing's parallel
    /// runner would race) or shelling out to a real `gh`.
    func testSubmitShortCircuitsWithoutCallingGHWhenMockIsEnabled() async throws {
        let url = "https://github.com/j-s-3/contour/pull/10"
        try await PRReview.submit(prURL: url, verdict: .approve, mockEnabled: true)
    }

    func testReviewStateEqualityDistinguishesEveryCase() {
        XCTAssertEqual(PRReview.State.idle, .idle)
        XCTAssertEqual(PRReview.State.submitting(.approve), .submitting(.approve))
        XCTAssertNotEqual(PRReview.State.submitting(.approve), .submitting(.requestChanges))
        XCTAssertNotEqual(PRReview.State.submitting(.approve), .submitted(.approve))
        XCTAssertEqual(PRReview.State.failed(.approve, "boom"), .failed(.approve, "boom"))
        XCTAssertNotEqual(PRReview.State.failed(.approve, "boom"), .failed(.approve, "other"))
    }
}
