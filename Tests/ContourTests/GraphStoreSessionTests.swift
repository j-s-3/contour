import Foundation
import Testing

@testable import Contour

@MainActor
struct GraphStoreSessionTests {
    private struct FakePRSource: PRSource {
        let describesItself = "fake (tests)"
        let context: RawPRContext
        func fetchContext(prURL: String) async throws -> RawPRContext { context }
        func fetchIssue(owner: String, repo: String, number: String) async -> RawIssue? { nil }
    }

    private struct SubmitFailure: LocalizedError {
        var errorDescription: String? { "gh exploded" }
    }

    private let prURL = "https://github.com/acme/shop/pull/7"

    private func context() -> RawPRContext {
        RawPRContext(
            url: prURL, owner: "acme", repo: "shop", number: 7,
            title: "Detect binary content", body: "", author: "someone", state: "OPEN", headRefName: "fix",
            baseRefName: "main", headSha: "head1", baseSha: "base1", isCrossRepository: false,
            headCloneURL: "https://github.com/acme/shop.git", additions: 3, deletions: 1, changedFiles: 2,
            files: ["a.rs"], commits: [], comments: [], reviews: [], diff: "diff"
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "contour-graphstore-\(UUID().uuidString)", isDirectory: true)
    }

    private func preferences(harness: String?) -> Preferences {
        let defaults = UserDefaults(suiteName: "contour-graphstore-\(UUID().uuidString)")!
        let environment = harness.map { ["CONTOUR_HARNESS": $0, "CONTOUR_TRACKER": "none"] } ?? [:]
        return Preferences(defaults: defaults, environment: environment)
    }

    private func pipelineFactory(
        latencyScale: Double? = nil, cacheDirectory: URL
    ) -> GraphStore.PipelineFactory {
        let ctx = context()
        return { harness, tracker, _ in
            AnalysisPipeline(
                harnessID: harness, trackerID: tracker, cache: AnalysisCache(directory: cacheDirectory),
                prSourceOverride: FakePRSource(context: ctx),
                checkoutOverride: { fetched in
                    let dir = FileManager.default.temporaryDirectory
                        .appendingPathComponent("contour-checkout-\(UUID().uuidString)", isDirectory: true)
                    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    return RepoCheckout(
                        rootDir: dir, headSha: fetched.headSha, baseSha: fetched.baseSha, symbolIndexPath: nil)
                },
                mockOverride: AnalysisService.MockOptions(latencyScale: latencyScale)
            )
        }
    }

    private func makeStore(
        harness: String? = "claude", latencyScale: Double? = 0.05, metricsURL: URL? = nil,
        submitReview: @escaping GraphStore.ReviewSubmitter = { _, _, _ in }
    ) -> GraphStore {
        GraphStore(
            preferences: preferences(harness: harness),
            makePipeline: pipelineFactory(latencyScale: latencyScale, cacheDirectory: temporaryDirectory()),
            metricsURL: metricsURL ?? temporaryDirectory().appendingPathComponent("metrics.jsonl"),
            submitReview: submitReview,
            canUseGitHubCLI: true
        )
    }

    private func wait(timeout: Duration = .seconds(30), until condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            if ContinuousClock.now > deadline { return false }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return true
    }

    @Test func loadingWithNoHarnessFailsInTheReviewersTermsAndKeepsTheURLForReopen() {
        let store = makeStore(harness: nil)
        store.navigate(to: .architecture)
        store.load(prURL: prURL)
        guard case .failed(let message) = store.phase else {
            Issue.record("expected a failed phase, got \(store.phase)")
            return
        }
        #expect(message.contains("No AI harness selected"))
        #expect(store.lastPRURL == prURL)
        #expect(store.harnessID == nil)
        #expect(store.current == .summary, "load resets navigation before resolving the harness")
        #expect(store.metrics?.pr == prURL)
    }

