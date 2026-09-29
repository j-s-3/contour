import SwiftUI

extension Provenance {
    var color: Color {
        switch self {
        case .fact: return .secondary
        case .claim: return .green
        case .interpretation: return .purple
        }
    }
    var glyph: String {
        switch self {
        case .fact: return "checkmark.circle"
        case .claim: return "quote.bubble"
        case .interpretation: return "sparkles"
        }
    }
    var label: String {
        switch self {
        case .fact: return "Fact"
        case .claim: return "Author"
        case .interpretation: return "AI"
        }
    }
}

extension Confidence {
    var label: String { rawValue.capitalized }
    var color: Color {
        switch self {
        case .low: return .orange
        case .medium: return .yellow
        case .high: return .green
        }
    }
}

extension ChangeKind {
    var label: String {
        switch self {
        case .new: return "New"
        case .changed: return "Changed"
        case .touched: return "Touched"
        case .unchanged: return "Context"
        case .removed: return "Removed"
        }
    }
    var color: Color {
        switch self {
        case .new: return .green
        case .changed: return .blue
        case .touched: return .gray
        case .unchanged: return .secondary
        case .removed: return .red
        }
    }
}

struct ProvenanceBadge: View {
    let provenance: Provenance
    let confidence: Confidence?
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: provenance.glyph).font(.caption2)
            Text(provenance.label).font(.caption2.weight(.medium))
            if let confidence, provenance == .interpretation {
                Text("· \(confidence.label)").font(.caption2).foregroundStyle(confidence.color)
            }
        }
        .foregroundStyle(provenance.color)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(provenance.color.opacity(0.12), in: Capsule())
    }
}

struct ProvenanceMark: View {
    let provenance: Provenance
    let confidence: Confidence?
    var source: String? = nil

    var body: some View {
        Image(systemName: provenance.glyph)
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .help(helpText)
            .accessibilityLabel(helpText)
    }

    private var helpText: String { Self.helpText(provenance: provenance, confidence: confidence, source: source) }

    static func helpText(provenance: Provenance, confidence: Confidence?, source: String?) -> String {
        var text: String
        switch provenance {
        case .fact: text = "Observed fact"
        case .claim: text = "The author's claim"
        case .interpretation:
            text = "AI inference" + (confidence.map { " · \($0.label.lowercased()) confidence" } ?? "")
        }
        if let source, !source.isEmpty { text += " — \(source)" }
        return text
    }
}

struct StatementView: View {
    let statement: Statement
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 6) {
                ProvenanceBadge(provenance: statement.provenance, confidence: statement.confidence)
                Spacer()
            }
            Text(statement.text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            if let source = statement.source, !source.isEmpty {
                Text(source)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .italic()
            }
        }
    }
}

struct ChangeKindBadge: View {
    let kind: ChangeKind
    var body: some View {
        Text(kind.label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(kind.color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(kind.color.opacity(0.15), in: Capsule())
    }
}

struct CodeRefChip: View {
    let ref: CodeRef
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                Text(ref.display)
            }
            .font(.system(.caption, design: .monospaced))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.blue)
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
        .reviewContextMenu(.codeRef(ref))
    }
}

struct WrapChips<Content: View>: View {
    let refs: [CodeRef]
    let content: (CodeRef) -> Content
    init(_ refs: [CodeRef], @ViewBuilder content: @escaping (CodeRef) -> Content) {
        self.refs = refs
        self.content = content
    }
    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(refs) { content($0) }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return Self.wrap(sizes: sizes, spacing: spacing, maxWidth: maxWidth).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let origins = Self.wrap(sizes: sizes, spacing: spacing, maxWidth: bounds.width).origins
        for (subview, origin) in zip(subviews, origins) {
            subview.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    static func wrap(sizes: [CGSize], spacing: CGFloat, maxWidth: CGFloat) -> (size: CGSize, origins: [CGPoint]) {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var origins: [CGPoint] = []
        origins.reserveCapacity(sizes.count)
        for size in sizes {
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        let size = CGSize(width: maxWidth.isFinite ? maxWidth : x, height: y + rowHeight)
        return (size, origins)
    }
}
