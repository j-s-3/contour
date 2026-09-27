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
    /// `@MainActor` because `NSImage` isn't `Sendable`, and a bare `static let` of a
    /// non-`Sendable` type is exactly the shared-mutable-global-state Swift 6 rejects —
    /// isolating it to the actor it's only ever read from is the fix, not a workaround.
    @MainActor static let appIcon: NSImage? = Bundle.module.url(forResource: "AppIcon", withExtension: "icns")
        .flatMap(NSImage.init(contentsOf:))

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        MainActor.assumeIsolated {
            // With no Info.plist there's no `CFBundleIconFile`, so the Dock shows the
            // generic "exec" icon. Set it from the bundled resource — after the policy
            // change, which creates the Dock tile.
            if let icon = AppDelegate.appIcon { NSApp.applicationIconImage = icon }
            // Push any stored per-tier model overrides into AnalysisTier before the first
            // run can read them.
            Preferences.shared.applyModelOverrides()
        }
        NSApp.activate(ignoringOtherApps: true)
        // Debug-only diagnostic: logs when the main thread stops responding for a while
        // (§13/§14 scaling limits). Compiled out of release builds entirely; see
        // `Support/MainThreadWatchdog.swift`.
        #if DEBUG
        MainThreadWatchdog.start()
        #endif
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
            PRSessionCommands() // replaces New Window and Close: single-window MVP, one PR per window
            CommandGroup(after: .newItem) { ReviewCommands() }
        }

        // ⌘, — the three pluggable choices (harness, GitHub access, issue tracker) plus
        // per-tier model overrides.
        Settings {
            SettingsView()
        }
    }
}

/// File-menu exit from the review with the reviewer's judgment on the pasteboard, below
/// `PRSessionCommands`' Open on GitHub. Disabled until a PR is open.
private struct ReviewCommands: View {
    @FocusedValue(\.reviewStore) private var store

    var body: some View {
        Button("Copy Review Summary") { store?.copyReviewSummary() }
            .disabled(store?.graph == nil)
    }
}
