import SwiftUI

extension FlowChange {
    var color: Color {
        switch self {
        case .new: return .green
        case .changed: return .blue
        case .existing: return .secondary
        case .removed: return .red
        }
    }
    var tag: String? {
        switch self {
        case .new: return "NEW"
        case .changed: return "CHANGED"
        case .removed: return "REMOVED"
        case .existing: return nil
        }
    }
}

extension FlowAnnotation.Kind {
    var color: Color { self == .decision ? .teal : .orange }
    var symbol: String { self == .decision ? "diamond" : "exclamationmark.triangle.fill" }
    var caption: String { self == .decision ? "DECISION" : "REVIEW QUESTION" }
}

/// A flow drawn as runtime behavior (§4.6): trigger at the top, stages below, branches side by
/// side, notes for decisions and review questions beside the connection they sit on, and
/// boxes around the systems it runs in. In Delta, unchanged stages recede and what the PR
/// changed carries the color; Before and After are coherent snapshots at full strength.
///
/// Canvas draws connectors; stages, labels, and notes are real views so each one is clickable
/// and has the standard right-click menu.
struct BehaviorDiagramView: View {
    let flowId: String
    let behavior: FlowBehavior
    let annotations: [FlowAnnotation]
    let mode: DiagramMode
    var selectedNodeId: String?
    var onSelect: (FlowBehaviorNode) -> Void
    var onDrill: (FlowBehaviorNode) -> Void
    var onShowImplementation: (FlowBehaviorNode) -> Void
    var onOpenAnnotation: (FlowAnnotation) -> Void
    var onOpenSubflow: (String) -> Void
    var subflowTitle: (String) -> String?

    @State private var hoveredId: String?

