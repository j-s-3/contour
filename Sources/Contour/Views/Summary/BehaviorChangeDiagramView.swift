import SwiftUI

struct BehaviorChangeDiagramView: View {
    let change: BehaviorChange
    var compact = false
    var onSelectStage: (BehaviorStage) -> Void

    enum Density {
        case regular
        case tight
        case wrapped
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            if !compact { diagram(.regular) }
            diagram(.tight)
            diagram(.wrapped)
            ScrollView(.horizontal) { diagram(.wrapped) }
        }
    }

    private func diagram(_ density: Density) -> some View {
        let spacing = BehaviorChangeDiagramMetrics.gridSpacing(for: density)
        return Grid(alignment: .leading, horizontalSpacing: spacing.horizontal, verticalSpacing: spacing.vertical) {
            row(label: "Before", stages: change.before, isAfter: false, density: density)
            row(label: "After", stages: change.after, isAfter: true, density: density)
        }
    }

    @ViewBuilder
    private func row(label: String, stages: [BehaviorStage], isAfter: Bool, density: Density) -> some View {
        GridRow(alignment: .center) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(isAfter ? .primary : .secondary)
                .frame(width: BehaviorChangeDiagramMetrics.labelWidth(for: density), alignment: .leading)
            if stages.isEmpty {
                Text(isAfter ? "Nothing recorded." : "Didn't happen before this PR.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 0) { chain(stages, isAfter: isAfter, density: density) }
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func chain(_ stages: [BehaviorStage], isAfter: Bool, density: Density) -> some View {
        ForEach(Array(stages.enumerated()), id: \.element.id) { index, stage in
            StageBox(stage: stage, isAfter: isAfter, density: density) { onSelectStage(stage) }
                .reviewContextMenu(.behaviorStage(changeId: change.id, stageId: stage.id))
            if index < stages.count - 1 {
                Image(systemName: "arrow.right")
                    .font(.system(size: BehaviorChangeDiagramMetrics.arrowFontSize(for: density), weight: .semibold))
                    .foregroundStyle(isAfter ? .secondary : .tertiary)
                    .padding(.horizontal, BehaviorChangeDiagramMetrics.arrowHorizontalPadding(for: density))
            }
        }
    }
}

enum BehaviorChangeDiagramMetrics {
    static func gridSpacing(for density: BehaviorChangeDiagramView.Density) -> (horizontal: CGFloat, vertical: CGFloat)
    {
        density == .regular ? (18, 16) : (12, 10)
    }

    static func labelWidth(for density: BehaviorChangeDiagramView.Density) -> CGFloat {
        density == .regular ? 56 : 48
    }

    static func arrowFontSize(for density: BehaviorChangeDiagramView.Density) -> CGFloat {
        density == .regular ? 13 : 11
    }

    static func arrowHorizontalPadding(for density: BehaviorChangeDiagramView.Density) -> CGFloat {
        switch density {
        case .regular: return 10
        case .tight: return 6
        case .wrapped: return 4
        }
    }

    static func boxHorizontalPadding(for density: BehaviorChangeDiagramView.Density) -> CGFloat {
        density == .regular ? 14 : 10
    }

    static func boxVerticalPadding(for density: BehaviorChangeDiagramView.Density) -> CGFloat {
        density == .regular ? 10 : 6
    }
}

private struct StageBox: View {
    let stage: BehaviorStage
    let isAfter: Bool
    let density: BehaviorChangeDiagramView.Density
    var action: () -> Void

    @State private var hovered = false

    private var isDelta: Bool { StageBoxLogic.isDelta(isAfter: isAfter, tag: stage.tag) }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let outcome = stage.outcome {
                    Image(systemName: outcome == .failure ? "xmark.octagon.fill" : "checkmark.circle.fill")
                        .foregroundStyle(outcome == .failure ? Color.red : Color.green)
                } else if isAfter && isDelta {
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                }
                label
            }
            .font(density == .regular ? .body.weight(.medium) : .callout.weight(.medium))
            .foregroundStyle(isAfter ? .primary : .secondary)
            .padding(.horizontal, BehaviorChangeDiagramMetrics.boxHorizontalPadding(for: density))
            .padding(.vertical, BehaviorChangeDiagramMetrics.boxVerticalPadding(for: density))
            .frame(maxHeight: .infinity)
            .background(fill, in: RoundedRectangle(cornerRadius: 9))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(stroke, style: StrokeStyle(lineWidth: strokeStyle.lineWidth, dash: strokeStyle.dash))
            )
            .contentShape(RoundedRectangle(cornerRadius: 9))
            .scaleEffect(hovered ? 1.02 : 1)
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovered = h } }
        .help(helpText)
    }

    @ViewBuilder
    private var label: some View {
        if density == .wrapped {
            CappedWidth(maxWidth: 88) {
                Text(stage.label).lineLimit(3)
            }
        } else {
            Text(stage.label)
                .lineLimit(1)
                .fixedSize()
        }
    }

    private var tint: Color? { StageBoxLogic.tint(outcome: stage.outcome, isAfter: isAfter, isDelta: isDelta) }

    private var fill: Color { StageBoxLogic.fill(tint: tint, hovered: hovered, isAfter: isAfter) }

    private var stroke: Color { StageBoxLogic.stroke(tint: tint, isAfter: isAfter) }

    private var strokeStyle: (lineWidth: CGFloat, dash: [CGFloat]) {
        StageBoxLogic.strokeStyle(isDelta: isDelta, hasOutcome: stage.outcome != nil, isAfter: isAfter)
    }

    private var helpText: String { StageBoxLogic.helpText(isDelta: isDelta, isAfter: isAfter, outcome: stage.outcome) }
}

