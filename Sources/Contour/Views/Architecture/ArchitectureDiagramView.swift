import AppKit
import SwiftUI

enum ArchEmphasis: Equatable {
    case context, changed, added, removed

    var color: Color {
        switch self {
        case .context: return .secondary
        case .changed: return .blue
        case .added: return .green
        case .removed: return .red
        }
    }

    var word: String {
        switch self {
        case .context: return "Context"
        case .changed: return "Changed"
        case .added: return "New"
        case .removed: return "Removed"
        }
    }
}

struct ArchBox: Identifiable, Equatable {
    var id: String
    var title: String
    var purpose: String?
    var emphasis: ArchEmphasis
    var changeBefore: String?
    var changeAfter: String?
    var decision: String?
    var decisionId: String?
    var moreDecisions: Int = 0
    var questions: Int = 0
    var isNeighbor = false
    var hasInside = false

    var showsChange: Bool { changeBefore != nil || changeAfter != nil || emphasis != .context }
}

struct ArchArrow: Identifiable, Equatable {
    var id: String
    var fromId: String
    var toId: String
    var label: String
    var previousLabel: String?
    var emphasis: ArchEmphasis
    var isAsync: Bool
    var questions: Int = 0
    var decisions: Int = 0
}

struct ArchContainer: Identifiable, Equatable {
    var id: String
    var label: String
    var kind: BoundaryKind
    var memberIds: [String]
    var isFocus = false

    var isExternalBoundary: Bool { [.external, .trust, .network].contains(kind) }

    var tint: Color { kind == .trust ? .orange : (isFocus ? .accentColor : .secondary) }
}

enum ArchDrawingLogic {
    static func strokeStyle(for emphasis: ArchEmphasis) -> (color: Color, width: CGFloat) {
        switch emphasis {
        case .context: return (Color.secondary.opacity(0.55), 1.4)
        case .changed: return (.blue, 2.4)
        case .added: return (.green, 2.6)
        case .removed: return (Color.red.opacity(0.8), 1.8)
        }
    }

    static func dashPattern(for arrow: ArchArrow) -> [CGFloat] {
        if arrow.emphasis == .removed { return [4, 4] }
        if arrow.isAsync { return [7, 5] }
        return []
    }

    static func arrowheadTriangle(tip: CGPoint, from prev: CGPoint, size: CGFloat) -> (
        tip: CGPoint, left: CGPoint, right: CGPoint
    ) {
        let angle = atan2(tip.y - prev.y, tip.x - prev.x)
        let back = CGPoint(x: tip.x - size * cos(angle), y: tip.y - size * sin(angle))
        let left = CGPoint(x: back.x - size * 0.5 * sin(angle), y: back.y + size * 0.5 * cos(angle))
        let right = CGPoint(x: back.x + size * 0.5 * sin(angle), y: back.y - size * 0.5 * cos(angle))
        return (tip, left, right)
    }

    static func hoverUpdate(current: ArchAnchor?, anchor: ArchAnchor, isHovering: Bool) -> ArchAnchor? {
        isHovering ? anchor : (current == anchor ? nil : current)
    }
}

struct ArchitectureDiagramView: View {
    let boxes: [ArchBox]
    let arrows: [ArchArrow]
    let containers: [ArchContainer]
    var selection: ArchAnchor?
    var onSelect: (ArchAnchor?) -> Void
    var onZoomIn: (String) -> Void
    var onOpenDecision: (String) -> Void

    @State private var hovered: ArchAnchor?

    private let minimumScale: CGFloat = 0.62

