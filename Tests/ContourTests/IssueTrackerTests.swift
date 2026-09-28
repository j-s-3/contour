import Testing
@testable import Contour

/// `IssueTracker.swift` was at 42.31% coverage (`GitHubIssueTrackerTests`/`TrackerAndCacheTests`
/// already exercise `displayKey` for all three trackers). `TrackerID.displayName`, `NoTracker`,
/// and `IssueTrackerFactory.make`'s dispatch were still untested.
struct IssueTrackerTests {

    private struct UnusedSource: PRSource {
        var describesItself: String { "unused" }
        func fetchContext(prURL: String) async throws -> RawPRContext { fatalError("not used") }
        func fetchIssue(owner: String, repo: String, number: String) async -> RawIssue? { nil }
    }

    @Test func everyTrackerHasADisplayName() {
        #expect(TrackerID.github.displayName == "GitHub Issues")
        #expect(TrackerID.jira.displayName == "Jira")
        #expect(TrackerID.none.displayName == "None")
    }

    @Test func noTrackerNeverFindsOrFetchesAnything() async {
        let tracker = NoTracker()
        #expect(tracker.id == .none)
        let context = RawPRContext(
            url: "https://github.com/acme/shop/pull/1", owner: "acme", repo: "shop", number: 1,
            title: "Fixes #1", body: "", author: "someone", state: "OPEN", headRefName: "main",
            baseRefName: "main", headSha: "abc123", baseSha: "def456", isCrossRepository: false,
            headCloneURL: "https://github.com/acme/shop.git", additions: 1, deletions: 1, changedFiles: 1,
            files: [], commits: [], comments: [], reviews: [], diff: "diff"
        )
        #expect(tracker.reference(in: context) == nil)
        let fetched = await tracker.fetch(IssueRef(id: "1", tracker: .none))
        #expect(fetched == nil)
    }

    @Test func factoryDispatchesToTheMatchingTracker() {
        #expect(IssueTrackerFactory.make(.github, source: UnusedSource()).id == .github)
        #expect(IssueTrackerFactory.make(.jira, source: UnusedSource()).id == .jira)
        #expect(IssueTrackerFactory.make(.none, source: UnusedSource()).id == .none)
    }
}
