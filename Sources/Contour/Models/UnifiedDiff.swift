import Foundation

enum DiffFileStatus: String, Hashable, Sendable {
    case modified, added, deleted, renamed, copied

    var label: String {
        switch self {
        case .modified: return "Modified"
        case .added: return "Added"
        case .deleted: return "Deleted"
        case .renamed: return "Renamed"
        case .copied: return "Copied"
        }
    }
}

struct DiffLine: Hashable, Sendable, Identifiable {
    enum Kind: Hashable, Sendable {
        case context, added, removed
        case noNewlineMarker
    }
    var id: Int
    var kind: Kind
    var text: String
    var oldLine: Int?
    var newLine: Int?
}

struct DiffHunk: Hashable, Sendable, Identifiable {
    var id: String
    var header: String
    var oldStart: Int
    var oldCount: Int
    var newStart: Int
    var newCount: Int
    var lines: [DiffLine] = []

    func overlaps(_ ref: CodeRef) -> Bool {
        let (start, count) = ref.side == .base ? (oldStart, oldCount) : (newStart, newCount)
        guard count > 0 else { return false }
        return start <= ref.endLine && ref.startLine <= start + count - 1
    }
}

struct DiffFile: Hashable, Sendable, Identifiable {
    var id: Int
    var oldPath: String?
    var newPath: String?
    var status: DiffFileStatus = .modified
    var isBinary = false
    var hunks: [DiffHunk] = []

    var path: String { newPath ?? oldPath ?? "" }
    var additions: Int { hunks.reduce(0) { $0 + $1.lines.count { $0.kind == .added } } }
    var deletions: Int { hunks.reduce(0) { $0 + $1.lines.count { $0.kind == .removed } } }

    func contains(_ ref: CodeRef) -> Bool {
        ref.path == (ref.side == .base ? oldPath : newPath)
    }
}

