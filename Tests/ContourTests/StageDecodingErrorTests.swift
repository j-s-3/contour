import Foundation
import Testing
@testable import Contour

struct StageDecodingErrorTests {
    private func decodeFailure(_ object: [String: Any]) throws -> StageDecodingError {
        do {
            _ = try StageDecoding.decode(StageDecoding.UnderstandingResult.self, stageLabel: "Understanding", from: object)
            Issue.record("expected a decode failure")
            throw StageDecodingError(stageLabel: "unreachable", underlying: CancellationError(), rawJSON: "")
        } catch let error as StageDecodingError {
            return error
        }
    }

    @Test func describesAMissingRequiredKey() throws {
        let error = try decodeFailure([:])
        #expect(error.errorDescription?.contains(#"missing required key "intent""#) == true)
    }

    @Test func describesATypeMismatch() throws {
        let error = try decodeFailure(["intent": "not an object"])
        #expect(error.errorDescription?.contains("expected") == true)
    }

    @Test func describesAnExplicitNullWhereAValueWasRequired() throws {
        let error = try decodeFailure(["intent": NSNull()])
        #expect(error.errorDescription?.contains("null where") == true)
    }

    @Test func describesCorruptedData() throws {
        let error = try decodeFailure(["intent": ["text": "x", "provenance": "not-a-real-provenance"]])
        #expect(error.errorDescription?.contains("corrupted data") == true)
    }

    @Test func errorDescriptionNamesTheStageAndKeepsTheRawResponse() throws {
        let error = try decodeFailure([:])
        #expect(error.errorDescription?.hasPrefix("Understanding stage returned JSON that didn't decode:") == true)
        #expect(error.errorDescription?.contains("Raw response (truncated):") == true)
    }

    @Test func arrayFieldsToleratesMissingAndExplicitNull() throws {
        let missing = try StageDecoding.decode(StageDecoding.BehaviorChangeResult.self, from: [:])
        #expect(missing.behaviorChanges.isEmpty)

        let nulled = try StageDecoding.decode(StageDecoding.BehaviorChangeResult.self, from: ["behaviorChanges": NSNull()])
        #expect(nulled.behaviorChanges.isEmpty)

        let flows = try StageDecoding.decode(StageDecoding.FlowsResult.self, from: ["entryPoints": NSNull(), "flows": NSNull()])
        #expect(flows.entryPoints.isEmpty && flows.flows.isEmpty)

        let decisions = try StageDecoding.decode(StageDecoding.DecisionsResult.self, from: ["decisions": NSNull()])
        #expect(decisions.decisions.isEmpty)
    }

    @Test func decodeSucceedsWithRealContent() throws {
        let result = try StageDecoding.decode(StageDecoding.DecisionsResult.self, from: [
            "decisions": [[
                "id": "d1", "title": "Use a queue",
                "decision": ["text": "Queued.", "provenance": "fact"],
                "confidence": "high",
            ]]
        ])
        #expect(result.decisions.count == 1)
        #expect(result.decisions[0].title == "Use a queue")
    }

    @Test func judgmentResultDecodesChangeMapInEveryShape() throws {
        let withEntries = try StageDecoding.decode(StageDecoding.JudgmentResult.self, from: [
            "changeMap": [["name": "IndexQueue", "filesChanged": 2]]
        ])
        #expect(withEntries.changeMap?.first?.name == "IndexQueue")
        #expect(withEntries.considerations.isEmpty && withEntries.needsJudgment.isEmpty && withEntries.uncertainties.isEmpty)

        let absent = try StageDecoding.decode(StageDecoding.JudgmentResult.self, from: [:])
        #expect(absent.changeMap == nil)
    }

    @Test func architectureResultFallsBackToTheAssessmentsExplanation() throws {
        let result = try StageDecoding.decode(StageDecoding.ArchitectureResult.self, from: [
            "architecture": [
                "impact": "moderate", "headline": "New async hop",
                "explanation": ["text": "A queue now sits between publish and reindex.", "provenance": "fact"],
            ]
        ])
        #expect(result.architecture?.headline == "New async hop")
        #expect(result.architectureImpact?.text == "A queue now sits between publish and reindex.")
        #expect(result.components.isEmpty && result.edges.isEmpty && result.boundaries.isEmpty)

        let malformed = try StageDecoding.decode(StageDecoding.ArchitectureResult.self, from: ["architecture": "not an object"])
        #expect(malformed.architecture == nil)
        #expect(malformed.architectureImpact == nil)
    }
}
