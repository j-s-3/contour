import AppKit
import Foundation
import SwiftUI
import Testing

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
        let provider = NSItemProvider(
            object: "please review https://github.com/sharkdp/bat/pull/3877 today" as NSString)
        let result = await PRDropTarget.loadPullRequest(from: provider)
        #expect(result == "https://github.com/sharkdp/bat/pull/3877")
    }

    @Test func aTextProviderWithNoLinkCompletesWithNil() async {
        let provider = NSItemProvider(object: "just some unrelated words" as NSString)
        let result = await PRDropTarget.loadPullRequest(from: provider)
        #expect(result == nil)
    }
}

@MainActor
struct PRDropTargetHostingTests {
    private func host<V: View>(_ view: V) -> CGSize {
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        host.layoutSubtreeIfNeeded()
        return host.fittingSize
    }

    @Test func modifierAndHighlightLayOut() {
        _ = host(Text("body").opensDroppedPullRequests { _ in })
        _ = host(PRDropHighlight())
    }

    @Test func dropWithNoProvidersIsRejected() {
        let target = PRDropTarget(open: { _ in })
        #expect(target.handleDrop([]) == false)
    }

    @Test func dropOfAPullRequestURLOpensItAndIsAccepted() async {
        let opened = OpenedLinks()
        let target = PRDropTarget(open: { opened.add($0) })
        let provider = NSItemProvider(object: URL(string: "https://github.com/sharkdp/bat/pull/3877")! as NSURL)
        #expect(target.handleDrop([provider]) == true)
        for _ in 0..<200 where opened.values.isEmpty { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(opened.values == ["https://github.com/sharkdp/bat/pull/3877"])
    }

    @Test func dropOfUnrelatedTextIsAcceptedButOpensNothing() async {
        let opened = OpenedLinks()
        let target = PRDropTarget(open: { opened.add($0) })
        let provider = NSItemProvider(object: "nothing here" as NSString)
        #expect(target.handleDrop([provider]) == true)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(opened.values.isEmpty)
    }
}

@MainActor
private final class OpenedLinks {
    private(set) var values: [String] = []
    func add(_ value: String) { values.append(value) }
}
