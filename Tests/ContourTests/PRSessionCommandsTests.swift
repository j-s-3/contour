import AppKit
import SwiftUI
import Testing

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

@MainActor
struct PRSessionCommandsBodyTests {
    @Test func menuActionsForwardToTheFocusedSession() {
        let url = URL(string: "https://github.com/acme/shop/pull/42")!
        var opened = 0
        var closed = 0
        var openedURL: URL?
        var windowsClosed = 0
        let session = PRSessionActions(
            hasOpenPR: true, pullRequestURL: url, openDifferent: { opened += 1 }, close: { closed += 1 })
        let actions = PRSessionMenuActions(
            session: session, closeKeyWindow: { windowsClosed += 1 }, openURL: { openedURL = $0 })

        actions.openDifferent()
        actions.openOnGitHub()
        actions.closePullRequest()
        actions.closeWindow()

        #expect(opened == 1)
        #expect(closed == 1)
        #expect(openedURL == url)
        #expect(windowsClosed == 1)
    }

    @Test func menuActionsAreNoOpsWithoutAFocusedSession() {
        var openedURL: URL?
        let actions = PRSessionMenuActions(session: nil, closeKeyWindow: {}, openURL: { openedURL = $0 })
        actions.openDifferent()
        actions.openOnGitHub()
        actions.copyLink()
        actions.closePullRequest()
        #expect(openedURL == nil)
    }

    @Test func copyLinkActionPutsTheURLOnThePasteboard() {
        let url = URL(string: "https://github.com/acme/shop/pull/43")!
        let session = PRSessionActions(hasOpenPR: true, pullRequestURL: url, openDifferent: {}, close: {})
        PRSessionMenuActions(session: session).copyLink()
        #expect(NSPasteboard.general.string(forType: .string) == url.absoluteString)
    }

    @Test func defaultCloseAndOpenClosuresAreCallableWithoutAKeyWindow() {
        let actions = PRSessionMenuActions(session: nil)
        actions.closeWindow()
    }

    @Test func bodyBuildsBothCommandGroupsWithoutAFocusedSession() {
        _ = PRSessionCommands().body
    }

    @Test func groupsBuildForAnOpenPullRequestSession() {
        let url = URL(string: "https://github.com/acme/shop/pull/42")!
        let session = PRSessionActions(hasOpenPR: true, pullRequestURL: url, openDifferent: {}, close: {})
        _ = PRSessionCommands.groups(session: session, actions: PRSessionMenuActions(session: session))
    }

    @Test func groupsBuildForASessionWithNoOpenPullRequest() {
        let session = PRSessionActions(hasOpenPR: false, pullRequestURL: nil, openDifferent: {}, close: {})
        _ = PRSessionCommands.groups(session: session, actions: PRSessionMenuActions(session: session))
    }
}
