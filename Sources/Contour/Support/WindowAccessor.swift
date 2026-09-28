import SwiftUI
import AppKit

/// Grabs the hosting `NSWindow` for a SwiftUI view and, only when the user has opted in
/// (Settings › Window), enters real macOS full screen once, shortly after the window
/// appears. This app is built as a bare SPM executable (no .app bundle) rather than an
/// Xcode app target — the standard green-button full screen affordance is still present
/// since SwiftUI/AppKit windows get it by default, but launching straight into full
/// screen needs an explicit `toggleFullScreen` call, which requires a real `NSWindow`
/// reference SwiftUI doesn't hand you directly.
///
/// The window's frame is not handled here: SwiftUI autosaves it for a `WindowGroup` with
/// a stable id (see `ContourApp`), so by default the window simply reopens where it was.
struct WindowAccessor: NSViewRepresentable {
    /// Read once at launch; flipping the setting takes effect on the next launch rather
    /// than yanking the current window into or out of full screen.
    var entersFullScreen: Bool

    /// Guards against re-toggling if this view updates more than once — full screen
    /// should happen at most once, right after launch.
    final class Coordinator {
        var didEnterFullScreen = false
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// The full decision behind `updateNSView`'s deferred toggle, pulled out so it's
    /// testable without a live `NSWindow`: opted in, not already toggled by this view, and
    /// the window isn't already in full screen by some other means (the user's own
    /// green-button click, or a restored full-screen frame).
    nonisolated static func shouldEnterFullScreen(entersFullScreen: Bool, alreadyEntered: Bool, isCurrentlyFullScreen: Bool) -> Bool {
        entersFullScreen && !alreadyEntered && !isCurrentlyFullScreen
    }

    /// The belt-and-suspenders fix-up applied in `makeNSView`, pulled out as a pure
    /// `OptionSet` operation so it's testable without a live `NSWindow`: make sure the
    /// window is explicitly eligible for the full-screen space even if something about
    /// running unbundled left the default collection behavior off.
    nonisolated static func collectionBehaviorWithFullScreenPrimary(_ behavior: NSWindow.CollectionBehavior) -> NSWindow.CollectionBehavior {
        behavior.union(.fullScreenPrimary)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window else { return }
            window.collectionBehavior = Self.collectionBehaviorWithFullScreenPrimary(window.collectionBehavior)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard entersFullScreen, !context.coordinator.didEnterFullScreen else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak nsView] in
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
