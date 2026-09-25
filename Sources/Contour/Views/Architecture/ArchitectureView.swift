import SwiftUI

/// The Architecture lens, redesigned (§4.3) to answer "how does this change fit into the
/// system, and how does behavior move through it" rather than "which class calls which".
///
/// The diagram is a deliberately laid-out, left-to-right story of directional, labeled
/// relationships. Two pieces of chrome drive it: a Before / After / Delta mode (Delta is
/// the default — it shows enough context but emphasizes the architectural change) and a
/// System / Implementation zoom (System shows conceptual responsibilities; Implementation
/// reveals the real classes). Selecting a node or an edge fills the inspector, and an
/// edge's embodied decisions link straight into the Decisions lens.
struct ArchitectureView: View {
    let graph: PRGraph
    var onOpenEvidence: (CodeRef) -> Void
    var onOpenDecision: (String) -> Void

    enum Selection: Equatable {
        case node(String)
        case edge(String)
        case none
    }

    @State private var selection: Selection = .none
    @State private var mode: ArchMode = .delta
    @State private var zoom: AbstractionLevel = .system

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            controls
            if let impact = graph.pr.architectureImpact {
                StatementView(statement: impact)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
            HSplitView {
                ArchitectureDiagramView(
                    components: visibleComponents,
                    edges: visibleEdges,
                    boundaries: graph.boundaries,
                    mode: mode,
                    selectedNodeId: selectedNodeId,
                    selectedEdgeId: selectedEdgeId,
                    onSelectNode: { selection = .node($0.id) },
                    onSelectEdge: { selection = .edge($0.id) }
                )
                .frame(minWidth: 420, minHeight: 300)

                inspector
                    .frame(minWidth: 300, idealWidth: 340)
            }
        }
        .onAppear { if selection == .none { selection = defaultSelection } }
        .onChange(of: mode) { _, _ in reconcileSelection() }
        .onChange(of: zoom) { _, _ in reconcileSelection() }
    }

    // MARK: - Chrome

    private var controls: some View {
        HStack(spacing: 16) {
            labeledPicker("View") {
                Picker("View", selection: $mode) {
                    ForEach(ArchMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented).frame(width: 220).labelsHidden()
            }
            labeledPicker("Zoom") {
                Picker("Zoom", selection: $zoom) {
                    Text("System").tag(AbstractionLevel.system)
                    Text("Implementation").tag(AbstractionLevel.implementation)
                }
                .pickerStyle(.segmented).frame(width: 220).labelsHidden()
            }
            Spacer()
        }
        .padding(12)
    }

    private func labeledPicker<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            content()
        }
    }

    // MARK: - Visible subset

    private var visibleComponents: [ComponentNode] {
        graph.components.filter { c in
            guard c.level <= zoom else { return false }
            if mode == .before && c.changeKind == .new { return false }
            return true
        }
    }

    private var visibleEdges: [ArchitectureEdge] {
        let ids = Set(visibleComponents.map(\.id))
        return graph.resolvedEdges.filter { e in
            guard ids.contains(e.fromId), ids.contains(e.toId) else { return false }
            switch mode {
            case .before: return e.presence != .after
            case .after: return e.presence != .before
            case .delta: return true
            }
        }
    }

    // MARK: - Selection plumbing

    private var selectedNodeId: String? {
        if case let .node(id) = selection { return id }
        return nil
    }
    private var selectedEdgeId: String? {
        if case let .edge(id) = selection { return id }
        return nil
    }

    /// Open on the hero of the change: the source of the most prominent new critical-path
    /// edge, else any new/changed node, else the first visible node.
    private var defaultSelection: Selection {
        if let heroEdge = visibleEdges.first(where: { $0.change == .new && $0.onCriticalPath })
            ?? visibleEdges.first(where: { $0.change == .new }) {
            return .edge(heroEdge.id)
        }
        if let changed = visibleComponents.first(where: { $0.changeKind == .new || $0.changeKind == .changed }) {
            return .node(changed.id)
        }
        return visibleComponents.first.map { .node($0.id) } ?? .none
    }

    /// When mode/zoom hides the current selection, fall back to a sensible default.
    private func reconcileSelection() {
        switch selection {
        case let .node(id) where !visibleComponents.contains(where: { $0.id == id }):
            selection = defaultSelection
        case let .edge(id) where !visibleEdges.contains(where: { $0.id == id }):
            selection = defaultSelection
        case .none:
            selection = defaultSelection
        default:
            break
        }
    }

    // MARK: - Inspector

    @ViewBuilder
    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                switch selection {
                case let .node(id):
                    if let node = graph.component(id) { nodeInspector(node) }
                case let .edge(id):
                    if let edge = visibleEdges.first(where: { $0.id == id }) ?? graph.resolvedEdges.first(where: { $0.id == id }) {
                        edgeInspector(edge)
                    }
                case .none:
                    Text("Select a node or a relationship to inspect it.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Node inspector

    @ViewBuilder
    private func nodeInspector(_ node: ComponentNode) -> some View {
        inspectorHeader(kind: node.level.label, title: node.title)

        if let purpose = node.summary {
            field("RESPONSIBILITY") { StatementView(statement: purpose) }
        }

        field("CHANGED BY THIS PR") {
            HStack(spacing: 6) {
                let changed = node.changeKind == .new || node.changeKind == .changed
                Image(systemName: changed ? "checkmark.circle.fill" : "minus.circle")
                    .foregroundStyle(changed ? .green : .secondary)
                ChangeKindBadge(kind: node.changeKind)
            }
        }

        let incoming = edges(into: node.id)
        if !incoming.isEmpty {
            field("TRIGGERED BY") { relationshipList(incoming, endpoint: \.fromId, prefix: "") }
        }
        let outgoing = edges(from: node.id)
        if !outgoing.isEmpty {
            field("TRIGGERS") { relationshipList(outgoing, endpoint: \.toId, prefix: "") }
        }

        let decisions = graph.decisions(affecting: node.id)
        if !decisions.isEmpty {
            field("REVIEW DECISIONS") { decisionButtons(decisions) }
        }

        if !node.implementedBy.isEmpty {
            field("IMPLEMENTED BY") {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(node.implementedBy, id: \.self) { name in
                        Text(name).font(.system(.callout, design: .monospaced))
                    }
                    if zoom == .system, !graph.implementationComponents(for: node.id).isEmpty {
                        Button("Zoom to implementation") { zoom = .implementation }
                            .buttonStyle(.link).font(.caption)
                    }
                }
            }
        }

        if !node.refs.isEmpty {
            field("EVIDENCE") {
                WrapChips(node.refs) { ref in CodeRefChip(ref: ref) { onOpenEvidence(ref) } }
            }
        }
    }

    // MARK: Edge inspector

    @ViewBuilder
    private func edgeInspector(_ edge: ArchitectureEdge) -> some View {
        let from = graph.component(edge.fromId)
        let to = graph.component(edge.toId)
        inspectorHeader(kind: "Relationship", title: edge.label.isEmpty ? "relates to" : edge.label)

        field("DIRECTION") {
            HStack(spacing: 6) {
                Text(from?.title ?? edge.fromId).font(.callout.weight(.medium))
                Image(systemName: "arrow.right").font(.caption).foregroundStyle(edge.change.color)
                Text(to?.title ?? edge.toId).font(.callout.weight(.medium))
            }
            .fixedSize(horizontal: false, vertical: true)
        }

        field("KIND") {
            HStack(spacing: 8) {
                pill(edge.change == .new ? "New relationship"
                     : edge.change == .changed ? "Changed"
                     : edge.change == .removed ? "Removed" : "Existing",
                     color: edge.change.color)
                pill(edge.flow == .async ? "Asynchronous" : "Synchronous",
                     color: edge.flow == .async ? .secondary : .primary)
                if edge.isTrustBoundary { pill("Trust boundary", color: .orange, glyph: "lock.shield") }
            }
        }

        if edge.onCriticalPath {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(edge.change == .new ? "New work on a critical path" : "On a critical path")
                    .font(.callout.weight(.semibold))
            }
        }

        if let note = edge.note, !note.isEmpty {
            field("NOTE") { Text(note).font(.callout) }
        }

        let decisions = graph.decisions(forEdge: edge)
        if !decisions.isEmpty {
            field("REVIEW DECISION") { decisionButtons(decisions) }
        } else {
            Text("No decision is linked to this relationship yet.")
                .font(.caption).foregroundStyle(.secondary)
        }

        HStack {
            if let from { Button("Inspect \(from.title)") { selection = .node(from.id) }.buttonStyle(.link).font(.caption) }
            if let to { Button("Inspect \(to.title)") { selection = .node(to.id) }.buttonStyle(.link).font(.caption) }
        }
    }

    // MARK: Inspector building blocks

    private func inspectorHeader(kind: String, title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(kind.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Text(title).font(.title3.weight(.semibold))
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption2.weight(.bold)).foregroundStyle(.secondary).tracking(0.5)
            content()
        }
    }

    private func relationshipList(_ edges: [ArchitectureEdge], endpoint: KeyPath<ArchitectureEdge, String>, prefix: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(edges) { e in
                Button { selection = .edge(e.id) } label: {
                    HStack(spacing: 5) {
                        if e.change == .new { Circle().fill(Color.green).frame(width: 6, height: 6) }
                        Text(e.label).font(.callout.weight(e.change == .new ? .semibold : .regular))
                        Text(graph.component(e[keyPath: endpoint])?.title ?? e[keyPath: endpoint])
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func decisionButtons(_ decisions: [DecisionNode]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(decisions) { d in
                Button { onOpenDecision(d.id) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.bubble").foregroundStyle(.orange)
                        Text(d.title).font(.callout).multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func pill(_ text: String, color: Color, glyph: String? = nil) -> some View {
        HStack(spacing: 3) {
            if let glyph { Image(systemName: glyph).font(.caption2) }
            Text(text).font(.caption2.weight(.medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(color.opacity(0.12), in: Capsule())
    }

    // MARK: Edge queries

    private func edges(from id: String) -> [ArchitectureEdge] { visibleEdges.filter { $0.fromId == id } }
    private func edges(into id: String) -> [ArchitectureEdge] { visibleEdges.filter { $0.toId == id } }
}
