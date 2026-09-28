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
        let totals = DiffViewLogic.totalLineCounts(files)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(DiffViewLogic.fileCountLabel(files.count))
                    .font(.callout.weight(.semibold))
                LineCounts(additions: totals.additions, deletions: totals.deletions)
                Spacer()
                Button {
                    collapsed = DiffViewLogic.toggleAllCollapsed(files: files, collapsed: collapsed)
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
                            Text(DiffViewLogic.fileName(file.path)).lineLimit(1)
                            if let dir = DiffViewLogic.directory(file.path) {
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
        collapsed = DiffViewLogic.removingFile(file.id, from: collapsed)
        proxy.scrollTo(fileAnchor(file), anchor: .top)
    }

    /// Opens the file a reference points into and scrolls its first cited hunk into view. A
    /// reference outside every hunk (unchanged context) still lands on its file.
    private func land(on ref: CodeRef?, _ proxy: ScrollViewProxy) {
        guard let target = DiffViewLogic.landingTarget(for: ref, in: files) else { return }
        currentFile = target.file.id
        collapsed = DiffViewLogic.removingFile(target.file.id, from: collapsed)
        // After the expanded file has been laid out.
        DispatchQueue.main.async {
            // Just below the top, so the pinned file header doesn't cover the hunk's header.
            if let hunk = target.hunk { proxy.scrollTo(hunk.id, anchor: UnitPoint(x: 0, y: 0.08)) }
            else { proxy.scrollTo(fileAnchor(target.file), anchor: .top) }
        }
    }

    private func fileAnchor(_ file: DiffFile) -> String { "file-\(file.id)" }

    // MARK: - File sections

    private func fileHeader(_ file: DiffFile) -> some View {
        let isCollapsed = collapsed.contains(file.id)
        let title = DiffViewLogic.headerTitle(for: file)
        return Button {
            collapsed = DiffViewLogic.toggleCollapsed(file.id, in: collapsed)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
                Group {
                    if let old = title.old {
                        Text(old).foregroundStyle(.secondary) + Text(" → ").foregroundStyle(.secondary) + Text(title.new)
                    } else {
                        Text(title.new)
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
        if let text = DiffViewLogic.emptyStateNote(for: file) {
            note(text)
        } else {
            let gutter = DiffViewLogic.gutterWidth(file)
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
        let visible = DiffViewLogic.visibleCitations(citations)
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(hunk.header)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.purple)
                .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 8)
            ForEach(visible.shown) { citation in
                CitationBadge(citation: citation) { actions.navigate(citation.target) }
            }
            if !visible.overflow.isEmpty {
                Menu("+\(visible.overflow.count)") {
                    ForEach(visible.overflow) { c in Button(c.title) { actions.navigate(c.target) } }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .font(.caption)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 4)
        .background(Color.purple.opacity(0.06))
        .reviewContextMenu(.codeRef(DiffViewLogic.hunkRef(hunk, in: file)))
    }

    private func lineRow(_ line: DiffLine, in file: DiffFile, gutter: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(line.oldLine.map(String.init) ?? "")
                .frame(width: gutter, alignment: .trailing)
                .foregroundStyle(.tertiary)
            Text(line.newLine.map(String.init) ?? "")
                .frame(width: gutter, alignment: .trailing)
                .foregroundStyle(.tertiary)
            Text(DiffViewLogic.marker(line.kind))
                .frame(width: 22, alignment: .center)
                .foregroundStyle(DiffViewLogic.markerColor(line.kind))
            Text(line.text.isEmpty ? " " : line.text)
                .foregroundStyle(line.kind == .noNewlineMarker ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .italic(line.kind == .noNewlineMarker)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .font(.system(.footnote, design: .monospaced))
        .padding(.trailing, 12).padding(.vertical, 0.5)
        .background(DiffViewLogic.background(line, in: file, focus: focus))
    }
}

/// File/hunk navigation, line highlighting/coloring, and path formatting — pulled out of
/// `DiffView`'s instance methods (per CLAUDE.md's guidance) so it's directly testable
/// without a live view, the same way `UnifiedDiff` parsing is.
enum DiffViewLogic {
    /// Which file (and, if any, which hunk) a code reference lands on — nil for the "open
    /// nothing" case (no reference, or one outside every file in this diff).
    static func landingTarget(for ref: CodeRef?, in files: [DiffFile]) -> (file: DiffFile, hunk: DiffHunk?)? {
        guard let ref, let file = files.first(where: { $0.contains(ref) }) else { return nil }
        return (file, file.hunks.first { $0.overlaps(ref) })
    }

    /// The range a hunk shows, as a reference — head side unless the file is gone.
    static func hunkRef(_ hunk: DiffHunk, in file: DiffFile) -> CodeRef {
        if file.status == .deleted || hunk.newCount == 0 {
            return CodeRef(path: file.oldPath ?? file.path, startLine: hunk.oldStart,
                           endLine: max(hunk.oldStart, hunk.oldStart + hunk.oldCount - 1), side: .base)
        }
        return CodeRef(path: file.newPath ?? file.path, startLine: hunk.newStart,
                       endLine: max(hunk.newStart, hunk.newStart + hunk.newCount - 1))
    }

    static func marker(_ kind: DiffLine.Kind) -> String {
        switch kind {
        case .added: return "+"
        case .removed: return "−"
        case .context, .noNewlineMarker: return ""
        }
    }

    static func markerColor(_ kind: DiffLine.Kind) -> Color {
        kind == .added ? .green : kind == .removed ? .red : .secondary
    }

    static func background(_ line: DiffLine, in file: DiffFile, focus: CodeRef?) -> Color {
        if isFocused(line, in: file, focus: focus) { return Color.yellow.opacity(0.22) }
        switch line.kind {
        case .added: return Color.green.opacity(0.10)
        case .removed: return Color.red.opacity(0.10)
        case .context, .noNewlineMarker: return .clear
        }
    }

    /// Whether the line is one the focused reference cites, on the side it cites.
    static func isFocused(_ line: DiffLine, in file: DiffFile, focus: CodeRef?) -> Bool {
        guard let focus, file.contains(focus),
              let number = focus.side == .base ? line.oldLine : line.newLine else { return false }
        return number >= focus.startLine && number <= focus.endLine
    }

    /// Wide enough for the file's largest line number on either side.
    static func gutterWidth(_ file: DiffFile) -> CGFloat {
        let largest = file.hunks.map { max($0.oldStart + $0.oldCount, $0.newStart + $0.newCount) }.max() ?? 1
        return CGFloat(max(String(largest).count, 3)) * 7.5 + 12
    }

    static func fileName(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    static func directory(_ path: String) -> String? {
        guard let slash = path.lastIndex(of: "/") else { return nil }
        return String(path[..<slash])
    }

    /// "1 file" / "N files" for the file-list header.
    static func fileCountLabel(_ count: Int) -> String {
        "\(count) \(count == 1 ? "file" : "files")"
    }

    /// Additions and deletions summed across every file, for the file-list header's total.
    static func totalLineCounts(_ files: [DiffFile]) -> (additions: Int, deletions: Int) {
        (files.reduce(0) { $0 + $1.additions }, files.reduce(0) { $0 + $1.deletions })
    }

    /// The collapsed set after the "collapse all" / "expand all" toggle: collapse every file
    /// if any are expanded, otherwise expand them all.
    static func toggleAllCollapsed(files: [DiffFile], collapsed: Set<Int>) -> Set<Int> {
        collapsed.isEmpty ? Set(files.map(\.id)) : []
    }

    /// The collapsed set after one file's disclosure triangle is clicked.
    static func toggleCollapsed(_ fileID: Int, in collapsed: Set<Int>) -> Set<Int> {
        var next = collapsed
        if next.contains(fileID) { next.remove(fileID) } else { next.insert(fileID) }
        return next
    }

    /// The collapsed set with one file expanded — jumping to a file, or landing a citation on
    /// one, always opens it even if it was collapsed.
    static func removingFile(_ fileID: Int, from collapsed: Set<Int>) -> Set<Int> {
        var next = collapsed
        next.remove(fileID)
        return next
    }

    /// The note shown in place of hunks: for a binary file, or one with no hunks at all
    /// (renamed without content changes, newly added or deleted empty, or otherwise
    /// unchanged). Nil means the file has hunks to render normally.
    static func emptyStateNote(for file: DiffFile) -> String? {
        if file.isBinary { return "Binary file not shown" }
        guard file.hunks.isEmpty else { return nil }
        if file.status == .renamed { return "Renamed without content changes" }
        if file.status == .added || file.status == .deleted { return "Empty file" }
        return "No content changes"
    }

    /// The display for a hunk's file header: the rename/copy arrow when both paths are known,
    /// otherwise just the file's own path.
    static func headerTitle(for file: DiffFile) -> (old: String?, new: String) {
        if (file.status == .renamed || file.status == .copied), let old = file.oldPath, let new = file.newPath {
            return (old, new)
        }
        return (nil, file.path)
    }

    /// The citations shown inline on a hunk header versus rolled into the "+N" overflow menu.
    static func visibleCitations(_ citations: [DiffCitation], max: Int = 3) -> (shown: [DiffCitation], overflow: [DiffCitation]) {
        guard citations.count > max else { return (citations, []) }
        return (Array(citations.prefix(max)), Array(citations.dropFirst(max)))
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

extension DiffFileStatus {
    var color: Color {
        switch self {
        case .modified: return .secondary
        case .added: return .green
        case .deleted: return .red
        case .renamed, .copied: return .blue
        }
    }
}
