import SwiftUI

/// §17 MVP — the raw diff stays available, as supporting evidence, at the bottom of the
/// progressive-disclosure stack (§4: System change → Architecture → Decisions → Flows →
/// Evidence → Raw diff). Never the primary interface, but navigable: a file list to jump
/// from, files that collapse, both sides' line numbers, and hunks badged with the decisions
/// and flow stages that cite them, so the evidence links back up the ladder.
struct DiffView: View {
    let files: [DiffFile]
    let graph: PRGraph
    /// A code reference to land on: its file is expanded and its hunk scrolled to the top,
    /// with the cited lines highlighted.
    var focus: CodeRef?

    @Environment(\.reviewActions) private var actions
    @State private var collapsed: Set<Int> = []
    @State private var currentFile: Int?

    var body: some View {
        let citations = graph.diffCitations(in: files)
        ScrollViewReader { proxy in
            HStack(spacing: 0) {
                fileList(proxy)
                    .frame(width: 260)
                Divider()
                if files.isEmpty {
                    ContentUnavailableView("No changes in this diff", systemImage: "doc.text")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        // Lazy, with every hunk line a row of its own, so a diff of thousands
                        // of lines only lays out what's on screen.
                        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                            ForEach(files) { file in
                                Section {
                                    if !collapsed.contains(file.id) {
                                        fileBody(file, citations: citations)
                                    }
                                } header: {
                                    fileHeader(file)
                                }
                            }
                        }
                    }
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onAppear { land(on: focus, proxy) }
            .onChange(of: focus) { _, new in land(on: new, proxy) }
        }
    }

    // MARK: - File list

