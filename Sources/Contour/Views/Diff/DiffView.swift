import SwiftUI

/// §17 MVP — the raw diff stays available, as supporting evidence, at the bottom of the
/// progressive-disclosure stack (§4: System change → Architecture → Decisions → Flows →
/// Evidence → Raw diff). Never the primary interface.
struct DiffView: View {
    let diff: String

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(color(for: line))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(14)
            .textSelection(.enabled)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var lines: [String] { diff.components(separatedBy: "\n") }

    private func color(for line: String) -> Color {
        if line.hasPrefix("+++") || line.hasPrefix("---") { return .secondary }
        if line.hasPrefix("+") { return .green }
        if line.hasPrefix("-") { return .red }
        if line.hasPrefix("@@") { return .purple }
        if line.hasPrefix("diff --git") { return .primary }
        return .secondary
    }
}
