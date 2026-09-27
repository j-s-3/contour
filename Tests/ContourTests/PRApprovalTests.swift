import XCTest
@testable import Contour

final class PRApprovalTests: XCTestCase {
    func testOnlyAnOpenPRCanBeApproved() {
        XCTAssertTrue(PRApproval.canApprove(prState: "OPEN", ghAvailable: true))
        XCTAssertTrue(PRApproval.canApprove(prState: "open", ghAvailable: true))
        XCTAssertFalse(PRApproval.canApprove(prState: "MERGED", ghAvailable: true))
        XCTAssertFalse(PRApproval.canApprove(prState: "CLOSED", ghAvailable: true))
    }

    /// The anonymous REST source can't write, so approving needs `gh`.
    func testApprovingNeedsGH() {
        XCTAssertFalse(PRApproval.canApprove(prState: "OPEN", ghAvailable: false))
    }

    func testSubmitsAnApprovingReviewThroughGH() {
        let url = "https://github.com/j-s-3/contour/pull/10"
        XCTAssertEqual(PRApproval.arguments(prURL: url), ["pr", "review", url, "--approve"])
    }
}
