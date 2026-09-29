import SwiftUI
import AppKit

struct WindowAccessor: NSViewRepresentable {
    var entersFullScreen: Bool

    final class Coordinator {
        var didEnterFullScreen = false
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    nonisolated static func shouldEnterFullScreen(entersFullScreen: Bool, alreadyEntered: Bool, isCurrentlyFullScreen: Bool) -> Bool {
        entersFullScreen && !alreadyEntered && !isCurrentlyFullScreen
    }

    nonisolated static func collectionBehaviorWithFullScreenPrimary(_ behavior: NSWindow.CollectionBehavior) -> NSWindow.CollectionBehavior {
        behavior.union(.fullScreenPrimary)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        Task { @MainActor [weak view] in
            guard let window = view?.window else { return }
            window.collectionBehavior = Self.collectionBehaviorWithFullScreenPrimary(window.collectionBehavior)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard entersFullScreen, !context.coordinator.didEnterFullScreen else { return }
        Task { @MainActor [weak nsView] in
            try? await Task.sleep(for: .seconds(0.2))
            guard let window = nsView?.window else { return }
            guard Self.shouldEnterFullScreen(
                entersFullScreen: entersFullScreen,
                alreadyEntered: context.coordinator.didEnterFullScreen,
                isCurrentlyFullScreen: window.styleMask.contains(.fullScreen)
            ) else { return }
            context.coordinator.didEnterFullScreen = true
            window.toggleFullScreen(nil)
        }
    }
}
