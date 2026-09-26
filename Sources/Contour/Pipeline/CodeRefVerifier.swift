import Foundation

/// Mechanical CodeRef verification (§18 item 2): the grounding prompt tells the model to cite
/// only code it actually read, and this is what checks that it did.
///
/// Every stage's refs are resolved against the checkout as the stage lands — the file exists
/// and the range starts inside it, or for `base` refs, the file at `baseSha` does. A ref
/// that doesn't resolve is dropped rather than shown, since one broken `path:start-end` undoes
/// the trust every other ref builds, and `GraphLinker` would happily link decisions to flows
/// through it. A statement whose refs *all* failed keeps its text but loses its standing: a
/// `fact` becomes a low-confidence `interpretation` (see `Statement.demotedForUnverifiedRefs`).
///
/// An actor so file reads and `git show` run off the main actor, and so the per-file line
/// counts it caches are shared by every stage of one run.
actor CodeRefVerifier {
    private let rootDir: URL
    private let baseSha: String
    /// Line count per `side:path`; nil when that file doesn't exist on that side.
    private var lineCounts: [String: Int?] = [:]

    init(rootDir: URL, baseSha: String) {
        self.rootDir = rootDir.standardizedFileURL
        self.baseSha = baseSha
    }

    init(checkout: RepoCheckout) {
        self.init(rootDir: checkout.rootDir, baseSha: checkout.baseSha)
    }

    // MARK: - One ref

    /// The ref as it resolves in the checkout, or nil when it doesn't.
    ///
    /// Two lenient corrections are made rather than failing a ref that plainly points at real
    /// code: a range that runs past the end of the file is trimmed to it, and a `head` ref to a
    /// file the PR deleted is moved to `base`. `side` defaults to `head` when the model omits
    /// it, so without the second a deleted file's code could never be cited.
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

    /// Resolves a holder's refs: the ones that resolved, and whether it cited any at all but
    /// none of them resolved — the case that demotes what it says.
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

    // MARK: - A stage's slice

    /// The stage result with every ref resolved, plus the tally for the analysis details.
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

    /// A decision stands on its own refs plus its tradeoffs'. If every one of them failed, the
    /// decision is low confidence and its statement no longer reads as fact; a tradeoff whose
    /// own refs all failed has its explanation demoted likewise.
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

    // MARK: - Files

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
            // `cat-file blob` rather than `git show`, which the code viewer uses: for a
            // directory `show` prints a tree listing, which would pass as a file.
            if let content = try? await Shell.run("git", ["cat-file", "blob", "\(baseSha):\(path)"], cwd: rootDir) {
                count = Self.lineCount(of: Data(content.utf8))
            } else {
                count = nil
            }
        }
        lineCounts[key] = count
        return count
    }

    /// Lines as an editor numbers them: a trailing newline ends the last line rather than
    /// starting an empty one.
    static func lineCount(of data: Data) -> Int {
        guard !data.isEmpty else { return 0 }
        let newlines = data.reduce(0) { $0 + ($1 == UInt8(ascii: "\n") ? 1 : 0) }
        return data.last == UInt8(ascii: "\n") ? newlines : newlines + 1
    }

    /// A repo-relative path, or nil for one that can't be (empty, or climbing out of the repo).
    /// Models sometimes write `./src/x.rs` or `/src/x.rs` for the same file.
    static func normalized(_ path: String) -> String? {
        var p = path.trimmingCharacters(in: .whitespaces)
        while p.hasPrefix("./") { p.removeFirst(2) }
        while p.hasPrefix("/") { p.removeFirst() }
        guard !p.isEmpty, !p.split(separator: "/").contains("..") else { return nil }
        return p
    }
}

/// How many of one stage's refs were checked and which didn't resolve — what the analysis
/// details report as "3 of 41 references couldn't be verified".
struct RefCheck: Codable, Hashable, Sendable {
    var checked = 0
    var unresolvedCount = 0
    /// The first few unresolved refs as written (`path:start-end`), for the details popover.
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
    /// What a statement is worth once none of the code it cites could be found: an observed
    /// fact becomes a low-confidence interpretation. An author's claim stays a claim — its
    /// truth never came from the code — and interpretations are merely lowered.
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
