import SwiftUI

/// Tradeoffs are folded into Decisions as an inline one-line slider (see
/// `TradeoffSliderRow` / `DecisionsView`). This screen stays reachable from the sidebar
/// and command palette as a focused list of just the sliders, for a reviewer who wants
/// every tradeoff at a glance without wading through decisions — never a verdict on
/// whether the chosen pole was correct.
struct TradeoffsView: View {
    let graph: PRGraph
    var onOpenEvidence: (CodeRef) -> Void
    var onOpenDecision: (String) -> Void

    var body: some View {
        if graph.tradeoffs.isEmpty {
            ContentUnavailableView("No tradeoffs surfaced", systemImage: "arrow.left.arrow.right.circle",
                description: Text("Nothing in this PR forced a visible tradeoff between competing goals."))
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(graph.tradeoffs) { t in
                        card(t)
                    }
                }
                .padding(20)
                .frame(maxWidth: 1100, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func card(_ t: TradeoffNode) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(t.title).font(.callout.weight(.semibold))
            TradeoffSliderRow(tradeoff: t)
            if !t.decisionIds.isEmpty {
                HStack(spacing: 8) {
                    Text("From:").font(.caption2).foregroundStyle(.secondary)
                    ForEach(t.decisionIds, id: \.self) { id in
                        if let d = graph.decision(id) {
                            Button { onOpenDecision(id) } label: { Text(d.title) }.buttonStyle(.link).font(.caption2)
                        }
                    }
                }
            }
            if !t.refs.isEmpty {
                WrapChips(t.refs) { ref in CodeRefChip(ref: ref) { onOpenEvidence(ref) } }
            }
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .reviewContextMenu(.tradeoff(t.id))
        .id(t.id)
    }
}
