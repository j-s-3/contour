import Testing
import Foundation
@testable import Contour

/// `PRDropTarget.loadPullRequest`'s URL/text branches wrap `PRLink` parsing (already
/// covered by `PRLinkTests`) behind `NSItemProvider.loadObject`'s async delivery. An
/// earlier attempt (#169) drove that with a synthetic `NSItemProvider` from a synchronous
/// `@Test` and crashed the CI test process — the completion handler fires on a background
/// queue, and returning from a synchronous test before it runs raced its teardown. Awaiting
/// delivery from an `async` `@Test` (`loadPullRequest` bridges the handler through
/// `withCheckedContinuation` itself) keeps the test alive until the handler actually resumes it, which is the documented
/// way to drive this API outside a real drag session.
struct PRDropTargetTests {
    @Test func completesWithNilWhenTheProviderCarriesNeitherAURLNorText() async {
        let result = await PRDropTarget.loadPullRequest(from: NSItemProvider())
        #expect(result == nil)
    }

    /// A browser drag hands `onDrop` a URL directly; a GitHub PR link resolves through
    /// `PRLink.pullRequestURL` to the canonical form.
    @Test func aPullRequestURLProviderResolvesToTheCanonicalLink() async {
        let provider = NSItemProvider(object: URL(string: "https://github.com/sharkdp/bat/pull/3877")! as NSURL)
        let result = await PRDropTarget.loadPullRequest(from: provider)
        #expect(result == "https://github.com/sharkdp/bat/pull/3877")
    }

    /// A dropped URL that isn't a GitHub pull request completes with nil rather than
    /// opening an unrelated page as a review.
    @Test func aNonPullRequestURLProviderCompletesWithNil() async {
        let provider = NSItemProvider(object: URL(string: "https://example.com/sharkdp/bat")! as NSURL)
        let result = await PRDropTarget.loadPullRequest(from: provider)
        #expect(result == nil)
    }

    /// A text drag (Slack, email) carries the link surrounded by prose, so the text branch
    /// searches the whole string rather than requiring it to be nothing but the URL.
    @Test func aTextProviderWithSurroundingProseFindsTheLink() async {
        let provider = NSItemProvider(object: "please review https://github.com/sharkdp/bat/pull/3877 today" as NSString)
        let result = await PRDropTarget.loadPullRequest(from: provider)
        #expect(result == "https://github.com/sharkdp/bat/pull/3877")
    }

    /// Plain text carrying no pull request link at all completes with nil.
    @Test func aTextProviderWithNoLinkCompletesWithNil() async {
        let provider = NSItemProvider(object: "just some unrelated words" as NSString)
        let result = await PRDropTarget.loadPullRequest(from: provider)
        #expect(result == nil)
    }
}
