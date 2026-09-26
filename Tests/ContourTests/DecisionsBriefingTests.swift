import Testing
import Foundation
@testable import Contour

/// The Decisions lens draws each decision as a question, its options, a short why, and the
/// tradeoff it made — for new graphs from the fields the decisions stage writes, and for
/// older graphs by condensing what they already have.
struct DecisionsBriefingTests {

    /// The captured bat#3877 run: four decisions, two of them system-level with substantial
    /// tradeoffs, and Overview questions that point at them.
    private func fixtureGraph() throws -> PRGraph {
        let arch = try StageDecoding.decode(StageDecoding.ArchitectureResult.self, from: MockAnalysisFixtures.response(for: .architecture))
        let decisions = try StageDecoding.decode(StageDecoding.DecisionsResult.self, from: MockAnalysisFixtures.response(for: .decisions))
        let flows = try StageDecoding.decode(StageDecoding.FlowsResult.self, from: MockAnalysisFixtures.response(for: .flows))
        let judgment = try StageDecoding.decode(StageDecoding.JudgmentResult.self, from: MockAnalysisFixtures.response(for: .judgment))
        var graph = ContourSampleData.publishTriggeredReindex
        graph.components = arch.components
        graph.architectureEdges = arch.edges
        graph.decisions = decisions.decisions
        graph.flows = flows.flows
        graph.pr.considerations = judgment.considerations
        return graph
    }

    private func decision(_ id: String, level: AbstractionLevel = .system, options: [DecisionOption] = [],
                          shape: DecisionShape? = nil, significance: ReviewSignificance? = nil) -> DecisionNode {
        DecisionNode(
            id: id, title: "Title \(id)",
            decision: Statement(text: "Read one chunk (src/input.rs:12-20). Then stop.", provenance: .fact),
            rationale: [Statement(text: "Waiting could block a tty (src/input.rs:30). More detail.", provenance: .claim)],
            alternatives: [Statement(text: "Loop until 1 KB. It blocks.", provenance: .interpretation)],
            confidence: .medium, level: level, options: options, shape: shape, significance: significance
        )
    }

    private func concern(_ id: String, on decisionId: String) -> Consideration {
        Consideration(id: id, question: "Is \(decisionId) safe?", detail: "", relatedIds: [decisionId])
    }

    // MARK: - Significance decides attention, not abstraction

    /// The captured run predates significance, so it's inferred: the two decisions that move
    /// hard along a real tradeoff are the ones to review. The long-first-line fallback has an
    /// Overview question (about test coverage) but no tradeoff, so it stays with the others.
    @Test func capturedRunPromotesTheDecisionsWithSubstantialTradeoffs() throws {
        let graph = try fixtureGraph()
        #expect(graph.decisionsToReview.map(\.id) == ["inspect-multi-line-prefix", "use-already-buffered-bytes"])
        #expect(graph.otherDecisions.map(\.id) == ["fallback-to-longer-first-line", "skip-read-on-empty-input"])
        let fallback = try #require(graph.decision("fallback-to-longer-first-line"))
        #expect(graph.significance(of: fallback) == .medium)
        #expect(graph.attentionReason(for: fallback).contains("Overview asks"))
    }

    /// An implementation choice that matters is reviewed; an architectural one that doesn't
    /// isn't.
    @Test func levelNeverDecidesVisibility() {
        var graph = ContourSampleData.publishTriggeredReindex
        graph.pr.considerations = []
        graph.decisions = [
            decision("helper-home", level: .system, significance: .low),
            decision("idempotent-retry", level: .implementation, significance: .high)
        ]
        #expect(graph.decisionsToReview.map(\.id) == ["idempotent-retry"])
        #expect(graph.otherDecisions.map(\.id) == ["helper-home"])
    }

    /// An Overview concern about a decision raises its significance a step: enough to promote
    /// a medium one, not enough to promote a low one.
    @Test func overviewConcernsRaiseSignificance() {
        var graph = ContourSampleData.publishTriggeredReindex
        graph.decisions = [decision("medium", significance: .medium), decision("low", significance: .low),
                           decision("quiet", significance: .medium)]
        graph.pr.considerations = [concern("c1", on: "medium"), concern("c2", on: "low")]
        #expect(graph.decisionsToReview.map(\.id) == ["medium"])
        #expect(graph.otherDecisions.map(\.id) == ["low", "quiet"])
    }

