import XCTest
@testable import Contour

/// Nightly real-PR corpus run (issue #64): runs the full pipeline against a small corpus of
/// real, long-merged public PRs (`Fixtures/corpus.json`) and records per-stage failure rate,
/// malformed-JSON retries, unverifiable-citation counts, streamed-vs-final element counts and
/// `AnalysisMetrics` latency milestones — a trend `IntegrationSmokeTests`'s single tiny PR
/// can't show. Not run in CI; only the nightly workflow runs it, and it's gated the same way
/// as `IntegrationSmokeTests` so a plain `swift test` never touches it:
///
///   RUN_CONTOUR_INTEGRATION=1 swift test --filter CorpusRunTests
///
/// One JSON line per PR is appended to `CONTOUR_CORPUS_RESULTS` as its run finishes (default:
/// a file under the test's own temp directory, whose path is printed) — so a crash partway
/// through the corpus still leaves every PR analyzed up to that point on disk. A PR that fails
/// is a recorded result, never a stopped run: every entry in the corpus is always attempted,
/// mirroring how a stage failing never stops the rest of the pipeline (§10).
///
/// `scripts/summarize-corpus.py` turns a results file into failure rates, retry rates and
/// p50/p95 latencies; see `Fixtures/README.md` for running the corpus locally.
final class CorpusRunTests: XCTestCase {

    /// One entry of `Fixtures/corpus.json`.
    struct CorpusEntry: Decodable {
        var url: String
        var reason: String
    }

    /// One stage's outcome for one PR — the pipeline's own vocabulary (§10, `StageStatus`),
    /// not a pass/fail bit, since a "failed" stage is an expected, recorded outcome here.
    struct StageRecord: Codable {
        var stage: String
        var outcome: String
        var durationSeconds: Double?
        var failureMessage: String?
        /// Times `AnalysisService.runStage` retried this stage after malformed JSON, counted
        /// from the log line it emits on retry (there's no separate event for it).
        var malformedJSONRetries: Int
        /// From `CodeRefVerifier`/`RefCheck`, surfaced on the graph as `refChecks[stage]`.
        var citationsChecked: Int
        var citationsUnverifiable: Int
        /// Decisions/flows only: the running count seen in the "N found so far" status detail
        /// while the stage streamed, versus the authoritative count once it landed. These can
        /// legitimately differ (a streamed element can be dropped by CodeRefVerifier before it
        /// lands), so this is a data point, not an inconsistency to flag on its own.
        var streamedElementCount: Int?
        var finalElementCount: Int?
    }

    /// One PR's full record — one JSON line in the results file.
    struct PRRecord: Codable {
        var url: String
        var reason: String
        var startedAt: Date
        var totalDurationSeconds: Double
        /// "completed" (every analysis stage settled, however it settled), "fatal" (fetch or
        /// checkout failed — the only two fatal stages, §10), or "error" (something in this
        /// test itself, e.g. an unparseable corpus URL, kept it from ever starting the pipeline).
        var outcome: String
        var fatalMessage: String?
        var stages: [StageRecord]
        /// `LatencyMilestone.rawValue` → seconds, exactly what `AnalysisMetrics` records for a
        /// real reviewer session (§13), computed the same way `GraphStore` does.
        var milestones: [String: Double]
        var decisionsCount: Int
        var componentsCount: Int
        var flowsCount: Int
    }

