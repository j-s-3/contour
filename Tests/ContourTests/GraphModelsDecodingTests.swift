import Foundation
import Testing
@testable import Contour

/// `GraphModels.swift`'s `init(from:)` implementations are deliberately lenient — real model
/// output omits optional keys, and a malformed element must drop just itself, never the
/// whole array or the object around it (§ "Decoding is deliberately lenient" in CLAUDE.md).
/// These pin the specific types and lenient-array behaviors that no other suite exercised
/// directly: minimal-payload decoding for `EntryPointNode`/`QuestionNode`/`ChangeMapEntry`,
/// and `DecisionNode`'s two lenient-array fields (`tradeoffs` via `LenientDecodable`,
/// `impacts` via `DecisionImpact.init(lenient:)`).
struct GraphModelsDecodingTests {

    @Test func entryPointNodeFillsInDefaultsForMissingOptionalFields() throws {
        let minimal = try JSONDecoder().decode(
            EntryPointNode.self, from: Data(#"{"id": "e1", "title": "PUT /pages"}"#.utf8)
        )
        #expect(minimal.kind == "unknown")
        #expect(minimal.changeKind == .touched)
        #expect(minimal.refs.isEmpty)
        #expect(minimal.flowId == nil)
        #expect(minimal.triggersLabel == nil)

        let full = try JSONDecoder().decode(
            EntryPointNode.self,
            from: Data(#"{"id": "e1", "title": "PUT /pages", "kind": "REST", "changeKind": "new", "flowId": "f1"}"#.utf8)
        )
        #expect(full.kind == "REST")
        #expect(full.changeKind == .new)
        #expect(full.flowId == "f1")
    }

    @Test func questionNodeDefaultsIdAndArraysWhenAbsent() throws {
        let minimal = try JSONDecoder().decode(QuestionNode.self, from: Data(#"{"text": "Why?"}"#.utf8))
        #expect(minimal.text == "Why?")
        #expect(!minimal.id.isEmpty, "a missing id still gets a stable placeholder rather than crashing")
        #expect(minimal.relatedIds.isEmpty)
        #expect(minimal.refs.isEmpty)
    }

    @Test func changeMapEntryDefaultsFilesChangedToZero() throws {
        let entry = try JSONDecoder().decode(ChangeMapEntry.self, from: Data(#"{"name": "Index Queue"}"#.utf8))
        #expect(entry.name == "Index Queue")
        #expect(entry.filesChanged == 0)
        #expect(entry.id == "Index Queue")
    }

    /// A minimal decision (only the four required fields) must still produce every
    /// defaulted array/enum/optional rather than throwing — this is the shape a stage that
    /// only fills in the essentials sends.
    @Test func decisionNodeDefaultsEveryOptionalFieldWhenOnlyTheEssentialsArePresent() throws {
        let json = #"{"id": "d1", "title": "Pick an approach", "decision": {"text": "Did X.", "provenance": "fact"}, "confidence": "high"}"#
        let d = try JSONDecoder().decode(DecisionNode.self, from: Data(json.utf8))
        #expect(d.rationale.isEmpty && d.alternatives.isEmpty && d.consequences.isEmpty)
        #expect(d.refs.isEmpty && d.tradeoffs.isEmpty && d.componentIds.isEmpty)
        #expect(d.reviewerState == .unreviewed)
        #expect(d.reviewerNote == "")
        #expect(d.level == .system)
        #expect(d.question == nil)
        #expect(d.options.isEmpty)
        #expect(d.shape == nil)
        #expect(d.why == nil)
        #expect(d.significance == nil)
        #expect(d.impacts.isEmpty)
        #expect(d.significanceReason == nil)
        #expect(d.reviewerPlacement == nil)
    }

    /// A malformed element in `tradeoffs` (missing a required dimension) drops only that
    /// element via `LenientDecodable`, keeping the well-formed one and the decision itself.
    @Test func decisionNodeDropsOnlyTheMalformedTradeoff() throws {
        let json = """
        {"id": "d1", "title": "T", "decision": {"text": "Did X.", "provenance": "fact"}, "confidence": "high",
         "tradeoffs": [{"dimensionA": "speed", "dimensionB": "safety"}, {"dimensionA": "onlyOneSide"}]}
        """
        let d = try JSONDecoder().decode(DecisionNode.self, from: Data(json.utf8))
        #expect(d.tradeoffs.count == 1)
        #expect(d.tradeoffs.first?.dimensionA == "speed")
    }

    /// An unrecognized impact string is dropped via `DecisionImpact.init(lenient:)` rather
    /// than failing the whole decode; a recognized one survives alongside it.
    @Test func decisionNodeDropsUnrecognizedImpactsButKeepsKnownOnes() throws {
        let json = """
        {"id": "d1", "title": "T", "decision": {"text": "Did X.", "provenance": "fact"}, "confidence": "high",
         "impacts": ["correctness", "not-a-real-impact"]}
        """
        let d = try JSONDecoder().decode(DecisionNode.self, from: Data(json.utf8))
        #expect(d.impacts == [.correctness])
    }
}
