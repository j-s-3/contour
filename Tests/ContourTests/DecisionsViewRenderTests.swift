import AppKit
import SwiftUI
import Testing

@testable import Contour

@MainActor
struct DecisionsViewRenderTests {
    private func option(_ label: String, chosen: Bool = false, detail: String? = nil) -> DecisionOption {
        DecisionOption(label: label, detail: detail, chosen: chosen)
    }

    private var ref: CodeRef { CodeRef(path: "src/A.swift", startLine: 1, endLine: 5) }

    private func decision(
        _ id: String, shape: DecisionShape?, options: [DecisionOption],
        significance: ReviewSignificance = .high, state: ReviewerState = .unreviewed,
        note: String = "", rich: Bool = true
    ) -> DecisionNode {
        DecisionNode(
            id: id, title: "Decision \(id)",
            decision: Statement(text: "Did \(id). Then more.", provenance: .fact),
            rationale: rich ? [Statement(text: "Because \(id).", provenance: .claim, source: "PR description")] : [],
            alternatives: rich
                ? [Statement(text: "Instead of \(id).", provenance: .interpretation, confidence: .medium)] : [],
            consequences: rich
                ? [Statement(text: "Costs for \(id).", provenance: .interpretation, confidence: .low)] : [],
            confidence: .medium,
            refs: rich ? [ref] : [],
            tradeoffs: rich
                ? [
                    DecisionTradeoff(
                        dimensionA: "speed", dimensionB: "freshness", chosenPosition: 0.8,
                        explanation: Statement(text: "Trades speed.", provenance: .fact), refs: [ref]),
                    DecisionTradeoff(
                        dimensionA: "cost", dimensionB: "safety", chosenPosition: 0.2,
                        prominence: .secondary),
                ] : [],
            componentIds: ["page-publishing"],
            reviewerState: state, reviewerNote: note,
            question: "Should we \(id)?", options: options, shape: shape,
            why: rich ? Statement(text: "It lands here.", provenance: .interpretation, confidence: .high) : nil,
            significance: significance, impacts: [.correctness, .security, .performance, .reliability],
            significanceReason: nil
        )
    }

    private func graph(toReviewEmpty: Bool = false) -> PRGraph {
        var g = ContourSampleData.publishTriggeredReindex
        let level: ReviewSignificance = toReviewEmpty ? .low : .high
        g.decisions = [
            decision(
                "binary", shape: .binary, options: [option("Sync", chosen: true, detail: "inline"), option("Async")],
                significance: level),
            decision(
                "threshold", shape: .threshold,
                options: [option("1 KB"), option("4 KB", chosen: true), option("16 KB", detail: "big")],
                significance: level,
                state: .questioned, note: "Why 4?"),
            decision(
                "options", shape: .options,
                options: [option("A", chosen: true, detail: "d"), option("B"), option("C")],
                significance: level, state: .accepted),
            decision(
                "beforeafter", shape: .beforeAfter,
                options: [
                    option("Reader → Printer"), option("Reader → Inspector → Printer", chosen: true, detail: "checked"),
                ],
                significance: .low),
            decision("plain", shape: nil, options: [], significance: .low, state: .discuss, rich: false),
        ]
        g.pr.considerations = [
            Consideration(id: "q1", headline: "Is it safe?", impact: "detail", relatedIds: ["binary", "plain"])
        ]
        return g
    }

