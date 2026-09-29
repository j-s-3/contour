import Foundation

actor CodeRefVerifier {
    private let rootDir: URL
    private let baseSha: String
    private var lineCounts: [String: Int?] = [:]

    init(rootDir: URL, baseSha: String) {
        self.rootDir = rootDir.standardizedFileURL
        self.baseSha = baseSha
    }

    init(checkout: RepoCheckout) {
        self.init(rootDir: checkout.rootDir, baseSha: checkout.baseSha)
    }

    func resolve(_ ref: CodeRef) async -> CodeRef? {
        guard let path = Self.normalized(ref.path) else { return nil }
        var sides: [RefSide] = [ref.side]
        if ref.side == .head { sides.append(.base) }
        for side in sides {
            guard let count = await lineCount(path: path, side: side),
                  ref.startLine >= 1, ref.startLine <= count
            else { continue }
            var resolved = ref
            resolved.path = path
            resolved.side = side
            resolved.endLine = min(max(ref.endLine, ref.startLine), count)
            return resolved
        }
        return nil
    }

    func resolve(_ refs: [CodeRef], into check: inout RefCheck) async -> (kept: [CodeRef], allFailed: Bool) {
        guard !refs.isEmpty else { return ([], false) }
        var kept: [CodeRef] = []
        for ref in refs {
            check.checked += 1
            if let resolved = await resolve(ref) {
                kept.append(resolved)
            } else {
                check.record(unresolved: ref)
            }
        }
        return (kept, kept.isEmpty)
    }

    func verify(_ result: StageResult) async -> (StageResult, RefCheck) {
        var check = RefCheck()
        switch result {
        case .understanding:
            return (result, check)

        case .behaviorChange(var r):
            for c in r.behaviorChanges.indices {
                for s in r.behaviorChanges[c].before.indices {
                    r.behaviorChanges[c].before[s].refs = await resolve(r.behaviorChanges[c].before[s].refs, into: &check).kept
                }
                for s in r.behaviorChanges[c].after.indices {
                    r.behaviorChanges[c].after[s].refs = await resolve(r.behaviorChanges[c].after[s].refs, into: &check).kept
                }
            }
            return (.behaviorChange(r), check)

        case .architecture(var r):
            for i in r.components.indices {
                let (kept, allFailed) = await resolve(r.components[i].refs, into: &check)
                r.components[i].refs = kept
                if allFailed { r.components[i].summary = r.components[i].summary?.demotedForUnverifiedRefs() }
            }
            return (.architecture(r), check)

        case .decisions(var decisions):
            for i in decisions.indices {
                await verify(&decisions[i], into: &check)
            }
            return (.decisions(decisions), check)

        case .flows(var r):
            for i in r.entryPoints.indices {
                r.entryPoints[i].refs = await resolve(r.entryPoints[i].refs, into: &check).kept
            }
            for f in r.flows.indices {
                for s in r.flows[f].steps.indices {
                    r.flows[f].steps[s].refs = await resolve(r.flows[f].steps[s].refs, into: &check).kept
                }
                guard r.flows[f].behavior != nil else { continue }
                for n in r.flows[f].behavior!.nodes.indices {
                    let (kept, allFailed) = await resolve(r.flows[f].behavior!.nodes[n].refs, into: &check)
                    r.flows[f].behavior!.nodes[n].refs = kept
                    if allFailed { r.flows[f].behavior!.nodes[n].demoteForUnverifiedRefs() }
                }
            }
            return (.flows(r), check)

        case .judgment(var r):
            for i in r.considerations.indices {
                let (kept, allFailed) = await resolve(r.considerations[i].refs, into: &check)
                r.considerations[i].refs = kept
                if allFailed { r.considerations[i].demoteForUnverifiedRefs() }
            }
            for i in r.questions.indices {
                r.questions[i].refs = await resolve(r.questions[i].refs, into: &check).kept
            }
            return (.judgment(r), check)
        }
    }

    private func verify(_ decision: inout DecisionNode, into check: inout RefCheck) async {
        let cited = decision.refs.count + decision.tradeoffs.reduce(0) { $0 + $1.refs.count }
        decision.refs = await resolve(decision.refs, into: &check).kept
        var kept = decision.refs.count
        for t in decision.tradeoffs.indices {
            let resolved = await resolve(decision.tradeoffs[t].refs, into: &check)
            decision.tradeoffs[t].refs = resolved.kept
            kept += resolved.kept.count
            if resolved.allFailed {
                decision.tradeoffs[t].explanation = decision.tradeoffs[t].explanation?.demotedForUnverifiedRefs()
            }
        }
        if cited > 0, kept == 0 {
            decision.confidence = .low
            decision.decision = decision.decision.demotedForUnverifiedRefs()
        }
    }

    private func lineCount(path: String, side: RefSide) async -> Int? {
        let key = "\(side.rawValue):\(path)"
        if let cached = lineCounts[key] { return cached }
        let count: Int?
        switch side {
        case .head:
            let url = rootDir.appendingPathComponent(path).standardizedFileURL
            var isDirectory: ObjCBool = false
            if url.path.hasPrefix(rootDir.path + "/"),
               FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue,
               let data = try? Data(contentsOf: url) {
                count = Self.lineCount(of: data)
            } else {
                count = nil
            }
        case .base:
            if let content = try? await Shell.run("git", ["cat-file", "blob", "\(baseSha):\(path)"], cwd: rootDir) {
                count = Self.lineCount(of: Data(content.utf8))
            } else {
                count = nil
            }
        }
        lineCounts[key] = count
        return count
    }

    static func lineCount(of data: Data) -> Int {
        guard !data.isEmpty else { return 0 }
        let newlines = data.reduce(0) { $0 + ($1 == UInt8(ascii: "\n") ? 1 : 0) }
        return data.last == UInt8(ascii: "\n") ? newlines : newlines + 1
    }

    static func normalized(_ path: String) -> String? {
        var p = path.trimmingCharacters(in: .whitespaces)
        while p.hasPrefix("./") { p.removeFirst(2) }
        while p.hasPrefix("/") { p.removeFirst() }
        guard !p.isEmpty, !p.split(separator: "/").contains("..") else { return nil }
        return p
    }
}

struct RefCheck: Codable, Hashable, Sendable {
    var checked = 0
    var unresolvedCount = 0
    var unresolved: [String] = []

    static let sampleLimit = 20

    mutating func record(unresolved ref: CodeRef) {
        unresolvedCount += 1
        if unresolved.count < Self.sampleLimit { unresolved.append(ref.display) }
    }

    static func + (lhs: RefCheck, rhs: RefCheck) -> RefCheck {
        RefCheck(checked: lhs.checked + rhs.checked, unresolvedCount: lhs.unresolvedCount + rhs.unresolvedCount,
                 unresolved: Array((lhs.unresolved + rhs.unresolved).prefix(sampleLimit)))
    }
}

extension Statement {
    func demotedForUnverifiedRefs() -> Statement {
        var s = self
        switch provenance {
        case .fact, .interpretation:
            s.provenance = .interpretation
            s.confidence = .low
        case .claim:
            break
        }
        return s
    }
}

extension FlowBehaviorNode {
    mutating func demoteForUnverifiedRefs() {
        if provenance != .claim {
            provenance = .interpretation
            confidence = .low
        }
    }
}

extension Consideration {
    mutating func demoteForUnverifiedRefs() {
        if provenance != .claim {
            provenance = .interpretation
            confidence = .low
        }
    }
}
