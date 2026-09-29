import SwiftUI

struct DecisionCard: View {
    let decision: DecisionNode
    let brief: DecisionBrief
    let graph: PRGraph
    let number: Int?
    let attentionReason: String
    var arrivedFromConsiderationId: String?
    var isSelected: Bool
    var isArrived: Bool
    var isExpanded: Bool
    var noteFocus: FocusState<String?>.Binding
    var onSetState: (ReviewerState) -> Void
    var onSetNote: (String) -> Void
    var onToggleExpanded: () -> Void
    var onNotWorthReviewing: () -> Void
    var onSelect: () -> Void

    @Environment(\.reviewActions) private var actions

    private var questions: [Consideration] {
        DecisionsViewLogic.questions(
            from: graph.overviewQuestions(reviewedOn: decision.id),
            leadingWith: arrivedFromConsiderationId)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                DecisionBadge(number: number, state: decision.reviewerState)
                Text(brief.question)
                    .font(.system(size: number == nil ? 17 : 20, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .reviewContextMenu(.decision(decision.id))
                Spacer(minLength: 12)
                ReviewedChip(state: decision.reviewerState)
            }

            whyHighlighted
                .padding(.leading, 36)
                .padding(.top, -10)

            DecisionChoiceView(decisionId: decision.id, brief: brief)
                .padding(.leading, 36)

            briefGrid
                .padding(.leading, 36)

            HStack(spacing: 8) {
                ReviewButtons(state: decision.reviewerState, onSet: onSetState)
                Spacer()
                Button(action: onNotWorthReviewing) {
                    Label("Not worth reviewing", systemImage: "arrow.down.to.line")
                        .font(.callout)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Move this to Other Decisions — it stops being judged here")
                .padding(.trailing, 8)
                Button(action: onToggleExpanded) {
                    HStack(spacing: 4) {
                        Text(isExpanded ? "Less" : "More…")
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2.weight(.semibold))
                    }
                    .font(.callout)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Rationale, alternatives, what it traded, consequences, what this affects, and evidence (M)")
            }
            .padding(.leading, 36)

            if DecisionsViewLogic.showsNoteField(state: decision.reviewerState, note: decision.reviewerNote) {
                noteField
                    .padding(.leading, 36)
            }

            if isExpanded {
                DecisionDrillDown(decision: decision, graph: graph)
                    .padding(.leading, 36)
                    .transition(.opacity)
            }
        }
        .padding(22)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    isSelected ? Color.accentColor.opacity(0.55) : Color.secondary.opacity(0.18),
                    lineWidth: isSelected ? 1.5 : 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.accentColor.opacity(isArrived ? 0.08 : 0))
                .allowsHitTesting(false)
        )
        .shadow(color: Color.accentColor.opacity(isArrived ? 0.35 : 0), radius: 10)
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture(perform: onSelect)
    }

    private var whyHighlighted: some View {
        let impacts = DecisionsViewLogic.impactsSummary(decision.impacts)
        var line = Text("")
        if decision.reviewerPlacement == .review { line = line + Text("You added this to review. ") }
        if !impacts.isEmpty { line = line + Text("Impacts \(impacts)").fontWeight(.medium) + Text(" — ") }
        line = line + Text(attentionReason)
        return
            line
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .help("Why this is highlighted for review")
    }

    private var briefGrid: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 12) {
            if let tradeoff = brief.tradeoff, let index = decision.tradeoffs.firstIndex(of: tradeoff) {
                GridRow {
                    rowLabel("What we're trading")
                    TradeoffSpectrum(tradeoff: tradeoff)
                        .reviewContextMenu(.tradeoff(decisionId: decision.id, index: index)) {
                            if !decision.consequences.isEmpty {
                                Button("Show Consequences") { if !isExpanded { onToggleExpanded() } }
                            }
                        }
                }
            }
            if let why = brief.why {
                GridRow {
                    rowLabel(
                        DecisionsViewLogic.whyLabel(hasShape: brief.shape != nil, hasTradeoff: brief.tradeoff != nil))
                    (Text(why.text)
                        + Text("   " + DecisionsViewLogic.provenanceNote(why)).font(.caption).foregroundStyle(.tertiary))
                        .font(.body)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .help(DecisionsViewLogic.provenanceHelp(why))
                        .reviewContextMenu(.decision(decision.id))
                }
            }
            if !questions.isEmpty {
                GridRow {
                    rowLabel("Overview asks")
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(questions) { item in
                            Text(item.reviewerAsk)
                                .font(.body.weight(item.id == arrivedFromConsiderationId ? .semibold : .regular))
                                .foregroundStyle(.orange)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                                .help(item.judgment == nil ? item.impact : "\(item.headline). \(item.impact)")
                                .reviewContextMenu(.consideration(item.id))
                        }
                    }
                }
            }
            let appearances = graph.flowAppearances(ofDecision: decision.id)
            if !appearances.isEmpty {
                GridRow {
                    rowLabel("Appears in")
                    FlowLayout(spacing: 12) {
                        ForEach(appearances, id: \.flow.id) { flow, nodeId in
                            Button {
                                actions.navigate(.flowNodeDetail(flowId: flow.id, nodeId: nodeId))
                            } label: {
                                Label(graph.scenarioTitle(for: flow) + " flow", systemImage: "arrow.triangle.branch")
                                    .font(.callout)
                            }
                            .buttonStyle(.link)
                            .reviewContextMenu(.flowNode(flowId: flow.id, nodeId: nodeId))
                        }
                    }
                }
            }
        }
    }

    private func rowLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(0.5)
            .foregroundStyle(.secondary)
            .gridColumnAlignment(.leading)
    }

    private var noteField: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "questionmark.bubble")
                .foregroundStyle(.orange)
            TextField(
                "What would you ask the author?",
                text: Binding(
                    get: { decision.reviewerNote },
                    set: { onSetNote($0) }
                ), axis: .vertical
            )
            .textFieldStyle(.plain)
            .lineLimit(1...4)
            .focused(noteFocus, equals: decision.id)
            .onSubmit { noteFocus.wrappedValue = nil }
            .onExitCommand { noteFocus.wrappedValue = nil }
        }
        .font(.callout)
        .padding(10)
        .background(Color.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.orange.opacity(0.25)))
    }
}

