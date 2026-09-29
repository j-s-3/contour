import SwiftUI

struct SummaryView: View {
    let graph: PRGraph
    var analysis = AnalysisState(isComplete: true)
    var discussed: Set<String> = []
    var onRetry: (PipelineStage) -> Void = { _ in }
    var navigate: (NavigationTarget) -> Void

    private var behaviorStatus: StageStatus { analysis.status(.behaviorChange) }
    private var understandingStatus: StageStatus { analysis.status(.understanding) }
    private var judgmentStatus: StageStatus { analysis.status(.judgment) }
    private var awaitingBehavior: Bool { graph.dominantBehaviorChange == nil && !behaviorStatus.isSettled }

    @Environment(\.reviewActions) private var actions
    @State private var expandedConsideration: String?
    @State private var showAllConsiderations = false
    @State private var expandedOtherChange: String?

    private let considerationBudget = 5

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.bottom, 28)

                whatChanged

                switch SummaryViewLogic.whySectionMode(
                    hasDominantChange: graph.dominantBehaviorChange != nil,
                    hasWhyOrConsequence: graph.dominantBehaviorChange?.why != nil
                        || graph.dominantBehaviorChange?.consequence != nil,
                    awaitingBehavior: awaitingBehavior
                ) {
                case .whyAndConsequence:
                    if let change = graph.dominantBehaviorChange {
                        whyAndConsequence(change)
                            .padding(.top, 26)
                    }
                case .placeholder:
                    whyPlaceholder
                        .padding(.top, 26)
                case .none:
                    EmptyView()
                }

                let considerations = graph.thingsToThinkAbout(during: analysis)
                switch SummaryViewLogic.thingsToThinkAboutBranch(
                    items: considerations, judgmentStopped: judgmentStatus == .stopped)
                {
                case .list:
                    if let items = considerations {
                        thingsToThinkAbout(items)
                            .padding(.top, 36)
                    }
                case .stoppedEmpty:
                    retryLine("Stopped before weighing what needs judgment.", stage: .judgment)
                        .padding(.top, 36)
                case .none:
                    EmptyView()
                case .placeholder:
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(graph.pr.title)
                .font(.system(size: 26, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            HStack(spacing: 6) {
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
        SummaryViewLogic.factTint(tone).map(AnyShapeStyle.init) ?? AnyShapeStyle(.secondary)
    }

    private var dot: some View { Text("\u{00b7}").foregroundStyle(.tertiary) }

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
                if let how = graph.pr.howItWasSolved {
                    Text(how.text)
                        .font(.title3.weight(.medium))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .reviewContextMenu(.pullRequest)
                        .transition(.opacity)
                    WorkingLine(text: "Building before / after…")
                } else {
                    WorkingLine(
                        text: SummaryViewLogic.awaitingBehaviorText(
                            understandingFailed: understandingStatus.failure != nil),
                        font: .title3)
                }
            } else if let problem = graph.pr.problemToBeSolved {
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
            if let text = SummaryViewLogic.retryBannerText(
                status: behaviorStatus,
                failureText: "Couldn't build the before / after.",
                stoppedText: "Stopped before the before / after was built."
            ) {
                retryLine(text, stage: .behaviorChange)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: graph.dominantBehaviorChange?.id)
        .animation(.easeInOut(duration: 0.35), value: graph.pr.howItWasSolved?.text)
    }

    private func retryLine(_ text: String, stage: PipelineStage) -> some View {
        HStack(spacing: 8) {
            StageStatusGlyph(status: analysis.status(stage))
            Text(text).foregroundStyle(.secondary)
            Button("Retry") { onRetry(stage) }
                .buttonStyle(.link)
        }
        .font(.caption)
    }

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
                Image(systemName: SummaryViewLogic.judgmentSymbol)
                    .foregroundStyle(.tertiary)
                    .font(.callout)
                Text(verbatim: SummaryViewLogic.judgmentHeaderLabel(count: nil))
                    .font(.callout.weight(.semibold))
                    .tracking(0.5)
            }
            WorkingLine(text: judgmentWorkingText)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.06)))
    }

    private var judgmentWorkingText: String {
        SummaryViewLogic.judgmentWorkingText(
            decisionsFound: graph.decisions.count, decisionsStatus: analysis.status(.decisions),
            judgmentStatus: judgmentStatus
        )
    }

    private func openStage(_ stage: BehaviorStage) {
        navigate(SummaryViewLogic.navigationTarget(for: stage))
    }

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
                ProvenanceMark(
                    provenance: statement.provenance, confidence: statement.confidence, source: statement.source)
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

    private func thingsToThinkAbout(_ items: [Consideration]) -> some View {
        let visible = SummaryViewLogic.visibleConsiderations(
            items, showAll: showAllConsiderations, budget: considerationBudget)
        let progress = graph.reviewProgress(discussed: discussed)
        let resolvedText = SummaryViewLogic.resolvedProgressText(reviewed: progress.reviewed, total: progress.total)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: SummaryViewLogic.judgmentSymbol)
                    .foregroundStyle(.secondary)
                    .font(.callout)
                Text(verbatim: "\(items.count)")
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                Text(verbatim: SummaryViewLogic.judgmentHeaderLabel(count: items.count))
                    .font(.callout.weight(.semibold))
                    .tracking(0.5)
                Spacer()
                if let resolvedText {
                    Text(verbatim: resolvedText)
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
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
                    isResolved: graph.isResolved(item, discussed: discussed),
                    isExpanded: expandedConsideration == item.id,
                    onToggle: {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            expandedConsideration = SummaryViewLogic.toggled(expandedConsideration, item.id)
                        }
                    },
                    onReview: { review(item) },
                    navigate: navigate
                )
            }

            if let moreLabel = SummaryViewLogic.showMoreLabel(
                count: items.count, budget: considerationBudget, showingAll: showAllConsiderations)
            {
                Button(moreLabel) {
                    withAnimation(.easeInOut(duration: 0.18)) { showAllConsiderations.toggle() }
                }
                .buttonStyle(.link)
                .font(.caption)
                .padding(.leading, 60)
                .padding(.bottom, 4)
            }

            switch SummaryViewLogic.judgmentTailState(status: judgmentStatus) {
            case .working:
                WorkingLine(text: judgmentWorkingText, font: .caption)
                    .padding(.leading, 58)
                    .padding(.top, 6)
                    .padding(.bottom, 4)
            case .failed:
                retryLine("Couldn't finish weighing what needs judgment.", stage: .judgment)
                    .padding(.leading, 58)
                    .padding(.top, 6)
            case .stopped:
                retryLine("Stopped before weighing what else needs judgment.", stage: .judgment)
                    .padding(.leading, 58)
                    .padding(.top, 6)
            case .settled:
                EmptyView()
            }
        }
        .padding(.bottom, 10)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.1)))
    }

    private func review(_ item: Consideration) {
        switch SummaryViewLogic.reviewAction(hasDecision: graph.reviewDecisionId(for: item) != nil) {
        case .navigate: navigate(.consideration(item.id))
        case .ask: actions.ask(.consideration(item.id))
        }
    }

    private var otherBehaviorChanges: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Other behavior changes")
            VStack(alignment: .leading, spacing: 4) {
                ForEach(graph.behaviorChanges.dropFirst()) { change in
                    VStack(alignment: .leading, spacing: 10) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                expandedOtherChange = SummaryViewLogic.toggled(expandedOtherChange, change.id)
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

    private var exploreTheChange: some View {
        let architecture = SummaryViewLogic.architectureReadyText(
            impactLabel: graph.architecture?.impact.label, partsCount: graph.topLevelParts.count
        )
        let progress = graph.reviewProgress(discussed: discussed)
        let decisionsReady = SummaryViewLogic.decisionsReadyText(
            reviewed: progress.reviewed, total: progress.total, decisionsCount: graph.decisions.count
        )
        return VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Explore the change")
            HStack(spacing: 12) {
                ExploreTile(
                    title: "Architecture",
                    detail: tileDetail(.architecture, ready: architecture, count: graph.components.count, noun: "part"),
                    symbol: "square.stack.3d.up"
                ) { navigate(.architecture) }
                ExploreTile(
                    title: "Flows",
                    detail: tileDetail(
                        .flows, ready: "\(graph.flows.count) traced", count: graph.flows.count, noun: "flow"),
                    symbol: "arrow.triangle.branch"
                ) { navigate(.flows) }
                ExploreTile(
                    title: "Decisions",
                    detail: tileDetail(
                        .decisions, ready: decisionsReady, count: graph.decisions.count, noun: "decision"),
                    symbol: "checklist"
                ) { navigate(.decisions) }
            }
        }
    }

    private func tileDetail(_ stage: PipelineStage, ready: String, count: Int, noun: String) -> String {
        SummaryViewLogic.tileDetail(status: analysis.status(stage), ready: ready, count: count, noun: noun)
    }

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

struct ConsiderationRow: View {
    let number: Int
    let item: Consideration
    let graph: PRGraph
    let isResolved: Bool
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
                    if let context = item.contextLabel {
                        Text(verbatim: context.uppercased())
                            .font(.caption2.weight(.semibold))
                            .tracking(0.6)
                            .foregroundStyle(.tertiary)
                    }
                    Text(item.headline)
                        .font(.body.weight(.semibold))
                        .lineLimit(isExpanded ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                    if !item.impact.isEmpty {
                        Text(item.impact)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(isExpanded ? nil : 2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let decision = item.decision {
                        decisionLine(decision)
                            .padding(.top, 3)
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
                .help(SummaryViewLogic.reviewButtonHelp(hasDecision: graph.reviewDecisionId(for: item) != nil))
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

    private func decisionLine(_ decision: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: SummaryViewLogic.decisionLabel(kind: item.kind))
                .font(.caption.weight(.semibold))
                .foregroundStyle(item.kind == .question ? Color.secondary : Color.orange)
            Text(decision)
                .font(.callout)
                .lineLimit(isExpanded ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 8)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1)
                .fill((item.kind == .question ? Color.secondary : Color.orange).opacity(0.5))
                .frame(width: 2)
        }
    }

    private var badge: some View {
        let isQuestion = item.kind == .question
        return ZStack {
            if isResolved {
                Circle().fill(Color.green.opacity(0.14))
                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.green)
            } else {
                openBadge(isQuestion)
            }
        }
        .frame(width: 24, height: 24)
        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
        .help(SummaryViewLogic.considerationBadgeHelp(isResolved: isResolved, isQuestion: isQuestion))
    }

    @ViewBuilder
    private func openBadge(_ isQuestion: Bool) -> some View {
        Circle()
            .fill(Color.secondary.opacity(isQuestion ? 0.14 : 0.18))
        if isQuestion {
            Image(systemName: "questionmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
        } else {
            Text(verbatim: "\(number)").font(.system(size: 12, weight: .semibold)).monospacedDigit().foregroundStyle(
                .primary)
        }
    }

    @ViewBuilder
    private var expanded: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let evidence = item.evidence, !evidence.isEmpty {
                Text(evidence)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            let related = relatedLinks
            if !related.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(related, id: \.title) { link in
                        Button {
                            navigate(link.target)
                        } label: {
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
                Text(SummaryViewLogic.capitalizedFirst(PRGraph.provenanceLabel(item.provenance, item.confidence)))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Button {
                    actions.ask(.consideration(item.id))
                } label: {
                    Label("Ask about this", systemImage: "sparkles").font(.caption)
                }
                .buttonStyle(.link)
            }
        }
    }

    private var relatedLinks: [(title: String, symbol: String, target: NavigationTarget)] {
        SummaryViewLogic.relatedLinks(for: item, graph: graph)
    }
}

struct ExploreTile: View {
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
            .background(
                hovered ? Color.secondary.opacity(0.1) : Color.secondary.opacity(0.05),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator.opacity(0.6)))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovered = h } }
    }
}

