import Foundation
import Testing
@testable import Contour

/// Race and cancellation coverage for `AnalysisPipeline` itself (issue: run the suite under
/// Thread Sanitizer and add tests for Stop/Retry races): Stop mid-stream, Retry spam, a
/// second `start()` racing the first, cancelling during checkout, and stale-while-revalidate
/// clearing rather than mixing when the fresh stage fails.
///
/// Driven with the mock harness and its existing latency/failure hooks
/// (`CONTOUR_MOCK_ANALYSIS`, `CONTOUR_MOCK_LATENCY`, `CONTOUR_MOCK_FAIL_STAGE` — see
/// `StopAnalysisTests` and `ProgressiveAnalysisTests`), plus three test-only seams on
/// `AnalysisPipeline` (`prSourceOverride`, `checkoutOverride`, `previousRevisionOverride`)
/// that stand in for the network fetch, the git checkout, and the cache's "previous
/// revision" lookup — the last of which `AnalysisCache` itself bypasses entirely under
/// `CONTOUR_MOCK_ANALYSIS=1` (see its doc comment), so there's no other way to exercise
/// stale-while-revalidate without a real model. Every seam stays nil in production.
///
/// Every test reacts to the pipeline's own events (a status change, a graph snapshot,
/// `.complete`) rather than sleeping for a fixed duration, so ordering is deterministic even
/// though `CONTOUR_MOCK_LATENCY` uses real `Task.sleep` under the hood to pace streamed
/// stages enough to be caught mid-flight.
///
/// `.serialized`: every test here toggles the process-wide `CONTOUR_MOCK_*` environment
/// variables that `AnalysisService` reads on every call, so two of these tests must never
/// run at once. No other file in the suite touches those same variables from a `@Test` (only
/// from `XCTestCase`s, which don't run concurrently with Swift Testing's own tests).
@Suite(.serialized)
struct PipelineConcurrencyTests {

    // MARK: - Fixtures

    private func context(number: Int, head: String) -> RawPRContext {
        RawPRContext(
            url: "https://github.com/acme/shop/pull/\(number)", owner: "acme", repo: "shop", number: number,
            title: "Detect binary content", body: "", author: "someone", state: "OPEN", headRefName: "fix",
            baseRefName: "main", headSha: head, baseSha: "base1", isCrossRepository: false,
            headCloneURL: "https://github.com/acme/shop.git", additions: 3, deletions: 1, changedFiles: 2,
            files: ["a.rs"], commits: [], comments: [], reviews: [], diff: "diff"
        )
    }

    /// Stands in for a real GitHub fetch: hands back a fixed context per URL instead of
    /// hitting the network.
    private struct FakePRSource: PRSource {
        let describesItself = "fake (tests)"
        let contexts: [String: RawPRContext]
        init(_ context: RawPRContext) { contexts = [context.url: context] }
        init(_ contexts: [RawPRContext]) { self.contexts = Dictionary(uniqueKeysWithValues: contexts.map { ($0.url, $0) }) }
        func fetchContext(prURL: String) async throws -> RawPRContext {
            guard let ctx = contexts[prURL] else { throw GitHubServiceError.badURL(prURL) }
            return ctx
        }
        func fetchIssue(owner: String, repo: String, number: String) async -> RawIssue? { nil }
    }

    private func tempCache() throws -> AnalysisCache {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("contour-pipeline-cache-\(UUID().uuidString)", isDirectory: true)
        return AnalysisCache(directory: dir)
    }