struct OtherDecisionRow: View {
    let decision: DecisionNode
    let brief: DecisionBrief
    let graph: PRGraph
    let reason: String
    var isSelected: Bool
    var isArrived: Bool
    var isExpanded: Bool
    var onAddToReview: () -> Void
    var onToggleExpanded: () -> Void
    var onSelect: () -> Void

    @Environment(\.reviewActions) private var actions

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: decision.reviewerState == .unreviewed ? "circle" : decision.reviewerState.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(decision.reviewerState.tint)
                    .frame(width: 16)
                Text(brief.question)
                    .font(.body.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .reviewContextMenu(.decision(decision.id))
                Spacer(minLength: 12)
                ReviewedChip(state: decision.reviewerState)
            }

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 6) {
                GridRow {
                    label("Chosen")
                    Text(DecisionsViewLogic.chosenSummary(brief))
                        .font(.callout)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                GridRow {
                    label("Why it's here")
                    Text(reason)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let question = graph.overviewQuestions(reviewedOn: decision.id).first {
                    GridRow {
                        label("Overview asks")
                        Text(question.reviewerAsk)
                            .font(.callout)
                            .foregroundStyle(.orange)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .reviewContextMenu(.consideration(question.id))
                    }
                }
            }
            .padding(.leading, 26)

            HStack(spacing: 14) {
                Button(action: onAddToReview) {
                    Label("Add to review", systemImage: "arrow.up.to.line")
                }
                .help("Make this one of the decisions you review and judge")
                Button {
                    actions.ask(.decision(decision.id))
                } label: {
                    Label("Ask…", systemImage: "sparkles")
                }
                Button(action: onToggleExpanded) {
                    HStack(spacing: 4) {
                        Text(isExpanded ? "Hide" : "Show")
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2.weight(.semibold))
                    }
                }
                .help("The options, reasoning, what it affects, and evidence (M)")
            }
            .buttonStyle(.link)
            .font(.callout)
            .padding(.leading, 26)

            if isExpanded {
                VStack(alignment: .leading, spacing: 16) {
                    DecisionChoiceView(decisionId: decision.id, brief: brief)
                        .padding(.top, 6)
                    DecisionDrillDown(decision: decision, graph: graph)
                }
                .padding(.leading, 26)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Color.accentColor.opacity(isArrived ? 0.08 : 0))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.accentColor.opacity(isSelected ? 0.7 : 0))
                .frame(width: 3)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }

    private func label(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption2.weight(.bold))
            .tracking(0.5)
            .foregroundStyle(.secondary)
            .frame(width: 104, alignment: .leading)
            .gridColumnAlignment(.leading)
    }
}