enum SummaryViewLogic {
    static func toggled(_ current: String?, _ id: String) -> String? {
        current == id ? nil : id
    }

    enum ReviewAction: Equatable { case navigate, ask }

    static func reviewAction(hasDecision: Bool) -> ReviewAction {
        hasDecision ? .navigate : .ask
    }

    static func factTint(_ tone: GlanceFact.Tone) -> Color? {
        switch tone {
        case .plain: return nil
        case .good: return .green
        case .caution: return .orange
        case .bad: return .red
        }
    }

    static func judgmentWorkingText(decisionsFound: Int, decisionsStatus: StageStatus, judgmentStatus: StageStatus)
        -> String
    {
        if !judgmentStatus.isRunning, decisionsStatus.isRunning || decisionsStatus == .pending {
            return decisionsFound > 0
                ? "\(decisionsFound) \(decisionsFound == 1 ? "decision" : "decisions") found · looking for consequential choices…"
                : "Looking for consequential choices…"
        }
        return "Weighing what needs your judgment…"
    }

    static func navigationTarget(for stage: BehaviorStage) -> NavigationTarget {
        if let componentId = stage.componentIds.first {
            return .componentDetail(componentId)
        } else if let flowId = stage.flowId {
            return .flowDetail(flowId)
        } else {
            return .architecture
        }
    }

