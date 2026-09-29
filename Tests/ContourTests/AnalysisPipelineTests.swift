import Foundation
import Testing

@testable import Contour

@Suite(.serialized)
struct AnalysisPipelineTests {
    private func context(number: Int = 501, head: String = "head1", body: String = "") -> RawPRContext {
        RawPRContext(
            url: "https://github.com/acme/shop/pull/\(number)", owner: "acme", repo: "shop", number: number,
            title: "Detect binary content", body: body, author: "someone", state: "OPEN", headRefName: "fix",
            baseRefName: "main", headSha: head, baseSha: "base1", isCrossRepository: false,
            headCloneURL: "https://github.com/acme/shop.git", additions: 3, deletions: 1, changedFiles: 2,
            files: ["a.rs"], commits: [], comments: [], reviews: [], diff: "diff"
        )
    }

    private struct FakePRSource: PRSource {
        let describesItself = "fake (tests)"
        let context: RawPRContext?
        func fetchContext(prURL: String) async throws -> RawPRContext {
            guard let context else { throw GitHubServiceError.badURL(prURL) }
            return context
        }
        func fetchIssue(owner: String, repo: String, number: String) async -> RawIssue? { nil }
    }

    private struct CheckoutFailure: Error {}

    private func tempCache() -> AnalysisCache {
        AnalysisCache(
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("contour-pipeline-tests-\(UUID().uuidString)", isDirectory: true))
    }

