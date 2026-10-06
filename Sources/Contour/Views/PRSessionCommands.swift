import AppKit
import SwiftUI

struct PRSessionActions {
    var hasOpenPR: Bool
    var pullRequestURL: URL?
    var openDifferent: () -> Void
    var close: () -> Void
    var repository: String?
    var isWatchingRepository = false
    var toggleWatch: () -> Void = {}
    var canOpenNextLayer = false
    var canOpenPreviousLayer = false
    var openNextLayer: () -> Void = {}
    var openPreviousLayer: () -> Void = {}

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
    static func watchEnabled(_ session: PRSessionActions?) -> Bool { session?.repository != nil }
    static func nextLayerEnabled(_ session: PRSessionActions?) -> Bool { session?.canOpenNextLayer == true }
    static func previousLayerEnabled(_ session: PRSessionActions?) -> Bool { session?.canOpenPreviousLayer == true }

    static func watchTitle(_ session: PRSessionActions?) -> String {
        guard let session, let repository = session.repository else { return "Watch Repository" }
        return session.isWatchingRepository ? "Stop Watching \(repository)" : "Watch \(repository)"
    }

    static func repository(fromPullRequestURL url: String?) -> String? {
        url.flatMap(WatchedRepository.parse)?.id
    }
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
    func toggleWatch() { session?.toggleWatch() }
    func openNextLayer() { session?.openNextLayer() }
    func openPreviousLayer() { session?.openPreviousLayer() }
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
            Button(PRSessionCommandsLogic.watchTitle(session), action: actions.toggleWatch)
                .disabled(!PRSessionCommandsLogic.watchEnabled(session))
            Divider()
            Button("Open Next Layer in Stack", action: actions.openNextLayer)
                .keyboardShortcut("]", modifiers: [.command, .option])
                .disabled(!PRSessionCommandsLogic.nextLayerEnabled(session))
            Button("Open Previous Layer in Stack", action: actions.openPreviousLayer)
                .keyboardShortcut("[", modifiers: [.command, .option])
                .disabled(!PRSessionCommandsLogic.previousLayerEnabled(session))
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
