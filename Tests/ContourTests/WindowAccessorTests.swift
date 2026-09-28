import Testing
@testable import Contour

/// `WindowAccessor.swift` was at 0.00% coverage. It's a thin `NSViewRepresentable` bridge:
/// `makeNSView`/`updateNSView` need a real, live `NSWindow` (via SwiftUI's own
/// `NSViewRepresentableContext`, which has no public initializer) and stay untested here.
/// `shouldEnterFullScreen` pulls the actual decision out of `updateNSView`'s deferred
/// closure into a plain function, per CLAUDE.md's own suggestion for this file, so the
/// three-way guard is directly testable.
struct WindowAccessorTests {

    @Test func coordinatorStartsWithoutHavingEnteredFullScreen() {
        let coordinator = WindowAccessor.Coordinator()
        #expect(!coordinator.didEnterFullScreen)
        coordinator.didEnterFullScreen = true
        #expect(coordinator.didEnterFullScreen)
    }

    @Test func makeCoordinatorReturnsAFreshInstanceEachCall() {
        let accessor = WindowAccessor(entersFullScreen: true)
        let first = accessor.makeCoordinator()
        let second = accessor.makeCoordinator()
        #expect(first !== second)
        #expect(!first.didEnterFullScreen && !second.didEnterFullScreen)
    }

    @Test func enteringRequiresOptInNotYetEnteredAndNotAlreadyFullScreen() {
        #expect(WindowAccessor.shouldEnterFullScreen(entersFullScreen: true, alreadyEntered: false, isCurrentlyFullScreen: false))

        #expect(!WindowAccessor.shouldEnterFullScreen(entersFullScreen: false, alreadyEntered: false, isCurrentlyFullScreen: false),
                "not opted in")
        #expect(!WindowAccessor.shouldEnterFullScreen(entersFullScreen: true, alreadyEntered: true, isCurrentlyFullScreen: false),
                "this view already toggled it once")
        #expect(!WindowAccessor.shouldEnterFullScreen(entersFullScreen: true, alreadyEntered: false, isCurrentlyFullScreen: true),
                "already full screen by some other means")
        #expect(!WindowAccessor.shouldEnterFullScreen(entersFullScreen: false, alreadyEntered: true, isCurrentlyFullScreen: true))
    }
}
