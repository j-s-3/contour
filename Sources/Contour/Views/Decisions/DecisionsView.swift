import SwiftUI

/// The Decisions lens: where the reviewer makes judgments. The Overview says what deserves
/// thought; this is where that thought is recorded, one consequential choice at a time.
///
/// Each decision is drawn as the question the engineer had to answer, the options on the
/// table with the chosen one marked, what that choice traded, and why it landed on that
/// side — one visual unit, scannable in a few seconds, followed by an explicit Looks good /
/// Question / Discuss. Tradeoffs are never a separate destination: a tradeoff exists because
/// a decision was made, so it is drawn on, and judged with, that decision.
/// Everything else (full rationale, alternatives, consequences, what it affects, evidence)
/// is behind More…, a right-click, or a conversation.
///
/// The lens directs scarce attention: the decisions where the reviewer's judgment appears to
/// matter most are shown as Decisions to Review; everything else the analysis found is
/// collapsed under Other Decisions, compact but still inspectable. Significance decides which
/// is which, never abstraction level — and the reviewer can move a decision either way.
/// The lens is built for a sequential, keyboard-only loop — J/K to move, A/Q/C to judge —
/// and has a one-at-a-time mode that reads like a design review.
struct DecisionsView: View {
    let graph: PRGraph
    /// Where navigation asked the lens to open.
    var focus: Focus?
    /// Overview questions talked through in a conversation, for review progress.
    var discussed: Set<String> = []
    var onSetState: (String, ReviewerState) -> Void
    var onSetNote: (String, String) -> Void
    /// Add to review (true) / Not worth reviewing (false).
    var onSetToReview: (String, Bool) -> Void

    struct Focus: Equatable {
        var decisionId: String
        /// The Overview question that brought the reviewer here, if any.
        var considerationId: String? = nil
    }

    enum Mode: String {
        case list
        case oneAtATime
    }

    @Environment(\.reviewActions) private var actions
    @AppStorage("decisions.mode") private var mode: Mode = .list
    @State private var selectedId: String?
    /// The decision briefly lit up after navigating to it.
    @State private var arrivedId: String?
    @State private var expandedIds: Set<String> = []
    @State private var showOther = false
    @FocusState private var keyboardFocused: Bool
    @FocusState private var noteFocus: String?

    private var toReview: [DecisionNode] { graph.decisionsToReview }
    private var other: [DecisionNode] { graph.otherDecisions }
    /// Other Decisions open by default only when nothing was proposed for review.
    private var otherShown: Bool {
        DecisionsViewLogic.otherShown(showOther: showOther, toReviewIsEmpty: toReview.isEmpty)
    }
    /// The review sequence J/K walks: decisions to review, then other decisions once shown.
    private var sequence: [DecisionNode] {
        DecisionsViewLogic.sequence(toReview: toReview, other: other, otherShown: otherShown)
    }
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

    // MARK: - Header

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
                // The same n of m as the Overview and the sidebar: its things to think
                // about, resolved — judging a decision here resolves the questions on it.
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

    /// Says what the list is for — where the reviewer's time is best spent — without claiming
    /// the analysis ranked importance perfectly, and that more was found than is shown.
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

    // MARK: - List mode

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
                        Text(DecisionsViewLogic.otherToggleTitle(showOther: showOther, count: other.count))
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

    /// A decision to review in the list or one-at-a-time, or an other decision's compact row.
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

    // MARK: - One at a time

    @ViewBuilder
    private var oneAtATime: some View {
        if let current = selected, let index = sequence.firstIndex(where: { $0.id == current.id }) {
            let position = DecisionsViewLogic.oneAtATimeStep(index: index, count: sequence.count,
                                                             otherCount: other.count, otherShown: otherShown)
            VStack(spacing: 18) {
                Text(verbatim: position.label)
                    .font(.callout.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                item(current)
                HStack {
                    Button { step(-1) } label: { Label("Previous", systemImage: "arrow.left") }
                        .disabled(!position.canGoPrevious)
                    Spacer()
                    if position.offersOtherDecisions {
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
                    .disabled(!position.canGoNext)
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

    // MARK: - Behavior

    /// Opens the decision navigation asked for: reveal it, select it, scroll to it, and
    /// light it up briefly so the eye lands on it.
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

    /// Records a judgment. "Looks good" moves on to the next decision still waiting for
    /// one; "Question" opens a note for the author; "Discuss" opens a conversation.
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

    /// Add to review / Not worth reviewing. A decision added to review is selected where it
    /// lands; one taken out hands the selection to the next decision still to review.
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
