import SwiftUI

struct DecisionDrillDownActions {
    let decisionId: String
    let actions: ReviewActions

    func openEvidence(_ ref: CodeRef) { actions.navigate(.evidence(ref)) }
    func open(_ target: NavigationTarget) { actions.navigate(target) }
    func ask() { actions.ask(.decision(decisionId)) }

    static func edgeLabel(_ edge: ArchitectureEdge, in graph: PRGraph) -> String {
        let from = graph.component(edge.fromId)?.title ?? edge.fromId
        let to = graph.component(edge.toId)?.title ?? edge.toId
        return DecisionsViewLogic.edgeTitle(from: from, to: to)
    }
}

struct DecisionDrillDown: View {
    let decision: DecisionNode
    let graph: PRGraph

    @Environment(\.reviewActions) private var environmentActions

    private var drill: DecisionDrillDownActions {
        DecisionDrillDownActions(decisionId: decision.id, actions: environmentActions)
    }

    var body: some View {
        let affects = graph.affects(decision)
        VStack(alignment: .leading, spacing: 16) {
            Divider()
            section("How it's implemented") { line(decision.decision) }
            if !decision.rationale.isEmpty {
                section("Rationale") { ForEach(decision.rationale) { line($0) } }
            }
            if !decision.alternatives.isEmpty {
                section("Alternatives considered") { ForEach(decision.alternatives) { line($0) } }
            }
            if !decision.tradeoffs.isEmpty {
                section(DecisionsViewLogic.tradeoffsTitle(count: decision.tradeoffs.count)) {
                    ForEach(Array(decision.tradeoffs.enumerated()), id: \.offset) { index, tradeoff in
                        tradeoffDetail(tradeoff, index: index)
                    }
                }
            }
            if !decision.consequences.isEmpty {
                section("Consequences") { ForEach(decision.consequences) { line($0) } }
            }
            if !affects.components.isEmpty || !affects.edges.isEmpty || !affects.flows.isEmpty {
                section("Affects") { affectsLinks(affects) }
            }
            if !decision.refs.isEmpty {
                section("Evidence") {
                    WrapChips(decision.refs) { ref in CodeRefChip(ref: ref, action: { drill.openEvidence(ref) }) }
                }
            }
            HStack(spacing: 14) {
                Text(
                    DecisionsViewLogic.drillDownFooter(
                        level: decision.level.label, confidence: decision.confidence.label)
                )
                .font(.caption)
                .foregroundStyle(.tertiary)
                Button(action: drill.ask) {
                    Label("Ask about this…", systemImage: "sparkles").font(.caption)
                }
                .buttonStyle(.link)
            }
        }
    }

    private func tradeoffDetail(_ tradeoff: DecisionTradeoff, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            TradeoffSpectrum(tradeoff: tradeoff)
                .reviewContextMenu(.tradeoff(decisionId: decision.id, index: index))
            if let explanation = tradeoff.explanation { line(explanation) }
            if !tradeoff.refs.isEmpty {
                WrapChips(tradeoff.refs) { ref in CodeRefChip(ref: ref, action: { drill.openEvidence(ref) }) }
            }
        }
    }

    private func affectsLinks(_ affects: (components: [ComponentNode], edges: [ArchitectureEdge], flows: [FlowNode]))
        -> some View
    {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
            if !affects.components.isEmpty || !affects.edges.isEmpty {
                GridRow {
                    Text("Architecture").font(.callout).foregroundStyle(.secondary)
                    FlowLayout(spacing: 10) {
                        ForEach(affects.components) { c in
                            link(c.title, "square.stack.3d.up", .componentDetail(c.id))
                                .reviewContextMenu(.component(c.id))
                        }
                        ForEach(affects.edges) { e in
                            link(DecisionDrillDownActions.edgeLabel(e, in: graph), "arrow.right", .edgeDetail(e.id))
                                .reviewContextMenu(.relationship(e.id))
                        }
                    }
                }
            }
            if !affects.flows.isEmpty {
                GridRow {
                    Text("Flows").font(.callout).foregroundStyle(.secondary)
                    FlowLayout(spacing: 10) {
                        ForEach(affects.flows) { f in
                            link(graph.scenarioTitle(for: f), "arrow.triangle.branch", .flowDetail(f.id))
                                .reviewContextMenu(.flow(f.id))
                        }
                    }
                }
            }
        }
    }

    private func link(_ title: String, _ symbol: String, _ target: NavigationTarget) -> some View {
        Button(action: { drill.open(target) }) {
            Label(title, systemImage: symbol).font(.callout)
        }
        .buttonStyle(.link)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(0.5)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func line(_ statement: Statement) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(statement.text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            ProvenanceMark(provenance: statement.provenance, confidence: statement.confidence, source: statement.source)
        }
    }
}
