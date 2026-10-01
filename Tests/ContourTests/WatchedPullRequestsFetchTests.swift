import Foundation
import Testing
import os

@testable import Contour

struct WatchedPullRequestsFetchTests {
    private let repository = WatchedRepository(owner: "acme", name: "api")
    private let moment = Date(timeIntervalSince1970: 1_000_000)

    private let oneRow = """
        [{"number":7,"title":"Seven","url":"https://github.com/acme/api/pull/7",
          "author":{"login":"mwright","is_bot":false},"isDraft":false,"createdAt":"2026-09-25T10:00:00Z"}]
        """

    private func service(
        ghAvailable: Bool = true, runGH: @escaping @Sendable ([String]) async throws -> String
    ) -> WatchedPullRequests {
        let moment = moment
        return WatchedPullRequests(ghAvailable: { ghAvailable }, runGH: runGH, now: { moment })
    }

    @Test func transportFollowsTheAccessModeAndWhetherGHIsInstalled() {
        #expect(WatchedPullRequests.transport(access: .anonymous, ghAvailable: true) == .rest)
        #expect(WatchedPullRequests.transport(access: .anonymous, ghAvailable: false) == .rest)
        #expect(WatchedPullRequests.transport(access: .gh, ghAvailable: true) == .gh)
        #expect(WatchedPullRequests.transport(access: .gh, ghAvailable: false) == nil)
        #expect(WatchedPullRequests.transport(access: .auto, ghAvailable: true) == .gh)
        #expect(WatchedPullRequests.transport(access: .auto, ghAvailable: false) == .rest)
    }

    @Test func ghIsAskedForThirtyOpenPullRequestsInTheRepository() {
        #expect(
            WatchedPullRequests.arguments(for: repository) == [
                "pr", "list", "-R", "acme/api", "--state", "open", "--limit", "30",
                "--json", "number,title,url,author,isDraft,createdAt",
            ])
    }

    @Test func aGHAnswerBecomesAListStampedWithTheFetchTime() async {
        let seen = OSAllocatedUnfairLock<[[String]]>(initialState: [])
        let oneRow = oneRow
        let service = service { arguments in
            seen.withLock { $0.append(arguments) }
            return oneRow
        }
        let result = await service.fetch(repository, access: .gh)
        #expect(seen.withLock { $0 } == [WatchedPullRequests.arguments(for: repository)])
        #expect((try? result.get())?.pullRequests.map(\.number) == [7])
        #expect((try? result.get())?.fetchedAt == moment)
    }

    @Test func ghAccessWithoutGHInstalledIsUnavailableAndRunsNothing() async {
        let service = service(ghAvailable: false) { _ in
            Issue.record("gh must not run")
            return ""
        }
        #expect(await service.fetch(repository, access: .gh) == .failure(.unavailable))
    }

    @Test func aGHAnswerThatIsNotAListIsUnavailable() async {
        let service = service { _ in "not json" }
        #expect(await service.fetch(repository, access: .gh) == .failure(.unavailable))
    }

    @Test func ghNotFindingTheRepositoryIsNotFound() async {
        let service = service { _ in
            throw ProcessError(
                command: "gh pr list", exitCode: 1,
                stderr: "GraphQL: Could not resolve to a Repository with the name 'acme/api'. (repository)")
        }
        #expect(await service.fetch(repository, access: .gh) == .failure(.notFound))
    }

    @Test func ghHittingTheRateLimitIsRateLimited() async {
        let service = service { _ in
            throw ProcessError(command: "gh pr list", exitCode: 1, stderr: "HTTP 403: API rate limit exceeded")
        }
        #expect(await service.fetch(repository, access: .gh) == .failure(.rateLimited(resetAt: nil)))
    }

    @Test func anyOtherGHFailureIsUnavailable() async {
        let service = service { _ in
            throw ProcessError(command: "gh pr list", exitCode: 4, stderr: "gh auth login")
        }
        #expect(await service.fetch(repository, access: .gh) == .failure(.unavailable))
    }

    @Test func serviceErrorsMapOntoFailures() {
        let reset = Date(timeIntervalSince1970: 5)
        #expect(
            WatchedPullRequests.failure(from: GitHubServiceError.privateRepository(owner: "a", repo: "b"))
                == .notFound)
        #expect(
            WatchedPullRequests.failure(from: GitHubServiceError.rateLimited(resetAt: reset))
                == .rateLimited(resetAt: reset))
        #expect(WatchedPullRequests.failure(from: GitHubServiceError.ghUnavailable) == .unavailable)
        #expect(WatchedPullRequests.failure(from: CancellationError()) == .unavailable)
    }

    @Test func theViewerLoginComesFromGHAndIsTrimmed() async {
        let seen = OSAllocatedUnfairLock<[[String]]>(initialState: [])
        let service = service { arguments in
            seen.withLock { $0.append(arguments) }
            return "jstephens\n"
        }
        #expect(await service.viewerLogin(access: .auto) == "jstephens")
        #expect(seen.withLock { $0 } == [["api", "user", "--jq", ".login"]])
    }

    @Test func thereIsNoViewerLoginAnonymouslyOrWhenGHFailsOrAnswersNothing() async {
        let never = service { _ in
            Issue.record("gh must not run")
            return ""
        }
        #expect(await never.viewerLogin(access: .anonymous) == nil)

        let failing = service { _ in throw ProcessError(command: "gh api user", exitCode: 1, stderr: "no") }
        #expect(await failing.viewerLogin(access: .gh) == nil)

        let blank = service { _ in "\n" }
        #expect(await blank.viewerLogin(access: .gh) == nil)
    }

    @Test func aMissingRepositoryIsExplainedAndAnonymousAccessIsToldHowToSignIn() {
        #expect(
            WatchedPullRequests.message(for: .notFound, repository: "acme/api", anonymous: true)
                == "Couldn't list pull requests for acme/api. It's private or doesn't exist. "
                + "Sign in with the GitHub CLI to watch private repositories.")
        #expect(
            WatchedPullRequests.message(for: .notFound, repository: "acme/api", anonymous: false)
                == "Couldn't list pull requests for acme/api. It's private or doesn't exist.")
    }

    @Test func aRateLimitNamesWhenToTryAgainIfGitHubSaid() {
        let reset = Date(timeIntervalSince1970: 1_000_000)
        let time = DateFormatter.localizedString(from: reset, dateStyle: .none, timeStyle: .short)
        #expect(
            WatchedPullRequests.message(
                for: .rateLimited(resetAt: reset), repository: "acme/api", anonymous: true)
                == "Couldn't list pull requests for acme/api. GitHub's anonymous limit is used up. "
                + "Try again after \(time).")
        #expect(
            WatchedPullRequests.message(for: .rateLimited(resetAt: nil), repository: "acme/api", anonymous: false)
                == "Couldn't list pull requests for acme/api. GitHub's rate limit is used up.")
    }

    @Test func anyOtherFailureSaysOnlyWhatCouldNotBeDone() {
        #expect(
            WatchedPullRequests.message(for: .unavailable, repository: "acme/api", anonymous: true)
                == "Couldn't list pull requests for acme/api.")
    }
}

