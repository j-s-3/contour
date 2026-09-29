import Foundation
import Testing

@testable import Contour

struct OverviewBriefingTests {
    @Test func considerationsFromTheJudgmentStageWin() {
        var graph = ContourSampleData.publishTriggeredReindex
        graph.pr.considerations = [
            Consideration(id: "c1", headline: "Is a queue hop acceptable?", impact: "Publishing gets slower.")
        ]
        #expect(graph.thingsToThinkAbout.map(\.id) == ["c1"])
    }

    @Test func olderGraphsAreCondensedInOrder() {
        var graph = ContourSampleData.publishTriggeredReindex
        graph.pr.considerations = nil
        let items = graph.thingsToThinkAbout
        #expect(items.map(\.kind) == [.concern, .concern, .question])
        #expect(items.first?.headline == "Can the index queue absorb a burst of publishes without falling behind?")
    }

    @Test func condensingSplitsObservationImpactAndDecisionAndDropsCodeLocations() {
        let statement = Statement(
            text:
                "The fix reads only the first chunk (src/input.rs:273-274). Pipes can deliver short chunks. Is timing-dependent classification acceptable? More detail follows here.",
            provenance: .interpretation, confidence: .medium
        )
        let item = PRGraph.condense(statement, id: "x", kind: .concern)
        #expect(item.headline == "The fix reads only the first chunk.")
        #expect(item.impact == "Pipes can deliver short chunks.")
        #expect(item.judgment == "Is timing-dependent classification acceptable?")
        #expect(!item.headline.contains("src/"))
        #expect(item.evidence == statement.text)
        #expect(item.confidence == .medium)
    }

    @Test func condensingAStatementWithoutAQuestionHasNoDecision() {
        let item = PRGraph.condense(
            Statement(text: "No timeout is set on evaluate(). It can hang the upload.", provenance: .interpretation),
            id: "y", kind: .concern
        )
        #expect(item.headline == "No timeout is set on evaluate().")
        #expect(item.impact == "It can hang the upload.")
        #expect(item.judgment == nil)
        #expect(item.evidence == nil)
    }

    @Test func condensingABareQuestionUsesItAsTheHeadline() {
        let item = PRGraph.condense(
            Statement(text: "Should this be silent?", provenance: .interpretation), id: "q", kind: .question)
        #expect(item.headline == "Should this be silent?")
        #expect(item.impact == "")
        #expect(item.judgment == nil)
    }

    @Test func abbreviationsAndBareCitationsDontBreakHeadlines() {
        let item = PRGraph.condense(
            Statement(
                text:
                    "The fix is partial for stdin (e.g. `gpg -d ... | bat`). The test at src/input.rs:435-455 checks it.",
                provenance: .interpretation),
            id: "z", kind: .concern
        )
        #expect(item.headline == "The fix is partial for stdin (e.g. `gpg -d ... | bat`).")
        #expect(item.impact == "The test checks it.")
    }

    @Test func legacyConsiderationKeysStillDecode() throws {
        let json =
            #"{"question": "Should this be silent?", "detail": "It hides errors.", "explanation": "See x.swift:3.", "kind": "somethingNew", "confidence": "very"}"#
        let item = try JSONDecoder().decode(Consideration.self, from: Data(json.utf8))
        #expect(item.headline == "Should this be silent?")
        #expect(item.impact == "It hides errors.")
        #expect(item.evidence == "See x.swift:3.")
        #expect(item.judgment == nil)
        #expect(item.category == nil)
        #expect(item.kind == .concern)
        #expect(item.provenance == .interpretation)
        #expect(item.confidence == nil)
    }

    @Test func considerationDecodesTheReviewerFacingFields() throws {
        let json =
            #"{"category": "ERROR HANDLING", "headline": "Token failures behave differently", "impact": "Auth failures fail the whole run.", "decision": "Should auth failures fail the run?", "evidence": "mint() throws past gather()."}"#
        let item = try JSONDecoder().decode(Consideration.self, from: Data(json.utf8))
        #expect(item.category == .errorHandling)
        #expect(item.headline == "Token failures behave differently")
        #expect(item.impact == "Auth failures fail the whole run.")
        #expect(item.judgment == "Should auth failures fail the run?")
        #expect(item.evidence == "mint() throws past gather().")
    }

    @Test func newKeysWinOverLegacyKeys() throws {
        let json =
            #"{"headline": "New", "question": "Old?", "impact": "New impact", "detail": "Old detail", "evidence": "New evidence", "explanation": "Old"}"#
        let item = try JSONDecoder().decode(Consideration.self, from: Data(json.utf8))
        #expect(item.headline == "New")
        #expect(item.impact == "New impact")
        #expect(item.evidence == "New evidence")
    }

