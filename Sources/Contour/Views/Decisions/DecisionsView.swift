import SwiftUI

/// Default view shows only `.behavior`/`.system`-level decisions, compact — title, one-line
/// why, one-line cost/alternative, accept/question/discuss control. Implementation-level
/// decisions are collapsed behind "Show implementation decisions". Tradeoffs fold in here
/// as a one-line slider per decision rather than a separate wall of text.
struct DecisionsView: View {
    let graph: PRGraph
    /// A decision the navigation target asked for; scrolled to and briefly highlighted.
    var focusDecisionId: String? = nil
    var onSetState: (String, ReviewerState) -> Void
    var onOpenEvidence: (CodeRef) -> Void
    var onOpenTradeoff: (String) -> Void

    @State private var showImplementation = false

    private var systemDecisions: [DecisionNode] { graph.decisions.filter { $0.level <= .system } }
    private var implementationDecisions: [DecisionNode] { graph.decisions.filter { $0.level > .system } }

    var body: some View {
        if graph.decisions.isEmpty {
            ContentUnavailableView("No standout decisions", systemImage: "questionmark.diamond",
                description: Text("This PR didn't surface anything a reviewer would need to interrogate."))
        } else {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(systemDecisions.enumerated()), id: \.element.id) { index, decision in
                        DecisionCard(
                            index: index + 1, decision: decision,
                            tradeoffs: graph.tradeoffs(for: decision.id),
                            isFocused: decision.id == focusDecisionId,
                            onSetState: { onSetState(decision.id, $0) },
                            onOpenEvidence: onOpenEvidence,
                            onOpenTradeoff: onOpenTradeoff
                        )
                        .id(decision.id)
                    }
                    if systemDecisions.isEmpty {
                        Text("No system-level decisions surfaced — check implementation decisions below.")
                            .foregroundStyle(.secondary)
                    }
                    if !implementationDecisions.isEmpty {
                        implementationSection
                    }
                }
                .padding(20)
                .frame(maxWidth: 1300, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .onAppear { scroll(proxy) }
            .onChange(of: focusDecisionId) { _, _ in scroll(proxy) }
            }
        }
    }

    private func scroll(_ proxy: ScrollViewProxy) {
        guard let id = focusDecisionId else { return }
        if implementationDecisions.contains(where: { $0.id == id }) { showImplementation = true }
        DispatchQueue.main.async { withAnimation { proxy.scrollTo(id, anchor: .top) } }
    }

    private var implementationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                showImplementation.toggle()
            } label: {
                HStack {
                    Image(systemName: showImplementation ? "chevron.down" : "chevron.right")
                    Text("Show implementation decisions (\(implementationDecisions.count))")
                        .font(.callout.weight(.semibold))
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 8)

            if showImplementation {
                ForEach(Array(implementationDecisions.enumerated()), id: \.element.id) { index, decision in
                    DecisionCard(
                        index: index + 1, decision: decision,
                        tradeoffs: graph.tradeoffs(for: decision.id),
                        isFocused: decision.id == focusDecisionId,
                        onSetState: { onSetState(decision.id, $0) },
                        onOpenEvidence: onOpenEvidence,
                        onOpenTradeoff: onOpenTradeoff
                    )
                    .id(decision.id)
                }
            }
        }
    }
}

