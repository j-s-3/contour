import Testing
@testable import Contour

struct AppDelegateTests {
    @MainActor
    @Test func appIconResolvesFromTheBundleWithoutCrashing() {
        _ = AppDelegate.appIcon
    }
}
