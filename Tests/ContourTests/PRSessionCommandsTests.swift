import Testing
import AppKit
@testable import Contour

/// `PRSessionCommandsLogic` is the menu's enablement logic CLAUDE.md calls out for this
/// file, pulled out of `PRSessionCommands`'s `Commands` closures so it's directly testable
/// against a plain `PRSessionActions?`. `PRSessionActions` itself holds the dispatch
/// methods: `copyLink` is safe to drive against the real pasteboard; `openOnGitHub` takes
/// an injectable `opener` closure for the same reason, so its URL-present branch is
/// exercised without actually invoking `NSWorkspace.shared.open` and launching a real
/// browser from CI — the same caution this suite already applies to `NSItemProvider.loadObject`.
/// `PRSessionCommands` itself (its `body`) is a SwiftUI `Commands` scene with no UI-testing
/// infrastructure in this suite to host it, same as `ContourApp.body`/`ReviewCommands.body`
/// in `AppDelegateTests`: not safely exercisable from a headless unit test without either a
/// UI test target or risking side effects on `NSApp`/`FocusedValues`. That's this file's
/// accepted remaining coverage gap: `PRSessionCommandsLogic` factors every branch of that
/// body's actual decision-making out into something this suite *can* drive directly, and
/// the tests below drive all of it; what's left in `body` is SwiftUI wiring (`CommandGroup`,
/// `Button`, `.keyboardShortcut`) with no logic of its own to assert on.
/// `.serialized`: `NSPasteboard.general` is a process-wide resource, like `AnonymousAPISourceTests`'
/// static handler — concurrent reads/writes from parallel tests crashed CI.
@Suite(.serialized)
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
        var openerCalled = false
        actions.openOnGitHub(opener: { _ in openerCalled = true })
        #expect(!openerCalled)
    }

    /// Pins that `openOnGitHub` hands the injected opener the PR's own URL (not some other
    /// value), covering the branch that in production calls `NSWorkspace.shared.open`
    /// without this suite ever launching a real browser.
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