private struct DecisionCard: View {
    let index: Int
    let decision: DecisionNode
    let tradeoffs: [TradeoffNode]
    var isFocused = false
    var onSetState: (ReviewerState) -> Void
    var onOpenEvidence: (CodeRef) -> Void
    var onOpenTradeoff: (String) -> Void

    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text("\(circled(index))  \(decision.title)")
                    .font(.title3.weight(.semibold))
                Spacer()
                ConfidenceTag(confidence: decision.confidence)
            }

            // One-line why (the first rationale, if any) — the rest is behind "show more".
            oneLineStatement(label: "WHY", statement: decision.rationale.first ?? decision.decision)

            if let firstAlt = decision.alternatives.first {
                oneLineStatement(label: "ALTERNATIVE", statement: firstAlt)
            }

            ForEach(tradeoffs) { t in
                TradeoffSliderRow(tradeoff: t, onOpenDecision: nil, onOpen: { onOpenTradeoff(t.id) })
                    .reviewContextMenu(.tradeoff(t.id))
            }

            if hasMoreDetail {
                Button(expanded ? "Show less" : "Show more") { expanded.toggle() }
                    .buttonStyle(.link).font(.caption)
            }

            if expanded {
                expandedDetail
            }

            Divider()
            HStack {
                Text("Reviewer:").font(.caption).foregroundStyle(.secondary)
                ReviewerStateControl(state: decision.reviewerState, onSet: onSetState)
                if decision.reviewerState != .unreviewed {
                    Text(decision.reviewerState.label).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .padding(18)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(borderColor, lineWidth: decision.reviewerState == .unreviewed ? 0 : 1.4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.accentColor.opacity(isFocused ? 0.55 : 0), lineWidth: 2)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .reviewContextMenu(.decision(decision.id))
    }

    private var hasMoreDetail: Bool {
        decision.rationale.count > 1 || decision.alternatives.count > 1 || !decision.consequences.isEmpty || !decision.refs.isEmpty
    }

    @ViewBuilder
    private var expandedDetail: some View {
        VStack(alignment: .leading, spacing: 10) {
            field("DECISION") { StatementView(statement: decision.decision) }
            if decision.rationale.count > 1 {
                field("RATIONALE") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(decision.rationale) { StatementView(statement: $0) }
                    }
                }
            }
            if decision.alternatives.count > 1 {
                field("ALTERNATIVES") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(decision.alternatives) { StatementView(statement: $0) }
                    }
                }
            }
            if !decision.consequences.isEmpty {
                field("CONSEQUENCES") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(decision.consequences) { StatementView(statement: $0) }
                    }
                }
            }
            if !decision.refs.isEmpty {
                field("EVIDENCE") {
                    WrapChips(decision.refs) { ref in CodeRefChip(ref: ref) { onOpenEvidence(ref) } }
                }
            }
        }
    }

    private func oneLineStatement(label: String, statement: Statement) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label).font(.caption2.weight(.bold)).foregroundStyle(.secondary).frame(width: 70, alignment: .leading)
            ProvenanceBadge(provenance: statement.provenance, confidence: statement.confidence)
            Text(statement.text).font(.callout).lineLimit(2)
        }
    }

    private var borderColor: Color {
        switch decision.reviewerState {
        case .unreviewed: return .clear
        case .accepted: return .green.opacity(0.5)
        case .questioned: return .orange.opacity(0.5)
        case .discuss: return .red.opacity(0.5)
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption2.weight(.bold)).foregroundStyle(.secondary).tracking(0.5)
            content()
        }
    }

    private func circled(_ n: Int) -> String {
        let circled = ["①", "②", "③", "④", "⑤", "⑥", "⑦", "⑧", "⑨"]
        return n <= circled.count ? circled[n - 1] : "\(n)."
    }
}

private struct ConfidenceTag: View {
    let confidence: Confidence
    var body: some View {
        Text(confidence.label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(confidence.color)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(confidence.color.opacity(0.15), in: Capsule())
    }
}

/// The one-line tradeoff slider from the brief: two short poles, a dot showing where the
/// implementation landed, and an expandable row for why/evidence/related decision —
/// folded into Decisions rather than a separate wall of text.
struct TradeoffSliderRow: View {
    let tradeoff: TradeoffNode
    var onOpenDecision: ((String) -> Void)?
    var onOpen: (() -> Void)?
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                if let onOpen { onOpen() } else { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Text(tradeoff.poleA).font(.caption).foregroundStyle(tradeoff.poleAWeight < 0.5 ? .primary : .secondary)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.secondary.opacity(0.2)).frame(height: 4)
                            Circle().fill(Color.accentColor)
                                .frame(width: 10, height: 10)
                                .offset(x: max(0, min(geo.size.width - 10, geo.size.width * tradeoff.poleAWeight - 5)))
                        }
                        .frame(height: 10)
                    }
                    .frame(width: 90, height: 10)
                    Text(tradeoff.poleB).font(.caption).foregroundStyle(tradeoff.poleAWeight >= 0.5 ? .primary : .secondary)
                    Spacer()
                    if onOpen == nil {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
            .buttonStyle(.plain)

            if expanded {
                StatementView(statement: tradeoff.explanation)
                if !tradeoff.refs.isEmpty {
                    WrapChips(tradeoff.refs) { ref in CodeRefChip(ref: ref) { } }
                }
            }
        }
    }
}