    private static func makeCheckout(for ctx: RawPRContext) throws -> RepoCheckout {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("contour-pipeline-checkout-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return RepoCheckout(rootDir: dir, headSha: ctx.headSha, baseSha: ctx.baseSha, symbolIndexPath: nil)
    }

    private func pipeline(
        ctx: RawPRContext?, cache: AnalysisCache, trackerID: TrackerID = .none,
        previous: AnalysisCache.Entry? = nil, mock: AnalysisService.MockOptions = .init(),
        failCheckout: Bool = false
    ) -> AnalysisPipeline {
        AnalysisPipeline(
            harnessID: .claude, trackerID: trackerID, cache: cache,
            prSourceOverride: FakePRSource(context: ctx),
            checkoutOverride: { fetched in
                if failCheckout { throw CheckoutFailure() }
                return try Self.makeCheckout(for: fetched)
            },
            previousRevisionOverride: previous,
            mockOverride: mock
        )
    }

    private func drain(_ pipeline: AnalysisPipeline) async -> [PipelineEvent] {
        var events: [PipelineEvent] = []
        for await event in pipeline.events {
            events.append(event)
            switch event {
            case .complete, .fatal: return events
            default: continue
            }
        }
        return events
    }

    private func logs(_ events: [PipelineEvent]) -> [String] {
        events.compactMap {
            if case .log(let entry) = $0 { return "\(entry.stage): \(entry.detail)" }
            return nil
        }
    }

    private func finalStatuses(_ events: [PipelineEvent]) -> [PipelineStage: StageStatus] {
        var result: [PipelineStage: StageStatus] = [:]
        for case .status(let stage, let status) in events { result[stage] = status }
        return result
    }

    private func finalGraph(_ events: [PipelineEvent]) -> PRGraph? {
        var graph: PRGraph?
        for case .graph(let g) in events { graph = g }
        return graph
    }

    private func sawFromCache(_ events: [PipelineEvent]) -> Bool {
        events.contains {
            if case .fromCache = $0 { return true }
            return false
        }
    }

    private func sawFatal(_ events: [PipelineEvent]) -> Bool {
        events.contains {
            if case .fatal = $0 { return true }
            return false
        }
    }

    @Test func aFullRunSettlesEveryStageAndReportsTheSummary() async {
        let ctx = context()
        let p = pipeline(ctx: ctx, cache: tempCache())
        await p.start(prURL: ctx.url)
        let events = await drain(p)
        let statuses = finalStatuses(events)
        for stage in PipelineStage.analysis { #expect(statuses[stage] == .done, "\(stage)") }
        #expect(statuses[.ticket] == .done)
        #expect(logs(events).contains { $0.hasPrefix("Done: ") && $0.contains("decisions") })
        #expect(logs(events).contains("Fetching PR: via fake (tests)"))
        #expect(logs(events).contains("Checking issue tracker: issue lookup is turned off"))
        #expect(finalGraph(events)?.decisions.isEmpty == false)
    }

    @Test func aSecondRunOfTheSameCommitIsServedFromTheCache() async {
        let ctx = context(number: 502)
        let cache = tempCache()
        let first = pipeline(ctx: ctx, cache: cache)
        await first.start(prURL: ctx.url)
        let firstEvents = await drain(first)
        #expect(finalStatuses(firstEvents)[.judgment] == .done)

        let second = pipeline(ctx: ctx, cache: cache)
        await second.start(prURL: ctx.url)
        let events = await drain(second)
        #expect(sawFromCache(events))
        #expect(logs(events).contains { $0.hasPrefix("Checking cache: using cached analysis") })
        #expect(!finalStatuses(events).values.contains { $0.isRunning })
    }

    @Test func aPartialCacheResumesOnlyTheMissingStages() async throws {
        let ctx = context(number: 503)
        let cache = tempCache()
        var graph = PRGraph.shell(from: ctx)
        graph.decisions = try StageDecoding.decode(
            StageDecoding.DecisionsResult.self, from: MockAnalysisFixtures.response(for: .decisions)
        ).decisions
        cache.save(
            owner: ctx.owner, repo: ctx.repo, number: ctx.number, headSha: ctx.headSha, baseSha: ctx.baseSha,
            pipelineVersion: AnalysisPipeline.pipelineVersion, graph: graph, diff: ctx.diff,
            completedStages: [.decisions])

        let p = pipeline(ctx: ctx, cache: cache)
        await p.start(prURL: ctx.url)
        let events = await drain(p)
        #expect(logs(events).contains { $0.contains("resuming a partial analysis — 5 stage(s) still to run") })
        let statuses = finalStatuses(events)
        for stage in PipelineStage.analysis { #expect(statuses[stage] == .done, "\(stage)") }
        #expect(!logs(events).contains("Extracting decisions: reading changed code"), "a cached stage is not re-run")
    }

    @Test func aMovedHeadShowsTheOldSliceAsStaleThenClearsTheRevalidation() async throws {
        let oldCtx = context(number: 504, head: "old")
        let newCtx = context(number: 504, head: "new")
        var previousGraph = PRGraph.shell(from: oldCtx)
        previousGraph.decisions = try StageDecoding.decode(
            StageDecoding.DecisionsResult.self, from: MockAnalysisFixtures.response(for: .decisions)
        ).decisions
        let entry = AnalysisCache.Entry(graph: previousGraph, diff: oldCtx.diff, completedStages: [.decisions])

        let p = pipeline(ctx: newCtx, cache: tempCache(), previous: entry, mock: .init(latencyScale: 0.05))
        await p.start(prURL: newCtx.url)
        let events = await drain(p)
        var heads: [String?] = []
        for case .revalidating(let head) in events { heads.append(head) }
        #expect(heads == ["old", nil])
        #expect(logs(events).contains { $0.contains("showing the analysis of old while this revision is analyzed") })
    }

    @Test func aFailedStageIsReportedAndRetryRerunsOnlyThatStage() async {
        let ctx = context(number: 505)
        let p = pipeline(ctx: ctx, cache: tempCache(), mock: .init(failStage: .architecture))
        await p.start(prURL: ctx.url)
        let events = await drain(p)
        #expect(finalStatuses(events)[.architecture]?.failure != nil)
        #expect(logs(events).contains { $0.hasPrefix("Analyzing architecture: failed:") })
        #expect(logs(events).contains { $0.hasPrefix("Done: ") && $0.contains("failed: Architecture") })

        await p.retry(.architecture)
        var retried: [StageStatus] = []
        retrying: for await event in p.events {
            switch event {
            case .status(.architecture, let status): retried.append(status)
            case .complete: break retrying
            default: continue
            }
        }
        #expect(retried.contains { $0.isRunning })
        #expect(retried.last == .done, "the mock fails a stage once, so the retry succeeds")
    }

    @Test func retryIgnoresStagesThatCannotBeRetried() async {
        let ctx = context(number: 506)
        let p = pipeline(ctx: ctx, cache: tempCache())
        await p.retry(.decisions)
        await p.start(prURL: ctx.url)
        let events = await drain(p)
        await p.retry(.decisions)
        await p.retry(.fetching)
        #expect(finalStatuses(events)[.decisions] == .done)
    }

    @Test func retryingUnderstandingAfterAFailureCompletesTheRun() async {
        let ctx = context(number: 507)
        let p = pipeline(ctx: ctx, cache: tempCache(), mock: .init(failStage: .understanding))
        await p.start(prURL: ctx.url)
        let first = await drain(p)
        #expect(finalStatuses(first)[.understanding]?.failure != nil)
        await p.retry(.understanding)
        var last: StageStatus?
        retrying: for await event in p.events {
            switch event {
            case .status(.understanding, let status): last = status
            case .complete: break retrying
            default: continue
            }
        }
        #expect(last == .done)
    }

    @Test func aFetchFailureIsFatal() async {
        let p = pipeline(ctx: nil, cache: tempCache())
        await p.start(prURL: "https://github.com/acme/shop/pull/1")
        let events = await drain(p)
        #expect(sawFatal(events))
        #expect(finalStatuses(events)[.checkingOut] == nil)
    }

    @Test func aCheckoutFailureIsFatalAndNeverStartsAnalysis() async {
        let ctx = context(number: 508)
        let p = pipeline(ctx: ctx, cache: tempCache(), failCheckout: true)
        await p.start(prURL: ctx.url)
        let events = await drain(p)
        #expect(sawFatal(events))
        #expect(finalStatuses(events)[.decisions] == nil)
    }

    @Test func theOfflineEntryPointRunsWithoutFetchingOrCheckingOut() async throws {
        let ctx = context(number: 509)
        let checkout = try Self.makeCheckout(for: ctx)
        let p = pipeline(ctx: ctx, cache: tempCache())
        await p.start(offlineContext: ctx, checkout: checkout)
        let events = await drain(p)
        #expect(!logs(events).contains { $0.hasPrefix("Fetching PR") })
        let statuses = finalStatuses(events)
        for stage in PipelineStage.analysis { #expect(statuses[stage] == .done, "\(stage)") }
    }

    @Test func theOfflineEntryPointHonoursTheCacheWhenNotForced() async throws {
        let ctx = context(number: 510)
        let cache = tempCache()
        let first = pipeline(ctx: ctx, cache: cache)
        await first.start(offlineContext: ctx, checkout: try Self.makeCheckout(for: ctx))
        _ = await drain(first)

        let second = pipeline(ctx: ctx, cache: cache)
        await second.start(offlineContext: ctx, checkout: try Self.makeCheckout(for: ctx), forceRefresh: false)
        let events = await drain(second)
        #expect(sawFromCache(events))
    }

    @Test func forceRefreshIgnoresAnExistingCacheEntry() async {
        let ctx = context(number: 511)
        let cache = tempCache()
        let first = pipeline(ctx: ctx, cache: cache)
        await first.start(prURL: ctx.url)
        _ = await drain(first)

        let second = pipeline(ctx: ctx, cache: cache)
        await second.start(prURL: ctx.url, forceRefresh: true)
        let events = await drain(second)
        #expect(!sawFromCache(events))
        #expect(finalStatuses(events)[.judgment] == .done)
    }

    @Test func stoppingMidRunLogsWhatWasStopped() async {
        let ctx = context(number: 512)
        let p = pipeline(ctx: ctx, cache: tempCache(), mock: .init(latencyScale: 0.5))
        await p.start(prURL: ctx.url)
        var events: [PipelineEvent] = []
        var stopped = false
        for await event in p.events {
            events.append(event)
            if !stopped, case .status(let stage, let status) = event, status.isRunning,
                PipelineStage.analysis.contains(stage)
            {
                stopped = true
                await p.stop()
            }
            if case .complete = event { break }
        }
        #expect(logs(events).contains { $0.hasPrefix("Stopped: stopped by the reviewer:") })
        #expect(logs(events).contains { $0.hasPrefix("Done: ") && $0.contains("stopped:") })
    }

    @Test func stoppingBeforeAnyStageRunsMarksEveryUnsettledStageStopped() async {
        let p = pipeline(ctx: context(), cache: tempCache())
        await p.stop()
        await p.cancel()
        var events: [PipelineEvent] = []
        for await event in p.events { events.append(event) }
        let statuses = finalStatuses(events)
        for stage in PipelineStage.analysis { #expect(statuses[stage] == .stopped, "\(stage)") }
        #expect(statuses[.ticket] == .done)
    }

    @Test func aGitHubTrackerLogsWhenThePRReferencesNoIssue() async {
        let ctx = context(number: 513, body: "no references at all")
        let p = AnalysisPipeline(
            harnessID: .claude, trackerID: .github, githubAccess: .anonymous, cache: tempCache(),
            prSourceOverride: FakePRSource(context: ctx),
            checkoutOverride: { try Self.makeCheckout(for: $0) },
            mockOverride: .init())
        await p.start(prURL: ctx.url)
        let events = await drain(p)
        #expect(logs(events).contains("Checking issue tracker: no reference found in title/body/branch/commits"))
    }

    @Test func aJiraTrackerLogsWhenThePRNamesNoTicket() async {
        let ctx = context(number: 514, body: "no ticket here")
        let p = pipeline(ctx: ctx, cache: tempCache(), trackerID: .jira)
        await p.start(prURL: ctx.url)
        let events = await drain(p)
        #expect(logs(events).contains("Checking issue tracker: no reference found in title/body/branch/commits"))
    }
}
