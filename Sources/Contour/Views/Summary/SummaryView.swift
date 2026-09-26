import SwiftUI

/// The Overview: a thirty-second briefing from a staff engineer before the review starts,
/// not a dashboard. After a glance the reviewer should be able to say what changed, why,
/// what happens differently now, and what deserves their judgment. It reads top to bottom
/// in one centered column:
///
///     title / metadata
///     WHAT CHANGED — the before/after hero
///     WHY · CONSEQUENCE — one or two lines each
///     THINGS TO THINK ABOUT — short questions, not reports
///     OTHER BEHAVIOR CHANGES — one line each
///     EXPLORE THE CHANGE — Architecture / Flows / Decisions, as navigation
///
/// Everything here is deliberately short; explanation lives one step down — a click, an
/// expansion, or right-click → Ask about this…. File paths and line numbers never appear at
/// this level. Review progress lives in the sidebar, since it's status, not understanding.
///
/// It opens before the analysis behind it has finished, so every section has a reserved
/// place from the start: "✦ Understanding the change…" becomes the plain-language answer,
/// then the before/after hero; "Loading…" becomes the why; the things to think about fill
/// in as the analysis finds them. Placeholders are replaced in place and nothing above
/// the reviewer's reading position is inserted later, so the page doesn't jump.
struct SummaryView: View {
    let graph: PRGraph
    var analysis = AnalysisState(isComplete: true)
    var onRetry: (PipelineStage) -> Void = { _ in }
    var navigate: (NavigationTarget) -> Void

    private var behaviorStatus: StageStatus { analysis.status(.behaviorChange) }
    private var understandingStatus: StageStatus { analysis.status(.understanding) }
    private var judgmentStatus: StageStatus { analysis.status(.judgment) }
    /// Still expecting the before/after: nothing to show yet, and nothing has failed.
    private var awaitingBehavior: Bool { graph.dominantBehaviorChange == nil && !behaviorStatus.isSettled }

    @Environment(\.reviewActions) private var actions
    @State private var expandedConsideration: String?
    @State private var showAllConsiderations = false
    @State private var expandedOtherChange: String?

