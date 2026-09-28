import Foundation
import Testing
@testable import Contour

/// Routes every request through a canned response keyed by path + Accept header, so
/// `AnonymousAPISource` (injected with a `URLSession` built on this protocol) never
/// touches the network. `.serialized` because `handler` is a process-wide static — safe
/// here since no other suite in this target does networking at all.
final class MockURLProtocol: URLProtocol {
    struct Canned { var status: Int; var headers: [String: String] = [:]; var body: Data }
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> Canned)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: GitHubServiceError.ghUnavailable)
            return
        }
        let canned = handler(request)
        let response = HTTPURLResponse(
            url: request.url!, statusCode: canned.status, httpVersion: "HTTP/1.1", headerFields: canned.headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: canned.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private func json(_ object: Any) -> Data { try! JSONSerialization.data(withJSONObject: object) }

@Suite(.serialized)
struct AnonymousAPISourceTests {

    private func mockSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    /// The full happy path: one PR object, its diff, one page each of files/commits/
    /// comments/reviews, and a CI rollup from check-runs + statuses — everything
    /// `fetchContext` assembles from eight separate GitHub endpoints.
    @Test func fetchContextAssemblesEveryFieldFromTheAPI() async throws {
        let pr: [String: Any] = [
            "title": "Add feature", "state": "closed", "merged": true,
            "head": ["sha": "headsha1", "ref": "feature-branch",
                     "repo": ["owner": ["login": "forker"], "name": "shop"]],
            "base": ["sha": "basesha1", "ref": "main"],
            "user": ["login": "alice"], "body": "PR body text",
            "additions": 10, "deletions": 2, "changed_files": 3,
            "html_url": "https://github.com/acme/shop/pull/5",
            "created_at": "2024-01-01T00:00:00Z",
        ]
        let files: [[String: Any]] = [["filename": "src/a.swift"], ["filename": "src/b.swift"]]
        let commits: [[String: Any]] = [
            ["sha": "c1", "commit": ["message": "msg1", "author": ["name": "Embedded Name"]],
             "author": ["login": "alice"]],
            ["sha": "c2", "commit": ["message": "msg2", "author": ["name": "Embedded Only"]]],
        ]
        let comments: [[String: Any]] = [
            ["body": "Please fix", "user": ["login": "bob"]],
            ["body": "", "user": ["login": "carol"]],
        ]
        let reviews: [[String: Any]] = [
            ["body": "LGTM", "user": ["login": "dave"], "state": "APPROVED"],
            ["body": "", "user": ["login": "erin"], "state": "CHANGES_REQUESTED"],
        ]
        let checkRuns: [String: Any] = ["check_runs": [["status": "completed", "conclusion": "success"]]]
        let statuses: [String: Any] = ["statuses": []]

        // Serialized up front: a closure typed `@Sendable` can't capture `[String: Any]`
        // (it isn't Sendable), but `Data` is.
        let prData = json(pr), filesData = json(files), commitsData = json(commits)
        let commentsData = json(comments), reviewsData = json(reviews)
        let checkRunsData = json(checkRuns), statusesData = json(statuses)

        MockURLProtocol.handler = { request in
            let path = request.url!.path
            let accept = request.value(forHTTPHeaderField: "Accept")
            switch (path, accept) {
            case ("/repos/acme/shop/pulls/5", "application/vnd.github.v3.diff"):
                return .init(status: 200, body: Data("diff --git a/x b/x\n+hi".utf8))
            case ("/repos/acme/shop/pulls/5", _):
                return .init(status: 200, body: prData)
            case ("/repos/acme/shop/pulls/5/files", _):
                return .init(status: 200, body: filesData)
            case ("/repos/acme/shop/pulls/5/commits", _):
                return .init(status: 200, body: commitsData)
            case ("/repos/acme/shop/issues/5/comments", _):
                return .init(status: 200, body: commentsData)
            case ("/repos/acme/shop/pulls/5/reviews", _):
                return .init(status: 200, body: reviewsData)
            case ("/repos/acme/shop/commits/headsha1/check-runs", _):
                return .init(status: 200, body: checkRunsData)
            case ("/repos/acme/shop/commits/headsha1/status", _):
                return .init(status: 200, body: statusesData)
            default:
                return .init(status: 404, body: Data())
            }
        }
        defer { MockURLProtocol.handler = nil }

        let source = AnonymousAPISource(session: mockSession())
        #expect(source.describesItself == "GitHub REST API (anonymous)")
        let context = try await source.fetchContext(prURL: "https://github.com/acme/shop/pull/5")

        #expect(context.owner == "acme" && context.repo == "shop" && context.number == 5)
        #expect(context.title == "Add feature")
        #expect(context.state == "MERGED", "merged:true overrides the raw closed state")
        #expect(context.headSha == "headsha1" && context.baseSha == "basesha1")
        #expect(context.isCrossRepository, "the head repo's owner differs from the base repo's")
        #expect(context.headCloneURL == "https://github.com/forker/shop.git")
        #expect(context.author == "alice")
        #expect(context.files == ["src/a.swift", "src/b.swift"])
        #expect(context.commits.count == 2)
        #expect(context.commits[0].author == "alice", "the GitHub login wins when present")
        #expect(context.commits[1].author == "Embedded Only", "falls back to the embedded commit author")
        #expect(context.comments == ["bob: Please fix"], "an empty-body comment is dropped")
        #expect(context.reviews == ["dave: LGTM"], "an empty-body review is dropped from the text list")
        #expect(context.glance.approvals == 1)
        #expect(context.glance.changesRequested == 1, "tallied by state even though its body was empty")
        #expect(context.glance.checks == .passing)
        #expect(context.diff.contains("+hi"))
    }

    @Test func fetchContextRejectsAURLThatIsntARecognizablePullRequest() async {
        do {
            _ = try await AnonymousAPISource(session: mockSession()).fetchContext(prURL: "https://example.com/nope")
            Issue.record("expected badURL")
        } catch is GitHubServiceError {
            // expected
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    @Test func rateLimitedRespondsDifferentlyFromAPrivateRepository() async throws {
        let source = AnonymousAPISource(session: mockSession())

        MockURLProtocol.handler = { _ in
            .init(status: 403, headers: ["X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "1704067200"], body: Data())
        }
        do {
            _ = try await source.fetchContext(prURL: "https://github.com/acme/shop/pull/5")
            Issue.record("expected rateLimited")
        } catch GitHubServiceError.rateLimited(let resetAt) {
            #expect(resetAt == Date(timeIntervalSince1970: 1_704_067_200))
        } catch { Issue.record("wrong error: \(error)") }

        MockURLProtocol.handler = { _ in .init(status: 403, body: Data()) }
        do {
            _ = try await source.fetchContext(prURL: "https://github.com/acme/shop/pull/5")
            Issue.record("expected privateRepository")
        } catch GitHubServiceError.privateRepository(let owner, let repo) {
            #expect(owner == "acme" && repo == "shop")
        } catch { Issue.record("wrong error: \(error)") }

        MockURLProtocol.handler = { _ in .init(status: 404, body: Data()) }
        do {
            _ = try await source.fetchContext(prURL: "https://github.com/acme/shop/pull/5")
            Issue.record("expected privateRepository (404 reads as private)")
        } catch GitHubServiceError.privateRepository(_, _) {
            // expected
        } catch { Issue.record("wrong error: \(error)") }
        MockURLProtocol.handler = nil
    }

    @Test func aNonObjectResponseBodyIsAMalformedResponse() async {
        MockURLProtocol.handler = { _ in .init(status: 200, body: Data("[1,2,3]".utf8)) }
        defer { MockURLProtocol.handler = nil }
        do {
            _ = try await AnonymousAPISource(session: mockSession()).fetchContext(prURL: "https://github.com/acme/shop/pull/5")
            Issue.record("expected malformedResponse")
        } catch GitHubServiceError.malformedResponse(_) {
            // expected
        } catch { Issue.record("wrong error: \(error)") }
    }

    @Test func fetchIssueReturnsNilWhenTheResponseHasNoTitleAndAValueOtherwise() async {
        let source = AnonymousAPISource(session: mockSession())

        MockURLProtocol.handler = { _ in .init(status: 200, body: Data("{}".utf8)) }
        #expect(await source.fetchIssue(owner: "acme", repo: "shop", number: "42") == nil)

        MockURLProtocol.handler = { _ in
            .init(status: 200, body: try! JSONSerialization.data(withJSONObject: [
                "title": "Bug title", "body": "desc", "html_url": "https://github.com/acme/shop/issues/42",
            ]))
        }
        let issue = await source.fetchIssue(owner: "acme", repo: "shop", number: "42")
        #expect(issue?.title == "Bug title")
        #expect(issue?.body == "desc")
        MockURLProtocol.handler = nil
    }
}
