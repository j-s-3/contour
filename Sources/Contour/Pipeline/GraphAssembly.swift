import Foundation

/// One analysis stage's decoded output — the slice of the graph it owns.
enum StageResult: Sendable {
    case behaviorChange(StageDecoding.BehaviorChangeResult)
    case understanding(StageDecoding.UnderstandingResult)
    case architecture(StageDecoding.ArchitectureResult)
    case decisions([DecisionNode])
    case flows(StageDecoding.FlowsResult)
    case judgment(StageDecoding.JudgmentResult)
}

/// How the graph is built up one slice at a time. Each stage owns a disjoint set of fields,
/// so slices can land in any order, be replaced when a stage is retried or revalidated, and
/// be cleared when one fails — without touching what any other stage produced.
extension PRGraph {

    /// The graph as soon as the PR has been fetched and before any model has run: enough to
    /// open the review window with a title, metadata and the raw diff. The PR's own title
    /// stands in for intent — it is literally the author's claim — until the understanding
    /// stage replaces it.
    static func shell(from ctx: RawPRContext) -> PRGraph {
        PRGraph(pr: PRSummary(
            repo: "\(ctx.owner)/\(ctx.repo)", number: ctx.number, title: ctx.title, author: ctx.author,
            state: ctx.state, branch: ctx.headRefName, baseBranch: ctx.baseRefName, headSha: ctx.headSha,
            baseSha: ctx.baseSha, intent: shellIntent(title: ctx.title),
            filesChanged: ctx.changedFiles, additions: ctx.additions, deletions: ctx.deletions,
            glance: ctx.glance
        ))
    }

    /// Replaces the PR metadata with a fresh fetch while keeping every analysis-owned field,
    /// for a cached or previous-revision graph shown against the PR as it is now.
    mutating func refreshMetadata(from ctx: RawPRContext) {
        let fresh = PRGraph.shell(from: ctx).pr
        pr.title = fresh.title
        pr.author = fresh.author
        pr.state = fresh.state
        pr.branch = fresh.branch
        pr.baseBranch = fresh.baseBranch
        pr.headSha = fresh.headSha
        pr.baseSha = fresh.baseSha
        pr.filesChanged = fresh.filesChanged
        pr.additions = fresh.additions
        pr.deletions = fresh.deletions
        pr.glance = fresh.glance
    }

    mutating func apply(_ result: StageResult) {
        switch result {
        case .behaviorChange(let r):
            behaviorChanges = r.behaviorChanges
        case .understanding(let r):
            pr.intent = r.intent
            pr.problemToBeSolved = r.problemToBeSolved
            pr.howItWasSolved = r.howItWasSolved
        case .architecture(let r):
            components = r.components
            architectureEdges = r.edges
            boundaries = r.boundaries
            pr.architectureImpact = r.architectureImpact
            architecture = r.architecture
        case .decisions(let d):
            decisions = d
        case .flows(let r):
            flows = r.flows
            entryPoints = r.entryPoints
        case .judgment(let r):
            pr.considerations = r.considerations
            pr.needsJudgment = r.needsJudgment
            pr.uncertainties = r.uncertainties
            questions = r.questions
            pr.changeMap = r.changeMap ?? []
        }
        if pr.changeMap.isEmpty, !components.isEmpty {
            pr.changeMap = components.map { ChangeMapEntry(name: $0.title, filesChanged: $0.filesChanged) }
        }
    }

    /// Empties the slice a stage owns — for a failed stage whose previous-revision slice
    /// must not keep standing in for a conclusion about the current code, and for saving a
    /// partial analysis without the parts that weren't produced for this revision.
    mutating func clear(_ stage: PipelineStage) {
        switch stage {
        case .behaviorChange:
            behaviorChanges = []
        case .understanding:
            pr.problemToBeSolved = nil
            pr.howItWasSolved = nil
            pr.intent = PRGraph.shellIntent(title: pr.title)
        case .architecture:
            components = []
            architectureEdges = []
            boundaries = []
            pr.architectureImpact = nil
            architecture = nil
            pr.changeMap = []
        case .decisions:
            decisions = []
        case .flows:
            flows = []
            entryPoints = []
        case .judgment:
            pr.considerations = nil
            pr.needsJudgment = []
            pr.uncertainties = []
            questions = []
        case .fetching, .checkingOut, .cacheCheck, .ticket:
            break
        }
        refChecks?[stage.rawValue] = nil
    }

    /// Records how a stage's refs fared against the checkout, replacing any earlier tally
    /// for the same stage (a retry, or this revision replacing a previous one's slice).
    mutating func record(_ check: RefCheck, for stage: PipelineStage) {
        refChecks = refChecks ?? [:]
        refChecks?[stage.rawValue] = check
    }

    static func shellIntent(title: String) -> Statement {
        Statement(text: title, provenance: .claim, confidence: nil, source: "PR title")
    }

    /// Decisions and flows are produced side by side now, so their links to architecture
    /// parts and to each other are derived once both sides exist (see `GraphLinker`).
    func linked() -> PRGraph {
        var g = self
        g.decisions = GraphLinker.linkDecisions(decisions, to: components)
        g.flows = GraphLinker.pinDecisions(g.decisions, to: flows)
        return g
    }

    /// Carries the reviewer's own marks onto a newer snapshot of the graph. The pipeline
    /// knows nothing about them, so without this every slice that lands while the reviewer
    /// is working would silently reset the decisions they had already judged.
    func carryingReviewerState(from previous: PRGraph?) -> PRGraph {
        guard let previous else { return self }
        let marks = Dictionary(previous.decisions.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var g = self
        for i in g.decisions.indices {
            guard let marked = marks[g.decisions[i].id] else { continue }
            g.decisions[i].reviewerState = marked.reviewerState
            g.decisions[i].reviewerNote = marked.reviewerNote
            g.decisions[i].reviewerPlacement = marked.reviewerPlacement
        }
        return g
    }
}
