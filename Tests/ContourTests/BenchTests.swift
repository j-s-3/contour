import XCTest
@testable import Contour

final class BenchTests: XCTestCase {
    private struct BenchRun {
        var corpus: BenchCorpus
        var files: Int
        var diffBytes: Int
        var metrics: AnalysisMetrics
    }

    func testLatencyAcrossFixtureCorpusSizes() async throws {
        setenv("CONTOUR_MOCK_ANALYSIS", "1", 1)
        unsetenv("CONTOUR_MOCK_LATENCY")
        unsetenv("CONTOUR_MOCK_FAIL_STAGE")
        defer { unsetenv("CONTOUR_MOCK_ANALYSIS") }

        var runs: [BenchRun] = []
        for corpus in BenchCorpus.allCases {
            let fixture = try BenchFixtures.make(corpus)
            defer { try? FileManager.default.removeItem(at: fixture.rootDir) }
            let metrics = try await run(fixture)
            runs.append(BenchRun(corpus: corpus, files: fixture.context.files.count,
                                  diffBytes: fixture.context.diff.utf8.count, metrics: metrics))
        }

        print("\n=== Bench: Contour's own latency (CONTOUR_MOCK_ANALYSIS=1, no model, no network) ===")
        for entry in runs {
            print("--- \(entry.corpus.rawValue) (\(entry.files) files, \(entry.diffBytes) diff bytes) ---")
            for milestone in LatencyMilestone.allCases {
                let value = entry.metrics.elapsed(milestone).map { String(format: "%8.1f ms", $0 * 1000) } ?? "     n/a"
                print("  \(milestone.label.padding(toLength: 18, withPad: " ", startingAt: 0)) \(value)")
            }
        }

        for entry in runs {
            let elapsed = try XCTUnwrap(entry.metrics.elapsed(.fullAnalysis), "\(entry.corpus.rawValue) never reached full analysis")
            XCTAssertLessThan(elapsed, 20, "\(entry.corpus.rawValue) took \(elapsed)s end to end offline — Contour's own path should never be this slow with no model in the loop")
        }

        if let small = runs.first(where: { $0.corpus == .small })?.metrics.elapsed(.usefulOverview),
           let large = runs.first(where: { $0.corpus == .large })?.metrics.elapsed(.usefulOverview) {
            let ratio = (large + 0.05) / (small + 0.05)
            XCTAssertLessThan(ratio, 100, "large took \(ratio)x as long as small to reach a useful overview — expected roughly linear scaling with corpus size")
        }
    }

    private func run(_ fixture: BenchFixture) async throws -> AnalysisMetrics {
        let pipeline = AnalysisPipeline(harnessID: .claude, trackerID: .none, githubAccess: .anonymous)
        var metrics = AnalysisMetrics(pr: fixture.context.url)
        var state = AnalysisState()
        var graph: PRGraph?
        var diffText: String?

        await pipeline.start(offlineContext: fixture.context, checkout: fixture.checkout, forceRefresh: true)
        loop: for await event in pipeline.events {
            switch event {
            case .log:
                break
            case .status(let stage, let status):
                state.stages[stage] = status
                if status.isRunning, PipelineStage.analysis.contains(stage) { state.isComplete = false }
            case .graph(let snapshot):
                graph = snapshot
            case .diff(let diff):
                diffText = diff
                _ = UnifiedDiff.parse(diff)
            case .checkout:
                break
            case .revalidating(let head):
                state.revalidatingFrom = head
            case .fromCache:
                state.fromCache = true
                metrics.fromCache = true
            case .complete:
                state.isComplete = true
            case .fatal(let message):
                XCTFail("bench fixture pipeline failed: \(message)")
            }
            metrics.update(state: state, graph: graph, diffAvailable: diffText != nil)
            if case .complete = event { break loop }
            if case .fatal = event { break loop }
        }
        await pipeline.cancel()
        return metrics
    }
}
