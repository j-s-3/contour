import SwiftUI

struct ArchitectureView: View {
    let graph: PRGraph
    var focus: ArchAnchor? = nil
    @Binding var mode: DiagramMode

    @Environment(\.reviewActions) private var actions

    @FocusState private var keyboardFocused: Bool
    @State private var path: [String] = []
    @State private var selection: ArchAnchor?

    private var level: ArchLevel { graph.architectureLevel(path: path) }

    var body: some View {
        let level = self.level
        VStack(alignment: .leading, spacing: 0) {
            header(level)
            Divider()
            if level.nodes.isEmpty {
                ContentUnavailableView(
                    "Nothing to draw", systemImage: "square.stack.3d.up",
                    description: Text("The analysis didn't identify any architecture for this PR."))
            } else {
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
        .focusable()
        .focusEffectDisabled()
        .focused($keyboardFocused)
        .diagramModeKeys($mode)
        .onAppear {
            keyboardFocused = true
            if let focus { reveal(focus) } else { publishFocus() }
        }
        .onChange(of: focus) { _, new in if let new { reveal(new) } }
        .onChange(of: selection) { _, _ in
            keyboardFocused = true
            publishFocus()
        }
        .onChange(of: mode) { _, _ in dropHiddenSelection() }
        .onDisappear { actions.focus(nil) }
    }

    private func header(_ level: ArchLevel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            impactLabel
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
                    ProvenanceMark(
                        provenance: explanation.provenance, confidence: explanation.confidence,
                        source: explanation.source)
                }
                .frame(maxWidth: 900, alignment: .leading)
                .reviewContextMenu(.pullRequest)
            }
            if !path.isEmpty { breadcrumb }
            DiagramModeControl(mode: $mode, subject: "architecture")
                .padding(.top, 4)
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
            Button {
                zoom(to: Array(path.dropLast()))
            } label: {
                Label("Zoom out", systemImage: "minus.magnifyingglass")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("-", modifiers: .command)
        }
        .font(.callout)
    }

    private func boxes(_ level: ArchLevel) -> [ArchBox] { Self.boxes(level, graph: graph, mode: mode) }
    private func arrows(_ level: ArchLevel) -> [ArchArrow] { Self.arrows(level, graph: graph, mode: mode) }
    private func containers(_ level: ArchLevel) -> [ArchContainer] { Self.containers(level, graph: graph, mode: mode) }

