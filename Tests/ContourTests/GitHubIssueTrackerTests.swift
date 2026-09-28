import Testing
import Foundation
@testable import Contour

/// Issue-reference detection, which is the part of the default tracker most likely to be
/// quietly wrong: it runs against prose people write by hand, and a false positive sends
/// the ELI5 stage off to ground itself in the wrong issue.
struct GitHubIssueTrackerTests {

    /// Never contacted — every test here is about `reference(in:)`, which is pure.
    private struct UnusedSource: PRSource {
        var describesItself: String { "unused" }
        func fetchContext(prURL: String) async throws -> RawPRContext { fatalError("not used") }
        func fetchIssue(owner: String, repo: String, number: String) async -> RawIssue? { nil }
    }

    private func context(
        title: String = "Some change",
        body: String = "",
        headRef: String = "feature",
        commits: [String] = [],
        owner: String = "acme",
        repo: String = "shop"
    ) -> RawPRContext {
        RawPRContext(
            url: "https://github.com/\(owner)/\(repo)/pull/1", owner: owner, repo: repo, number: 1,
            title: title, body: body, author: "someone", state: "OPEN", headRefName: headRef,
            baseRefName: "main", headSha: "abc123", baseSha: "def456", isCrossRepository: false,
            headCloneURL: "https://github.com/\(owner)/\(repo).git",
            additions: 1, deletions: 1, changedFiles: 1, files: ["a.txt"],
            commits: commits.map { CommitInfo(sha: "s", message: $0, author: "x") },
            comments: [], reviews: [], diff: "diff"
        )
    }

    private func ref(_ ctx: RawPRContext) -> IssueRef? {
        GitHubIssueTracker(source: UnusedSource()).scoped(to: ctx).reference(in: ctx)
    }

    // MARK: - Closing keywords

    @Test(arguments: [
        "Fixes #123", "fixes #123", "FIXES #123", "Fixed #123", "Fix #123",
        "Closes #123", "closed #123", "close #123",
        "Resolves #123", "resolve #123", "resolved #123",
        "Fixes: #123", "Fixes  #123",
        "This one fixes #123 at last.",
        "Fixes GH-123",
    ])
    func closingKeywordsAreRecognized(phrase: String) {
        #expect(ref(context(body: phrase))?.id == "123")
    }

    @Test func closingKeywordInTitleIsFound() {
        #expect(ref(context(title: "Add retry, fixes #7"))?.id == "7")
    }

    @Test func closingKeywordInCommitMessageIsFound() {
        #expect(ref(context(commits: ["rework the queue\n\nCloses #4821"]))?.id == "4821")
    }

    /// The body is GitHub's own home for "Closes #N", so it wins over a number that merely
    /// appears in the title.
    @Test func bodyClosingKeywordBeatsTitleMention() {
        let ctx = context(title: "Follow-up to #100", body: "Fixes #200")
        #expect(ref(ctx)?.id == "200")
    }

    /// An explicit closing keyword anywhere beats a bare mention anywhere, because it
    /// states intent rather than just referring to something.
    @Test func closingKeywordBeatsBareMentionInEarlierField() {
        let ctx = context(title: "See #11 for background", body: "Resolves #22")
        #expect(ref(ctx)?.id == "22")
    }

    // MARK: - Bare and cross-repo references

    @Test func bareReferenceIsFoundWhenNoKeywordExists() {
        #expect(ref(context(body: "Related to #99"))?.id == "99")
    }

    @Test func crossRepoReferenceRecordsItsRepo() {
        let r = ref(context(body: "Fixes other-org/other-repo#55"))
        #expect(r?.id == "55")
        #expect(r?.owner == "other-org")
        #expect(r?.repo == "other-repo")
        #expect(r?.displayKey == "other-org/other-repo#55")
    }

    /// A reference that names the PR's own repo is the same thing as a bare `#N`, and
    /// should render as one.
    @Test func sameRepoQualifierIsNormalizedAway() {
        let r = ref(context(body: "Fixes acme/shop#55", owner: "acme", repo: "shop"))
        #expect(r?.id == "55")
        #expect(r?.owner == nil)
        #expect(r?.displayKey == "#55")
    }

