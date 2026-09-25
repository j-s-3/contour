import XCTest
@testable import Contour

/// Full end-to-end pipeline run against a real, tiny, **public** PR. Hits the network and
/// shells out to a real model for every stage — not a unit test, a genuine integration
/// smoke test. Gated behind an env var so it doesn't run in normal `swift test` (cost +
/// network + external-service flakiness).
///
///   RUN_CONTOUR_INTEGRATION=1 swift test --filter IntegrationSmokeTests
///
/// The PR is public on purpose: the run needs no private-repo access, and with
/// `CONTOUR_GITHUB_ACCESS=anonymous` it needs no `gh` either, which is the only way to
/// exercise the bare-machine path end to end.
///
/// Both the harness and the GitHub access mode come from the environment, so the same
/// test covers every combination:
///
///   RUN_CONTOUR_INTEGRATION=1 CONTOUR_HARNESS=claude swift test --filter IntegrationSmoke
///   RUN_CONTOUR_INTEGRATION=1 CONTOUR_GITHUB_ACCESS=anonymous swift test --filter IntegrationSmoke
final class IntegrationSmokeTests: XCTestCase {

    func testFullPipelineAgainstRealTinyPR() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_CONTOUR_INTEGRATION"] == "1",
                          "Set RUN_CONTOUR_INTEGRATION=1 to run this (network + model calls).")

        let env = ProcessInfo.processInfo.environment
        let harness = env["CONTOUR_HARNESS"].flatMap(HarnessID.init(rawValue:)) ?? .claude
        let access = env["CONTOUR_GITHUB_ACCESS"].flatMap(GitHubAccessMode.init(rawValue:)) ?? .auto

        let pipeline = AnalysisPipeline(harnessID: harness, trackerID: .github, githubAccess: access)
        let result = try await pipeline.run(prURL: "https://github.com/cli/cli/pull/1") { stage, entry in
            print("[\(stage.rawValue)] \(entry.detail)")
        }

        XCTAssertEqual(result.graph.pr.number, 1)
        XCTAssertEqual(result.graph.pr.repo, "cli/cli")
        XCTAssertFalse(result.graph.components.isEmpty)
        XCTAssertFalse(result.diff.isEmpty)

        print("=== SUMMARY (harness: \(harness.rawValue), github: \(access.rawValue)) ===")
        print("Intent:", result.graph.pr.intent.text)
        print("Components:", result.graph.components.map(\.title))
        print("Decisions:", result.graph.decisions.map(\.title))
        print("Tradeoffs:", result.graph.tradeoffs.map(\.title))
        print("Flows:", result.graph.flows.map(\.title))
        print("Entry points:", result.graph.entryPoints.map(\.title))
        print("Needs judgment:", result.graph.pr.needsJudgment.map(\.text))
        print("Uncertainties:", result.graph.pr.uncertainties.map(\.text))
        print("Linked issue:", result.graph.pr.ticket?.key ?? "none")
        print("Problem to be solved:", result.graph.pr.problemToBeSolved?.text ?? "nil")
        print("How it was solved:", result.graph.pr.howItWasSolved?.text ?? "nil")
    }

    /// The anonymous path on its own, without the model spend. This is the check that
    /// matters most for "works on a bare machine": no `gh`, no token, just HTTPS.
    func testAnonymousSourceFetchesAPublicPR() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_CONTOUR_INTEGRATION"] == "1",
                          "Set RUN_CONTOUR_INTEGRATION=1 to run this (network).")

        let ctx = try await AnonymousAPISource().fetchContext(prURL: "https://github.com/cli/cli/pull/1")
        XCTAssertEqual(ctx.owner, "cli")
        XCTAssertEqual(ctx.repo, "cli")
        XCTAssertEqual(ctx.number, 1)
        XCTAssertFalse(ctx.title.isEmpty)
        XCTAssertFalse(ctx.diff.isEmpty)
        XCTAssertFalse(ctx.headSha.isEmpty)
        XCTAssertFalse(ctx.files.isEmpty)
    }

    /// Both sources must produce the same `RawPRContext` for the same PR. Since `gh` is
    /// preferred whenever it's installed, the anonymous path is the rarely-exercised one —
    /// this is what keeps it from drifting unnoticed.
    func testBothSourcesAgreeOnTheSamePR() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_CONTOUR_INTEGRATION"] == "1",
                          "Set RUN_CONTOUR_INTEGRATION=1 to run this (network + gh).")
        try XCTSkipIf(Shell.which("gh") == nil, "gh not installed")

        let url = "https://github.com/cli/cli/pull/1"
        let viaGH = try await GHCLISource().fetchContext(prURL: url)
        let viaAPI = try await AnonymousAPISource().fetchContext(prURL: url)

        XCTAssertEqual(viaGH.owner, viaAPI.owner)
        XCTAssertEqual(viaGH.repo, viaAPI.repo)
        XCTAssertEqual(viaGH.number, viaAPI.number)
        XCTAssertEqual(viaGH.title, viaAPI.title)
        XCTAssertEqual(viaGH.author, viaAPI.author)
        XCTAssertEqual(viaGH.headSha, viaAPI.headSha)
        XCTAssertEqual(viaGH.baseSha, viaAPI.baseSha)
        XCTAssertEqual(viaGH.headRefName, viaAPI.headRefName)
        XCTAssertEqual(viaGH.baseRefName, viaAPI.baseRefName)
        XCTAssertEqual(viaGH.state, viaAPI.state)
        XCTAssertEqual(viaGH.changedFiles, viaAPI.changedFiles)
        XCTAssertEqual(Set(viaGH.files), Set(viaAPI.files))
        XCTAssertEqual(viaGH.commits.map(\.sha), viaAPI.commits.map(\.sha))
    }
}
