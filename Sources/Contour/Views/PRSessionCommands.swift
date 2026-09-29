import AppKit
import SwiftUI

struct PRSessionActions {
    var hasOpenPR: Bool
    var pullRequestURL: URL?
    var openDifferent: () -> Void
    var close: () -> Void

    func openOnGitHub(opener: (URL) -> Void = { NSWorkspace.shared.open($0) }) {
        if let pullRequestURL { opener(pullRequestURL) }
    }

    func copyLink() {
        guard let pullRequestURL else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(pullRequestURL.absoluteString, forType: .string)
    }
}

extension FocusedValues {
    @Entry var prSession: PRSessionActions?
}

enum PRSessionCommandsLogic {
    static func openPullRequestEnabled(_ session: PRSessionActions?) -> Bool { session != nil }
    static func hasLinkableURL(_ session: PRSessionActions?) -> Bool { session?.pullRequestURL != nil }
    static func showsClosePullRequest(_ session: PRSessionActions?) -> Bool { session?.hasOpenPR == true }
}

@MainActor
struct PRSessionMenuActions {
    var session: PRSessionActions?
    var closeKeyWindow: () -> Void = { NSApplication.shared.keyWindow?.performClose(nil) }
    var openURL: (URL) -> Void = { NSWorkspace.shared.open($0) }

    func openDifferent() { session?.openDifferent() }
    func openOnGitHub() { session?.openOnGitHub(opener: openURL) }
    func copyLink() { session?.copyLink() }
    func closePullRequest() { session?.close() }
    func closeWindow() { closeKeyWindow() }
}

struct PRSessionCommands: Commands {
    @FocusedValue(\.prSession) private var session

    var body: some Commands {
        PRSessionCommands.groups(session: session, actions: PRSessionMenuActions(session: session))
    }

    @CommandsBuilder
    static func groups(session: PRSessionActions?, actions: PRSessionMenuActions) -> some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open Pull Request…", action: actions.openDifferent)
                .keyboardShortcut("o", modifiers: .command)
                .disabled(!PRSessionCommandsLogic.openPullRequestEnabled(session))
            Divider()
            Button("Open on GitHub", action: actions.openOnGitHub)
                .keyboardShortcut(OpenOnGitHubShortcut.key, modifiers: OpenOnGitHubShortcut.modifiers)
                .disabled(!PRSessionCommandsLogic.hasLinkableURL(session))
            Button("Copy Link to Pull Request", action: actions.copyLink)
                .disabled(!PRSessionCommandsLogic.hasLinkableURL(session))
        }
        CommandGroup(replacing: .saveItem) {
            if PRSessionCommandsLogic.showsClosePullRequest(session) {
                Button("Close Pull Request", action: actions.closePullRequest)
                    .keyboardShortcut("w", modifiers: .command)
            } else {
                Button("Close", action: actions.closeWindow)
                    .keyboardShortcut("w", modifiers: .command)
            }
        }
    }
}
