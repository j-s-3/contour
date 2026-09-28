import Testing
import Foundation
@testable import Contour

/// `PRDropTarget.loadPullRequest`'s URL/text branches wrap `PRLink` parsing (already
/// covered by `PRLinkTests`) behind `NSItemProvider.loadObject`'s async delivery. Driving
/// that asynchronously with a synthetic (non-drag-session) `NSItemProvider` crashed the
/// whole test process in CI — a runtime trap, not a clean assertion failure — rather than
/// completing or timing out, so those branches aren't exercised here. Only the "neither a
/// URL nor text" branch is covered: it never calls `loadObject` at all, completing
/// synchronously with `nil`.
struct PRDropTargetTests {
    @MainActor
    @Test func completesWithNilWhenTheProviderCarriesNeitherAURLNorText() {
        var result: String? = "not yet completed"
        PRDropTarget.loadPullRequest(from: NSItemProvider()) { result = $0 }
        #expect(result == nil)
    }
}
