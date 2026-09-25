import XCTest
@testable import Contour

final class PlaceholderTests: XCTestCase {
    func testGitHubURLNormalization() {
        XCTAssertNotNil(GitHubService.normalize("https://github.com/acme/shop/pull/1423"))
        XCTAssertNil(GitHubService.normalize("not a url"))
    }

    /// Regression test using a captured real response from `pi` analyzing cli/cli#1
    /// (see design doc §10) — proves the architecture-stage JSON schema this app asks
    /// for actually round-trips through StageDecoding into real graph nodes, with real
    /// CodeRefs, real provenance tags, and lenient decoding for the fields pi omitted
    /// (blobSha, side on some refs).
    func testDecodeRealArchitectureResponse() throws {
        let url = Bundle.module.url(forResource: "architecture_response", withExtension: "json", subdirectory: "Fixtures")!
        let data = try Data(contentsOf: url)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let result = try StageDecoding.decode(StageDecoding.ArchitectureResult.self, from: obj)

        XCTAssertGreaterThanOrEqual(result.components.count, 3)
        XCTAssertNotNil(result.architectureImpact)
        XCTAssertEqual(result.architectureImpact?.provenance, .interpretation)

        let prCommand = result.components.first { $0.id == "pr-command-cli" }
        XCTAssertEqual(prCommand?.changeKind, .new)
        XCTAssertEqual(prCommand?.summary?.provenance, .claim)
        XCTAssertFalse(prCommand?.refs.isEmpty ?? true)
        XCTAssertEqual(prCommand?.refs.first?.path, "command/pr.go")

        // This component's ref omitted blobSha/side entirely — confirms lenient decoding.
        let clientComponent = result.components.first { $0.id == "github-api-client" }
        XCTAssertEqual(clientComponent?.refs.first?.side, .head)
        XCTAssertNil(clientComponent?.refs.first?.blobSha)
    }

    /// Lenient decode of the behavior-change stage: confirms defaults kick in when the
    /// AI omits `before`/`after`/`tag`/`componentIds`, mirroring the architecture-stage
    /// lenient-decode test above.
    func testDecodeLenientBehaviorChange() throws {
        let json = """
        {
          "behaviorChanges": [
            {
              "title": "Immediate reindex on publish",
              "after": [{"label": "Rebuild search entry"}],
              "why": {"text": "avoid stale search results", "provenance": "interpretation", "confidence": "medium"},
              "consequence": {"text": "indexing queues immediately", "provenance": "interpretation", "confidence": "high"},
              "humanQuestion": {"text": "does this overload the index queue under burst publishes?", "provenance": "interpretation", "confidence": "medium"}
            }
          ]
        }
        """
        let obj = try JSONSerialization.jsonObject(with: json.data(using: .utf8)!) as! [String: Any]
        let result = try StageDecoding.decode(StageDecoding.BehaviorChangeResult.self, from: obj)

        XCTAssertEqual(result.behaviorChanges.count, 1)
        let change = result.behaviorChanges[0]
        XCTAssertTrue(change.before.isEmpty)
        XCTAssertEqual(change.after.count, 1)
        XCTAssertEqual(change.after[0].label, "Rebuild search entry")
        XCTAssertEqual(change.after[0].tag, .both)
        XCTAssertTrue(change.after[0].componentIds.isEmpty)
    }

    /// Confirms a `PRGraph` constructed directly (mock/preview data, same shape the
    /// pipeline assembles) round-trips the new hierarchy fields end to end.
    func testMockGraphExercisesHierarchyFields() throws {
        let graph = ContourSampleData.publishTriggeredReindex
        XCTAssertNotNil(graph.dominantBehaviorChange)
        XCTAssertFalse(graph.components.filter { $0.level == .system }.isEmpty)
        XCTAssertFalse(graph.components.filter { $0.level == .implementation }.isEmpty)
        XCTAssertFalse(graph.flows.first?.storySteps.isEmpty ?? true)

        let data = try JSONEncoder().encode(graph)
        let decoded = try JSONDecoder().decode(PRGraph.self, from: data)
        XCTAssertEqual(decoded.pr.title, graph.pr.title)
        XCTAssertEqual(decoded.dominantBehaviorChange?.title, graph.dominantBehaviorChange?.title)
    }
}
