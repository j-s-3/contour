import XCTest

@testable import Contour

final class CorpusRunTests: XCTestCase {
    struct CorpusEntry: Decodable {
        var url: String
        var reason: String
    }

    struct StageRecord: Codable {
        var stage: String
        var outcome: String
        var durationSeconds: Double?
        var failureMessage: String?
        var malformedJSONRetries: Int
        var citationsChecked: Int
        var citationsUnverifiable: Int
        var streamedElementCount: Int?
        var finalElementCount: Int?
    }

    struct PRRecord: Codable {
        var url: String
        var reason: String
        var startedAt: Date
        var totalDurationSeconds: Double
        var outcome: String
        var fatalMessage: String?
        var stages: [StageRecord]
        var milestones: [String: Double]
        var decisionsCount: Int
        var componentsCount: Int
        var flowsCount: Int
    }

    func testCorpusRun() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["RUN_CONTOUR_INTEGRATION"] == "1",
            "Set RUN_CONTOUR_INTEGRATION=1 to run this (network + model calls, one full run per corpus PR).")

        let env = ProcessInfo.processInfo.environment
        let harness = env["CONTOUR_HARNESS"].flatMap(HarnessID.init(rawValue:)) ?? .claude
        let access = env["CONTOUR_GITHUB_ACCESS"].flatMap(GitHubAccessMode.init(rawValue:)) ?? .auto

        let corpusURL = try XCTUnwrap(
            Bundle.module.url(forResource: "corpus", withExtension: "json", subdirectory: "Fixtures"),
            "Fixtures/corpus.json wasn't bundled with the test target")
        let corpus = try JSONDecoder().decode([CorpusEntry].self, from: Data(contentsOf: corpusURL))
        XCTAssertFalse(corpus.isEmpty, "the corpus is empty — nothing to run")

        let resultsURL =
            env["CONTOUR_CORPUS_RESULTS"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("contour-corpus-results-\(Int(Date().timeIntervalSince1970)).jsonl")
        _ = FileManager.default.createFile(atPath: resultsURL.path, contents: nil)
        print("=== Corpus run: \(corpus.count) PR(s), harness: \(harness.rawValue), github: \(access.rawValue) ===")
        print("Results file: \(resultsURL.path)")

        for (index, entry) in corpus.enumerated() {
            print("--- [\(index + 1)/\(corpus.count)] \(entry.url) ---")
            let record = await Self.run(entry, harness: harness, access: access)
            print(
                "    outcome: \(record.outcome), \(record.totalDurationSeconds.rounded())s, "
                    + "\(record.decisionsCount) decisions, \(record.componentsCount) components, \(record.flowsCount) flows"
            )
            Self.append(record, to: resultsURL)
        }

        let lineCount =
            (try? String(contentsOf: resultsURL, encoding: .utf8))?
            .split(separator: "\n", omittingEmptySubsequences: true).count ?? 0
        XCTAssertEqual(lineCount, corpus.count, "expected one result line per corpus entry")
    }

    private static func run(_ entry: CorpusEntry, harness: HarnessID, access: GitHubAccessMode) async -> PRRecord {
        let started = Date()

        guard (try? GitHubService.parse(prURL: entry.url)) != nil else {
            return PRRecord(
                url: entry.url, reason: entry.reason, startedAt: started,
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
            metrics.update(state: state, graph: graph, diffAvailable: diffAvailable)
            if settled { break }
        }
        await pipeline.cancel()

        if let fatalMessage {
            for stage in [PipelineStage.fetching, .checkingOut] where state.status(stage).isRunning {
                stageRecords[stage] = StageRecord(
                    stage: stage.rawValue, outcome: "failed",
                    durationSeconds: stageStarted[stage].map { Date().timeIntervalSince($0) },
                    failureMessage: fatalMessage, malformedJSONRetries: 0,
                    citationsChecked: 0, citationsUnverifiable: 0, streamedElementCount: nil, finalElementCount: nil)
            }
        }

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

    private static let foundSoFarSuffix = " found so far"
    private static func streamedCount(in detail: String?) -> Int? {
        guard let detail, detail.hasSuffix(foundSoFarSuffix) else { return nil }
        return Int(detail.dropLast(foundSoFarSuffix.count))
    }

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
