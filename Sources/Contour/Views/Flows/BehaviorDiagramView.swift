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

enum BehaviorDiagramLogic {
    static func fades(mode: DiagramMode, change: FlowChange) -> Bool {
        mode == .delta && change == .existing
    }

    static func emphasized(mode: DiagramMode, change: FlowChange) -> Bool {
        mode == .delta && change != .existing
    }

    static func tint(mode: DiagramMode, change: FlowChange) -> Color? {
        guard mode == .delta, change != .existing else { return nil }
        return change.color
    }

    static func dash(mode: DiagramMode, change: FlowChange, kind: FlowNodeKind) -> [CGFloat] {
        if mode == .delta && change == .removed { return [4, 3] }
        if kind == .external { return [5, 3] }
        return []
    }

    static func stageFill(mode: DiagramMode, change: FlowChange, kind: FlowNodeKind, isHovered: Bool) -> Color {
        if let tint = tint(mode: mode, change: change) { return tint.opacity(isHovered ? 0.14 : 0.08) }
        switch kind {
        case .decision: return Color.secondary.opacity(isHovered ? 0.1 : 0.05)
        case .outcome: return Color.secondary.opacity(isHovered ? 0.12 : 0.07)
        default: return Color(nsColor: .controlBackgroundColor).opacity(isHovered ? 0.9 : 1)
        }
    }

    static func stageStroke(mode: DiagramMode, change: FlowChange, kind: FlowNodeKind, isSelected: Bool) -> Color {
        if isSelected { return .accentColor }
        if let tint = tint(mode: mode, change: change) { return tint.opacity(0.85) }
        if kind == .external { return .purple.opacity(0.55) }
        return Color.secondary.opacity(0.4)
    }

    static func stageStrokeWidth(isSelected: Bool, isTinted: Bool) -> CGFloat {
        isSelected ? 2.4 : (isTinted ? 1.8 : 1)
    }

    static func stageCaption(kind: FlowNodeKind, subflowTitle: String?) -> (text: String, symbol: String, color: Color)? {
        switch kind {
        case .external: return ("EXTERNAL", "globe", .purple)
        case .datastore: return ("STORAGE", "cylinder.split.1x2", .secondary)
        case .subflow: return ("SHARED FLOW" + (subflowTitle == nil ? "" : " ↗"), "arrow.triangle.merge", .secondary)
        default: return nil
        }
    }

    static func stageHelpText(detail: String?, change: FlowChange, isUncertain: Bool) -> String {
        var parts: [String] = []
        if let detail { parts.append(detail) }
        if change != .existing { parts.append(PRGraph.flowChangeLabel(change)) }
        if isUncertain { parts.append("Inferred, not traced in the code") }
        parts.append("Click to inspect · double-click to go deeper · right-click to ask")
        return parts.joined(separator: "\n")
    }

    enum ChangeDetailContent: Equatable {
        case beforeAndAfter(before: String?, after: String?)
        case beforeOnly(String)
        case afterOnly(String)
        case none
    }

    static func changeDetailContent(mode: DiagramMode, change: FlowChange, before: String?, after: String?) -> ChangeDetailContent {
        guard change == .changed else { return .none }
        switch mode {
        case .delta where before != nil || after != nil: return .beforeAndAfter(before: before, after: after)
        case .before where before != nil: return .beforeOnly(before!)
        case .after where after != nil: return .afterOnly(after!)
        default: return .none
        }
    }

    static func hoverUpdate(current: String?, id: String, isHovering: Bool) -> String? {
        isHovering ? id : (current == id ? nil : current)
    }

    static func boundaryStyle(kind: BoundaryKind) -> (outside: Bool, tint: Color) {
        let outside = kind == .external || kind == .trust
        return (outside, kind == .trust ? .orange : (outside ? .purple : .secondary))
    }

    static func boundaryLabelText(kind: BoundaryKind, label: String) -> String {
        (boundaryStyle(kind: kind).outside ? "External · " : "") + label.uppercased()
    }

    static func edgeOpacity(mode: DiagramMode, change: FlowChange) -> Double {
        fades(mode: mode, change: change) ? 0.35 : (change == .existing ? 0.6 : 0.95)
    }

    static func edgeDash(flow: EdgeFlow, change: FlowChange) -> [CGFloat] {
        var dash: [CGFloat] = []
        if flow == .async { dash = [6, 4] }
        if change == .removed { dash = [3, 3] }
        return dash
    }

    static func edgeWidth(change: FlowChange) -> CGFloat { change == .existing ? 1.3 : 2.2 }

    static func edgeArrowSize(change: FlowChange) -> CGFloat { change == .existing ? 8 : 10 }

