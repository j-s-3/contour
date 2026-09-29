import Testing
@testable import Contour

struct JiraTrackerFetchTests {
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

    @Test func browseURLFallsBackWhenTheSelfLinkHasNoHost() {
        #expect(JiraTracker.browseURL(forKey: "PROJ-1", siteHost: nil, selfLink: "not a url") == "https://atlassian.net/browse/PROJ-1")
    }

    @Test(.enabled(if: Shell.which("acli") == nil))
    func fetchReturnsNilWhenAcliIsUnavailable() async {
        let ticket = await JiraTracker().fetch(IssueRef(id: "PROJ-1", tracker: .jira))
        #expect(ticket == nil)
    }

    @Test func trackerIDIsJira() {
        #expect(JiraTracker().id == .jira)
    }
}
