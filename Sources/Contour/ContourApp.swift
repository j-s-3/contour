import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static let appIcon: NSImage? = Bundle.module.url(forResource: "AppIcon", withExtension: "icns")
        .flatMap(NSImage.init(contentsOf:))

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        MainActor.assumeIsolated {
            if let icon = AppDelegate.appIcon { NSApp.applicationIconImage = icon }
            Preferences.shared.applyModelOverrides()
            #if DEBUG
                MainThreadWatchdog.start()
            #endif
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct ContourApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup(id: "review") {
            ReviewWindowContent()
        }
        .defaultSize(width: 1280, height: 820)
        .windowStyle(.automatic)
        .commands {
            PRSessionCommands()
            CommandGroup(after: .newItem) { ReviewCommands() }
        }

        Settings {
            SettingsView()
        }
    }
}

struct ReviewCommands: View {
    @FocusedValue(\.reviewStore) private var store

    var body: some View {
        Button("Copy Review Summary") { store?.copyReviewSummary() }
            .disabled(store?.graph == nil)
    }
}

struct ReviewWindowContent: View {
    var body: some View {
        ContentView()
            .frame(minWidth: 1080, minHeight: 720)
    }
}
