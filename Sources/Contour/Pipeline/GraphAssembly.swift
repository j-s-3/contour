enum StageResult: Sendable {
    case behaviorChange(StageDecoding.BehaviorChangeResult)
    case understanding(StageDecoding.UnderstandingResult)
    case architecture(StageDecoding.ArchitectureResult)
    case decisions([DecisionNode])
    case flows(StageDecoding.FlowsResult)
    case judgment(StageDecoding.JudgmentResult)
}

extension PRGraph {
    static func shell(from ctx: RawPRContext) -> PRGraph {
        PRGraph(
            pr: PRSummary(
                repo: "\(ctx.owner)/\(ctx.repo)", number: ctx.number, title: ctx.title, author: ctx.author,
                state: ctx.state, branch: ctx.headRefName, baseBranch: ctx.baseRefName, headSha: ctx.headSha,
                baseSha: ctx.baseSha, intent: shellIntent(title: ctx.title),
                filesChanged: ctx.changedFiles, additions: ctx.additions, deletions: ctx.deletions,
                glance: ctx.glance
            ))
    }

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

    mutating func record(_ check: RefCheck, for stage: PipelineStage) {
        refChecks = refChecks ?? [:]
        refChecks?[stage.rawValue] = check
    }

    static func shellIntent(title: String) -> Statement {
        Statement(text: title, provenance: .claim, confidence: nil, source: "PR title")
    }

    func linked() -> PRGraph {
        var g = self
        g.decisions = GraphLinker.linkDecisions(decisions, to: components)
        g.flows = GraphLinker.pinDecisions(g.decisions, to: flows)
        return g
    }

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
