import XCTest
@testable import Contour

final class JiraAndCacheTests: XCTestCase {

    private func makeContext(title: String, body: String = "", headRef: String = "main", commits: [CommitInfo] = []) -> RawPRContext {
        RawPRContext(
            url: "https://github.com/acme/shop/pull/1", owner: "acme", repo: "shop", number: 1,
            title: title, body: body, author: "someone", state: "OPEN", headRefName: headRef,
            baseRefName: "main", headSha: "abc123", baseSha: "def456", isCrossRepository: false,
            headCloneURL: "https://github.com/acme/shop.git", additions: 1, deletions: 1, changedFiles: 1,
            files: ["a.txt"], commits: commits, comments: [], reviews: [], diff: "diff"
        )
    }

    func testTicketKeyFoundInTitle() {
        let ctx = makeContext(title: "PROJ-40000 fix flaky login redirect")
        XCTAssertEqual(JiraService.ticketKey(in: ctx), "PROJ-40000")
    }

    func testTicketKeyFoundInBranchWhenTitleHasNone() {
        let ctx = makeContext(title: "Fix flaky login redirect", headRef: "ABC-1234-fix-redirect")
        XCTAssertEqual(JiraService.ticketKey(in: ctx), "ABC-1234")
    }

    func testTicketKeyFoundInCommitMessage() {
        let ctx = makeContext(
            title: "Fix flaky login redirect", headRef: "fix-redirect",
            commits: [CommitInfo(sha: "abc", message: "fix redirect (ABC-9)", author: "x")]
        )
        XCTAssertEqual(JiraService.ticketKey(in: ctx), "ABC-9")
    }

    func testNoTicketKeyFound() {
        let ctx = makeContext(title: "Fix flaky login redirect", body: "no ticket here")
        XCTAssertNil(JiraService.ticketKey(in: ctx))
    }

    func testTicketKeyIgnoresLowercase() {
        // "v1-2" style version strings shouldn't false-positive as ticket keys.
        let ctx = makeContext(title: "bump to v1-2 release")
        XCTAssertNil(JiraService.ticketKey(in: ctx))
    }

    /// Real `acli` call against a real ticket — gated like IntegrationSmokeTests since it
    /// needs network + a working acli auth session. Confirms the ADF description actually
    /// flattens to readable plain text, not just that the regex matches a key.
    func testFetchRealJiraTicket() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_CONTOUR_INTEGRATION"] == "1",
                           "Set RUN_CONTOUR_INTEGRATION=1 to run this (network + acli call).")
        let ticket = await JiraService().fetchTicket(key: "PROJ-40000")
        let unwrapped = try XCTUnwrap(ticket, "acli fetch failed — check `acli auth status`")
        XCTAssertEqual(unwrapped.key, "PROJ-40000")
        XCTAssertFalse(unwrapped.summary.isEmpty)
        XCTAssertFalse(unwrapped.description.isEmpty)
        XCTAssertTrue(unwrapped.url.contains("/browse/PROJ-40000"))
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

        cache.save(owner: "acme", repo: "shop", number: 42, headSha: "headsha123", baseSha: "basesha456", pipelineVersion: 999, graph: graph, diff: "diff text")
        let loaded = cache.load(owner: "acme", repo: "shop", number: 42, headSha: "headsha123", baseSha: "basesha456", pipelineVersion: 999)
        XCTAssertEqual(loaded?.graph.pr.title, "t")
        XCTAssertEqual(loaded?.diff, "diff text")

        // A different pipeline version must miss even for the same SHAs.
        XCTAssertNil(cache.load(owner: "acme", repo: "shop", number: 42, headSha: "headsha123", baseSha: "basesha456", pipelineVersion: 1000))

        cache.invalidate(owner: "acme", repo: "shop", number: 42, headSha: "headsha123", baseSha: "basesha456", pipelineVersion: 999)
        XCTAssertNil(cache.load(owner: "acme", repo: "shop", number: 42, headSha: "headsha123", baseSha: "basesha456", pipelineVersion: 999))
    }
}