    nonisolated static func boxes(_ level: ArchLevel, graph: PRGraph, mode: DiagramMode) -> [ArchBox] {
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
                case .delta:
                    box.changeBefore = part.delta?.before
                    box.changeAfter = part.delta?.after
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

    nonisolated static func arrows(_ level: ArchLevel, graph: PRGraph, mode: DiagramMode) -> [ArchArrow] {
        let drawn = Set(Self.boxes(level, graph: graph, mode: mode).map(\.id))
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

    nonisolated static func containers(_ level: ArchLevel, graph: PRGraph, mode: DiagramMode) -> [ArchContainer] {
        let drawn = Set(Self.boxes(level, graph: graph, mode: mode).map(\.id))
        return level.boundaries.compactMap { b in
            let members = b.componentIds.filter(drawn.contains)
            guard !members.isEmpty else { return nil }
            return ArchContainer(
                id: b.id, label: b.label, kind: b.kind, memberIds: members, isFocus: b.id.hasPrefix("focus:"))
        }
    }

    @ViewBuilder
    private func legend(_ level: ArchLevel) -> some View {
        if let info = Self.legendInfo(level, graph: graph, mode: mode) {
            HStack(spacing: 14) {
                ForEach([ArchEmphasis.changed, .added, .removed].filter(info.kinds.contains), id: \.word) { k in
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 3).strokeBorder(k.color, lineWidth: 1.6).frame(
                            width: 14, height: 10)
                        Text(k.word)
                    }
                }
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 3).strokeBorder(Color.secondary.opacity(0.5)).frame(
                        width: 14, height: 10)
                    Text("Existing context")
                }
                if info.hasAsync { Label("Asynchronous", systemImage: "clock.arrow.circlepath") }
                if info.hasDecision { Text("◇ Decision").foregroundStyle(.purple) }
                if info.hasQuestion {
                    Label("Review question", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    struct LegendInfo: Equatable {
        var kinds: [ArchEmphasis]
        var hasDecision: Bool
        var hasQuestion: Bool
        var hasAsync: Bool
    }

    nonisolated static func legendInfo(_ level: ArchLevel, graph: PRGraph, mode: DiagramMode) -> LegendInfo? {
        guard mode == .delta else { return nil }
        let boxes = Self.boxes(level, graph: graph, mode: mode)
        let arrows = Self.arrows(level, graph: graph, mode: mode)
        let present = Set(boxes.map(\.emphasis) + arrows.map(\.emphasis)).subtracting([.context])
        let kinds = [ArchEmphasis.changed, .added, .removed].filter(present.contains)
        let hasDecision = boxes.contains { $0.decision != nil } || arrows.contains { $0.decisions > 0 }
        let hasQuestion = boxes.contains { $0.questions > 0 } || arrows.contains { $0.questions > 0 }
        let hasAsync = arrows.contains(where: \.isAsync)
        guard !kinds.isEmpty || hasDecision || hasQuestion || hasAsync else { return nil }
        return LegendInfo(kinds: kinds, hasDecision: hasDecision, hasQuestion: hasQuestion, hasAsync: hasAsync)
    }

    private func zoom(into id: String) {
        guard let newPath = Self.zoomTarget(into: id, graph: graph) else { return }
        zoom(to: newPath)
    }

    nonisolated static func zoomTarget(into id: String, graph: PRGraph) -> [String]? {
        guard !graph.parts(inside: id).isEmpty else { return nil }
        return graph.ancestry(of: id).map(\.id)
    }

    private func zoom(to newPath: [String]) {
        withAnimation(.easeInOut(duration: 0.2)) {
            let newSelection = Self.selectionAfterZoom(from: path, to: newPath, graph: graph)
            path = newPath
            selection = newSelection
        }
    }

    nonisolated static func selectionAfterZoom(from oldPath: [String], to newPath: [String], graph: PRGraph)
        -> ArchAnchor?
    {
        guard let previousFocus = oldPath.last else { return nil }
        let newLevel = graph.architectureLevel(path: newPath)
        return newLevel.contains(previousFocus) ? .node(previousFocus) : nil
    }

    private func reveal(_ anchor: ArchAnchor) {
        guard let target = Self.revealTarget(anchor, graph: graph) else { return }
        path = target.path
        selection = target.selection
    }

    nonisolated static func revealTarget(_ anchor: ArchAnchor, graph: PRGraph) -> (
        path: [String], selection: ArchAnchor
    )? {
        switch anchor {
        case .node(let id):
            guard let part = graph.drawablePart(for: id) else { return nil }
            return (graph.architecturePath(showing: part.id), .node(part.id))
        case .edge(let id):
            guard let edge = graph.resolvedEdges.first(where: { $0.id == id }) else { return nil }
            let candidates =
                [[]]
                + graph.ancestry(of: edge.fromId).dropLast().indices.map { i in
                    Array(graph.ancestry(of: edge.fromId).prefix(i + 1).map(\.id))
                }
            for candidate in candidates {
                let level = graph.architectureLevel(path: candidate)
                if let drawn = level.edges.first(where: { $0.id == id || $0.mergedIds.contains(id) }) {
                    return (candidate, .edge(drawn.id))
                }
            }
            return nil
        }
    }

    private func dropHiddenSelection() {
        selection = Self.selectionAfterHidingCheck(selection, level: level, graph: graph, mode: mode)
    }

    nonisolated static func selectionAfterHidingCheck(
        _ selection: ArchAnchor?, level: ArchLevel, graph: PRGraph, mode: DiagramMode
    ) -> ArchAnchor? {
        guard let selection else { return nil }
        let boxes = Set(Self.boxes(level, graph: graph, mode: mode).map(\.id))
        let arrows = Set(Self.arrows(level, graph: graph, mode: mode).map(\.id))
        switch selection {
        case .node(let id) where !boxes.contains(id): return nil
        case .edge(let id) where !arrows.contains(id): return nil
        default: return selection
        }
    }

    private func publishFocus() {
        actions.focus(Self.focusSubject(selection: selection, path: path))
    }

    nonisolated static func focusSubject(selection: ArchAnchor?, path: [String]) -> ReviewSubject? {
        switch selection {
        case .node(let id): return .component(id)
        case .edge(let id): return .relationship(id)
        case nil: return path.last.map { .component($0) }
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