extension AnonymousAPISourceTests {
    private func watchedService() -> WatchedPullRequests {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return WatchedPullRequests(
            ghAvailable: { false },
            runGH: { _ in
                Issue.record("gh must not run")
                return ""
            },
            anonymous: AnonymousAPISource(session: URLSession(configuration: config)),
            now: { Date(timeIntervalSince1970: 1_000_000) })
    }

    private var watchedRepository: WatchedRepository { WatchedRepository(owner: "acme", name: "api") }

    @Test func watchedPullRequestsAreReadFromTheOpenPullsEndpoint() async {
        let seen = OSAllocatedUnfairLock<[String]>(initialState: [])
        MockURLProtocol.handler = { request in
            seen.withLock { $0.append(request.url?.absoluteString ?? "") }
            let body = """
                [{"number":7,"title":"Seven","html_url":"https://github.com/acme/api/pull/7",
                  "user":{"login":"mwright","type":"User"},"draft":false,"created_at":"2026-09-25T10:00:00Z"},
                 {"number":8,"title":"Bump","html_url":"https://github.com/acme/api/pull/8",
                  "user":{"login":"dependabot[bot]","type":"Bot"},"draft":false,
                  "created_at":"2026-09-26T10:00:00Z"}]
                """
            return MockURLProtocol.Canned(status: 200, body: Data(body.utf8))
        }
        defer { MockURLProtocol.handler = nil }

        let result = await watchedService().fetch(watchedRepository, access: .auto)
        #expect((try? result.get())?.pullRequests.map(\.number) == [7])
        #expect(
            seen.withLock { $0 } == [
                "https://api.github.com/repos/acme/api/pulls?state=open&sort=created&direction=desc&per_page=30"
            ])
    }

    @Test func aMissingWatchedRepositoryIsNotFound() async {
        MockURLProtocol.handler = { _ in MockURLProtocol.Canned(status: 404, body: Data("{}".utf8)) }
        defer { MockURLProtocol.handler = nil }
        #expect(await watchedService().fetch(watchedRepository, access: .anonymous) == .failure(.notFound))
    }

    @Test func anExhaustedAnonymousLimitCarriesItsResetTime() async {
        MockURLProtocol.handler = { _ in
            MockURLProtocol.Canned(
                status: 403, headers: ["X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "1700000000"],
                body: Data("{}".utf8))
        }
        defer { MockURLProtocol.handler = nil }
        #expect(
            await watchedService().fetch(watchedRepository, access: .anonymous)
                == .failure(.rateLimited(resetAt: Date(timeIntervalSince1970: 1_700_000_000))))
    }

    @Test func aWatchedAnswerThatIsNotAListIsUnavailable() async {
        MockURLProtocol.handler = { _ in
            MockURLProtocol.Canned(status: 200, body: Data(#"{"message":"odd"}"#.utf8))
        }
        defer { MockURLProtocol.handler = nil }
        #expect(await watchedService().fetch(watchedRepository, access: .anonymous) == .failure(.unavailable))
    }

    @Test func aServerErrorForAWatchedRepositoryIsUnavailable() async {
        MockURLProtocol.handler = { _ in MockURLProtocol.Canned(status: 500, body: Data("boom".utf8)) }
        defer { MockURLProtocol.handler = nil }
        #expect(await watchedService().fetch(watchedRepository, access: .anonymous) == .failure(.unavailable))
    }
}
