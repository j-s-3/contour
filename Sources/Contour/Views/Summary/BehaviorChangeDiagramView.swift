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

    /// How tightly the chain is set. Each side must read left to right as one sequence, so
    /// rather than wrap a row onto a second line, the diagram steps down through denser
    /// settings until both rows fit, and scrolls sideways only as a last resort.
    fileprivate enum Density {
        /// Full-size boxes, one-line labels.
        case regular
        /// Smaller type, padding and arrows; one-line labels.
        case tight
        /// As tight, with each label wrapping inside a narrow box.
        case wrapped
    }

    var body: some View {
        // Before and After step down together so their boxes stay the same size.
        ViewThatFits(in: .horizontal) {
            if !compact { diagram(.regular) }
            diagram(.tight)
            diagram(.wrapped)
            ScrollView(.horizontal) { diagram(.wrapped) }
        }
    }

    private func diagram(_ density: Density) -> some View {
        let dense = density != .regular
        return Grid(alignment: .leading, horizontalSpacing: dense ? 12 : 18, verticalSpacing: dense ? 10 : 16) {
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
                .frame(width: density == .regular ? 56 : 48, alignment: .leading)
            if stages.isEmpty {
                Text(isAfter ? "Nothing recorded." : "Didn't happen before this PR.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                // Equal-height boxes, so a wrapped label doesn't leave its neighbors floating.
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
                    .font(.system(size: density == .regular ? 13 : 11, weight: .semibold))
                    .foregroundStyle(isAfter ? .secondary : .tertiary)
                    .padding(.horizontal, density == .regular ? 10 : density == .tight ? 6 : 4)
            }
        }
    }
}

private struct StageBox: View {
    let stage: BehaviorStage
    let isAfter: Bool
    let density: BehaviorChangeDiagramView.Density
    var action: () -> Void

    @State private var hovered = false

    /// A step this PR introduces (in After) or removes (in Before).
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
            .padding(.horizontal, density == .regular ? 14 : 10)
            .padding(.vertical, density == .regular ? 10 : 6)
            .frame(maxHeight: .infinity)
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

    @ViewBuilder
    private var label: some View {
        if density == .wrapped {
            // Short labels keep their own width; longer ones break onto a second or third line.
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

    private var helpText: String { StageBoxLogic.helpText(isDelta: isDelta, isAfter: isAfter, outcome: stage.outcome) }
}

/// The delta/tint/help-text derivation CLAUDE.md calls out for this file, pulled out of
/// `StageBox`'s body so it's directly testable against plain `BehaviorStageTag`/
/// `BehaviorOutcome` fixtures rather than through the SwiftUI `body`.
enum StageBoxLogic {
    /// A step this PR introduces (in After) or removes (in Before).
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

    static func helpText(isDelta: Bool, isAfter: Bool, outcome: BehaviorOutcome?) -> String {
        var parts: [String] = []
        if isDelta { parts.append(isAfter ? "New in this PR" : "No longer happens") }
        if outcome == .failure { parts.append("Fails") }
        if outcome == .success { parts.append("Succeeds") }
        parts.append("Click to open · right-click to ask about it")
        return parts.joined(separator: " · ")
    }
}

/// Sizes its content to its natural width up to `maxWidth`, wrapping beyond that — the same
/// answer whatever width it's offered. A plain `.frame(maxWidth:)` passes an unspecified
/// proposal straight through, so inside `ViewThatFits` or a horizontal `ScrollView` the text
/// would measure as one line and then be clipped once it wraps.
private struct CappedWidth: Layout {
    let maxWidth: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let subview = subviews.first else { return .zero }
        let width = min(subview.sizeThatFits(.unspecified).width, maxWidth)
        return CGSize(width: width, height: subview.sizeThatFits(ProposedViewSize(width: width, height: nil)).height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
}
