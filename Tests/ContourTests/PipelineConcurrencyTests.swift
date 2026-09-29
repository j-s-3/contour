import Foundation
import Testing
@testable import Contour

@Suite(.serialized)
struct PipelineConcurrencyTests {
    private func context(number: Int, head: String) -> RawPRContext {
        RawPRContext(
            url: "https://github.com/acme/shop/pull/\(number)", owner: "acme", repo: "shop", number: number,
            title: "Detect binary content", body: "", author: "someone", state: "OPEN", headRefName: "fix",
            baseRefName: "main", headSha: head, baseSha: "base1", isCrossRepository: false,
            headCloneURL: "https://github.com/acme/shop.git", additions: 3, deletions: 1, changedFiles: 2,
            files: ["a.rs"], commits: [], comments: [], reviews: [], diff: "diff"
        )
    }

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

    private func makePipeline(source: FakePRSource, cache: AnalysisCache,
                              previousRevision: AnalysisCache.Entry? = nil,
                              mock: AnalysisService.MockOptions = AnalysisService.MockOptions()) -> AnalysisPipeline {
        AnalysisPipeline(
            harnessID: .claude, trackerID: .none, cache: cache,
            prSourceOverride: source,
            checkoutOverride: { fetchedCtx in
                let dir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("contour-checkout-\(fetchedCtx.number)-\(fetchedCtx.headSha)-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                return RepoCheckout(rootDir: dir, headSha: fetchedCtx.headSha, baseSha: fetchedCtx.baseSha, symbolIndexPath: nil)
            },
            previousRevisionOverride: previousRevision,
            mockOverride: mock
        )
    }

    private let paced = AnalysisService.MockOptions(latencyScale: 0.05)

    private func withMockAnalysis<T>(_ body: () async throws -> T) async throws -> T {
        try await body()
    }

    private func decisionsFixture() throws -> [DecisionNode] {
        try StageDecoding.decode(StageDecoding.DecisionsResult.self, from: MockAnalysisFixtures.response(for: .decisions)).decisions
    }

    @Test func stoppingMidStreamLeavesNoTornOrDuplicateDecisions() async throws {
        let ctx = context(number: 101, head: "head1")
        let cache = try tempCache()
        let pipeline = makePipeline(source: FakePRSource(ctx), cache: cache, mock: paced)
        let fixtureCount = try decisionsFixture().count

        try await withMockAnalysis {
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

    @Test func retryingRepeatedlySettlesOnceWithNoDuplicateDecisions() async throws {
        let ctx = context(number: 102, head: "head1")
        let cache = try tempCache()
        let pipeline = makePipeline(source: FakePRSource(ctx), cache: cache, mock: paced)
        let fixtureCount = try decisionsFixture().count

        try await withMockAnalysis {
            await pipeline.start(prURL: ctx.url)

            stopping: for await event in pipeline.events {
                if case .status(.decisions, let status) = event, status.isRunning {
                    await pipeline.stop()
                    break stopping
                }
            }

            waitingForStop: for await event in pipeline.events {
                if case .status(.decisions, .stopped) = event { break waitingForStop }
                if case .complete = event { break waitingForStop }
            }

            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<5 { group.addTask { await pipeline.retry(.decisions) } }
            }

            var lastGraph: PRGraph?
            var finalStatus: StageStatus = .pending
            var sawRetryRunning = false
            settling: for await event in pipeline.events {
                switch event {
                case .graph(let g): lastGraph = g
                case .status(.decisions, let status):
                    finalStatus = status
                    if status.isRunning { sawRetryRunning = true }
                case .complete: if sawRetryRunning { break settling }
                default: break
                }
            }

            let decisions = lastGraph?.decisions ?? []
            #expect(finalStatus == .done, "settles to done, not left mid-retry: \(finalStatus)")
            #expect(decisions.count == fixtureCount)
            #expect(Set(decisions.map(\.id)).count == fixtureCount, "no duplicate decisions from overlapping retries")
        }
    }

    @Test func startingASecondPRMidRunNeverLeaksTheFirstRunsEvents() async throws {
        let ctxA = context(number: 201, head: "headA")
        let ctxB = context(number: 202, head: "headB")
        let cache = try tempCache()
        let pipeline = makePipeline(source: FakePRSource([ctxA, ctxB]), cache: cache, mock: paced)

        try await withMockAnalysis {
            await pipeline.start(prURL: ctxA.url)

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

    @Test func cancellingDuringCheckoutPublishesNothingAfterAndNeverReachesAnalysis() async throws {
        let ctx = context(number: 301, head: "head1")
        let cache = try tempCache()
        let pipeline = AnalysisPipeline(
            harnessID: .claude, trackerID: .none, cache: cache,
            prSourceOverride: FakePRSource(ctx),
            checkoutOverride: { fetchedCtx in
                try await Task.sleep(for: .milliseconds(300))
                let dir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("contour-checkout-\(fetchedCtx.number)-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                return RepoCheckout(rootDir: dir, headSha: fetchedCtx.headSha, baseSha: fetchedCtx.baseSha, symbolIndexPath: nil)
            },
            mockOverride: AnalysisService.MockOptions()
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

            let all = events + afterCancel
            #expect(!all.contains { if case .checkout = $0 { return true }; return false },
                    "checkout never completed, so no .checkout event should have been published")
            #expect(!afterCancel.contains { if case .graph = $0 { return true }; return false },
                    "no graph snapshot is published after cancel()")
            #expect(!all.contains {
                        if case .status(let stage, let status) = $0 { return status.isRunning && PipelineStage.analysis.contains(stage) }
                        return false
                    }, "cancelling during checkout must mean no analysis stage ever started")
        }
    }

    @Test func staleWhileRevalidateClearsWithoutMixingWhenTheFreshStageFails() async throws {
        let oldCtx = context(number: 401, head: "head1")
        let newCtx = context(number: 401, head: "head2")
        let cache = try tempCache()

        var previousGraph = PRGraph.shell(from: oldCtx)
        previousGraph.decisions = try decisionsFixture()
        let previousEntry = AnalysisCache.Entry(graph: previousGraph, diff: oldCtx.diff, completedStages: [.decisions])

        let pipeline = makePipeline(source: FakePRSource(newCtx), cache: cache, previousRevision: previousEntry,
                                    mock: AnalysisService.MockOptions(failStage: .decisions))

        try await withMockAnalysis {
            await pipeline.start(prURL: newCtx.url)

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
