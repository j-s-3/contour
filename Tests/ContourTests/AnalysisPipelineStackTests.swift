import Foundation
import Testing

@testable import Contour

@Suite(.serialized)
struct AnalysisPipelineStackTests {
    private struct FakePRSource: PRSource {
        let describesItself = "fake (tests)"
        let context: RawPRContext
        func fetchContext(prURL: String) async throws -> RawPRContext { context }
        func fetchIssue(owner: String, repo: String, number: String) async -> RawIssue? { nil }
    }

    private func context() -> RawPRContext {
        RawPRContext(
            url: "https://github.com/acme/shop/pull/501", owner: "acme", repo: "shop", number: 501,
            title: "Layer 1", body: "", author: "someone", state: "OPEN", headRefName: "fix",
            baseRefName: "main", headSha: "head1", baseSha: "base1", isCrossRepository: false,
            headCloneURL: "https://github.com/acme/shop.git", additions: 3, deletions: 1, changedFiles: 2,
            files: ["a.rs"], commits: [], comments: [], reviews: [], diff: "diff")
    }

    private func stack(for ctx: RawPRContext) -> PRStack {
        let above = StackLayer(
            url: "https://github.com/acme/shop/pull/502", number: 502, title: "Layer 2", author: "someone",
            isDraft: false, headRefName: "fix-2", baseRefName: "fix", headSha: "head2", baseSha: "head1", size: nil)
        return PRStack(layers: [StackDiscovery.layer(from: ctx), above], currentIndex: 0)
    }

    private func tempCache() -> AnalysisCache {
        AnalysisCache(
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("contour-stack-pipeline-\(UUID().uuidString)", isDirectory: true))
    }

    private func pipeline(
        ctx: RawPRContext, cache: AnalysisCache, grace: Duration = .seconds(5),
        discover: @escaping @Sendable (RawPRContext) async -> PRStack?
    ) -> AnalysisPipeline {
        AnalysisPipeline(
            harnessID: .claude, trackerID: .none, cache: cache,
            prSourceOverride: FakePRSource(context: ctx),
            checkoutOverride: { fetched in
                let dir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("contour-stack-checkout-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                return RepoCheckout(rootDir: dir, headSha: fetched.headSha, baseSha: fetched.baseSha)
            },
            mockOverride: .init(),
            stackDiscoveryOverride: discover,
            stackDiscoveryGrace: grace)
    }

    private func drain(_ pipeline: AnalysisPipeline, untilStackAfterComplete: Bool = false) async -> [PipelineEvent] {
        var events: [PipelineEvent] = []
        var complete = false
        for await event in pipeline.events {
            events.append(event)
            switch event {
            case .complete, .fatal: complete = true
            default: break
            }
            if complete, !untilStackAfterComplete || stackEvent(events) != nil { return events }
        }
        return events
    }

    private func contextFile(_ events: [PipelineEvent]) throws -> String {
        var checkout: RepoCheckout?
        for case .checkout(let found) in events { checkout = found }
        let root = try #require(checkout).rootDir
        return try String(contentsOf: root.appendingPathComponent(PromptBuilder.contextFileName), encoding: .utf8)
    }

    private func stackEvent(_ events: [PipelineEvent]) -> (PRStack, Set<Int>)? {
        for case .stack(let stack, let cached) in events { return (stack, cached) }
        return nil
    }

    @Test func aDiscoveredStackIsEmittedAndWrittenIntoTheContextFile() async throws {
        let ctx = context()
        let stack = stack(for: ctx)
        let pipeline = pipeline(ctx: ctx, cache: tempCache()) { _ in stack }
        await pipeline.start(prURL: ctx.url)
        let events = await drain(pipeline)
        #expect(stackEvent(events)?.0 == stack)
        #expect(stackEvent(events)?.1 == [])
        #expect(try contextFile(events).contains("Stack: this pull request is part 1 of 2."))
    }

    @Test func noStackMeansNoEventAndAnUnchangedContextFile() async throws {
        let ctx = context()
        let pipeline = pipeline(ctx: ctx, cache: tempCache()) { _ in nil }
        await pipeline.start(prURL: ctx.url)
        let events = await drain(pipeline)
        #expect(stackEvent(events) == nil)
        #expect(!(try contextFile(events).contains("Stack:")))
    }

    @Test func slowDiscoveryDoesNotDelayTheAnalysisButStillArrives() async throws {
        let ctx = context()
        let stack = stack(for: ctx)
        let pipeline = pipeline(ctx: ctx, cache: tempCache(), grace: .milliseconds(20)) { _ in
            try? await Task.sleep(for: .milliseconds(400))
            return stack
        }
        await pipeline.start(prURL: ctx.url)
        let events = await drain(pipeline, untilStackAfterComplete: true)
        #expect(events.contains { if case .complete = $0 { true } else { false } })
        #expect(stackEvent(events)?.0 == stack)
        #expect(!(try contextFile(events).contains("Stack:")))
    }

    @Test func layersWithACompleteCachedAnalysisAreReportedAsCached() async throws {
        let ctx = context()
        let cache = tempCache()
        let stack = stack(for: ctx)
        var graph = PRGraph.shell(from: ctx)
        graph.pr.number = 502
        cache.save(
            owner: "acme", repo: "shop", number: 502, headSha: "head2", baseSha: "head1",
            pipelineVersion: AnalysisPipeline.pipelineVersion, graph: graph, diff: "",
            completedStages: Set(PipelineStage.analysis))
        let pipeline = pipeline(ctx: ctx, cache: cache) { _ in stack }
        await pipeline.start(prURL: ctx.url)
        let events = await drain(pipeline)
        #expect(stackEvent(events)?.1 == [502])
    }

    @Test func aPartiallyCachedLayerIsNotReportedAsCached() async throws {
        let ctx = context()
        let cache = tempCache()
        let stack = stack(for: ctx)
        var graph = PRGraph.shell(from: ctx)
        graph.pr.number = 502
        cache.save(
            owner: "acme", repo: "shop", number: 502, headSha: "head2", baseSha: "head1",
            pipelineVersion: AnalysisPipeline.pipelineVersion, graph: graph, diff: "",
            completedStages: [.behaviorChange])
        let pipeline = pipeline(ctx: ctx, cache: cache) { _ in stack }
        await pipeline.start(prURL: ctx.url)
        let events = await drain(pipeline)
        #expect(stackEvent(events)?.1 == [])
    }

    @Test func cancellingThePipelineDropsAPendingDiscovery() async throws {
        let ctx = context()
        let stack = stack(for: ctx)
        let pipeline = pipeline(ctx: ctx, cache: tempCache(), grace: .milliseconds(20)) { _ in
            try? await Task.sleep(for: .milliseconds(300))
            return stack
        }
        await pipeline.start(prURL: ctx.url)
        let events = await drain(pipeline)
        await pipeline.cancel()
        try? await Task.sleep(for: .milliseconds(500))
        #expect(stackEvent(events) == nil)
    }
}