    /// A pipeline wired to a fake source and an empty temp checkout directory — mock
    /// analysis never reads real files, and `CodeRefVerifier` simply leaves refs it can't
    /// resolve unverified rather than failing, so the checkout's contents never matter here.
    private func makePipeline(source: FakePRSource, cache: AnalysisCache,
                              previousRevision: AnalysisCache.Entry? = nil) -> AnalysisPipeline {
        AnalysisPipeline(
            harnessID: .claude, trackerID: .none, cache: cache,
            prSourceOverride: source,
            checkoutOverride: { fetchedCtx in
                let dir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("contour-checkout-\(fetchedCtx.number)-\(fetchedCtx.headSha)-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                return RepoCheckout(rootDir: dir, headSha: fetchedCtx.headSha, baseSha: fetchedCtx.baseSha, symbolIndexPath: nil)
            },
            previousRevisionOverride: previousRevision
        )
    }

    /// `CONTOUR_MOCK_ANALYSIS=1`, with just enough `CONTOUR_MOCK_LATENCY` (when given) that a
    /// streamed stage's elements land one at a time instead of all at once — the signal a
    /// test reacts to instead of a blind sleep. `failStage`, when given, fails that stage
    /// exactly once: `AnalysisService`'s own fail-once bookkeeping is a process-wide
    /// singleton, so each stage here is used to trigger a failure by at most one test in this
    /// file (`.decisions`, in `staleWhileRevalidateClearsWithoutMixingWhenTheFreshStageFails`).
    private func withMockAnalysis<T>(latency: String? = nil, failStage: PipelineStage? = nil,
                                     _ body: () async throws -> T) async throws -> T {
        setenv("CONTOUR_MOCK_ANALYSIS", "1", 1)
        if let latency { setenv("CONTOUR_MOCK_LATENCY", latency, 1) } else { unsetenv("CONTOUR_MOCK_LATENCY") }
        if let failStage { setenv("CONTOUR_MOCK_FAIL_STAGE", "\(failStage)", 1) } else { unsetenv("CONTOUR_MOCK_FAIL_STAGE") }
        defer {
            unsetenv("CONTOUR_MOCK_ANALYSIS")
            unsetenv("CONTOUR_MOCK_LATENCY")
            unsetenv("CONTOUR_MOCK_FAIL_STAGE")
        }
        return try await body()
    }

    private func decisionsFixture() throws -> [DecisionNode] {
        try StageDecoding.decode(StageDecoding.DecisionsResult.self, from: MockAnalysisFixtures.response(for: .decisions)).decisions
    }

    // MARK: - Stop mid-stream

    /// Stopping while a streamed decision is being applied: the graph ends up holding either
    /// the element or not — never a duplicate, never torn — and the stage settles rather than
    /// being left running.
    @Test func stoppingMidStreamLeavesNoTornOrDuplicateDecisions() async throws {
        let ctx = context(number: 101, head: "head1")
        let cache = try tempCache()
        let pipeline = makePipeline(source: FakePRSource(ctx), cache: cache)
        let fixtureCount = try decisionsFixture().count

        try await withMockAnalysis(latency: "0.05") {
            await pipeline.start(prURL: ctx.url)

            var lastGraph: PRGraph?
            var decisionsStatus: StageStatus = .pending
            var sawFirstElement = false
            loop: for await event in pipeline.events {
                switch event {
                case .graph(let g):
                    lastGraph = g
                case .status(.decisions, let status):
                    decisionsStatus = status
                    if !sawFirstElement, case .running(let detail) = status, detail != nil {
                        sawFirstElement = true
                        await pipeline.stop()
                    }
                case .complete:
                    break loop
                default:
                    break
                }
            }

            #expect(sawFirstElement, "precondition: at least one decision streamed before stopping")
            let decisions = lastGraph?.decisions ?? []
            #expect(Set(decisions.map(\.id)).count == decisions.count, "no duplicate decisions")
            #expect(decisions.count <= fixtureCount, "never more than the stage could produce")
            #expect(decisionsStatus == .stopped || decisionsStatus == .done,
                    "settled one way or the other, never left running: \(decisionsStatus)")
        }
    }

    // MARK: - Retry spam

