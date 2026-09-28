import Testing
import AppKit
@testable import Contour

/// `PRSessionCommandsLogic` is the menu's enablement logic CLAUDE.md calls out for this
/// file, pulled out of `PRSessionCommands`'s `Commands` closures so it's directly testable
/// against a plain `PRSessionActions?`. `PRSessionActions` itself holds the dispatch
/// methods: `copyLink` is safe to drive against the real pasteboard (a legitimate macOS
/// API, like the established `NSPasteboard` usage elsewhere); `openOnGitHub` isn't
/// exercised past its nil guard, since actually invoking `NSWorkspace.shared.open` would
/// launch a real browser from CI — the same caution this suite already applies to
/// `NSItemProvider.loadObject`. `PRSessionCommands` itself is a SwiftUI `Commands` scene
/// with no UI-testing infrastructure in this suite to host it.
struct PRSessionCommandsTests {

    // MARK: - PRSessionCommandsLogic

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

    // MARK: - PRSessionActions

    @Test func openOnGitHubDoesNothingWithNoPullRequestURL() {
        let actions = PRSessionActions(hasOpenPR: true, pullRequestURL: nil, openDifferent: {}, close: {})
        actions.openOnGitHub()
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
