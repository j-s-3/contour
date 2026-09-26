import SwiftUI

/// The Architecture lens (§4.3): "draw the relevant part of the system on a whiteboard, and
/// show me where this change sits."
///
/// It opens by saying how much the PR changes the structure — often "no structural change"
/// — and then draws the handful of conceptual parts involved, with only what changed drawing
/// the eye (Delta, the default; Before and After are plain snapshots). A part with parts
/// inside can be zoomed into; implementation and code are reached from the inspector, which
/// appears only when something is selected. Decisions and Overview questions are marked on
/// the box or arrow they concern and lead to the Decisions lens.
///
/// Everything here is sized to the space it's given: the drawing fits itself to the pane
/// rather than asking for its natural size. An earlier version put an unbounded frame inside
/// a two-axis scroll view, which made the detail column wider than the window and left the
/// sidebar blank (issue #1).
struct ArchitectureView: View {
    let graph: PRGraph
    /// A part or relationship the navigation target asked for ("Open details", a chat link,
    /// "Show in Architecture" from a flow).
    var focus: ArchAnchor? = nil

    @Environment(\.reviewActions) private var actions

    @State private var mode: ArchMode = .delta
    @State private var path: [String] = []
    @State private var selection: ArchAnchor?

    private var level: ArchLevel { graph.architectureLevel(path: path) }