    /// Retry called repeatedly on the same stage: only the newest run is ever in flight (see
    /// `retry(_:)`'s cancel-before-replace), so it settles once, done, with no duplicate
    /// elements from overlapping attempts.
    @Test func retryingRepeatedlySettlesOnceWithNoDuplicateDecisions() async throws {
        let ctx = context(number: 102, head: "head1")
        let cache = try tempCache()
        let pipeline = makePipeline(source: FakePRSource(ctx), cache: cache)
        let fixtureCount = try decisionsFixture().count

        try await withMockAnalysis(latency: "0.05") {
            await pipeline.start(prURL: ctx.url)

            // Stop as soon as decisions starts streaming, before it can finish — `retry`
            // only accepts a stage that has failed or stopped.
            stopping: for await event in pipeline.events {
                if case .status(.decisions, let status) = event, status.isRunning {
                    await pipeline.stop()
                    break stopping
                }
            }

            // Wait for the stop to actually land before spamming Retry — spamming while it's
            // still `.running` is the already-covered case of `retry`'s own guard rejecting it.
            waitingForStop: for await event in pipeline.events {
                if case .status(.decisions, .stopped) = event { break waitingForStop }
                if case .complete = event { break waitingForStop }
            }

            // Retry mashed several times back to back, concurrently rather than one at a
            // time, to actually exercise the race rather than serialize around it.
            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<5 { group.addTask { await pipeline.retry(.decisions) } }
            }

            var lastGraph: PRGraph?
            var finalStatus: StageStatus = .pending
            settling: for await event in pipeline.events {
                switch event {
                case .graph(let g): lastGraph = g
                case .status(.decisions, let status): finalStatus = status
                case .complete: break settling
                default: break
                }
            }

            let decisions = lastGraph?.decisions ?? []
            #expect(finalStatus == .done, "settles to done, not left mid-retry: \(finalStatus)")
            #expect(decisions.count == fixtureCount)
            #expect(Set(decisions.map(\.id)).count == fixtureCount, "no duplicate decisions from overlapping retries")
        }
    }

    // MARK: - A second PR mid-run

    /// `start` called for a second PR while the first is mid-run: the first run's events —
    /// in particular its graph snapshots — never reach the session that opens after it.
    @Test func startingASecondPRMidRunNeverLeaksTheFirstRunsEvents() async throws {
        let ctxA = context(number: 201, head: "headA")
        let ctxB = context(number: 202, head: "headB")
        let cache = try tempCache()
        let pipeline = makePipeline(source: FakePRSource([ctxA, ctxB]), cache: cache)

        try await withMockAnalysis(latency: "0.05") {
            await pipeline.start(prURL: ctxA.url)

            // Let A genuinely get into analysis — not just fetched — before switching.
            startingB: for await event in pipeline.events {
                if case .status(let stage, let status) = event, status.isRunning, PipelineStage.analysis.contains(stage) {
                    break startingB
                }
            }

            await pipeline.start(prURL: ctxB.url)

            var sawA = false
            var lastGraph: PRGraph?
            settling: for await event in pipeline.events {
                if case .graph(let g) = event {
                    lastGraph = g
                    if g.pr.number == ctxA.number { sawA = true }
                }
                if case .complete = event { break settling }
            }

            #expect(!sawA, "no graph snapshot for the first PR was published after the second PR's start()")
            #expect(lastGraph?.pr.number == ctxB.number)
            #expect(lastGraph?.pr.headSha == ctxB.headSha)
        }
    }

    // MARK: - Cancel during checkout

    /// Cancelling while the checkout is still running: `cancel()` closes the stream for
    /// good, no `.checkout` event ever lands, and no analysis stage starts — no partial
    /// checkout state is ever treated as valid.
    @Test func cancellingDuringCheckoutPublishesNothingAfterAndNeverReachesAnalysis() async throws {
        let ctx = context(number: 301, head: "head1")
        let cache = try tempCache()
        let pipeline = AnalysisPipeline(
            harnessID: .claude, trackerID: .none, cache: cache,
            prSourceOverride: FakePRSource(ctx),
            checkoutOverride: { fetchedCtx in
                // Slow enough that the test can react to "checkout started" and cancel well
                // before it would ever complete.
                try await Task.sleep(for: .milliseconds(300))
                let dir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("contour-checkout-\(fetchedCtx.number)-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                return RepoCheckout(rootDir: dir, headSha: fetchedCtx.headSha, baseSha: fetchedCtx.baseSha, symbolIndexPath: nil)
            }
        )

        try await withMockAnalysis {
            await pipeline.start(prURL: ctx.url)

            var events: [PipelineEvent] = []
            waitingForCheckout: for await event in pipeline.events {
                events.append(event)
                if case .status(.checkingOut, let status) = event, status.isRunning {
                    await pipeline.cancel()
                    break waitingForCheckout
                }
            }

            var afterCancel: [PipelineEvent] = []
            for await event in pipeline.events { afterCancel.append(event) }

            #expect(afterCancel.isEmpty, "cancel() closes the stream for good; nothing more should ever arrive")
            #expect(!events.contains { if case .checkout = $0 { return true }; return false },
                    "checkout never completed, so no .checkout event should have been published")
            #expect(!events.contains {
                        if case .status(let stage, let status) = $0 { return status.isRunning && PipelineStage.analysis.contains(stage) }
                        return false
                    }, "cancelling during checkout must mean no analysis stage ever started")
        }
    }

    // MARK: - Stale-while-revalidate

    /// The fresh stage failing after a stale slice was shown: the stale slice is cleared, not
    /// mixed with (nonexistent) new output, and the reviewer sees a failure rather than a
    /// slice from a revision that no longer exists.
    @Test func staleWhileRevalidateClearsWithoutMixingWhenTheFreshStageFails() async throws {
        let oldCtx = context(number: 401, head: "head1")
        let newCtx = context(number: 401, head: "head2") // same PR, a new commit
        let cache = try tempCache()

        var previousGraph = PRGraph.shell(from: oldCtx)
        previousGraph.decisions = try decisionsFixture()
        let previousEntry = AnalysisCache.Entry(graph: previousGraph, diff: oldCtx.diff, completedStages: [.decisions])

        let pipeline = makePipeline(source: FakePRSource(newCtx), cache: cache, previousRevision: previousEntry)

        try await withMockAnalysis(failStage: .decisions) {
            await pipeline.start(prURL: newCtx.url)

            // `.revalidating` fires twice here: once with the earlier head, when the stale
            // slice is first shown, and again with nil once every stale stage has settled —
            // this one included, since a failure also clears a stage out of `stale` (§13).
            var revalidatingHeads: [String?] = []
            var sawStaleDecisions = false
            var lastGraph: PRGraph?
            var decisionsStatus: StageStatus = .pending
            loop: for await event in pipeline.events {
                switch event {
                case .revalidating(let fromHead):
                    revalidatingHeads.append(fromHead)
                case .graph(let g):
                    lastGraph = g
                    if !sawStaleDecisions, !g.decisions.isEmpty { sawStaleDecisions = true }
                case .status(.decisions, let status):
                    decisionsStatus = status
                case .complete:
                    break loop
                default:
                    break
                }
            }

            #expect(revalidatingHeads.first == oldCtx.headSha, "shown against the previous revision first")
            #expect(sawStaleDecisions, "precondition: the stale slice was shown at all")
            #expect(decisionsStatus.failure != nil, "expected .decisions to fail; got \(decisionsStatus)")
            #expect(lastGraph?.decisions.isEmpty == true,
                    "the stale slice is cleared, not left standing in for a failed fresh stage")
        }
    }
}