struct DecisionBadge: View {
    let number: Int?
    let state: ReviewerState

    var body: some View {
        ZStack {
            Circle().fill(tint.opacity(state == .unreviewed ? 0.12 : 0.18))
            switch state {
            case .unreviewed:
                if let number {
                    Text(verbatim: "\(number)")
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                } else {
                    Circle().fill(Color.secondary.opacity(0.6)).frame(width: 5, height: 5)
                }
            default:
                Image(systemName: state.symbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tint)
            }
        }
        .frame(width: 24, height: 24)
        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 6 }
    }

    private var tint: Color { DecisionsViewLogic.badgeTint(for: state) }
}

struct ReviewedChip: View {
    let state: ReviewerState

    var body: some View {
        if state != .unreviewed {
            Label(state.chipLabel, systemImage: state.symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(state.tint)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(state.tint.opacity(0.12), in: Capsule())
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
    }
}

struct ReviewProgressDots: View {
    let graph: PRGraph
    let discussed: Set<String>

    private func fill(_ dot: DecisionsViewLogic.DotFill) -> Color {
        switch dot {
        case .pending: return Color.secondary.opacity(0.25)
        case .discussed: return .green
        case .judged(let state): return state.tint
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(graph.thingsToThinkAbout) { item in
                let state = graph.decision(graph.reviewDecisionId(for: item))?.reviewerState ?? .unreviewed
                let resolved = graph.isResolved(item, discussed: discussed)
                Circle()
                    .fill(fill(DecisionsViewLogic.progressDotFill(resolved: resolved, state: state)))
                    .frame(width: 7, height: 7)
                    .help(item.headline + (resolved ? " — resolved" : ""))
            }
        }
    }
}

struct ReviewButtons: View {
    let state: ReviewerState
    var onSet: (ReviewerState) -> Void

    var body: some View {
        HStack(spacing: 8) {
            button(.accepted, "Looks good", shortcut: "A")
            button(.questioned, "Question", shortcut: "Q")
            button(.discuss, "Discuss", shortcut: "C")
        }
    }

    private func button(_ target: ReviewerState, _ title: String, shortcut: String) -> some View {
        let isOn = state == target
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { onSet(target) }
        } label: {
            Label(title, systemImage: target.symbol)
                .font(.callout.weight(isOn ? .semibold : .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundStyle(isOn ? target.tint : Color.primary)
                .background(
                    isOn ? target.tint.opacity(0.16) : Color.secondary.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 7)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(isOn ? target.tint.opacity(0.5) : Color.secondary.opacity(0.22))
                )
                .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help(DecisionsViewLogic.reviewButtonHelp(isOn: isOn, target: target, title: title, shortcut: shortcut))
    }
}