enum UnifiedDiff {
    static func parse(_ diff: String) -> [DiffFile] {
        var files: [DiffFile] = []
        var file: DiffFile?
        var hunk: DiffHunk?
        var oldLeft = 0
        var newLeft = 0
        var oldNo = 0
        var newNo = 0

        func closeHunk() {
            if let h = hunk { file?.hunks.append(h) }
            hunk = nil
        }
        func closeFile() {
            closeHunk()
            if let f = file { files.append(f) }
            file = nil
        }
        func startFile(oldPath: String?, newPath: String?) {
            closeFile()
            file = DiffFile(id: files.count, oldPath: oldPath, newPath: newPath)
        }

        for (position, raw) in diff.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = raw.hasSuffix("\r") ? raw.dropLast() : raw

            if hunk != nil, oldLeft > 0 || newLeft > 0 {
                let text = String(line.dropFirst())
                switch line.first {
                case "+":
                    hunk?.lines.append(DiffLine(id: position, kind: .added, text: text, newLine: newNo))
                    newNo += 1
                    newLeft -= 1
                    continue
                case "-":
                    hunk?.lines.append(DiffLine(id: position, kind: .removed, text: text, oldLine: oldNo))
                    oldNo += 1
                    oldLeft -= 1
                    continue
                case " ", nil:
                    hunk?.lines.append(
                        DiffLine(id: position, kind: .context, text: text, oldLine: oldNo, newLine: newNo))
                    oldNo += 1
                    newNo += 1
                    oldLeft -= 1
                    newLeft -= 1
                    continue
                case "\\":
                    hunk?.lines.append(DiffLine(id: position, kind: .noNewlineMarker, text: String(line)))
                    continue
                default:
                    break
                }
            }
            if line.hasPrefix("\\"), hunk != nil {
                hunk?.lines.append(DiffLine(id: position, kind: .noNewlineMarker, text: String(line)))
                continue
            }

            if line.hasPrefix("diff --git ") {
                let (a, b) = gitHeaderPaths(line.dropFirst("diff --git ".count))
                startFile(oldPath: a, newPath: b)
            } else if line.hasPrefix("@@ "), let parsed = hunkHeader(line) {
                if file == nil { startFile(oldPath: nil, newPath: nil) }
                closeHunk()
                hunk = DiffHunk(
                    id: "\(file!.id):\(file!.hunks.count)", header: String(line),
                    oldStart: parsed.oldStart, oldCount: parsed.oldCount,
                    newStart: parsed.newStart, newCount: parsed.newCount)
                oldNo = parsed.oldStart
                newNo = parsed.newStart
                oldLeft = parsed.oldCount
                newLeft = parsed.newCount
            } else if line.hasPrefix("--- ") {
                if file == nil || !(file!.hunks.isEmpty && hunk == nil) { startFile(oldPath: nil, newPath: nil) }
                let path = markerPath(line.dropFirst(4))
                file?.oldPath = path
                if path == nil { file?.status = .added }
            } else if line.hasPrefix("+++ ") {
                let path = markerPath(line.dropFirst(4))
                file?.newPath = path
                if path == nil { file?.status = .deleted }
            } else if line.hasPrefix("new file mode") {
                file?.status = .added
                file?.oldPath = nil
            } else if line.hasPrefix("deleted file mode") {
                file?.status = .deleted
                file?.newPath = nil
            } else if line.hasPrefix("rename from ") {
                file?.status = .renamed
                file?.oldPath = unquote(line.dropFirst("rename from ".count))
            } else if line.hasPrefix("rename to ") {
                file?.status = .renamed
                file?.newPath = unquote(line.dropFirst("rename to ".count))
            } else if line.hasPrefix("copy from ") {
                file?.status = .copied
                file?.oldPath = unquote(line.dropFirst("copy from ".count))
            } else if line.hasPrefix("copy to ") {
                file?.status = .copied
                file?.newPath = unquote(line.dropFirst("copy to ".count))
            } else if line.hasPrefix("Binary files ") || line.hasPrefix("GIT binary patch") {
                file?.isBinary = true
            }
        }
        closeFile()
        return files
    }

    static func hunkHeader(_ line: Substring) -> (oldStart: Int, oldCount: Int, newStart: Int, newCount: Int)? {
        let parts = line.split(separator: " ", maxSplits: 3)
        guard parts.count >= 3, parts[1].hasPrefix("-"), parts[2].hasPrefix("+"),
            let old = range(parts[1].dropFirst()), let new = range(parts[2].dropFirst())
        else { return nil }
        return (old.start, old.count, new.start, new.count)
    }

    private static func range(_ s: Substring) -> (start: Int, count: Int)? {
        let bits = s.split(separator: ",", omittingEmptySubsequences: false)
        guard let start = Int(bits[0]) else { return nil }
        if bits.count == 1 { return (start, 1) }
        guard let count = Int(bits[1]) else { return nil }
        return (start, count)
    }

    private static func gitHeaderPaths(_ rest: Substring) -> (String?, String?) {
        if rest.hasPrefix("\"") {
            let parts = rest.split(separator: "\"", omittingEmptySubsequences: true).filter { $0 != " " }
            guard parts.count == 2 else { return (nil, nil) }
            return (strip(parts[0]), strip(parts[1]))
        }
        let half = (rest.count - 1) / 2
        let a = rest.prefix(half)
        let b = rest.suffix(half)
        if rest.count % 2 == 1, a.hasPrefix("a/"), b.hasPrefix("b/"), a.dropFirst(2) == b.dropFirst(2) {
            return (String(a.dropFirst(2)), String(b.dropFirst(2)))
        }
        guard let split = rest.range(of: " b/", options: .backwards) else { return (nil, nil) }
        return (strip(rest[..<split.lowerBound]), String(rest[split.upperBound...]))
    }

    private static func markerPath(_ rest: Substring) -> String? {
        let path = unquote(rest.split(separator: "\t", maxSplits: 1).first ?? rest)
        return path == "/dev/null" ? nil : strip(Substring(path))
    }

    private static func strip(_ path: Substring) -> String {
        (path.hasPrefix("a/") || path.hasPrefix("b/")) ? String(path.dropFirst(2)) : String(path)
    }

    private static func unquote(_ s: Substring) -> String {
        s.count >= 2 && s.hasPrefix("\"") && s.hasSuffix("\"") ? String(s.dropFirst().dropLast()) : String(s)
    }
}

struct DiffCitation: Hashable, Identifiable {
    enum Kind: Hashable { case decision, flowStage }
    var kind: Kind
    var title: String
    var target: NavigationTarget
    var id: NavigationTarget { target }
}

extension PRGraph {
    func diffCitations(in files: [DiffFile]) -> [String: [DiffCitation]] {
        var citers: [(DiffCitation, [CodeRef])] = []
        for d in decisions {
            citers.append(
                (
                    DiffCitation(kind: .decision, title: d.title, target: .decisionDetail(d.id)),
                    d.refs + d.tradeoffs.flatMap(\.refs)
                ))
        }
        for flow in flows {
            for node in behavior(for: flow).nodes {
                let stepRefs = flow.steps.filter { node.stepIds.contains($0.id) }.flatMap(\.refs)
                citers.append(
                    (
                        DiffCitation(
                            kind: .flowStage, title: node.label,
                            target: .flowNodeDetail(flowId: flow.id, nodeId: node.id)),
                        node.refs + stepRefs
                    ))
            }
        }

        let byPath = Dictionary(
            grouping: files.flatMap { f in
                [f.oldPath, f.newPath].compactMap { $0 }.map { ($0, f) }
            }, by: \.0)
        var out: [String: [DiffCitation]] = [:]
        for (citation, refs) in citers {
            for ref in refs {
                for (_, file) in byPath[ref.path] ?? [] where file.contains(ref) {
                    for hunk in file.hunks where hunk.overlaps(ref) {
                        if out[hunk.id, default: []].contains(citation) { continue }
                        out[hunk.id, default: []].append(citation)
                    }
                }
            }
        }
        return out
    }
}
