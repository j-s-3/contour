import XCTest
@testable import Contour

/// Full end-to-end pipeline run against a real, tiny, public PR. Hits the network (gh)
/// and shells out to a real model (pi) for all six stages — not a unit test, a genuine
/// integration smoke test. Gated behind an env var so it doesn't run in normal `swift
/// test` (cost + network + external-service flakiness); run explicitly with:
///   RUN_CONTOUR_INTEGRATION=1 swift test --filter IntegrationSmokeTests
final class IntegrationSmokeTests: XCTestCase {
    func testFullPipelineAgainstRealTinyPR() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_CONTOUR_INTEGRATION"] == "1",
                           "Set RUN_CONTOUR_INTEGRATION=1 to run this (network + pi calls).")

        let pipeline = AnalysisPipeline()
        let result = try await pipeline.run(prURL: "https://github.com/cli/cli/pull/1") { stage, entry in
            print("[\(stage.rawValue)] \(entry.detail)")
        }

        XCTAssertEqual(result.graph.pr.number, 1)
        XCTAssertEqual(result.graph.pr.repo, "cli/cli")
        XCTAssertFalse(result.graph.components.isEmpty)
        XCTAssertFalse(result.diff.isEmpty)

        print("=== SUMMARY ===")
        print("Intent:", result.graph.pr.intent.text)
        print("Components:", result.graph.components.map(\.title))
        print("Decisions:", result.graph.decisions.map(\.title))
        print("Tradeoffs:", result.graph.tradeoffs.map(\.title))
        print("Flows:", result.graph.flows.map(\.title))
        print("Entry points:", result.graph.entryPoints.map(\.title))
        print("Needs judgment:", result.graph.pr.needsJudgment.map(\.text))
        print("Uncertainties:", result.graph.pr.uncertainties.map(\.text))
        print("Jira ticket:", result.graph.pr.jiraTicket?.key ?? "none")
        print("Problem to be solved:", result.graph.pr.problemToBeSolved?.text ?? "nil")
        print("How it was solved:", result.graph.pr.howItWasSolved?.text ?? "nil")
    }
}
