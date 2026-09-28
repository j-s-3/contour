import Testing
import Foundation
@testable import Contour

/// `PRDropTarget.loadPullRequest` wraps `PRLink` parsing (already covered by `PRLinkTests`)
/// for drag-and-drop, per CLAUDE.md's guidance for this file. Tested against a real
/// `NSItemProvider` — a stable system type, not a network or CLI dependency — the same way
/// `PRLinkTests` uses fixture strings/URLs.
struct PRDropTargetTests {

    @MainActor
    private func load(_ provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            PRDropTarget.loadPullRequest(from: provider) { continuation.resume(returning: $0) }
        }
    }

    @MainActor
    @Test func loadsAPRLinkFromADraggedURL() async {
        let provider = NSItemProvider(object: URL(string: "https://github.com/owner/repo/pull/42")! as NSURL)
        #expect(await load(provider) == "https://github.com/owner/repo/pull/42")
    }

    @MainActor
    @Test func ignoresADraggedURLThatIsntAPullRequest() async {
        let provider = NSItemProvider(object: URL(string: "https://example.com")! as NSURL)
        #expect(await load(provider) == nil)
    }

    /// A text drag (Slack, email) carries the surrounding words, so the link is searched
    /// for rather than taken whole.
    @MainActor
    @Test func loadsAPRLinkFoundWithinDraggedText() async {
        let provider = NSItemProvider(object: "check out https://github.com/owner/repo/pull/7 please" as NSString)
        #expect(await load(provider) == "https://github.com/owner/repo/pull/7")
    }

    @MainActor
    @Test func ignoresTextWithNoPRLink() async {
        let provider = NSItemProvider(object: "no links here" as NSString)
        #expect(await load(provider) == nil)
    }

    @MainActor
    @Test func completesWithNilWhenTheProviderCarriesNeitherAURLNorText() async {
        #expect(await load(NSItemProvider()) == nil)
    }
}