    static func tileDetail(status: StageStatus, ready: String, count: Int, noun: String) -> String {
        switch status {
        case .done, .stale: return ready
        case .failed: return "Couldn't be analyzed"
        case .stopped: return count > 0 ? "\(count) \(noun)\(count == 1 ? "" : "s"), stopped" : "Stopped"
        case .running: return count > 0 ? "\(count) \(noun)\(count == 1 ? "" : "s") so far…" : "Analyzing…"
        case .pending: return "Waiting…"
        }
    }

    static func relatedLinks(for item: Consideration, graph: PRGraph) -> [(
        title: String, symbol: String, target: NavigationTarget
    )] {
        item.relatedIds.compactMap { id in
            if let d = graph.decision(id) { return (d.title, "checklist", .decisionDetail(id)) }
            if let c = graph.component(id) { return (c.title, "square.stack.3d.up", .componentDetail(id)) }
            if let f = graph.flow(id) { return (f.title, "arrow.triangle.branch", .flowDetail(id)) }
            return nil
        }
    }

    static func capitalizedFirst(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }

    static func awaitingBehaviorText(understandingFailed: Bool) -> String {
        understandingFailed ? "Building before / after…" : "Understanding the change…"
    }

    static func retryBannerText(status: StageStatus, failureText: String, stoppedText: String) -> String? {
        if status.failure != nil { return failureText }
        if status == .stopped { return stoppedText }
        return nil
    }

