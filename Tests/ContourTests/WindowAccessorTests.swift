import Testing

@testable import Contour

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
}