    @Test func theDefaultPipelineRejectsAnUnparseableURLWithoutTouchingTheNetwork() async {
        let defaults = UserDefaults(suiteName: "contour-graphstore-\(UUID().uuidString)")!
        let environment = [
            "CONTOUR_HARNESS": "claude", "CONTOUR_TRACKER": "none", "CONTOUR_GITHUB_ACCESS": "anonymous",
        ]
        let store = GraphStore(
            preferences: Preferences(defaults: defaults, environment: environment),
            metricsURL: temporaryDirectory().appendingPathComponent("metrics.jsonl"))

        store.load(prURL: "not a pull request")

        #expect(await wait { store.phase != .opening })
        guard case .failed = store.phase else {
            Issue.record("expected a failed phase, got \(store.phase)")
            return
        }
        store.close()
    }

    @Test func loadResetsEverythingTheReviewerHadOpen() {
        let store = makeStore(harness: nil)
        store.handle(.graph(ContourSampleData.publishTriggeredReindex))
        store.handle(.diff("diff --git a/x b/x\n--- a/x\n+++ b/x\n@@ -1 +1 @@\n-a\n+b\n"))
        store.handle(.log(PipelineProgressEntry(stage: "Fetch", detail: "started")))
        store.navigate(to: .decisions)
        store.focusedSubject = .decision("d")
        store.diagramMode = .after
        store.ask(about: .pullRequest)

        store.load(prURL: prURL)

        #expect(store.graph == nil)
        #expect(store.diffText == nil)
        #expect(store.diffFiles.isEmpty)
        #expect(store.progressLog.isEmpty)
        #expect(store.current == .summary)
        #expect(!store.canGoBack)
        #expect(store.focusedSubject == nil)
        #expect(store.diagramMode == .delta)
        #expect(store.review == .idle)
        #expect(store.conversations.active == nil)
        #expect(!store.analysis.isComplete)
    }

    @Test func aFullLoadOpensTheReviewCompletesTheAnalysisAndRecordsMetricsOnce() async throws {
        let directory = temporaryDirectory()
        let metricsURL = directory.appendingPathComponent("metrics.jsonl")
        let store = makeStore(metricsURL: metricsURL)

        store.load(prURL: prURL)
        #expect(store.phase == .opening)
        #expect(store.harnessID == .claude)

        let finished = await wait { store.analysis.isComplete }
        #expect(finished, "the mock analysis should run to completion")
        #expect(store.phase == .review)
        #expect(store.graph?.pr.number == 7)
        #expect(store.diffText == "diff")
        #expect(store.checkout?.headSha == "head1")
        #expect(!store.progressLog.isEmpty)
        #expect(store.metrics?.elapsed(.prShell) != nil)
        #expect(!store.canStopAnalysis, "a completed analysis has nothing left to stop")

        let lines = try String(contentsOf: metricsURL, encoding: .utf8).split(separator: "\n")
        #expect(lines.count == 1)
        #expect(lines.first?.contains("acme\\/shop\\/pull\\/7") == true)

        store.close()
        let afterClose = try String(contentsOf: metricsURL, encoding: .utf8).split(separator: "\n")
        #expect(afterClose.count == 1, "metrics are appended once per session")
        #expect(store.phase == .idle)
    }

    @Test func closingBeforeThePRShellArrivesWritesNoMetrics() {
        let metricsURL = temporaryDirectory().appendingPathComponent("metrics.jsonl")
        let store = makeStore(metricsURL: metricsURL)
        store.load(prURL: prURL)
        store.close()
        #expect(!FileManager.default.fileExists(atPath: metricsURL.path))
    }

    @Test func reopenLoadsTheLastPRAgain() async {
        let store = makeStore()
        store.load(prURL: prURL)
        #expect(await wait { store.phase == .review })
        store.navigate(to: .decisions)

        store.reopen()

        #expect(store.phase == .opening)
        #expect(store.lastPRURL == prURL)
        #expect(store.current == .summary)
        store.close()
    }

