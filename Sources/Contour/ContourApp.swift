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
        // With no Info.plist there's no `CFBundleIconFile`, so the Dock shows the generic
        // "exec" icon. Set it from the bundled resource — after the policy change, which
        // creates the Dock tile.
        if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }
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