    enum JudgmentTailState: Equatable {
        case working
        case failed
        case stopped
        case settled
    }

    static func judgmentTailState(status: StageStatus) -> JudgmentTailState {
        if !status.isSettled { return .working }
        if status.failure != nil { return .failed }
        if status == .stopped { return .stopped }
        return .settled
    }

    enum ThingsToThinkAboutBranch: Equatable {
        case list
        case stoppedEmpty
        case none
        case placeholder
    }

    static func thingsToThinkAboutBranch(items: [Consideration]?, judgmentStopped: Bool) -> ThingsToThinkAboutBranch {
        guard let items else { return .placeholder }
        if !items.isEmpty { return .list }
        if judgmentStopped { return .stoppedEmpty }
        return .none
    }

    static func visibleConsiderations(_ items: [Consideration], showAll: Bool, budget: Int) -> [Consideration] {
        showAll ? items : Array(items.prefix(budget))
    }

    static func showMoreLabel(count: Int, budget: Int, showingAll: Bool) -> String? {
        guard count > budget else { return nil }
        return showingAll ? "Show fewer" : "Show \(count - budget) more"
    }

    static func judgmentHeaderLabel(count: Int?) -> String {
        (count == 1 ? "area needing your judgment" : "areas needing your judgment").uppercased()
    }

    static let judgmentSymbol = "scalemass"

    static func decisionLabel(kind: ConsiderationKind) -> String {
        kind == .question ? "To confirm" : "Decision"
    }

    static func resolvedProgressText(reviewed: Int, total: Int) -> String? {
        guard reviewed > 0 else { return nil }
        return "\(reviewed) of \(total) resolved"
    }

    static func architectureReadyText(impactLabel: String?, partsCount: Int) -> String {
        if let impactLabel { return "\(impactLabel) architectural impact" }
        return "\(partsCount) parts"
    }

    static func decisionsReadyText(reviewed: Int, total: Int, decisionsCount: Int) -> String {
        total > 0 ? "\(reviewed) of \(total) resolved" : "\(decisionsCount) identified"
    }

    static func considerationBadgeHelp(isResolved: Bool, isQuestion: Bool) -> String {
        if isResolved { return "Resolved" }
        return isQuestion ? "Open question — the analysis couldn't settle this" : "A judgment call worth your attention"
    }

    static func reviewButtonHelp(hasDecision: Bool) -> String {
        hasDecision ? "Review the decision this question is about" : "Ask about this"
    }

    enum WhySectionMode: Equatable {
        case whyAndConsequence
        case placeholder
        case none
    }

    static func whySectionMode(hasDominantChange: Bool, hasWhyOrConsequence: Bool, awaitingBehavior: Bool)
        -> WhySectionMode
    {
        if hasDominantChange && hasWhyOrConsequence { return .whyAndConsequence }
        if awaitingBehavior { return .placeholder }
        return .none
    }
}