    private func fileList(_ proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("\(files.count) \(files.count == 1 ? "file" : "files")")
                    .font(.callout.weight(.semibold))
                LineCounts(additions: files.reduce(0) { $0 + $1.additions },
                           deletions: files.reduce(0) { $0 + $1.deletions })
                Spacer()
                Button {
                    collapsed = collapsed.isEmpty ? Set(files.map(\.id)) : []
                } label: {
                    Image(systemName: collapsed.isEmpty ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
                }
                .buttonStyle(.plain)
                .help(collapsed.isEmpty ? "Collapse all files" : "Expand all files")
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            Divider()
            List(files) { file in
                Button { jump(to: file, proxy) } label: {
                    HStack(spacing: 6) {
                        StatusGlyph(status: file.status)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(fileName(file.path)).lineLimit(1)
                            if let dir = directory(file.path) {
                                Text(dir).font(.caption).foregroundStyle(.secondary)
                                    .lineLimit(1).truncationMode(.head)
                            }
                        }
                        Spacer(minLength: 4)
                        if file.isBinary {
                            Text("binary").font(.caption).foregroundStyle(.secondary)
                        } else {
                            LineCounts(additions: file.additions, deletions: file.deletions)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(file.path)
                .listRowBackground(currentFile == file.id ? Color.accentColor.opacity(0.15) : Color.clear)
            }
            .listStyle(.plain)
        }
    }

    private func jump(to file: DiffFile, _ proxy: ScrollViewProxy) {
        currentFile = file.id
        collapsed.remove(file.id)
        proxy.scrollTo(fileAnchor(file), anchor: .top)
    }

    /// Opens the file a reference points into and scrolls its first cited hunk into view. A
    /// reference outside every hunk (unchanged context) still lands on its file.
    private func land(on ref: CodeRef?, _ proxy: ScrollViewProxy) {
        guard let ref, let file = files.first(where: { $0.contains(ref) }) else { return }
        currentFile = file.id
        collapsed.remove(file.id)
        let hunk = file.hunks.first { $0.overlaps(ref) }
        // After the expanded file has been laid out.
        DispatchQueue.main.async {
            // Just below the top, so the pinned file header doesn't cover the hunk's header.
            if let hunk { proxy.scrollTo(hunk.id, anchor: UnitPoint(x: 0, y: 0.08)) } else { proxy.scrollTo(fileAnchor(file), anchor: .top) }
        }
    }

    private func fileAnchor(_ file: DiffFile) -> String { "file-\(file.id)" }

    // MARK: - File sections

    private func fileHeader(_ file: DiffFile) -> some View {
        let isCollapsed = collapsed.contains(file.id)
        return Button {
            if isCollapsed { collapsed.remove(file.id) } else { collapsed.insert(file.id) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
                Group {
                    if file.status == .renamed || file.status == .copied, let old = file.oldPath, let new = file.newPath {
                        Text(old).foregroundStyle(.secondary) + Text(" → ").foregroundStyle(.secondary) + Text(new)
                    } else {
                        Text(file.path)
                    }
                }
                .font(.system(.callout, design: .monospaced).weight(.medium))
                .lineLimit(1).truncationMode(.middle)
                if file.status != .modified {
                    Text(file.status.label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(file.status.color)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(file.status.color.opacity(0.15), in: Capsule())
                }
                Spacer()
                if !file.isBinary { LineCounts(additions: file.additions, deletions: file.deletions) }
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) { Divider() }
        .help(isCollapsed ? "Expand file" : "Collapse file")
        .id(fileAnchor(file))
    }

    @ViewBuilder
    private func fileBody(_ file: DiffFile, citations: [String: [DiffCitation]]) -> some View {
        if file.isBinary {
            note("Binary file not shown")
        } else if file.hunks.isEmpty {
            note(file.status == .renamed ? "Renamed without content changes"
                 : file.status == .added || file.status == .deleted ? "Empty file" : "No content changes")
        } else {
            let gutter = gutterWidth(file)
            ForEach(file.hunks) { hunk in
                hunkHeader(hunk, in: file, citations: citations[hunk.id] ?? [])
                ForEach(hunk.lines) { line in
                    lineRow(line, in: file, gutter: gutter)
                }
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.callout).foregroundStyle(.secondary)
            .padding(.horizontal, 12).padding(.vertical, 10)
    }

    private func hunkHeader(_ hunk: DiffHunk, in file: DiffFile, citations: [DiffCitation]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(hunk.header)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.purple)
                .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 8)
            ForEach(citations.prefix(3)) { citation in
                CitationBadge(citation: citation) { actions.navigate(citation.target) }
            }
            if citations.count > 3 {
                Menu("+\(citations.count - 3)") {
                    ForEach(citations.dropFirst(3)) { c in Button(c.title) { actions.navigate(c.target) } }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .font(.caption)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 4)
        .background(Color.purple.opacity(0.06))
        .reviewContextMenu(.codeRef(hunkRef(hunk, in: file)))
    }

    /// The range a hunk shows, as a reference — head side unless the file is gone.
    private func hunkRef(_ hunk: DiffHunk, in file: DiffFile) -> CodeRef {
        if file.status == .deleted || hunk.newCount == 0 {
            return CodeRef(path: file.oldPath ?? file.path, startLine: hunk.oldStart,
                           endLine: max(hunk.oldStart, hunk.oldStart + hunk.oldCount - 1), side: .base)
        }
        return CodeRef(path: file.newPath ?? file.path, startLine: hunk.newStart,
                       endLine: max(hunk.newStart, hunk.newStart + hunk.newCount - 1))
    }

    private func lineRow(_ line: DiffLine, in file: DiffFile, gutter: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(line.oldLine.map(String.init) ?? "")
                .frame(width: gutter, alignment: .trailing)
                .foregroundStyle(.tertiary)
            Text(line.newLine.map(String.init) ?? "")
                .frame(width: gutter, alignment: .trailing)
                .foregroundStyle(.tertiary)
            Text(marker(line.kind))
                .frame(width: 22, alignment: .center)
                .foregroundStyle(markerColor(line.kind))
            Text(line.text.isEmpty ? " " : line.text)
                .foregroundStyle(line.kind == .noNewlineMarker ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .italic(line.kind == .noNewlineMarker)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .font(.system(.footnote, design: .monospaced))
        .padding(.trailing, 12).padding(.vertical, 0.5)
        .background(background(line, in: file))
    }

    private func marker(_ kind: DiffLine.Kind) -> String {
        switch kind {
        case .added: return "+"
        case .removed: return "−"
        case .context, .noNewlineMarker: return ""
        }
    }

    private func markerColor(_ kind: DiffLine.Kind) -> Color {
        kind == .added ? .green : kind == .removed ? .red : .secondary
    }

    private func background(_ line: DiffLine, in file: DiffFile) -> Color {
        if isFocused(line, in: file) { return Color.yellow.opacity(0.22) }
        switch line.kind {
        case .added: return Color.green.opacity(0.10)
        case .removed: return Color.red.opacity(0.10)
        case .context, .noNewlineMarker: return .clear
        }
    }

    /// Whether the line is one the focused reference cites, on the side it cites.
    private func isFocused(_ line: DiffLine, in file: DiffFile) -> Bool {
        guard let focus, file.contains(focus),
              let number = focus.side == .base ? line.oldLine : line.newLine else { return false }
        return number >= focus.startLine && number <= focus.endLine
    }

    /// Wide enough for the file's largest line number on either side.
    private func gutterWidth(_ file: DiffFile) -> CGFloat {
        let largest = file.hunks.map { max($0.oldStart + $0.oldCount, $0.newStart + $0.newCount) }.max() ?? 1
        return CGFloat(max(String(largest).count, 3)) * 7.5 + 12
    }

    private func fileName(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    private func directory(_ path: String) -> String? {
        guard let slash = path.lastIndex(of: "/") else { return nil }
        return String(path[..<slash])
    }
}

/// "+12 −3", green and red, the way every diff tool counts a change.
private struct LineCounts: View {
    let additions: Int
    let deletions: Int
    var body: some View {
        HStack(spacing: 4) {
            Text("+\(additions)").foregroundStyle(.green)
            Text("−\(deletions)").foregroundStyle(.red)
        }
        .font(.caption.monospacedDigit())
    }
}

private struct StatusGlyph: View {
    let status: DiffFileStatus
    var body: some View {
        Image(systemName: symbol)
            .foregroundStyle(status.color)
            .frame(width: 14)
            .help(status.label)
    }
    private var symbol: String {
        switch status {
        case .modified: return "pencil.circle"
        case .added: return "plus.circle"
        case .deleted: return "minus.circle"
        case .renamed: return "arrow.right.circle"
        case .copied: return "doc.on.doc"
        }
    }
}

/// A decision or flow stage that cites this hunk — one click back up to the concept.
private struct CitationBadge: View {
    let citation: DiffCitation
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: citation.kind == .decision ? "checklist" : "arrow.triangle.branch")
                Text(citation.title).lineLimit(1)
            }
            .font(.caption)
            .frame(maxWidth: 220)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.blue)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(Color.blue.opacity(0.08), in: Capsule())
        .help((citation.kind == .decision ? "Decision: " : "Flow stage: ") + citation.title)
    }
}

private extension DiffFileStatus {
    var color: Color {
        switch self {
        case .modified: return .secondary
        case .added: return .green
        case .deleted: return .red
        case .renamed, .copied: return .blue
        }
    }
}
