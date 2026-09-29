import Testing
import AppKit
@testable import Contour

@Suite(.serialized)
struct PRSessionCommandsTests {
    @Test func openPullRequestIsEnabledOnlyWithASession() {
        let session = PRSessionActions(hasOpenPR: false, pullRequestURL: nil, openDifferent: {}, close: {})
        #expect(PRSessionCommandsLogic.openPullRequestEnabled(session))
        #expect(!PRSessionCommandsLogic.openPullRequestEnabled(nil))
    }

    @Test func hasLinkableURLNeedsBothASessionAndAURL() {
        let url = URL(string: "https://github.com/acme/shop/pull/42")!
        let withURL = PRSessionActions(hasOpenPR: true, pullRequestURL: url, openDifferent: {}, close: {})
        let withoutURL = PRSessionActions(hasOpenPR: true, pullRequestURL: nil, openDifferent: {}, close: {})
        #expect(PRSessionCommandsLogic.hasLinkableURL(withURL))
        #expect(!PRSessionCommandsLogic.hasLinkableURL(withoutURL))
        #expect(!PRSessionCommandsLogic.hasLinkableURL(nil))
    }

    @Test func showsClosePullRequestOnlyWhenASessionHasAnOpenPR() {
        let open = PRSessionActions(hasOpenPR: true, pullRequestURL: nil, openDifferent: {}, close: {})
        let notOpen = PRSessionActions(hasOpenPR: false, pullRequestURL: nil, openDifferent: {}, close: {})
        #expect(PRSessionCommandsLogic.showsClosePullRequest(open))
        #expect(!PRSessionCommandsLogic.showsClosePullRequest(notOpen))
        #expect(!PRSessionCommandsLogic.showsClosePullRequest(nil))
    }

    @Test func openOnGitHubDoesNothingWithNoPullRequestURL() {
        let actions = PRSessionActions(hasOpenPR: true, pullRequestURL: nil, openDifferent: {}, close: {})
        var openerCalled = false
        actions.openOnGitHub(opener: { _ in openerCalled = true })
        #expect(!openerCalled)
    }

    @Test func openOnGitHubOpensThePullRequestURLThroughTheInjectedOpener() {
        let url = URL(string: "https://github.com/acme/shop/pull/42")!
        let actions = PRSessionActions(hasOpenPR: true, pullRequestURL: url, openDifferent: {}, close: {})
        var opened: URL?
        actions.openOnGitHub(opener: { opened = $0 })
        #expect(opened == url)
    }

    @Test func copyLinkDoesNothingWithNoPullRequestURL() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("unrelated", forType: .string)

        let actions = PRSessionActions(hasOpenPR: true, pullRequestURL: nil, openDifferent: {}, close: {})
        actions.copyLink()

        #expect(pasteboard.string(forType: .string) == "unrelated")
    }

    @Test func copyLinkPutsThePullRequestURLOnThePasteboard() {
        let url = URL(string: "https://github.com/acme/shop/pull/42")!
        let actions = PRSessionActions(hasOpenPR: true, pullRequestURL: url, openDifferent: {}, close: {})
        actions.copyLink()

        #expect(NSPasteboard.general.string(forType: .string) == url.absoluteString)
    }

    @Test func hasOpenPRAndPullRequestURLAreStoredAsGiven() {
        let url = URL(string: "https://github.com/acme/shop/pull/42")!
        let actions = PRSessionActions(hasOpenPR: false, pullRequestURL: url, openDifferent: {}, close: {})
        #expect(actions.hasOpenPR == false)
        #expect(actions.pullRequestURL == url)
    }
}