    var body: some View {
        let level = self.level
        VStack(alignment: .leading, spacing: 0) {
            header(level)
            Divider()
            if level.nodes.isEmpty {
                ContentUnavailableView("Nothing to draw", systemImage: "square.stack.3d.up",
                                       description: Text("The analysis didn't identify any architecture for this PR."))
            } else {
                // The inspector takes its own column only while something is selected, and
                // the drawing refits beside it rather than being covered.
                HStack(spacing: 0) {
                    ArchitectureDiagramView(
                        boxes: boxes(level),
                        arrows: arrows(level),
                        containers: containers(level),
                        selection: selection,
                        onSelect: { anchor in withAnimation(.easeOut(duration: 0.15)) { selection = anchor } },
                        onZoomIn: zoom(into:),
                        onOpenDecision: { actions.navigate(.decisionDetail($0)) }
                    )

                    if let selection {
                        ArchitectureInspector(
                            graph: graph, level: level, anchor: selection,
                            onSelect: { anchor in self.selection = anchor },
                            onZoomIn: zoom(into:),
                            onClose: { withAnimation(.easeOut(duration: 0.15)) { self.selection = nil } }
                        )
                        .frame(width: 340)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .background(.background.secondary)
                        .overlay(alignment: .leading) { Divider() }
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                legend(level)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { if let focus { reveal(focus) } else { publishFocus() } }
        .onChange(of: focus) { _, new in if let new { reveal(new) } }
        .onChange(of: selection) { _, _ in publishFocus() }
        .onChange(of: mode) { _, _ in dropHiddenSelection() }
        .onDisappear { actions.focus(nil) }
    }

    // MARK: - Header

    private func header(_ level: ArchLevel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                impactLabel
                Spacer()
                Picker("View", selection: $mode) {
                    ForEach(ArchMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
                .help("Delta shows the existing architecture with this PR's change highlighted")
            }
            if let headline = graph.architecture?.headline, !headline.isEmpty {
                Text(headline).font(.title2.weight(.semibold))
                    .lineLimit(2)
            }
            if let explanation = graph.architecture?.explanation ?? graph.pr.architectureImpact {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(explanation.text)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                    ProvenanceMark(provenance: explanation.provenance, confidence: explanation.confidence, source: explanation.source)
                }
                .frame(maxWidth: 900, alignment: .leading)
                .reviewContextMenu(.pullRequest)
            }
            if !path.isEmpty { breadcrumb }
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private var impactLabel: some View {
        HStack(spacing: 8) {
            Text("ARCHITECTURAL IMPACT")
                .font(.caption.weight(.semibold)).tracking(0.6).foregroundStyle(.secondary)
            if let impact = graph.architecture?.impact {
                Text(impact.label)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(impact.color)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(impact.color.opacity(0.13), in: Capsule())
            }
        }
    }

    private var breadcrumb: some View {
        HStack(spacing: 6) {
            Button("System") { zoom(to: []) }.buttonStyle(.link)
            ForEach(Array(path.enumerated()), id: \.offset) { i, id in
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                if i == path.count - 1 {
                    Text(graph.component(id)?.title ?? id).fontWeight(.semibold)
                } else {
                    Button(graph.component(id)?.title ?? id) { zoom(to: Array(path.prefix(i + 1))) }.buttonStyle(.link)
                }
            }
            Spacer(minLength: 12)
            Button { zoom(to: Array(path.dropLast())) } label: {
                Label("Zoom out", systemImage: "minus.magnifyingglass")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("-", modifiers: .command)
        }
        .font(.callout)
    }

    // MARK: - What to draw

    private func boxes(_ level: ArchLevel) -> [ArchBox] {
        let decisions = mode == .before ? [:] : graph.decisionAnchors(on: level)
        let questions = mode == .before ? [:] : graph.questionAnchors(on: level)
        let neighbors = Set(level.context.map(\.id))
        return level.nodes.compactMap { part in
            if mode == .before, part.changeKind == .new { return nil }
            if mode == .after, part.changeKind == .removed { return nil }
            let changed = [.new, .changed, .removed].contains(part.changeKind)
            var box = ArchBox(
                id: part.id, title: part.title, purpose: part.summary?.text,
                emphasis: mode == .delta ? part.changeKind.emphasis : .context,
                isNeighbor: neighbors.contains(part.id),
                hasInside: !neighbors.contains(part.id) && !graph.parts(inside: part.id).isEmpty
            )
            if changed {
                switch mode {
                case .delta: box.changeBefore = part.delta?.before; box.changeAfter = part.delta?.after
                case .before: box.changeBefore = part.delta?.before
                case .after: box.changeAfter = part.delta?.after
                }
            }
            if let marked = decisions[.node(part.id)], let first = marked.first {
                box.decision = graph.brief(for: first).question
                box.decisionId = first.id
                box.moreDecisions = marked.count - 1
            }
            box.questions = questions[.node(part.id)]?.count ?? 0
            return box
        }
    }

    private func arrows(_ level: ArchLevel) -> [ArchArrow] {
        let drawn = Set(boxes(level).map(\.id))
        let decisions = mode == .before ? [:] : graph.decisionAnchors(on: level)
        let questions = mode == .before ? [:] : graph.questionAnchors(on: level)
        return level.edges.compactMap { le in
            let e = le.edge
            guard drawn.contains(le.fromId), drawn.contains(le.toId) else { return nil }
            if mode == .before, e.change == .new { return nil }
            if mode == .after, e.change == .removed { return nil }
            let label = mode == .before ? (e.previousLabel ?? e.label) : e.label
            return ArchArrow(
                id: le.id, fromId: le.fromId, toId: le.toId,
                label: label.isEmpty ? "uses" : label,
                previousLabel: mode == .delta && e.change == .changed ? e.previousLabel : nil,
                emphasis: mode == .delta ? e.change.emphasis : .context,
                isAsync: e.flow == .async,
                questions: questions[.edge(le.id)]?.count ?? 0,
                decisions: decisions[.edge(le.id)]?.count ?? 0
            )
        }
    }

    private func containers(_ level: ArchLevel) -> [ArchContainer] {
        let drawn = Set(boxes(level).map(\.id))
        return level.boundaries.compactMap { b in
            let members = b.componentIds.filter(drawn.contains)
            guard !members.isEmpty else { return nil }
            return ArchContainer(id: b.id, label: b.label, kind: b.kind, memberIds: members, isFocus: b.id.hasPrefix("focus:"))
        }
    }

    @ViewBuilder
    private func legend(_ level: ArchLevel) -> some View {
        if mode == .delta {
            let boxes = boxes(level), arrows = arrows(level)
            let kinds = Set(boxes.map(\.emphasis) + arrows.map(\.emphasis)).subtracting([.context])
            let hasDecision = boxes.contains { $0.decision != nil } || arrows.contains { $0.decisions > 0 }
            let hasQuestion = boxes.contains { $0.questions > 0 } || arrows.contains { $0.questions > 0 }
            let hasAsync = arrows.contains(where: \.isAsync)
            if !kinds.isEmpty || hasDecision || hasQuestion || hasAsync {
                HStack(spacing: 14) {
                    ForEach([ArchEmphasis.changed, .added, .removed].filter(kinds.contains), id: \.word) { k in
                        HStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 3).strokeBorder(k.color, lineWidth: 1.6).frame(width: 14, height: 10)
                            Text(k.word)
                        }
                    }
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 3).strokeBorder(Color.secondary.opacity(0.5)).frame(width: 14, height: 10)
                        Text("Existing context")
                    }
                    if hasAsync { Label("Asynchronous", systemImage: "clock.arrow.circlepath") }
                    if hasDecision { Text("◇ Decision").foregroundStyle(.purple) }
                    if hasQuestion { Label("Review question", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Zoom and selection

    private func zoom(into id: String) {
        guard !graph.parts(inside: id).isEmpty else { return }
        zoom(to: graph.ancestry(of: id).map(\.id))
    }

    private func zoom(to newPath: [String]) {
        withAnimation(.easeInOut(duration: 0.2)) {
            let previousFocus = path.last
            path = newPath
            // Zooming out keeps the part we came from selected, so the reviewer sees where they were.
            if let previousFocus, level.contains(previousFocus) {
                selection = .node(previousFocus)
            } else {
                selection = nil
            }
        }
    }

    /// Shows a part or relationship that navigation asked for, zooming in if it's inside
    /// another part.
    private func reveal(_ anchor: ArchAnchor) {
        switch anchor {
        case .node(let id):
            guard let part = graph.drawablePart(for: id) else { return }
            path = graph.architecturePath(showing: part.id)
            selection = .node(part.id)
        case .edge(let id):
            guard let edge = graph.resolvedEdges.first(where: { $0.id == id }) else { return }
            // The outermost level where this relationship is its own arrow.
            let candidates = [[]] + graph.ancestry(of: edge.fromId).dropLast().indices.map { i in
                Array(graph.ancestry(of: edge.fromId).prefix(i + 1).map(\.id))
            }
            for candidate in candidates {
                let level = graph.architectureLevel(path: candidate)
                if let drawn = level.edges.first(where: { $0.id == id || $0.mergedIds.contains(id) }) {
                    path = candidate
                    selection = .edge(drawn.id)
                    return
                }
            }
        }
    }

    private func dropHiddenSelection() {
        guard let selection else { return }
        let boxes = Set(boxes(level).map(\.id))
        let arrows = Set(arrows(level).map(\.id))
        switch selection {
        case .node(let id) where !boxes.contains(id): self.selection = nil
        case .edge(let id) where !arrows.contains(id): self.selection = nil
        default: break
        }
    }

    /// Tells the window what "this" is for ⌘⇧A.
    private func publishFocus() {
        switch selection {
        case .node(let id): actions.focus(.component(id))
        case .edge(let id): actions.focus(.relationship(id))
        case nil: actions.focus(path.last.map { .component($0) })
        }
    }
}

extension ChangeKind {
    var emphasis: ArchEmphasis {
        switch self {
        case .new: return .added
        case .changed: return .changed
        case .removed: return .removed
        case .touched, .unchanged: return .context
        }
    }
}

extension EdgeChange {
    var emphasis: ArchEmphasis {
        switch self {
        case .new: return .added
        case .changed: return .changed
        case .removed: return .removed
        case .existing: return .context
        }
    }
}

extension ArchitecturalImpact {
    var color: Color {
        switch self {
        case .none: return .secondary
        case .low: return .blue
        case .moderate: return .orange
        case .significant: return .red
        }
    }
}