enum StageBoxLogic {
    static func isDelta(isAfter: Bool, tag: BehaviorStageTag) -> Bool {
        isAfter ? tag == .afterOnly : tag == .beforeOnly
    }

    static func tint(outcome: BehaviorOutcome?, isAfter: Bool, isDelta: Bool) -> Color? {
        switch outcome {
        case .failure: return .red
        case .success: return .green
        case nil: return isAfter && isDelta ? .green : nil
        }
    }

    static func fill(tint: Color?, hovered: Bool, isAfter: Bool) -> Color {
        if let tint { return tint.opacity(hovered ? 0.16 : 0.1) }
        return Color.secondary.opacity(hovered ? 0.12 : (isAfter ? 0.07 : 0.04))
    }

    static func stroke(tint: Color?, isAfter: Bool) -> Color {
        if let tint { return tint.opacity(0.55) }
        return Color.secondary.opacity(isAfter ? 0.3 : 0.25)
    }

    static func strokeStyle(isDelta: Bool, hasOutcome: Bool, isAfter: Bool) -> (lineWidth: CGFloat, dash: [CGFloat]) {
        (lineWidth: isDelta || hasOutcome ? 1.2 : 1, dash: !isAfter && isDelta ? [4, 3] : [])
    }

    static func helpText(isDelta: Bool, isAfter: Bool, outcome: BehaviorOutcome?) -> String {
        var parts: [String] = []
        if isDelta { parts.append(isAfter ? "New in this PR" : "No longer happens") }
        if outcome == .failure { parts.append("Fails") }
        if outcome == .success { parts.append("Succeeds") }
        parts.append("Click to open · right-click to ask about it")
        return parts.joined(separator: " · ")
    }
}

private struct CappedWidth: Layout {
    let maxWidth: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let subview = subviews.first else { return .zero }
        let width = CappedWidthLogic.cap(naturalWidth: subview.sizeThatFits(.unspecified).width, at: maxWidth)
        return CGSize(width: width, height: subview.sizeThatFits(ProposedViewSize(width: width, height: nil)).height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
}

enum CappedWidthLogic {
    static func cap(naturalWidth: CGFloat, at maxWidth: CGFloat) -> CGFloat {
        min(naturalWidth, maxWidth)
    }
}
