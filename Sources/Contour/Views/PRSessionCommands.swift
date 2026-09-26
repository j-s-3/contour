import SwiftUI
import AppKit

/// What the menu bar and the window title can do with the PR a window has open. Published
/// by `ContentView` as a focused scene value, since the store lives in the window and the
/// menu bar belongs to the app.
struct PRSessionActions {
    /// Whether a PR is open (or opening, or failed to open) rather than the start screen.
    var hasOpenPR: Bool
    /// The PR on GitHub, once there is one to link to.
    var pullRequestURL: URL?
    /// Returns to the start screen with the URL field focused.
    var openDifferent: () -> Void
    /// Leaves the PR for the start screen.
    var close: () -> Void

    /// Opens the PR in the browser.
    func openOnGitHub() {
        if let pullRequestURL { NSWorkspace.shared.open(pullRequestURL) }
    }

    /// Puts the PR's link on the clipboard.
    func copyLink() {
        guard let pullRequestURL else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(pullRequestURL.absoluteString, forType: .string)
    }
}

extension FocusedValues {
    @Entry var prSession: PRSessionActions?
}

/// File ▸ Open Pull Request… / Close Pull Request, so leaving a PR never depends on knowing
/// the ⌘K palette. Takes the place of New Window (one PR per window) and of the standard
/// Close item, so that ⌘W can mean "close this PR".
struct PRSessionCommands: Commands {
    @FocusedValue(\.prSession) private var session

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open Pull Request…") { session?.openDifferent() }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(session == nil)
            Divider()
            Button("Open on GitHub") { session?.openOnGitHub() }
                .disabled(session?.pullRequestURL == nil)
            Button("Copy Link to Pull Request") { session?.copyLink() }
                .disabled(session?.pullRequestURL == nil)
        }
        // The standard Close lives in this group. SwiftUI drops a shortcut that another
        // menu item already claims, so Close Pull Request can only have ⌘W by replacing
        // it — and then ⌘W must still close the window when there's no PR to close. Two
        // branches, not one item with a conditional shortcut or title, because SwiftUI
        // doesn't re-apply those to an existing menu item.
        CommandGroup(replacing: .saveItem) {
            if let session, session.hasOpenPR {
                Button("Close Pull Request") { session.close() }
                    .keyboardShortcut("w", modifiers: .command)
            } else {
                Button("Close") { NSApp.keyWindow?.performClose(nil) }
                    .keyboardShortcut("w", modifiers: .command)
            }
        }
    }
}
