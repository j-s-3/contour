import XCTest

@testable import Contour

final class IntegrationSmokeTests: XCTestCase {
    static let defaultPR = "https://github.com/cli/cli/pull/1"

    func testFullPipelineAgainstRealTinyPR() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["RUN_CONTOUR_INTEGRATION"] == "1",
            "Set RUN_CONTOUR_INTEGRATION=1 to run this (network + model calls).")

        let env = ProcessInfo.processInfo.environment
        let harness = env["CONTOUR_HARNESS"].flatMap(HarnessID.init(rawValue:)) ?? .claude
        let access = env["CONTOUR_GITHUB_ACCESS"].flatMap(GitHubAccessMode.init(rawValue:)) ?? .auto

        let prURL = env["CONTOUR_PR_URL"] ?? Self.defaultPR
        let expected = try GitHubService.parse(prURL: prURL)

        let pipeline = AnalysisPipeline(harnessID: harness, trackerID: .github, githubAccess: access)
        await pipeline.start(prURL: prURL, forceRefresh: true)
        let started = Date()
        var graph: PRGraph?
        var diff = ""
        var failures: [String] = []
        loop: for await event in pipeline.events {
            switch event {
            case .log(let entry): print("[\(entry.stage)] \(entry.detail)")
            case .status(let stage, let status):
                print(
                    String(format: "%6.1fs  %@ → %@", Date().timeIntervalSince(started), stage.shortLabel, "\(status)"))
                if case .failed(let message) = status { failures.append("\(stage.shortLabel): \(message)") }
            case .graph(let g): graph = g
            case .diff(let d): diff = d
            case .fatal(let message):
                XCTFail(message)
                break loop
            case .complete: break loop
            case .checkout, .stack, .revalidating, .fromCache: break
            }
        }
        await pipeline.cancel()
        XCTAssertEqual(failures, [])

        let result = (graph: try XCTUnwrap(graph), diff: diff)
        XCTAssertEqual(result.graph.pr.number, expected.number)
        XCTAssertEqual(result.graph.pr.repo, "\(expected.owner)/\(expected.repo)")
        XCTAssertFalse(result.graph.components.isEmpty)
        XCTAssertFalse(result.diff.isEmpty)

        print("=== SUMMARY (harness: \(harness.rawValue), github: \(access.rawValue)) ===")
        print("Intent:", result.graph.pr.intent.text)
        print("Components:", result.graph.components.map(\.title))
        print("Decisions:", result.graph.decisions.map(\.title))
        print(
            "Tradeoffs:",
            result.graph.decisions.flatMap { d in d.tradeoffs.map { "\(d.id): \($0.dimensionA) vs \($0.dimensionB)" } })
        print("Flows:", result.graph.flows.map(\.title))
        print("Entry points:", result.graph.entryPoints.map(\.title))
        print("Needs judgment:", result.graph.pr.needsJudgment.map(\.text))
        print("Uncertainties:", result.graph.pr.uncertainties.map(\.text))
        print("Linked issue:", result.graph.pr.ticket?.key ?? "none")
        print("Problem to be solved:", result.graph.pr.problemToBeSolved?.text ?? "nil")
        print("How it was solved:", result.graph.pr.howItWasSolved?.text ?? "nil")
    }

    func testAnonymousSourceFetchesAPublicPR() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["RUN_CONTOUR_INTEGRATION"] == "1",
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

    func testBothSourcesAgreeOnTheSamePR() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["RUN_CONTOUR_INTEGRATION"] == "1",
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
