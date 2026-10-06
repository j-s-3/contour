import Foundation
import Testing

@testable import Contour

@MainActor
@Suite(.serialized)
struct GraphStoreStackTests {
    private struct FakePRSource: PRSource {
        let describesItself = "fake (tests)"
        let context: RawPRContext
        func fetchContext(prURL: String) async throws -> RawPRContext { context }
        func fetchIssue(owner: String, repo: String, number: String) async -> RawIssue? { nil }
    }

    private static func context(number: Int) -> RawPRContext {
        RawPRContext(
            url: "https://github.com/acme/shop/pull/\(number)", owner: "acme", repo: "shop", number: number,
            title: "Layer \(number)", body: "", author: "someone", state: "OPEN", headRefName: "l\(number)",
            baseRefName: number == 1 ? "main" : "l\(number - 1)", headSha: "head\(number)", baseSha: "base\(number)",
            isCrossRepository: false, headCloneURL: "https://github.com/acme/shop.git", additions: 1, deletions: 0,
            changedFiles: 1, files: ["a.rs"], commits: [], comments: [], reviews: [], diff: "diff")
    }

    private func stack(current: Int) -> PRStack {
        PRStack(layers: (1...3).map { StackDiscovery.layer(from: Self.context(number: $0)) }, currentIndex: current - 1)
    }

    private func preferences() -> Preferences {
        let defaults = UserDefaults(suiteName: "contour-stack-\(UUID().uuidString)")!
        return Preferences(defaults: defaults, environment: ["CONTOUR_HARNESS": "claude", "CONTOUR_TRACKER": "none"])
    }

    private func makeStore(discover: @escaping @Sendable (RawPRContext) async -> PRStack?) -> GraphStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "contour-stack-store-\(UUID().uuidString)", isDirectory: true)
        let fetched = Self.context(number: 2)
        return GraphStore(
            preferences: preferences(),
            makePipeline: { harness, tracker, _ in
                AnalysisPipeline(
                    harnessID: harness, trackerID: tracker, cache: AnalysisCache(directory: directory),
                    prSourceOverride: FakePRSource(context: fetched),
                    checkoutOverride: { context in
                        let dir = FileManager.default.temporaryDirectory
                            .appendingPathComponent("contour-stack-checkout-\(UUID().uuidString)", isDirectory: true)
                        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                        return RepoCheckout(rootDir: dir, headSha: context.headSha, baseSha: context.baseSha)
                    },
                    mockOverride: AnalysisService.MockOptions(latencyScale: 0.05),
                    stackDiscoveryOverride: discover)
            },
            metricsURL: directory.appendingPathComponent("metrics.jsonl"),
            submitReview: { _, _, _ in },
            canUseGitHubCLI: true)
    }

    private func wait(until condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(60)
        while !condition() {
            if ContinuousClock.now > deadline { return false }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return true
    }

    @Test func theStackArrivesWithTheReviewAndNamesNeighbours() async {
        let stack = stack(current: 2)
        let store = makeStore { _ in stack }
        store.load(prURL: Self.context(number: 2).url)
        #expect(await wait { store.stack != nil })
        #expect(store.stack == stack)
        #expect(store.canOpenNextLayer)
        #expect(store.canOpenPreviousLayer)
        #expect(store.stackAnalysis.isEmpty)
        store.close()
    }

    @Test func openingTheNextLayerLoadsItsURLAndClearsTheOldStack() async {
        let stack = stack(current: 2)
        let store = makeStore { _ in stack }
        store.load(prURL: Self.context(number: 2).url)
        #expect(await wait { store.stack != nil })
        store.openNextLayer()
        #expect(store.lastPRURL == Self.context(number: 3).url)
        #expect(store.stack == nil)
        store.close()
    }

    @Test func openingThePreviousLayerLoadsItsURL() async {
        let stack = stack(current: 2)
        let store = makeStore { _ in stack }
        store.load(prURL: Self.context(number: 2).url)
        #expect(await wait { store.stack != nil })
        store.openPreviousLayer()
        #expect(store.lastPRURL == Self.context(number: 1).url)
        store.close()
    }

    @Test func atTheEndsNextAndPreviousAreDisabledAndDoNothing() async {
        let top = stack(current: 3)
        let store = makeStore { _ in top }
        store.load(prURL: Self.context(number: 2).url)
        #expect(await wait { store.stack != nil })
        #expect(!store.canOpenNextLayer)
        #expect(store.canOpenPreviousLayer)
        store.openNextLayer()
        #expect(store.lastPRURL == Self.context(number: 2).url)
        #expect(store.stack == top)
        store.close()
    }

    @Test func withoutAStackNothingIsEnabled() {
        let store = makeStore { _ in nil }
        #expect(!store.canOpenNextLayer)
        #expect(!store.canOpenPreviousLayer)
        store.openPreviousLayer()
        store.openNextLayer()
        #expect(store.lastPRURL == nil)
    }

    @Test func cachedLayersFromTheEventAreMarked() {
        let store = makeStore { _ in nil }
        store.handle(.stack(stack(current: 1), cached: [3]))
        #expect(store.stackAnalysis == [3: .cached])
        #expect(store.stack?.currentIndex == 0)
    }
}