    func testCorpusRun() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_CONTOUR_INTEGRATION"] == "1",
                          "Set RUN_CONTOUR_INTEGRATION=1 to run this (network + model calls, one full run per corpus PR).")

        let env = ProcessInfo.processInfo.environment
        let harness = env["CONTOUR_HARNESS"].flatMap(HarnessID.init(rawValue:)) ?? .claude
        let access = env["CONTOUR_GITHUB_ACCESS"].flatMap(GitHubAccessMode.init(rawValue:)) ?? .auto

        let corpusURL = try XCTUnwrap(
            Bundle.module.url(forResource: "corpus", withExtension: "json", subdirectory: "Fixtures"),
            "Fixtures/corpus.json wasn't bundled with the test target")
        let corpus = try JSONDecoder().decode([CorpusEntry].self, from: Data(contentsOf: corpusURL))
        XCTAssertFalse(corpus.isEmpty, "the corpus is empty — nothing to run")

        let resultsURL = env["CONTOUR_CORPUS_RESULTS"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.temporaryDirectory
                .appendingPathComponent("contour-corpus-results-\(Int(Date().timeIntervalSince1970)).jsonl")
        _ = FileManager.default.createFile(atPath: resultsURL.path, contents: nil)
        print("=== Corpus run: \(corpus.count) PR(s), harness: \(harness.rawValue), github: \(access.rawValue) ===")
        print("Results file: \(resultsURL.path)")

        for (index, entry) in corpus.enumerated() {
            print("--- [\(index + 1)/\(corpus.count)] \(entry.url) ---")
            let record = await Self.run(entry, harness: harness, access: access)
            print("    outcome: \(record.outcome), \(record.totalDurationSeconds.rounded())s, "
                + "\(record.decisionsCount) decisions, \(record.componentsCount) components, \(record.flowsCount) flows")
            Self.append(record, to: resultsURL)
        }

        let lineCount = (try? String(contentsOf: resultsURL, encoding: .utf8))?
            .split(separator: "\n", omittingEmptySubsequences: true).count ?? 0
        XCTAssertEqual(lineCount, corpus.count, "expected one result line per corpus entry")
    }

    // MARK: - Running one PR

    /// Runs the full pipeline against one corpus entry and records what happened, stage by
    /// stage. Never throws: any failure — fatal pipeline error, a URL this test itself can't
    /// parse, anything unexpected — becomes a recorded `PRRecord`, never an `XCTFail`, per the
    /// "a failed PR is a recorded result" contract above.
    private static func run(_ entry: CorpusEntry, harness: HarnessID, access: GitHubAccessMode) async -> PRRecord {
        let started = Date()

        guard (try? GitHubService.parse(prURL: entry.url)) != nil else {
            return PRRecord(url: entry.url, reason: entry.reason, startedAt: started,
                            totalDurationSeconds: Date().timeIntervalSince(started), outcome: "error",
                            fatalMessage: "couldn't parse as a GitHub PR URL", stages: [], milestones: [:],
                            decisionsCount: 0, componentsCount: 0, flowsCount: 0)
        }

        var metrics = AnalysisMetrics(pr: entry.url, startedAt: started)
        var state = AnalysisState()
        var graph: PRGraph?
        var diffAvailable = false
        var fatalMessage: String?

        var stageStarted: [PipelineStage: Date] = [:]
        var stageRecords: [PipelineStage: StageRecord] = [:]
        var malformedRetries: [PipelineStage: Int] = [:]
        var streamedMax: [PipelineStage: Int] = [:]

        let pipeline = AnalysisPipeline(harnessID: harness, trackerID: .github, githubAccess: access)
        await pipeline.start(prURL: entry.url, forceRefresh: true)

        for await event in pipeline.events {
            var settled = false
            switch event {
            case .log(let logEntry):
                // AnalysisService's only retry message; see its doc comment. There's no
                // separate event for this, so the log line is the one observable signal.
                if logEntry.detail.contains("malformed JSON"), let stage = PipelineStage(rawValue: logEntry.stage) {
                    malformedRetries[stage, default: 0] += 1
                }

            case .status(let stage, let status):
                state.stages[stage] = status
                if status.isRunning, PipelineStage.analysis.contains(stage) { state.isComplete = false }
                if stageStarted[stage] == nil, status.isRunning { stageStarted[stage] = Date() }
                if case .running(let detail) = status, let n = streamedCount(in: detail) {
                    streamedMax[stage] = max(streamedMax[stage] ?? 0, n)
                }
                if status.isSettled {
                    stageRecords[stage] = StageRecord(
                        stage: stage.rawValue, outcome: outcomeName(status),
                        durationSeconds: stageStarted[stage].map { Date().timeIntervalSince($0) },
                        failureMessage: status.failure, malformedJSONRetries: malformedRetries[stage] ?? 0,
                        citationsChecked: 0, citationsUnverifiable: 0,
                        streamedElementCount: streamedMax[stage], finalElementCount: nil)
                }

            case .graph(let snapshot):
                graph = snapshot
            case .diff:
                diffAvailable = true
            case .checkout, .revalidating, .fromCache:
                break
            case .complete:
                state.isComplete = true
                settled = true
            case .fatal(let message):
                fatalMessage = message
                settled = true
            }
            // Mirrors GraphStore.handle: recomputed after every event, including the last one,
            // so `.fullAnalysis` and friends land the same way they would for a real reviewer.
            metrics.update(state: state, graph: graph, diffAvailable: diffAvailable)
            if settled { break }
        }
        await pipeline.cancel()

        // Only fetching/checking out can be fatal (§10), and the one that failed never got an
        // explicit failed status — the pipeline jumps straight to `.fatal` — so it's still
        // `.running` here. That's how we tell the two apart without guessing.
        if let fatalMessage {
            for stage in [PipelineStage.fetching, .checkingOut] where state.status(stage).isRunning {
                stageRecords[stage] = StageRecord(
                    stage: stage.rawValue, outcome: "failed",
                    durationSeconds: stageStarted[stage].map { Date().timeIntervalSince($0) },
                    failureMessage: fatalMessage, malformedJSONRetries: 0,
                    citationsChecked: 0, citationsUnverifiable: 0, streamedElementCount: nil, finalElementCount: nil)
            }
        }

        // Backfill what only the final graph can answer: verified-citation tallies, and the
        // streamed stages' authoritative final counts.
        for stage in PipelineStage.analysis {
            guard var record = stageRecords[stage] else { continue }
            if let check = graph?.refChecks?[stage.rawValue] {
                record.citationsChecked = check.checked
                record.citationsUnverifiable = check.unresolvedCount
            }
            switch stage {
            case .decisions: record.finalElementCount = graph?.decisions.count
            case .flows: record.finalElementCount = graph?.flows.count
            default: break
            }
            stageRecords[stage] = record
        }

        return PRRecord(
            url: entry.url, reason: entry.reason, startedAt: started,
            totalDurationSeconds: Date().timeIntervalSince(started),
            outcome: fatalMessage != nil ? "fatal" : "completed", fatalMessage: fatalMessage,
            stages: PipelineStage.allCases.compactMap { stageRecords[$0] },
            milestones: metrics.milestones,
            decisionsCount: graph?.decisions.count ?? 0,
            componentsCount: graph?.components.count ?? 0,
            flowsCount: graph?.flows.count ?? 0)
    }

    private static func outcomeName(_ status: StageStatus) -> String {
        switch status {
        case .done: return "done"
        case .failed: return "failed"
        case .stopped: return "stopped"
        case .pending, .running, .stale: return "notRun"
        }
    }

    /// Parses the "<N> found so far" running-status detail a streamed stage reports
    /// (`AnalysisPipeline.appendStreamed`) back into `N`.
    private static let foundSoFarSuffix = " found so far"
    private static func streamedCount(in detail: String?) -> Int? {
        guard let detail, detail.hasSuffix(foundSoFarSuffix) else { return nil }
        return Int(detail.dropLast(foundSoFarSuffix.count))
    }

    // MARK: - Results file

    private static func append(_ record: PRRecord, to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard var line = try? encoder.encode(record) else { return }
        line.append(0x0A)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: url, options: .atomic)
        }
    }
}