    // MARK: - Branch names

    @Test(arguments: [
        "123-add-retry", "feature/123-add-retry", "gh-123", "issue-123",
        "alice/gh-123/fix", "fix/123",
    ])
    func branchNamesYieldTheirIssueNumber(branch: String) {
        #expect(ref(context(headRef: branch))?.id == "123")
    }

    /// Branch names are the weakest signal, so anything explicit in prose outranks them.
    @Test func proseBeatsBranchName() {
        #expect(ref(context(body: "Fixes #500", headRef: "123-add-retry"))?.id == "500")
    }

    // MARK: - Non-matches

    @Test(arguments: [
        "No issue here at all",
        "Bump version to 1.2.3",
        "Use the #hashtag style",       // '#' followed by letters, not digits
        "Refs C++ issue numbering",
    ])
    func proseWithoutAReferenceYieldsNothing(body: String) {
        #expect(ref(context(body: body, headRef: "no-numbers-here")) == nil)
    }

    @Test func emptyContextYieldsNothing() {
        #expect(ref(context(headRef: "main")) == nil)
    }

    /// A Jira-style key is not a GitHub issue. The GitHub tracker must not claim it, or
    /// selecting GitHub would silently swallow references meant for Jira.
    @Test func jiraKeysAreNotTreatedAsGitHubIssues() {
        #expect(ref(context(title: "PROJ-1234 fix the thing", headRef: "proj-fix")) == nil)
    }

    // MARK: - fetch(_:)

    private struct CannedSource: PRSource {
        var issue: RawIssue?
        var describesItself: String { "canned" }
        func fetchContext(prURL: String) async throws -> RawPRContext { fatalError("not used") }
        func fetchIssue(owner: String, repo: String, number: String) async -> RawIssue? { issue }
    }

    @Test func fetchUsesTheRefsOwnOwnerAndRepoWhenPresent() async {
        let source = CannedSource(issue: RawIssue(title: "Bug", body: "desc", url: "https://github.com/other-org/other-repo/issues/55"))
        let tracker = GitHubIssueTracker(source: source, currentOwner: "acme", currentRepo: "shop")
        let ref = IssueRef(id: "55", tracker: .github, owner: "other-org", repo: "other-repo")

        let ticket = await tracker.fetch(ref)
        #expect(ticket?.kind == .github)
        #expect(ticket?.key == "other-org/other-repo#55")
        #expect(ticket?.summary == "Bug")
        #expect(ticket?.description == "desc")
        #expect(ticket?.url == "https://github.com/other-org/other-repo/issues/55")
    }

    @Test func fetchFallsBackToTheCurrentRepoWhenTheRefHasNone() async {
        let source = CannedSource(issue: RawIssue(title: "Same-repo bug", body: "d", url: "u"))
        let tracker = GitHubIssueTracker(source: source, currentOwner: "acme", currentRepo: "shop")
        let ticket = await tracker.fetch(IssueRef(id: "9", tracker: .github))
        #expect(ticket?.summary == "Same-repo bug")
        #expect(ticket?.key == "#9", "no owner/repo on the ref, so the display key stays bare")
    }

    @Test func fetchReturnsNilWithNoRepoToLookIn() async {
        let tracker = GitHubIssueTracker(source: CannedSource(issue: nil))
        let ticket = await tracker.fetch(IssueRef(id: "9", tracker: .github))
        #expect(ticket == nil)
    }

    @Test func fetchReturnsNilWhenTheSourceCantFindTheIssue() async {
        let tracker = GitHubIssueTracker(source: CannedSource(issue: nil), currentOwner: "acme", currentRepo: "shop")
        let ticket = await tracker.fetch(IssueRef(id: "9", tracker: .github))
        #expect(ticket == nil)
    }

    @Test func trackerIDIsGitHub() {
        #expect(GitHubIssueTracker(source: CannedSource(issue: nil)).id == .github)
    }
}
