import SwiftUI

struct DecisionsView: View {
    let graph: PRGraph
    var focus: Focus?
    var discussed: Set<String> = []
    var onSetState: (String, ReviewerState) -> Void
    var onSetNote: (String, String) -> Void
    var onSetToReview: (String, Bool) -> Void

    struct Focus: Equatable {
        var decisionId: String
        var considerationId: String? = nil
    }

    enum Mode: String {
        case list
        case oneAtATime
    }

    @Environment(\.reviewActions) private var actions
    @AppStorage("decisions.mode") private var mode: Mode = .list
    @State private var selectedId: String?
    @State private var arrivedId: String?
    @State private var expandedIds: Set<String> = []
    @State private var showOther = false
    @FocusState private var keyboardFocused: Bool
    @FocusState private var noteFocus: String?

    private var toReview: [DecisionNode] { graph.decisionsToReview }
    private var other: [DecisionNode] { graph.otherDecisions }
    private var otherShown: Bool { showOther || toReview.isEmpty }
    private var sequence: [DecisionNode] { toReview + (otherShown ? other : []) }
    private var selected: DecisionNode? { graph.decision(selectedId) ?? sequence.first }

    var body: some View {
        if graph.decisions.isEmpty {
            ContentUnavailableView("No standout decisions", systemImage: "questionmark.diamond",
                description: Text("This PR didn't surface a choice a reviewer would need to judge."))
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                            .padding(.bottom, 24)
                        switch mode {
                        case .list: list
                        case .oneAtATime: oneAtATime
                        }
                        shortcutsHint
                            .padding(.top, 28)
                    }
                    .padding(.horizontal, 40)
                    .padding(.vertical, 32)
                    .frame(maxWidth: mode == .list ? 940 : 780, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .focusable()
                .focusEffectDisabled()
                .focused($keyboardFocused)
                .onKeyPress(phases: .down) { press in handleKey(press, proxy: proxy) }
                .onAppear {
                    keyboardFocused = true
                    arrive(proxy)
                }
                .onChange(of: focus) { _, _ in arrive(proxy) }
                .onChange(of: selectedId) { _, id in actions.focus(id.map { .decision($0) }) }
            }
        }
    }

    private var header: some View {
        let progress = graph.reviewProgress(discussed: discussed)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Decisions to Review")
                    .font(.system(size: 26, weight: .semibold))
                Spacer()
                Picker("Layout", selection: $mode) {
                    Label("List", systemImage: "list.bullet").tag(Mode.list)
                    Label("One at a time", systemImage: "rectangle.portrait").tag(Mode.oneAtATime)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("Review every decision in a list, or one at a time")
            }
            HStack(spacing: 10) {
                Text(Self.framing(toReview: toReview.count, total: graph.decisions.count))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                if progress.total > 0 {
                    ReviewProgressDots(graph: graph, discussed: discussed)
                    Text(verbatim: "\(progress.reviewed) of \(progress.total) resolved")
                        .monospacedDigit()
                        .help("Things to think about from the Overview you've resolved")
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    nonisolated static func framing(toReview: Int, total: Int) -> String {
        let others = total - toReview
        if toReview == 0 {
            return "No choice in this PR stood out as needing your judgment. "
                + (others == 1 ? "The one decision identified is below." : "The \(others) decisions identified are below.")
        }
        let lead = toReview == 1
            ? "1 choice in this PR appears worth your attention"
            : "\(toReview) choices in this PR appear worth your attention"
        let found = others > 0 ? ", out of \(total) identified" : ""
        return lead + found + (toReview == 1 ? ". Do you agree with it?" : ". Do you agree with them?")
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(toReview.enumerated()), id: \.element.id) { index, decision in
                card(decision, number: index + 1)
            }
            if !other.isEmpty {
                otherSection
                    .padding(.top, toReview.isEmpty ? 0 : 16)
            }
        }
    }

    private var otherSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("OTHER DECISIONS")
                    .font(.caption.weight(.semibold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(verbatim: "\(other.count)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            if !toReview.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { showOther.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: showOther ? "chevron.down" : "chevron.right")
                            .font(.caption.weight(.semibold))
                            .frame(width: 12)
                        Text(showOther
                             ? "Hide lower-impact decisions"
                             : other.count == 1 ? "Show 1 lower-impact decision" : "Show \(other.count) lower-impact decisions")
                    }
                    .font(.callout)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Decisions the analysis found but judged less in need of your attention — you can add any of them to review")
            }

            if otherShown {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(other.enumerated()), id: \.element.id) { index, decision in
                        if index > 0 { Divider() }
                        row(decision)
                    }
                }
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.secondary.opacity(0.18)))
            }
        }
    }

    private func row(_ decision: DecisionNode) -> some View {
        OtherDecisionRow(
            decision: decision,
            brief: graph.brief(for: decision),
            graph: graph,
            reason: graph.attentionReason(for: decision),
            isSelected: selected?.id == decision.id && keyboardFocused,
            isArrived: arrivedId == decision.id,
            isExpanded: expandedIds.contains(decision.id),
            onAddToReview: { setToReview(decision, true) },
            onToggleExpanded: { toggleExpanded(decision.id) },
            onSelect: { selectedId = decision.id; keyboardFocused = true }
        )
        .id(decision.id)
    }

    @ViewBuilder
    private func item(_ decision: DecisionNode) -> some View {
        if let index = toReview.firstIndex(where: { $0.id == decision.id }) {
            card(decision, number: index + 1)
        } else {
            row(decision)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.secondary.opacity(0.18)))
        }
    }

    private func card(_ decision: DecisionNode, number: Int?) -> some View {
        DecisionCard(
            decision: decision,
            brief: graph.brief(for: decision),
            graph: graph,
            number: number,
            attentionReason: graph.attentionReason(for: decision),
            arrivedFromConsiderationId: focus?.decisionId == decision.id ? focus?.considerationId : nil,
            isSelected: selected?.id == decision.id && keyboardFocused,
            isArrived: arrivedId == decision.id,
            isExpanded: expandedIds.contains(decision.id),
            noteFocus: $noteFocus,
            onSetState: { judge(decision, $0) },
            onSetNote: { onSetNote(decision.id, $0) },
            onToggleExpanded: { toggleExpanded(decision.id) },
            onNotWorthReviewing: { setToReview(decision, false) },
            onSelect: { selectedId = decision.id; keyboardFocused = true }
        )
        .id(decision.id)
    }

    @ViewBuilder
    private var oneAtATime: some View {
        if let current = selected, let index = sequence.firstIndex(where: { $0.id == current.id }) {
            VStack(spacing: 18) {
                Text(verbatim: "\(index + 1) of \(sequence.count)")
                    .font(.callout.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                item(current)
                HStack {
                    Button { step(-1) } label: { Label("Previous", systemImage: "arrow.left") }
                        .disabled(index == 0)
                    Spacer()
                    if !other.isEmpty, !otherShown, index == sequence.count - 1 {
                        Button("Other decisions (\(other.count))") {
                            showOther = true
                            step(1)
                        }
                        .buttonStyle(.link)
                        Spacer()
                    }
                    Button { step(1) } label: {
                        HStack(spacing: 4) { Text("Next"); Image(systemName: "arrow.right") }
                    }
                    .disabled(index == sequence.count - 1)
                }
                .controlSize(.large)
            }
        }
    }

    private var shortcutsHint: some View {
        HStack(spacing: 14) {
            hint("J K", "move")
            hint("A", "looks good")
            hint("Q", "question")
            hint("C", "discuss")
            hint("M", "more")
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
    }

    private func hint(_ keys: String, _ action: String) -> some View {
        HStack(spacing: 4) {
            Text(keys)
                .font(.caption.monospaced().weight(.semibold))
                .padding(.horizontal, 4)
                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 3))
            Text(action)
        }
    }

    private func arrive(_ proxy: ScrollViewProxy) {
        let id = focus?.decisionId
        let exists = id.flatMap { graph.decision($0) } != nil
        let plan = DecisionsViewLogic.arrivalSelection(
            decisionId: id,
            decisionExists: exists,
            isOtherDecision: id.map { i in other.contains { $0.id == i } } ?? false,
            existingSelectedId: selectedId,
            fallbackId: sequence.first?.id)
        selectedId = plan.selectedId
        guard exists, let id else { return }
        if plan.revealOther { showOther = true }
        withAnimation(.easeOut(duration: 0.2)) { arrivedId = id }
        DispatchQueue.main.async {
            withAnimation { proxy.scrollTo(id, anchor: .top) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            if arrivedId == id { withAnimation(.easeInOut(duration: 0.6)) { arrivedId = nil } }
        }
    }

    private func handleKey(_ press: KeyPress, proxy: ScrollViewProxy) -> KeyPress.Result {
        let action = DecisionsViewLogic.keyAction(
            isArrowDown: press.key == .downArrow,
            isArrowUp: press.key == .upArrow,
            character: press.characters,
            modifiersBlockShortcuts: !press.modifiers.isDisjoint(with: [.command, .control, .option]),
            noteFieldFocused: noteFocus != nil,
            hasSelection: selected != nil,
            selectionIsToReview: selected.map(graph.isToReview) ?? false)
        switch action {
        case .step(let delta):
            step(delta, proxy: proxy)
            return .handled
        case .judge(let state):
            guard let decision = selected else { return .ignored }
            judge(decision, state, proxy: proxy)
            return .handled
        case .toggleExpanded:
            guard let decision = selected else { return .ignored }
            toggleExpanded(decision.id)
            return .handled
        case .ignored:
            return .ignored
        }
    }

    private func step(_ delta: Int, proxy: ScrollViewProxy? = nil) {
        let ids = sequence.map(\.id)
        guard let nextId = DecisionsViewLogic.stepId(in: ids, currentId: selected?.id, delta: delta) else { return }
        selectedId = nextId
        keyboardFocused = true
        if let proxy { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(nextId) } }
    }

    private func judge(_ decision: DecisionNode, _ state: ReviewerState, proxy: ScrollViewProxy? = nil) {
        let turningOn = decision.reviewerState != state
        selectedId = decision.id
        onSetState(decision.id, state)
        guard turningOn else { return }
        switch state {
        case .accepted:
            guard let nextId = DecisionsViewLogic.nextAfterAccepting(sequence: sequence, decisionId: decision.id) else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                selectedId = nextId
                if let proxy { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(nextId) } }
            }
        case .questioned:
            DispatchQueue.main.async { noteFocus = decision.id }
        case .discuss:
            actions.ask(.decision(decision.id))
        case .unreviewed:
            break
        }
    }

    private func setToReview(_ decision: DecisionNode, _ toReview: Bool) {
        let nextId = DecisionsViewLogic.selectionAfterTogglingReview(
            toReview: self.toReview, decisionId: decision.id, addingToReview: toReview)
        withAnimation(.easeInOut(duration: 0.2)) {
            onSetToReview(decision.id, toReview)
            expandedIds.remove(decision.id)
        }
        selectedId = nextId
        keyboardFocused = true
    }

    private func toggleExpanded(_ id: String) {
        withAnimation(.easeInOut(duration: 0.18)) {
            if expandedIds.contains(id) { expandedIds.remove(id) } else { expandedIds.insert(id) }
        }
    }
}

