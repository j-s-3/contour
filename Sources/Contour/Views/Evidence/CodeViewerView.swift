import SwiftUI

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
                ScrollView { codeText(CodeViewerLogic.numberedLines(wholeFile)) }
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
                let isInRef = CodeViewerLogic.isInRef(row.number, ref: ref)
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
        switch await CodeViewerLogic.loadExcerpt(
            checkout: checkout, ref: ref, contextLines: contextLines, service: repoContext
        ) {
        case .noCheckout:
            errorMessage = "No local checkout available."
        case .loaded(let ls):
            lines = ls
            errorMessage = nil
        case .failed(let message):
            errorMessage = message
        }
    }

    private func loadWholeFile() async {
        switch await CodeViewerLogic.loadWholeFile(checkout: checkout, path: ref.path, service: repoContext) {
        case .noCheckout:
            break
        case .loaded(let content):
            wholeFile = content
            errorMessage = nil
        case .failed(let message):
            errorMessage = message
        }
    }
}

enum CodeViewerLogic {
    static func isInRef(_ lineNumber: Int, ref: CodeRef) -> Bool {
        lineNumber >= ref.startLine && lineNumber <= ref.endLine
    }

    static func numberedLines(_ text: String) -> [(number: Int, text: String)] {
        text.components(separatedBy: "\n").enumerated().map { ($0.offset + 1, $0.element) }
    }

    enum ExcerptOutcome {
        case noCheckout
        case loaded([(number: Int, text: String)])
        case failed(String)
    }

    static func loadExcerpt(
        checkout: RepoCheckout?, ref: CodeRef, contextLines: Int, service: RepoContextService
    ) async -> ExcerptOutcome {
        guard let checkout else { return .noCheckout }
        do {
            let result = try await service.readLines(
                in: checkout, path: ref.path, startLine: ref.startLine, endLine: ref.endLine,
                contextLines: contextLines, side: ref.side
            )
            return .loaded(result.lines)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    enum WholeFileOutcome {
        case noCheckout
        case loaded(String)
        case failed(String)
    }

    static func loadWholeFile(
        checkout: RepoCheckout?, path: String, service: RepoContextService
    ) async -> WholeFileOutcome {
        guard let checkout else { return .noCheckout }
        do {
            return .loaded(try await service.readWholeFile(in: checkout, path: path))
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
