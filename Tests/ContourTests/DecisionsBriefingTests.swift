import Testing
import Foundation
@testable import Contour

/// The Decisions lens draws each decision as a question, its options, a short why, and the
/// tradeoff it made — for new graphs from the fields the decisions stage writes, and for
/// older graphs by condensing what they already have.
struct DecisionsBriefingTests {

    /// The captured bat#3877 run: two design decisions, two implementation decisions, and
    /// Overview questions that point at them.
    private func fixtureGraph() throws -> PRGraph {
        let arch = try StageDecoding.decode(StageDecoding.ArchitectureResult.self, from: MockAnalysisFixtures.response(for: .architecture))
        let decisions = try StageDecoding.decode(StageDecoding.DecisionsResult.self, from: MockAnalysisFixtures.response(for: .decisions))
        let tradeoffs = try StageDecoding.decode(StageDecoding.TradeoffsResult.self, from: MockAnalysisFixtures.response(for: .tradeoffs))
        let flows = try StageDecoding.decode(StageDecoding.FlowsResult.self, from: MockAnalysisFixtures.response(for: .flows))
        let judgment = try StageDecoding.decode(StageDecoding.JudgmentResult.self, from: MockAnalysisFixtures.response(for: .judgment))
        var graph = ContourSampleData.publishTriggeredReindex
        graph.components = arch.components
        graph.architectureEdges = arch.edges
        graph.decisions = decisions.decisions
        graph.tradeoffs = tradeoffs.tradeoffs
        graph.flows = flows.flows
        graph.pr.considerations = judgment.considerations
        return graph
    }

    private func decision(_ id: String, level: AbstractionLevel = .system, options: [DecisionOption] = [],
                          shape: DecisionShape? = nil) -> DecisionNode {
        DecisionNode(
            id: id, title: "Title \(id)",
            decision: Statement(text: "Read one chunk (src/input.rs:12-20). Then stop.", provenance: .fact),
            rationale: [Statement(text: "Waiting could block a tty (src/input.rs:30). More detail.", provenance: .claim)],
            alternatives: [Statement(text: "Loop until 1 KB. It blocks.", provenance: .interpretation)],
            confidence: .medium, level: level, options: options, shape: shape
        )
    }

    // MARK: - Hierarchy and progress

    @Test func designDecisionsLeadAndImplementationDecisionsWait() throws {
        let graph = try fixtureGraph()
        #expect(graph.primaryDecisions.map(\.id) == ["inspect-buffered-prefix-not-first-line", "no-extra-blocking-read"])
        #expect(graph.implementationDecisions.map(\.id) == ["fallback-to-longer-first-line", "skip-read-on-empty-input"])
    }

    /// Progress means "I judged n of the consequential decisions", so implementation
    /// details don't count toward it.
    @Test func reviewProgressCountsOnlyDesignDecisions() throws {
        var graph = try fixtureGraph()
        #expect(graph.reviewProgress.total == 2)
        let impl = try #require(graph.decisions.firstIndex { $0.id == "skip-read-on-empty-input" })
        graph.decisions[impl].reviewerState = .accepted
        #expect(graph.reviewProgress.reviewed == 0)
        let design = try #require(graph.decisions.firstIndex { $0.id == "no-extra-blocking-read" })
        graph.decisions[design].reviewerState = .questioned
        #expect(graph.reviewProgress.reviewed == 1)
    }

    @Test func whenEverythingIsImplementationEverythingCounts() {
        var graph = ContourSampleData.publishTriggeredReindex
        graph.decisions = [decision("a", level: .implementation), decision("b", level: .implementation)]
        #expect(graph.primaryDecisions.count == 2)
        #expect(graph.implementationDecisions.isEmpty)
        #expect(graph.reviewProgress.total == 2)
    }

    // MARK: - The brief

    /// Older graphs have no options: the tradeoff's poles stand in, so the choice is still
    /// drawn — and the same axis isn't drawn a second time as the tradeoff.
    @Test func olderGraphsDrawTheChoiceFromTheTradeoff() throws {
        let graph = try fixtureGraph()
        let d = try #require(graph.decision("no-extra-blocking-read"))
        let brief = graph.brief(for: d)
        #expect(brief.shape == .binary)
        #expect(brief.options.map(\.label) == ["always fill 1024 bytes", "inspect what's buffered"])
        #expect(brief.chosen?.label == "inspect what's buffered")
        #expect(brief.tradeoff == nil)
        let why = try #require(brief.why)
        #expect(why.provenance == .claim)
        #expect(!why.text.contains("src/"))
        #expect(graph.splitSentencesCount(why.text) == 1)
    }

    @Test func explicitOptionsWinAndKeepTheTradeoff() {
        var graph = ContourSampleData.publishTriggeredReindex
        graph.decisions = [decision("d", options: [
            DecisionOption(label: "First line"), DecisionOption(label: "First 1 KB", detail: "better detection", chosen: true)
        ])]
        graph.decisions[0].question = "How much data should binary detection inspect?"
        graph.decisions[0].why = Statement(text: "Binary files can have a newline before their first NUL.", provenance: .claim)
        graph.tradeoffs = [TradeoffNode(id: "t", title: "T", poleA: "minimal buffering", poleB: "better detection",
                                        chosen: "poleB", explanation: Statement(text: "x", provenance: .interpretation),
                                        decisionIds: ["d"], poleAWeight: 0.8)]
        let brief = graph.brief(for: graph.decisions[0])
        #expect(brief.question == "How much data should binary detection inspect?")
        #expect(brief.shape == .binary)
        #expect(brief.chosen?.label == "First 1 KB")
        #expect(brief.why?.text == "Binary files can have a newline before their first NUL.")
        #expect(brief.tradeoff?.id == "t")
    }

