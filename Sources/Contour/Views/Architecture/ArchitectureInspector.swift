import SwiftUI

struct ArchitectureInspector: View {
    let graph: PRGraph
    let level: ArchLevel
    let anchor: ArchAnchor
    var onSelect: (ArchAnchor) -> Void
    var onZoomIn: (String) -> Void
    var onClose: () -> Void

    @Environment(\.reviewActions) private var actions

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                switch anchor {
                case .node(let id):
                    if let part = graph.component(id) { partDetail(part) }
                case .edge(let id):
                    if let drawn = level.edges.first(where: { $0.id == id }) { relationshipDetail(drawn) }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func partDetail(_ part: ComponentNode) -> some View {
        header(eyebrow: Self.eyebrow(for: part, in: graph), title: part.title, subject: .component(part.id))

        if let purpose = part.summary {
            section("Purpose") { statement(purpose) }
        }

        section("This PR") {
            if let summary = part.delta?.summary {
                statement(summary)
            }
            if let before = part.delta?.before, let after = part.delta?.after {
                beforeAfter(before, after)
            }
            if Self.showsUnchangedNote(part) {
                Text(Self.unchangedLine(part)).font(.callout).foregroundStyle(.secondary)
            }
        }

        let inside = graph.parts(inside: part.id)
        if !inside.isEmpty {
            section("Inside") {
                ForEach(inside) { child in
                    HStack(spacing: 6) {
                        changeDot(child.changeKind)
                        Text(child.title).font(.callout)
                        Spacer(minLength: 0)
                    }
                }
                if level.focus?.id != part.id {
                    Button {
                        onZoomIn(part.id)
                    } label: {
                        Label("Look inside \(part.title)", systemImage: "plus.magnifyingglass")
                    }
                    .buttonStyle(.link).font(.callout)
                }
            }
        }

        let incoming = level.edges.filter { $0.toId == part.id }
        let outgoing = level.edges.filter { $0.fromId == part.id }
        if !incoming.isEmpty || !outgoing.isEmpty {
            section("Connections") {
                ForEach(incoming) { e in connectionRow(e, direction: "from", other: e.fromId) }
                ForEach(outgoing) { e in connectionRow(e, direction: "to", other: e.toId) }
            }
        }

        questions(graph.questionAnchors(on: level)[.node(part.id)] ?? [])
        decisions(graph.decisions(within: part.id))
        flows(graph.flows(through: part.id))
        implementation(part)
        askButton(.component(part.id))
    }

    nonisolated static func eyebrow(for part: ComponentNode, in graph: PRGraph) -> String {
        let kind = part.parentId.flatMap(graph.component).map { "Part of \($0.title)" } ?? "Part"
        switch part.changeKind {
        case .new: return "\(kind) · New"
        case .changed: return "\(kind) · Changed"
        case .removed: return "\(kind) · Removed"
        case .touched, .unchanged: return kind
        }
    }

    nonisolated static func unchangedLine(_ part: ComponentNode) -> String {
        switch part.changeKind {
        case .new: return "Added by this PR."
        case .removed: return "Removed by this PR."
        case .changed: return "Changed by this PR."
        case .touched, .unchanged: return "Not changed by this PR — drawn for context."
        }
    }

    nonisolated static func showsUnchangedNote(_ part: ComponentNode) -> Bool {
        part.delta?.summary == nil && (part.delta?.before == nil || part.delta?.after == nil)
    }

    nonisolated static func connectionIcon(direction: String) -> String {
        direction == "from" ? "arrow.down.right" : "arrow.up.right"
    }

    nonisolated static func connectionLabel(_ edge: ArchitectureEdge) -> String {
        edge.label.isEmpty ? "—" : edge.label
    }

    nonisolated static func connectionLabelWeight(_ change: EdgeChange) -> Font.Weight {
        change == .existing ? .regular : .semibold
    }

    nonisolated static func connectionLabelColor(_ change: EdgeChange) -> Color {
        change == .existing ? Color.primary : change.color
    }

    nonisolated static func connectionCaption(direction: String, otherTitle: String) -> String {
        "\(direction) \(otherTitle)"
    }

    private func connectionRow(_ e: ArchLevelEdge, direction: String, other: String) -> some View {
        Button {
            onSelect(.edge(e.id))
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: Self.connectionIcon(direction: direction))
                    .font(.caption2).foregroundStyle(.secondary)
                Text(Self.connectionLabel(e.edge))
                    .font(.callout.weight(Self.connectionLabelWeight(e.edge.change)))
                    .foregroundStyle(Self.connectionLabelColor(e.edge.change))
                Text(Self.connectionCaption(direction: direction, otherTitle: graph.component(other)?.title ?? other))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .reviewContextMenu(.relationship(e.id))
    }

    @ViewBuilder
    private func relationshipDetail(_ drawn: ArchLevelEdge) -> some View {
        let e = drawn.edge
        let from = graph.component(drawn.fromId)?.title ?? drawn.fromId
        let to = graph.component(drawn.toId)?.title ?? drawn.toId
        header(eyebrow: Self.relationshipEyebrow(e.change), title: "\(from) → \(to)", subject: .relationship(e.id))

        section("What crosses it") {
            if let previous = e.previousLabel {
                beforeAfter(previous, e.label)
            } else {
                Text(Self.crossesLabel(e)).font(.callout.weight(.medium))
            }
            Text(Self.properties(e)).font(.caption).foregroundStyle(.secondary)
        }

        if let note = Self.relationshipThisPRNote(e) {
            section("This PR") {
                if note.isFallback {
                    Text(note.text).font(.callout).foregroundStyle(.secondary)
                } else {
                    Text(note.text).font(.callout)
                }
            }
        }

        let folded = drawn.mergedIds.compactMap { id in graph.resolvedEdges.first { $0.id == id } }
        if !folded.isEmpty {
            section("Also between these parts") {
                ForEach(folded) { other in
                    Text(
                        Self.foldedEdgeLine(
                            fromTitle: graph.component(other.fromId)?.title ?? other.fromId,
                            toTitle: graph.component(other.toId)?.title ?? other.toId,
                            label: other.label)
                    )
                    .font(.callout).foregroundStyle(.secondary)
                    .reviewContextMenu(.relationship(other.id))
                }
            }
        }

        questions(graph.questionAnchors(on: level)[.edge(e.id)] ?? [])
        let anchored = graph.decisionAnchors(on: level)[.edge(e.id)] ?? []
        decisions(unique(anchored + graph.decisions(forEdge: e)))
        flows(Self.sharedFlows(graph.flows(through: drawn.fromId), graph.flows(through: drawn.toId)))

        HStack(spacing: 14) {
            Button("Inspect \(from)") { onSelect(.node(drawn.fromId)) }
            Button("Inspect \(to)") { onSelect(.node(drawn.toId)) }
        }
        .buttonStyle(.link).font(.caption)

        askButton(.relationship(e.id))
    }

    nonisolated static func properties(_ e: ArchitectureEdge) -> String {
        var parts = [e.flow == .async ? "Asynchronous" : "Synchronous"]
        if e.isTrustBoundary { parts.append("crosses a trust boundary") }
        if e.onCriticalPath { parts.append("on a critical path") }
        return parts.joined(separator: " · ")
    }

    nonisolated static func relationshipEyebrow(_ change: EdgeChange) -> String {
        "Relationship" + (change == .existing ? "" : " · \(changeWord(change))")
    }

    nonisolated static func crossesLabel(_ e: ArchitectureEdge) -> String {
        e.label.isEmpty ? "Not labeled" : e.label
    }

    nonisolated static func relationshipThisPRNote(_ e: ArchitectureEdge) -> (text: String, isFallback: Bool)? {
        if let note = e.note, !note.isEmpty { return (note, false) }
        if e.change == .existing { return ("Not changed by this PR — drawn for context.", true) }
        return nil
    }

    nonisolated static func foldedEdgeLine(fromTitle: String, toTitle: String, label: String) -> String {
        "\(fromTitle) → \(toTitle): \(label)"
    }

    nonisolated static func sharedFlows(_ fromFlows: [FlowNode], _ toFlows: [FlowNode]) -> [FlowNode] {
        let fromIds = Set(fromFlows.map(\.id))
        return toFlows.filter { fromIds.contains($0.id) }
    }

    nonisolated static func changeWord(_ change: EdgeChange) -> String {
        switch change {
        case .new: return "New"
        case .changed: return "Changed"
        case .existing: return "Existing"
        case .removed: return "Removed"
        }
    }

    @ViewBuilder
    private func questions(_ items: [Consideration]) -> some View {
        if !items.isEmpty {
            section("Review questions") {
                ForEach(items) { item in
                    linkRow(icon: "exclamationmark.triangle.fill", tint: .orange, text: item.question) {
                        actions.navigate(.consideration(item.id))
                    }
                    .reviewContextMenu(.consideration(item.id))
                }
            }
        }
    }

    @ViewBuilder
    private func decisions(_ items: [DecisionNode]) -> some View {
        if !items.isEmpty {
            section("Related decisions") {
                ForEach(items.prefix(5)) { d in
                    linkRow(icon: "diamond", tint: .purple, text: graph.brief(for: d).question) {
                        actions.navigate(.decisionDetail(d.id))
                    }
                    .reviewContextMenu(.decision(d.id))
                }
            }
        }
    }

    @ViewBuilder
    private func flows(_ items: [FlowNode]) -> some View {
        if !items.isEmpty {
            section("Flows through this") {
                ForEach(items) { f in
                    linkRow(icon: "arrow.triangle.branch", tint: .secondary, text: f.title) {
                        actions.navigate(.flowDetail(f.id))
                    }
                    .reviewContextMenu(.flow(f.id))
                }
            }
        }
    }

    nonisolated static func implementationCountLabel(nodeCount: Int, nameCount: Int) -> String? {
        let count = nodeCount + nameCount
        guard count > 0 else { return nil }
        return "\(count) implementation \(count == 1 ? "component" : "components")"
    }

    nonisolated static func mergedRefs(partRefs: [CodeRef], implRefs: [CodeRef]) -> [CodeRef] {
        unique(partRefs + implRefs)
    }

    @ViewBuilder
    private func implementation(_ part: ComponentNode) -> some View {
        let impl = graph.implementation(of: part.id)
        let countLabel = Self.implementationCountLabel(nodeCount: impl.nodes.count, nameCount: impl.names.count)
        let refs = Self.mergedRefs(partRefs: part.refs, implRefs: impl.nodes.flatMap(\.refs))
        if countLabel != nil || !refs.isEmpty {
            section("Implementation") {
                if let countLabel {
                    Text(countLabel)
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(impl.nodes) { node in
                    HStack(spacing: 6) {
                        Text(node.title).font(.system(.callout, design: .monospaced))
                        Spacer(minLength: 0)
                        if let ref = node.refs.first {
                            Button("Code") { actions.navigate(.evidence(ref)) }.buttonStyle(.link).font(.caption)
                        }
                    }
                    .reviewContextMenu(.component(node.id))
                }
                ForEach(impl.names, id: \.self) { name in
                    Text(name).font(.system(.callout, design: .monospaced))
                }
                if !refs.isEmpty {
                    WrapChips(Array(refs.prefix(8))) { ref in CodeRefChip(ref: ref) { actions.navigate(.evidence(ref)) }
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

    private func header(eyebrow: String, title: String, subject: ReviewSubject) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(eyebrow.uppercased())
                    .font(.caption2.weight(.semibold)).tracking(0.5).foregroundStyle(.secondary)
                Text(title).font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button(action: onClose) { Image(systemName: "xmark").font(.caption.weight(.semibold)) }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Close (Esc)")
                .keyboardShortcut(.cancelAction)
        }
        .contentShape(Rectangle())
        .reviewContextMenu(subject)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold)).tracking(0.5).foregroundStyle(.secondary)
            content()
        }
    }

    private func statement(_ s: Statement) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(s.text).font(.callout).fixedSize(horizontal: false, vertical: true)
            ProvenanceMark(provenance: s.provenance, confidence: s.confidence, source: s.source)
        }
    }

    private func beforeAfter(_ before: String, _ after: String) -> some View {
        (Text(before).foregroundStyle(.secondary).strikethrough(true, color: .secondary)
            + Text("  →  ").foregroundStyle(.tertiary)
            + Text(after).fontWeight(.semibold))
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func changeDot(_ kind: ChangeKind) -> some View {
        Circle()
            .fill(kind == .unchanged || kind == .touched ? Color.secondary.opacity(0.4) : kind.color)
            .frame(width: 7, height: 7)
    }

    private func linkRow(icon: String, tint: Color, text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Image(systemName: icon).font(.caption).foregroundStyle(tint)
                Text(text).font(.callout).multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func askButton(_ subject: ReviewSubject) -> some View {
        Button {
            actions.ask(subject)
        } label: {
            Label("Ask about this…", systemImage: "sparkles")
        }
        .controlSize(.regular)
        .help("Ask about this… (⌘⇧A)")
        .padding(.top, 4)
    }
}

extension EdgeChange {
    var color: Color {
        switch self {
        case .new: return .green
        case .changed: return .blue
        case .existing: return .secondary
        case .removed: return .red
        }
    }
}
