import SwiftUI
import AppKit

/// A bare SwiftPM executable target (no .app bundle / Info.plist) doesn't reliably get
/// `NSApplicationActivationPolicy.regular` from the system — depending on how it's
/// launched (double-click vs. backgrounded from a script/tool) it can come up as
/// LaunchServices `BackgroundOnly`: alive, no crash, but no Dock icon and no window ever
/// shown. That reads as "the app is hung" from the outside when it's actually just never
/// requesting a normal foreground presence. Force it explicitly so the window always
/// appears regardless of launch context.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The Contour mark, bundled from `Assets/Logo/Contour.icns` by `scripts/build-icon.sh`.
    static let appIcon: NSImage? = Bundle.module.url(forResource: "AppIcon", withExtension: "icns")
        .flatMap(NSImage.init(contentsOf:))

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        // With no Info.plist there's no `CFBundleIconFile`, so the Dock shows the generic
        // "exec" icon. Set it from the bundled resource — after the policy change, which
        // creates the Dock tile.
        if let icon = AppDelegate.appIcon { NSApp.applicationIconImage = icon }
        NSApp.activate(ignoringOtherApps: true)
        // Push any stored per-tier model overrides into AnalysisTier before the first run
        // can read them.
        MainActor.assumeIsolated { Preferences.shared.applyModelOverrides() }
    }
}

@main
struct ContourApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The stable id is what SwiftUI keys the autosaved window frame on; without one
        // the key is derived from the root view's type, so any change to ContentView's
        // modifiers would silently forget where the user left the window.
        WindowGroup(id: "review") {
            ContentView()
                .frame(minWidth: 1080, minHeight: 720)
        }
        .defaultSize(width: 1280, height: 820)
        .windowStyle(.automatic)
        .commands {
            CommandGroup(replacing: .newItem) { } // single-window MVP; one PR per window
            CommandGroup(after: .newItem) { ReviewCommands() }
        }

        // ⌘, — the three pluggable choices (harness, GitHub access, issue tracker) plus
        // per-tier model overrides.
        Settings {
            SettingsView()
        }
    }
}

/// File-menu exits from the review: to the PR on GitHub, or with the reviewer's judgment on
/// the pasteboard. Disabled until a PR is open.
private struct ReviewCommands: View {
    @FocusedValue(\.reviewStore) private var store

    var body: some View {
        Button("Open on GitHub") { store?.openOnGitHub() }
            .keyboardShortcut(OpenOnGitHubShortcut.key, modifiers: OpenOnGitHubShortcut.modifiers)
            .disabled(store?.pullRequestWebURL == nil)
        Button("Copy Review Summary") { store?.copyReviewSummary() }
            .disabled(store?.graph == nil)
    }
}
