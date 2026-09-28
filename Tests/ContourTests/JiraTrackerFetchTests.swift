import Testing
@testable import Contour

/// `JiraTracker.swift` was at 55.32% coverage after `JiraADFTests` covered `flattenADF`
/// (#156): the rest of the gap was `fetchTicket`'s request-building and response-parsing,
/// all reached only via `Shell.run("acli", ...)`. Per `GHCLISource`'s precedent for the
/// same problem, `parseWorkItemJSON`, `parseSiteHost(fromAuthStatusOutput:)`, and
/// `browseURL` were pulled out of `fetchTicket`/`authenticatedSiteHost`/`browseURL` as
/// static functions taking plain strings, so they're testable against fixture text
/// instead of a real `acli` call. Only the two `Shell.run` call sites themselves (and the
/// thin `fetchTicket`/`fetch` wrappers around them) stay uncovered here, matching this
/// suite's sibling `JiraADFTests` and `GHCLISourceTests`.
struct JiraTrackerFetchTests {

    // MARK: - parseWorkItemJSON

    @Test func parseWorkItemJSONExtractsSummaryDescriptionAndSelfLink() {
        let json = """
        {
            "self": "https://jira-prod-us-28-1.prod.atl-paas.net/rest/api/2/issue/10001",
            "fields": {
                "summary": "Fix flaky login redirect",
                "description": {
                    "type": "doc",
                    "content": [
                        {"type": "paragraph", "content": [{"type": "text", "text": "Users see a blank page."}]}
                    ]
                }
            }
        }
        """
        let parsed = JiraTracker.parseWorkItemJSON(json)
        #expect(parsed?.summary == "Fix flaky login redirect")
        #expect(parsed?.description == "Users see a blank page.")
        #expect(parsed?.selfLink == "https://jira-prod-us-28-1.prod.atl-paas.net/rest/api/2/issue/10001")
    }

    /// `description` is optional ADF; its absence must not fail the whole parse, since
    /// plenty of real tickets have a summary but no description.
    @Test func parseWorkItemJSONDefaultsMissingDescriptionToEmptyString() {
        let json = #"{"fields": {"summary": "No description here"}}"#
        let parsed = JiraTracker.parseWorkItemJSON(json)
        #expect(parsed?.summary == "No description here")
        #expect(parsed?.description == "")
        #expect(parsed?.selfLink == nil)
    }

    @Test func parseWorkItemJSONIsNilWithoutASummary() {
        #expect(JiraTracker.parseWorkItemJSON(#"{"fields": {}}"#) == nil)
        #expect(JiraTracker.parseWorkItemJSON(#"{"nope": true}"#) == nil)
    }

    @Test func parseWorkItemJSONIsNilOnMalformedJSON() {
        #expect(JiraTracker.parseWorkItemJSON("not json at all") == nil)
        #expect(JiraTracker.parseWorkItemJSON("[1, 2, 3]") == nil)
        #expect(JiraTracker.parseWorkItemJSON("") == nil)
    }

    // MARK: - parseSiteHost(fromAuthStatusOutput:)

    /// Pins the exact line shape `acli jira auth status` prints, per the doc comment on
    /// `browseURL`: "Site: your-org.atlassian.net" among other auth-status chatter.
    @Test func parseSiteHostExtractsTheSiteLine() {
        let output = """
        Logged in as: someone@example.com
        Site: your-org.atlassian.net
        Auth type: oauth
        """
        #expect(JiraTracker.parseSiteHost(fromAuthStatusOutput: output) == "your-org.atlassian.net")
    }

    @Test func parseSiteHostTrimsWhitespaceAroundTheHost() {
        #expect(JiraTracker.parseSiteHost(fromAuthStatusOutput: "Site:   your-org.atlassian.net   ") == "your-org.atlassian.net")
    }

    @Test func parseSiteHostIsNilWhenNoSiteLineExists() {
        #expect(JiraTracker.parseSiteHost(fromAuthStatusOutput: "Logged in as: someone@example.com") == nil)
        #expect(JiraTracker.parseSiteHost(fromAuthStatusOutput: "") == nil)
    }

    // MARK: - browseURL

    /// The site host, when known, wins over the `self` link entirely — the doc comment on
    /// `browseURL` explains why: the API's `self` host is an internal backend host that
    /// isn't guaranteed to resolve for a human.
    @Test func browseURLPrefersTheSiteHostOverTheSelfLink() {
        let url = JiraTracker.browseURL(
            forKey: "PROJ-1", siteHost: "your-org.atlassian.net",
            selfLink: "https://jira-prod-us-28-1.prod.atl-paas.net/rest/api/2/issue/1"
        )
        #expect(url == "https://your-org.atlassian.net/browse/PROJ-1")
    }

    @Test func browseURLFallsBackToTheSelfLinksHostWhenNoSiteHost() {
        let url = JiraTracker.browseURL(
            forKey: "PROJ-1", siteHost: nil,
            selfLink: "https://jira-prod-us-28-1.prod.atl-paas.net/rest/api/2/issue/1"
        )
        #expect(url == "https://jira-prod-us-28-1.prod.atl-paas.net/browse/PROJ-1")
    }

    @Test func browseURLFallsBackToAtlassianDotNetWithNeitherHostAvailable() {
        #expect(JiraTracker.browseURL(forKey: "PROJ-1", siteHost: nil, selfLink: nil) == "https://atlassian.net/browse/PROJ-1")
    }

    /// An unparseable or hostless `self` link is treated the same as no `self` link at all.
    @Test func browseURLFallsBackWhenTheSelfLinkHasNoHost() {
        #expect(JiraTracker.browseURL(forKey: "PROJ-1", siteHost: nil, selfLink: "not a url") == "https://atlassian.net/browse/PROJ-1")
    }

    // MARK: - fetch(_:) with no acli on PATH

    /// `fetchTicket` must degrade to `nil` rather than throw or hang when `acli` isn't
    /// installed/authenticated — the pipeline's best-effort contract from `IssueTracker`'s
    /// doc comment. Guarded on `acli` actually being absent (true on the CI runner, unlike
    /// `gh` which ships preinstalled there) so this can't flake into hitting a real,
    /// authenticated `acli` on a machine that happens to have one.
    @Test(.enabled(if: Shell.which("acli") == nil))
    func fetchReturnsNilWhenAcliIsUnavailable() async {
        let ticket = await JiraTracker().fetch(IssueRef(id: "PROJ-1", tracker: .jira))
        #expect(ticket == nil)
    }

    @Test func trackerIDIsJira() {
        #expect(JiraTracker().id == .jira)
    }
}