    @Test func retryOnALoadedSessionAsksThePipelineWithoutReopening() async {
        let store = makeStore()
        store.load(prURL: prURL)
        #expect(await wait { store.analysis.isComplete })

        store.retry(.architecture)

        #expect(store.phase == .review, "a checkout exists, so retry() must not fall back to reopen()")
        #expect(store.graph != nil)
        store.close()
    }

    @Test func stoppingARunningAnalysisSettlesEveryUnfinishedStage() async {
        let store = makeStore(latencyScale: 3)
        store.load(prURL: prURL)
        #expect(await wait { store.canStopAnalysis })

        store.stopAnalysis()

        #expect(await wait { store.analysis.isComplete })
        #expect(!store.analysis.stoppedSections.isEmpty)
        #expect(!store.canStopAnalysis)
        store.close()
    }

    @Test func submittingAnApprovalMarksItSubmittedAfterTheSubmitterReturns() async {
        let received = SubmissionLog()
        let store = makeStore(submitReview: { url, verdict, comment in
            await received.record(url: url, verdict: verdict, comment: comment)
        })
        store.load(prURL: prURL)
        #expect(await wait { store.phase == .review })

        store.submitReview(.approve)
        #expect(store.review == .submitting(.approve))

        #expect(await wait { store.review == .submitted(.approve) })
        let entries = await received.entries
        #expect(entries.count == 1)
        #expect(entries.first?.url == prURL)
        #expect(entries.first?.verdict == .approve)
        store.close()
    }

    @Test func aFailedSubmissionSurfacesTheErrorAndCanBeDismissed() async {
        let store = makeStore(submitReview: { _, _, _ in throw SubmitFailure() })
        store.load(prURL: prURL)
        #expect(await wait { store.phase == .review })

        store.submitReview(.requestChanges, comment: "please add a test")
        #expect(await wait { store.review == .failed(.requestChanges, "gh exploded") })

        store.dismissReviewFailure()
        #expect(store.review == .idle)
        store.close()
    }

    @Test func requestingChangesWithoutACommentNeverReachesTheSubmitter() async {
        let received = SubmissionLog()
        let store = makeStore(submitReview: { url, verdict, comment in
            await received.record(url: url, verdict: verdict, comment: comment)
        })
        store.load(prURL: prURL)
        #expect(await wait { store.phase == .review })

        store.submitReview(.requestChanges, comment: "   ")

        #expect(store.review == .idle)
        #expect(await received.entries.isEmpty)
        store.close()
    }

    @Test func aSubmissionResolvingAfterTheReviewerMovedToAnotherPRIsDiscarded() async {
        let gate = SubmissionGate()
        let store = makeStore(submitReview: { _, _, _ in await gate.wait() })
        store.load(prURL: prURL)
        #expect(await wait { store.phase == .review })

        store.submitReview(.approve)
        #expect(store.review == .submitting(.approve))

        store.load(prURL: "https://github.com/acme/shop/pull/8")
        await gate.open()
        try? await Task.sleep(for: .milliseconds(100))

        #expect(store.review != .submitted(.approve))
        store.close()
    }

    @Test func aFailedSubmissionResolvingAfterTheReviewerMovedToAnotherPRIsDiscarded() async {
        let gate = SubmissionGate()
        let store = makeStore(submitReview: { _, _, _ in
            await gate.wait()
            throw SubmitFailure()
        })
        store.load(prURL: prURL)
        #expect(await wait { store.phase == .review })

        store.submitReview(.approve)
        store.load(prURL: "https://github.com/acme/shop/pull/8")
        await gate.open()
        try? await Task.sleep(for: .milliseconds(100))

        #expect(store.review == .idle)
        store.close()
    }
}

private actor SubmissionLog {
    struct Entry {
        let url: String
        let verdict: PRReview.Verdict
        let comment: String
    }

    private(set) var entries: [Entry] = []

    func record(url: String, verdict: PRReview.Verdict, comment: String) {
        entries.append(Entry(url: url, verdict: verdict, comment: comment))
    }
}

private actor SubmissionGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}
