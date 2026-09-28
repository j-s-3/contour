import Foundation
import Testing
@testable import Contour

/// `StageDecodingError.describe` turns each `DecodingError` case into a diagnosable-from-
/// the-UI message without the raw response — every existing test that touches
/// `StageDecodingError` builds one directly with a non-`DecodingError` underlying error
/// (its "\(error)" fallback), so none of the four real `DecodingError` branches were ever
/// exercised. These trigger each one through a real `JSONDecoder` failure.
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

    /// An unrecognized enum raw value (a `Provenance` the model didn't spell as documented)
    /// decodes as corrupted data, not a type mismatch or a missing key.
    @Test func describesCorruptedData() throws {
        let error = try decodeFailure(["intent": ["text": "x", "provenance": "not-a-real-provenance"]])
        #expect(error.errorDescription?.contains("corrupted data") == true)
    }

    /// The full message names the stage and keeps the raw response for the technical log,
    /// truncated rather than unbounded.
    @Test func errorDescriptionNamesTheStageAndKeepsTheRawResponse() throws {
        let error = try decodeFailure([:])
        #expect(error.errorDescription?.hasPrefix("Understanding stage returned JSON that didn't decode:") == true)
        #expect(error.errorDescription?.contains("Raw response (truncated):") == true)
    }

    // MARK: - StageDecoding.decode success paths and lenient array decoding

    /// The whole point of this file's custom `init(from:)`s: a real `pi` response can spell
    /// "found none" as an explicit JSON `null` on an array field instead of `[]`, and the
    /// synthesized `Decodable` would treat that as `DecodingError.valueNotFound`. Every
    /// result type's array fields must tolerate both an absent key and an explicit null.
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

    /// A stage response with real content decodes into real objects — the success path
    /// every other test in this file skips past on the way to a decode failure.
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

    /// `JudgmentResult.changeMap` is the one `Optional` (not lenient-defaulted) array field
    /// in this file — present-with-content, present-as-null, and absent all need to decode
    /// without throwing, and only "absent" should stay nil (matching an older cached graph).
    @Test func judgmentResultDecodesChangeMapInEveryShape() throws {
        let withEntries = try StageDecoding.decode(StageDecoding.JudgmentResult.self, from: [
            "changeMap": [["name": "IndexQueue", "filesChanged": 2]]
        ])
        #expect(withEntries.changeMap?.first?.name == "IndexQueue")
        #expect(withEntries.considerations.isEmpty && withEntries.needsJudgment.isEmpty && withEntries.uncertainties.isEmpty)

        let absent = try StageDecoding.decode(StageDecoding.JudgmentResult.self, from: [:])
        #expect(absent.changeMap == nil)
    }

    /// `ArchitectureResult` degrades a malformed `architecture` assessment to nil rather
    /// than failing the whole stage (`try?`), and falls back to the assessment's own
    /// explanation for `architectureImpact` when the model didn't send that field directly.
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
