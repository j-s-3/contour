import SwiftUI

/// The provenance spine rendered as UI (§15). These three colors/glyphs recur everywhere
/// a Statement is shown — fact, claim, or interpretation must always be visually distinct.
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

/// A small chip showing provenance (and confidence, for interpretations). Tapping shows
/// the source in a popover — "The implementation suggests…" is never presented bare.
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

/// Provenance as quiet metadata: a single tertiary glyph whose tooltip says whether a line
/// is the author's claim, an observed fact, or an AI inference (and how confident). Used
/// where the statement itself should dominate — the Overview — while keeping §15's
/// distinction one hover away rather than dropping it.
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

    private var helpText: String {
        var text: String
        switch provenance {
        case .fact: text = "Observed fact"
        case .claim: text = "The author's claim"
        case .interpretation: text = "AI inference" + (confidence.map { " · \($0.label.lowercased()) confidence" } ?? "")
        }
        if let source, !source.isEmpty { text += " — \(source)" }
        return text
    }
}

/// Renders one Statement with its provenance badge and, if present, its source pointer —
/// the "fact vs claim vs interpretation" distinction made visible at the point of use.
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

/// A tappable code evidence chip — "src/foo/OrderService.java:142-167" — that opens the
/// focused code viewer without losing the reviewer's place (§7).
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

/// A simple flow layout for code-ref chips so a component with many refs wraps instead
/// of forcing horizontal scroll.
struct WrapChips<Content: View>: View {
    let refs: [CodeRef]
    let content: (CodeRef) -> Content
    init(_ refs: [CodeRef], @ViewBuilder content: @escaping (CodeRef) -> Content) {
        self.refs = refs; self.content = content
    }
    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(refs) { content($0) }
        }
    }
}

/// Minimal SwiftUI Layout implementation for left-to-right wrapping chip rows.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth.isFinite ? maxWidth : x, height: y + rowHeight)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX, y: CGFloat = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX; y += rowHeight + spacing; rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
