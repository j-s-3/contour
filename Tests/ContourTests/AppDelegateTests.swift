import AppKit
import SwiftUI
import Testing

@testable import Contour

struct AppDelegateTests {
    @MainActor
    @Test func appIconResolvesFromTheBundleWithoutCrashing() {
        _ = AppDelegate.appIcon
    }
}

@MainActor
@Suite(.serialized)
struct ContourAppTests {
    @Test func launchingTheDelegateActivatesARegularApp() {
        _ = NSApplication.shared
        AppDelegate().applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification))
        #expect(NSApp.activationPolicy() == .regular)
    }

    @Test func sceneBodyBuilds() {
        _ = NSApplication.shared
        _ = ContourApp().body
    }

    private func host(_ store: GraphStore?) -> NSWindow {
        _ = NSApplication.shared
        struct Probe: View {
            let store: GraphStore?
            var body: some View {
                ReviewCommands().focusedSceneValue(\.reviewStore, store)
            }
        }
        let view = NSHostingView(rootView: Probe(store: store))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 100),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.orderBack(nil)
        for _ in 0..<2 {
            view.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        return window
    }

    @Test func reviewCommandsRenderWithoutAndWithAStore() {
        host(nil).close()
        let store = GraphStore(phase: .opening)
        store.handle(.graph(ContourSampleData.publishTriggeredReindex))
        host(store).close()
    }

    @Test func reviewWindowContentHostsTheContentView() {
        _ = NSApplication.shared
        let view = NSHostingView(rootView: ReviewWindowContent(startScreen: .offline()))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.orderBack(nil)
        for _ in 0..<2 {
            view.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        #expect(view.fittingSize.width >= 1080)
        window.close()
    }
}