    static func arrowHeadWings(from: CGPoint, tip: CGPoint, size: CGFloat) -> (left: CGPoint, right: CGPoint) {
        let angle = atan2(tip.y - from.y, tip.x - from.x)
        let back = CGPoint(x: tip.x - size * cos(angle), y: tip.y - size * sin(angle))
        return (CGPoint(x: back.x - size * 0.5 * sin(angle), y: back.y + size * 0.5 * cos(angle)),
                CGPoint(x: back.x + size * 0.5 * sin(angle), y: back.y - size * 0.5 * cos(angle)))
    }
}

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
        VStack(spacing: 0) {
            canvas
            Divider()
            legend
        }
    }

    private var canvas: some View {
        GeometryReader { geo in
            let layout = BehaviorDiagramLayoutEngine.layout(behavior, mode: mode, annotations: annotations,
                                                            availableWidth: geo.size.width)
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
                            .onHover { hoveredId = BehaviorDiagramLogic.hoverUpdate(current: hoveredId, id: placed.id, isHovering: $0) }
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
                .frame(minWidth: geo.size.width, minHeight: geo.size.height, alignment: .top)
            }
        }
    }

    private func fades(_ change: FlowChange) -> Bool { BehaviorDiagramLogic.fades(mode: mode, change: change) }

    private func drawEdge(_ placed: BehaviorDiagramLayout.PlacedEdge, in context: inout GraphicsContext) {
        let e = placed.edge
        guard placed.points.count >= 2 else { return }
        let color = e.change.color.opacity(BehaviorDiagramLogic.edgeOpacity(mode: mode, change: e.change))
        var path = Path()
        path.addLines(placed.points)
        let dash = BehaviorDiagramLogic.edgeDash(flow: e.flow, change: e.change)
        let width = BehaviorDiagramLogic.edgeWidth(change: e.change)
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round, dash: dash))

        let tip = placed.points[placed.points.count - 1]
        let from = placed.points[placed.points.count - 2]
        let size = BehaviorDiagramLogic.edgeArrowSize(change: e.change)
        let wings = BehaviorDiagramLogic.arrowHeadWings(from: from, tip: tip, size: size)
        var arrow = Path()
        arrow.move(to: tip)
        arrow.addLine(to: wings.left)
        arrow.addLine(to: wings.right)
        arrow.closeSubpath()
        context.fill(arrow, with: .color(color))
    }

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

    private func boundaryBox(_ placed: BehaviorDiagramLayout.PlacedBoundary) -> some View {
        let b = placed.boundary
        let (outside, tint) = BehaviorDiagramLogic.boundaryStyle(kind: b.kind)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 14).fill(tint.opacity(0.04))
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(tint.opacity(outside ? 0.55 : 0.35), style: StrokeStyle(lineWidth: 1.2, dash: outside ? [6, 4] : []))
            HStack(spacing: 4) {
                Image(systemName: Self.glyph(b.kind)).font(.caption2)
                Text(BehaviorDiagramLogic.boundaryLabelText(kind: b.kind, label: b.label)).font(.caption2.weight(.bold)).tracking(0.5)
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 10).padding(.vertical, 6)
        }
        .frame(width: placed.frame.width, height: placed.frame.height)
        .position(x: placed.frame.midX, y: placed.frame.midY)
        .allowsHitTesting(false)
    }

    nonisolated static func glyph(_ kind: BoundaryKind) -> String {
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
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
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

private struct StageBox: View {
    let node: FlowBehaviorNode
    let mode: DiagramMode
    let isSelected: Bool
    let isHovered: Bool
    let subflowTitle: String?

    private var fades: Bool { BehaviorDiagramLogic.fades(mode: mode, change: node.change) }
    private var emphasized: Bool { BehaviorDiagramLogic.emphasized(mode: mode, change: node.change) }

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

    @ViewBuilder
    private var changeDetail: some View {
        switch BehaviorDiagramLogic.changeDetailContent(mode: mode, change: node.change, before: node.before, after: node.after) {
        case let .beforeAndAfter(before, after):
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: 2) {
                if let before {
                    GridRow {
                        Text("BEFORE").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                        Text(before).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                if let after {
                    GridRow {
                        Text("AFTER").font(.system(size: 9, weight: .bold)).foregroundStyle(node.change.color)
                        Text(after).font(.caption.weight(.semibold)).lineLimit(1)
                    }
                }
            }
            .padding(.top, 2)
        case let .beforeOnly(before):
            Text(before).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        case let .afterOnly(after):
            Text(after).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        case .none:
            EmptyView()
        }
    }

    private var caption: (text: String, symbol: String, color: Color)? {
        BehaviorDiagramLogic.stageCaption(kind: node.kind, subflowTitle: subflowTitle)
    }

    private var tint: Color? { BehaviorDiagramLogic.tint(mode: mode, change: node.change) }

    private var fill: Color {
        BehaviorDiagramLogic.stageFill(mode: mode, change: node.change, kind: node.kind, isHovered: isHovered)
    }

    private var stroke: Color {
        BehaviorDiagramLogic.stageStroke(mode: mode, change: node.change, kind: node.kind, isSelected: isSelected)
    }

    private var strokeWidth: CGFloat { BehaviorDiagramLogic.stageStrokeWidth(isSelected: isSelected, isTinted: tint != nil) }

    private var dash: [CGFloat] { BehaviorDiagramLogic.dash(mode: mode, change: node.change, kind: node.kind) }

    private var helpText: String {
        BehaviorDiagramLogic.stageHelpText(detail: node.detail, change: node.change, isUncertain: node.isUncertain)
    }
}

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