    /// Without an assessed significance, only a tradeoff that leans substantially promotes.
    @Test func inferredSignificanceFollowsTradeoffMagnitude() {
        var d = decision("d")
        #expect(PRGraph.inferredSignificance(d) == .low)
        d.tradeoffs = [DecisionTradeoff(dimensionA: "a", dimensionB: "b", chosenPosition: 0.6)]
        #expect(PRGraph.inferredSignificance(d) == .medium)
        d.tradeoffs = [DecisionTradeoff(dimensionA: "a", dimensionB: "b", chosenPosition: 0.2)]
        #expect(PRGraph.inferredSignificance(d) == .high)
    }

    /// The reviewer controls the filter: Add to review and Not worth reviewing override the
    /// analysis, and moving a decision back to where the analysis put it clears the override.
    @Test func reviewerCanMoveDecisionsEitherWay() {
        var graph = ContourSampleData.publishTriggeredReindex
        graph.pr.considerations = []
        graph.decisions = [decision("a", significance: .high), decision("b", significance: .low)]
        graph.setToReview(true, forDecision: "b")
        graph.setToReview(false, forDecision: "a")
        #expect(graph.decisionsToReview.map(\.id) == ["b"])
        #expect(graph.otherDecisions.map(\.id) == ["a"])
        #expect(graph.decision("b")?.reviewerPlacement == .review)
        #expect(graph.reviewProgress.total == 1)
        graph.setToReview(true, forDecision: "a")
        #expect(graph.decision("a")?.reviewerPlacement == nil)
        #expect(graph.decisionsToReview.map(\.id) == ["a", "b"])
    }

    /// Progress means "I judged n of the decisions to review", so other decisions don't count.
    @Test func reviewProgressCountsOnlyDecisionsToReview() throws {
        var graph = try fixtureGraph()
        #expect(graph.reviewProgress.total == 2)
        let other = try #require(graph.decisions.firstIndex { $0.id == "skip-read-on-empty-input" })
        graph.decisions[other].reviewerState = .accepted
        #expect(graph.reviewProgress.reviewed == 0)
        let review = try #require(graph.decisions.firstIndex { $0.id == "use-already-buffered-bytes" })
        graph.decisions[review].reviewerState = .questioned
        #expect(graph.reviewProgress.reviewed == 1)
    }

    /// Nothing is promoted to fill the list: when no choice stands out, the reviewer is told
    /// so and the decisions found are listed under Other Decisions.
    @Test func whenNothingStandsOutNothingIsPromoted() {
        var graph = ContourSampleData.publishTriggeredReindex
        graph.pr.considerations = []
        graph.decisions = [decision("a", significance: .low), decision("b", significance: .medium)]
        #expect(graph.decisionsToReview.isEmpty)
        #expect(graph.otherDecisions.map(\.id) == ["b", "a"])
        #expect(graph.reviewProgress.total == 0)
        #expect(DecisionsView.framing(toReview: 0, total: 2).hasPrefix("No choice in this PR stood out"))
    }

