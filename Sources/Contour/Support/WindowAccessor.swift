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

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window else { return }
            // Belt-and-suspenders: make sure this window is explicitly eligible for the
            // full-screen space even if something about running unbundled left the
            // default collection behavior off.
            window.collectionBehavior.insert(.fullScreenPrimary)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard entersFullScreen, !context.coordinator.didEnterFullScreen else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak nsView] in
            guard let window = nsView?.window, !window.styleMask.contains(.fullScreen) else { return }
            context.coordinator.didEnterFullScreen = true
            window.toggleFullScreen(nil)
        }
    }
}
