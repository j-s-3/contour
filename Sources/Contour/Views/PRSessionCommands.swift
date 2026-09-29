import SwiftUI
import AppKit

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

struct PRSessionCommands: Commands {
    @FocusedValue(\.prSession) private var session

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open Pull Request…") { session?.openDifferent() }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(!PRSessionCommandsLogic.openPullRequestEnabled(session))
            Divider()
            Button("Open on GitHub") { session?.openOnGitHub() }
                .keyboardShortcut(OpenOnGitHubShortcut.key, modifiers: OpenOnGitHubShortcut.modifiers)
                .disabled(!PRSessionCommandsLogic.hasLinkableURL(session))
            Button("Copy Link to Pull Request") { session?.copyLink() }
                .disabled(!PRSessionCommandsLogic.hasLinkableURL(session))
        }
        CommandGroup(replacing: .saveItem) {
            if PRSessionCommandsLogic.showsClosePullRequest(session), let session {
                Button("Close Pull Request") { session.close() }
                    .keyboardShortcut("w", modifiers: .command)
            } else {
                Button("Close") { NSApp.keyWindow?.performClose(nil) }
                    .keyboardShortcut("w", modifiers: .command)
            }
        }
    }
}