    @Test func framingSaysMoreWereFound() {
        #expect(DecisionsView.framing(toReview: 2, total: 4)
                == "2 choices in this PR appear worth your attention, out of 4 identified. Do you agree with them?")
        #expect(DecisionsView.framing(toReview: 1, total: 1)
                == "1 choice in this PR appears worth your attention. Do you agree with it?")
    }

    @Test func significanceDecodesLeniently() throws {
        let json = #"""
        {"id": "d", "title": "t", "decision": {"text": "x", "provenance": "fact"}, "confidence": "high",
         "level": "implementation", "significance": "high",
         "impacts": ["Data integrity", "failure-behavior", "vibes", "concurrency"],
         "significanceReason": "  Retries could duplicate writes.  "}
        """#
        let d = try JSONDecoder().decode(DecisionNode.self, from: Data(json.utf8))
        #expect(d.significance == .high)
        #expect(d.impacts == [.dataIntegrity, .failureBehavior, .concurrency])
        #expect(d.significanceReason == "Retries could duplicate writes.")
        let unknown = try JSONDecoder().decode(DecisionNode.self, from: Data(json.replacingOccurrences(of: #""significance": "high""#, with: #""significance": "critical""#).utf8))
        #expect(unknown.significance == nil)
        let roundTrip = try JSONDecoder().decode(DecisionNode.self, from: JSONEncoder().encode(d))
        #expect(roundTrip.impacts == d.impacts)
        #expect(roundTrip.significance == .high)
    }

    // MARK: - The brief

    /// A decision with a tradeoff but no options: the tradeoff's dimensions stand in, so the
    /// choice is still drawn — and the same axis isn't drawn a second time as the tradeoff.
    @Test func withoutOptionsTheChoiceIsDrawnFromTheTradeoff() {
        var graph = ContourSampleData.publishTriggeredReindex
        var d = decision("d")
        d.tradeoffs = [DecisionTradeoff(dimensionA: "detection completeness", dimensionB: "streaming behavior", chosenPosition: 0.85)]
        graph.decisions = [d]
        let brief = graph.brief(for: d)
        #expect(brief.shape == .binary)
        #expect(brief.options.map(\.label) == ["detection completeness", "streaming behavior"])
        #expect(brief.chosen?.label == "streaming behavior")
        #expect(brief.tradeoff == nil)
        let why = try! #require(brief.why)
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
        let traded = DecisionTradeoff(dimensionA: "minimal buffering", dimensionB: "detection completeness", chosenPosition: 0.8)
        graph.decisions[0].tradeoffs = [traded]
        let brief = graph.brief(for: graph.decisions[0])
        #expect(brief.question == "How much data should binary detection inspect?")
        #expect(brief.shape == .binary)
        #expect(brief.chosen?.label == "First 1 KB")
        #expect(brief.why?.text == "Binary files can have a newline before their first NUL.")
        #expect(brief.tradeoff == traded)
    }

    /// When the options already name the two qualities, the tradeoff line would only repeat
    /// them, so the alternatives carry it alone.
    @Test func aTradeoffTheOptionsAlreadySayIsNotDrawnTwice() {
        var graph = ContourSampleData.publishTriggeredReindex
        var d = decision("d", options: [
            DecisionOption(label: "Always fill 1 KB", detail: "deterministic classification"),
            DecisionOption(label: "Use what's buffered", detail: "non-blocking streaming", chosen: true)
        ])
        d.tradeoffs = [DecisionTradeoff(dimensionA: "Deterministic classification", dimensionB: "non-blocking streaming.", chosenPosition: 0.9)]
        graph.decisions = [d]
        #expect(graph.brief(for: d).tradeoff == nil)
    }

    /// The primary tradeoff is drawn on the decision; secondary ones wait in the drill-down.
    @Test func thePrimaryTradeoffLeadsAndSecondaryOnesWait() {
        let secondary = DecisionTradeoff(dimensionA: "one sample source", dimensionB: "old behavior kept", prominence: .secondary)
        let primary = DecisionTradeoff(dimensionA: "detection completeness", dimensionB: "streaming behavior", prominence: .primary)
        var d = decision("d", options: [DecisionOption(label: "A"), DecisionOption(label: "B", chosen: true)])
        d.tradeoffs = [secondary, primary]
        var graph = ContourSampleData.publishTriggeredReindex
        graph.decisions = [d]
        #expect(d.primaryTradeoff == primary)
        #expect(d.secondaryTradeoffs == [secondary])
        #expect(graph.brief(for: d).tradeoff == primary)
    }

    /// A before/after diagram needs the old structure and the new, chosen one; anything else
    /// degrades to a plain two-option line.
    @Test func beforeAfterNeedsTheNewStructureChosen() {
        var graph = ContourSampleData.publishTriggeredReindex
        graph.decisions = [
            decision("ok", options: [DecisionOption(label: "Reader → Printer"), DecisionOption(label: "Reader → Inspector → Printer", chosen: true)], shape: .beforeAfter),
            decision("backwards", options: [DecisionOption(label: "New", chosen: true), DecisionOption(label: "Old")], shape: .beforeAfter),
        ]
        #expect(graph.brief(for: graph.decisions[0]).shape == .beforeAfter)
        #expect(graph.brief(for: graph.decisions[1]).shape == .binary)
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
        #expect(graph.brief(for: graph.decisions[0]).shape == .options)
        #expect(graph.brief(for: graph.decisions[1]).shape == .threshold)
        #expect(graph.brief(for: graph.decisions[2]).shape == .options)
    }

    /// Options with nothing marked chosen can't show what the PR did, so they're ignored.
    @Test func withNothingToDrawTheAnswerIsOneSentence() {
        var graph = ContourSampleData.publishTriggeredReindex
        graph.decisions = [decision("d", options: [DecisionOption(label: "A"), DecisionOption(label: "B")])]
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
        let onBlocking = graph.overviewQuestions(reviewedOn: "use-already-buffered-bytes").map(\.id)
        #expect(onBlocking == ["short-first-read-gap"])
        let placed = graph.decisions.flatMap { graph.overviewQuestions(reviewedOn: $0.id).map(\.id) }
        #expect(placed.count == Set(placed).count)
        #expect(Set(placed) == Set(graph.thingsToThinkAbout.compactMap { graph.reviewDecisionId(for: $0) == nil ? nil : $0.id }))
    }

    @Test func aDecisionReachesItsArchitectureAndFlows() throws {
        let graph = try fixtureGraph()
        let d = try #require(graph.decision("use-already-buffered-bytes"))
        let affects = graph.affects(d)
        #expect(affects.components.map(\.id) == ["input-reading", "content-inspection"])
        #expect(affects.edges.contains { $0.fromId == "input-reading" && $0.toId == "content-inspection" })
        #expect(affects.flows.map(\.id).contains("flow-cli-stdin-binary-detection"))
    }

    // MARK: - Contextual chat

    @Test func anOptionCarriesItsDecisionTradeoffAndQuestions() throws {
        let graph = try fixtureGraph()
        let resolved = try #require(graph.resolve(.decisionOption(decisionId: "use-already-buffered-bytes", index: 1)))
        #expect(resolved.kind == .option)
        #expect(resolved.title == "Use what's buffered")
        #expect(resolved.lineage.last == graph.brief(for: graph.decision("use-already-buffered-bytes")!).question)
        #expect(resolved.detail.contains("the option this PR chose"))
        #expect(resolved.detail.contains("Read until 1 KB"))
        #expect(resolved.detail.contains("Overview question reviewed on this decision: Can binary data still slip through when the first read is short?"))
        #expect(resolved.detail.contains("Tradeoff: detection completeness versus streaming responsiveness"))
        #expect(resolved.detailTarget == .decisionDetail("use-already-buffered-bytes"))
        #expect(!ChatContextBuilder.availableExpansions(for: resolved).contains(.relatedDecisions))

        #expect(graph.resolve(.decisionOption(decisionId: "use-already-buffered-bytes", index: 5)) == nil)
    }

    /// Right-clicking a tradeoff asks about it inside its decision: the chat gets the choice,
    /// the alternatives, the rationale, the Overview question, and the evidence behind the
    /// tradeoff itself, and "Open details" is the decision.
    @Test func aTradeoffIsDiscussedAsPartOfItsDecision() throws {
        let graph = try fixtureGraph()
        let d = try #require(graph.decision("use-already-buffered-bytes"))
        let t = try #require(d.primaryTradeoff)
        let resolved = try #require(graph.resolve(.tradeoff(decisionId: d.id, index: 0)))
        #expect(resolved.kind == .tradeoff)
        #expect(resolved.title == "detection completeness vs. streaming responsiveness")
        #expect(resolved.lineage.last == graph.brief(for: d).question)
        #expect(resolved.detail.contains("Option: Use what's buffered"))
        #expect(resolved.detail.contains("Overview question reviewed on this decision"))
        #expect(resolved.refs == t.refs)
        #expect(resolved.decisionIds == [d.id])
        #expect(resolved.detailTarget == .decisionDetail(d.id))
        #expect(ChatContextBuilder.linkToken(for: resolved.subject) == "[[decision:\(d.id)]]")
        #expect(graph.resolve(.tradeoff(decisionId: d.id, index: 3)) == nil)
    }

    /// The captured run, read the way a reviewer opening Decisions would: two decisions to
    /// review, each drawn with the tradeoff that makes it worth reviewing; two other
    /// decisions whose options already say what was traded.
    @Test func eachDecisionToReviewCarriesItsTradeoff() throws {
        let graph = try fixtureGraph()
        for d in graph.decisionsToReview {
            let brief = graph.brief(for: d)
            #expect(brief.shape != nil, "\(d.id) has no drawn choice")
            #expect(brief.tradeoff != nil, "\(d.id) has no tradeoff drawn")
            #expect(brief.why != nil)
            #expect(d.tradeoffs.allSatisfy { !$0.refs.isEmpty }, "\(d.id)'s tradeoff lost its evidence")
        }
        let blocking = try #require(graph.decision("use-already-buffered-bytes"))
        #expect(blocking.primaryTradeoff?.chosenDimension == "streaming responsiveness")
        #expect(graph.otherDecisions.allSatisfy { $0.tradeoffs.isEmpty })
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