    var body: some View {
        GeometryReader { geo in
            let available = CGSize(width: max(geo.size.width - 48, 1), height: max(geo.size.height - 48, 1))
            let nodes = boxes.map { GraphLayoutEngine.NodeSpec(id: $0.id, size: ArchMetrics.size(of: $0)) }
            let edges = arrows.map {
                GraphLayoutEngine.EdgeSpec(
                    id: $0.id, fromId: $0.fromId, toId: $0.toId, labelSize: ArchMetrics.size(of: $0))
            }
            let groups = containers.map { GraphLayoutEngine.GroupSpec(id: $0.id, memberIds: $0.memberIds) }
            let (layout, fit) = GraphLayoutEngine.bestFit(
                nodes: nodes, edges: edges, groups: groups, available: available)
            let scale = max(fit, minimumScale)
            let scaled = CGSize(width: layout.size.width * scale, height: layout.size.height * scale)
            let drawing = canvas(layout)
                .frame(width: layout.size.width, height: layout.size.height)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: scaled.width, height: scaled.height, alignment: .topLeading)

            Group {
                if fit >= minimumScale {
                    drawing.frame(width: geo.size.width, height: geo.size.height)
                } else {
                    ScrollView([.horizontal, .vertical]) {
                        drawing.padding(24)
                    }
                }
            }
            .background(Color.clear.contentShape(Rectangle()).onTapGesture { onSelect(nil) })
        }
    }

    private func canvas(_ layout: ArchDiagramLayout) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear.contentShape(Rectangle()).onTapGesture { onSelect(nil) }

            ForEach(layout.boundaries) { placed in
                let base = placed.id.split(separator: "#").first.map(String.init) ?? placed.id
                if let container = containers.first(where: { $0.id == base }) {
                    containerView(container)
                        .frame(width: placed.frame.width, height: placed.frame.height)
                        .offset(x: placed.frame.minX, y: placed.frame.minY)
                }
            }

            Canvas { context, _ in
                for placed in layout.edges {
                    if let arrow = arrows.first(where: { $0.id == placed.id }) { draw(arrow, placed, in: &context) }
                }
            }
            .frame(width: layout.size.width, height: layout.size.height)
            .allowsHitTesting(false)

            ForEach(layout.nodes) { placed in
                if let box = boxes.first(where: { $0.id == placed.id }) {
                    boxView(box)
                        .frame(width: placed.frame.width, height: placed.frame.height)
                        .offset(x: placed.frame.minX, y: placed.frame.minY)
                }
            }

            ForEach(layout.edges) { placed in
                if let arrow = arrows.first(where: { $0.id == placed.id }) {
                    labelView(arrow)
                        .fixedSize()
                        .position(placed.labelCenter)
                }
            }
        }
        .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
    }

    private func boxView(_ box: ArchBox) -> some View {
        let selected = selection == .node(box.id)
        let isHovered = hovered == .node(box.id)
        let accent = box.emphasis.color
        let quiet = box.emphasis == .context
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(box.title)
                    .font(
                        .system(
                            size: box.isNeighbor ? ArchMetrics.neighborTitleSize : ArchMetrics.titleSize,
                            weight: .semibold)
                    )
                    .foregroundStyle(
                        quiet ? AnyShapeStyle(.primary.opacity(box.isNeighbor ? 0.6 : 0.85)) : AnyShapeStyle(.primary)
                    )
                    .strikethrough(box.emphasis == .removed)
                    .lineLimit(2)
                Spacer(minLength: 0)
                if box.hasInside {
                    Button {
                        onZoomIn(box.id)
                    } label: {
                        Image(systemName: "plus.magnifyingglass").font(.system(size: 11))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Look inside \(box.title)")
                }
            }
            if let purpose = box.purpose, !box.isNeighbor {
                Text(purpose)
                    .font(.system(size: ArchMetrics.bodySize))
                    .foregroundStyle(.secondary)
                    .lineLimit(ArchMetrics.purposeLines)
                    .padding(.top, ArchMetrics.titleToPurpose)
            }
            if box.showsChange, !box.isNeighbor {
                VStack(alignment: .leading, spacing: 2) {
                    if box.emphasis != .context {
                        Text(box.emphasis.word.uppercased())
                            .font(.system(size: ArchMetrics.tagSize, weight: .bold))
                            .tracking(0.6)
                            .foregroundStyle(accent)
                    }
                    changePhrase(box)
                }
                .padding(.top, ArchMetrics.sectionGap)
            }
            if let decision = box.decision, !box.isNeighbor {
                Button {
                    box.decisionId.map(onOpenDecision)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("◇").font(.system(size: ArchMetrics.markerSize, weight: .semibold))
                        Text(decision + (box.moreDecisions > 0 ? "  +\(box.moreDecisions)" : ""))
                            .font(.system(size: ArchMetrics.markerSize))
                            .lineLimit(ArchMetrics.decisionLines)
                            .multilineTextAlignment(.leading)
                    }
                    .foregroundStyle(.purple)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open this decision")
                .padding(.top, ArchMetrics.sectionGap)
            }
            if box.questions > 0, !box.isNeighbor {
                Label(
                    box.questions == 1 ? "Review question" : "\(box.questions) review questions",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.system(size: ArchMetrics.markerSize, weight: .medium))
                .foregroundStyle(.orange)
                .padding(.top, ArchMetrics.markerGap)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, ArchMetrics.padding)
        .padding(.vertical, ArchMetrics.padding - 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10).fill(.background))
        .background(RoundedRectangle(cornerRadius: 10).fill(quiet ? Color.clear : accent.opacity(0.07)))
        .overlay(
            RoundedRectangle(cornerRadius: 10).strokeBorder(
                selected
                    ? Color.accentColor
                    : (quiet ? Color.secondary.opacity(box.isNeighbor ? 0.25 : 0.4) : accent.opacity(0.9)),
                style: StrokeStyle(
                    lineWidth: selected ? 2.5 : (quiet ? 1 : 2), dash: box.emphasis == .removed ? [5, 4] : [])
            )
        )
        .shadow(color: .black.opacity(isHovered ? 0.16 : 0.05), radius: isHovered ? 6 : 2, y: 1)
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture { onSelect(.node(box.id)) }
        .onHover { hovered = ArchDrawingLogic.hoverUpdate(current: hovered, anchor: .node(box.id), isHovering: $0) }
        .reviewContextMenu(.component(box.id))
        .help(box.purpose ?? box.title)
    }

    @ViewBuilder
    private func changePhrase(_ box: ArchBox) -> some View {
        let color = box.emphasis == .context ? Color.secondary : box.emphasis.color
        switch (box.changeBefore, box.changeAfter) {
        case (let before?, let after?):
            (Text(before).foregroundStyle(.secondary).strikethrough(true, color: .secondary)
                + Text("  →  ").foregroundStyle(.tertiary)
                + Text(after).foregroundStyle(color))
                .font(.system(size: ArchMetrics.bodySize, weight: .medium))
                .lineLimit(ArchMetrics.changeLines)
        case (let only?, nil), (nil, let only?):
            Text(only).font(.system(size: ArchMetrics.bodySize, weight: .medium)).foregroundStyle(color)
                .lineLimit(ArchMetrics.changeLines)
        case (nil, nil):
            EmptyView()
        }
    }

    private func draw(_ arrow: ArchArrow, _ placed: ArchDiagramLayout.PlacedEdge, in context: inout GraphicsContext) {
        guard placed.points.count >= 2 else { return }
        let selected = selection == .edge(arrow.id)
        let (color, width) = ArchDrawingLogic.strokeStyle(for: arrow.emphasis)
        let stroke = selected ? Color.accentColor : color
        let dash = ArchDrawingLogic.dashPattern(for: arrow)

        context.stroke(
            Self.roundedPath(placed.points), with: .color(stroke),
            style: StrokeStyle(lineWidth: selected ? width + 0.8 : width, lineCap: .round, lineJoin: .round, dash: dash)
        )

        let tip = placed.points[placed.points.count - 1]
        let prev = placed.points[placed.points.count - 2]
        let size: CGFloat = arrow.emphasis == .context ? 8 : 10
        let triangle = ArchDrawingLogic.arrowheadTriangle(tip: tip, from: prev, size: size)
        var head = Path()
        head.move(to: triangle.tip)
        head.addLine(to: triangle.left)
        head.addLine(to: triangle.right)
        head.closeSubpath()
        context.fill(head, with: .color(stroke))
    }

    nonisolated static func roundedPath(_ points: [CGPoint]) -> Path {
        var path = Path()
        path.move(to: points[0])
        for i in 1..<points.count {
            if i < points.count - 1 {
                let a = points[i - 1]
                let b = points[i]
                let c = points[i + 1]
                let room = min(hypot(b.x - a.x, b.y - a.y), hypot(c.x - b.x, c.y - b.y)) / 2
                path.addArc(tangent1End: b, tangent2End: c, radius: min(8, room))
            } else {
                path.addLine(to: points[i])
            }
        }
        return path
    }

    private func labelView(_ arrow: ArchArrow) -> some View {
        let selected = selection == .edge(arrow.id)
        let color = arrow.emphasis == .context ? Color.secondary : arrow.emphasis.color
        return VStack(spacing: 1) {
            if let previous = arrow.previousLabel {
                Text(previous)
                    .font(.system(size: ArchMetrics.previousLabelSize))
                    .strikethrough(true, color: .secondary)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            HStack(spacing: 4) {
                if arrow.questions > 0 {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                if arrow.decisions > 0 {
                    Text("◇").foregroundStyle(.purple)
                }
                if arrow.isAsync {
                    Image(systemName: "clock.arrow.circlepath").foregroundStyle(.secondary)
                }
                Text(arrow.label)
                    .foregroundStyle(arrow.emphasis == .context ? AnyShapeStyle(.secondary) : AnyShapeStyle(color))
                    .strikethrough(arrow.emphasis == .removed)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: ArchMetrics.labelMaxWidth)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: ArchMetrics.labelSize, weight: arrow.emphasis == .context ? .regular : .semibold))
        }
        .padding(.horizontal, ArchMetrics.labelPadH)
        .padding(.vertical, ArchMetrics.labelPadV)
        .background(RoundedRectangle(cornerRadius: 6).fill(.background))
        .overlay(
            RoundedRectangle(cornerRadius: 6).strokeBorder(
                selected ? Color.accentColor : (arrow.emphasis == .context ? Color.clear : color.opacity(0.5)),
                lineWidth: selected ? 1.6 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .onTapGesture { onSelect(.edge(arrow.id)) }
        .reviewContextMenu(.relationship(arrow.id))
        .help(arrow.previousLabel.map { "\($0) → \(arrow.label)" } ?? arrow.label)
    }

    private func containerView(_ container: ArchContainer) -> some View {
        let tint = container.tint
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 14).fill(tint.opacity(container.isFocus ? 0.05 : 0.035))
            RoundedRectangle(cornerRadius: 14).strokeBorder(
                tint.opacity(container.isFocus ? 0.5 : 0.35),
                style: StrokeStyle(lineWidth: 1.2, dash: container.isExternalBoundary ? [6, 4] : [])
            )
            Text(container.label.uppercased())
                .font(.system(size: 10.5, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(tint.opacity(0.9))
                .padding(.horizontal, 12)
                .padding(.top, 8)
        }
        .allowsHitTesting(false)
    }
}

enum ArchMetrics {
    static let boxWidth: CGFloat = 224
    static let neighborWidth: CGFloat = 176
    static let padding: CGFloat = 13
    static let titleSize: CGFloat = 15
    static let neighborTitleSize: CGFloat = 13
    static let bodySize: CGFloat = 12
    static let tagSize: CGFloat = 9.5
    static let markerSize: CGFloat = 11.5
    static let labelSize: CGFloat = 12
    static let previousLabelSize: CGFloat = 10.5
    static let labelPadH: CGFloat = 7
    static let labelPadV: CGFloat = 4
    static let labelMaxWidth: CGFloat = 190
    static let titleToPurpose: CGFloat = 4
    static let sectionGap: CGFloat = 9
    static let markerGap: CGFloat = 7
    static let purposeLines = 3
    static let changeLines = 2
    static let decisionLines = 2

    static func size(of box: ArchBox) -> CGSize {
        let width = box.isNeighbor ? neighborWidth : boxWidth
        let inner = width - padding * 2 - (box.hasInside ? 20 : 0)
        var height = padding * 2 - 2
        height += measure(
            box.title, size: box.isNeighbor ? neighborTitleSize : titleSize, weight: .semibold, width: inner, lines: 2)
        guard !box.isNeighbor else { return CGSize(width: width, height: max(height, 44)) }
        let body = width - padding * 2
        if let purpose = box.purpose {
            height += titleToPurpose + measure(purpose, size: bodySize, width: body, lines: purposeLines)
        }
        if box.showsChange {
            height += sectionGap
            if box.emphasis != .context {
                height += measure("CHANGED", size: tagSize, weight: .bold, width: body, lines: 1) + 2
            }
            let phrase = [box.changeBefore, box.changeAfter].compactMap { $0 }.joined(separator: "  →  ")
            if !phrase.isEmpty {
                height += measure(phrase, size: bodySize, weight: .medium, width: body, lines: changeLines)
            }
        }
        if let decision = box.decision {
            height += sectionGap + measure(decision + "  +9", size: markerSize, width: body - 14, lines: decisionLines)
        }
        if box.questions > 0 {
            height += markerGap + measure("Review question", size: markerSize, weight: .medium, width: body, lines: 1)
        }
        return CGSize(width: width, height: ceil(height + 4))
    }

    static func size(of arrow: ArchArrow) -> CGSize {
        var glyphs: CGFloat = 0
        if arrow.questions > 0 { glyphs += 16 }
        if arrow.decisions > 0 { glyphs += 13 }
        if arrow.isAsync { glyphs += 16 }
        let weight: NSFont.Weight = arrow.emphasis == .context ? .regular : .semibold
        let natural = measureWidth(arrow.label, size: labelSize, weight: weight) + glyphs
        let textWidth = min(labelMaxWidth, natural)
        var height = measure(arrow.label, size: labelSize, weight: weight, width: textWidth - glyphs + 1, lines: 2)
        var width = textWidth
        if let previous = arrow.previousLabel {
            width = max(width, min(labelMaxWidth, measureWidth(previous, size: previousLabelSize)))
            height += 1 + measure(previous, size: previousLabelSize, width: labelMaxWidth, lines: 1)
        }
        return CGSize(width: ceil(width + labelPadH * 2 + 2), height: ceil(height + labelPadV * 2))
    }

    private static func font(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: weight)
    }

    static func measureWidth(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font(size, weight)]).width)
    }

    static func measure(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, width: CGFloat, lines: Int)
        -> CGFloat
    {
        let f = font(size, weight)
        let lineHeight = ceil(f.ascender - f.descender + f.leading)
        let rect = (text as NSString).boundingRect(
            with: CGSize(width: max(width, 1), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: f]
        )
        return min(ceil(rect.height), lineHeight * CGFloat(lines))
    }
}