enum DecisionsViewLogic {
    static func questions(from all: [Consideration], leadingWith arrivedFromConsiderationId: String?) -> [Consideration] {
        guard let lead = arrivedFromConsiderationId, let item = all.first(where: { $0.id == lead }) else { return all }
        return [item] + all.filter { $0.id != lead }
    }

    nonisolated static func provenanceNote(_ s: Statement) -> String {
        switch s.provenance {
        case .claim: return "Author rationale"
        case .fact: return "Observed"
        case .interpretation: return "AI inference"
        }
    }

    static func provenanceHelp(_ s: Statement) -> String {
        var text = PRGraph.provenanceLabel(s.provenance, s.confidence)
        if let source = s.source, !source.isEmpty { text += " — \(source)" }
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    enum KeyAction: Equatable {
        case step(Int)
        case judge(ReviewerState)
        case toggleExpanded
        case ignored
    }

    nonisolated static func keyAction(isArrowDown: Bool, isArrowUp: Bool, character: String,
                                       modifiersBlockShortcuts: Bool, noteFieldFocused: Bool,
                                       hasSelection: Bool, selectionIsToReview: Bool) -> KeyAction {
        guard !noteFieldFocused, !modifiersBlockShortcuts else { return .ignored }
        if isArrowDown { return .step(1) }
        if isArrowUp { return .step(-1) }
        guard hasSelection else { return .ignored }
        let key = character.lowercased()
        if ["a", "q", "c"].contains(key), !selectionIsToReview { return .ignored }
        switch key {
        case "j": return .step(1)
        case "k": return .step(-1)
        case "a": return .judge(.accepted)
        case "q": return .judge(.questioned)
        case "c": return .judge(.discuss)
        case "m", " ": return .toggleExpanded
        default: return .ignored
        }
    }

    nonisolated static func stepId(in ids: [String], currentId: String?, delta: Int) -> String? {
        guard !ids.isEmpty else { return nil }
        let current = currentId.flatMap { ids.firstIndex(of: $0) } ?? 0
        let next = min(max(current + delta, 0), ids.count - 1)
        return ids[next]
    }

    nonisolated static func nextAfterAccepting(sequence: [DecisionNode], decisionId: String) -> String? {
        guard let at = sequence.firstIndex(where: { $0.id == decisionId }) else { return nil }
        let after = sequence[sequence.index(after: at)...]
        return (after.first { $0.reviewerState == .unreviewed } ?? after.first)?.id
    }

    nonisolated static func selectionAfterTogglingReview(toReview: [DecisionNode], decisionId: String,
                                                          addingToReview: Bool) -> String? {
        guard !addingToReview else { return decisionId }
        let next = toReview.drop { $0.id != decisionId }.dropFirst().first
        return (next ?? toReview.first { $0.id != decisionId })?.id
    }

    nonisolated static func arrivalSelection(decisionId: String?, decisionExists: Bool, isOtherDecision: Bool,
                                              existingSelectedId: String?, fallbackId: String?)
        -> (selectedId: String?, revealOther: Bool) {
        guard let id = decisionId, decisionExists else {
            return (existingSelectedId ?? fallbackId, false)
        }
        return (id, isOtherDecision)
    }

    nonisolated static func impactsSummary(_ impacts: [DecisionImpact]) -> String {
        impacts.prefix(3).map(\.label).joined(separator: " · ")
    }

    nonisolated static func badgeTint(for state: ReviewerState) -> Color {
        state == .unreviewed ? .secondary : state.tint
    }

    nonisolated static func tradeoffHelp(_ tradeoff: DecisionTradeoff) -> String {
        (tradeoff.explanation?.text ?? "Leans toward \(tradeoff.chosenDimension)") + " — right-click to ask about it"
    }

    nonisolated static func beforeAfterParts(from label: String) -> [String] {
        label.components(separatedBy: CharacterSet(charactersIn: "→>"))
            .map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "-")) }
            .filter { !$0.isEmpty }
    }
}

