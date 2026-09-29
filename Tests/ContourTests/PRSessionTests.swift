import Testing
import Foundation
@testable import Contour

struct PRSessionTests {
    @Test @MainActor func startScreenHasNoOpenPR() {
        let store = GraphStore()
        #expect(store.phase == .idle)
        #expect(!store.hasOpenPR)
        #expect(store.pullRequestURL == nil)
    }

    @Test @MainActor func closingFromTheStartScreenStaysThere() {
        let store = GraphStore()
        store.close()
        #expect(store.phase == .idle)
        #expect(!store.hasOpenPR)
    }

    @Test func pullRequestLinkIsTheURLItWasOpenedFrom() {
        let url = "https://github.example.com/acme/widgets/pull/42"
        let actions = ReviewActions(graph: nil, prURL: url)
        #expect(actions.pullRequestURL?.absoluteString == url)
    }

    @Test func pullRequestLinkFallsBackToGitHubFromTheGraph() {
        let graph = ContourSampleData.publishTriggeredReindex
        let actions = ReviewActions(graph: graph, prURL: nil)
        #expect(actions.pullRequestURL?.absoluteString == "https://github.com/\(graph.pr.repo)/pull/\(graph.pr.number)")
    }
}
