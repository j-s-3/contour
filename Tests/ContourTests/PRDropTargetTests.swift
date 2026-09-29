import Testing
import Foundation
@testable import Contour

struct PRDropTargetTests {
    @Test func completesWithNilWhenTheProviderCarriesNeitherAURLNorText() async {
        let result = await PRDropTarget.loadPullRequest(from: NSItemProvider())
        #expect(result == nil)
    }

    @Test func aPullRequestURLProviderResolvesToTheCanonicalLink() async {
        let provider = NSItemProvider(object: URL(string: "https://github.com/sharkdp/bat/pull/3877")! as NSURL)
        let result = await PRDropTarget.loadPullRequest(from: provider)
        #expect(result == "https://github.com/sharkdp/bat/pull/3877")
    }

    @Test func aNonPullRequestURLProviderCompletesWithNil() async {
        let provider = NSItemProvider(object: URL(string: "https://example.com/sharkdp/bat")! as NSURL)
        let result = await PRDropTarget.loadPullRequest(from: provider)
        #expect(result == nil)
    }

    @Test func aTextProviderWithSurroundingProseFindsTheLink() async {
        let provider = NSItemProvider(object: "please review https://github.com/sharkdp/bat/pull/3877 today" as NSString)
        let result = await PRDropTarget.loadPullRequest(from: provider)
        #expect(result == "https://github.com/sharkdp/bat/pull/3877")
    }

    @Test func aTextProviderWithNoLinkCompletesWithNil() async {
        let provider = NSItemProvider(object: "just some unrelated words" as NSString)
        let result = await PRDropTarget.loadPullRequest(from: provider)
        #expect(result == nil)
    }
}
