import XCTest
@testable import Contour

final class TrackerAndCacheTests: XCTestCase {
    private func makeContext(title: String, body: String = "", headRef: String = "main", commits: [CommitInfo] = []) -> RawPRContext {
        RawPRContext(
            url: "https://github.com/acme/shop/pull/1", owner: "acme", repo: "shop", number: 1,
            title: title, body: body, author: "someone", state: "OPEN", headRefName: headRef,
            baseRefName: "main", headSha: "abc123", baseSha: "def456", isCrossRepository: false,
            headCloneURL: "https://github.com/acme/shop.git", additions: 1, deletions: 1, changedFiles: 1,
            files: ["a.txt"], commits: commits, comments: [], reviews: [], diff: "diff"
        )
    }

    private func jiraRef(_ ctx: RawPRContext) -> String? {
        JiraTracker().reference(in: ctx)?.id
    }

    func testJiraKeyFoundInTitle() {
        XCTAssertEqual(jiraRef(makeContext(title: "PROJ-40000 fix flaky login redirect")), "PROJ-40000")
    }

    func testJiraKeyFoundInBranchWhenTitleHasNone() {
        let ctx = makeContext(title: "Fix flaky login redirect", headRef: "ABC-1234-fix-redirect")
        XCTAssertEqual(jiraRef(ctx), "ABC-1234")
    }

    func testJiraKeyFoundInCommitMessage() {
        let ctx = makeContext(
            title: "Fix flaky login redirect", headRef: "fix-redirect",
            commits: [CommitInfo(sha: "abc", message: "fix redirect (ABC-9)", author: "x")]
        )
        XCTAssertEqual(jiraRef(ctx), "ABC-9")
    }

    func testNoJiraKeyFound() {
        XCTAssertNil(jiraRef(makeContext(title: "Fix flaky login redirect", body: "no ticket here")))
    }

    func testJiraKeyIgnoresLowercase() {
        XCTAssertNil(jiraRef(makeContext(title: "bump to v1-2 release")))
    }

    func testJiraRefCarriesTrackerIdentity() {
        let ref = JiraTracker().reference(in: makeContext(title: "PROJ-1 do a thing"))
        XCTAssertEqual(ref?.tracker, .jira)
        XCTAssertEqual(ref?.displayKey, "PROJ-1")
    }

    func testFetchRealJiraTicket() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_CONTOUR_INTEGRATION"] == "1",
                           "Set RUN_CONTOUR_INTEGRATION=1 to run this (network + acli call).")
        let key = try XCTUnwrap(ProcessInfo.processInfo.environment["CONTOUR_JIRA_TEST_KEY"],
                                "Set CONTOUR_JIRA_TEST_KEY to a ticket your acli session can read.")
        let ticket = await JiraTracker().fetch(IssueRef(id: key, tracker: .jira))
        let unwrapped = try XCTUnwrap(ticket, "acli fetch failed — check `acli jira auth status`")
        XCTAssertEqual(unwrapped.key, key)
        XCTAssertEqual(unwrapped.kind, .jira)
        XCTAssertFalse(unwrapped.summary.isEmpty)
        XCTAssertFalse(unwrapped.description.isEmpty)
        XCTAssertTrue(unwrapped.url.contains("/browse/\(key)"))
        print("summary:", unwrapped.summary)
        print("description:\n", unwrapped.description)
        print("url:", unwrapped.url)
    }

    func testAnalysisCacheRoundTrip() {
        let cache = AnalysisCache()
        let graph = PRGraph(pr: PRSummary(
            repo: "acme/shop", number: 42, title: "t", author: "a", state: "OPEN",
            branch: "b", baseBranch: "main", headSha: "headsha123", baseSha: "basesha456",
            intent: Statement(text: "intent", provenance: .claim), filesChanged: 1, additions: 1, deletions: 1
        ))
        cache.invalidate(owner: "acme", repo: "shop", number: 42, headSha: "headsha123", baseSha: "basesha456", pipelineVersion: 999)
        XCTAssertNil(cache.load(owner: "acme", repo: "shop", number: 42, headSha: "headsha123", baseSha: "basesha456", pipelineVersion: 999))

        cache.save(owner: "acme", repo: "shop", number: 42, headSha: "headsha123", baseSha: "basesha456", pipelineVersion: 999, graph: graph, diff: "diff text", completedStages: Set(PipelineStage.analysis))
        let loaded = cache.load(owner: "acme", repo: "shop", number: 42, headSha: "headsha123", baseSha: "basesha456", pipelineVersion: 999)
        XCTAssertEqual(loaded?.graph.pr.title, "t")
        XCTAssertEqual(loaded?.diff, "diff text")

        XCTAssertNil(cache.load(owner: "acme", repo: "shop", number: 42, headSha: "headsha123", baseSha: "basesha456", pipelineVersion: 1000))

        cache.invalidate(owner: "acme", repo: "shop", number: 42, headSha: "headsha123", baseSha: "basesha456", pipelineVersion: 999)
        XCTAssertNil(cache.load(owner: "acme", repo: "shop", number: 42, headSha: "headsha123", baseSha: "basesha456", pipelineVersion: 999))
    }

    func testAnalysisCacheIsBypassedInMockMode() {
        let cache = AnalysisCache()
        let key = (owner: "acme", repo: "shop", number: 43, headSha: "headsha789", baseSha: "basesha012", pipelineVersion: 999)
        let graph = PRGraph(pr: PRSummary(
            repo: "acme/shop", number: 43, title: "real", author: "a", state: "OPEN",
            branch: "b", baseBranch: "main", headSha: key.headSha, baseSha: key.baseSha,
            intent: Statement(text: "intent", provenance: .claim), filesChanged: 1, additions: 1, deletions: 0
        ))
        defer { cache.invalidate(owner: key.owner, repo: key.repo, number: key.number, headSha: key.headSha, baseSha: key.baseSha, pipelineVersion: key.pipelineVersion) }

        setenv("CONTOUR_MOCK_ANALYSIS", "1", 1)
        defer { unsetenv("CONTOUR_MOCK_ANALYSIS") }
        cache.save(owner: key.owner, repo: key.repo, number: key.number, headSha: key.headSha, baseSha: key.baseSha, pipelineVersion: key.pipelineVersion, graph: graph, diff: "mock", completedStages: [.decisions])
        unsetenv("CONTOUR_MOCK_ANALYSIS")
        XCTAssertNil(cache.load(owner: key.owner, repo: key.repo, number: key.number, headSha: key.headSha, baseSha: key.baseSha, pipelineVersion: key.pipelineVersion),
                     "a mock run must not write the real cache entry")

        cache.save(owner: key.owner, repo: key.repo, number: key.number, headSha: key.headSha, baseSha: key.baseSha, pipelineVersion: key.pipelineVersion, graph: graph, diff: "real", completedStages: [.decisions])
        setenv("CONTOUR_MOCK_ANALYSIS", "1", 1)
        XCTAssertNil(cache.load(owner: key.owner, repo: key.repo, number: key.number, headSha: key.headSha, baseSha: key.baseSha, pipelineVersion: key.pipelineVersion),
                     "a mock run must show the fixtures, not a real cached analysis")
    }
}