    /// Budgets from the brief: the Overview must not slowly grow back into a report.
    private let considerationBudget = 5

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.bottom, 28)

                whatChanged

                if let change = graph.dominantBehaviorChange, change.why != nil || change.consequence != nil {
                    whyAndConsequence(change)
                        .padding(.top, 26)
                } else if awaitingBehavior {
                    whyPlaceholder
                        .padding(.top, 26)
                }

                if !graph.thingsToThinkAbout.isEmpty {
                    thingsToThinkAbout
                        .padding(.top, 36)
                } else if !judgmentStatus.isSettled {
                    thingsToThinkAboutPlaceholder
                        .padding(.top, 36)
                }

                if graph.behaviorChanges.count > 1 {
                    sectionDivider
                    otherBehaviorChanges
                }

                sectionDivider
                exploreTheChange
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 32)
            .frame(maxWidth: 1240, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .onAppear { actions.focus(nil) }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(graph.pr.title)
                .font(.system(size: 26, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            HStack(spacing: 6) {
                // Verbatim for the same reason as the window title: a literal here is a
                // LocalizedStringKey, which locale-formats the interpolated Int and turns
                // PR #14039 into "#14,039".
                Text(verbatim: "\(graph.pr.repo) #\(graph.pr.number)")
                dot
                Text(graph.pr.state.capitalized)
                dot
                Text(graph.pr.author)
                dot
                Text(verbatim: "\(graph.pr.branch) \u{2192} \(graph.pr.baseBranch)")
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let ticket = graph.pr.ticket {
                    dot
                    ticketChip(ticket)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            factsLine
        }
        .reviewContextMenu(.pullRequest)
    }

    /// Size, CI, reviews, open threads and age: what a reviewer checks first, as one quiet
    /// line. Color is kept for CI's verdict and the facts that should stop a reviewer —
    /// requested changes, open threads; everything else stays secondary.
    private var factsLine: some View {
        let facts = graph.pr.glanceFacts()
        return HStack(spacing: 6) {
            ForEach(Array(facts.enumerated()), id: \.offset) { index, fact in
                if index > 0 { dot }
                Text(verbatim: fact.text)
                    .foregroundStyle(factColor(fact.tone))
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private func factColor(_ tone: GlanceFact.Tone) -> AnyShapeStyle {
        switch tone {
        case .plain: AnyShapeStyle(.secondary)
        case .good: AnyShapeStyle(Color.green)
        case .caution: AnyShapeStyle(Color.orange)
        case .bad: AnyShapeStyle(Color.red)
        }
    }

    private var dot: some View { Text("\u{00b7}").foregroundStyle(.tertiary) }

    /// Renders a GitHub issue or a Jira ticket identically apart from the icon — from the
    /// reviewer's side they play the same role, so only the glyph distinguishes them.
    private func ticketChip(_ ticket: TicketInfo) -> some View {
        Link(destination: URL(string: ticket.url) ?? URL(string: "about:blank")!) {
            HStack(spacing: 4) {
                Image(systemName: ticket.kind == .jira ? "link" : "smallcircle.filled.circle")
                Text(ticket.key)
            }
            .font(.caption.weight(.semibold))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.blue)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(Color.blue.opacity(0.1), in: Capsule())
        .help(ticket.summary)
    }

    // MARK: - What changed (the hero)

    @ViewBuilder
    private var whatChanged: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("What changed")
            if let change = graph.dominantBehaviorChange {
                Text(change.title)
                    .font(.title2.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .reviewContextMenu(.behaviorChange(change.id))
                BehaviorChangeDiagramView(change: change) { openStage($0) }
                    .padding(.vertical, 22)
                    .padding(.horizontal, 22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.separator.opacity(0.5)))
                    .padding(.top, 4)
                    .transition(.opacity)
            } else if awaitingBehavior {
                // The plain-language answer usually lands first; show it while the
                // before/after is built, in the space the diagram will take.
                if let how = graph.pr.howItWasSolved {
                    Text(how.text)
                        .font(.title3.weight(.medium))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .reviewContextMenu(.pullRequest)
                        .transition(.opacity)
                    WorkingLine(text: "Building before / after…")
                } else {
                    WorkingLine(text: understandingStatus.failure == nil ? "Understanding the change…" : "Building before / after…",
                                font: .title3)
                }
            } else if let problem = graph.pr.problemToBeSolved {
                // No before/after was extracted: fall back to the plain-language pair, still
                // as two short statements rather than cards.
                Text(graph.pr.howItWasSolved?.text ?? problem.text)
                    .font(.title3.weight(.medium))
                    .lineLimit(3)
                    .reviewContextMenu(.pullRequest)
                if graph.pr.howItWasSolved != nil {
                    briefLine("Problem", problem, subject: .pullRequest)
                }
            } else {
                Text(graph.pr.intent.text)
                    .font(.title3.weight(.medium))
                    .lineLimit(3)
                    .reviewContextMenu(.pullRequest)
            }
            if behaviorStatus.failure != nil {
                retryLine("Couldn't build the before / after.", stage: .behaviorChange)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: graph.dominantBehaviorChange?.id)
        .animation(.easeInOut(duration: 0.35), value: graph.pr.howItWasSolved?.text)
    }

    private func retryLine(_ text: String, stage: PipelineStage) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(text).foregroundStyle(.secondary)
            Button("Retry") { onRetry(stage) }
                .buttonStyle(.link)
        }
        .font(.caption)
    }

    // MARK: - Placeholders

    /// Reserves the why/consequence rows so the text lands where the reviewer expects it.
    private var whyPlaceholder: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 18, verticalSpacing: 12) {
            GridRow {
                Text("WHY")
                    .font(.caption.weight(.semibold))
                    .tracking(0.5)
                    .foregroundStyle(.secondary)
                Text("Loading…").font(.body).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 4)
    }

    private var thingsToThinkAboutPlaceholder: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange.opacity(0.5))
                    .font(.callout)
                Text("THINGS TO THINK ABOUT")
                    .font(.callout.weight(.semibold))
                    .tracking(0.5)
            }
            WorkingLine(text: judgmentWorkingText)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.orange.opacity(0.12)))
    }

    /// Judgment runs last, over everything else; until then, say what it's waiting on in the
    /// reviewer's terms, and point at the decisions already found.
    private var judgmentWorkingText: String {
        let found = graph.decisions.count
        let decisions = analysis.status(.decisions)
        if !judgmentStatus.isRunning, decisions.isRunning || decisions == .pending {
            return found > 0 ? "\(found) \(found == 1 ? "decision" : "decisions") found · looking for consequential choices…"
                             : "Looking for consequential choices…"
        }
        return "Weighing what needs your judgment…"
    }

    private func openStage(_ stage: BehaviorStage) {
        if let componentId = stage.componentIds.first {
            navigate(.componentDetail(componentId))
        } else if let flowId = stage.flowId {
            navigate(.flowDetail(flowId))
        } else {
            navigate(.architecture)
        }
    }

    // MARK: - Why / consequence

    private func whyAndConsequence(_ change: BehaviorChange) -> some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 18, verticalSpacing: 12) {
            if let why = change.why {
                briefRow("Why", why, subject: .behaviorWhy(changeId: change.id))
            }
            if let consequence = change.consequence {
                briefRow("Consequence", consequence, subject: .behaviorConsequence(changeId: change.id))
            }
        }
        .padding(.horizontal, 4)
    }

    private func briefRow(_ label: String, _ statement: Statement, subject: ReviewSubject) -> some View {
        GridRow {
            Text(label.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(0.5)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.leading)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(statement.text)
                    .font(.body)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                ProvenanceMark(provenance: statement.provenance, confidence: statement.confidence, source: statement.source)
            }
            .contentShape(Rectangle())
            .reviewContextMenu(subject)
        }
    }

    private func briefLine(_ label: String, _ statement: Statement, subject: ReviewSubject) -> some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 18) {
            briefRow(label, statement, subject: subject)
        }
    }

    // MARK: - Things to think about

    private var thingsToThinkAbout: some View {
        let items = graph.thingsToThinkAbout
        let visible = showAllConsiderations ? items : Array(items.prefix(considerationBudget))
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
                Text(verbatim: "\(items.count) \(items.count == 1 ? "thing" : "things") to think about".uppercased())
                    .font(.callout.weight(.semibold))
                    .tracking(0.5)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 6)

            ForEach(Array(visible.enumerated()), id: \.element.id) { index, item in
                if index > 0 { Divider().padding(.leading, 60) }
                ConsiderationRow(
                    number: index + 1,
                    item: item,
                    graph: graph,
                    isExpanded: expandedConsideration == item.id,
                    onToggle: {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            expandedConsideration = expandedConsideration == item.id ? nil : item.id
                        }
                    },
                    onReview: { review(item) },
                    navigate: navigate
                )
            }

            if items.count > considerationBudget {
                Button(showAllConsiderations ? "Show fewer" : "Show \(items.count - considerationBudget) more") {
                    withAnimation(.easeInOut(duration: 0.18)) { showAllConsiderations.toggle() }
                }
                .buttonStyle(.link)
                .font(.caption)
                .padding(.leading, 60)
                .padding(.bottom, 4)
            }

            // Until judgment lands this list is the behavior change's own question; say
            // more are coming rather than let it pass for the full list.
            if !judgmentStatus.isSettled {
                WorkingLine(text: judgmentWorkingText, font: .caption)
                    .padding(.leading, 58)
                    .padding(.top, 6)
                    .padding(.bottom, 4)
            } else if judgmentStatus.failure != nil {
                retryLine("Couldn't finish weighing what needs judgment.", stage: .judgment)
                    .padding(.leading, 58)
                    .padding(.top, 6)
            }
        }
        .padding(.bottom, 10)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.orange.opacity(0.22)))
    }

    /// "Review →" goes where the judgment is recorded — the decision the question belongs
    /// to, with the question shown there — and when there isn't one, straight into a
    /// conversation about the item.
    private func review(_ item: Consideration) {
        if graph.reviewDecisionId(for: item) != nil {
            navigate(.consideration(item.id))
        } else {
            actions.ask(.consideration(item.id))
        }
    }

    // MARK: - Other behavior changes

    private var otherBehaviorChanges: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Other behavior changes")
            VStack(alignment: .leading, spacing: 4) {
                ForEach(graph.behaviorChanges.dropFirst()) { change in
                    VStack(alignment: .leading, spacing: 10) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                expandedOtherChange = expandedOtherChange == change.id ? nil : change.id
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "arrow.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(change.title).font(.body)
                                Image(systemName: expandedOtherChange == change.id ? "chevron.down" : "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                Spacer()
                            }
                            .padding(.vertical, 3)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .reviewContextMenu(.behaviorChange(change.id))

                        if expandedOtherChange == change.id {
                            BehaviorChangeDiagramView(change: change, compact: true) { openStage($0) }
                                .padding(.leading, 22)
                                .padding(.bottom, 8)
                                .transition(.opacity)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Explore the change

    private var exploreTheChange: some View {
        // What the PR did to the structure, in words — never a count of parts it touched,
        // which says more about the diff than about the architecture.
        let architecture = graph.architecture.map { "\($0.impact.label) architectural impact" }
            ?? "\(graph.topLevelParts.count) parts"
        let progress = graph.reviewProgress
        return VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Explore the change")
            HStack(spacing: 12) {
                ExploreTile(title: "Architecture",
                            detail: tileDetail(.architecture, ready: architecture, count: graph.components.count, noun: "part"),
                            symbol: "square.stack.3d.up") { navigate(.architecture) }
                ExploreTile(title: "Flows",
                            detail: tileDetail(.flows, ready: "\(graph.flows.count) traced", count: graph.flows.count, noun: "flow"),
                            symbol: "arrow.triangle.branch") { navigate(.flows) }
                ExploreTile(title: "Decisions",
                            detail: tileDetail(.decisions, ready: "\(progress.reviewed) of \(progress.total) reviewed",
                                               count: graph.decisions.count, noun: "decision"),
                            symbol: "checklist") { navigate(.decisions) }
            }
        }
    }

    /// A tile's line: its summary once ready, otherwise how far its analysis has got.
    private func tileDetail(_ stage: PipelineStage, ready: String, count: Int, noun: String) -> String {
        switch analysis.status(stage) {
        case .done, .stale: return ready
        case .failed: return "Couldn't be analyzed"
        case .running: return count > 0 ? "\(count) \(noun)\(count == 1 ? "" : "s") so far…" : "Analyzing…"
        case .pending: return "Waiting…"
        }
    }

    // MARK: - Helpers

    private var sectionDivider: some View {
        Divider().padding(.vertical, 28)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }
}

// MARK: - A thing to think about

/// One question, one sentence, scannable in five seconds. Clicking expands the drill-down
/// (longer reasoning, related review objects, evidence, provenance); right-click offers the
/// usual Ask about this…. Concerns and open questions share the list and differ only in a
/// subtle badge — the analysis engine's taxonomy doesn't get to dictate the layout.
private struct ConsiderationRow: View {
    let number: Int
    let item: Consideration
    let graph: PRGraph
    let isExpanded: Bool
    var onToggle: () -> Void
    var onReview: () -> Void
    var navigate: (NavigationTarget) -> Void

    @Environment(\.reviewActions) private var actions
    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                badge
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.question)
                        .font(.body.weight(.semibold))
                        .lineLimit(isExpanded ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                    if !item.detail.isEmpty {
                        Text(item.detail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(isExpanded ? nil : 2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 16)
                Button(action: onReview) {
                    HStack(spacing: 3) {
                        Text("Review")
                        Image(systemName: "arrow.right")
                    }
                    .font(.callout.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .opacity(hovered || isExpanded ? 1 : 0.75)
                .help(graph.reviewDecisionId(for: item) != nil
                      ? "Review the decision this question is about" : "Ask about this")
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onToggle)

            if isExpanded {
                expanded
                    .padding(.leading, 38)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(hovered ? Color.secondary.opacity(0.06) : Color.clear)
        .onHover { hovered = $0 }
        .reviewContextMenu(.consideration(item.id))
    }

    private var badge: some View {
        let isQuestion = item.kind == .question
        return ZStack {
            Circle()
                .fill((isQuestion ? Color.secondary : Color.orange).opacity(0.14))
            if isQuestion {
                Image(systemName: "questionmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
            } else {
                Text(verbatim: "\(number)").font(.system(size: 12, weight: .semibold)).monospacedDigit().foregroundStyle(.orange)
            }
        }
        .frame(width: 24, height: 24)
        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
        .help(isQuestion ? "Open question — the analysis couldn't settle this" : "A judgment call worth your attention")
    }

    @ViewBuilder
    private var expanded: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let explanation = item.explanation, !explanation.isEmpty {
                Text(explanation)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            let related = relatedLinks
            if !related.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(related, id: \.title) { link in
                        Button { navigate(link.target) } label: {
                            Label(link.title, systemImage: link.symbol).font(.caption)
                        }
                        .buttonStyle(.link)
                    }
                }
            }
            if !item.refs.isEmpty {
                WrapChips(item.refs) { ref in CodeRefChip(ref: ref) { navigate(.evidence(ref)) } }
            }
            HStack(spacing: 12) {
                Text(PRGraph.provenanceLabel(item.provenance, item.confidence).capitalizedFirst)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Button { actions.ask(.consideration(item.id)) } label: {
                    Label("Ask about this", systemImage: "sparkles").font(.caption)
                }
                .buttonStyle(.link)
            }
        }
    }

    private var relatedLinks: [(title: String, symbol: String, target: NavigationTarget)] {
        item.relatedIds.compactMap { id in
            if let d = graph.decision(id) { return (d.title, "checklist", .decisionDetail(id)) }
            if let c = graph.component(id) { return (c.title, "square.stack.3d.up", .componentDetail(id)) }
            if let f = graph.flow(id) { return (f.title, "arrow.triangle.branch", .flowDetail(id)) }
            return nil
        }
    }
}

// MARK: - Explore tile

/// Navigation, not content: an icon, a name, and one count.
private struct ExploreTile: View {
    let title: String
    let detail: String
    let symbol: String
    var action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.callout.weight(.semibold))
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .offset(x: hovered ? 2 : 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(hovered ? Color.secondary.opacity(0.1) : Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator.opacity(0.6)))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovered = h } }
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
