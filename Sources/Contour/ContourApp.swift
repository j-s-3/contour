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
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
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
        WindowGroup {
            ContentView()
                .frame(minWidth: 1080, minHeight: 720)
        }
        .windowStyle(.automatic)
        .commands {
            CommandGroup(replacing: .newItem) { } // single-window MVP; one PR per window
        }

        // ⌘, — the three pluggable choices (harness, GitHub access, issue tracker) plus
        // per-tier model overrides.
        Settings {
            SettingsView()
        }
    }
}