    @Test func aConsiderationWithoutAHeadlineOrQuestionFailsToDecode() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Consideration.self, from: Data(#"{"impact": "x"}"#.utf8))
        }
    }

    @Test func reviewerFacingFieldsDropMarkdownBackticksButEvidenceKeepsThem() throws {
        let json =
            #"{"headline": "Files show a `<BINARY>` header", "impact": "Unless `-A` is passed.", "decision": "Keep `--binary`?", "evidence": "See `try_new`."}"#
        let item = try JSONDecoder().decode(Consideration.self, from: Data(json.utf8))
        #expect(item.headline == "Files show a <BINARY> header")
        #expect(item.impact == "Unless -A is passed.")
        #expect(item.judgment == "Keep --binary?")
        #expect(item.evidence == "See `try_new`.")
    }

    @Test func blankDecisionsAndUnknownCategoriesDecodeAsAbsent() throws {
        let json = #"{"headline": "H", "decision": "   ", "category": "vibes"}"#
        let item = try JSONDecoder().decode(Consideration.self, from: Data(json.utf8))
        #expect(item.judgment == nil)
        #expect(item.category == nil)
    }

    @Test(arguments: [
        ("error-handling", ConsiderationCategory.errorHandling), ("Test Coverage", .testCoverage),
        ("testing", .testCoverage), ("compatibility", .compatibility), ("RELIABILITY", .reliability),
        ("performance", .scaling), ("scalability", .scaling), ("scaling", .scaling), ("security", .security),
        ("architecture", .architecture), ("product_behaviour", .productBehavior),
        ("PRODUCT BEHAVIOR", .productBehavior),
        ("behavior", .productBehavior),
    ])
    func categoriesDecodeLeniently(raw: String, expected: ConsiderationCategory) {
        #expect(ConsiderationCategory(lenient: raw) == expected)
    }

    @Test func everyCategoryHasALabelAndRoundTrips() throws {
        for category in ConsiderationCategory.allCases {
            #expect(!category.label.isEmpty)
            let data = try JSONEncoder().encode(category)
            #expect(try JSONDecoder().decode(ConsiderationCategory.self, from: data) == category)
        }
    }

    @Test func aConsiderationRoundTripsThroughTheCacheEncoding() throws {
        let item = Consideration(
            id: "a", category: .security, judgmentType: .securityDecision, headline: "H", impact: "I", judgment: "D?",
            kind: .question, evidence: "E", relatedIds: ["d1"])
        let decoded = try JSONDecoder().decode(Consideration.self, from: JSONEncoder().encode(item))
        #expect(decoded == item)
    }

    @Test func briefingReadsAsPlainSentences() {
        let full = Consideration(
            id: "a", headline: "Token failures differ", impact: "They fail the run.", judgment: "Should they?")
        #expect(full.briefing == "Token failures differ. They fail the run. Your judgment: Should they?")
        let bare = Consideration(id: "b", headline: "Is this safe?", impact: "")
        #expect(bare.briefing == "Is this safe?")
    }

    @Test func briefingReadsInDecisionBriefOrder() {
        let item = Consideration(
            id: "a", headline: "Reads use write credentials", context: "One credential path serves reads and writes",
            impact: "A leak exposes more than reads need.", tradeoff: "A second path is more to maintain.",
            moreContext: "Deeper background.", judgment: "Should reads get their own credential?",
            assumptions: ["Permissions are configured elsewhere."])
        #expect(
            item.briefing
                == "Reads use write credentials. One credential path serves reads and writes. A leak exposes more than reads need. A second path is more to maintain. Your judgment: Should reads get their own credential?"
        )
    }

    @Test func decisionBriefFieldsDecodeInTheirOwnKeys() throws {
        let json =
            #"{"headline": "H", "context": "What the system does.", "impact": "Why it matters.", "tradeoff": "One side, other side.", "moreContext": "Deeper.", "judgment": "J?", "assumptions": ["Inferred a thing.", "  ", "Could not confirm `x`."]}"#
        let item = try JSONDecoder().decode(Consideration.self, from: Data(json.utf8))
        #expect(item.context == "What the system does.")
        #expect(item.impact == "Why it matters.")
        #expect(item.tradeoff == "One side, other side.")
        #expect(item.moreContext == "Deeper.")
        #expect(item.assumptions == ["Inferred a thing.", "Could not confirm x."])
    }

    @Test func missingDecisionBriefFieldsDecodeAsAbsent() throws {
        let item = try JSONDecoder().decode(
            Consideration.self, from: Data(#"{"headline": "H", "impact": "I", "tradeoff": null}"#.utf8))
        #expect(item.context == nil)
        #expect(item.tradeoff == nil)
        #expect(item.moreContext == nil)
        #expect(item.assumptions == [])
    }

    @Test func blankDecisionBriefProseDecodesAsAbsent() throws {
        let json = #"{"headline": "H", "context": "  ", "tradeoff": "", "moreContext": "\n"}"#
        let item = try JSONDecoder().decode(Consideration.self, from: Data(json.utf8))
        #expect(item.context == nil)
        #expect(item.tradeoff == nil)
        #expect(item.moreContext == nil)
    }

    @Test func decisionBriefProseDropsMarkdownBackticks() throws {
        let json =
            #"{"headline": "H", "context": "Calls `reindex()` once.", "tradeoff": "Keep `-A`, or not.", "moreContext": "See `queue`."}"#
        let item = try JSONDecoder().decode(Consideration.self, from: Data(json.utf8))
        #expect(item.context == "Calls reindex() once.")
        #expect(item.tradeoff == "Keep -A, or not.")
        #expect(item.moreContext == "See queue.")
    }

    @Test func whyItMattersIsAnAliasForImpactThatImpactOverrides() throws {
        let alias = try JSONDecoder().decode(
            Consideration.self, from: Data(#"{"headline": "H", "whyItMatters": "Aliased."}"#.utf8))
        #expect(alias.impact == "Aliased.")
        let both = try JSONDecoder().decode(
            Consideration.self,
            from: Data(#"{"headline": "H", "impact": "Primary.", "whyItMatters": "Aliased.", "detail": "Old."}"#.utf8))
        #expect(both.impact == "Primary.")
        let legacy = try JSONDecoder().decode(
            Consideration.self, from: Data(#"{"headline": "H", "whyItMatters": "Aliased.", "detail": "Old."}"#.utf8))
        #expect(legacy.impact == "Aliased.")
    }

    @Test func aDecisionBriefRoundTripsThroughTheCacheEncoding() throws {
        let item = Consideration(
            id: "a", headline: "H", context: "C", impact: "I", tradeoff: "T", moreContext: "M", judgment: "J?",
            assumptions: ["A"])
        let decoded = try JSONDecoder().decode(Consideration.self, from: JSONEncoder().encode(item))
        #expect(decoded == item)
    }

    @Test func judgmentStageDecodesImplicationsAsPlainStatements() throws {
        let raw: [String: Any] = [
            "implications": [
                ["text": "Reads now need `write` access.", "provenance": "fact"],
                ["text": "Bursts may lag.", "provenance": "interpretation", "confidence": "medium"],
            ],
            "considerations": [],
        ]
        let result = try StageDecoding.decode(StageDecoding.JudgmentResult.self, from: raw)
        #expect(result.implications.map(\.text) == ["Reads now need write access.", "Bursts may lag."])
        #expect(result.implications.map(\.provenance) == [.fact, .interpretation])
        #expect(result.implications.last?.confidence == .medium)
    }

    @Test func judgmentStageWithoutImplicationsDecodesToNone() throws {
        let result = try StageDecoding.decode(StageDecoding.JudgmentResult.self, from: ["considerations": []])
        #expect(result.implications.isEmpty)
    }

    @Test func implicationsAreAppliedAndClearedWithTheJudgmentStage() throws {
        var graph = ContourSampleData.publishTriggeredReindex
        graph.pr.implications = nil
        let result = try StageDecoding.decode(
            StageDecoding.JudgmentResult.self,
            from: ["implications": [["text": "Search now tracks publishing.", "provenance": "interpretation"]]])
        graph.apply(.judgment(result))
        #expect(graph.pr.implications?.map(\.text) == ["Search now tracks publishing."])
        graph.clear(.judgment)
        #expect(graph.pr.implications == nil)
        #expect(graph.pr.considerations == nil)
    }

    @Test(arguments: [
        ("potential_problem", JudgmentType.potentialProblem), ("bug", .potentialProblem),
        ("CONFIRM INTENT", .confirmIntent), ("intentional", .confirmIntent),
        ("design-decision", .designDecision), ("tradeoff", .designDecision),
        ("compatibility decision", .compatibilityDecision), ("compatibility", .compatibilityDecision),
        ("operational_risk", .operationalRisk), ("operations", .operationalRisk),
        ("security-decision", .securityDecision), ("security", .securityDecision),
        ("unclear requirement", .unclearRequirement), ("open-question", .unclearRequirement),
        ("external-dependency", .externalDependency), ("cross-product dependency", .externalDependency),
    ])
    func judgmentTypesDecodeLeniently(raw: String, expected: JudgmentType) {
        #expect(JudgmentType(lenient: raw) == expected)
    }

    @Test func everyJudgmentTypeHasALabelAndRoundTrips() throws {
        for type in JudgmentType.allCases {
            #expect(!type.label.isEmpty)
            #expect(try JSONDecoder().decode(JudgmentType.self, from: JSONEncoder().encode(type)) == type)
        }
        #expect(JudgmentType(lenient: "vibes") == nil)
    }

    @Test func judgmentTypeDecodesAndAnUnknownOneIsAbsent() throws {
        let known = try JSONDecoder().decode(
            Consideration.self, from: Data(#"{"headline": "H", "judgmentType": "confirm_intent"}"#.utf8))
        #expect(known.judgmentType == .confirmIntent)
        let unknown = try JSONDecoder().decode(
            Consideration.self, from: Data(#"{"headline": "H", "judgmentType": "hunch"}"#.utf8))
        #expect(unknown.judgmentType == nil)
    }

    @Test func theContextLabelJoinsCategoryAndJudgmentType() {
        #expect(
            Consideration(id: "a", category: .compatibility, judgmentType: .confirmIntent, headline: "H", impact: "")
                .contextLabel
                == "Compatibility · Confirm intent")
        #expect(Consideration(id: "b", category: .security, headline: "H", impact: "").contextLabel == "Security")
        #expect(
            Consideration(id: "c", judgmentType: .operationalRisk, headline: "H", impact: "").contextLabel
                == "Operational risk")
        #expect(Consideration(id: "d", headline: "H", impact: "").contextLabel == nil)
    }

    @Test func theContextLabelDoesNotRepeatTheCategoryInTheJudgmentType() {
        #expect(
            Consideration(
                id: "a", category: .compatibility, judgmentType: .compatibilityDecision, headline: "H", impact: ""
            ).contextLabel == "Compatibility · Decision")
        #expect(
            Consideration(id: "b", category: .security, judgmentType: .securityDecision, headline: "H", impact: "")
                .contextLabel == "Security · Decision")
        #expect(
            Consideration(id: "c", category: .reliability, judgmentType: .operationalRisk, headline: "H", impact: "")
                .contextLabel == "Reliability · Operational risk")
        #expect(
            Consideration(id: "d", category: .architecture, judgmentType: .securityDecision, headline: "H", impact: "")
                .contextLabel == "Architecture · Security decision")
        #expect(
            Consideration(id: "e", judgmentType: .compatibilityDecision, headline: "H", impact: "").contextLabel
                == "Compatibility decision")
    }

    @Test func theJudgmentDecodesFromItsOwnKeyAndFromTheLegacyDecisionKey() throws {
        let current = try JSONDecoder().decode(
            Consideration.self, from: Data(#"{"headline": "H", "judgment": "Should `X` happen?"}"#.utf8))
        #expect(current.judgment == "Should X happen?")
        let legacy = try JSONDecoder().decode(
            Consideration.self, from: Data(#"{"headline": "H", "decision": "Should Y happen?"}"#.utf8))
        #expect(legacy.judgment == "Should Y happen?")
        let both = try JSONDecoder().decode(
            Consideration.self, from: Data(#"{"headline": "H", "judgment": "New?", "decision": "Old?"}"#.utf8))
        #expect(both.judgment == "New?")
        let blank = try JSONDecoder().decode(
            Consideration.self, from: Data(#"{"headline": "H", "judgment": "  "}"#.utf8))
        #expect(blank.judgment == nil)
    }

    @Test func theReviewerAskIsTheJudgmentWhenThereIsOne() {
        #expect(Consideration(id: "a", headline: "H", impact: "", judgment: "D?").reviewerAsk == "D?")
        #expect(Consideration(id: "b", headline: "H", impact: "").reviewerAsk == "H")
    }

    @Test func judgmentStageDecodesConsiderations() throws {
        let raw: [String: Any] = [
            "considerations": [
                ["id": "a", "question": "Q?", "detail": "D.", "kind": "question", "relatedIds": ["d1"]]
            ],
            "needsJudgment": [], "uncertainties": [], "questions": [],
        ]
        let result = try StageDecoding.decode(StageDecoding.JudgmentResult.self, from: raw)
        #expect(result.considerations.first?.kind == .question)
        #expect(result.considerations.first?.relatedIds == ["d1"])
    }

    @Test func stageOutcomeDecodesAndDegrades() throws {
        let ok = try JSONDecoder().decode(
            BehaviorStage.self, from: Data(#"{"label": "Server rejects", "outcome": "failure"}"#.utf8))
        #expect(ok.outcome == .failure)
        let odd = try JSONDecoder().decode(
            BehaviorStage.self, from: Data(#"{"label": "Run", "outcome": "maybe"}"#.utf8))
        #expect(odd.outcome == nil)
    }

    @Test func mockFixturesStillYieldThingsToThinkAbout() throws {
        let behavior = try StageDecoding.decode(
            StageDecoding.BehaviorChangeResult.self, from: MockAnalysisFixtures.response(for: .behaviorChange)
        )
        let judgment = try StageDecoding.decode(
            StageDecoding.JudgmentResult.self, from: MockAnalysisFixtures.response(for: .judgment)
        )
        var graph = ContourSampleData.publishTriggeredReindex
        graph.pr.considerations = nil
        graph.behaviorChanges = behavior.behaviorChanges
        graph.pr.needsJudgment = judgment.needsJudgment
        graph.pr.uncertainties = judgment.uncertainties
        let items = graph.thingsToThinkAbout
        #expect(!items.isEmpty)
        #expect(items.allSatisfy { !$0.headline.contains("src/") })
    }

    @Test func mockFixturesCarryBudgetedConsiderations() throws {
        let judgment = try StageDecoding.decode(
            StageDecoding.JudgmentResult.self, from: MockAnalysisFixtures.response(for: .judgment)
        )
        #expect((1...5).contains(judgment.considerations.count))
        #expect(judgment.considerations.allSatisfy { !$0.headline.isEmpty && !$0.impact.isEmpty })
        let behavior = try StageDecoding.decode(
            StageDecoding.BehaviorChangeResult.self, from: MockAnalysisFixtures.response(for: .behaviorChange)
        )
        #expect(behavior.behaviorChanges.first?.after.last?.outcome != nil)
    }

    @Test func thingsToThinkAboutOnlyGrowWhileStagesLand() throws {
        func fixture<T: Decodable>(_ type: T.Type, _ stage: PipelineStage) throws -> T {
            try StageDecoding.decode(type, from: MockAnalysisFixtures.response(for: stage))
        }
        let stages: [(PipelineStage, StageResult)] = [
            (.behaviorChange, .behaviorChange(try fixture(StageDecoding.BehaviorChangeResult.self, .behaviorChange))),
            (.understanding, .understanding(try fixture(StageDecoding.UnderstandingResult.self, .understanding))),
            (.decisions, .decisions(try fixture(StageDecoding.DecisionsResult.self, .decisions).decisions)),
            (.architecture, .architecture(try fixture(StageDecoding.ArchitectureResult.self, .architecture))),
            (.flows, .flows(try fixture(StageDecoding.FlowsResult.self, .flows))),
            (.judgment, .judgment(try fixture(StageDecoding.JudgmentResult.self, .judgment))),
        ]

        var graph = ContourSampleData.publishTriggeredReindex
        for stage in PipelineStage.analysis { graph.clear(stage) }
        var analysis = AnalysisState()
        var shown: [String] = []
        for (stage, result) in stages {
            analysis.stages[stage] = .running(detail: nil)
            graph.apply(result)
            analysis.stages[stage] = .done
            let items = graph.linked().thingsToThinkAbout(during: analysis)?.map(\.id)
            if stage != .judgment {
                #expect(items == nil, "placeholder until judgment, not \(items ?? []) after \(stage)")
            }
            if let items {
                #expect(Array(items.prefix(shown.count)) == shown, "\(stage) removed or reordered \(shown)")
                shown = items
            }
        }
        #expect(!shown.isEmpty)
        #expect(shown == graph.pr.considerations?.map(\.id))
    }

    @Test func thingsToThinkAboutShowAtOnceWhenNothingMoreIsComing() {
        let graph = ContourSampleData.publishTriggeredReindex
        #expect(graph.thingsToThinkAbout(during: AnalysisState(isComplete: true))?.isEmpty == false)
        #expect(
            graph.thingsToThinkAbout(during: AnalysisState(stages: [.judgment: .stale])) == graph.thingsToThinkAbout)
        #expect(
            graph.thingsToThinkAbout(during: AnalysisState(stages: [.judgment: .failed("boom")]))
                == graph.thingsToThinkAbout)
        #expect(graph.thingsToThinkAbout(during: AnalysisState(stages: [.judgment: .running(detail: nil)])) == nil)
    }
}
