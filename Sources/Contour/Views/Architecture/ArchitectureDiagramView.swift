import SwiftUI

/// Which snapshot the diagram is showing. Delta is the default — it draws enough existing
/// architecture for context but pushes the reviewer's eye to what this PR changed.
enum ArchMode: String, CaseIterable, Identifiable {
    case before, after, delta
    var id: String { rawValue }
    var label: String {
        switch self {
        case .before: return "Before"
        case .after: return "After"
        case .delta: return "Delta"
        }
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

/// The native architecture diagram (§4.3). Directional, labeled edges are the primary
/// content: line style encodes synchronous (solid) vs asynchronous (dashed), weight/color
/// encodes the change kind so a newly-introduced interaction reads as the delta, and a
/// dashed orange treatment marks trust-boundary crossings. Boundaries render as containers
/// behind their members. Canvas draws connectors/arrowheads/labels; transparent overlays
/// give real per-node and per-edge hit-testing (this is not a static image or web render).
struct ArchitectureDiagramView: View {
    let components: [ComponentNode]
    let edges: [ArchitectureEdge]
    let boundaries: [SystemBoundary]
    let mode: ArchMode
    var selectedNodeId: String?
    var selectedEdgeId: String?
    var onSelectNode: (ComponentNode) -> Void
    var onSelectEdge: (ArchitectureEdge) -> Void

    @State private var hoveredId: String?

    var body: some View {
        let layout = GraphLayoutEngine.layout(components: components, edges: edges, boundaries: boundaries)
        let trustNodeIds = trustBoundaryNodeIds(from: layout.edges)

        ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                ForEach(layout.boundaries) { boundaryBox($0) }

                Canvas { context, _ in
                    for placed in layout.edges { drawEdge(placed, in: &context) }
                }
                .frame(width: layout.size.width, height: layout.size.height)
                .allowsHitTesting(false)

                ForEach(layout.nodes) { placed in
                    nodeBox(placed.component, onTrustBoundary: trustNodeIds.contains(placed.component.id))
                        .frame(width: placed.frame.width, height: placed.frame.height)
                        .position(x: placed.frame.midX, y: placed.frame.midY)
                        .onTapGesture { onSelectNode(placed.component) }
                        .onHover { hoveredId = $0 ? placed.component.id : nil }
                }

                // Edge labels double as hit targets — tapping one selects the relationship.
                // Drawn last (on top of node boxes): each label is width-capped to the
                // column gap it lives in, so it shouldn't physically reach a node box, but
                // if anything ever does overlap, the label must win, never get clipped
                // behind an opaque box the way an unlabeled connector would.
                ForEach(layout.edges) { placed in
                    edgeLabel(placed)
                        .position(placed.labelPoint)
                        .onTapGesture { onSelectEdge(placed.edge) }
                }
            }
            .frame(width: layout.size.width, height: layout.size.height)
            .padding(20)
            // Pin content to the top-leading corner explicitly — a diagram smaller than
            // the available pane must never appear vertically centered with dead space
            // above it; it should read top-down like the rest of the app.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .overlay(alignment: .bottomLeading) { legend }
    }

    // MARK: - Edges

    private func drawEdge(_ placed: ArchDiagramLayout.PlacedEdge, in context: inout GraphicsContext) {
        let e = placed.edge
        let dim = shouldFade(edgeChange: e.change)
        let baseColor = e.isTrustBoundary ? Color.orange : e.change.color
        let color = baseColor.opacity(dim ? 0.28 : (e.change == .existing ? 0.55 : 0.95))

        var path = Path()
        path.move(to: placed.from)
        if let via = placed.via {
            // Routed edge: rise into the reserved skip lane close to the source, travel
            // flat at that height clear of every row in between (the whole point — a
            // midpoint-only arc can still dip back down over an intervening column if that
            // column happens to share the target's row), then only descend once we're in
            // the final gap immediately before the target column.
            let span = placed.to.x - placed.from.x
            let legLength = max(1, min(40, span * 0.25))
            let riseX = placed.from.x + legLength
            let descendX = max(riseX, placed.to.x - legLength)
            let apexY = via.y
            path.addCurve(to: CGPoint(x: riseX, y: apexY),
                          control1: CGPoint(x: placed.from.x + legLength * 0.4, y: placed.from.y),
                          control2: CGPoint(x: riseX, y: apexY))
            if descendX > riseX {
                path.addLine(to: CGPoint(x: descendX, y: apexY))
            }
            path.addCurve(to: placed.to,
                          control1: CGPoint(x: descendX, y: apexY),
                          control2: CGPoint(x: placed.to.x - legLength * 0.4, y: placed.to.y))
        } else {
            let midX = (placed.from.x + placed.to.x) / 2
            path.addCurve(to: placed.to,
                          control1: CGPoint(x: midX, y: placed.from.y),
                          control2: CGPoint(x: midX, y: placed.to.y))
        }

        var dash: [CGFloat] = []
        if e.flow == .async { dash = [6, 4] }
        if e.change == .removed { dash = [3, 3] }
        if e.isTrustBoundary && dash.isEmpty { dash = [5, 4] }

        context.stroke(path, with: .color(color),
                       style: StrokeStyle(lineWidth: edgeWidth(e), lineCap: .round, dash: dash))

        // Heavy "new critical path" edges get a second, translucent underlay so they read
        // as the thickest thing on the canvas without a solid slab.
        if e.change == .new && e.onCriticalPath {
            context.stroke(path, with: .color(color.opacity(0.25)),
                           style: StrokeStyle(lineWidth: edgeWidth(e) + 5, lineCap: .round))
        }

        // Arrowhead at the target.
        let angle = atan2(placed.to.y - placed.from.y, placed.to.x - placed.from.x)
        let tip = placed.to
        let size: CGFloat = e.change == .new ? 11 : 9
        let back = CGPoint(x: tip.x - size * cos(angle), y: tip.y - size * sin(angle))
        var arrow = Path()
        arrow.move(to: tip)
        arrow.addLine(to: CGPoint(x: back.x - size * 0.5 * sin(angle), y: back.y + size * 0.5 * cos(angle)))
        arrow.addLine(to: CGPoint(x: back.x + size * 0.5 * sin(angle), y: back.y - size * 0.5 * cos(angle)))
        arrow.closeSubpath()
        context.fill(arrow, with: .color(color))
    }

    private func edgeWidth(_ e: ArchitectureEdge) -> CGFloat {
        switch e.change {
        case .new: return e.onCriticalPath ? 3.4 : 2.4
        case .changed: return 2.0
        case .existing: return 1.2
        case .removed: return 1.4
        }
    }

    @ViewBuilder
    private func edgeLabel(_ placed: ArchDiagramLayout.PlacedEdge) -> some View {
        let e = placed.edge
        let dim = shouldFade(edgeChange: e.change)
        let selected = selectedEdgeId == e.id
        VStack(spacing: 1) {
            HStack(spacing: 3) {
                if e.flow == .async {
                    Image(systemName: "clock.arrow.circlepath").font(.system(size: 8))
                }
                if e.isTrustBoundary {
                    Image(systemName: "lock.shield").font(.system(size: 8)).foregroundStyle(.orange)
                }
                Text(e.label.isEmpty ? "relates to" : e.label)
                    .font(.caption2.weight(e.change == .new ? .bold : .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if e.change == .removed {
                    Text("removed").font(.system(size: 8).weight(.bold)).foregroundStyle(.red)
                }
                // The full note / critical-path callout lives in the inspector, not on the
                // canvas — a small warning glyph is enough of a hint here to stay legible.
                if e.onCriticalPath && e.change == .new {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 8)).foregroundStyle(.orange)
                }
            }
        }
        .padding(.horizontal, 5).padding(.vertical, 2)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5))
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(selected ? Color.accentColor : (e.change == .new ? e.change.color.opacity(0.7) : Color.secondary.opacity(0.25)),
                              lineWidth: selected ? 1.6 : (e.change == .new ? 1.2 : 0.8))
        )
        .opacity(dim ? 0.5 : 1)
        // Capped, not `.fixedSize()`: a label wider than the column gap it lives in must
        // truncate rather than spill into a neighboring node's box — the full text (plus
        // any note) is always available via the tooltip and, when selected, the detail
        // panel below the diagram.
        .frame(maxWidth: GraphLayoutEngine.hGap - 24)
        .help(e.note?.isEmpty == false ? "\(e.label) — \(e.note!)" : e.label)
    }

    // MARK: - Nodes

    private func nodeBox(_ c: ComponentNode, onTrustBoundary: Bool) -> some View {
        let dim = shouldFade(nodeChange: c.changeKind)
        let emphasized = c.changeKind == .new || c.changeKind == .changed
        let selected = selectedNodeId == c.id
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(c.title)
                    .font(.system(.callout, weight: emphasized ? .semibold : .regular))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            HStack(spacing: 6) {
                ChangeKindBadge(kind: c.changeKind)
                if onTrustBoundary {
                    Image(systemName: "lock.shield").font(.caption2).foregroundStyle(.orange)
                }
                if !c.implementedBy.isEmpty {
                    Text("\(c.implementedBy.count) impl").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(nodeBorderColor(c, selected: selected),
                              lineWidth: selected ? 2.4 : (c.changeKind == .new ? 2 : (c.changeKind == .changed ? 1.6 : 1)))
        )
        .opacity(dim ? 0.5 : 1)
        .shadow(color: .black.opacity(hoveredId == c.id ? 0.18 : 0.06), radius: hoveredId == c.id ? 6 : 2, y: 1)
        .scaleEffect(hoveredId == c.id ? 1.02 : 1.0)
        .animation(.easeOut(duration: 0.12), value: hoveredId)
        .contentShape(Rectangle())
    }

    private func nodeBorderColor(_ c: ComponentNode, selected: Bool) -> Color {
        if selected { return .accentColor }
        switch c.changeKind {
        case .new: return .green
        case .changed: return .blue
        default: return .secondary.opacity(0.4)
        }
    }

    // MARK: - Boundaries

    private func boundaryBox(_ placed: ArchDiagramLayout.PlacedBoundary) -> some View {
        let b = placed.boundary
        let isTrust = b.kind == .trust
        let isExternal = b.kind == .external || b.kind == .trust
        let stroke = isTrust ? Color.orange : (isExternal ? Color.purple : Color.secondary)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12)
                .fill(stroke.opacity(0.045))
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(stroke.opacity(isExternal ? 0.6 : 0.4),
                              style: StrokeStyle(lineWidth: 1.2, dash: isExternal ? [6, 4] : []))
            HStack(spacing: 4) {
                Image(systemName: boundaryGlyph(b.kind)).font(.caption2)
                Text(b.label.uppercased()).font(.caption2.weight(.bold)).tracking(0.5)
            }
            .foregroundStyle(stroke)
            .padding(.horizontal, 8).padding(.vertical, 3)
        }
        .frame(width: placed.frame.width, height: placed.frame.height)
        .position(x: placed.frame.midX, y: placed.frame.midY)
        .allowsHitTesting(false)
    }

    private func boundaryGlyph(_ kind: BoundaryKind) -> String {
        switch kind {
        case .application: return "square.dashed"
        case .process: return "cpu"
        case .service: return "server.rack"
        case .datastore: return "cylinder.split.1x2"
        case .external: return "globe"
        case .trust: return "lock.shield"
        case .network: return "network"
        case .asyncBoundary: return "clock.arrow.circlepath"
        }
    }

    // MARK: - Helpers

    /// Fading only happens in Delta — Before/After are coherent snapshots shown at full
    /// strength. In Delta, unchanged context recedes so the eye goes to the change.
    private func shouldFade(nodeChange: ChangeKind) -> Bool {
        mode == .delta && (nodeChange == .unchanged || nodeChange == .touched)
    }
    private func shouldFade(edgeChange: EdgeChange) -> Bool {
        mode == .delta && edgeChange == .existing
    }

    private func trustBoundaryNodeIds(from edges: [ArchDiagramLayout.PlacedEdge]) -> Set<String> {
        var ids: Set<String> = []
        for placed in edges where placed.edge.isTrustBoundary {
            ids.insert(placed.edge.fromId); ids.insert(placed.edge.toId)
        }
        return ids
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 12) {
                legendLine(color: .green, width: 2.6, dash: [], label: "New relationship")
                legendLine(color: .blue, width: 2, dash: [], label: "Changed")
                legendLine(color: .secondary, width: 1.2, dash: [], label: "Existing context")
            }
            HStack(spacing: 12) {
                legendLine(color: .secondary, width: 1.6, dash: [6, 4], label: "Asynchronous / queued")
                legendLine(color: .orange, width: 1.6, dash: [5, 4], label: "Trust boundary")
                legendLine(color: .red, width: 1.4, dash: [3, 3], label: "Removed")
            }
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .padding(10)
    }

    private func legendLine(color: Color, width: CGFloat, dash: [CGFloat], label: String) -> some View {
        HStack(spacing: 5) {
            Canvas { ctx, size in
                var p = Path()
                p.move(to: CGPoint(x: 0, y: size.height / 2))
                p.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: width, dash: dash))
            }
            .frame(width: 22, height: 8)
            Text(label).font(.caption2)
        }
    }
}