    var body: some View {
        let layout = BehaviorDiagramLayoutEngine.layout(behavior, mode: mode, annotations: annotations)
        GeometryReader { geo in
            ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .topLeading) {
                    ForEach(layout.boundaries) { boundaryBox($0) }

                    Canvas { context, _ in
                        for placed in layout.edges { drawEdge(placed, in: &context) }
                        for placed in layout.annotations { drawTether(placed, layout: layout, in: &context) }
                    }
                    .frame(width: layout.size.width, height: layout.size.height)
                    .allowsHitTesting(false)

                    ForEach(layout.nodes) { placed in
                        StageBox(node: placed.node, mode: mode, isSelected: selectedNodeId == placed.id,
                                 isHovered: hoveredId == placed.id,
                                 subflowTitle: placed.node.subflowId.flatMap(subflowTitle))
                            .frame(width: placed.frame.width, height: placed.frame.height)
                            .position(x: placed.frame.midX, y: placed.frame.midY)
                            .onTapGesture(count: 2) { onDrill(placed.node) }
                            .onTapGesture { onSelect(placed.node) }
                            .onHover { hoveredId = $0 ? placed.id : (hoveredId == placed.id ? nil : hoveredId) }
                            .reviewContextMenu(.flowNode(flowId: flowId, nodeId: placed.id)) {
                                Button("Show Implementation") { onShowImplementation(placed.node) }
                                if let sub = placed.node.subflowId, let title = subflowTitle(sub) {
                                    Button("Open \u{201C}\(title)\u{201D}") { onOpenSubflow(sub) }
                                }
                            }
                    }

                    ForEach(layout.edges) { placed in
                        if let label = placed.edge.label, let point = placed.labelPoint {
                            branchLabel(label, edge: placed.edge).position(point)
                        }
                    }

                    ForEach(layout.annotations) { placed in
                        AnnotationNote(annotation: placed.annotation) { onOpenAnnotation(placed.annotation) }
                            .frame(width: placed.frame.width, height: placed.frame.height, alignment: .topLeading)
                            .position(x: placed.frame.midX, y: placed.frame.midY)
                            .reviewContextMenu(placed.annotation.kind == .decision
                                               ? .decision(placed.annotation.targetId)
                                               : .consideration(placed.annotation.targetId))
                    }

                    ForEach(layout.overflow) { placed in
                        Button {
                            if let node = layout.node(placed.nodeId)?.node { onSelect(node) }
                        } label: {
                            Text("+\(placed.count) more").font(.caption).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading, 8)
                        }
                        .buttonStyle(.plain)
                        .help("Select the stage to see every decision and question pinned here")
                        .frame(width: placed.frame.width, height: placed.frame.height)
                        .position(x: placed.frame.midX, y: placed.frame.midY)
                    }
                }
                .frame(width: layout.size.width, height: layout.size.height)
                // Room to scroll the last stage clear of the legend floating over the canvas.
                .padding(.bottom, 56)
                // Centered across the canvas when it fits; scrolls when it doesn't.
                .frame(minWidth: geo.size.width, minHeight: geo.size.height, alignment: .top)
            }
        }
        .overlay(alignment: .bottomLeading) { legend }
    }

    // MARK: - Connectors

    private func fades(_ change: FlowChange) -> Bool { mode == .delta && change == .existing }

    private func drawEdge(_ placed: BehaviorDiagramLayout.PlacedEdge, in context: inout GraphicsContext) {
        let e = placed.edge
        guard placed.points.count >= 2 else { return }
        let color = e.change.color.opacity(fades(e.change) ? 0.35 : (e.change == .existing ? 0.6 : 0.95))
        var path = Path()
        path.addLines(placed.points)
        var dash: [CGFloat] = []
        if e.flow == .async { dash = [6, 4] }
        if e.change == .removed { dash = [3, 3] }
        let width: CGFloat = e.change == .existing ? 1.3 : 2.2
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round, dash: dash))

        let tip = placed.points[placed.points.count - 1]
        let from = placed.points[placed.points.count - 2]
        let angle = atan2(tip.y - from.y, tip.x - from.x)
        let size: CGFloat = e.change == .existing ? 8 : 10
        let back = CGPoint(x: tip.x - size * cos(angle), y: tip.y - size * sin(angle))
        var arrow = Path()
        arrow.move(to: tip)
        arrow.addLine(to: CGPoint(x: back.x - size * 0.5 * sin(angle), y: back.y + size * 0.5 * cos(angle)))
        arrow.addLine(to: CGPoint(x: back.x + size * 0.5 * sin(angle), y: back.y - size * 0.5 * cos(angle)))
        arrow.closeSubpath()
        context.fill(arrow, with: .color(color))
    }

    /// A dotted tick from the stage's outgoing connector to its note, so the note reads as
    /// "this happens here".
    private func drawTether(_ placed: BehaviorDiagramLayout.PlacedAnnotation, layout: BehaviorDiagramLayout,
                            in context: inout GraphicsContext) {
        guard let node = layout.node(placed.annotation.nodeId) else { return }
        let y = placed.frame.minY + 10
        var path = Path()
        path.move(to: CGPoint(x: node.frame.midX, y: y))
        path.addLine(to: CGPoint(x: placed.frame.minX, y: y))
        context.stroke(path, with: .color(placed.annotation.kind.color.opacity(0.6)),
                       style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
        context.fill(Path(ellipseIn: CGRect(x: node.frame.midX - 2.5, y: y - 2.5, width: 5, height: 5)),
                     with: .color(placed.annotation.kind.color))
    }

    private func branchLabel(_ text: String, edge: FlowBehaviorEdge) -> some View {
        Text(text.uppercased())
            .font(.caption2.weight(.bold))
            .tracking(0.4)
            .lineLimit(1)
            .foregroundStyle(fades(edge.change) ? AnyShapeStyle(.secondary) : AnyShapeStyle(edge.change == .existing ? Color.primary : edge.change.color))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(.background, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.25), lineWidth: 0.8))
            .frame(maxWidth: BehaviorDiagramLayoutEngine.nodeWidth)
            .fixedSize()
    }

    // MARK: - Boundaries

    private func boundaryBox(_ placed: BehaviorDiagramLayout.PlacedBoundary) -> some View {
        let b = placed.boundary
        let outside = b.kind == .external || b.kind == .trust
        let tint: Color = b.kind == .trust ? .orange : (outside ? .purple : .secondary)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 14).fill(tint.opacity(0.04))
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(tint.opacity(outside ? 0.55 : 0.35), style: StrokeStyle(lineWidth: 1.2, dash: outside ? [6, 4] : []))
            HStack(spacing: 4) {
                Image(systemName: Self.glyph(b.kind)).font(.caption2)
                Text((outside ? "External · " : "") + b.label.uppercased()).font(.caption2.weight(.bold)).tracking(0.5)
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 10).padding(.vertical, 6)
        }
        .frame(width: placed.frame.width, height: placed.frame.height)
        .position(x: placed.frame.midX, y: placed.frame.midY)
        .allowsHitTesting(false)
    }

    static func glyph(_ kind: BoundaryKind) -> String {
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

    // MARK: - Legend

    private var legend: some View {
        HStack(spacing: 12) {
            if mode == .delta {
                legendSwatch(.green, "New")
                legendSwatch(.blue, "Changed")
                legendSwatch(.secondary, "Unchanged")
            }
            legendLine(dash: [6, 4], "Async")
            Label("Decision", systemImage: FlowAnnotation.Kind.decision.symbol).foregroundStyle(FlowAnnotation.Kind.decision.color)
            Label("Review question", systemImage: FlowAnnotation.Kind.question.symbol).foregroundStyle(FlowAnnotation.Kind.question.color)
        }
        .font(.caption2)
        .labelStyle(CompactLabelStyle())
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .padding(10)
    }

    private func legendSwatch(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3).strokeBorder(color, lineWidth: 1.6).frame(width: 14, height: 10)
            Text(label)
        }
    }

    private func legendLine(dash: [CGFloat], _ label: String) -> some View {
        HStack(spacing: 4) {
            Canvas { ctx, size in
                var p = Path()
                p.move(to: CGPoint(x: 0, y: size.height / 2))
                p.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                ctx.stroke(p, with: .color(.secondary), style: StrokeStyle(lineWidth: 1.6, dash: dash))
            }
            .frame(width: 20, height: 8)
            Text(label)
        }
    }
}

private struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) { configuration.icon; configuration.title.foregroundStyle(.primary) }
    }
}

// MARK: - Stage

/// One stage, shaped by what it is: a capsule trigger, a lozenge branch point, a dashed box
/// for an outside system, a double outline for a shared flow.
private struct StageBox: View {
    let node: FlowBehaviorNode
    let mode: DiagramMode
    let isSelected: Bool
    let isHovered: Bool
    let subflowTitle: String?

    private var fades: Bool { mode == .delta && node.change == .existing }
    private var emphasized: Bool { mode == .delta && node.change != .existing }

    var body: some View {
        content
            .opacity(fades ? 0.62 : 1)
            .shadow(color: .black.opacity(isHovered ? 0.16 : 0.05), radius: isHovered ? 6 : 2, y: 1)
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .help(helpText)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var content: some View {
        switch node.kind {
        case .trigger:
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill").font(.caption)
                Text(node.label.uppercased())
                    .font(.callout.weight(.bold)).tracking(0.6)
                    .multilineTextAlignment(.center).lineLimit(2)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.accentColor.opacity(0.1), in: Capsule())
            .overlay(Capsule().strokeBorder(isSelected ? Color.accentColor : Color.accentColor.opacity(0.45), lineWidth: isSelected ? 2.4 : 1.2))
            .contentShape(Capsule())
        case .decision:
            stageContent(alignment: .center)
                .background(fill, in: Lozenge())
                .overlay(Lozenge().strokeBorder(stroke, style: StrokeStyle(lineWidth: strokeWidth, dash: dash)))
                .contentShape(Lozenge())
        default:
            stageContent(alignment: .leading)
                .background(fill, in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(stroke, style: StrokeStyle(lineWidth: strokeWidth, dash: dash))
                )
                .overlay {
                    if node.kind == .subflow {
                        RoundedRectangle(cornerRadius: 7).strokeBorder(stroke.opacity(0.6), lineWidth: 0.8).padding(4)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func stageContent(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            if let caption {
                Label(caption.text, systemImage: caption.symbol)
                    .font(.caption2.weight(.bold)).tracking(0.4)
                    .foregroundStyle(caption.color)
                    .labelStyle(CompactLabelStyle())
            }
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                if node.isUncertain {
                    Text("?").font(.callout.weight(.bold)).foregroundStyle(.orange)
                        .help("Inferred, not traced in the code")
                }
                if node.kind == .outcome {
                    Image(systemName: "smallcircle.filled.circle").font(.caption).foregroundStyle(.secondary)
                }
                Text(node.label)
                    .font(.system(.callout, weight: emphasized || !fades ? .semibold : .regular))
                    .strikethrough(mode == .delta && node.change == .removed)
                    .multilineTextAlignment(alignment == .center ? .center : .leading)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                if alignment == .leading { Spacer(minLength: 0) }
                if mode == .delta, let tag = node.change.tag {
                    Text(tag).font(.system(size: 9, weight: .heavy)).tracking(0.4).foregroundStyle(node.change.color)
                }
            }
            changeDetail
        }
        .padding(.horizontal, node.kind == .decision ? 26 : 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment == .center ? .center : .topLeading)
    }

    /// What changed, inside the stage: both sides in Delta, one side in Before/After.
    @ViewBuilder
    private var changeDetail: some View {
        if node.change == .changed {
            switch mode {
            case .delta where node.before != nil || node.after != nil:
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: 2) {
                    if let before = node.before {
                        GridRow {
                            Text("BEFORE").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                            Text(before).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    if let after = node.after {
                        GridRow {
                            Text("AFTER").font(.system(size: 9, weight: .bold)).foregroundStyle(node.change.color)
                            Text(after).font(.caption.weight(.semibold)).lineLimit(1)
                        }
                    }
                }
                .padding(.top, 2)
            case .before where node.before != nil:
                Text(node.before!).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            case .after where node.after != nil:
                Text(node.after!).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            default:
                EmptyView()
            }
        }
    }

    private var caption: (text: String, symbol: String, color: Color)? {
        switch node.kind {
        case .external: return ("EXTERNAL", "globe", .purple)
        case .datastore: return ("STORAGE", "cylinder.split.1x2", .secondary)
        case .subflow: return ("SHARED FLOW" + (subflowTitle == nil ? "" : " ↗"), "arrow.triangle.merge", .secondary)
        default: return nil
        }
    }

    private var tint: Color? {
        guard mode == .delta, node.change != .existing else { return nil }
        return node.change.color
    }

    private var fill: Color {
        if let tint { return tint.opacity(isHovered ? 0.14 : 0.08) }
        switch node.kind {
        case .decision: return Color.secondary.opacity(isHovered ? 0.1 : 0.05)
        case .outcome: return Color.secondary.opacity(isHovered ? 0.12 : 0.07)
        default: return Color(nsColor: .controlBackgroundColor).opacity(isHovered ? 0.9 : 1)
        }
    }

    private var stroke: Color {
        if isSelected { return .accentColor }
        if let tint { return tint.opacity(0.85) }
        if node.kind == .external { return .purple.opacity(0.55) }
        return Color.secondary.opacity(0.4)
    }

    private var strokeWidth: CGFloat { isSelected ? 2.4 : (tint != nil ? 1.8 : 1) }

    private var dash: [CGFloat] {
        if mode == .delta && node.change == .removed { return [4, 3] }
        if node.kind == .external { return [5, 3] }
        return []
    }

    private var helpText: String {
        var parts: [String] = []
        if let detail = node.detail { parts.append(detail) }
        if node.change != .existing { parts.append(PRGraph.flowChangeLabel(node.change)) }
        if node.isUncertain { parts.append("Inferred, not traced in the code") }
        parts.append("Click to inspect · double-click to go deeper · right-click to ask")
        return parts.joined(separator: "\n")
    }
}

/// A flowchart decision shape: a box with pointed ends.
private struct Lozenge: InsettableShape {
    var inset: CGFloat = 0
    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        let point = min(18, r.height / 2)
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.midY))
        p.addLine(to: CGPoint(x: r.minX + point, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - point, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        p.addLine(to: CGPoint(x: r.maxX - point, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + point, y: r.maxY))
        p.closeSubpath()
        return p
    }
    func inset(by amount: CGFloat) -> Lozenge { var s = self; s.inset += amount; return s }
}

// MARK: - Notes

/// "◇ DECISION  Don't wait for more data" beside the connection it shapes; click to judge it.
private struct AnnotationNote: View {
    let annotation: FlowAnnotation
    var action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: annotation.kind.symbol).font(.system(size: 9, weight: .bold))
                    Text(annotation.kind.caption).font(.system(size: 9, weight: .heavy)).tracking(0.5)
                    Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold)).opacity(hovered ? 1 : 0)
                }
                .foregroundStyle(annotation.kind.color)
                Text(annotation.text)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(annotation.kind.color.opacity(hovered ? 0.14 : 0.07), in: RoundedRectangle(cornerRadius: 7))
            .overlay(alignment: .leading) {
                Rectangle().fill(annotation.kind.color).frame(width: 2).padding(.vertical, 3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovered = h } }
        .help((annotation.detail.map { $0 + "\n" } ?? "") + (annotation.kind == .decision ? "Open this decision" : "Review this question"))
    }
}
