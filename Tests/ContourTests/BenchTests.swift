import XCTest
@testable import Contour

/// Contour's own latency on a fixture corpus, driven through the mock harness end to end
/// (issue #60, DESIGN.md §13: "the measure that matters is time to a useful Overview").
/// No real model, no network: `AnalysisPipeline` runs against `BenchFixtures`-generated
/// PRs of increasing size through `start(offlineContext:checkout:forceRefresh:)` — the
/// same pipeline path a real run takes (cache lookup, stage dispatch, verification, graph
/// assembly, linking), minus the GitHub fetch and `git clone`.
///
///   swift test --filter BenchTests
///
/// Prints a per-milestone (`LatencyMilestone`) table for each corpus size and fails if a
/// corpus's own time, or the large-vs-small ratio, blows past a deliberately generous
/// bound. The `xcode-27` CI runner is noisy, so these thresholds are sized to catch a 5x
/// class regression — an accidentally-quadratic diff parser, a leaked synchronous I/O call
/// — not a 5% one.
final class BenchTests: XCTestCase {

    private struct BenchRun {
        var corpus: BenchCorpus
        var files: Int
        var diffBytes: Int
        var metrics: AnalysisMetrics
    }

    func testLatencyAcrossFixtureCorpusSizes() async throws {
        setenv("CONTOUR_MOCK_ANALYSIS", "1", 1)
        // Bench measures Contour's own work, not the simulated per-stage delay mock mode
        // can add for manually watching progressive opening (§13) — make sure neither that
        // nor a leftover forced-failure switch is leaking in from the calling environment.
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

        // A generous absolute ceiling per corpus. With no real model call in the loop, even
        // the large corpus's hundreds of files and tens of thousands of diff lines should
        // stay well under this; several seconds here means something in Contour's own path
        // — not a model — went very wrong.
        for entry in runs {
            let elapsed = try XCTUnwrap(entry.metrics.elapsed(.fullAnalysis), "\(entry.corpus.rawValue) never reached full analysis")
            XCTAssertLessThan(elapsed, 20, "\(entry.corpus.rawValue) took \(elapsed)s end to end offline — Contour's own path should never be this slow with no model in the loop")
        }

        // The point isn't pinning an exact number on a noisy shared runner, it's catching a
        // large-multiple regression: if Contour's own share of the latency stopped scaling
        // roughly linearly with input size (an accidentally-quadratic diff parser, say),
        // the large corpus's time relative to the small one would blow far past this.
        if let small = runs.first(where: { $0.corpus == .small })?.metrics.elapsed(.usefulOverview),
           let large = runs.first(where: { $0.corpus == .large })?.metrics.elapsed(.usefulOverview) {
            // A 50ms floor on both sides: the small corpus can land in a couple of
            // milliseconds, where CI scheduling noise alone would otherwise dominate the ratio.
            let ratio = (large + 0.05) / (small + 0.05)
            XCTAssertLessThan(ratio, 100, "large took \(ratio)x as long as small to reach a useful overview — expected roughly linear scaling with corpus size")
        }
    }

    /// Runs the pipeline against one fixture to completion and returns its metrics,
    /// mirroring how `GraphStore.handle(_:)` folds pipeline events into `AnalysisMetrics`
    /// (§13) — this is what the bench numbers are meant to reflect: what a reviewer's own
    /// clock would show, minus the model and the network.
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
                // The one piece of "Contour's own latency" that isn't inside
                // AnalysisPipeline itself: the raw-diff parse GraphStore does as soon as
                // the diff arrives, folded into the same milestone timeline as everything
                // else here.
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
