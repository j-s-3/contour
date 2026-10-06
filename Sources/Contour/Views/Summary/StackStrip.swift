import SwiftUI

enum StackStripLogic {
    static func positionText(_ stack: PRStack) -> String { "\(stack.position) in a stack" }

    static func chipLabel(index: Int, layer: StackLayer) -> String { "\(index + 1) · \(layer.title)" }

    static func tooltip(_ layer: StackLayer) -> String {
        var line = layer.author
        if let size = layer.size {
            let files = size.changedFiles == 1 ? "1 file" : "\(size.changedFiles) files"
            line += " · +\(size.additions) \u{2212}\(size.deletions) · \(files)"
        }
        return "#\(layer.number) \(layer.title)\n\(line)"
    }

    static func statusSymbol(_ status: StackLayerStatus?) -> String? {
        switch status {
        case .cached: return "checkmark.circle.fill"
        case nil: return nil
        }
    }
}

struct StackStrip: View {
    let stack: PRStack
    let statuses: [Int: StackLayerStatus]
    let openLayer: (StackLayer) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(StackStripLogic.positionText(stack))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(stack.layers.enumerated()), id: \.element.id) { index, layer in
                        chip(index: index, layer: layer)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func chip(index: Int, layer: StackLayer) -> some View {
        let isCurrent = index == stack.currentIndex
        let label = StackStripLogic.chipLabel(index: index, layer: layer)
        return Button(action: { openLayer(layer) }) {
            HStack(spacing: 4) {
                Text(verbatim: label)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 220)
                if let symbol = StackStripLogic.statusSymbol(statuses[layer.number]) {
                    Image(systemName: symbol).font(.caption2)
                }
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isCurrent ? Color.accentColor.opacity(0.18) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isCurrent ? Color.accentColor : Color.secondary.opacity(0.4)))
        }
        .buttonStyle(.plain)
        .disabled(isCurrent)
        .help(StackStripLogic.tooltip(layer))
        .accessibilityLabel(Text(verbatim: label))
    }
}
