import SwiftUI

/// The focused code viewer from §7: exact lines, a little surrounding context, expand to
/// whole file, diff toggle, and a guaranteed way back to wherever the reviewer came from
/// in the conceptual review. This is supporting evidence, not the primary interface.
struct CodeViewerView: View {
    let ref: CodeRef
    let checkout: RepoCheckout?
    var onBack: () -> Void

    @State private var lines: [(number: Int, text: String)] = []
    @State private var contextLines = 6
    @State private var showWholeFile = false
    @State private var wholeFile: String = ""
    @State private var errorMessage: String?

    private let repoContext = RepoContextService()
    @Environment(\.reviewActions) private var actions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if let errorMessage {
                ContentUnavailableView("Couldn't load this file", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if showWholeFile {
                ScrollView { codeText(wholeFile.components(separatedBy: "\n").enumerated().map { ($0.offset + 1, $0.element) }) }
            } else {
                ScrollView { codeText(lines) }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .task(id: ref) { await load() }
        .onAppear { actions.focus(.codeRef(ref)) }
        .onChange(of: ref) { _, new in actions.focus(.codeRef(new)) }
        .onDisappear { actions.focus(nil) }
    }

    private var header: some View {
        HStack {
            Button(action: onBack) {
                Label("Back", systemImage: "chevron.left")
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])

            Divider().frame(height: 14)

            Text(ref.display)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.medium)

            if ref.side == .base {
                Text("base").font(.caption2).foregroundStyle(.secondary)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
            }

            Spacer()

            // "Why this line?" — asks about exactly this range, carrying the concepts it
            // supports along as context.
            Button { actions.ask(.codeRef(ref)) } label: {
                Label("Ask about these lines", systemImage: "sparkles")
            }
            .buttonStyle(.plain)
            .help("Ask about this code… (⌘⇧A)")

            Button { actions.navigate(.diffLocation(ref)) } label: {
                Label("Show in diff", systemImage: "plusminus")
            }
            .buttonStyle(.plain)
            .help("See these lines in the raw diff")

            Button {
                contextLines += 8
                Task { await load() }
            } label: {
                Label("Expand context", systemImage: "arrow.up.and.down")
            }
            .buttonStyle(.plain)
            .disabled(showWholeFile)

            Button {
                showWholeFile.toggle()
                if showWholeFile { Task { await loadWholeFile() } }
            } label: {
                Label(showWholeFile ? "Show excerpt" : "Open whole file", systemImage: "doc.text")
            }
            .buttonStyle(.plain)
        }
        .padding(10)
    }

    private func codeText(_ rows: [(number: Int, text: String)]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows, id: \.number) { row in
                let isInRef = row.number >= ref.startLine && row.number <= ref.endLine
                HStack(alignment: .top, spacing: 10) {
                    Text("\(row.number)")
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .frame(width: 40, alignment: .trailing)
                    Text(row.text.isEmpty ? " " : row.text)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 8).padding(.vertical, 1)
                .background(isInRef ? Color.yellow.opacity(0.14) : Color.clear)
            }
        }
        .padding(.vertical, 8)
        .textSelection(.enabled)
        .reviewContextMenu(.codeRef(ref))
    }

    private func load() async {
        guard let checkout else { errorMessage = "No local checkout available."; return }
        do {
            let result = try await repoContext.readLines(
                in: checkout, path: ref.path, startLine: ref.startLine, endLine: ref.endLine,
                contextLines: contextLines, side: ref.side
            )
            lines = result.lines
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadWholeFile() async {
        guard let checkout else { return }
        do {
            wholeFile = try repoContext.readWholeFile(in: checkout, path: ref.path)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
