import Foundation

/// Approving the open pull request — the one write Contour makes to GitHub. It goes
/// through the reviewer's own authenticated `gh`, like every private read, so the approval
/// is theirs and Contour still never holds a token. The anonymous REST source can't write
/// at all, so without `gh` there is no Approve.
enum PRApproval {
    enum State: Equatable {
        case idle
        case approving
        case approved
        case failed(String)
    }

    /// Only an open PR can be approved; GitHub rejects a review on a merged or closed one.
    /// Both sources report state as `gh` does (OPEN / CLOSED / MERGED).
    static func canApprove(prState: String, ghAvailable: Bool) -> Bool {
        ghAvailable && prState.uppercased() == "OPEN"
    }

    static func arguments(prURL: String) -> [String] {
        ["pr", "review", prURL, "--approve"]
    }

    /// With `CONTOUR_MOCK_ANALYSIS=1` nothing is sent: the fixtures' PR isn't the
    /// reviewer's to approve.
    static func approve(prURL: String) async throws {
        if MockAnalysisFixtures.isEnabled {
            try await Task.sleep(for: .milliseconds(400))
            return
        }
        try await Shell.run("gh", arguments(prURL: prURL))
    }
}