private struct DecisionCard: View {
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
        DecisionsViewLogic.questions(from: graph.overviewQuestions(reviewedOn: decision.id),
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

            if decision.reviewerState == .questioned || !decision.reviewerNote.isEmpty {
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
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.55) : Color.secondary.opacity(0.18),
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
        return line
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
                    rowLabel(brief.shape == nil && brief.tradeoff == nil ? "Why" : "Why this side?")
                    (Text(why.text) + Text("   " + DecisionsViewLogic.provenanceNote(why)).font(.caption).foregroundStyle(.tertiary))
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
                            Text(item.question)
                                .font(.body.weight(item.id == arrivedFromConsiderationId ? .semibold : .regular))
                                .foregroundStyle(.orange)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                                .help(item.detail)
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
                            Button { actions.navigate(.flowNodeDetail(flowId: flow.id, nodeId: nodeId)) } label: {
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
            TextField("What would you ask the author?", text: Binding(
                get: { decision.reviewerNote },
                set: { onSetNote($0) }
            ), axis: .vertical)
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

private struct OtherDecisionRow: View {
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
                    Text(brief.chosen.map { $0.label + ($0.detail.map { " — \($0)" } ?? "") } ?? brief.answer)
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
                        Text(question.question)
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
                Button { actions.ask(.decision(decision.id)) } label: {
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

private struct DecisionBadge: View {
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

private struct ReviewedChip: View {
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

private struct ReviewProgressDots: View {
    let graph: PRGraph
    let discussed: Set<String>

    var body: some View {
        HStack(spacing: 4) {
            ForEach(graph.thingsToThinkAbout) { item in
                let state = graph.decision(graph.reviewDecisionId(for: item))?.reviewerState ?? .unreviewed
                let resolved = graph.isResolved(item, discussed: discussed)
                Circle()
                    .fill(!resolved ? Color.secondary.opacity(0.25) : state == .unreviewed ? Color.green : state.tint)
                    .frame(width: 7, height: 7)
                    .help(item.question + (resolved ? " — resolved" : ""))
            }
        }
    }
}

private struct ReviewButtons: View {
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
        return Button { withAnimation(.easeOut(duration: 0.15)) { onSet(target) } } label: {
            Label(title, systemImage: target.symbol)
                .font(.callout.weight(isOn ? .semibold : .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundStyle(isOn ? target.tint : Color.primary)
                .background(isOn ? target.tint.opacity(0.16) : Color.secondary.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(isOn ? target.tint.opacity(0.5) : Color.secondary.opacity(0.22)))
                .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help(isOn ? "\(target.label) — click to clear (\(shortcut))" : "\(title) (\(shortcut))")
    }
}

extension ReviewerState {
    var symbol: String {
        switch self {
        case .unreviewed: return "circle"
        case .accepted: return "checkmark"
        case .questioned: return "questionmark"
        case .discuss: return "bubble.left.and.bubble.right"
        }
    }

    var tint: Color {
        switch self {
        case .unreviewed: return .secondary
        case .accepted: return .green
        case .questioned: return .orange
        case .discuss: return .blue
        }
    }

    var chipLabel: String {
        switch self {
        case .unreviewed: return "Unreviewed"
        case .accepted: return "Reviewed"
        case .questioned: return "Question"
        case .discuss: return "Discussing"
        }
    }
}

private struct DecisionChoiceView: View {
    let decisionId: String
    let brief: DecisionBrief

    var body: some View {
        switch brief.shape {
        case .binary?: binary
        case .threshold?: threshold
        case .options?: optionList
        case .beforeAfter?: beforeAfter
        case nil: answerLines
        }
    }

    private var binary: some View {
        let a = brief.options[0], b = brief.options[1]
        return VStack(spacing: 7) {
            HStack(alignment: .bottom) {
                label(a, index: 0).frame(maxWidth: .infinity, alignment: .leading)
                label(b, index: 1).frame(maxWidth: .infinity, alignment: .trailing)
            }
            HStack(spacing: 0) {
                dot(a)
                Rectangle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(height: 2)
                dot(b)
            }
            HStack(alignment: .top) {
                caption(a, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
                caption(b, alignment: .trailing).frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(maxWidth: 640)
    }

    private var threshold: some View {
        let last = brief.options.count - 1
        return HStack(alignment: .top, spacing: 0) {
            ForEach(Array(brief.options.enumerated()), id: \.offset) { index, option in
                VStack(spacing: 7) {
                    label(option, index: index, alignment: .center)
                        .frame(height: 36, alignment: .bottom)
                    ZStack {
                        HStack(spacing: 0) {
                            Rectangle().fill(Color.secondary.opacity(index == 0 ? 0 : 0.3))
                            Rectangle().fill(Color.secondary.opacity(index == last ? 0 : 0.3))
                        }
                        .frame(height: 2)
                        dot(option)
                    }
                    caption(option, alignment: .center)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: 680)
    }

    private var optionList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(brief.options.enumerated()), id: \.offset) { index, option in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: option.chosen ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(option.chosen ? Color.accentColor : Color.secondary)
                    Text(option.label)
                        .font(.body.weight(option.chosen ? .semibold : .regular))
                        .foregroundStyle(option.chosen ? .primary : .secondary)
                    if let detail = option.detail {
                        Text(detail).font(.callout).foregroundStyle(.tertiary)
                    }
                    if option.chosen { chosenTag }
                }
                .contentShape(Rectangle())
                .reviewContextMenu(.decisionOption(decisionId: decisionId, index: index))
            }
        }
    }

    private var beforeAfter: some View {
        let before = brief.options[0], after = brief.options[1]
        return VStack(alignment: .leading, spacing: 10) {
            structure(before, index: 0, title: "BEFORE")
            structure(after, index: 1, title: "AFTER")
        }
    }

    private func structure(_ option: DecisionOption, index: Int, title: String) -> some View {
        let parts = DecisionsViewLogic.beforeAfterParts(from: option.label)
        let tint = option.chosen ? Color.accentColor : Color.secondary
        return HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.caption2.weight(.bold))
                .tracking(0.6)
                .foregroundStyle(option.chosen ? Color.accentColor : Color.secondary)
                .frame(width: 52, alignment: .leading)
            HStack(spacing: 6) {
                ForEach(Array(parts.enumerated()), id: \.offset) { i, part in
                    if i > 0 {
                        Image(systemName: "arrow.right").font(.caption2).foregroundStyle(tint.opacity(0.7))
                    }
                    Text(part)
                        .font(.callout.weight(option.chosen ? .medium : .regular))
                        .foregroundStyle(option.chosen ? .primary : .secondary)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(tint.opacity(option.chosen ? 0.1 : 0.05), in: RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(tint.opacity(option.chosen ? 0.45 : 0.25)))
                }
            }
            if let detail = option.detail {
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            if option.chosen { chosenTag }
        }
        .contentShape(Rectangle())
        .reviewContextMenu(.decisionOption(decisionId: decisionId, index: index))
    }

    private var answerLines: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 8) {
            GridRow {
                chosenTag.gridColumnAlignment(.leading)
                Text(brief.answer).font(.body).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            if let insteadOf = brief.insteadOf {
                GridRow {
                    Text("INSTEAD OF")
                        .font(.caption2.weight(.bold))
                        .tracking(0.5)
                        .foregroundStyle(.tertiary)
                    Text(insteadOf).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .reviewContextMenu(.decision(decisionId))
    }

    private func label(_ option: DecisionOption, index: Int, alignment: TextAlignment = .leading) -> some View {
        Text(option.label.uppercased())
            .font(.callout.weight(option.chosen ? .bold : .medium))
            .tracking(0.4)
            .foregroundStyle(option.chosen ? .primary : .secondary)
            .multilineTextAlignment(alignment == .leading && index == 1 ? .trailing : alignment)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .contentShape(Rectangle())
            .help(option.chosen ? "What this PR chose — right-click to ask why" : "Not chosen — right-click to ask about it")
            .reviewContextMenu(.decisionOption(decisionId: decisionId, index: index))
    }

    @ViewBuilder
    private func dot(_ option: DecisionOption) -> some View {
        if option.chosen {
            Circle().fill(Color.accentColor).frame(width: 14, height: 14)
        } else {
            Circle().strokeBorder(Color.secondary.opacity(0.6), lineWidth: 1.5)
                .background(Circle().fill(Color(nsColor: .windowBackgroundColor)))
                .frame(width: 12, height: 12)
        }
    }

    private func caption(_ option: DecisionOption, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            if option.chosen { chosenTag }
            if let detail = option.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(alignment == .trailing ? .trailing : (alignment == .center ? .center : .leading))
            }
        }
    }

    private var chosenTag: some View {
        Text("CHOSEN")
            .font(.caption2.weight(.bold))
            .tracking(0.6)
            .foregroundStyle(Color.accentColor)
    }
}

struct TradeoffSpectrum: View {
    let tradeoff: DecisionTradeoff

    var body: some View {
        let weight = tradeoff.chosenPosition
        HStack(spacing: 10) {
            Text(tradeoff.dimensionA)
                .foregroundStyle(weight < 0.5 ? .primary : .secondary)
                .fontWeight(weight < 0.5 ? .medium : .regular)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(height: 1.5)
                        .padding(.horizontal, 6)
                    HStack {
                        Image(systemName: "arrowtriangle.left.fill")
                        Spacer()
                        Image(systemName: "arrowtriangle.right.fill")
                    }
                    .font(.system(size: 7))
                    .foregroundStyle(Color.secondary.opacity(0.6))
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 10, height: 10)
                        .offset(x: 6 + (geo.size.width - 22) * weight)
                }
                .frame(height: geo.size.height)
            }
            .frame(width: 150, height: 12)
            Text(tradeoff.dimensionB)
                .foregroundStyle(weight >= 0.5 ? .primary : .secondary)
                .fontWeight(weight >= 0.5 ? .medium : .regular)
        }
        .font(.callout)
        .lineLimit(1)
        .contentShape(Rectangle())
        .help(DecisionsViewLogic.tradeoffHelp(tradeoff))
    }
}

private struct DecisionDrillDown: View {
    let decision: DecisionNode
    let graph: PRGraph

    @Environment(\.reviewActions) private var actions

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
                section(decision.tradeoffs.count == 1 ? "What it traded" : "What it traded (\(decision.tradeoffs.count))") {
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
                    WrapChips(decision.refs) { ref in CodeRefChip(ref: ref) { actions.navigate(.evidence(ref)) } }
                }
            }
            HStack(spacing: 14) {
                Text("\(decision.level.label)-level choice · analysis confidence \(decision.confidence.label.lowercased())")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Button { actions.ask(.decision(decision.id)) } label: {
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
                WrapChips(tradeoff.refs) { ref in CodeRefChip(ref: ref) { actions.navigate(.evidence(ref)) } }
            }
        }
    }

    private func affectsLinks(_ affects: (components: [ComponentNode], edges: [ArchitectureEdge], flows: [FlowNode])) -> some View {
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
                            let from = graph.component(e.fromId)?.title ?? e.fromId
                            let to = graph.component(e.toId)?.title ?? e.toId
                            link("\(from) → \(to)", "arrow.right", .edgeDetail(e.id))
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
        Button { actions.navigate(target) } label: {
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
