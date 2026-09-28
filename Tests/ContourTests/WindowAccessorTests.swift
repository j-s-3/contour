import Testing
@testable import Contour

/// `WindowAccessor` is a thin `NSViewRepresentable` bridge: `makeNSView`/`updateNSView`
/// themselves need a real, live `NSWindow` (via SwiftUI's own `NSViewRepresentableContext`,
/// which has no public initializer) and stay untested here. `shouldEnterFullScreen` and
/// `collectionBehaviorWithFullScreenPrimary` pull the two pieces of actual decision logic
/// out of those methods' bodies into plain functions, per CLAUDE.md's own suggestion for
/// this file, so both are directly testable without a live window.
struct WindowAccessorTests {

    @Test func coordinatorStartsWithoutHavingEnteredFullScreen() {
        let coordinator = WindowAccessor.Coordinator()
        #expect(!coordinator.didEnterFullScreen)
        coordinator.didEnterFullScreen = true
        #expect(coordinator.didEnterFullScreen)
    }

    /// `makeCoordinator()` is a `NSViewRepresentable` requirement, implicitly `@MainActor`.
    @Test @MainActor func makeCoordinatorReturnsAFreshInstanceEachCall() {
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

    /// `makeNSView`'s collection-behavior fix-up is pulled out as a pure `OptionSet`
    /// operation (see `collectionBehaviorWithFullScreenPrimary`) so this can be checked
    /// without touching a live `NSWindow`.
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
}
