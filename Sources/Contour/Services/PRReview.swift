import Foundation

/// Reviewing the open pull request — approving it or requesting changes, the only writes
/// Contour makes to GitHub. They go through the reviewer's own authenticated `gh`, like
/// every private read, so the review is theirs and Contour still never holds a token. The
/// anonymous REST source can't write at all, so without `gh` there is no review.
enum PRReview {
    enum Verdict: Equatable {
        case approve
        case requestChanges
    }

    enum State: Equatable {
        case idle
        case submitting(Verdict)
        case submitted(Verdict)
        case failed(Verdict, String)
    }

    /// Only an open PR can be reviewed; GitHub rejects a review on a merged or closed one.
    /// Both sources report state as `gh` does (OPEN / CLOSED / MERGED).
    static func canReview(prState: String, ghAvailable: Bool) -> Bool {
        ghAvailable && prState.uppercased() == "OPEN"
    }

    /// GitHub rejects a request for changes that doesn't say what to change.
    static func isReady(_ verdict: Verdict, comment: String) -> Bool {
        verdict == .approve || !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func arguments(prURL: String, verdict: Verdict, comment: String = "") -> [String] {
        switch verdict {
        case .approve:
            ["pr", "review", prURL, "--approve"]
        case .requestChanges:
            ["pr", "review", prURL, "--request-changes", "--body", comment]
        }
    }

    /// With `CONTOUR_MOCK_ANALYSIS=1` nothing is sent: the fixtures' PR isn't the
    /// reviewer's to review. `mockEnabled` defaults to the real environment check; tests
    /// override it directly rather than mutating the process environment, which
    /// `AnalysisCache` and friends also read and which Swift Testing's parallel runner
    /// would race.
    static func submit(
        prURL: String, verdict: Verdict, comment: String = "",
        mockEnabled: Bool = MockAnalysisFixtures.isEnabled
    ) async throws {
        if mockEnabled {
            try await Task.sleep(for: .milliseconds(400))
            return
        }
        try await Shell.run("gh", arguments(prURL: prURL, verdict: verdict, comment: comment))
    }
}