    private func layout<V: View>(_ view: V, width: CGFloat = 900) {
        let hosting = NSHostingView(rootView: view.environment(\.reviewActions, ReviewActions()))
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: 1600)
        hosting.layoutSubtreeIfNeeded()
        #expect(hosting.fittingSize.width >= 0)
    }

    private func withMode(_ mode: DecisionsView.Mode, _ body: () -> Void) {
        let key = "decisions.mode"
        let previous = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.set(mode.rawValue, forKey: key)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        body()
    }

    private func lens(_ graph: PRGraph, focus: DecisionsView.Focus? = nil) -> DecisionsView {
        DecisionsView(
            graph: graph, focus: focus, discussed: ["q1"],
            onSetState: { _, _ in }, onSetNote: { _, _ in }, onSetToReview: { _, _ in })
    }

    @Test func listModeRendersDecisionsToReviewAndOtherDecisions() {
        withMode(.list) { layout(lens(graph())) }
    }

    @Test func listModeWithNothingToReviewOpensOtherDecisions() {
        withMode(.list) { layout(lens(graph(toReviewEmpty: true))) }
    }

    @Test func oneAtATimeModeRenders() {
        withMode(.oneAtATime) { layout(lens(graph()), width: 800) }
        withMode(.oneAtATime) { layout(lens(graph(toReviewEmpty: true)), width: 800) }
    }

    @Test func focusedArrivalRendersForReviewAndOtherDecisions() {
        withMode(.list) {
            layout(lens(graph(), focus: .init(decisionId: "binary", considerationId: "q1")))
            layout(lens(graph(), focus: .init(decisionId: "plain")))
            layout(lens(graph(), focus: .init(decisionId: "missing")))
        }
        withMode(.oneAtATime) {
            layout(lens(graph(), focus: .init(decisionId: "beforeafter")))
        }
    }

    @Test func emptyGraphShowsTheUnavailableState() {
        var g = graph()
        g.decisions = []
        layout(lens(g))
    }

    private struct CardHost: View {
        let graph: PRGraph
        let decision: DecisionNode
        var number: Int?
        var expanded: Bool
        var arrived: Bool
        var considerationId: String?
        @FocusState private var noteFocus: String?

        var body: some View {
            DecisionCard(
                decision: decision, brief: graph.brief(for: decision), graph: graph, number: number,
                attentionReason: graph.attentionReason(for: decision),
                arrivedFromConsiderationId: considerationId,
                isSelected: arrived, isArrived: arrived, isExpanded: expanded,
                noteFocus: $noteFocus,
                onSetState: { _ in }, onSetNote: { _ in }, onToggleExpanded: {},
                onNotWorthReviewing: {}, onSelect: {})
        }
    }

    @Test func everyDecisionShapeRendersAsACardCollapsedAndExpanded() {
        let g = graph()
        for d in g.decisions {
            for expanded in [false, true] {
                layout(
                    CardHost(
                        graph: g, decision: d, number: 1, expanded: expanded, arrived: expanded, considerationId: "q1"))
            }
            layout(CardHost(graph: g, decision: d, number: nil, expanded: false, arrived: false, considerationId: nil))
        }
    }

    @Test func everyDecisionRendersAsAnOtherRowCollapsedAndExpanded() {
        let g = graph()
        for d in g.decisions {
            for expanded in [false, true] {
                layout(
                    OtherDecisionRow(
                        decision: d, brief: g.brief(for: d), graph: g, reason: g.attentionReason(for: d),
                        isSelected: expanded, isArrived: expanded, isExpanded: expanded,
                        onAddToReview: {}, onToggleExpanded: {}, onSelect: {}))
            }
        }
    }

    @Test func badgeChipAndButtonsRenderForEveryReviewerState() {
        for state in [ReviewerState.unreviewed, .accepted, .questioned, .discuss] {
            layout(DecisionBadge(number: 2, state: state))
            layout(DecisionBadge(number: nil, state: state))
            layout(ReviewedChip(state: state))
            layout(ReviewButtons(state: state, onSet: { _ in }))
        }
    }

    @Test func progressDotsRenderResolvedAndPending() {
        layout(ReviewProgressDots(graph: graph(), discussed: []))
        layout(ReviewProgressDots(graph: graph(), discussed: ["q1"]))
    }

    @Test func choiceViewRendersEveryShapeIncludingAnOptionlessAnswer() {
        let g = graph()
        for d in g.decisions {
            layout(DecisionChoiceView(decisionId: d.id, brief: g.brief(for: d)))
        }
        var withInstead = g.brief(for: g.decisions[4])
        withInstead.insteadOf = "the road not taken"
        layout(DecisionChoiceView(decisionId: "plain", brief: withInstead))
    }

    @Test func spectrumRendersBothSidesAndTheMidpoint() {
        for position in [0.0, 0.3, 0.5, 1.0] {
            layout(
                TradeoffSpectrum(tradeoff: DecisionTradeoff(dimensionA: "a", dimensionB: "b", chosenPosition: position))
            )
        }
    }

    @Test func drillDownRendersRichAndBareDecisions() {
        let g = graph()
        for d in g.decisions {
            layout(DecisionDrillDown(decision: d, graph: g))
        }
    }

    @Test func drillDownRendersAffectedArchitectureAndFlows() {
        var g = ContourSampleData.publishTriggeredReindex
        let d = g.decisions[0]
        #expect(!g.affects(d).components.isEmpty)
        g.decisions[0].componentIds = g.components.map(\.id)
        layout(DecisionDrillDown(decision: g.decisions[0], graph: g))
    }
}
