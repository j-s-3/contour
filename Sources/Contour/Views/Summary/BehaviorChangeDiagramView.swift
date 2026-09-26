import SwiftUI

/// The Overview's hero: a before/after pipeline of short labeled boxes, readable without
/// reading a sentence. Before is quiet (it's the past); After carries the emphasis. Color is
/// restrained and always means the same thing — green for a step this PR introduces, a
/// dashed outline for a step that no longer happens, red/green glyphs only on an outcome.
///
/// Each box is a review object: click to drill into its component or flow, right-click for
/// "Ask about this…" and friends.
struct BehaviorChangeDiagramView: View {
    let change: BehaviorChange
    /// Smaller type and spacing, for a secondary behavior change expanded inline.
    var compact = false
    var onSelectStage: (BehaviorStage) -> Void

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: compact ? 12 : 18, verticalSpacing: compact ? 10 : 16) {
            row(label: "Before", stages: change.before, isAfter: false)
            row(label: "After", stages: change.after, isAfter: true)
        }
    }

    @ViewBuilder
    private func row(label: String, stages: [BehaviorStage], isAfter: Bool) -> some View {
        GridRow(alignment: .center) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(isAfter ? .primary : .secondary)
                .frame(width: compact ? 48 : 56, alignment: .leading)
            if stages.isEmpty {
                Text(isAfter ? "Nothing recorded." : "Didn't happen before this PR.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                // One row when it fits (it usually does, at 3-6 short stages); otherwise wrap,
                // keeping each arrow attached to the box it leads out of.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 0) { chain(stages, isAfter: isAfter) }
                    FlowLayout(spacing: 8) { chain(stages, isAfter: isAfter) }
                }
            }
        }
    }

    @ViewBuilder
    private func chain(_ stages: [BehaviorStage], isAfter: Bool) -> some View {
        ForEach(Array(stages.enumerated()), id: \.element.id) { index, stage in
            HStack(spacing: 0) {
                StageBox(stage: stage, isAfter: isAfter, compact: compact) { onSelectStage(stage) }
                    .reviewContextMenu(.behaviorStage(changeId: change.id, stageId: stage.id))
                if index < stages.count - 1 {
                    Image(systemName: "arrow.right")
                        .font(.system(size: compact ? 11 : 13, weight: .semibold))
                        .foregroundStyle(isAfter ? .secondary : .tertiary)
                        .padding(.horizontal, compact ? 7 : 10)
                }
            }
        }
    }
}

private struct StageBox: View {
    let stage: BehaviorStage
    let isAfter: Bool
    let compact: Bool
    var action: () -> Void

    @State private var hovered = false

    /// A step this PR introduces (in After) or removes (in Before).
    private var isDelta: Bool { isAfter ? stage.tag == .afterOnly : stage.tag == .beforeOnly }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let outcome = stage.outcome {
                    Image(systemName: outcome == .failure ? "xmark.octagon.fill" : "checkmark.circle.fill")
                        .foregroundStyle(outcome == .failure ? Color.red : Color.green)
                } else if isAfter && isDelta {
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                }
                Text(stage.label)
                    .lineLimit(1)
                    .fixedSize()
            }
            .font(compact ? .callout.weight(.medium) : .body.weight(.medium))
            .foregroundStyle(isAfter ? .primary : .secondary)
            .padding(.horizontal, compact ? 10 : 14)
            .padding(.vertical, compact ? 6 : 10)
            .background(fill, in: RoundedRectangle(cornerRadius: 9))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(stroke, style: StrokeStyle(lineWidth: isDelta || stage.outcome != nil ? 1.2 : 1,
                                                             dash: !isAfter && isDelta ? [4, 3] : []))
            )
            .contentShape(RoundedRectangle(cornerRadius: 9))
            .scaleEffect(hovered ? 1.02 : 1)
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovered = h } }
        .help(helpText)
    }

    private var tint: Color? {
        switch stage.outcome {
        case .failure: return .red
        case .success: return .green
        case nil: return isAfter && isDelta ? .green : nil
        }
    }

    private var fill: Color {
        if let tint { return tint.opacity(hovered ? 0.16 : 0.1) }
        return Color.secondary.opacity(hovered ? 0.12 : (isAfter ? 0.07 : 0.04))
    }

    private var stroke: Color {
        if let tint { return tint.opacity(0.55) }
        return Color.secondary.opacity(isAfter ? 0.3 : 0.25)
    }

    private var helpText: String {
        var parts: [String] = []
        if isDelta { parts.append(isAfter ? "New in this PR" : "No longer happens") }
        if stage.outcome == .failure { parts.append("Fails") }
        if stage.outcome == .success { parts.append("Succeeds") }
        parts.append("Click to open · right-click to ask about it")
        return parts.joined(separator: " · ")
    }
}
