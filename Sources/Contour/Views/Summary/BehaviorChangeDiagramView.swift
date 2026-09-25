import SwiftUI

/// The hero diagram: a before/after pipeline of short labeled boxes with arrows,
/// scannable in ~20 seconds. Native SwiftUI shapes, not prose — each box is 2-5 words,
/// color-coded by whether the stage existed before, after, or both.
struct BehaviorChangeDiagramView: View {
    let change: BehaviorChange
    var onSelectStage: (BehaviorStage) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            row(label: "BEFORE", stages: change.before)
            row(label: "AFTER", stages: change.after)
        }
    }

    private func row(label: String, stages: [BehaviorStage]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption2.weight(.bold)).foregroundStyle(.secondary).tracking(0.5)
            if stages.isEmpty {
                Text("No stages recorded.").font(.caption).foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(Array(stages.enumerated()), id: \.element.id) { index, stage in
                            stageBox(stage)
                            if index < stages.count - 1 {
                                Image(systemName: "arrow.right")
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                            }
                        }
                    }
                }
            }
        }
    }

    private func stageBox(_ stage: BehaviorStage) -> some View {
        Button { onSelectStage(stage) } label: {
            Text(stage.label)
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(tint(for: stage.tag).opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(tint(for: stage.tag).opacity(0.6)))
        }
        .buttonStyle(.plain)
    }

    private func tint(for tag: BehaviorStageTag) -> Color {
        switch tag {
        case .beforeOnly: return .secondary
        case .afterOnly: return .green
        case .both: return .blue
        }
    }
}
