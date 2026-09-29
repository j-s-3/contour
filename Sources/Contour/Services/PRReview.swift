import Foundation

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

    static func canReview(prState: String, ghAvailable: Bool) -> Bool {
        ghAvailable && prState.uppercased() == "OPEN"
    }

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
