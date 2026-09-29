import Foundation
import Testing

@testable import Contour

struct GHCLISourceTests {
    private func json(_ object: Any) -> String {
        String(data: try! JSONSerialization.data(withJSONObject: object), encoding: .utf8)!
    }

    private func fullPRView(overrides: [String: Any] = [:], removing: Set<String> = []) -> [String: Any] {
        var obj: [String: Any] = [
            "url": "https://github.com/acme/shop/pull/5", "number": 5, "title": "Add feature",
            "body": "PR body", "author": ["login": "alice"], "state": "OPEN",
            "headRefName": "feature", "baseRefName": "main",
            "headRefOid": "headsha1", "baseRefOid": "basesha1",
            "isCrossRepository": true,
            "headRepository": ["name": "shop"],
            "headRepositoryOwner": ["login": "forker"],
            "additions": 10, "deletions": 2, "changedFiles": 3,
            "files": [["path": "src/a.swift"], ["path": "src/b.swift"]],
            "commits": [
                [
                    "oid": "c1", "messageHeadline": "msg1", "messageBody": "",
                    "authors": [["login": "alice"]],
                ],
                [
                    "oid": "c2", "messageHeadline": "msg2", "messageBody": "details",
                    "authors": [],
                ],
            ],
            "comments": [
                ["body": "Please fix", "author": ["login": "bob"]],
                ["body": "", "author": ["login": "carol"]],
            ],
            "reviews": [
                ["body": "LGTM", "author": ["login": "dave"], "state": "APPROVED"],
                ["body": "", "author": ["login": "erin"], "state": "CHANGES_REQUESTED"],
            ],
            "createdAt": "2024-01-01T00:00:00Z",
            "statusCheckRollup": [["status": "COMPLETED", "conclusion": "SUCCESS"]],
        ]
        for (key, value) in overrides { obj[key] = value }
        for key in removing { obj.removeValue(forKey: key) }
        return obj
    }

    @Test func parsePRViewExtractsEveryRequiredFieldAndDerivesOwnerRepoFromTheURL() throws {
        let parsed = try GHCLISource.parsePRView(json: json(fullPRView()))
        #expect(parsed.url == "https://github.com/acme/shop/pull/5")
        #expect(parsed.number == 5)
        #expect(parsed.title == "Add feature")
        #expect(parsed.author == "alice")
        #expect(parsed.state == "OPEN")
        #expect(parsed.headRefName == "feature" && parsed.baseRefName == "main")
        #expect(parsed.headSha == "headsha1" && parsed.baseSha == "basesha1")
        #expect(parsed.owner == "acme" && parsed.repo == "shop")
    }

