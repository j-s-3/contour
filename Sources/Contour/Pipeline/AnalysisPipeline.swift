import Foundation

/// One line of the progress log shown while a PR is being analyzed (§4.1, "real substeps").
struct PipelineProgressEntry: Identifiable, Sendable {
    let id = UUID()
    var stage: String
    var detail: String
}

enum PipelineStage: String, CaseIterable {
    case fetching = "Fetching PR"
    case checkingOut = "Checking out repository"
    case cacheCheck = "Checking cache"
    case ticket = "Checking issue tracker"
    case behaviorChange = "Identifying behavior change"
    case architecture = "Analyzing architecture"
    case intent = "Extracting intent"
    case eli5 = "Writing plain-language summary"
    case decisions = "Extracting decisions"
    case flows = "Tracing flows"
    case judgment = "Identifying what needs judgment"
    case done = "Done"
}

/// Orchestrates the whole pipeline from §10: GitHub fetch → local checkout → staged
/// harness calls → assembled PRGraph. Stages run sequentially because each one after the first
/// depends on component/decision IDs from an earlier stage for cross-linking — this is
/// the graph's edges being built, not just independent summarization.
actor AnalysisPipeline {
    private let repoContext = RepoContextService()
    private let cache = AnalysisCache()

    /// All three pluggable choices are resolved once per run rather than read per stage,
    /// so changing a setting mid-analysis can't produce a graph built half one way and
    /// half the other.
    private let harnessID: HarnessID
    private let trackerID: TrackerID
    private let github: GitHubService

    init(harnessID: HarnessID, trackerID: TrackerID = .github, githubAccess: GitHubAccessMode = .auto) {
        self.harnessID = harnessID
        self.trackerID = trackerID
        self.github = GitHubService(mode: githubAccess)
    }

    /// Bump this whenever a prompt or JSON schema changes shape — it's baked into the
    /// cache filename, so old cache entries from a previous schema are never mistakenly
    /// decoded against the new one; they just miss and re-run (§13).
    static let pipelineVersion = 11

    struct Result: Sendable {
        var graph: PRGraph
        var checkout: RepoCheckout
        var diff: String
        /// Whether the graph came from a previous analysis of this exact commit.
        var fromCache = false
    }

    /// - Parameter forceRefresh: bypass any cached analysis for this exact
    ///   (repo, headSha, baseSha, pipelineVersion) and re-run every analysis stage. Used by the
    ///   "Re-analyze (ignore cache)" command.
    func run(
        prURL: String,
        forceRefresh: Bool = false,
        onProgress: @escaping @Sendable (PipelineStage, PipelineProgressEntry) -> Void
    ) async throws -> Result {
        let source = try github.source()
        onProgress(.fetching, .init(stage: "Fetching PR", detail: "via \(source.describesItself)"))
        let ctx = try await source.fetchContext(prURL: prURL)

        onProgress(.checkingOut, .init(stage: "Checking out repository", detail: "\(ctx.owner)/\(ctx.repo) @ \(ctx.headSha.prefix(8))"))
        let checkout = try await repoContext.checkout(ctx)

        // Built here rather than at init because the harness needs the checkout root to
        // resolve the context file it hands the model.
        let analysis = AnalysisService(
            harness: HarnessFactory.make(harnessID, contextDirectory: checkout.rootDir)
        )

        // Written before the cache check, not after: contextual chat reads this file too, and
        // it has to be there when the analysis itself came from the cache.
        let contextFile = checkout.rootDir.appendingPathComponent(PromptBuilder.contextFileName)
        try PromptBuilder.contextFileContents(ctx).write(to: contextFile, atomically: true, encoding: .utf8)

        // A checkout is needed either way (cache hit or miss) so the code viewer has real
        // files to read. The cache only saves the harness calls, not the git operations.
        onProgress(.cacheCheck, .init(stage: "Checking cache", detail: "looking for a previous analysis of this exact commit"))
        if !forceRefresh, let cached = cache.load(
            owner: ctx.owner, repo: ctx.repo, number: ctx.number,
            headSha: ctx.headSha, baseSha: ctx.baseSha, pipelineVersion: Self.pipelineVersion
        ) {
            onProgress(.done, .init(stage: "Done", detail: "using cached analysis — \(cached.graph.decisions.count) decisions, \(cached.graph.components.count) components"))
            return Result(graph: cached.graph, checkout: checkout, diff: cached.diff, fromCache: true)
        }

        // Best-effort issue lookup: never fails the pipeline. Returns nil when there's no
        // reference, when the tracker isn't set up, or when the lookup errors for any
        // reason.
        var ticket: TicketInfo?
        let tracker = Self.tracker(trackerID, source: source, context: ctx)
        if let ref = tracker.reference(in: ctx) {
            onProgress(.ticket, .init(stage: "Checking issue tracker", detail: "found \(ref.displayKey), fetching it"))
            ticket = await tracker.fetch(ref)
            if let ticket {
                onProgress(.ticket, .init(stage: "Checking issue tracker", detail: "\(ticket.key): \(ticket.summary)"))
            } else {
                onProgress(.ticket, .init(stage: "Checking issue tracker",
                                          detail: "\(ref.displayKey) referenced, but couldn't fetch it"))
            }
        } else {
            let where_ = trackerID == .none ? "issue lookup is turned off"
                                            : "no reference found in title/body/branch/commits"
            onProgress(.ticket, .init(stage: "Checking issue tracker", detail: where_))
        }

        // Stage 0: behavior change — the hero of Summary, everything else drills down from
        // this. Runs before architecture on purpose: the reviewer's mental model starts here.
        onProgress(.behaviorChange, .init(stage: "Identifying behavior change", detail: "finding the before/after pipeline"))
        let behaviorRaw = try await analysis.runStage(
            prompt: PromptBuilder.behaviorChangePrompt(), cwd: checkout.rootDir, tier: .fast, stage: .behaviorChange
        ) { p in onProgress(.behaviorChange, .init(stage: "Identifying behavior change", detail: p.detail)) }
        let behavior = try StageDecoding.decode(StageDecoding.BehaviorChangeResult.self, stageLabel: "Identifying behavior change", from: behaviorRaw)

        // Stage 1: architecture — establishes component IDs everything else links against.
        onProgress(.architecture, .init(stage: "Analyzing architecture", detail: "mapping changed files to components"))
        let archRaw = try await analysis.runStage(
            prompt: PromptBuilder.architecturePrompt(), cwd: checkout.rootDir, tier: .fast, stage: .architecture
        ) { p in onProgress(.architecture, .init(stage: "Analyzing architecture", detail: p.detail)) }
        let arch = try StageDecoding.decode(StageDecoding.ArchitectureResult.self, stageLabel: "Analyzing architecture", from: archRaw)

        // Stage 2: intent — independent of components, can run for its own clear provenance.
        onProgress(.intent, .init(stage: "Extracting intent", detail: "reading PR description and commits"))
        let intentRaw = try await analysis.runStage(
            prompt: PromptBuilder.intentPrompt(), cwd: checkout.rootDir, tier: .fast, stage: .intent
        ) { p in onProgress(.intent, .init(stage: "Extracting intent", detail: p.detail)) }
        let intent = try StageDecoding.decode(StageDecoding.IntentResult.self, stageLabel: "Extracting intent", from: intentRaw)

        // Stage 2b: ELI5 — the two plain-language briefs, grounded in the linked issue.
        onProgress(.eli5, .init(stage: "Writing plain-language summary", detail: ticket.map { "grounding in \($0.key)" } ?? "reading PR description and code"))
        let eli5Raw = try await analysis.runStage(
            prompt: PromptBuilder.eli5Prompt(ticket: ticket), cwd: checkout.rootDir, tier: .fast, stage: .eli5
        ) { p in onProgress(.eli5, .init(stage: "Writing plain-language summary", detail: p.detail)) }
        let eli5 = try StageDecoding.decode(StageDecoding.ELI5Result.self, stageLabel: "Writing plain-language summary", from: eli5Raw)

        // Stage 3: decisions — the strong-tier stage; needs component IDs for componentIds links.
        // Each decision carries its own tradeoffs: they are what makes a decision worth
        // reviewing, not a separate artifact, so they're found in the same pass.
        onProgress(.decisions, .init(stage: "Extracting decisions", detail: "reading changed code"))
        let decisionsRaw = try await analysis.runStage(
            prompt: PromptBuilder.decisionsPrompt(components: arch.components), cwd: checkout.rootDir, tier: .strong, stage: .decisions
        ) { p in onProgress(.decisions, .init(stage: "Extracting decisions", detail: p.detail)) }
        let decisions = try StageDecoding.decode(StageDecoding.DecisionsResult.self, stageLabel: "Extracting decisions", from: decisionsRaw)

        // Stage 4: flows + entry points — needs component IDs, and decision IDs to pin
        // decisions to the point in a flow they shape.
        onProgress(.flows, .init(stage: "Tracing flows", detail: "finding entry points"))
        let flowsRaw = try await analysis.runStage(
            prompt: PromptBuilder.flowsPrompt(components: arch.components, decisions: decisions.decisions, entryHints: []), cwd: checkout.rootDir, tier: .strong, stage: .flows
        ) { p in onProgress(.flows, .init(stage: "Tracing flows", detail: p.detail)) }
        let flows = try StageDecoding.decode(StageDecoding.FlowsResult.self, stageLabel: "Tracing flows", from: flowsRaw)

        // Stage 5: judgment + questions — final synthesis pass, sees everything so far.
        var partial = PRGraph(
            pr: PRSummary(
                repo: "\(ctx.owner)/\(ctx.repo)", number: ctx.number, title: ctx.title, author: ctx.author,
                state: ctx.state, branch: ctx.headRefName, baseBranch: ctx.baseRefName, headSha: ctx.headSha,
                baseSha: ctx.baseSha, intent: intent.intent, filesChanged: ctx.changedFiles,
                additions: ctx.additions, deletions: ctx.deletions
            ),
            components: arch.components,
            decisions: decisions.decisions,
            flows: flows.flows,
            entryPoints: flows.entryPoints,
            behaviorChanges: behavior.behaviorChanges,
            architectureEdges: arch.edges,
            boundaries: arch.boundaries
        )
        partial.pr.architectureImpact = arch.architectureImpact
        partial.architecture = arch.architecture
        partial.pr.ticket = ticket
        partial.pr.problemToBeSolved = eli5.problemToBeSolved
        partial.pr.howItWasSolved = eli5.howItWasSolved

        onProgress(.judgment, .init(stage: "Identifying what needs judgment", detail: "final synthesis"))
        let graphSoFarJSON = try Self.compactJSON(partial)
        let judgmentRaw = try await analysis.runStage(
            prompt: PromptBuilder.judgmentPrompt(graphSoFar: graphSoFarJSON), cwd: checkout.rootDir, tier: .strong, stage: .judgment
        ) { p in onProgress(.judgment, .init(stage: "Identifying what needs judgment", detail: p.detail)) }
        let judgment = try StageDecoding.decode(StageDecoding.JudgmentResult.self, stageLabel: "Identifying what needs judgment", from: judgmentRaw)

        partial.pr.considerations = judgment.considerations
        partial.pr.needsJudgment = judgment.needsJudgment
        partial.pr.uncertainties = judgment.uncertainties
        partial.questions = judgment.questions
        if let cm = judgment.changeMap, !cm.isEmpty {
            partial.pr.changeMap = cm
        } else {
            partial.pr.changeMap = arch.components.map { ChangeMapEntry(name: $0.title, filesChanged: $0.filesChanged) }
        }

        cache.save(
            owner: ctx.owner, repo: ctx.repo, number: ctx.number, headSha: ctx.headSha, baseSha: ctx.baseSha,
            pipelineVersion: Self.pipelineVersion, graph: partial, diff: ctx.diff
        )

        onProgress(.done, .init(stage: "Done", detail: "\(partial.decisions.count) decisions, \(partial.components.count) components"))
        return Result(graph: partial, checkout: checkout, diff: ctx.diff)
    }

    /// The GitHub tracker needs to know which repo a bare `#123` refers to, which is only
    /// known once the PR has been fetched.
    private static func tracker(_ id: TrackerID, source: any PRSource, context: RawPRContext) -> any IssueTracker {
        switch id {
        case .github: return GitHubIssueTracker(source: source).scoped(to: context)
        case .jira: return JiraTracker()
        case .none: return NoTracker()
        }
    }

    private static func compactJSON<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
