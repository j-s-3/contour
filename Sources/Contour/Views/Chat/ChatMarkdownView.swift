import SwiftUI

/// Renders an answer's markdown natively: paragraphs, bullet and numbered lists, headings,
/// and fenced code blocks, with inline emphasis/code/links via `AttributedString`. Inline
/// spans are linkified first so code citations and review-model references are clickable
/// in place. A deliberately small subset — answers are a few paragraphs, not documents.
struct ChatMarkdownView: View {
    let text: String
    /// Rewrites citations in one inline span into markdown links (see `ChatLinks`).
    var linkify: (String) -> String = { $0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(Self.blocks(text).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .textSelection(.enabled)
    }

    enum Block: Equatable {
        case paragraph(String)
        case heading(String)
        case bullet(String)
        case numbered(String, String)
        case code(String)
    }

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block {
        case .paragraph(let s):
            inline(s)
        case .heading(let s):
            inline(s).font(.callout.weight(.semibold)).padding(.top, 2)
        case .bullet(let s):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("•").foregroundStyle(.secondary)
                inline(s)
            }
        case .numbered(let n, let s):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(n).foregroundStyle(.secondary).monospacedDigit()
                inline(s)
            }
        case .code(let s):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(s)
                    .font(.system(.caption, design: .monospaced))
                    .padding(10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.7), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.separator.opacity(0.6)))
        }
    }

    private func inline(_ s: String) -> some View {
        let linked = linkify(s)
        let attributed = (try? AttributedString(
            markdown: linked,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(s)
        return Text(attributed)
            .font(.callout)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Line-oriented block split. Consecutive plain lines join into one paragraph.
    nonisolated static func blocks(_ text: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        var code: [String]?

        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))) }
            paragraph = []
        }

        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if let open = code {
                    blocks.append(.code(open.joined(separator: "\n")))
                    code = nil
                } else {
                    flush()
                    code = []
                }
                continue
            }
            if code != nil { code?.append(raw); continue }

            if line.isEmpty {
                flush()
            } else if line.hasPrefix("#") {
                flush()
                blocks.append(.heading(line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") {
                flush()
                blocks.append(.bullet(String(line.dropFirst(2))))
            } else if let dot = line.firstIndex(of: "."), line[..<dot].allSatisfy(\.isNumber), !line[..<dot].isEmpty,
                      line[line.index(after: dot)...].hasPrefix(" ") {
                flush()
                blocks.append(.numbered(String(line[...dot]), line[line.index(after: dot)...].trimmingCharacters(in: .whitespaces)))
            } else {
                paragraph.append(line)
            }
        }
        // An unterminated fence mid-stream still renders as code rather than vanishing.
        if let open = code { blocks.append(.code(open.joined(separator: "\n"))) }
        flush()
        return blocks
    }
}
