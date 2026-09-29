import Foundation
import Testing

@testable import Contour

struct PRSourceTests {
    @Test func normalizeAcceptsAnyStringContainingAPullURL() {
        #expect(GitHubService.normalize("https://github.com/acme/shop/pull/5") != nil)
        #expect(
            GitHubService.normalize("  https://github.com/acme/shop/pull/5  ") == "https://github.com/acme/shop/pull/5",
            "trims whitespace")
    }

    @Test func normalizeRejectsAnythingMissingGithubOrPull() {
        #expect(GitHubService.normalize("not a url") == nil)
        #expect(GitHubService.normalize("https://github.com/acme/shop") == nil, "no /pull/")
        #expect(GitHubService.normalize("https://example.com/acme/shop/pull/5") == nil, "not github.com")
    }

    @Test func parseSplitsAValidPullURLIntoItsParts() throws {
        let parsed = try GitHubService.parse(prURL: "https://github.com/acme/shop/pull/42")
        #expect(parsed.owner == "acme" && parsed.repo == "shop" && parsed.number == 42)
    }

    @Test func parseTrimsWhitespaceBeforeParsing() throws {
        let parsed = try GitHubService.parse(prURL: "  https://github.com/acme/shop/pull/42  ")
        #expect(parsed.number == 42)
    }

    @Test func parseRejectsAnythingThatIsntAFourSegmentPullURL() {
        for bad in [
            "not a url", "https://github.com/acme/shop", "https://github.com/acme/shop/issues/5",
            "https://github.com/acme/shop/pull/notanumber",
        ] {
            #expect(throws: GitHubServiceError.self, "\(bad) should be rejected") {
                try GitHubService.parse(prURL: bad)
            }
        }
    }

    @Test func ownerRepoExtractsTheFirstTwoPathComponents() throws {
        let (owner, repo) = try GitHubService.ownerRepo(fromCanonicalURL: "https://github.com/acme/shop/pull/5")
        #expect(owner == "acme" && repo == "shop")
    }

    @Test func ownerRepoRejectsAURLWithTooFewPathComponents() {
        #expect(throws: GitHubServiceError.self) {
            try GitHubService.ownerRepo(fromCanonicalURL: "https://github.com/acme")
        }
    }

    @Test func everyErrorCaseHasAReviewerFacingDescription() {
        #expect(GitHubServiceError.badURL("x").errorDescription?.contains("x") == true)
        #expect(GitHubServiceError.malformedResponse("raw json").errorDescription?.contains("raw json") == true)

        let privateRepo = GitHubServiceError.privateRepository(owner: "acme", repo: "shop")
        #expect(privateRepo.errorDescription?.contains("acme/shop") == true)
        #expect(privateRepo.errorDescription?.contains("gh auth login") == true)

        #expect(GitHubServiceError.rateLimited(resetAt: nil).errorDescription?.contains("60 requests/hour") == true)
        let resetAt = GitHubServiceError.rateLimited(resetAt: Date(timeIntervalSince1970: 1_704_067_200))
        #expect(resetAt.errorDescription?.contains("Try again after") == true)

        #expect(GitHubServiceError.ghUnavailable.errorDescription?.contains("GitHub CLI") == true)
    }

    @Test func ghModeThrowsWhenGHIsUnavailable() {
        let service = GitHubService(mode: .gh, ghAvailable: false)
        do {
            _ = try service.source()
            Issue.record("expected ghUnavailable")
        } catch GitHubServiceError.ghUnavailable {
        } catch { Issue.record("wrong error: \(error)") }
    }

    @Test func ghModeUsesGHCLIWhenAvailable() throws {
        let service = GitHubService(mode: .gh, ghAvailable: true)
        #expect(try service.source().describesItself == "gh CLI")
    }

    @Test func anonymousModeAlwaysUsesTheRESTAPIRegardlessOfGH() throws {
        #expect(
            try GitHubService(mode: .anonymous, ghAvailable: true).source().describesItself
                == "GitHub REST API (anonymous)")
        #expect(
            try GitHubService(mode: .anonymous, ghAvailable: false).source().describesItself
                == "GitHub REST API (anonymous)")
    }

    @Test func autoModePrefersGHWhenAvailableAndFallsBackOtherwise() throws {
        #expect(try GitHubService(mode: .auto, ghAvailable: true).source().describesItself == "gh CLI")
        #expect(
            try GitHubService(mode: .auto, ghAvailable: false).source().describesItself == "GitHub REST API (anonymous)"
        )
    }
}
