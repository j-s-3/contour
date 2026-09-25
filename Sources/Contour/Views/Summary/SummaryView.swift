import SwiftUI

/// The landing page — rebuilt around the BehaviorChange as hero content. "What does the
/// system do differently now" must be answerable in ~20 seconds via the before/after
/// diagram, not paragraphs. Everything else on this screen is a one-line entry point into
/// its full lens, never a restated wall of text.
struct SummaryView: View {
    let graph: PRGraph
    var navigate: (NavigationTarget) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if let change = graph.dominantBehaviorChange {
                    behaviorHero(change)
                } else if graph.pr.problemToBeSolved != nil || graph.pr.howItWasSolved != nil {
                    eli5Section
                }
                if graph.behaviorChanges.count > 1 {
                    otherBehaviorChanges
                }
                // Wide-window layout: quick links + review progress form a left column that
                // scales with the window; judgment/uncertainty call-outs form a second column
                // beside them, instead of one narrow centered strip with dead space either side.
                HStack(alignment: .top, spacing: 22) {
                    VStack(alignment: .leading, spacing: 22) {
                        quickLinksGrid
                        progressSection
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if !graph.pr.needsJudgment.isEmpty || !graph.pr.uncertainties.isEmpty {
                        VStack(alignment: .leading, spacing: 22) {
                            if !graph.pr.needsJudgment.isEmpty { needsJudgmentSection }
                            if !graph.pr.uncertainties.isEmpty { uncertaintiesSection }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 1500, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(graph.pr.title)
                .font(.largeTitle.weight(.semibold))
            HStack(spacing: 8) {
                Text("\(graph.pr.repo) #\(graph.pr.number)")
                Text("\u{00b7}").foregroundStyle(.tertiary)
                Text(graph.pr.state.capitalized)
                Text("\u{00b7}").foregroundStyle(.tertiary)
                Text("\(graph.pr.author) \u{00b7} \(graph.pr.branch) \u{2192} \(graph.pr.baseBranch)")
                if let jira = graph.pr.jiraTicket {
                    Text("\u{00b7}").foregroundStyle(.tertiary)
                    jiraChip(jira)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    private func jiraChip(_ jira: JiraTicketInfo) -> some View {
        Link(destination: URL(string: jira.url) ?? URL(string: "about:blank")!) {
            HStack(spacing: 4) {
                Image(systemName: "link")
                Text(jira.key)
            }
            .font(.caption.weight(.semibold))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.blue)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(Color.blue.opacity(0.1), in: Capsule())
        .help(jira.summary)
    }

    // MARK: - Hero: the behavior change

    private func behaviorHero(_ change: BehaviorChange) -> some View {
        sectionCard(title: change.title) {
            VStack(alignment: .leading, spacing: 14) {
                BehaviorChangeDiagramView(change: change) { stage in
                    if let componentId = stage.componentIds.first {
                        navigate(.componentDetail(componentId))
                    } else if let flowId = stage.flowId {
                        navigate(.flowDetail(flowId))
                    } else {
                        navigate(.architecture)
                    }
                }
                if change.why != nil || change.consequence != nil || change.humanQuestion != nil {
                    Divider()
                }
                if let why = change.why {
                    oneLine("Why", statement: why, action: { navigate(.decisions) })
                }
                if let consequence = change.consequence {
                    oneLine("Consequence", statement: consequence, action: { navigate(.architecture) })
                }
                if let humanQuestion = change.humanQuestion {
                    oneLine("The question", statement: humanQuestion, action: { navigate(.decisions) }, tint: .orange)
                }
            }
        }
    }

    private func oneLine(_ label: String, statement: Statement, action: @escaping () -> Void, tint: Color = .primary) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 8) {
                Text(label.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(tint == .primary ? .secondary : tint)
                    .frame(width: 90, alignment: .leading)
                ProvenanceBadge(provenance: statement.provenance, confidence: statement.confidence)
                Text(statement.text)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Spacer()
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }

    private var otherBehaviorChanges: some View {
        sectionCard(title: "Other behavior changes", trailing: "\(graph.behaviorChanges.count - 1)") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(graph.behaviorChanges.dropFirst()) { change in
                    Text("\u{2192} \(change.title)").font(.callout)
                }
            }
        }
    }

    /// Fallback hero when no BehaviorChange was extracted — the plain-language ELI5 pair.
    private var eli5Section: some View {
        HStack(alignment: .top, spacing: 22) {
            if let problem = graph.pr.problemToBeSolved {
                sectionCard(title: "Problem to be solved") { StatementView(statement: problem) }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let solved = graph.pr.howItWasSolved {
                sectionCard(title: "How it was solved") { StatementView(statement: solved) }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Quick links into each lens (one card each, no restated prose)

    /// A 2x2 grid rather than a single narrow vertical stack — on a wide window a stack of
    /// four one-line rows leaves most of the width empty; a grid actually uses it.
    private var quickLinksGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            quickLink(
                title: "Architecture", detail: "\(graph.components.filter { $0.level <= .system }.count) systems touched",
                symbol: "square.stack.3d.up", target: .architecture
            )
            quickLink(
                title: "Decisions", detail: "\(graph.decisions.count) decisions, \(graph.decisions.filter { $0.level <= .system }.count) system-level",
                symbol: "checklist", target: .decisions
            )
            quickLink(
                title: "Flows", detail: "\(graph.flows.count) traced",
                symbol: "arrow.triangle.branch", target: .flows
            )
            quickLink(
                title: "Entry points", detail: "\(graph.entryPoints.count) triggers",
                symbol: "arrow.right.to.line", target: .entryPoints
            )
        }
    }

    private func quickLink(title: String, detail: String, symbol: String, target: NavigationTarget) -> some View {
        Button { navigate(target) } label: {
            HStack {
                Label(title, systemImage: symbol).font(.callout.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private var needsJudgmentSection: some View {
        sectionCard(title: "\u{26a0} Needs human judgment", tint: .orange) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(graph.pr.needsJudgment.prefix(3)) { StatementView(statement: $0) }
                if graph.pr.needsJudgment.count > 3 {
                    Button("Show all (\(graph.pr.needsJudgment.count)) \u{2192}") { navigate(.decisions) }.buttonStyle(.link).font(.caption)
                }
            }
        }
    }

    private var uncertaintiesSection: some View {
        sectionCard(title: "\u{FF1F} Uncertainties", tint: .purple) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(graph.pr.uncertainties.prefix(3)) { StatementView(statement: $0) }
            }
        }
    }

    private var progressSection: some View {
        let progress = graph.reviewProgress
        return sectionCard(title: "Review progress") {
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: progress.total == 0 ? 0 : Double(progress.reviewed), total: Double(max(progress.total, 1)))
                Text("\(progress.reviewed)/\(progress.total) decisions reviewed")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Helpers

    private func sectionCard<Content: View>(title: String, trailing: String? = nil, tint: Color = .primary, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint == .primary ? .secondary : tint)
                    .tracking(0.5)
                Spacer()
                if let trailing {
                    Text(trailing).font(.caption).foregroundStyle(.secondary)
                }
            }
            content()
        }
        .padding(16)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }
}
