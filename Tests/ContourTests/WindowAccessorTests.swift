import AppKit
import SwiftUI
import Testing

@testable import Contour

@Suite(.serialized)
struct WindowAccessorTests {
    @Test func coordinatorStartsWithoutHavingEnteredFullScreen() {
        let coordinator = WindowAccessor.Coordinator()
        #expect(!coordinator.didEnterFullScreen)
        coordinator.didEnterFullScreen = true
        #expect(coordinator.didEnterFullScreen)
    }

    @Test @MainActor func makeCoordinatorReturnsAFreshInstanceEachCall() {
        let accessor = WindowAccessor(entersFullScreen: true)
        let first = accessor.makeCoordinator()
        let second = accessor.makeCoordinator()
        #expect(first !== second)
        #expect(!first.didEnterFullScreen && !second.didEnterFullScreen)
    }

    @Test func enteringRequiresOptInNotYetEnteredAndNotAlreadyFullScreen() {
        #expect(
            WindowAccessor.shouldEnterFullScreen(
                entersFullScreen: true, alreadyEntered: false, isCurrentlyFullScreen: false))

        #expect(
            !WindowAccessor.shouldEnterFullScreen(
                entersFullScreen: false, alreadyEntered: false, isCurrentlyFullScreen: false),
            "not opted in")
        #expect(
            !WindowAccessor.shouldEnterFullScreen(
                entersFullScreen: true, alreadyEntered: true, isCurrentlyFullScreen: false),
            "this view already toggled it once")
        #expect(
            !WindowAccessor.shouldEnterFullScreen(
                entersFullScreen: true, alreadyEntered: false, isCurrentlyFullScreen: true),
            "already full screen by some other means")
        #expect(
            !WindowAccessor.shouldEnterFullScreen(
                entersFullScreen: false, alreadyEntered: true, isCurrentlyFullScreen: true))
    }

    @Test func collectionBehaviorGainsFullScreenPrimaryWhenAbsent() {
        let result = WindowAccessor.collectionBehaviorWithFullScreenPrimary([])
        #expect(result.contains(.fullScreenPrimary))
    }

    @Test func collectionBehaviorStaysUnchangedWhenAlreadyPresent() {
        let result = WindowAccessor.collectionBehaviorWithFullScreenPrimary(.fullScreenPrimary)
        #expect(result == .fullScreenPrimary)
    }

    @Test func collectionBehaviorPreservesOtherFlagsAlreadySet() {
        let result = WindowAccessor.collectionBehaviorWithFullScreenPrimary(.managed)
        #expect(result.contains(.managed), "existing flags must survive the fix-up")
        #expect(result.contains(.fullScreenPrimary))
    }

    @MainActor
    final class RecordingWindow: NSWindow {
        var toggleCount = 0
        var reportsFullScreen = false
        var styleMaskReads = 0
        override var styleMask: NSWindow.StyleMask {
            get {
                styleMaskReads += 1
                return reportsFullScreen ? super.styleMask.union(.fullScreen) : super.styleMask
            }
            set { super.styleMask = newValue }
        }
        override func toggleFullScreen(_ sender: Any?) { toggleCount += 1 }
    }

    @MainActor
    private func host(entersFullScreen: Bool) -> (RecordingWindow, NSHostingView<WindowAccessor>) {
        _ = NSApplication.shared
        let view = NSHostingView(rootView: WindowAccessor(entersFullScreen: entersFullScreen))
        let window = RecordingWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.animationBehavior = .none
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.orderBack(nil)
        return (window, view)
    }

    @MainActor
    private func settle(_ view: NSView, for seconds: TimeInterval) async {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            view.layoutSubtreeIfNeeded()
            view.displayIfNeeded()
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    @MainActor
    private func poll(_ view: NSView, timeout: TimeInterval = 120, until condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            view.layoutSubtreeIfNeeded()
            view.displayIfNeeded()
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    @Test @MainActor func hostedViewMarksItsWindowFullScreenPrimary() async {
        let (window, view) = host(entersFullScreen: false)
        let marked = await poll(view) { window.collectionBehavior.contains(.fullScreenPrimary) }
        #expect(marked)
        #expect(window.toggleCount == 0)
        window.close()
    }

    @Test @MainActor func hostedViewEntersFullScreenOnceWhenOptedIn() async {
        let (window, view) = host(entersFullScreen: true)
        let entered = await poll(view) { window.toggleCount == 1 }
        #expect(entered)
        view.rootView = WindowAccessor(entersFullScreen: true)
        await settle(view, for: 1)
        #expect(window.toggleCount == 1)
        window.close()
    }

    @Test @MainActor func hostedViewSkipsFullScreenWhenWindowIsGoneBeforeTheDelay() async {
        let (window, view) = host(entersFullScreen: true)
        window.contentView = NSView()
        let detached = await poll(view) { view.window == nil }
        #expect(detached)
        await settle(view, for: 1)
        #expect(window.toggleCount == 0)
        window.close()
    }

    @Test @MainActor func hostedViewSkipsFullScreenWhenWindowAlreadyFullScreen() async {
        let (window, view) = host(entersFullScreen: true)
        window.reportsFullScreen = true
        let checked = await poll(view) { window.styleMaskReads > 0 }
        #expect(checked)
        await settle(view, for: 0.2)
        #expect(window.toggleCount == 0)
        window.close()
    }
}
