import Testing
import Foundation
@testable import Contour

/// The Overview's "Things to think about" must stay a list of five-second questions, even
/// for graphs produced before the judgment stage wrote to that budget.
struct OverviewBriefingTests {

    @Test func considerationsFromTheJudgmentStageWin() {
        var graph = ContourSampleData.publishTriggeredReindex
        graph.pr.considerations = [Consideration(id: "c1", question: "Is a queue hop acceptable?", detail: "Publishing gets slower.")]
        #expect(graph.thingsToThinkAbout.map(\.id) == ["c1"])
    }

    /// Older graphs: the behavior change's human question leads, then judgment items as
    /// concerns, then uncertainties as open questions.
    @Test func olderGraphsAreCondensedInOrder() {
        let graph = ContourSampleData.publishTriggeredReindex
        let items = graph.thingsToThinkAbout
        #expect(items.map(\.kind) == [.concern, .concern, .question])
        #expect(items.first?.question == "Can the index queue absorb a burst of publishes without falling behind?")
    }

    @Test func condensingLeadsWithTheQuestionAndDropsCodeLocations() {
        let statement = Statement(
            text: "The fix reads only the first chunk (src/input.rs:273-274). Pipes can deliver short chunks. Is timing-dependent classification acceptable? More detail follows here.",
            provenance: .interpretation, confidence: .medium
        )
        let item = PRGraph.condense(statement, id: "x", kind: .concern)
        #expect(item.question == "Is timing-dependent classification acceptable?")
        #expect(item.detail == "The fix reads only the first chunk.")
        #expect(!item.question.contains("src/"))
        #expect(item.explanation == statement.text)
        #expect(item.confidence == .medium)
    }

    @Test func condensingAStatementWithoutAQuestionUsesItsFirstSentence() {
        let item = PRGraph.condense(
            Statement(text: "No timeout is set on evaluate(). It can hang the upload.", provenance: .interpretation),
            id: "y", kind: .concern
        )
        #expect(item.question == "No timeout is set on evaluate().")
        #expect(item.detail == "It can hang the upload.")
        #expect(item.explanation == nil)
    }

    @Test func abbreviationsAndBareCitationsDontBreakHeadlines() {
        let item = PRGraph.condense(
            Statement(text: "The fix is partial for stdin (e.g. `gpg -d ... | bat`). The test at src/input.rs:435-455 checks it.", provenance: .interpretation),
            id: "z", kind: .concern
        )
        #expect(item.question == "The fix is partial for stdin (e.g. `gpg -d ... | bat`).")
        #expect(item.detail == "The test checks it.")
    }

    @Test func considerationDecodingIsLenient() throws {
        let json = #"{"question": "Should this be silent?", "kind": "somethingNew", "confidence": "very"}"#
        let item = try JSONDecoder().decode(Consideration.self, from: Data(json.utf8))
        #expect(item.question == "Should this be silent?")
        #expect(item.detail == "")
        #expect(item.kind == .concern)
        #expect(item.provenance == .interpretation)
        #expect(item.confidence == nil)
    }

    @Test func judgmentStageDecodesConsiderations() throws {
        let raw: [String: Any] = [
            "considerations": [["id": "a", "question": "Q?", "detail": "D.", "kind": "question", "relatedIds": ["d1"]]],
            "needsJudgment": [], "uncertainties": [], "questions": [],
        ]
        let result = try StageDecoding.decode(StageDecoding.JudgmentResult.self, from: raw)
        #expect(result.considerations.first?.kind == .question)
        #expect(result.considerations.first?.relatedIds == ["d1"])
    }

    @Test func stageOutcomeDecodesAndDegrades() throws {
        let ok = try JSONDecoder().decode(BehaviorStage.self, from: Data(#"{"label": "Server rejects", "outcome": "failure"}"#.utf8))
        #expect(ok.outcome == .failure)
        let odd = try JSONDecoder().decode(BehaviorStage.self, from: Data(#"{"label": "Run", "outcome": "maybe"}"#.utf8))
        #expect(odd.outcome == nil)
    }

    /// The captured fixtures predate `considerations`; the Overview must still produce a
    /// short list from them rather than an empty section.
    @Test func mockFixturesStillYieldThingsToThinkAbout() throws {
        let behavior = try StageDecoding.decode(
            StageDecoding.BehaviorChangeResult.self, from: MockAnalysisFixtures.response(for: .behaviorChange)
        )
        let judgment = try StageDecoding.decode(
            StageDecoding.JudgmentResult.self, from: MockAnalysisFixtures.response(for: .judgment)
        )
        var graph = ContourSampleData.publishTriggeredReindex
        graph.behaviorChanges = behavior.behaviorChanges
        graph.pr.needsJudgment = judgment.needsJudgment
        graph.pr.uncertainties = judgment.uncertainties
        let items = graph.thingsToThinkAbout
        #expect(!items.isEmpty)
        #expect(items.allSatisfy { !$0.question.contains("src/") })
    }

    /// The captured fixtures come from a run that wrote `considerations` to budget; if a
    /// regeneration ever loses them, mock mode would silently fall back to condensing.
    @Test func mockFixturesCarryBudgetedConsiderations() throws {
        let judgment = try StageDecoding.decode(
            StageDecoding.JudgmentResult.self, from: MockAnalysisFixtures.response(for: .judgment)
        )
        #expect((1...5).contains(judgment.considerations.count))
        #expect(judgment.considerations.allSatisfy { $0.question.hasSuffix("?") })
        let behavior = try StageDecoding.decode(
            StageDecoding.BehaviorChangeResult.self, from: MockAnalysisFixtures.response(for: .behaviorChange)
        )
        #expect(behavior.behaviorChanges.first?.after.last?.outcome != nil)
    }
}
