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
}
