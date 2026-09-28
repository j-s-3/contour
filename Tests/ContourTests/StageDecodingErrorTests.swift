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
}