    /// Not every choice is two-sided: three options can't be drawn as A ◀──▶ B, and an
    /// ordered scale stays a scale.
    @Test func shapeFollowsTheChoice() {
        let three = [DecisionOption(label: "Read more"), DecisionOption(label: "Use the buffer", chosen: true),
                     DecisionOption(label: "Skip streams")]
        var graph = ContourSampleData.publishTriggeredReindex
        graph.decisions = [
            decision("list", options: three, shape: .binary),
            decision("scale", options: three, shape: .threshold),
            decision("inferred", options: three),
        ]
        graph.tradeoffs = []
        #expect(graph.brief(for: graph.decisions[0]).shape == .options)
        #expect(graph.brief(for: graph.decisions[1]).shape == .threshold)
        #expect(graph.brief(for: graph.decisions[2]).shape == .options)
    }

    /// Options with nothing marked chosen can't show what the PR did, so they're ignored.
    @Test func withNothingToDrawTheAnswerIsOneSentence() {
        var graph = ContourSampleData.publishTriggeredReindex
        graph.decisions = [decision("d", options: [DecisionOption(label: "A"), DecisionOption(label: "B")])]
        graph.tradeoffs = []
        let brief = graph.brief(for: graph.decisions[0])
        #expect(brief.shape == nil)
        #expect(brief.question == "Title d")
        #expect(brief.answer == "Read one chunk.")
        #expect(brief.insteadOf == "Loop until 1 KB.")
    }

    // MARK: - Overview ↔ Decisions

    /// Each Overview question is reviewed on exactly one decision — the one "Review →" opens.
    @Test func overviewQuestionsLandOnTheirDecision() throws {
        let graph = try fixtureGraph()
        let onBlocking = graph.overviewQuestions(reviewedOn: "no-extra-blocking-read").map(\.id)
        #expect(onBlocking == ["stdin-chunking-nondeterminism"])
        let placed = graph.decisions.flatMap { graph.overviewQuestions(reviewedOn: $0.id).map(\.id) }
        #expect(placed.count == Set(placed).count)
        #expect(Set(placed) == Set(graph.thingsToThinkAbout.compactMap { graph.reviewDecisionId(for: $0) == nil ? nil : $0.id }))
    }

    @Test func aDecisionReachesItsArchitectureAndFlows() throws {
        let graph = try fixtureGraph()
        let d = try #require(graph.decision("no-extra-blocking-read"))
        let affects = graph.affects(d)
        #expect(affects.components.map(\.id) == ["input-reader", "input-source"])
        #expect(affects.edges.contains { $0.fromId == "input-reader" && $0.toId == "input-source" })
        #expect(affects.flows.map(\.id).contains("flow-stdin-binary-detection"))
    }

    // MARK: - Contextual chat

    @Test func anOptionCarriesItsDecisionTradeoffAndQuestions() throws {
        let graph = try fixtureGraph()
        let resolved = try #require(graph.resolve(.decisionOption(decisionId: "no-extra-blocking-read", index: 1)))
        #expect(resolved.kind == .option)
        #expect(resolved.title == "inspect what's buffered")
        #expect(resolved.lineage.last == graph.brief(for: graph.decision("no-extra-blocking-read")!).question)
        #expect(resolved.detail.contains("the option this PR chose"))
        #expect(resolved.detail.contains("always fill 1024 bytes"))
        #expect(resolved.detail.contains("Overview question reviewed on this decision: Is binary detection that depends on pipe chunking acceptable?"))
        #expect(resolved.detail.contains("Tradeoff: always fill 1024 bytes versus inspect what's buffered"))
        #expect(resolved.detailTarget == .decisionDetail("no-extra-blocking-read"))
        #expect(!ChatContextBuilder.availableExpansions(for: resolved).contains(.relatedDecisions))

        #expect(graph.resolve(.decisionOption(decisionId: "no-extra-blocking-read", index: 5)) == nil)
    }

    // MARK: - Decoding

    @Test func newDecisionFieldsDecodeLeniently() throws {
        let json = #"""
        {"id": "d", "title": "T", "decision": {"text": "x", "provenance": "fact"},
         "question": "Should it wait?", "shape": "spiral",
         "options": [{"label": "Wait"}, {"label": "Don't", "detail": "never blocks", "chosen": true}],
         "why": {"text": "Streams are interactive.", "provenance": "claim"}}
        """#
        let d = try JSONDecoder().decode(DecisionNode.self, from: Data(json.utf8))
        #expect(d.question == "Should it wait?")
        #expect(d.shape == nil)
        #expect(d.options.map(\.chosen) == [false, true])
        #expect(d.options.last?.detail == "never blocks")
        #expect(d.why?.provenance == .claim)

        let old = try JSONDecoder().decode(DecisionNode.self, from: Data(#"{"id": "d", "title": "T", "decision": {"text": "x", "provenance": "fact"}}"#.utf8))
        #expect(old.question == nil && old.options.isEmpty && old.why == nil)
    }
}

private extension PRGraph {
    func splitSentencesCount(_ text: String) -> Int { Self.splitSentences(text).count }
}
