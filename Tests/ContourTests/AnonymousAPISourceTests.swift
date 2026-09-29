import Foundation
import Testing
import os

@testable import Contour

final class MockURLProtocol: URLProtocol {
    struct Canned {
        var status: Int
        var headers: [String: String] = [:]
        var body: Data
    }
    private static let handlerLock = OSAllocatedUnfairLock<(@Sendable (URLRequest) -> Canned)?>(initialState: nil)
    static var handler: (@Sendable (URLRequest) -> Canned)? {
        get { handlerLock.withLock { $0 } }
        set { handlerLock.withLock { $0 = newValue } }
    }

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

private final class NonHTTPURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = URLResponse(url: request.url!, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
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

    @Test func fetchContextAssemblesEveryFieldFromTheAPI() async throws {
        let pr: [String: Any] = [
            "title": "Add feature", "state": "closed", "merged": true,
            "head": [
                "sha": "headsha1", "ref": "feature-branch",
                "repo": ["owner": ["login": "forker"], "name": "shop"],
            ],
            "base": ["sha": "basesha1", "ref": "main"],
            "user": ["login": "alice"], "body": "PR body text",
            "additions": 10, "deletions": 2, "changed_files": 3,
            "html_url": "https://github.com/acme/shop/pull/5",
            "created_at": "2024-01-01T00:00:00Z",
        ]
        let files: [[String: Any]] = [["filename": "src/a.swift"], ["filename": "src/b.swift"]]
        let commits: [[String: Any]] = [
            [
                "sha": "c1", "commit": ["message": "msg1", "author": ["name": "Embedded Name"]],
                "author": ["login": "alice"],
            ],
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

        let prData = json(pr)
        let filesData = json(files)
        let commitsData = json(commits)
        let commentsData = json(comments)
        let reviewsData = json(reviews)
        let checkRunsData = json(checkRuns)
        let statusesData = json(statuses)

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
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    @Test func rateLimitedRespondsDifferentlyFromAPrivateRepository() async throws {
        let source = AnonymousAPISource(session: mockSession())

        MockURLProtocol.handler = { _ in
            .init(
                status: 403, headers: ["X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "1704067200"], body: Data())
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
        } catch { Issue.record("wrong error: \(error)") }
        MockURLProtocol.handler = nil
    }

    @Test func aNonObjectResponseBodyIsAMalformedResponse() async {
        MockURLProtocol.handler = { _ in .init(status: 200, body: Data("[1,2,3]".utf8)) }
        defer { MockURLProtocol.handler = nil }
        do {
            _ = try await AnonymousAPISource(session: mockSession()).fetchContext(
                prURL: "https://github.com/acme/shop/pull/5")
            Issue.record("expected malformedResponse")
        } catch GitHubServiceError.malformedResponse(_) {
        } catch { Issue.record("wrong error: \(error)") }
    }

    @Test func aWellFormedButIncompletePRObjectIsAMalformedResponse() async {
        MockURLProtocol.handler = { request in
            request.url!.path.hasSuffix("/diff")
                || request.value(forHTTPHeaderField: "Accept") == "application/vnd.github.v3.diff"
                ? .init(status: 200, body: Data())
                : .init(status: 200, body: json(["title": "No head or base"]))
        }
        defer { MockURLProtocol.handler = nil }
        do {
            _ = try await AnonymousAPISource(session: mockSession()).fetchContext(
                prURL: "https://github.com/acme/shop/pull/5")
            Issue.record("expected malformedResponse")
        } catch GitHubServiceError.malformedResponse(_) {
        } catch { Issue.record("wrong error: \(error)") }
    }

    @Test func anUnrecognizedStatusCodeIsAMalformedResponse() async {
        MockURLProtocol.handler = { _ in .init(status: 500, body: Data("server exploded".utf8)) }
        defer { MockURLProtocol.handler = nil }
        do {
            _ = try await AnonymousAPISource(session: mockSession()).fetchContext(
                prURL: "https://github.com/acme/shop/pull/5")
            Issue.record("expected malformedResponse")
        } catch GitHubServiceError.malformedResponse(let detail) {
            #expect(detail.contains("500") && detail.contains("server exploded"))
        } catch { Issue.record("wrong error: \(error)") }
    }

    @Test func aFailingChecksEndpointDegradesToTheOtherOneRatherThanFailingTheFetch() async throws {
        let pr: [String: Any] = [
            "title": "t", "state": "open",
            "head": ["sha": "h", "ref": "f"], "base": ["sha": "b", "ref": "main"],
        ]
        let prData = json(pr)
        let statuses: [String: Any] = ["statuses": [["state": "success"]]]
        let statusesData = json(statuses)
        MockURLProtocol.handler = { request in
            let path = request.url!.path
            let accept = request.value(forHTTPHeaderField: "Accept")
            if accept == "application/vnd.github.v3.diff" { return .init(status: 200, body: Data()) }
            if path.hasSuffix("/check-runs") { return .init(status: 500, body: Data()) }
            if path.hasSuffix("/status") { return .init(status: 200, body: statusesData) }
            if path == "/repos/acme/shop/pulls/5" { return .init(status: 200, body: prData) }
            return .init(status: 200, body: json([[String: Any]]()))
        }
        defer { MockURLProtocol.handler = nil }
        let context = try await AnonymousAPISource(session: mockSession()).fetchContext(
            prURL: "https://github.com/acme/shop/pull/5")
        #expect(
            context.glance.checks == .passing,
            "the failing check-runs call is swallowed; the status call alone still rolls up")
    }

    @Test func paginationWalksToASecondPageWhenTheFirstIsFull() async throws {
        let pr: [String: Any] = [
            "title": "t", "state": "open",
            "head": ["sha": "h", "ref": "f"], "base": ["sha": "b", "ref": "main"],
        ]
        let prData = json(pr)
        let fullPage = json((1...100).map { ["filename": "file\($0).swift"] })
        let secondPage = json([["filename": "file101.swift"]])
        MockURLProtocol.handler = { request in
            let path = request.url!.path
            let accept = request.value(forHTTPHeaderField: "Accept")
            if accept == "application/vnd.github.v3.diff" { return .init(status: 200, body: Data()) }
            if path == "/repos/acme/shop/pulls/5" { return .init(status: 200, body: prData) }
            if path == "/repos/acme/shop/pulls/5/files" {
                let page = request.url!.query?.contains("page=2") == true
                return .init(status: 200, body: page ? secondPage : fullPage)
            }
            return .init(status: 200, body: json([[String: Any]]()))
        }
        defer { MockURLProtocol.handler = nil }
        let context = try await AnonymousAPISource(session: mockSession()).fetchContext(
            prURL: "https://github.com/acme/shop/pull/5")
        #expect(context.files.count == 101, "a full first page (100) must fetch page 2 for the 101st file")
    }

    @Test func fetchIssueReturnsNilWhenTheResponseHasNoTitleAndAValueOtherwise() async {
        let source = AnonymousAPISource(session: mockSession())

        MockURLProtocol.handler = { _ in .init(status: 200, body: Data("{}".utf8)) }
        #expect(await source.fetchIssue(owner: "acme", repo: "shop", number: "42") == nil)

        MockURLProtocol.handler = { _ in
            .init(
                status: 200,
                body: try! JSONSerialization.data(withJSONObject: [
                    "title": "Bug title", "body": "desc", "html_url": "https://github.com/acme/shop/issues/42",
                ]))
        }
        let issue = await source.fetchIssue(owner: "acme", repo: "shop", number: "42")
        #expect(issue?.title == "Bug title")
        #expect(issue?.body == "desc")
        MockURLProtocol.handler = nil
    }

    private func minimalPR() -> Data {
        json([
            "title": "t", "state": "open",
            "head": ["sha": "h", "ref": "f"], "base": ["sha": "b", "ref": "main"],
        ])
    }

    private func utf16JSON(_ object: Any) -> Data {
        let text = String(data: json(object), encoding: .utf8)!
        return text.data(using: .utf16)!
    }

    private func fetchMinimal(
        overrides: @escaping @Sendable (URLRequest) -> MockURLProtocol.Canned?
    ) async throws -> RawPRContext {
        let prData = minimalPR()
        MockURLProtocol.handler = { request in
            if let canned = overrides(request) { return canned }
            if request.value(forHTTPHeaderField: "Accept") == "application/vnd.github.v3.diff" {
                return .init(status: 200, body: Data())
            }
            if request.url!.path == "/repos/acme/shop/pulls/5" { return .init(status: 200, body: prData) }
            return .init(status: 200, body: json([[String: Any]]()))
        }
        defer { MockURLProtocol.handler = nil }
        return try await AnonymousAPISource(session: mockSession()).fetchContext(
            prURL: "https://github.com/acme/shop/pull/5")
    }

    @Test func missingOptionalFieldsFallBackToPlaceholders() async throws {
        let commitsData = json([["sha": "c1"]])
        let commentsData = json([["body": "anonymous note"]])
        let reviewsData = json([["body": "anonymous review", "state": "COMMENTED"]])
        let context = try await fetchMinimal { request in
            switch request.url!.path {
            case "/repos/acme/shop/pulls/5/commits": return .init(status: 200, body: commitsData)
            case "/repos/acme/shop/issues/5/comments": return .init(status: 200, body: commentsData)
            case "/repos/acme/shop/pulls/5/reviews": return .init(status: 200, body: reviewsData)
            default: return nil
            }
        }
        #expect(context.commits.count == 1)
        #expect(context.commits.first?.sha == "c1")
        #expect(context.commits.first?.message == "")
        #expect(context.commits.first?.author == "unknown")
        #expect(context.comments == ["someone: anonymous note"])
        #expect(context.reviews == ["someone: anonymous review"])
        #expect(context.author == "unknown")
        #expect(context.body == "")
        #expect(context.url == "https://github.com/acme/shop/pull/5")
    }

    @Test func fetchIssueFillsInABodyAndURLWhenTheResponseOmitsThem() async {
        MockURLProtocol.handler = { _ in .init(status: 200, body: json(["title": "Only a title"])) }
        defer { MockURLProtocol.handler = nil }
        let issue = await AnonymousAPISource(session: mockSession()).fetchIssue(
            owner: "acme", repo: "shop", number: "42")
        #expect(issue?.title == "Only a title")
        #expect(issue?.body == "")
        #expect(issue?.url == "https://github.com/acme/shop/issues/42")
    }

    @Test func aNonUTF8ErrorBodyStillProducesAMalformedResponse() async {
        MockURLProtocol.handler = { _ in .init(status: 500, body: Data([0xFF, 0xFE, 0xFD])) }
        defer { MockURLProtocol.handler = nil }
        do {
            _ = try await AnonymousAPISource(session: mockSession()).fetchContext(
                prURL: "https://github.com/acme/shop/pull/5")
            Issue.record("expected malformedResponse")
        } catch GitHubServiceError.malformedResponse(let detail) {
            #expect(detail.hasPrefix("HTTP 500"))
        } catch { Issue.record("wrong error: \(error)") }
    }

    @Test func aNonUTF8ObjectResponseThatIsNotAnObjectIsAMalformedResponse() async {
        let body = utf16JSON([1, 2, 3])
        MockURLProtocol.handler = { _ in .init(status: 200, body: body) }
        defer { MockURLProtocol.handler = nil }
        do {
            _ = try await AnonymousAPISource(session: mockSession()).fetchContext(
                prURL: "https://github.com/acme/shop/pull/5")
            Issue.record("expected malformedResponse")
        } catch GitHubServiceError.malformedResponse(let detail) {
            #expect(detail.isEmpty)
        } catch { Issue.record("wrong error: \(error)") }
    }

    @Test func anArrayEndpointReturningAnObjectIsAMalformedResponse() async {
        let objectBody = json(["message": "not an array"])
        let utf16Body = utf16JSON(["message": "not an array"])
        for body in [objectBody, utf16Body] {
            do {
                _ = try await fetchMinimal { request in
                    request.url!.path == "/repos/acme/shop/pulls/5/files" ? .init(status: 200, body: body) : nil
                }
                Issue.record("expected malformedResponse")
            } catch GitHubServiceError.malformedResponse(_) {
            } catch { Issue.record("wrong error: \(error)") }
        }
    }

    @Test func aNonUTF8DiffBodyDegradesToAnEmptyDiff() async throws {
        let context = try await fetchMinimal { request in
            request.value(forHTTPHeaderField: "Accept") == "application/vnd.github.v3.diff"
                ? .init(status: 200, body: Data([0xFF, 0xFE, 0xFD])) : nil
        }
        #expect(context.diff == "")
    }

    @Test func aNonHTTPResponseIsAMalformedResponse() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [NonHTTPURLProtocol.self]
        do {
            _ = try await AnonymousAPISource(session: URLSession(configuration: config)).fetchContext(
                prURL: "https://github.com/acme/shop/pull/5")
            Issue.record("expected malformedResponse")
        } catch GitHubServiceError.malformedResponse(let detail) {
            #expect(detail == "non-HTTP response")
        } catch { Issue.record("wrong error: \(error)") }
    }

    @Test func aRateLimitResponseWithoutAResetHeaderHasNoResetDate() async {
        MockURLProtocol.handler = { _ in .init(status: 429, headers: ["X-RateLimit-Remaining": "0"], body: Data()) }
        defer { MockURLProtocol.handler = nil }
        do {
            _ = try await AnonymousAPISource(session: mockSession()).fetchContext(
                prURL: "https://github.com/acme/shop/pull/5")
            Issue.record("expected rateLimited")
        } catch GitHubServiceError.rateLimited(let resetAt) {
            #expect(resetAt == nil)
        } catch { Issue.record("wrong error: \(error)") }
    }
}