    @Test func parsePRViewRejectsNonObjectJSON() {
        #expect(throws: GitHubServiceError.self) {
            try GHCLISource.parsePRView(json: "[1,2,3]")
        }
    }

    @Test func parsePRViewRejectsMissingRequiredFields() {
        for key in [
            "url", "number", "title", "author", "state", "headRefName", "baseRefName", "headRefOid", "baseRefOid",
        ] {
            let payload = json(fullPRView(removing: [key]))
            #expect(throws: GitHubServiceError.self, "missing \(key) should be rejected") {
                try GHCLISource.parsePRView(json: payload)
            }
        }
    }

    @Test func parsePRViewRejectsAnAuthorWithNoLogin() {
        let payload = json(fullPRView(overrides: ["author": [:]]))
        #expect(throws: GitHubServiceError.self) {
            try GHCLISource.parsePRView(json: payload)
        }
    }

    @Test func assembleContextFillsInEveryFieldFromTheParsedView() throws {
        let parsed = try GHCLISource.parsePRView(json: json(fullPRView()))
        let context = GHCLISource.assembleContext(parsed: parsed, diff: "diff --git a/x b/x\n+hi", unresolvedThreads: 2)

        #expect(context.owner == "acme" && context.repo == "shop" && context.number == 5)
        #expect(context.body == "PR body")
        #expect(context.isCrossRepository, "isCrossRepository:true in the payload")
        #expect(context.headCloneURL == "https://github.com/forker/shop.git", "fork-aware clone URL")
        #expect(context.additions == 10 && context.deletions == 2 && context.changedFiles == 3)
        #expect(context.files == ["src/a.swift", "src/b.swift"])
        #expect(context.diff.contains("+hi"))
        #expect(context.glance.unresolvedThreads == 2)

        #expect(context.commits.count == 2)
        #expect(context.commits[0].author == "alice")
        #expect(context.commits[0].message == "msg1", "empty messageBody falls back to the headline alone")
        #expect(context.commits[1].author == "unknown", "no authors on the commit falls back to \"unknown\"")
        #expect(context.commits[1].message == "msg2\ndetails", "a non-empty messageBody is appended to the headline")

        #expect(context.comments == ["bob: Please fix"], "an empty-body comment is dropped")
        #expect(context.reviews == ["dave: LGTM"], "an empty-body review is dropped from the text list")
        #expect(context.glance.approvals == 1)
        #expect(context.glance.changesRequested == 1, "tallied by state even though its body was empty")
        #expect(context.glance.checks == .passing)
        #expect(context.glance.createdAt == Date(timeIntervalSince1970: 1_704_067_200))
    }

    @Test func assembleContextDefaultsOptionalFieldsWhenAbsent() throws {
        let minimal: [String: Any] = [
            "url": "https://github.com/acme/shop/pull/5", "number": 5, "title": "t",
            "author": ["login": "alice"], "state": "OPEN",
            "headRefName": "feature", "baseRefName": "main",
            "headRefOid": "h", "baseRefOid": "b",
        ]
        let parsed = try GHCLISource.parsePRView(json: json(minimal))
        let context = GHCLISource.assembleContext(parsed: parsed, diff: "", unresolvedThreads: nil)

        #expect(context.body.isEmpty)
        #expect(!context.isCrossRepository)
        #expect(context.additions == 0 && context.deletions == 0 && context.changedFiles == 0)
        #expect(context.files.isEmpty)
        #expect(context.commits.isEmpty)
        #expect(context.comments.isEmpty)
        #expect(context.reviews.isEmpty)
        #expect(
            context.headCloneURL == "https://github.com/acme/shop.git",
            "falls back to the base owner/repo when no headRepository")
        #expect(context.glance.checks == nil, "no statusCheckRollup means no CI to report")
        #expect(context.glance.unresolvedThreads == nil)
        #expect(context.glance.createdAt == nil)
    }

    @Test func graphQLArgsOmitsHostnameForGitHubDotCom() {
        let args = GHCLISource.graphQLArgs(
            query: "q", owner: "acme", repo: "shop", number: 5, prURL: "https://github.com/acme/shop/pull/5"
        )
        #expect(!args.contains("--hostname"))
        #expect(args.contains("owner=acme"))
    }

    @Test func graphQLArgsNamesTheHostnameForGitHubEnterprise() {
        let args = GHCLISource.graphQLArgs(
            query: "q", owner: "acme", repo: "shop", number: 5, prURL: "https://ghe.internal/acme/shop/pull/5"
        )
        #expect(args.contains("--hostname"))
        #expect(args.contains("ghe.internal"))
    }

    @Test func parseUnresolvedThreadCountCountsOnlyThreadsThatArentResolved() {
        let payload: [String: Any] = [
            "data": [
                "repository": [
                    "pullRequest": [
                        "reviewThreads": [
                            "nodes": [
                                ["isResolved": true], ["isResolved": false], ["isResolved": false],
                            ]
                        ]
                    ]
                ]
            ]
        ]
        #expect(GHCLISource.parseUnresolvedThreadCount(json: json(payload)) == 2)
    }

    @Test func parseUnresolvedThreadCountIsNilOnAnUnexpectedShape() {
        #expect(GHCLISource.parseUnresolvedThreadCount(json: "{}") == nil)
        #expect(GHCLISource.parseUnresolvedThreadCount(json: "not json") == nil)
    }

    @Test func parseIssueReturnsTitleBodyAndURL() {
        let payload: [String: Any] = ["title": "Bug", "body": "desc", "url": "https://github.com/acme/shop/issues/42"]
        let issue = GHCLISource.parseIssue(json: json(payload), owner: "acme", repo: "shop", number: "42")
        #expect(issue?.title == "Bug")
        #expect(issue?.body == "desc")
        #expect(issue?.url == "https://github.com/acme/shop/issues/42")
    }

    @Test func parseIssueFallsBackToAConstructedURLWhenAbsent() {
        let payload: [String: Any] = ["title": "Bug"]
        let issue = GHCLISource.parseIssue(json: json(payload), owner: "acme", repo: "shop", number: "42")
        #expect(issue?.body.isEmpty == true)
        #expect(issue?.url == "https://github.com/acme/shop/issues/42")
    }

    @Test func parseIssueIsNilWithoutATitle() {
        #expect(GHCLISource.parseIssue(json: "{}", owner: "acme", repo: "shop", number: "42") == nil)
        #expect(GHCLISource.parseIssue(json: "not json", owner: "acme", repo: "shop", number: "42") == nil)
    }

    @Test func describesItselfIsGHCLI() {
        #expect(GHCLISource().describesItself == "gh CLI")
    }

    @Test func assembleContextDropsMalformedEntriesAndAppliesFallbacks() throws {
        let payload: [String: Any] = [
            "url": "https://github.com/acme/shop/pull/5", "number": 5, "title": "t",
            "author": ["login": "alice"], "state": "OPEN",
            "headRefName": "feature", "baseRefName": "main",
            "headRefOid": "h", "baseRefOid": "b",
            "files": [["path": "keep.swift"], ["notPath": "drop.swift"]],
            "commits": [
                ["oid": "c1", "authors": [["notLogin": "x"]]],
                ["messageHeadline": "no oid, dropped entirely"],
            ],
            "comments": [["body": "no author here"]],
            "reviews": [
                ["body": "no state", "author": ["login": "grace"]],
                ["body": "no author", "state": "APPROVED"],
            ],
        ]
        let parsed = try GHCLISource.parsePRView(json: json(payload))
        let context = GHCLISource.assembleContext(parsed: parsed, diff: "", unresolvedThreads: nil)

        #expect(context.files == ["keep.swift"], "the pathless file entry is dropped")

        #expect(context.commits.count == 1, "the oid-less commit is dropped entirely")
        #expect(context.commits[0].sha == "c1")
        #expect(context.commits[0].message == "", "no messageHeadline or messageBody: both default to empty")
        #expect(context.commits[0].author == "unknown", "the only author entry has no login, so it's filtered out")

        #expect(context.comments == ["someone: no author here"], "missing author falls back to \"someone\"")
        #expect(
            context.reviews == ["grace: no state", "someone: no author"],
            "a non-empty body keeps a review in the text list even without state or author"
        )
        #expect(
            context.glance.approvals == 0 && context.glance.changesRequested == 0,
            "neither review has both an author login and a state, so the tally counts neither")
    }

    @Test func fetchContextRejectsANonPRURLWithoutShellingOut() async {
        await #expect(throws: GitHubServiceError.self) {
            try await GHCLISource().fetchContext(prURL: "not a github pr url")
        }
    }

    @Test func fetchContextReachesTheRealGHForAWellFormedPRURL() async {
        do {
            let context = try await GHCLISource().fetchContext(prURL: "https://github.com/cli/cli/pull/1")
            #expect(context.number == 1, "gh answered: the well-known PR's number should come back unchanged")
        } catch {
        }
    }

    @Test func fetchIssueReachesTheRealGHForAWellFormedIssue() async {
        let issue = await GHCLISource().fetchIssue(owner: "cli", repo: "cli", number: "1")
        if let issue {
            #expect(!issue.title.isEmpty, "gh answered: a real issue always has a title")
        }
    }
}
